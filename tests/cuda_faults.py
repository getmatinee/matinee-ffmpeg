#!/usr/bin/env python3
# Copyright (C) 2023-2026 Swissmakers GmbH
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee

"""Verify CUDA errors in a disposable copy of a configured, built FFmpeg tree."""

import argparse
import os
import pathlib
import shutil
import subprocess
import tempfile


def encode(binary):
    return subprocess.run([
        str(binary), "-v", "error", "-nostdin", "-init_hw_device", "cuda=gpu:0",
        "-filter_hw_device", "gpu", "-f", "lavfi", "-i",
        "testsrc2=size=160x96:rate=25:duration=0.2", "-vf",
        "format=p010le,setparams=color_primaries=bt2020:color_trc=smpte2084:"
        "colorspace=bt2020nc,hwupload,tonemap_cuda=tonemap=hable:desat=0:"
        "format=nv12:p=bt709:t=bt709:m=bt709", "-frames:v", "1",
        "-c:v", "h264_nvenc", "-f", "null", "-",
    ], capture_output=True, text=True, timeout=60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path, help="configured production build tree")
    args = parser.parse_args()
    source = args.source.resolve()
    baseline = encode(source / "ffmpeg")
    assert baseline.returncode == 0, baseline.stderr

    with tempfile.TemporaryDirectory(prefix="matinee-cuda-faults-") as tmp:
        build = pathlib.Path(tmp) / "ffmpeg"
        shutil.copytree(source, build, ignore=shutil.ignore_patterns(".git"))
        target = build / "libavfilter/vf_tonemap_cuda.c"
        original = target.read_text()
        cases = [
            ("kernel failure", "    ret = run_kernel(ctx, s->frame, src);\n",
             "    ret = AVERROR_EXTERNAL;\n", "Generic error in an external library"),
            ("metadata allocation failure", "    ret = av_frame_copy_props(out, in);\n",
             "    ret = av_frame_copy_props(out, in);\n    ret = AVERROR(ENOMEM);\n",
             "Cannot allocate memory"),
        ]
        for name, needle, replacement, expected in cases:
            assert original.count(needle) == 1, f"update injection point for {name}"
            target.write_text(original.replace(needle, replacement))
            subprocess.run(["make", "-j" + os.environ.get("JOBS", "2"), "ffmpeg"],
                           cwd=build, check=True, stdout=subprocess.DEVNULL)
            result = encode(build / "ffmpeg")
            assert result.returncode != 0 and expected in result.stderr, (name, result.stderr)
            print(f"PASS CUDA {name} propagates to the CLI", flush=True)


if __name__ == "__main__":
    main()
