#!/usr/bin/env bash
# Copyright (C) 2023-2026 Matinee
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee
#
# Builds the patched Matinee FFmpeg for Enterprise Linux inside build container

set -euo pipefail

. "$(dirname "$0")/versions.env"
. "$(dirname "$0")/common.sh"

X265_VERSION="${X265_VERSION:-4.1}"
SVTAV1_VERSION="${SVTAV1_VERSION:-v2.3.0}"
ZIMG_VERSION="${ZIMG_VERSION:-release-3.0.5}"
CHROMAPRINT_VERSION="${CHROMAPRINT_VERSION:-v1.5.1}"

PREFIX="${PREFIX:-/usr/lib/matinee/ffmpeg}"
PATCHDIR="${PATCHDIR:?set PATCHDIR to the exported ffmpeg patch series}"
OUT="${OUT:?set OUT to the output tarball path}"
JOBS="${JOBS:-$(nproc)}"

workdir="$(mktemp -d)"
depprefix="$workdir/deps"
stage="$workdir/stage"
trap 'rm -rf "$workdir"' EXIT

export PKG_CONFIG_PATH="$depprefix/lib/pkgconfig:$depprefix/lib64/pkgconfig"

cd "$workdir"

git clone --quiet --depth 1 --branch stable \
    https://code.videolan.org/videolan/x264.git
(cd x264 && ./configure --prefix="$depprefix" --enable-static --disable-cli \
    && make -j"$JOBS" && make install)

curl -fsSL -o x265.tar.gz \
    "https://bitbucket.org/multicoreware/x265_git/downloads/x265_${X265_VERSION}.tar.gz"
mkdir x265 && tar -xf x265.tar.gz -C x265 --strip-components=1
(cd x265 && cmake -S source -B build \
    -DCMAKE_INSTALL_PREFIX="$depprefix" -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
    && cmake --build build -j "$JOBS" && cmake --install build)

curl -fsSL -o svtav1.tar.gz \
    "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/${SVTAV1_VERSION}/SVT-AV1-${SVTAV1_VERSION}.tar.gz"
mkdir svtav1 && tar -xf svtav1.tar.gz -C svtav1 --strip-components=1
(cd svtav1 && cmake -S . -B build \
    -DCMAKE_INSTALL_PREFIX="$depprefix" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF \
    && cmake --build build -j "$JOBS" && cmake --install build)

curl -fsSL -o zimg.tar.gz \
    "https://github.com/sekrit-twc/zimg/archive/refs/tags/${ZIMG_VERSION}.tar.gz"
mkdir zimg && tar -xf zimg.tar.gz -C zimg --strip-components=1
(cd zimg && ./autogen.sh && ./configure --prefix="$depprefix" \
    --enable-static --disable-shared \
    && make -j"$JOBS" && make install)

curl -fsSL -o chromaprint.tar.gz \
    "https://github.com/acoustid/chromaprint/archive/refs/tags/${CHROMAPRINT_VERSION}.tar.gz"
mkdir chromaprint && tar -xf chromaprint.tar.gz -C chromaprint --strip-components=1
(cd chromaprint && cmake -S . -B build \
    -DCMAKE_INSTALL_PREFIX="$depprefix" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF \
    -DFFT_LIB=kissfft \
    && cmake --build build -j "$JOBS" && cmake --install build)

install_nvcodec_headers "$depprefix"

fetch_ffmpeg
cd ffmpeg
apply_patch_series "$PATCHDIR"

./configure \
    --prefix="$PREFIX" \
    --pkg-config-flags="--static" \
    --extra-libs="-lstdc++ -lm" \
    "${FFMPEG_COMMON_FLAGS[@]}"

make -j"$JOBS"
make DESTDIR="$stage" install

mkdir -p "$(dirname "$OUT")"
tar --zstd -cf "$OUT" -C "$stage$PREFIX" bin
echo "ffmpeg tarball: $OUT"
