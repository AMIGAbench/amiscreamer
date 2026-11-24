/*
 * s2_none.c - THE BUILD WITHOUT SCREAMER 2 (amiga/Makefile NO_S2=1, tools/qemu_test.sh).  Screamer 2's routines
 * (s2_hooks.c) are not in the program, and with OS_NO_S2 os_game() is the constant 1 (port.h), so the compiler leaves
 * main.c's Screamer 2 paths out.  These are the calls left on paths it cannot see are never taken (the pause
 * screen's, the volumes'); each answers 0 / does nothing.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "../src/s2_port.h"

void s2_sound_pause(float dt, int on) { (void)dt; (void)on; }
int s2_volume(int which) { (void)which; return 0; }
void s2_volume_set(int which, int v) { (void)which; (void)v; }

#ifndef __OPTIMIZE__
/* Without optimisation (make OPT=-O0, a debugger's build) the compiler keeps main.c's Screamer 2 paths although
 * os_game() is the constant 1, and they call these: here they are, answering 0 / doing nothing.  The release (-O2)
 * leaves the paths out and does not have them. */
int s2_level, s2_laps, s2_mode, s2_ghost_on;
unsigned s2_race_seed;
char s2_name[4];
const int s2_league[4][7], s2_track_order[7];
int s2_race_start(int track, int condition, int ncars, const int *team, const int *model)
{ (void)track; (void)condition; (void)ncars; (void)team; (void)model; return 0; }
void s2_sound_start(int track) { (void)track; }
void s2_frame(float step) { (void)step; }
void s2_frame_times(float raw) { (void)raw; }
void s2_car(int i, s2_car_state *c) { (void)i; memset(c, 0, sizeof *c); }
float s2_env_rate(void) { return 0.0f; }
void s2_camera(s2_camera_state *c) { memset(c, 0, sizeof *c); }
void s2_mirror_set(int on) { (void)on; }
int s2_mirror(s2_camera_state *c) { (void)c; return 0; }
void s2_hud(s2_hud_state *h) { memset(h, 0, sizeof *h); }
void s2_robot(int on) { (void)on; }
int s2_puffs(s2_puff *out, int max) { (void)out; (void)max; return 0; }
int s2_sparks(s2_spark *out, int max) { (void)out; (void)max; return 0; }
int s2_obstacles(s2_obstacle *out, int max) { (void)out; (void)max; return 0; }
int s2_anims(s2_anim *out, int max) { (void)out; (void)max; return 0; }
int s2_laps_done(int i) { (void)i; return 0; }
int s2_touched(void) { return 0; }
void s2_race_music(void) {}
void s2_attract_step(void) {}
int s2_attack_plan(int track, int *team, int *model) { (void)track; (void)team; (void)model; return 0; }
int s2_replay_offered(void) { return 0; }
void s2_feel_read(s2_feel *f) { memset(f, 0, sizeof *f); }
int s2_replaying(void) { return 0; }
int s2_replay_band(int *team, int *view) { (void)team; (void)view; return 0; }
int s2_champ_weather(int league, int race, int *left, unsigned number) { (void)league; (void)race; (void)left; (void)number; return 0; }
int s2_results(s2_result *r) { (void)r; return 0; }
int s2_records_enter(void) { return -1; }
const void *s2_records_list(void) { return NULL; }
void s2_splits_forget(void) {}
int s2_player(void) { return 0; }
#endif
