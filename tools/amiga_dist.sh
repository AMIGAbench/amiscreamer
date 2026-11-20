#!/usr/bin/env bash
# The Amiga programs for an installation (its drawer: the game's DATA/ GFX/ CONFIG/
# MUSIC/ with the programs; the launcher starts amiscreamer_080 / _060 / _040 by those names):
#   tools/amiga_dist.sh [--nobuild]   ->  dist/amiga/AmiScreamer/ + AmiScreamer_v1.x.lha  (NO game data in it -- the game is still sold)
#                                         dist/amiga/AmiScreamer_Debug/ + AmiScreamer_Debug_v1.x.lha: amiscreamer_debug_* (the test
#                                         switches in them, DEBUG=1) and the benchmark; the release programs have none
# Copy the drawer's contents over the installed one (the old programs are replaced, the launcher stays).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AV="v$(cat "$ROOT/VERSION_AMIGA")"
VER="$(cat "$ROOT/VERSION_AMIGA" 2>/dev/null || echo 0.0)"
VD="$(git -C "$ROOT" log -1 --format=%cd --date=format:%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)"   # the $VER date: the commit's
                 # the archives: <name>_v1.x.lha
cd "$ROOT"
if [ "${1:-}" != "--nobuild" ]; then
  tools/amiga_build.sh CPU=68040 >/dev/null
  tools/amiga_build.sh CPU=68060 >/dev/null
  tools/amiga_build.sh CPU=68080 >/dev/null
  for c in 68040 68060 68080; do tools/amiga_build.sh CPU=$c DEBUG=1 >/dev/null; done
  mkdir -p port/build_amiga/server                 # amiscreamer_server (68020, bsdsocket.library)
  docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT":/work -w /work/port "${AMIGA_IMAGE:-amigadev/crosstools:m68k-amigaos}" \
    m68k-amigaos-gcc -m68020 -O2 -noixemul -DAMIGA=1 -DNET_SERVER "-DNET_VERSTAG=\"\$VER: amiscreamer_server $VER ($VD)\"" \
    -o build_amiga/server/amiscreamer_server \
    amiga/net/server.c amiga/net/net.c -lamiga
  tools/amiga_build_mos.sh >/dev/null                # MorphOS (PowerPC)
  tools/amiga_build_mos.sh DEBUG=1 >/dev/null
  tools/amiga_launcher.sh >/dev/null                 # the MUI launcher and its catalog
  tools/linux_progs.sh >/dev/null 2>&1               # the Linux programs (server, music converter), x86-64 / arm64
fi
OUT=dist/amiga/AmiScreamer
rm -rf "$OUT" dist/amiga/AmiScreamer.zip dist/amiga/AmiScreamer.lha dist/amiga/AmiScreamer_v*.lha; mkdir -p "$OUT/Catalogs/deutsch" "$OUT/Linux"
cp port/build_amiga/68040/openscreamer "$OUT/amiscreamer_040"
cp port/build_amiga/68060/openscreamer "$OUT/amiscreamer_060"
cp port/build_amiga/68080/openscreamer "$OUT/amiscreamer_080"
cp port/build_mos/screamer_mos_ppc "$OUT/amiscreamer_mos"
cp port/build_amiga/server/amiscreamer_server port/build_mos/amiscreamer_server_mos "$OUT/"
cp port/build_linux/amiscreamer_server_x64 port/build_linux/amiscreamer_server_arm64 "$OUT/Linux/"
cp build/launcher/amiscreamer_launcher installer_amiga/amiscreamer_launcher.info "$OUT/"
cp build/launcher/Catalogs/deutsch/amiscreamer_launcher.catalog "$OUT/Catalogs/deutsch/"
cp LICENSE "$OUT/LICENSE"                           # GPL-3.0, given along with the programs
cp installer_amiga/History.txt "$OUT/History.txt"
for l in de en; do
  iconv -f UTF-8 -t ISO-8859-1 installer_amiga/dist_README_$l > "$OUT/README_$l"
done
docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT/dist/amiga":/d -w /d "${AMIGA_IMAGE:-amigadev/crosstools:m68k-amigaos}" lha -aq AmiScreamer_$AV.lha AmiScreamer   # LhA for the Amiga
ls -l "$OUT"
# the debug programs and the benchmark
DBG=dist/amiga/AmiScreamer_Debug
rm -rf "$DBG" dist/amiga/AmiScreamer_Debug.zip dist/amiga/AmiScreamer_Debug.lha dist/amiga/AmiScreamer_Debug_v*.lha; mkdir -p "$DBG"
for c in 040 060 080; do cp port/build_amiga/68${c}_debug/openscreamer "$DBG/amiscreamer_debug_$c"; done
cp port/build_mos_debug/screamer_mos_ppc "$DBG/amiscreamer_debug_mos"
cp installer_amiga/Benchmark "$DBG/Benchmark"
cp LICENSE "$DBG/LICENSE"
cp installer_amiga/History.txt "$DBG/History.txt"
for l in de en; do
  iconv -f UTF-8 -t ISO-8859-1 installer_amiga/Benchmark_$l > "$DBG/Benchmark_$l"
  iconv -f UTF-8 -t ISO-8859-1 installer_amiga/debug_README_$l > "$DBG/README_$l"
done
docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT/dist/amiga":/d -w /d "${AMIGA_IMAGE:-amigadev/crosstools:m68k-amigaos}" lha -aq AmiScreamer_Debug_$AV.lha AmiScreamer_Debug   # LhA for the Amiga
ls -l "$DBG"
