#!/usr/bin/env bash
# The Amiga build, in the cross toolchain's container (Bebbo's gcc 6.5.0b, libnix, the NDK):
#   tools/amiga_build.sh [CPU=68060|68040|68080] [clean]   ->  port/build_amiga/<cpu>/openscreamer
#   DEBUG=1: the build with the test switches -> port/build_amiga/<cpu>_debug/openscreamer (tests, benchmark)
# The version is worked out here (the container has no git) and handed in.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${AMIGA_IMAGE:-amigadev/crosstools:m68k-amigaos}"
# AmiScreamer has its own number (VERSION_AMIGA); the engine's (tools/version.sh) goes along in brackets
AV="$(cat "$ROOT/VERSION_AMIGA" 2>/dev/null || echo 0.0)"
VD="$(git -C "$ROOT" log -1 --format=%cd --date=format:%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)"   # the $VER date: the commit's
V="$(cat "$ROOT/VERSION_AMIGA" 2>/dev/null || echo unknown) (OpenScreamer $(sh "$ROOT/tools/version.sh" 2>/dev/null || echo unknown))"
exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/work -w /work/port "$IMG" \
    make -f amiga/Makefile -j"$(nproc)" OS_VERSION="$V" AMI_VER="$AV" AMI_DATE="$VD" "$@"
