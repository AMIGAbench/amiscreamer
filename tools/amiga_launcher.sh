#!/usr/bin/env bash
# The MUI launcher (installer_amiga/launcher/) -> build/launcher/
# amiscreamer_launcher + Catalogs/deutsch/amiscreamer_launcher.catalog. 68020 without FPU; docker
# amigadev/crosstools:m68k-amigaos. The title logo's block stays empty: the installer fills it (amiscreamer_inst logo).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VER="$(cat "$ROOT/VERSION_AMIGA" 2>/dev/null || echo 0.0)"
VD="$(git -C "$ROOT" log -1 --format=%cd --date=format:%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)"   # the $VER date: the commit's
mkdir -p build/launcher/Catalogs/deutsch
docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT":/w -w /w amigadev/crosstools:m68k-amigaos \
  m68k-amigaos-gcc -noixemul -m68020 -msoft-float -O2 -std=c99 -D_DEFAULT_SOURCE -Wall -Wno-unused-parameter \
  -fomit-frame-pointer -Wno-pointer-sign "-DLAUNCHER_VERSION=\"$VER\"" "-DLAUNCHER_DATE=\"$VD\"" -Iinstaller_amiga/inst installer_amiga/launcher/launcher.c installer_amiga/inst/inst_core.c \
  -o build/launcher/amiscreamer_launcher -lmui -lamiga -lm
python3 -I installer_amiga/launcher/catgen.py installer_amiga/launcher/launcher_strings.h installer_amiga/launcher/deutsch.ct \
  build/launcher/Catalogs/deutsch/amiscreamer_launcher.catalog deutsch
