/*
 * amiga.h - the Amiga build (AMIGA): what the game's source calls beyond SDL,
 * and what the parts of port/amiga/ call of one another.
 */
#ifndef OS_AMIGA_H
#define OS_AMIGA_H

#include <stdint.h>

/* the picture (palette numbers, a byte a pixel, w x h) and its palette (256
   of 0x..RRGGBB) to the screen; the screen is opened, or opened again, at the
   picture's size (main.c's show_pixels, as the MiSTer's mister_show) */
void amiga_show(const void *pixels, const uint32_t *pal, int w, int h);
/* the race's pictures without a copy (the 68080's SAGA: $DFF1EC = the chunky picture shown): `pixels` shown as it is
   and the next of three buffers (FB_MAXW x rows bytes each) handed back to draw into; NULL = not possible here (then
   amiga_show).  Any amiga_show puts the system's picture back first.  OS_SAGA=0: never */
uint8_t *amiga_flip(const uint8_t *pixels, const uint32_t *pal, int w, int h, uint32_t bytes);

/* OS_PHASES=1: where a picture's time goes, every 50 pictures -- the game (input, simulation), the
   backdrop (mark 1), the scene's geometry (2), the painting (5), the rest (HUD ...) and the copy to
   the screen.  The marks are main.c's MISTER_MARK places */
void amiga_mark(int k);
void amiga_geo_split(uint64_t pieces, uint64_t others, int nothers);   /* the geometry: the track's pieces, the rest */

/* OS_CCC=1 (the Vampire's 68080 only: its cycle counter, movec ccc): cycles summed in slots 0..7 between
   AMIGA_CCC_IN / AMIGA_CCC_OUT, printed with OS_PHASES.  Elsewhere (a 68060 traps on it) never set it */
extern int g_ccc_on;
extern uint32_t g_ccc_sum[8];
#if defined(AMIGA) && !defined(OS_MOS)
static inline uint32_t amiga_ccc(void) { uint32_t v; __asm__ volatile(".short 0x4e7a,0x0809\n\tmove.l %%d0,%0" : "=d"(v) : : "d0"); return v; }
#define AMIGA_CCC_IN(t)     uint32_t t = g_ccc_on ? amiga_ccc() : 0
#define AMIGA_CCC_OUT(t, k) do { if (g_ccc_on) g_ccc_sum[k] += amiga_ccc() - (t); } while (0)
#else
#define AMIGA_CCC_IN(t)     ((void)0)
#define AMIGA_CCC_OUT(t, k) ((void)0)
#endif

/* ---- port/amiga/ inside ---- */
void amiga_video_close(void);
void amiga_video_pump(void);            /* the window's messages: keys, mouse */
void amiga_video_mouse(int relative);   /* SDL_SetRelativeMouseMode */
void amiga_key(unsigned code, unsigned qual);
void amiga_keys_released(void);
void amiga_mouse_moved(int dx, int dy);
void amiga_quit_event(void);

int  amiga_audio_init(void);            /* 0 = there is sound */
void amiga_audio_close(void);

/* the log: stderr, and with OS_SERIAL set the serial port too (the emulator's tests) */
void (amiga_log)(const char *fmt, ...);

#endif
