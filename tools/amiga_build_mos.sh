#!/usr/bin/env bash
# The MorphOS build (PowerPC), in the cross toolchain's container: tools/amiga_build_mos.sh [clean]
#   -> port/build_mos/screamer_mos_ppc, port/build_mos/amiscreamer_server_mos
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# AmiScreamer has its own number (VERSION_AMIGA); the engine's (tools/version.sh) goes along in brackets
AV="$(cat "$ROOT/VERSION_AMIGA" 2>/dev/null || echo 0.0)"
VD="$(git -C "$ROOT" log -1 --format=%cd --date=format:%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)"   # the $VER date: the commit's
V="$(cat "$ROOT/VERSION_AMIGA" 2>/dev/null || echo unknown) (OpenScreamer $(sh "$ROOT/tools/version.sh" 2>/dev/null || echo unknown))"
exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/work -w /work/port amigadev/crosstools:ppc-morphos \
    make -f amiga/Makefile.mos -j"$(nproc)" OS_VERSION="$V" AMI_VER="$AV" AMI_DATE="$VD" "$@"
