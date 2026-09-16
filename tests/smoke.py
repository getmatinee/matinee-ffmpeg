#!/usr/bin/env python3
# Copyright (C) 2023-2026 Swissmakers GmbH
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee

"""Exercise the Matinee CLI contract. The --gpu run also needs a working NVIDIA GPU."""

import argparse
import json
import pathlib
import subprocess
import tempfile
import time


def run(*args, timeout=60):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=timeout, text=True)
    if result.returncode:
        raise AssertionError(f"{args}\n{result.stderr}")
    return result.stdout


def until(predicate, process, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        if process.poll() is not None:
            raise AssertionError(f"FFmpeg exited early: {process.returncode}")
        time.sleep(0.05)
    raise AssertionError("FFmpeg did not make expected progress")


def pause_resume(ffmpeg, directory, terminate=False):
    output = directory / ("signal.raw" if terminate else "keyboard.raw")
    log = output.with_suffix(".log")
    with log.open("wb") as stderr:
        process = subprocess.Popen([
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-re",
            "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=25",
            "-threads", "1", "-c:v", "rawvideo", "-flush_packets", "1",
            "-f", "rawvideo", str(output),
        ], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=stderr)
        try:
            def size():
                return output.stat().st_size if output.exists() else 0

            def send(key):
                process.stdin.write(key)
                process.stdin.flush()

            until(lambda: size() >= 5 * 160 * 96 * 3 // 2, process)
            send(b"p")
            until(lambda: b"Transcoding is paused" in log.read_bytes(), process)
            # Frames already in the pipeline still drain after a pause
            time.sleep(0.8)
            paused_size = size()
            time.sleep(0.6)
            assert size() == paused_size, "output continued while paused"
            # A repeated pause must be idempotent
            send(b"p")
            time.sleep(0.6)
            assert size() == paused_size, "repeated pause resumed input"
            send(b"u")
            until(lambda: size() > paused_size, process)
            send(b"p")
            time.sleep(0.7)
            if terminate:
                process.terminate()
            else:
                send(b"q")
            status = process.wait(timeout=5)
            assert status == (255 if terminate else 0), log.read_text()
        except Exception as error:
            raise AssertionError(f"{error}\n{log.read_text()}") from error
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdin.close()
    print(f"PASS pause/resume and {'SIGTERM' if terminate else 'q'} while paused")


def hls(ffmpeg, ffprobe, directory):
    playlist = directory / "stream.m3u8"
    run(ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=25",
        "-f", "lavfi", "-i", "sine=sample_rate=48000", "-t", "3",
        "-threads", "1", "-c:v", "libx264", "-preset", "ultrafast",
        "-g", "25", "-sc_threshold", "0", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-f", "hls", "-hls_time", "1",
        "-hls_segment_type", "fmp4", "-hls_flags", "independent_segments",
        "-hls_segment_filename", str(directory / "seg%03d.m4s"), str(playlist))
    assert len(list(directory.glob("seg*.m4s"))) == 3
    streams = json.loads(run(ffprobe, "-v", "error", "-show_streams",
                             "-of", "json", str(playlist)))["streams"]
    assert {s["codec_name"] for s in streams} == {"h264", "aac"}
    run(ffmpeg, "-v", "error", "-xerror", "-nostdin", "-i", str(playlist),
        "-f", "null", "-")
    print("PASS H.264/AAC fMP4 HLS, ffprobe JSON and full decode")


def gpu(ffmpeg, ffprobe, directory):
    filters = run(ffmpeg, "-hide_banner", "-filters")
    assert "tonemap_cuda" in filters and "scale_cuda" in filters
    # Covers the upstream two-pass scaler and our luma dithering in every interpolation mode
    for algorithm in ("nearest", "bilinear", "bicubic", "lanczos"):
        for dimensions in ("160:96", "320:192"):
            run(ffmpeg, "-v", "error", "-xerror", "-nostdin",
                "-init_hw_device", "cuda=gpu:0", "-filter_hw_device", "gpu",
                "-f", "lavfi", "-i", "testsrc2=size=320x192:rate=25",
                "-vf", "format=p010le,hwupload," +
                f"scale_cuda={dimensions}:format=nv12:interp_algo={algorithm}," +
                "hwdownload,format=nv12", "-frames:v", "4", "-f", "null", "-")
    print("PASS CUDA scaler: four algorithms, downscale and same-size 10-to-8-bit")

    # Encode an HDR-tagged HEVC source, then run it through real NVDEC, CUDA and NVENC
    for transfer in ("smpte2084", "arib-std-b67"):
        source = directory / f"hdr-{transfer}.mkv"
        output = directory / f"sdr-{transfer}.mp4"
        run(ffmpeg, "-v", "error", "-nostdin", "-y", "-f", "lavfi", "-i",
            "testsrc2=size=640x360:rate=25", "-t", "1", "-vf",
            f"format=p010le,setparams=color_primaries=bt2020:color_trc={transfer}:colorspace=bt2020nc",
            "-c:v", "hevc_nvenc", "-preset", "p4", "-color_primaries", "bt2020",
            "-color_trc", transfer, "-colorspace", "bt2020nc", str(source))
        source_stream = json.loads(run(ffprobe, "-v", "error", "-show_streams",
                                       "-of", "json", str(source)))["streams"][0]
        assert source_stream["color_transfer"] == transfer, source_stream
        run(ffmpeg, "-v", "error", "-xerror", "-nostdin", "-y", "-hwaccel", "cuda",
            "-hwaccel_output_format", "cuda", "-i", str(source), "-vf",
            "scale_cuda=-2:180,tonemap_cuda=tonemap=hable:desat=0:format=nv12:p=bt709:t=bt709:m=bt709",
            "-c:v", "h264_nvenc", "-preset", "p4", "-forced-idr", "1",
            "-no-scenecut", "1", "-bf", "2", "-b_ref_mode", "0", str(output))
        stream = json.loads(run(ffprobe, "-v", "error", "-show_streams", "-of",
                                "json", str(output)))["streams"][0]
        assert stream["height"] == 180 and stream["pix_fmt"] == "yuv420p"
        assert all(stream[k] == "bt709" for k in
                   ("color_space", "color_transfer", "color_primaries")), stream
        run(ffmpeg, "-v", "error", "-xerror", "-nostdin", "-i", str(output),
            "-f", "null", "-")
    print("PASS PQ and HLG: HEVC NVDEC -> scale_cuda -> tonemap_cuda -> H.264 NVENC")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ffmpeg")
    parser.add_argument("ffprobe")
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--version", default="9.0.1",
                        help="expected FFmpeg version, normally from versions.env")
    args = parser.parse_args()
    expected = f"{args.version}-Matinee"
    assert expected in run(args.ffmpeg, "-version")
    assert expected in run(args.ffprobe, "-version")
    with tempfile.TemporaryDirectory(prefix="matinee-ffmpeg-smoke-") as tmp:
        directory = pathlib.Path(tmp)
        pause_resume(args.ffmpeg, directory)
        pause_resume(args.ffmpeg, directory, terminate=True)
        hls(args.ffmpeg, args.ffprobe, directory)
        if args.gpu:
            gpu(args.ffmpeg, args.ffprobe, directory)


if __name__ == "__main__":
    main()
