/*
 * s2_none.c - THE BUILD WITHOUT SCREAMER 2 (amiga/Makefile NO_S2=1, tools/qemu_test.sh).  Screamer 2's routines
 * (s2_hooks.c) are not in the program, and with OS_NO_S2 os_game() is the constant 1 (port.h), so the compiler leaves
 * main.c's Screamer 2 paths out.  These are the calls left on paths it cannot see are never taken (the pause
 * screen's, the volumes'); each answers 0 / does nothing.
 */
#include <stdint.h>
#include <stddef.h>
#include "../src/s2_port.h"

void s2_sound_pause(float dt, int on) { (void)dt; (void)on; }
int s2_volume(int which) { (void)which; return 0; }
void s2_volume_set(int which, int v) { (void)which; (void)v; }
