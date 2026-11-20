# The Amiga build (AmigaOS 3.x, 68040 / 68060 / 68080), run inside the cross toolchain's
# container by tools/amiga_build.sh (amigadev/crosstools:m68k-amigaos: Bebbo's gcc 6.5.0b,
# libnix, the NDK).  From port/:  make -f amiga/Makefile [CPU=68060|68040|68080]
#
#   build_amiga/<cpu>/openscreamer      the program
#
# The game's own objects are joined into one (os_all.o) so that amiga.ld can put marks round
# their statics, which port.c saves and puts back between the program's parts (the MiSTer's
# way: the libraries' statics are not among them).  port/amiga/*.c are linked beside it.

CPU     ?= 68060
# HOT=1 (the default): amiga/amiga_hot.ld -- the vasm kernels inside the main code hunk in phase order (V1200, 080 build:
# geometry 15.2 -> 13.8 ms a picture); HOT=0 the plain link (each vasm section a hunk of its own)
HOT     ?= 1
# ARENAREL=n: the memory field n bytes past the statics, modulo 128 KB (sys/arena.c ARENA_REL; the stack at its start).
# V1200 080 640x400 sweep 0..124 KB by 4 KB and 0..3840 by 256: 51.1..51.7 ms, flat within the noise -- 0
ARENAREL ?= 0
# HOTPAD=n: amiga_hot.ld's hot block n bytes further on.  V1200 080 640x400 sweep 0..7168 by 1024: 53.0..53.5 ms,
# but 3072 56.3 (painting +3 ms); 6144 the best with good neighbours
HOTPAD  ?= 6144
comma   := ,
HOTLD   := -Wl,-T,amiga/amiga_hot.ld -Wl,--defsym,__hot_pad=$(HOTPAD)
# NO_S2=1 (the default): Screamer 1 alone -- Screamer 2's routines (s2_hooks.c: the game's memory as the DOS
# program's, little-endian) are not in the program; amiga/s2_none.c answers main.c's calls of them, and
# os_game() is the constant 1 (port.h): main.c's Screamer 2 branches are left out by the compiler
NO_S2   ?= 1
# DEBUG=1: the build with the test switches (amiscreamer_debug_*, the tests and the benchmark); without it the
# release build, whose test switches are left out (amiga/os_release.h)
DEBUG   ?= 0
OUT     := build_amiga/$(CPU)$(if $(filter 1,$(PMK)),_pmk)$(if $(filter 0,$(HOT)),_cold)$(if $(filter 1,$(DEBUG)),_debug)
RELDEF  := $(if $(filter 1,$(DEBUG)),-DOS_DEBUG=1,-include amiga/os_release.h)
CC      := m68k-amigaos-gcc
LD      := m68k-amigaos-ld

# 68080 (Vampire): the 060's code. -m68080 only with the ApolloCrossDev GCC 6.5.0b (not Bebbo's,
# whose FPU code is faulty) and only when every task that runs C sets the Apollo bit (SR bit 11,
# the AMMX registration) first; without it 68080 code is a Line-A guru on the V1200.
GCCCPU  := $(if $(filter 68080,$(CPU)),68060,$(CPU))

# -fexcess-precision=fast: m68k evaluates in long double (FLT_EVAL_METHOD 2); "standard" would
#   make every float sum an 80-bit one.  Screamer 2's routines (s2_hooks.c) want exactly that,
#   with the FPU at 53 bits (S2_FPU_IN), as the x87 under the game: they get "standard".
# -fbbb without e: its pass "e" drops fintrz fpN,fpN -- (int)x would round, not cut.
# -include m68k_libm.h: the long double maths libnix has not (sinl, cosl, ... from the FPU).
CFLAGS  := -m$(GCCCPU) -mhard-float -O2 -fomit-frame-pointer -fbbb=abcfhilmnprsz0 \
           -std=gnu11 -fno-strict-aliasing -fno-common -fexcess-precision=fast \
           -D_GNU_SOURCE -DAMIGA=1 -DS2_CONVERTED -DOS_OWN_SECTIONS=1 -DOS_PAINTER=1 $(if $(filter 1,$(PMK)),-DPMKON=1) $(if $(filter 68080,$(CPU)),-DOS_V080=1) $(if $(filter 1,$(NO_S2)),-DOS_NO_S2=1) \
           -Iamiga/include -Iamiga -I$(OUT) -include amiga/m68k_libm.h $(RELDEF) \
           -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable \
           -Wno-misleading-indentation -Wno-unused-value
# Screamer 2's arithmetic (see above)
S2FLAGS := -fexcess-precision=standard
# (amiga_path.c: the C library's calls that take a path get it in AmigaDOS's form)
WRAP    := fopen freopen stat opendir mkdir remove rename unlink memcpy malloc calloc realloc free exit
LDFLAGS := -m68020 -m68881 $(if $(filter 1,$(HOT)),$(HOTLD),-Wl$(comma)-T$(comma)amiga/amiga.ld) $(foreach f,$(WRAP),-Wl,--wrap=$(f))
LDLIBS  := -ldebug -lamiga -lm

GAME    := main mesh unr scene drive port controls $(if $(filter 1,$(NO_S2)),,s2_hooks)
AMIGA   := sdl_amiga amiga_video snd_load snd_ahi amiga_path oldargs net $(if $(filter 1,$(NO_S2)),s2_none) span geo mem arena os_math
# the painter's rows: the kernel (vasm), its 64-bit helpers
# c2p.library's 8-bitplane routines (amiga/sys/c2plib, MIT, unchanged): the delta conversion of the AGA picture
C2PL    := $(addprefix $(OUT)/c2pl_,$(addsuffix .o,c2p_8 c2p_8x8 c2p_8x8_mexg c2p_8x8_mexg_040))
ASMOBJ  := $(OUT)/span_68k.o $(OUT)/m64_68k.o $(OUT)/geo_68k.o $(OUT)/pt_68k.o $(OUT)/mem_68k.o $(OUT)/sort_68k.o $(OUT)/hud_68k.o $(OUT)/game_68k.o $(OUT)/pi_68k.o $(OUT)/mixer_68k.o $(OUT)/snd_68k.o $(OUT)/lzw_68k.o $(OUT)/math_68k.o $(OUT)/c2p_68k.o $(OUT)/win_68k.o $(C2PL)
VASM    := vasmm68k_mot -quiet -no-opt -Fhunk

GAMEOBJ := $(addprefix $(OUT)/,$(addsuffix .o,$(GAME)))
AMIOBJ  := $(addprefix $(OUT)/,$(addsuffix .o,$(AMIGA)))

all: $(OUT)/openscreamer

# checked on every build (FORCE), replaced only when the version changed: a new commit, a new number
$(OUT)/os_version.h: FORCE | $(OUT)
	@echo '#define OS_VERSION "$(OS_VERSION)"' > $@.new
	@echo '#define OS_VERSTAG "$$VER: amiscreamer_$(if $(filter 1,$(DEBUG)),debug_)$(patsubst 68%,%,$(CPU)) $(AMI_VER) ($(AMI_DATE))"' >> $@.new
	@cmp -s $@.new $@ || mv $@.new $@; rm -f $@.new

$(OUT):
	mkdir -p $@

HDRS := $(wildcard src/*.h) $(wildcard amiga/*.h) amiga/net/net.h amiga/net/netgame.inc amiga/render/span.h amiga/render/geo.h amiga/render/ptf.h $(OUT)/os_version.h

$(OUT)/%.o: src/%.c $(HDRS) | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@
$(OUT)/s2_hooks.o: src/s2_hooks.c src/s2r_car.h $(HDRS) | $(OUT)
	$(CC) $(CFLAGS) $(S2FLAGS) -c $< -o $@
$(OUT)/net.o: amiga/net/net.c amiga/net/net.h | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@
$(OUT)/%.o: amiga/%.c $(HDRS) | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@
$(OUT)/span.o: amiga/render/span.c amiga/render/span.h | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@
# (the 68080's build: the kernel's own 080 form -- TEX8, AMMX -- tested on the machine before it is used)
$(OUT)/span_68k.o: amiga/render/span_68k.s amiga/render/m64.i | $(OUT)
	cd amiga/render && $(VASM) $(if $(filter 68080,$(CPU)),-m68080,-m68060 -DCPU060=1) $(if $(filter 1,$(PMK)),-DPMKON=1) -o ../../$@ span_68k.s
$(OUT)/geo.o: amiga/render/geo.c amiga/render/geo.h | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@
$(OUT)/geo_68k.o: amiga/render/geo_68k.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/arena.o: amiga/sys/arena.c | $(OUT)
	$(CC) $(CFLAGS) -DARENA_REL=$(ARENAREL) -c $< -o $@
# (the objects whose rule does not name $(HDRS): made again when the release's list changes)
$(addprefix $(OUT)/,net.o span.o geo.o arena.o mem.o os_math.o fpu64_math.o): amiga/os_release.h
$(OUT)/mem.o: amiga/sys/mem.c | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@
# the game's float maths (sin cos tan atan atan2 pow exp from musl in double; os_math.c)
$(OUT)/os_math.o: amiga/sys/os_math.c amiga/sys/fpu64_math.h | $(OUT)
	$(CC) $(CFLAGS) -c $< -o $@
$(OUT)/fpu64_math.o: amiga/sys/fpu64_math.c amiga/sys/fpu64_math.h | $(OUT)
	$(CC) $(CFLAGS) -w -c $< -o $@
$(OUT)/win_68k.o: amiga/sys/win_68k.s | $(OUT)
	$(VASM) -m68020 -o $@ $<
$(OUT)/mem_68k.o: amiga/sys/mem_68k.s | $(OUT)
	$(VASM) $(if $(filter 68080,$(CPU)),-m68080 -DV080=1,-m68060) -o $@ $<
$(OUT)/game_68k.o: amiga/sys/game_68k.s | $(OUT)
	$(VASM) $(if $(filter 68080,$(CPU)),-m68080 -DV080=1,-m68060) -o $@ $<
$(OUT)/mixer_68k.o: amiga/sys/mixer_68k.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/snd_68k.o: amiga/sys/snd_68k.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/lzw_68k.o: amiga/sys/lzw_68k.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/math_68k.o: amiga/sys/math_68k.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/c2pl_%.o: amiga/sys/c2plib/%.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/c2p_68k.o: amiga/sys/c2p_68k.s amiga/sys/c2p/c2p1x1_8_c5_040.s | $(OUT)
	$(VASM) $(if $(filter 68080,$(CPU)),-m68080 -DV080=1,-m68060) -o $@ $<
$(OUT)/pi_68k.o: amiga/render/pi_68k.s | $(OUT)
	$(VASM) -m68060 $(if $(filter 68080,$(CPU)),-DV080=1) -o $@ $<
$(OUT)/hud_68k.o: amiga/sys/hud_68k.s | $(OUT)
	$(VASM) $(if $(filter 68080,$(CPU)),-m68080 -DV080=1,-m68060) -o $@ $<
$(OUT)/sort_68k.o: amiga/render/sort_68k.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/pt_68k.o: amiga/render/pt_68k.s | $(OUT)
	$(VASM) -m68060 -o $@ $<
$(OUT)/m64_68k.o: amiga/render/m64_68k.s | $(OUT)
	$(VASM) -m68060 -DLIBGCC=1 -o $@ $<

$(OUT)/os_all.o: $(GAMEOBJ)
	$(LD) -r -o $@ $^

$(OUT)/openscreamer: $(OUT)/os_all.o $(AMIOBJ) $(ASMOBJ) amiga/amiga.ld
	$(CC) $(LDFLAGS) -Wl,-Map,$@.map $(OUT)/os_all.o $(AMIOBJ) $(ASMOBJ) -o $@ $(LDLIBS)
	@m68k-amigaos-size $@ 2>/dev/null || true

clean:
	rm -rf $(OUT)

.PHONY: all clean FORCE
FORCE:
