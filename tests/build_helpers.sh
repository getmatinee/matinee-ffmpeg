#!/usr/bin/env bash
# Copyright (C) 2023-2026 Swissmakers GmbH
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee
#
# Fails closed on a stale cached source, a duplicate patch or a drifting hunk
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/common.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

FFMPEG_VERSION=test
FFMPEG_SHA256=0000000000000000000000000000000000000000000000000000000000000000
printf 'stale source archive\n' > ffmpeg-test.tar.xz
if fetch_ffmpeg > checksum.log 2>&1; then
    echo 'incorrect source checksum was accepted' >&2; exit 1
fi
grep -q 'checksum mismatch' checksum.log
[ ! -d ffmpeg ]

mkdir patches
printf 'test.patch\n' > patches/series
cat > patches/test.patch <<'PATCH'
--- a/input
+++ b/input
@@ -1,3 +1,3 @@
 one
-two
+changed
 three
PATCH
printf 'one\ntwo\nthree\n' > input
apply_patch_series "$workdir/patches" > apply.log
if apply_patch_series "$workdir/patches" > repeat.log 2>&1; then
    echo 'duplicate patch was accepted' >&2; exit 1
fi
printf 'prefix\none\ntwo\nthree\n' > input
if apply_patch_series "$workdir/patches" > offset.log 2>&1; then
    echo 'offset patch was accepted' >&2; exit 1
fi
grep -q 'does not match the pinned source exactly' offset.log
printf 'different\ntwo\nthree\n' > input
if apply_patch_series "$workdir/patches" > fuzz.log 2>&1; then
    echo 'fuzzy patch was accepted' >&2; exit 1
fi
echo 'PASS source checksum, repeated patch, offset and fuzz rejection'
