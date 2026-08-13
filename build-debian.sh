#!/usr/bin/env bash
# Copyright (C) 2023-2026 Swissmakers GmbH
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee
#
# Builds the patched Matinee FFmpeg on Debian or Ubuntu

set -euo pipefail

. "$(dirname "$0")/versions.env"
. "$(dirname "$0")/common.sh"

PREFIX="${PREFIX:-/usr/lib/matinee/ffmpeg}"
PATCHDIR="${PATCHDIR:?set PATCHDIR to the exported ffmpeg patch series}"
OUT="${OUT:-}"
JOBS="${JOBS:-$(nproc)}"

workdir="$(mktemp -d)"
stage="$workdir/stage"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

install_nvcodec_headers

fetch_ffmpeg
cd ffmpeg
apply_patch_series "$PATCHDIR"

./configure \
    --prefix="$PREFIX" \
    "${FFMPEG_COMMON_FLAGS[@]}"

make -j"$JOBS"

if [ -n "$OUT" ]; then
    make DESTDIR="$stage" install
    mkdir -p "$(dirname "$OUT")"
    tar --zstd -cf "$OUT" -C "$stage$PREFIX" bin
    echo "ffmpeg tarball: $OUT"
else
    make install
fi
