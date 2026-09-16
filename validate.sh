#!/usr/bin/env bash
# Copyright (C) 2023-2026 Swissmakers GmbH
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee
#
# Validates the pinned source and optionally compiles and runs the CPU regressions
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
. "$repo/versions.env"
. "$repo/common.sh"
bash "$repo/tests/build_helpers.sh"

mode="${1:---patches}"
case "$mode" in
    --patches | --cpu) ;;
    *) echo "usage: $0 [--patches|--cpu]" >&2; exit 2 ;;
esac
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"
if [ -n "${FFMPEG_SOURCE_ARCHIVE:-}" ]; then
    cp "$FFMPEG_SOURCE_ARCHIVE" "ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi
fetch_ffmpeg
cd ffmpeg
apply_patch_series "$repo/patches"
for script in "$repo"/*.sh; do bash -n "$script"; done
[ "$mode" = --cpu ] || exit 0

# A small software build covers compilation and the same CLI contract as production.
# Full CUDA, QSV and VAAPI builds still use the production build scripts
./configure --prefix="$workdir/install" --extra-version=Matinee \
    --disable-autodetect --disable-everything --disable-network --disable-doc \
    --disable-debug --disable-ffplay --enable-gpl --enable-libx264 \
    --enable-protocol=file,pipe --enable-indev=lavfi \
    --enable-filter=testsrc2,sine,format,scale,aresample \
    --enable-encoder=libx264,aac,rawvideo,wrapped_avframe,pcm_s16le \
    --enable-decoder=h264,aac,pcm_s16le,rawvideo,wrapped_avframe \
    --enable-parser=h264,aac \
    --enable-muxer=rawvideo,null,hls,mp4,ass \
    --enable-demuxer=mov,hls --enable-bsf=aac_adtstoasc
make -j"${JOBS:-2}"
make install
export PKG_CONFIG_PATH="$workdir/install/lib/pkgconfig"
# pkg-config intentionally expands into individual compiler and linker arguments
cc "$repo/tests/regressions.c" -o "$workdir/regressions" \
    $(pkg-config --cflags --libs --static libavformat libswscale libavcodec libavutil)
"$workdir/regressions"
python3 "$repo/tests/smoke.py" --version "$FFMPEG_VERSION" \
    "$workdir/install/bin/ffmpeg" "$workdir/install/bin/ffprobe"
