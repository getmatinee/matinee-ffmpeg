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

# Exercise retry, version changes and damaged cache entries without a network
curl() {
    local output= url=
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o) output="$2"; shift 2 ;;
            --retry) shift 2 ;;
            -*) shift ;;
            *) url="$1"; shift ;;
        esac
    done
    printf '%s\n' "$url" >> downloads
    printf '%s\n' "$url" > "$output"
    [ "$url" != broken ]
}
if fetch_cached broken dependency.tar > download.log 2>&1; then
    echo 'failed dependency download was accepted' >&2; exit 1
fi
[ ! -f dependency.tar ] && [ ! -f dependency.tar.source ]
fetch_cached version-1 dependency.tar
fetch_cached version-1 dependency.tar
[ "$(wc -l < downloads)" -eq 2 ]
fetch_cached version-2 dependency.tar
grep -qx version-2 dependency.tar
[ "$(wc -l < downloads)" -eq 3 ]
printf 'damaged\n' > dependency.tar
fetch_cached version-2 dependency.tar
grep -qx version-2 dependency.tar
[ "$(wc -l < downloads)" -eq 4 ]
if fetch_cached broken dependency.tar > download.log 2>&1; then exit 1; fi
grep -qx version-2 dependency.tar
fetch_cached version-2 dependency.tar
[ "$(wc -l < downloads)" -eq 5 ]
# Caches without an integrity record must be downloaded once
rm dependency.tar.source
fetch_cached version-2 dependency.tar
[ "$(wc -l < downloads)" -eq 6 ]

printf recipe-1 > recipe
key1="$(printf version-1 | build_cache_key recipe)"
[ "$key1" = "$(printf version-1 | build_cache_key recipe)" ]
mkdir 'other checkout'
cp recipe 'other checkout/recipe'
[ "$key1" = "$(printf version-1 | build_cache_key "$workdir/other checkout/recipe")" ]
cp recipe $'other checkout/recipe\\with\nnewlines'
[ "$key1" = "$(printf version-1 | build_cache_key "$workdir/"$'other checkout/recipe\\with\nnewlines')" ]
[ "$key1" != "$(printf version-2 | build_cache_key recipe)" ]
printf recipe-2 > recipe
[ "$key1" != "$(printf version-1 | build_cache_key recipe)" ]
printf recipe-3 > recipe-other
[ "$(printf version-1 | build_cache_key recipe recipe-other)" != \
  "$(printf version-1 | build_cache_key recipe-other recipe)" ]
if printf version-1 | build_cache_key missing-recipe recipe > missing.log 2>&1; then
    echo 'missing recipe was accepted' >&2; exit 1
fi
echo 'PASS dependency cache: failed downloads, relocation, changed versions/recipes and damaged archives'

keep="$(printf active | sha256sum | cut -d ' ' -f1)"
stale="$(printf stale | sha256sum | cut -d ' ' -f1)"
linked="$(printf linked | sha256sum | cut -d ' ' -f1)"
mkdir -p "cache/prefix-$keep" "cache/prefix-$stale" cache/prefix-unrelated cache/prefix outside
touch outside/preserve
ln -s "$workdir/outside" "cache/prefix-$linked"
if prune_dependency_cache cache invalid; then
    echo 'invalid active cache key was accepted' >&2; exit 1
fi
[ -d "cache/prefix-$stale" ]
prune_dependency_cache cache "$keep"
[ -d "cache/prefix-$keep" ] && [ ! -e "cache/prefix-$stale" ]
[ -d cache/prefix-unrelated ] && [ -d cache/prefix ]
[ -L "cache/prefix-$linked" ] && [ -f outside/preserve ]
prune_dependency_cache cache "$keep"
prune_dependency_cache empty-cache "$keep"
echo 'PASS dependency pruning preserves the active prefix, unrelated paths and symlinks'
