# matinee-ffmpeg

This repository is the single source of truth for ffmpeg compilations or patchings in the Matinee ecosystem. All currently applied patches on top of the stock ffmpeg is found here: [`patches/`](patches/).

The ffmpeg and codec sources are downloaded from their upstreams at the version pinned here.

The following scripts are also part of this repo:

| Script | Target | Consumer (where used) |
|--------|--------|----------|
| [`build-debian.sh`](build-debian.sh) | Debian and Ubuntu | backend container-image, matinee-deb |
| [`build-el.sh`](build-el.sh) | Enterprise Linux 9 and 10, static x264, x265, SVT-AV1, zimg, chromaprint | matinee-rpm |
| [`build-windows.sh`](build-windows.sh) | Windows x64, mingw-w64 cross build | matinee-win |

The packaging repos fetch this repository alongside the server and web sources and run the matching script after the checkout.

## What it builds

Upstream FFmpeg as a GPL build (no `--enable-nonfree`, no libfdk and no libnpp), so it stays redistributable and compatible with Matinee's AGPL-3.0 license.

- **NVIDIA full pipeline** -> (`ffnvcodec`, `cuda`, `cuda-llvm`, `cuvid`, `nvdec`, `nvenc`) hardware decode (NVDEC), CUDA filters (`scale_cuda`, and `tonemap_cuda` for HDR->SDR), and hardware encode (`h264_nvenc`, `hevc_nvenc`). `--enable-cuda-llvm` compiles the CUDA filter kernels with clang, so **no CUDA SDK** is needed. The NVIDIA driver's encode/decode libraries are provided at runtime by the NVIDIA Container Toolkit
- **VAAPI** (`vaapi`, `libdrm`, `opencl`) `h264_vaapi` and OpenCL filters for AMD/Intel.
- **Intel Quick Sync** (`libvpl`) `h264_qsv` and `scale_qsv` through the oneVPL dispatcher. Intel ships oneVPL for x86_64 only, so `add_qsv_flag` in `common.sh` adds the flag when the host is x86_64 and the dispatcher is present and builds without it otherwise, which keeps the arm64 legs of the multi-arch manifest working. The Windows script cross-builds the dispatcher itself and does not share the flag list.
- **x264/x265 libraries** (`libx264`, `libx265`) -> `libx264` is the software-fallback encoder and `libx265` is ready for HEVC output
- **AV1 and scaling** (`libdav1d`, `libsvtav1`, `libzimg`) efficient AV1 decode/encode and scaling
- **Subtitles** (`libass`, `libfreetype`, `libfontconfig`, `libfribidi`, `libharfbuzz`) for subtitle burn-in
- **Audio** (`libopus`, `libmp3lame`, `libvorbis`)
- **Images / misc** (`libwebp`, `libvpx`, `chromaprint`).

## Base image

Debian trixie (glibc) -> Alpine cannot be used becaus NVIDIA's runtime driver libraries are glibc-only and NVIDIA does not support musl, so NVENC/NVDEC can never load there regardless of how FFmpeg is compiled.

## Versions

Pinned once in [`versions.env`](versions.env), sourced by all three build
scripts.

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

Some of the patches in this series were taken downstream from [jellyfin-ffmpeg](https://github.com/jellyfin/jellyfin-ffmpeg), whose maintainers had already solved problems we also ran into with FFmpeg and streaming -> the NVDEC surface clamp, the cooperative CLI pause, and the CUDA tone-mapping stack. Thanks to them. The patches are derived works of FFmpeg and stay under FFmpeg's GPL/LGPL licensing.

## Support the project

Matinee is free software, funded by sponsorship through [GitHub Sponsors](https://github.com/sponsors/getmatinee) or [Ko-fi](https://ko-fi.com/matinee) and by the 1.- per month subscription of the prebuilt phone apps on the App Store and Play Store. Building the same apps from the sources is free of charge. The subscription pays for the store distribution and supports the project. See the [main repository](https://github.com/getmatinee/matinee#support-the-project) for the full picture.

## License

AGPL-3.0-or-later for the build scripts in this repository. The patches stay under FFmpeg's own GPL/LGPL licensing, and the resulting FFmpeg builds are GPL-3.0-or-later (GPL with the version3 option, no nonfree components).
