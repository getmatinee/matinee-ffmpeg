#!/usr/bin/env bash
# Copyright (C) 2023-2026 Matinee
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee
#
# Cross-builds the patched Matinee FFmpeg for Windows x64 with mingw-w64

set -euo pipefail

. "$(dirname "$0")/versions.env"
FREETYPE_VERSION="${FREETYPE_VERSION:-2.13.3}"
FRIBIDI_VERSION="${FRIBIDI_VERSION:-1.0.16}"
HARFBUZZ_VERSION="${HARFBUZZ_VERSION:-10.1.0}"
LIBASS_VERSION="${LIBASS_VERSION:-0.17.3}"
X265_VERSION="${X265_VERSION:-4.1}"
DAV1D_VERSION="${DAV1D_VERSION:-1.5.0}"
SVTAV1_VERSION="${SVTAV1_VERSION:-v2.3.0}"
ZIMG_VERSION="${ZIMG_VERSION:-release-3.0.5}"
OPUS_VERSION="${OPUS_VERSION:-1.5.2}"
LAME_VERSION="${LAME_VERSION:-3.100}"
OGG_VERSION="${OGG_VERSION:-1.3.5}"
VORBIS_VERSION="${VORBIS_VERSION:-1.3.7}"
VPX_VERSION="${VPX_VERSION:-1.15.0}"
WEBP_VERSION="${WEBP_VERSION:-1.5.0}"
CHROMAPRINT_VERSION="${CHROMAPRINT_VERSION:-v1.5.1}"

PATCHDIR="${PATCHDIR:?set PATCHDIR to the exported ffmpeg patch series}"
OUT="${OUT:?set OUT to the output tarball path}"
JOBS="${JOBS:-$(nproc)}"

HOST=x86_64-w64-mingw32

workdir="${WORKDIR:-$(mktemp -d)}"
prefix="$workdir/prefix"
mkdir -p "$prefix"
[ -n "${WORKDIR:-}" ] || trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"

cat > cross.meson <<EOF
[binaries]
c = '${HOST}-gcc'
cpp = '${HOST}-g++'
ar = '${HOST}-ar'
strip = '${HOST}-strip'
windres = '${HOST}-windres'
pkgconfig = 'pkg-config'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

cat > cross.cmake <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER ${HOST}-gcc)
set(CMAKE_CXX_COMPILER ${HOST}-g++)
set(CMAKE_RC_COMPILER ${HOST}-windres)
set(CMAKE_FIND_ROOT_PATH $prefix)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

fetch() {
    [ -f "$2" ] || curl -fsSL -o "$2" "$1"
}

untar() {
    rm -rf "$2"
    mkdir -p "$2"
    tar -xf "$1" -C "$2" --strip-components=1
}

build_freetype() {
    fetch "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.xz" freetype.tar.xz
    untar freetype.tar.xz freetype
    cmake -S freetype -B freetype/build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$workdir/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON \
        -DFT_DISABLE_PNG=ON -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_ZLIB=ON
    cmake --build freetype/build -j "$JOBS"
    cmake --install freetype/build
}

build_fribidi() {
    fetch "https://github.com/fribidi/fribidi/releases/download/v${FRIBIDI_VERSION}/fribidi-${FRIBIDI_VERSION}.tar.xz" fribidi.tar.xz
    untar fribidi.tar.xz fribidi
    meson setup fribidi/build fribidi --cross-file cross.meson \
        --prefix "$prefix" --default-library static \
        -Ddocs=false -Dtests=false
    ninja -C fribidi/build -j "$JOBS" install
}

build_harfbuzz() {
    fetch "https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}/harfbuzz-${HARFBUZZ_VERSION}.tar.xz" harfbuzz.tar.xz
    untar harfbuzz.tar.xz harfbuzz
    meson setup harfbuzz/build harfbuzz --cross-file cross.meson \
        --prefix "$prefix" --default-library static \
        -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled \
        -Dcairo=disabled -Dicu=disabled -Ddocs=disabled -Dtests=disabled
    ninja -C harfbuzz/build -j "$JOBS" install
}

build_libass() {
    fetch "https://github.com/libass/libass/releases/download/${LIBASS_VERSION}/libass-${LIBASS_VERSION}.tar.xz" libass.tar.xz
    untar libass.tar.xz libass
    (cd libass && ./configure --host="$HOST" --prefix="$prefix" \
        --enable-static --disable-shared --disable-fontconfig \
        && make -j"$JOBS" && make install)
}

build_x264() {
    rm -rf x264
    git clone --quiet --depth 1 --branch stable \
        https://code.videolan.org/videolan/x264.git
    (cd x264 && ./configure --host="$HOST" --cross-prefix="${HOST}-" \
        --prefix="$prefix" --enable-static --disable-cli \
        && make -j"$JOBS" && make install)
}

build_x265() {
    fetch "https://bitbucket.org/multicoreware/x265_git/downloads/x265_${X265_VERSION}.tar.gz" x265.tar.gz
    untar x265.tar.gz x265
    cmake -S x265/source -B x265/build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$workdir/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED=OFF -DENABLE_CLI=OFF
    cmake --build x265/build -j "$JOBS"
    cmake --install x265/build
}

build_dav1d() {
    fetch "https://code.videolan.org/videolan/dav1d/-/archive/${DAV1D_VERSION}/dav1d-${DAV1D_VERSION}.tar.gz" dav1d.tar.gz
    untar dav1d.tar.gz dav1d
    meson setup dav1d/build dav1d --cross-file cross.meson \
        --prefix "$prefix" --default-library static \
        -Denable_tools=false -Denable_tests=false
    ninja -C dav1d/build -j "$JOBS" install
}

build_svtav1() {
    fetch "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/${SVTAV1_VERSION}/SVT-AV1-${SVTAV1_VERSION}.tar.gz" svtav1.tar.gz
    untar svtav1.tar.gz svtav1
    cmake -S svtav1 -B svtav1/build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$workdir/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF
    cmake --build svtav1/build -j "$JOBS"
    cmake --install svtav1/build
}

build_zimg() {
    fetch "https://github.com/sekrit-twc/zimg/archive/refs/tags/${ZIMG_VERSION}.tar.gz" zimg.tar.gz
    untar zimg.tar.gz zimg
    (cd zimg && ./autogen.sh && ./configure --host="$HOST" --prefix="$prefix" \
        --enable-static --disable-shared \
        && make -j"$JOBS" && make install)
}

build_opus() {
    fetch "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" opus.tar.gz
    untar opus.tar.gz opus
    (cd opus && ./configure --host="$HOST" --prefix="$prefix" \
        --enable-static --disable-shared --disable-doc --disable-extra-programs \
        && make -j"$JOBS" && make install)
}

build_lame() {
    fetch "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" lame.tar.gz
    untar lame.tar.gz lame
    (cd lame && ./configure --host="$HOST" --prefix="$prefix" \
        --enable-static --disable-shared --disable-frontend \
        && make -j"$JOBS" && make install)
}

build_ogg_vorbis() {
    fetch "https://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz" ogg.tar.gz
    untar ogg.tar.gz ogg
    (cd ogg && ./configure --host="$HOST" --prefix="$prefix" \
        --enable-static --disable-shared \
        && make -j"$JOBS" && make install)
    fetch "https://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz" vorbis.tar.gz
    untar vorbis.tar.gz vorbis
    (cd vorbis && ./configure --host="$HOST" --prefix="$prefix" \
        --enable-static --disable-shared --disable-docs --disable-examples \
        && make -j"$JOBS" && make install)
}

build_vpx() {
    fetch "https://github.com/webmproject/libvpx/archive/refs/tags/v${VPX_VERSION}.tar.gz" vpx.tar.gz
    untar vpx.tar.gz vpx
    (cd vpx && CROSS="${HOST}-" ./configure --target=x86_64-win64-gcc \
        --prefix="$prefix" --enable-static --disable-shared \
        --disable-examples --disable-tools --disable-docs --disable-unit-tests \
        && make -j"$JOBS" && make install)
}

build_webp() {
    fetch "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${WEBP_VERSION}.tar.gz" webp.tar.gz
    untar webp.tar.gz webp
    cmake -S webp -B webp/build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$workdir/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
        -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
        -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
    cmake --build webp/build -j "$JOBS"
    cmake --install webp/build
}

build_chromaprint() {
    fetch "https://github.com/acoustid/chromaprint/archive/refs/tags/${CHROMAPRINT_VERSION}.tar.gz" chromaprint.tar.gz
    untar chromaprint.tar.gz chromaprint
    cmake -S chromaprint -B chromaprint/build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$workdir/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF \
        -DFFT_LIB=kissfft \
        -DKISSFFT_SOURCE_DIR="$workdir/chromaprint/src/3rdparty/kissfft"
    cmake --build chromaprint/build -j "$JOBS"
    cmake --install chromaprint/build
}

for dep in freetype fribidi harfbuzz libass x264 x265 dav1d svtav1 zimg \
    opus lame ogg_vorbis vpx webp chromaprint; do
    if [ ! -f "$prefix/.stamp-$dep" ]; then
        echo "=== building $dep ==="
        "build_$dep"
        touch "$prefix/.stamp-$dep"
    fi
done

rm -rf nv-codec-headers
git clone --quiet --depth 1 --branch "$NVCODEC_VERSION" \
    https://github.com/FFmpeg/nv-codec-headers.git
make -C nv-codec-headers install PREFIX="$prefix"

fetch "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" ffmpeg.tar.xz
untar ffmpeg.tar.xz ffmpeg
cd ffmpeg

while read -r patchfile; do
    [ -n "$patchfile" ] || continue
    patch -p1 --no-backup-if-mismatch < "$PATCHDIR/$patchfile"
done < "$PATCHDIR/series"

./configure \
    --prefix=/ffmpeg \
    --target-os=mingw32 \
    --arch=x86_64 \
    --enable-cross-compile \
    --cross-prefix="${HOST}-" \
    --pkg-config=pkg-config \
    --pkg-config-flags="--static" \
    --extra-libs="-lstdc++" \
    --extra-cflags="-I$prefix/include -DCHROMAPRINT_NODLL" \
    --extra-ldflags="-L$prefix/lib" \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --enable-gpl \
    --enable-version3 \
    --extra-version=Matinee \
    --enable-ffnvcodec \
    --enable-cuda \
    --enable-cuda-llvm \
    --enable-cuvid \
    --enable-nvdec \
    --enable-nvenc \
    --enable-d3d11va \
    --enable-dxva2 \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libdav1d \
    --enable-libsvtav1 \
    --enable-libzimg \
    --enable-libass \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libharfbuzz \
    --enable-libopus \
    --enable-libmp3lame \
    --enable-libvorbis \
    --enable-libwebp \
    --enable-libvpx \
    --enable-chromaprint

make -j"$JOBS"
stage="$workdir/stage"
make DESTDIR="$stage" install

mkdir -p "$(dirname "$OUT")"
tar --zstd -cf "$OUT" -C "$stage/ffmpeg" bin
echo "ffmpeg tarball: $OUT"
