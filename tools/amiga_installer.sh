#!/usr/bin/env bash
# The installation package dist/amiga/AmiScreamer_Install + AmiScreamer_Install_v1.x.lha (NO data of the original game): the game's programs (68040,
# 68060, 68080, MorphOS), amiscreamer_server(_mos, Linux _x64 / _arm64), the installer script "Install!" and the READMEs (installer_amiga/, ISO-8859-1
# in the package), the icons (Install!.info: tools/mkicon.py from installer_amiga/install_icon_src.info), the MUI
# launcher and its catalog (tools/amiga_launcher.sh), and the installer's helper amiscreamer_inst (installer_amiga/inst/:
# configuration, title logo, music, GOG; 68020 + FPU) -> port/build_amiga/inst/.
#   tools/amiga_installer.sh [--nobuild]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AV="v$(cat "$ROOT/VERSION_AMIGA")"                 # the archives: <name>_v1.x.lha
cd "$ROOT"
[ "${1:-}" = "--nobuild" ] || tools/amiga_dist.sh >/dev/null
mkdir -p port/build_amiga/inst
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/work -w /work amigadev/crosstools:m68k-amigaos sh -c '
  I=installer_amiga/inst; O=port/build_amiga/inst
  vasmm68k_mot -quiet -m68020 -Fhunk -o $O/inst_68k.o $I/inst_68k.s &&
  m68k-amigaos-gcc -noixemul -m68020 -m68881 -Wl,-u,___stkinit -O2 -Wall -Wno-pointer-sign -DINST_ASM \
    -I/opt/m68k-amigaos/usr/include $I/screamer_inst.c $I/inst_core.c $I/inst_gog.c $I/lzmadec.c $I/md5.c $O/inst_68k.o \
    -o $O/amiscreamer_inst -L/opt/m68k-amigaos/usr/lib -lz -lamiga -lm' >/dev/null 2>&1 \
  || { echo "amiscreamer_inst: the build failed" >&2; exit 1; }
D=dist/amiga/AmiScreamer_Install
F=$D/Files
P=dist/amiga/AmiScreamer
rm -rf "$D" "$D.info" dist/amiga/AmiScreamer_Install.zip dist/amiga/AmiScreamer_Install.lha dist/amiga/AmiScreamer_Install_v*.lha
mkdir -p "$F/Catalogs/deutsch" "$D/Linux"
cp $P/amiscreamer_040 $P/amiscreamer_060 $P/amiscreamer_080 $P/amiscreamer_mos $P/amiscreamer_server \
   $P/amiscreamer_server_mos $P/amiscreamer_launcher $P/amiscreamer_launcher.info "$F/"
cp $P/Catalogs/deutsch/amiscreamer_launcher.catalog "$F/Catalogs/deutsch/"
cp port/build_amiga/inst/amiscreamer_inst "$F/amiscreamer_inst"
iconv -f UTF-8 -t ISO-8859-1 installer_amiga/Install-Screamer > "$D/Install!"
python3 -I tools/mkicon.py retype installer_amiga/install_icon_src.info "$D/Install!.info" Installer APPNAME=Screamer MINUSER=AVERAGE
cp LICENSE "$D/LICENSE"                             # GPL-3.0, given along with the programs
cp installer_amiga/History.txt "$D/History.txt"
for l in de en; do
  iconv -f UTF-8 -t ISO-8859-1 installer_amiga/README_$l > "$D/README_$l"
  cp installer_amiga/readme.info "$D/README_$l.info"
done
# the drawer's window: Install! at the top in the middle, the two READMEs under it (only these three have icons)
python3 -I tools/mkicon.py drawer installer_amiga/drawer_icon_src.info "$D.info" 120 60 244 180
python3 -I tools/mkicon.py place "$D/Install!.info" 98 6
python3 -I tools/mkicon.py place "$D/README_de.info" 34 80
python3 -I tools/mkicon.py place "$D/README_en.info" 144 80
# the game's drawer after the installation: the launcher's big icon at the top in the middle, ReadMe and LICENSE under
# it (Install! copies these icons with the drawer's own, Files/drawer.info, which holds the window)
python3 -I tools/mkicon.py drawer installer_amiga/drawer_icon_src.info "$F/drawer.info" 100 50 292 258
python3 -I tools/mkicon.py place "$F/amiscreamer_launcher.info" 68 6
cp installer_amiga/readme.info "$F/ReadMe.info"; python3 -I tools/mkicon.py place "$F/ReadMe.info" 45 168
cp installer_amiga/readme.info "$F/LICENSE.info"; python3 -I tools/mkicon.py place "$F/LICENSE.info" 180 168
# Linux/: the network servers and the music converter, ready programs (tools/linux_progs.sh), no sources
cp port/build_linux/amiscreamer_server_x64 port/build_linux/amiscreamer_server_arm64 port/build_linux/amiscreamer_music_x64 \
   port/build_linux/amiscreamer_music_arm64 installer_amiga/amiscreamer_music.sh "$D/Linux/"
(cd "$D" && find . -type f | sort | xargs md5sum)
docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT/dist/amiga":/d -w /d "${AMIGA_IMAGE:-amigadev/crosstools:m68k-amigaos}" lha -aq AmiScreamer_Install_$AV.lha AmiScreamer_Install AmiScreamer_Install.info   # LhA for the Amiga
