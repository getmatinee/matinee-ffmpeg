# Matinee FFmpeg patch series

Matinee's maintained patch series for upstream FFmpeg. Every build script applies the patches listed in [`series`](series), in order, after extracting the source and before running `./configure`. Update `series` when adding or removing a patch.

The base is **FFmpeg 9.0.1**. The shared build helper rejects reversed patches, offsets, fuzz, and failed hunks. Patches retain the licenses and copyright notices of the files they modify (including MIT-licensed CUDA files); the resulting `--enable-gpl --enable-version3` build is GPL-3.0-or-later.

## Applied series

| Patch | Function |
|---|---|
| 0002 | Cooperative CLI pause/resume with synchronized state, elapsed-time accounting and shutdown handling. |
| 0003 | Prevent software color conversion between hardware pixel formats. |
| 0004 | CUDA vector constructors and tone-mapping math helpers. |
| 0005 | CUDA luma dithering during bit-depth reduction, integrated with upstream scaling and anti-aliasing. |
| 0006 | GPU tone mapping through `tonemap_cuda`, with color utilities and CUDA runtime linking. |
| 0007 | Remove trailing NUL padding from ASS headers and trailers. |
| 0008 | Preserve hardware frame contexts for empty video output. |
| 0009 | Support software frames that retain hardware mapping references in swscale. |
| 0012 | Preserve queued subtitle end-of-stream signals during filter graph initialization. |

Patch numbers remain stable across releases and retired numbers are not reused.

| Retired | Reason |
|---|---|
| 0001 | NVDEC surface handling is included in upstream FFmpeg 9.0.1. |
| 0010 | `hwupload` device discovery is already handled by `hw_device_for_filter`, which falls back to the device `-hwaccel` registers. |
| 0011 | VAAPI MJPEG range support covers an encoder Matinee never invokes, because every image and thumbnail is encoded in software. |
| 0013 | QSV AV1 HDR side data reaches Matinee through ffprobe rather than the decoder, so exporting it changes nothing. |

## Usage

Applications can pause and resume transcoding by sending a single `p` or `u` byte to FFmpeg's stdin. Keep stdin enabled for this feature. Pause stops input reading after frames already in the pipeline drain. Repeated commands are safe, and `q` or SIGTERM can terminate a paused process.

For GPU HDR-to-SDR conversion, use the following pipeline:

```text
NVDEC -> scale_cuda -> tonemap_cuda -> NVENC
scale_cuda=-2:HEIGHT,tonemap_cuda=tonemap=hable:desat=0:format=nv12:p=bt709:t=bt709:m=bt709
```

This build provides `tonemap_cuda`. CUDA kernels compile through clang (`--enable-cuda-llvm`), without the CUDA SDK or nonfree libraries.

See the [validation commands](../README.md#validation) for patch, CPU and NVIDIA runtime checks.