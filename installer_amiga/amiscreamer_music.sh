#!/bin/sh
# amiscreamer_music.sh - creates the music files for Screamer on the Amiga (track02.raw ... track08.raw) on a Linux PC.
# Copy the files afterwards into the drawer Screamer/MUSIC (or Bleifuss/MUSIC) on the Amiga.
#
#   sh amiscreamer_music.sh                      music from the CD in /dev/cdrom
#   sh amiscreamer_music.sh --cd /dev/sr1        music from the CD in another drive
#   sh amiscreamer_music.sh --gog <setup_screamer_1.01_gog_v2_(86677).exe>
#   sh amiscreamer_music.sh --wav <dir>          already ripped tracks (track02.wav ... track08.wav)
#   option -o <dir>: where to put the files (default: ./MUSIC)
#
# The converter is the program next to this script: amiscreamer_music_x64 (PC) or amiscreamer_music_arm64
# (arm64, e.g. Raspberry Pi). For the CD it needs cdparanoia (or icedax).
set -eu

out=MUSIC
mode=cd
src=/dev/cdrom
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        --cd) mode=cd; src=$2; shift 2 ;;
        --gog) mode=gog; src=$2; shift 2 ;;
        --wav) mode=wav; src=$2; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown option $1 (see --help)" >&2; exit 2 ;;
    esac
done

here=$(cd "$(dirname "$0")" && pwd)
case $(uname -m) in
    x86_64|amd64) conv=$here/amiscreamer_music_x64 ;;
    aarch64|arm64) conv=$here/amiscreamer_music_arm64 ;;
    *) echo "No converter for this processor ($(uname -m)): only x86-64 and arm64" >&2; exit 1 ;;
esac
[ -f "$conv" ] && [ ! -x "$conv" ] && chmod +x "$conv" 2>/dev/null   # copied over from the Amiga: no x bit
[ -x "$conv" ] || { echo "$conv not found (it lies next to this script)" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$out"

case $mode in
gog)
    "$conv" gog "$src" "$out"
    ;;
wav|cd)
    if [ "$mode" = cd ]; then
        wavs=$tmp
        for t in 2 3 4 5 6 7 8; do
            f=$(printf '%s/track%02d.wav' "$wavs" "$t")
            echo "Reading track $t from $src ..."
            if command -v cdparanoia >/dev/null 2>&1; then
                cdparanoia -q -d "$src" "$t" "$f"
            elif command -v icedax >/dev/null 2>&1; then
                icedax -D "$src" -t "$t" -q "$f"
            else
                echo "Neither cdparanoia nor icedax found (e.g. sudo apt install cdparanoia)" >&2
                exit 1
            fi
        done
    else
        wavs=$src
    fi
    for t in 02 03 04 05 06 07 08; do
        f=$wavs/track$t.wav
        [ -f "$f" ] || { echo "$f is missing" >&2; exit 1; }
        "$conv" wav "$f" "$out/track$t.raw"
        echo "Track $t: done"
    done
    ;;
esac
echo "Finished. Copy $out/track02.raw ... track08.raw into the drawer Screamer/MUSIC on the Amiga."
