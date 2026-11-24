/*
 * mos_stubs.c - THE MORPHOS BUILD's stand-ins for what the 68k builds take from their vasm files and their arena:
 *  - the driving step's numbers (game_68k.s g_dt_smooth ..., the 68k builds' vasm reads them there);
 *  - the window's bigger pixels (mem_68k.s scale_row68k) and rows in the screen's format (win_68k.s), the arena's aligned blocks (sys/arena.c), AGA's c2p (no
 *    AGA on MorphOS: never called);
 *  - setenv / unsetenv: MorphOS' libnix has none -- the program's own table, getenv (wrapped) asks it first, then
 *    the C library's (ENV:);
 *  - the 68k builds' sound devices (snd_68k.s amiga_audio_*): here SDL's audio is mos_audio.c's.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

float g_dt_smooth = 0.02f, g_dt_raw = 0.02f, g_dt500 = 10.0f, g_dt1000 = 20.0f, g_dt2000 = 40.0f, g_dt6000 = 120.0f;

/* the window's rows into the screen's pixel format (the 68k builds: win_68k.s; here the PPC loops) */
void win_row16x1(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *t)
{
    for (uint32_t x = 0; x < n; x += 4, s += 4, d += 2) {
        uint32_t a = t[s[0]], b = t[s[1]], c = t[s[2]], e = t[s[3]];
        d[0] = (a & 0xffff0000u) | (b & 0xffffu);
        d[1] = (c & 0xffff0000u) | (e & 0xffffu);
    }
}
void win_row32x1(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *t)
{
    for (uint32_t x = 0; x < n; x += 4, s += 4, d += 4) {
        d[0] = t[s[0]]; d[1] = t[s[1]]; d[2] = t[s[2]]; d[3] = t[s[3]];
    }
}
void win_row32x2(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *t, uint32_t bpr)
{
    win_row32x1(d, s, n, t);
    memcpy((uint8_t *)d + bpr, d, n * 4);
}
void scale_row68k(uint8_t *dst, const uint8_t *src, uint32_t w, uint32_t n)
{
    for (uint32_t i = 0; i < w; i++) for (uint32_t k = 0; k < n; k++) *dst++ = src[i];
}
void *arena_alloc_aligned(size_t n, uint32_t align)
{
    uint8_t *v = malloc(n + align);
    return v ? (void *)(((uintptr_t)v + align - 1) & ~(uintptr_t)(align - 1)) : NULL;
}
void arena_where(char *out, int n) { snprintf(out, (size_t)n, "the C library's (MorphOS)"); }
void c2p_init(uint32_t w, uint32_t h, uint32_t bplsize) { (void)w; (void)h; (void)bplsize; }
void c2p_conv(const uint8_t *chunky, uint8_t *planes) { (void)chunky; (void)planes; }
void c2pl_delta(const uint8_t *c, uint8_t *p, uint8_t *r, uint32_t n, uint32_t b, uint32_t w) { (void)c; (void)p; (void)r; (void)n; (void)b; (void)w; }
int amiga_audio_init(void) { return 0; }
void amiga_audio_close(void) { }

/* the environment */
static struct { char *name, *value; } s_env[256];
static int s_nenv;
char *__real_getenv(const char *name);
char *__wrap_getenv(const char *name)
{
    for (int i = 0; i < s_nenv; i++) if (!strcmp(s_env[i].name, name)) return s_env[i].value;   /* (NULL: unset here) */
    return __real_getenv(name);
}
int setenv(const char *name, const char *value, int overwrite)
{
    for (int i = 0; i < s_nenv; i++)
        if (!strcmp(s_env[i].name, name)) {
            if (!overwrite && s_env[i].value) return 0;
            free(s_env[i].value);
            s_env[i].value = strdup(value);
            return 0;
        }
    if (!overwrite && __real_getenv(name)) return 0;
    if (s_nenv >= 256) return -1;
    s_env[s_nenv].name = strdup(name);
    s_env[s_nenv].value = strdup(value);
    s_nenv++;
    return 0;
}
void unsetenv(const char *name)
{
    for (int i = 0; i < s_nenv; i++)
        if (!strcmp(s_env[i].name, name)) { free(s_env[i].value); s_env[i].value = NULL; return; }
    if (s_nenv >= 256) return;
    s_env[s_nenv].name = strdup(name);                 /* (unset over the C library's: remembered as unset) */
    s_env[s_nenv].value = NULL;
    s_nenv++;
}

#ifdef OS_MOS_TRACE
__attribute__((constructor(101))) static void mos_trace_ctor(void) { fprintf(stderr, "mos: constructors\n"); fflush(stderr); }
#endif

#ifndef __OPTIMIZE__
/* (without optimisation, make OPT=-O0: main.c's calls of the 68k builds' vasm kernels stay in the PowerPC program
   although they are never taken there -- named here, never called) */
void car68k(const void *c) { (void)c; }
int ci_faces68k(void *c) { (void)c; return 0; }
void sd68k(const void *x) { (void)x; }
void sw68k(const void *x, float lx, float ly, int over) { (void)x; (void)lx; (void)ly; (void)over; }
#endif
