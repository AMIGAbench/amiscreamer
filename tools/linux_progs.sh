#!/usr/bin/env bash
# The Linux programs of the packages, x86-64 and arm64 (e.g. a Raspberry Pi), static so they run on any
# distribution, built in a Debian container with its cross compiler:
#   amiscreamer_server_x64 / _arm64   the network server (the POSIX path of port/amiga/net/net.c)
#   amiscreamer_music_x64 / _arm64    the music converter (CD tracks / GOG installer -> MUSIC/trackNN.raw), from
#                                     installer_amiga/inst/ (the same core as amiscreamer_inst)
#   tools/linux_progs.sh   ->  port/build_linux/
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p port/build_linux
docker run --rm -v "$ROOT":/w -w /w debian:bookworm-slim sh -c '
  set -e
  dpkg --add-architecture arm64
  apt-get update -qq >/dev/null
  apt-get install -y -qq --no-install-recommends gcc libc6-dev zlib1g-dev gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
    zlib1g-dev:arm64 >/dev/null
  O=port/build_linux
  NET="port/amiga/net/server.c port/amiga/net/net.c"
  I=installer_amiga/inst; MUS="$I/music_main.c $I/inst_core.c $I/inst_gog.c $I/lzmadec.c $I/md5.c"
  gcc -O2 -static -DNET_SERVER -o $O/amiscreamer_server_x64 $NET 2>/dev/null
  aarch64-linux-gnu-gcc -O2 -static -DNET_SERVER -o $O/amiscreamer_server_arm64 $NET 2>/dev/null
  gcc -O2 -static -o $O/amiscreamer_music_x64 $MUS -lz -lm
  aarch64-linux-gnu-gcc -O2 -static -o $O/amiscreamer_music_arm64 $MUS -L/usr/lib/aarch64-linux-gnu -lz -lm
  strip $O/amiscreamer_server_x64 $O/amiscreamer_music_x64
  aarch64-linux-gnu-strip $O/amiscreamer_server_arm64 $O/amiscreamer_music_arm64
  chown '"$(id -u):$(id -g)"' $O/amiscreamer_*'
file port/build_linux/amiscreamer_*
