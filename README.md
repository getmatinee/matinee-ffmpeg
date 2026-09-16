# matinee-ffmpeg

Build scripts and patches for Matinee's FFmpeg distribution. The maintained patch series is available in [`patches/`](patches/).

FFmpeg and codec sources are downloaded from their upstream projects at the versions pinned in this repository.

The following scripts are also part of this repo:

| Script | Target | Consumer (where used) |
|--------|--------|----------|
| [`build-debian.sh`](build-debian.sh) | Debian and Ubuntu | backend container-image, matinee-deb |
| [`build-el.sh`](build-el.sh) | Enterprise Linux 9 and 10, static x264, x265, SVT-AV1, zimg, chromaprint | matinee-rpm |
| [`build-windows.sh`](build-windows.sh) | Windows x64, mingw-w64 cross build | matinee-win |

The packaging repos fetch this repository alongside the server and web sources and run the matching script after the checkout.

## What it builds

Upstream FFmpeg as a GPL build (no `--enable-nonfree`, no libfdk and no libnpp), so it stays redistributable and compatible with Matinee's AGPL-3.0 license.

- **NVIDIA full pipeline** (`ffnvcodec`, `cuda`, `cuda-llvm`, `cuvid`, `nvdec`, `nvenc`) gives hardware decode through NVDEC, the CUDA filters `scale_cuda` and `tonemap_cuda` for HDR to SDR, and hardware encode through `h264_nvenc` and `hevc_nvenc`. `--enable-cuda-llvm` compiles the CUDA filter kernels with clang, so no CUDA SDK is needed. The NVIDIA driver's encode and decode libraries are provided at runtime by the NVIDIA Container Toolkit.
- **VAAPI** (`vaapi`, `libdrm`, `opencl`) gives `h264_vaapi` and OpenCL filters on AMD and Intel.
- **Intel Quick Sync** (`libvpl`) gives `h264_qsv` and `scale_qsv` through the oneVPL dispatcher. Intel ships oneVPL for x86_64 only, so `add_qsv_flag` in `common.sh` adds the flag when the host is x86_64 and the dispatcher is present and builds without it otherwise, which keeps the arm64 legs of the multi-arch manifest working. The Windows script cross-builds the dispatcher itself and does not share the flag list.
- **x264 and x265 libraries** (`libx264`, `libx265`) provide the software fallback encoder and HEVC output.
- **AV1 and scaling** (`libdav1d`, `libsvtav1`, `libzimg`) provide AV1 decode and encode, and software scaling.
- **Subtitles** (`libass`, `libfreetype`, `libfontconfig`, `libfribidi`, `libharfbuzz`) provide the `subtitles` and `ass` filters, which render text subtitles onto video.
- **Audio** (`libopus`, `libmp3lame`, `libvorbis`) adds the Opus, MP3 and Vorbis encoders alongside FFmpeg's own AAC encoder.
- **Images and fingerprinting** (`libwebp`, `libvpx`, `chromaprint`) add WebP output for trickplay tiles, VP8 and VP9, and the chromaprint muxer for audio fingerprints.

## Base image

The container uses Debian trixie, which is built on glibc. Alpine cannot be used, because NVIDIA's runtime driver libraries are glibc-only and NVIDIA does not support musl, so NVENC and NVDEC can never load there however FFmpeg is compiled.

## Versions

Pinned once in [`versions.env`](versions.env), sourced by all three build scripts. The current base is **upstream FFmpeg 9.0.1**, with a SHA-256 pin checked before extraction on every platform. Windows records each download's URL and content hash, so an existing `WORKDIR` cannot silently reuse a stale or damaged archive. Override both `FFMPEG_VERSION` and `FFMPEG_SHA256` when evaluating another release.

## Windows dependency cache

Windows builds with a reusable `WORKDIR` isolate dependency prefixes by version pins, build recipes, compiler version and compiler/linker flags. Download caches record the source URL and content hash; changed or damaged entries are fetched again, and incomplete downloads are never promoted to cache entries.

Moving a checkout does not change the dependency key. Prefixes are retained so switching versions can reuse prior builds. Set `PRUNE_DEPENDENCY_CACHE=1` to remove other generated dependency prefixes after a successful Windows build; the current prefix, downloaded archives and unrelated directories are preserved. Use a separate `WORKDIR` for concurrent builds.

## Validation

`validate.sh` takes one mode. Each mode includes the checks of the one above it. CI runs `--cpu` and `--cuda`.

| Mode | Checks | Requires |
|---|---|---|
| `--patches` | Release checksum, exact patch application with no offsets or fuzz, shell syntax, download-cache behavior. | Nothing beyond a shell and `curl`. |
| `--cpu` | Builds a small FFmpeg, then checks pause and resume, shutdown while paused, MPEG-TS and fMP4 HLS, independent segment decoding and seeking, ASS bounds, queued subtitle EOF, and hardware buffer dimensions using a simulated allocator. | A C toolchain, pkg-config, nasm, libx264 development files, Python 3. |
| `--cuda` | Compiles the CUDA patches and checks partial texture-allocation cleanup against simulated driver calls. Runs without a GPU. | The `--cpu` requirements plus clang, git. |

To use an already downloaded archive, set `FFMPEG_SOURCE_ARCHIVE` to its absolute path. To test a complete production build, run:

```bash
python3 tests/smoke.py /path/to/ffmpeg /path/to/ffprobe
# Also exercise CUDA scaling and PQ/HLG NVDEC -> tone mapping -> NVENC:
python3 tests/smoke.py /path/to/ffmpeg /path/to/ffprobe --gpu
```

The GPU test requires an NVIDIA GPU and the runtime encode/decode libraries. It also checks empty hardware output and the visible dimensions of shared frames composited by `overlay_cuda`, and fails if a required pipeline cannot run. To verify error propagation, run `python3 tests/cuda_faults.py /path/to/configured-ffmpeg-build`: it rebuilds instrumented copies in a temporary directory and requires the production build dependencies and a working NVIDIA GPU.

The image workflow runs validation before publishing and exercises the produced binaries for both architectures. Hardware runtime checks still require the matching devices.

## Container image

Release images are published as `getmatinee/matinee-ffmpeg` on Docker Hub and as `ghcr.io/getmatinee/matinee-ffmpeg`, tagged with the FFmpeg version and `latest`. The backend image consumes the Docker Hub image by default through its `FFMPEG_IMAGE` build argument, so nothing needs to be built here for a normal deployment.

To build a local image variant yourself:

```bash
podman build -t matinee-ffmpeg:local -f Containerfile .
```

To verify the pipeline is present in the produced image:

```bash
podman run --rm matinee-ffmpeg:local sh -c '\
  /opt/matinee-ffmpeg/bin/ffmpeg -hide_banner -encoders | grep -E "nvenc|libx264"; \
  /opt/matinee-ffmpeg/bin/ffmpeg -hide_banner -filters  | grep scale_cuda; \
  /opt/matinee-ffmpeg/bin/ffmpeg -hide_banner -decoders | grep -E "cuvid|dav1d"'
```

## Credits

Some of the patches in this series were taken downstream from [jellyfin-ffmpeg](https://github.com/jellyfin/jellyfin-ffmpeg), whose maintainers had already solved problems we also ran into with FFmpeg and streaming, namely the cooperative CLI pause, the CUDA tone-mapping stack, and several subtitle and hardware-frame fixes. Thanks to them. The patches are derived works of FFmpeg and stay under FFmpeg's GPL/LGPL licensing.

## Support the project

Matinee is free software, funded by sponsorship through [GitHub Sponsors](https://github.com/sponsors/getmatinee) or [Ko-fi](https://ko-fi.com/matinee) and by the 1.- per month subscription of the prebuilt phone apps on the App Store and Play Store. Building the same apps from the sources is free of charge. The subscription pays for the store distribution and supports the project. See the [main repository](https://github.com/getmatinee/matinee#support-the-project) for the full picture.

## License

Build scripts are licensed under AGPL-3.0-or-later. Patches retain the licenses of the files they modify, including GPL, LGPL and MIT. The resulting FFmpeg builds are GPL-3.0-or-later (`--enable-gpl --enable-version3`, without nonfree components).
