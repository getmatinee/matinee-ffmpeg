# Copyright (C) 2023-2026 Swissmakers GmbH
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee
#
# Shared helpers for the Linux build scripts
# build-windows.sh does not source this..

install_nvcodec_headers() {
    git clone --quiet --depth 1 --branch "$NVCODEC_VERSION" \
        https://github.com/FFmpeg/nv-codec-headers.git
    make -C nv-codec-headers install ${1:+PREFIX="$1"}
}

fetch_ffmpeg() {
    curl -fsSL -o ffmpeg.tar.xz \
        "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    mkdir ffmpeg && tar -xf ffmpeg.tar.xz -C ffmpeg --strip-components=1
}

add_qsv_flag() {
    case "$(uname -m)" in
    x86_64 | amd64) ;;
    *) return 0 ;;
    esac
    if pkg-config --exists "vpl >= 2.6" 2>/dev/null; then
        FFMPEG_COMMON_FLAGS+=(--enable-libvpl)
        return 0
    fi
    echo "note: libvpl >= 2.6 not found, building without Intel Quick Sync" >&2
}

apply_patch_series() {
    while read -r patchfile; do
        [ -n "$patchfile" ] || continue
        patch -p1 --no-backup-if-mismatch < "$1/$patchfile"
    done < "$1/series"
}

FFMPEG_COMMON_FLAGS=(
    --disable-debug
    --disable-doc
    --disable-ffplay
    --enable-gpl
    --enable-version3
    --extra-version=Matinee
    --enable-ffnvcodec
    --enable-cuda
    --enable-cuda-llvm
    --enable-cuvid
    --enable-nvdec
    --enable-nvenc
    --enable-vaapi
    --enable-libdrm
    --enable-opencl
    --enable-libx264
    --enable-libx265
    --enable-libdav1d
    --enable-libsvtav1
    --enable-libzimg
    --enable-libass
    --enable-libfreetype
    --enable-libfontconfig
    --enable-libfribidi
    --enable-libharfbuzz
    --enable-libopus
    --enable-libmp3lame
    --enable-libvorbis
    --enable-libwebp
    --enable-libvpx
    --enable-chromaprint
)
