# Matinee FFmpeg

The curated patch series Matinee applies on top of pristine upstream FFmpeg. Every build script in this repository applies the patches listed in [`series`](series), in order, right after extracting the FFmpeg source and before `./configure`. To add or drop a patch, we do this in that file `series`.

All patches are minimal unified diffs. They modify FFmpeg and are therefore derived works of FFmpeg, licensed LGPL like the files they touch. The build enables `--enable-gpl --enable-version3`. Several patches were taken downstream from jellyfin-ffmpeg and refactored as standalone diffs against
FFmpeg 8.1.2.

## Overview of currently applied patches
See below to get insights what every patch does.


### 0001 - NVDEC "exceed 32 surfaces" fix

NVDEC rejects decoder init when asked for more than 32 decode surfaces; some high-DPB streams (e.g. certain HEVC) request more via `initial_pool_size` and init fails hard. The patch clamps `ulNumDecodeSurfaces`/`dpb_size` to `FFMIN(pool, 32)` and `ulNumOutputSurfaces` to `FFMIN(pool, 64)`, and adjusts one surface refcount accordingly. Small and defensive; it matters because the whole point of our build is the NVDEC -> NVENC pipeline.

### 0002 - Cooperative pause for the ffmpeg CLI

Adds two globals (`paused_start`, `paused_time`), `p`/`u` keyboard commands, and one check in the demuxer's `input_thread`: while paused it sleeps 1 ms and skips `av_read_frame`, so the demuxer stops reading ahead (bounds memory) instead of buffering. Timing is corrected via `gettime_relative_minus_pause()` so stats stay accurate.

Matinee's continuous HLS writer paces each long-running ffmpeg to ~realtime so it never races to encode the whole title and idles at ~0 CPU when playback pauses. That throttle (`matinee-server/internal/transcode/writer.go`) previously used `SIGSTOP`/`SIGCONT`; it now writes a single `p`/`u` byte to the writer ffmpeg's stdin instead. Cooperative pause is preferable to `SIGSTOP` here because the process holds an NVENC/CUDA context: `SIGSTOP` freezes it mid-syscall, while the patch pauses cleanly at the demuxer read loop. The writer's ffmpeg therefore runs **without** `-nostdin`; one-shot/audio/subtitle/thumbnail/download invocations keep `-nostdin`.

### 0003 - No software colour-conversion between HW formats

When the filtergraph output is a hardware pixel format, stock ffmpeg still appends colour-space/range/alpha options to format negotiation, which can make it insert a software colour-convert between two HW formats - a silent GPU->CPU->GPU roundtrip that collapses throughput. The patch skips those colour options when the output format carries `AV_PIX_FMT_FLAG_HWACCEL`. This keeps our `nvdec -> scale_cuda -> nvenc` path zero-copy.

### 0004-0006 - GPU tonemapping

Three patches taken together from jellyfin-ffmpeg master (their 0002 update-cuda-func-header, 0003 add-enhanced-cuda-pixfmt-converter-impl, 0004 add-cuda-tonemap-impl), which are already written against the FFFilter API and apply to 8.1.2.

- `matinee-0004-cuda-func-header` -> extends `compat/cuda/cuda_runtime.h` with the device functions the CUDA kernels below need.
- `matinee-0005-cuda-pixfmt-converter` -> rewrites `vf_scale_cuda`'s kernels with a full pixel format converter (adds dithering and more formats); prerequisite of the tonemap filter.
- `matinee-0006-cuda-tonemap` -> adds the `tonemap_cuda` filter (new files under `libavfilter/cuda/` plus configure/Makefile/allfilters registration). Compiles via `--enable-cuda-llvm` (deps: ffnvcodec + cuda_nvcc|cuda_llvm), no CUDA SDK needed.

Why? HDR sources previously tonemapped on the CPU (`hwdownload` + zscale/tonemap/zscale), the single biggest throughput killer for 4K HDR on NVENC hosts. With `tonemap_cuda` the whole HDR pipeline stays on the GPU: `nvdec -> scale_cuda -> tonemap_cuda -> nvenc` (patch 0003 in this series keeps it zero-copy). The backend detects the filter at runtime (`Capabilities.HasFilter("tonemap_cuda")`, `matinee-server/internal/transcode/encoder.go`) and falls back to the CPU chain on builds without it, so the patches can be dropped without code changes.
