/*
 * amiga_video.c - THE PICTURE on the Amiga.
 *
 * The game draws palette numbers, a byte a pixel (fb), and hands them over
 * with their palette once a picture (amiga_show).  Here they go to a screen
 * of their own, 8 bits deep:
 *
 *   RTG   (cybergraphics.library: CyberGraphX, Picasso96) a screen of the
 *         picture's size, or the next bigger one with the picture in the
 *         middle; the bytes copied in with LockBitMap (WritePixelArray8 when
 *         the bitmap will not be locked).
 *   AGA   no RTG, or OS_AGA=1: PAL, 320 x 200 lores (640 x 400 hires
 *         interlaced for the high resolution), 8 bitplanes:
 *         two sets of contiguous planes in chip memory, the picture made
 *         into the hidden one with Kalms' c2p (sys/c2p_68k.s), shown at the
 *         next frame with ChangeScreenBuffer (no tearing); WriteChunkyPixels
 *         only when that cannot be had (a width not a multiple of 32, no
 *         chip memory, no screen buffers).
 *
 * A backdrop window without border covers the screen: its messages are the
 * keys (IDCMP_RAWKEY) and the mouse.
 *
 *   WINDOW  OS_WINDOW=1..3 (--window / --scale N, the launcher's): a window on the Workbench
 *         (the default public screen), the picture 1x, 2x or 3x, put in with cybergraphics' WriteLUTPixelArray
 *         through the palette; its close gadget ends the game.  Not with AGA.  The palette is loaded only when it has
 * changed since the last picture.
 */
#include <exec/types.h>
#include <exec/memory.h>
#include <exec/execbase.h>
#include <intuition/intuition.h>
#include <intuition/screens.h>
#include <graphics/modeid.h>
#include <graphics/gfxbase.h>
#include <graphics/displayinfo.h>
#include <cybergraphx/cybergraphics.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <proto/graphics.h>
#include <proto/cybergraphics.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <SDL.h>
#include "amiga.h"

extern struct Library *CyberGfxBase;

static struct Screen *g_scr;
static struct Window *g_win;
static int g_inwin;                     /* the picture in a window on the Workbench (g_scr NULL then) */
static int g_wscale;                    /* its scale 1..3 */
static ULONG g_lut[256];                /* its palette, 0x00RRGGBB */
static uint8_t *g_wbuf;                 /* the scaled picture, or the picture in the screen's pixel format */
/* The program's own conversion into the Workbench's pixel format (16/32 bits): P96 takes
 * ~180 ns a pixel for WriteLUTPixelArray (V1200: 320x200 11.6 ms, 2x 54 ms); here a table of finished pixels, the
 * scaling in the same pass (win_68k.s), then WritePixelArray RECTFMT_RAW (a copy only). 0 = WriteLUTPixelArray
 * (an 8-bit Workbench, a format not known). */
static int g_wbpp;                      /* 2 or 4 bytes a pixel, 0 = the LUT way */
static ULONG g_wfmt;                    /* PIXFMT_* of the window's bitmap */
static uint32_t g_wpix[256];            /* pixels in the screen's format (16 bits: low, doubled high for 2x) */
static int g_wpix_dirty;
#ifndef RECTFMT_RAW
#define RECTFMT_RAW 5UL                 /* data in the target bitmap's format (CGX 4, P96) */
#endif
static uint32_t g_wbuf_n;
static UWORD *g_blank;                  /* an empty pointer (chip memory) */
static int g_w, g_h;                    /* the picture's size the screen is for */
static int g_sw, g_sh, g_x0, g_y0;      /* the screen's size, where the picture is on it */
static int g_rtg;                       /* the screen is an RTG one */
static int g_mouse_rel;
static uint32_t g_pal_shown[256];
static int g_pal_valid;
static ULONG g_pal32[2 + 256 * 3];      /* LoadRGB32's table */
/* AGA, double-buffered */
void c2p_init(uint32_t w, uint32_t h, uint32_t bplsize);
void c2p_conv(const uint8_t *chunky, uint8_t *planes);
#ifdef OS_V080
/* the 68080's AMMX c2p (c2p_conv080, sys/c2p_68k.s): 320x200 only, after its test at the start --
   the same bytes as Kalms' on a random picture; OS_C2P080=0: Kalms' always */
void c2p_conv080(const uint8_t *chunky, uint8_t *planes, uint32_t n64);
int span_ammx_on(void);
static int g_c2p080;
static int c2p080_test(void)
{
    enum { W = 320, H = 200, BUF = W / 8 * H * 8 };
    uint8_t *src = AllocVec(W * H, MEMF_ANY), *a = AllocVec(BUF, MEMF_ANY), *b = AllocVec(BUF, MEMF_ANY);
    int ok = 0;
    if (src && a && b) {
        uint32_t x = 0x1995c2b1u;
        for (int i = 0; i < W * H; i++) { x = x * 1664525u + 1013904223u; src[i] = (uint8_t)(x >> 24); }
        c2p_conv(src, a);
        c2p_conv080(src, b, W * H / 64);
        ok = !memcmp(a, b, BUF);
    }
    if (src) FreeVec(src);
    if (a) FreeVec(a);
    if (b) FreeVec(b);
    return ok;
}
#endif
static uint8_t *g_aga_mem, *g_aga_pl[2];
static ULONG g_aga_memsize, g_aga_bpl;
static struct BitMap g_aga_bm[2];
static struct ScreenBuffer *g_aga_sb[2];
static struct MsgPort *g_aga_safe;
static int g_aga, g_aga_cur, g_aga_busy;      /* the double-buffered way is on; the buffer shown; a change on its way */
/* THE DELTA C2P: each buffer's planes show the picture of two pictures ago -- its copy in Fast RAM (the reference)
   against the new one, 32 pixels at a time; only what differs goes into chip memory (c2p.library's delta conversion,
   sys/c2plib, MIT: c2pl_delta in sys/c2p_68k.s). When nearly everything changes (a race on the move) that costs more
   than the whole picture: both ways are timed, the faster one used, the other tried again every 16th picture (every
   64th while delta takes less than half the time).
   OS_C2PDIRTY=0: the whole picture every time */
static uint8_t *g_aga_shmem, *g_aga_sh[2];
static int g_aga_sh_ok[2], g_aga_kfull;          /* a buffer's copy valid; Kalms' set up for the whole picture */
static int g_c2p_delta = 1;                      /* the delta way in use */
static unsigned g_c2p_f;
static uint64_t g_c2p_tw, g_c2p_td;              /* the two ways' times (counter ticks, averaged) */
void c2pl_delta(const uint8_t *chunky, uint8_t *planes, uint8_t *ref, uint32_t npix, uint32_t bplsize, uint32_t rowbytes);

static void aga_wait_safe(void)
{
    if (!g_aga_busy) return;
    while (!GetMsg(g_aga_safe)) WaitPort(g_aga_safe);
    g_aga_busy = 0;
}

void (amiga_log)(const char *fmt, ...)
{
    char buf[400];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    fputs(buf, stderr);
    fputc('\n', stderr);
}

static void flip_off(void);
static void flip_free(void);
void amiga_video_close(void)
{
    flip_off();
    flip_free();
    if (g_win) {
        if (!g_inwin) ClearPointer(g_win);
        CloseWindow(g_win);
        g_win = NULL;
    }
    g_inwin = 0;
    if (g_wbuf) { FreeVec(g_wbuf); g_wbuf = NULL; g_wbuf_n = 0; }
    g_wbpp = 0;
    if (g_aga) {
        aga_wait_safe();
        for (int k = 0; k < 2; k++)
            if (g_aga_sb[k]) { FreeScreenBuffer(g_scr, g_aga_sb[k]); g_aga_sb[k] = NULL; }
        g_aga = 0;
    }
    if (g_scr) {
        CloseScreen(g_scr);
        g_scr = NULL;
    }
    if (g_aga_mem) { FreeMem(g_aga_mem, g_aga_memsize); g_aga_mem = NULL; }
    if (g_aga_shmem) { FreeVec(g_aga_shmem); g_aga_shmem = NULL; }
    g_aga_sh_ok[0] = g_aga_sh_ok[1] = 0;
    if (g_aga_safe) { DeleteMsgPort(g_aga_safe); g_aga_safe = NULL; }
    if (g_blank) {
        FreeVec(g_blank);
        g_blank = NULL;
    }
    g_w = g_h = 0;
    g_pal_valid = 0;
}

/* an 8-bit RTG mode at least w x h, INVALID_ID if there is none */
static ULONG rtg_mode(int w, int h, int *mw, int *mh)
{
    if (!CyberGfxBase && !(CyberGfxBase = OpenLibrary((CONST_STRPTR)CYBERGFXNAME, 41))) return INVALID_ID;
    static const int cand[][2] = {{0, 0}, {320, 240}, {640, 400}, {640, 480}, {800, 600}};
    for (unsigned i = 0; i < sizeof cand / sizeof cand[0]; i++) {
        int cw = i ? cand[i][0] : w, ch = i ? cand[i][1] : h;
        if (cw < w || ch < h) continue;
        struct TagItem t[] = {{CYBRBIDTG_NominalWidth, (ULONG)cw}, {CYBRBIDTG_NominalHeight, (ULONG)ch},
                              {CYBRBIDTG_Depth, 8}, {TAG_DONE, 0}};
        ULONG id = BestCModeIDTagList(t);
        if (id == INVALID_ID || !IsCyberModeID(id) || GetCyberIDAttr(CYBRIDATTR_DEPTH, id) != 8) continue;
        *mw = (int)GetCyberIDAttr(CYBRIDATTR_WIDTH, id);
        *mh = (int)GetCyberIDAttr(CYBRIDATTR_HEIGHT, id);
        if (*mw >= w && *mh >= h) return id;
    }
    return INVALID_ID;
}

static int want_aga(void)
{
    const char *v = getenv("OS_AGA");
    return v && *v && *v != '0';
}

/* OS_WINDOW=1..3: the scale of the window wanted (0: a screen) -- not with AGA, and only with cybergraphics */
static int want_window(void)
{
    static int v = -1;
    if (v < 0) {
        const char *e = getenv("OS_WINDOW");
        v = e && *e ? atoi(e) : 0;
        v = v < 0 ? 0 : v > 3 ? 3 : v;
        if (v && want_aga()) { (amiga_log)("amiga: a window only on RTG (not with AGA) -- the screen"); v = 0; }
        if (v && !CyberGfxBase && !(CyberGfxBase = OpenLibrary((CONST_STRPTR)CYBERGFXNAME, 41))) {
            (amiga_log)("amiga: a window needs cybergraphics.library -- the screen");
            v = 0;
        }
    }
    return v;
}

static int window_open(int w, int h, int n)
{
    struct Screen *pub = LockPubScreen(NULL);
    if (!pub) { (amiga_log)("amiga: no public screen for the window"); return -1; }
    struct TagItem wa[] = {
        {WA_PubScreen, (ULONG)pub}, {WA_InnerWidth, (ULONG)(w * n)}, {WA_InnerHeight, (ULONG)(h * n)},
        {WA_Title, (ULONG)"AmiScreamer"}, {WA_DragBar, TRUE}, {WA_DepthGadget, TRUE}, {WA_CloseGadget, TRUE},
        {WA_Activate, TRUE}, {WA_RMBTrap, TRUE}, {WA_NoCareRefresh, TRUE}, {WA_SimpleRefresh, TRUE},
        {WA_ReportMouse, TRUE},
        {WA_IDCMP, IDCMP_RAWKEY | IDCMP_INACTIVEWINDOW | IDCMP_CLOSEWINDOW | IDCMP_MOUSEMOVE | IDCMP_DELTAMOVE}, {TAG_DONE, 0}};
    g_win = OpenWindowTagList(NULL, wa);
    UnlockPubScreen(NULL, pub);
    if (!g_win) { (amiga_log)("amiga: no window of %dx%d on the Workbench", w * n, h * n); return -1; }
    g_wfmt = GetCyberMapAttr(g_win->RPort->BitMap, CYBRMATTR_PIXFMT);
    g_wbpp = 0;
    if (GetCyberMapAttr(g_win->RPort->BitMap, CYBRMATTR_ISCYBERGFX)) {
        if (g_wfmt >= PIXFMT_RGB15 && g_wfmt <= PIXFMT_BGR16PC) g_wbpp = 2;
        else if (g_wfmt >= PIXFMT_ARGB32 && g_wfmt <= PIXFMT_RGBA32) g_wbpp = 4;
    }
    if (g_wbpp) {
        g_wbuf_n = (uint32_t)(w * n) * (uint32_t)(h * n) * (uint32_t)g_wbpp;
        if (!(g_wbuf = AllocVec(g_wbuf_n, MEMF_ANY | MEMF_CLEAR))) { g_wbuf_n = 0; g_wbpp = 0; }   /* no memory: the LUT way */
    }
    g_wpix_dirty = 1;
    if (!g_wbpp && n > 1) {
        g_wbuf_n = (uint32_t)(w * n) * (uint32_t)(h * n);
        if (!(g_wbuf = AllocVec(g_wbuf_n, MEMF_ANY))) { CloseWindow(g_win); g_win = NULL; return -1; }
    }
    amiga_log("amiga: window conversion %s (pixel format %lu)", g_wbpp ? (g_wbpp == 2 ? "own, 16 bits" : "own, 32 bits") :
              "WriteLUTPixelArray", (unsigned long)g_wfmt);
    g_inwin = 1; g_wscale = n;
    g_w = w; g_h = h; g_sw = w * n; g_sh = h * n; g_x0 = g_y0 = 0;
    g_rtg = 0; g_pal_valid = 0;
    amiga_log("amiga: a window of %dx%d on the Workbench for a picture of %dx%d (%dx)", w * n, h * n, w, h, n);
    return 0;
}

static int video_open(int w, int h)
{
    amiga_video_close();
    if (want_window()) return window_open(w, h, want_window());
    ULONG id = INVALID_ID;
    int mw = w, mh = h;
    g_rtg = 0;
    if (!want_aga()) {
        id = rtg_mode(w, h, &mw, &mh);
        g_rtg = id != INVALID_ID;
    }
    if (id == INVALID_ID) {                                          /* AGA */
        id = w > 320 ? (PAL_MONITOR_ID | HIRESLACE_KEY) : (PAL_MONITOR_ID | LORES_KEY);
        if (ModeNotAvailable(id)) id = w > 320 ? HIRESLACE_KEY : LORES_KEY;   /* (the default monitor) */
        mw = w; mh = h;
    }
    memset(g_pal32, 0, sizeof g_pal32);                              /* black until the first picture */
    g_pal32[0] = 256UL << 16;
    /* AGA: the planes of two pictures in chip memory, 16-aligned (FMODE 3), each set contiguous */
    int aga_buf = !g_rtg && (w & 31) == 0 && !(getenv("OS_C2P") && getenv("OS_C2P")[0] == '0');
    if (aga_buf) {
        g_aga_bpl = (ULONG)(w / 8 * h);
        g_aga_memsize = 2 * 8 * g_aga_bpl + 16;
        if (!(g_aga_mem = AllocMem(g_aga_memsize, MEMF_CHIP | MEMF_CLEAR)) || !(g_aga_safe = CreateMsgPort())) {
            if (g_aga_mem) { FreeMem(g_aga_mem, g_aga_memsize); g_aga_mem = NULL; }
            aga_buf = 0;
        } else {
            uint8_t *b = (uint8_t *)(((ULONG)g_aga_mem + 15) & ~15ul);
            for (int k = 0; k < 2; k++) {
                g_aga_pl[k] = b + k * 8 * g_aga_bpl;
                InitBitMap(&g_aga_bm[k], 8, (UWORD)w, (UWORD)h);
                for (int i = 0; i < 8; i++) g_aga_bm[k].Planes[i] = (PLANEPTR)(g_aga_pl[k] + i * g_aga_bpl);
            }
        }
    }
    ULONG err = 0;
    struct TagItem sa[] = {
        {aga_buf ? SA_BitMap : TAG_IGNORE, (ULONG)&g_aga_bm[0]},
        {SA_DisplayID, id}, {SA_Width, (ULONG)mw}, {SA_Height, (ULONG)mh}, {SA_Depth, 8},
        {SA_Type, CUSTOMSCREEN}, {SA_Quiet, TRUE}, {SA_ShowTitle, FALSE}, {SA_Draggable, FALSE},
        {SA_AutoScroll, FALSE}, {SA_Exclusive, TRUE}, {SA_Colors32, (ULONG)g_pal32},
        {SA_Title, (ULONG)"AmiScreamer"}, {SA_ErrorCode, (ULONG)&err}, {TAG_DONE, 0}};
    if (!(g_scr = OpenScreenTagList(NULL, sa))) {
        (amiga_log)("amiga: no screen of %dx%d (mode %08lx, error %lu)", mw, mh, (unsigned long)id, (unsigned long)err);
        return -1;
    }
    struct TagItem wa[] = {
        {WA_CustomScreen, (ULONG)g_scr}, {WA_Left, 0}, {WA_Top, 0},
        {WA_Width, (ULONG)mw}, {WA_Height, (ULONG)mh},
        {WA_Flags, WFLG_BACKDROP | WFLG_BORDERLESS | WFLG_ACTIVATE | WFLG_RMBTRAP | WFLG_NOCAREREFRESH | WFLG_REPORTMOUSE},
        {WA_IDCMP, IDCMP_RAWKEY | IDCMP_INACTIVEWINDOW | IDCMP_MOUSEMOVE | IDCMP_DELTAMOVE}, {TAG_DONE, 0}};
    if (!(g_win = OpenWindowTagList(NULL, wa))) {
        amiga_video_close();
        (amiga_log)("amiga: no window on the screen");
        return -1;
    }
    if ((g_blank = AllocVec(6 * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR))) SetPointer(g_win, g_blank, 1, 16, 0, 0);
    if (aga_buf) {
        g_aga_sb[0] = AllocScreenBuffer(g_scr, &g_aga_bm[0], 0);
        g_aga_sb[1] = AllocScreenBuffer(g_scr, &g_aga_bm[1], 0);
        if (g_aga_sb[0] && g_aga_sb[1]) {
            for (int k = 0; k < 2; k++) g_aga_sb[k]->sb_DBufInfo->dbi_SafeMessage.mn_ReplyPort = g_aga_safe;
            g_aga = 1; g_aga_cur = 0; g_aga_busy = 0;
            c2p_init((uint32_t)w, (uint32_t)h, g_aga_bpl);
            g_aga_kfull = 1;
            {   const char *e = getenv("OS_C2PDIRTY");
                g_aga_sh_ok[0] = g_aga_sh_ok[1] = 0;
                g_c2p_delta = 1; g_c2p_f = 0; g_c2p_tw = g_c2p_td = 0;
                if (!(e && e[0] == '0') && (w * h) % 32 == 0 && (g_aga_shmem = AllocVec((ULONG)(2 * w * h + 16), MEMF_ANY))) {
                    g_aga_sh[0] = (uint8_t *)(((ULONG)g_aga_shmem + 15) & ~15ul);
                    g_aga_sh[1] = g_aga_sh[0] + w * h;
                }
                amiga_log("amiga: c2p %s", g_aga_shmem ? "delta (c2p.library's) or the whole picture, the faster" : "whole pictures");
            }
#ifdef OS_V080
            {   const char *e = getenv("OS_C2P080");
                g_c2p080 = w == 320 && h == 200 && !(e && e[0] == '0') && span_ammx_on() && c2p080_test();
                amiga_log("amiga: c2p %s", g_c2p080 ? "AMMX (the same bytes as Kalms')" : "Kalms' c2p1x1_8_c5_040");
            }
#endif
        } else {                                /* (single-buffered then, WriteChunkyPixels) */
            for (int k = 0; k < 2; k++) if (g_aga_sb[k]) { FreeScreenBuffer(g_scr, g_aga_sb[k]); g_aga_sb[k] = NULL; }
        }
    }
    LoadRGB32(&g_scr->ViewPort, g_pal32);
    SetRast(&g_scr->RastPort, 0);
    g_w = w; g_h = h; g_sw = mw; g_sh = mh;
    g_x0 = (mw - w) / 2 & ~3; g_y0 = (mh - h) / 2;
    g_pal_valid = 0;
    amiga_log("amiga: screen %dx%d %s (mode %08lx) for a picture of %dx%d%s", mw, mh, g_rtg ? "RTG" : "AGA", (unsigned long)id, w, h,
              g_rtg ? "" : g_aga ? ", Kalms c2p into two buffers in chip memory" : ", WriteChunkyPixels");
    return 0;
}

static void load_palette(const uint32_t *pal)
{
    if (g_pal_valid && !memcmp(pal, g_pal_shown, sizeof g_pal_shown)) return;
    memcpy(g_pal_shown, pal, sizeof g_pal_shown);
    g_pal_valid = 1;
    if (g_inwin) {                                      /* (the window: the colours go with the pixels) */
        for (int i = 0; i < 256; i++) g_lut[i] = pal[i] & 0xffffffu;
        g_wpix_dirty = 1;
        return;
    }
    g_pal32[0] = 256UL << 16;
    for (int i = 0; i < 256; i++) {
        uint32_t c = pal[i];
        g_pal32[1 + i * 3 + 0] = (c >> 16 & 255) * 0x01010101u;
        g_pal32[1 + i * 3 + 1] = (c >> 8 & 255) * 0x01010101u;
        g_pal32[1 + i * 3 + 2] = (c & 255) * 0x01010101u;
    }
    g_pal32[1 + 256 * 3] = 0;
    LoadRGB32(&g_scr->ViewPort, g_pal32);
}

/* a row: mem_68k.s's copy (MOVE16 into the card's memory when both lie alike on 16 and it passed its test) */
void *os_copy(void *d, const void *s, uint32_t n);
static void copy_row(uint8_t *d, const uint8_t *s, int n) { os_copy(d, s, (uint32_t)n); }

/*
 * OS_SCREENSHOT=<file>:<n>   picture n, read BACK FROM THE SCREEN (the graphics card's memory, or the
 *                            screen's bitmap) with the palette the screen has, as a PPM: it checks the
 *                            whole way into the screen.  The split is at the last ':' (':' is also
 *                            AmigaDOS's volume mark).
 * OS_SCREENSHOT_EVERY=<n>    the same into <file> every n pictures (the last one stays): what is on the
 *                            screen after a long time.
 * Every picture's number and time go to the log with OS_SHOWLOG=1.
 */
static unsigned g_frames;
static char g_shot_file[256];
static unsigned g_shot_at, g_shot_every;
static int g_shot_cfg = -1;

static void shot_config(void)
{
    char v[300];
    const char *e = getenv("OS_SCREENSHOT");
    g_shot_cfg = 0;
    if (!e) return;
    snprintf(v, sizeof v, "%s", e);
    char *c = strrchr(v, ':');
    if (c && c[1] && strspn(c + 1, "0123456789") == strlen(c + 1)) { *c = 0; g_shot_at = (unsigned)atol(c + 1); }
    snprintf(g_shot_file, sizeof g_shot_file, "%s", v);
    if (getenv("OS_SCREENSHOT_EVERY")) g_shot_every = (unsigned)atol(getenv("OS_SCREENSHOT_EVERY"));
    g_shot_cfg = 1;
}

static uint8_t *g_fl_buf[3];                    /* (the SAGA page flip's, below) */
static int g_fl_on, g_fl_cur;
static void shot_write(void)
{
    const int w = g_w, h = g_h;
    uint8_t *img = AllocVec((ULONG)(w * h), MEMF_ANY);
    if (!img) return;
    ULONG bpr = 0, base = 0;
    struct TagItem lt[] = {{LBMI_BYTESPERROW, (ULONG)&bpr}, {LBMI_BASEADDRESS, (ULONG)&base}, {TAG_DONE, 0}};
    APTR lock = NULL;
    if (g_fl_on) {                                      /* (the SAGA page flip: the buffer shown, not the screen's bitmap) */
        for (int y = 0; y < h; y++) CopyMem((APTR)(g_fl_buf[g_fl_cur] + (ULONG)y * (ULONG)w), img + y * w, (ULONG)w);
    } else if ((lock = g_rtg ? LockBitMapTagList(g_scr->RastPort.BitMap, lt) : NULL)) {
        for (int y = 0; y < h; y++) CopyMem((APTR)(base + (ULONG)(y + g_y0) * bpr + (ULONG)g_x0), img + y * w, (ULONG)w);
        UnLockBitMap(lock);
    } else if (g_aga) {                                 /* the planes shown, back into bytes */
        const uint8_t *pl = g_aga_pl[g_aga_cur];
        for (int i = 0; i < w * h; i++) {
            uint8_t v = 0;
            for (int p = 0; p < 8; p++) v |= (uint8_t)(((pl[p * g_aga_bpl + (ULONG)(i >> 3)] >> (7 - (i & 7))) & 1) << p);
            img[i] = v;
        }
    } else
        ReadPixelArray8(&g_scr->RastPort, (UWORD)g_x0, (UWORD)g_y0, (UWORD)(g_x0 + w - 1), (UWORD)(g_y0 + h - 1), img, NULL);
    static ULONG cols[256 * 3];
    GetRGB32(g_scr->ViewPort.ColorMap, 0, 256, cols);
    FILE *f = fopen(g_shot_file, "wb");
    if (f) {
        fprintf(f, "P6\n%d %d\n255\n", w, h);
        uint8_t *row = AllocVec((ULONG)w * 3, MEMF_ANY);
        for (int y = 0; row && y < h; y++) {
            for (int x = 0; x < w; x++)
                for (int c = 0; c < 3; c++) row[x * 3 + c] = (uint8_t)(cols[img[y * w + x] * 3 + c] >> 24);
            fwrite(row, 1, (size_t)w * 3, f);
        }
        if (row) FreeVec(row);
        fclose(f);
        amiga_log("amiga: screenshot %s (picture %u, %s)", g_shot_file, g_frames, lock ? "from the card's memory" : g_aga ? "the AGA planes shown" : "ReadPixelArray8");
    }
    FreeVec(img);
}

/* ---- OS_PHASES (amiga.h) ---- */
static int g_ph_on = -1;
static uint64_t g_ph_t[12], g_ph_end, g_ph_sum[8], g_ph_geo[2];
static long g_ph_nothers;
static uint64_t g_ph_sub[3];
static uint64_t g_ph_rsub[4];           /* the rest: after the painting, the instruments (of them the radar), after them */
int g_ccc_on;
uint32_t g_ccc_sum[8];

void amiga_geo_split(uint64_t pieces, uint64_t others, int nothers)
{
    g_ph_geo[0] += pieces; g_ph_geo[1] += others; g_ph_nothers += nothers;
}
static unsigned g_ph_n;

void amiga_mark(int k)
{
    if (g_ph_on < 0) {
        g_ph_on = getenv("OS_PHASES") != NULL; g_ccc_on = getenv("OS_CCC") != NULL;
#ifdef PMKON
        { extern long raster_zuv; raster_zuv = getenv("OS_ZUV") != NULL; }   /* texture steps 0: every texel from the cache */
#endif
    }
    if (g_ph_on && k >= 0 && k < 12) g_ph_t[k] = SDL_GetPerformanceCounter();
}

static void phases_frame(uint64_t show0, uint64_t show1)
{
    if (g_ph_on <= 0) return;
    if (g_ph_end && g_ph_t[0] > g_ph_end && g_ph_t[5] >= g_ph_t[0]) {
        g_ph_sum[0] += g_ph_t[0] - g_ph_end;          /* the game */
        g_ph_sum[1] += g_ph_t[1] - g_ph_t[0];         /* backdrop */
        g_ph_sum[2] += g_ph_t[2] - g_ph_t[1];         /* geometry */
        g_ph_sum[3] += g_ph_t[5] - g_ph_t[2];         /* painting */
        g_ph_sum[4] += show0 - g_ph_t[5];             /* the rest: HUD ... */
        g_ph_sum[5] += show1 - show0;                 /* the copy to the screen */
        if (g_ph_t[6] > g_ph_end && g_ph_t[7] >= g_ph_t[6] && g_ph_t[0] >= g_ph_t[7]) {   /* the game: before, steps, after */
            g_ph_sub[0] += g_ph_t[6] - g_ph_end; g_ph_sub[1] += g_ph_t[7] - g_ph_t[6]; g_ph_sub[2] += g_ph_t[0] - g_ph_t[7];
        }
        /* the rest (main.c marks 8 .. 11): 5 -> 8 the render's end, 8 -> 11 the instruments (9 -> 10 the radar), 11 -> show0 */
        if (g_ph_t[8] >= g_ph_t[5] && g_ph_t[11] >= g_ph_t[8] && show0 >= g_ph_t[11]) {
            g_ph_rsub[0] += g_ph_t[8] - g_ph_t[5]; g_ph_rsub[1] += g_ph_t[11] - g_ph_t[8]; g_ph_rsub[3] += show0 - g_ph_t[11];
            if (g_ph_t[9] >= g_ph_t[8] && g_ph_t[10] >= g_ph_t[9] && g_ph_t[11] >= g_ph_t[10]) g_ph_rsub[2] += g_ph_t[10] - g_ph_t[9];
        }
        if (++g_ph_n == 50) {
            const double k = 1000.0 / (double)SDL_GetPerformanceFrequency() / 50.0;
            amiga_log("phases (ms a picture): game %.2f  backdrop %.2f  geometry %.2f (pieces %.2f, %ld others %.2f)  painting %.2f  rest %.2f  copy %.2f  = %.2f",
                      g_ph_sum[0] * k, g_ph_sum[1] * k, g_ph_sum[2] * k, g_ph_geo[0] * k, g_ph_nothers / 50, g_ph_geo[1] * k,
                      g_ph_sum[3] * k, g_ph_sum[4] * k, g_ph_sum[5] * k,
                      (g_ph_sum[0] + g_ph_sum[1] + g_ph_sum[2] + g_ph_sum[3] + g_ph_sum[4] + g_ph_sum[5]) * k);
            amiga_log("  the game (ms a picture): before the steps %.1f  the steps %.1f  after them %.1f",
                      g_ph_sub[0] * k, g_ph_sub[1] * k, g_ph_sub[2] * k);
            memset(g_ph_sub, 0, sizeof g_ph_sub);
            amiga_log("  the rest (ms a picture): after the painting %.2f  the instruments %.2f (the radar %.2f)  after them %.2f",
                      g_ph_rsub[0] * k, g_ph_rsub[1] * k, g_ph_rsub[2] * k, g_ph_rsub[3] * k);
            memset(g_ph_rsub, 0, sizeof g_ph_rsub);
            if (g_ccc_on)
                amiga_log("cycles a picture (k): %lu %lu %lu %lu %lu %lu %lu %lu",
                          (unsigned long)g_ccc_sum[0] / 50000, (unsigned long)g_ccc_sum[1] / 50000, (unsigned long)g_ccc_sum[2] / 50000,
                          (unsigned long)g_ccc_sum[3] / 50000, (unsigned long)g_ccc_sum[4] / 50000, (unsigned long)g_ccc_sum[5] / 50000,
                          (unsigned long)g_ccc_sum[6] / 50000, (unsigned long)g_ccc_sum[7] / 50000);
            memset(g_ccc_sum, 0, sizeof g_ccc_sum);
#ifdef PMKON
            {   extern long pmk_get(long w, long k);          /* span_68k.s, the measuring build (PMK=1) */
                for (long k = 0; k < 16; k++) {
                    const unsigned long c = (unsigned long)pmk_get(0, k), px = (unsigned long)pmk_get(1, k), rw = (unsigned long)pmk_get(2, k);
                    if (px > 0)
                        amiga_log("pixel loop kind %lu: %lu px %lu rows a picture, %lu cycles a picture, %lu.%02lu cycles a pixel",
                                  (unsigned long)k, px / 50, rw / 50, c / 50, c / px, (c % px) * 100 / px);
                }
                for (long k = 0; k < 16; k++)
                    if (pmk_get(4, k) > 0)
                        amiga_log("poly section %lu: %lu times, %lu cycles a picture", (unsigned long)k,
                                  (unsigned long)pmk_get(4, k) / 50, (unsigned long)pmk_get(3, k) / 50);
                pmk_get(-1, 0);
            }
#endif
            memset(g_ph_sum, 0, sizeof g_ph_sum); memset(g_ph_geo, 0, sizeof g_ph_geo); g_ph_nothers = 0; g_ph_n = 0;
        }
    }
    g_ph_end = show1;
}

/* ---- the SAGA page flip (amiga.h amiga_flip) ---- */
#define SAGA_GFXPTR (*(volatile ULONG *)0xdff1ecUL)
#ifndef FLIP_PAD
#define FLIP_PAD 0                              /* KB past a 32 KB bound (OS_FLIPPAD) */
#endif
static uint8_t *g_fl_mem, *g_fl_buf[3];
static uint32_t g_fl_bytes;
static ULONG g_fl_os;                   /* the system's picture, to go back to */
static int g_fl_on, g_fl_cur, g_fl_tried, g_fl_ok;

static void flip_off(void)
{
    if (g_fl_on) { SAGA_GFXPTR = g_fl_os; g_fl_on = 0; }
}

static void flip_free(void)
{
    g_fl_ok = 0; g_fl_tried = 0;                /* (the buffers are the arena's: kept, freed with the field at the end) */
}
uint8_t *amiga_flip(const uint8_t *pixels, const uint32_t *pal, int w, int h, uint32_t bytes)
{
    if (w <= 0 || h <= 0 || want_window()) return NULL;
    if ((!g_scr || w != g_w || h != g_h) && video_open(w, h)) return NULL;
    if (!g_fl_tried || g_fl_bytes < (uint32_t)(w * h)) {
        g_fl_tried = 1; g_fl_ok = 0;
        const char *e = getenv("OS_SAGA");
        ULONG bpr = 0, base = 0;
        if (g_rtg && !(e && e[0] == '0') && (SysBase->AttnFlags & (1u << 10)) && g_x0 == 0 && g_y0 == 0 && g_sw == w && g_sh == h) {
            struct TagItem lt[] = {{LBMI_BYTESPERROW, (ULONG)&bpr}, {LBMI_BASEADDRESS, (ULONG)&base}, {TAG_DONE, 0}};
            APTR lock = LockBitMapTagList(g_scr->RastPort.BitMap, lt);
            if (lock) UnLockBitMap(lock);
            if (lock && bpr == (ULONG)w && base && !(base & 31)) {
                g_fl_bytes = (bytes + 63) & ~63u;
                /* out of the arena's fixed field (sys/arena.c, $0C000000): the same addresses every run -- AllocVec's
                   moved with whatever AmigaOS had free, and with them the data cache's conflicts (painting 28.8 /
                   30.2 ms for the same program); kept for the program's whole run (this file's statics are not put
                   back between the parts) */
                if (!g_fl_mem) {
                    /* OS_FLIPPAD=k: the buffers k KB further on (their place against the textures' in the 32 KB data
                       cache; measured: see FLIP_PAD) */
                    extern void *arena_alloc_aligned(size_t n, uint32_t align);
                    const char *e = getenv("OS_FLIPPAD");
                    const uint32_t pad = (e ? (uint32_t)atoi(e) : FLIP_PAD) * 1024u;
                    uint8_t *m = arena_alloc_aligned(3 * g_fl_bytes + 64 + 64 * 1024, 32768);
                    if (m) { g_fl_mem = m + (pad % (64 * 1024)); memset(g_fl_mem, 0, 3 * g_fl_bytes + 64); }
                }
                if (g_fl_mem) {
                    uint8_t *b = (uint8_t *)(((uintptr_t)g_fl_mem + 63) & ~(uintptr_t)63);
                    for (int k = 0; k < 3; k++) g_fl_buf[k] = b + k * g_fl_bytes;
                    g_fl_os = base; g_fl_ok = 1; g_fl_cur = 0;
                }
            }
        }
        amiga_log("amiga: SAGA page flip %s (RTG %d, screen %dx%d at %d,%d, %lu bytes a row, base %08lx, 080 %d, buffers %p, largest free %lu)",
                  g_fl_ok ? "on" : "off", g_rtg, g_sw, g_sh, g_x0, g_y0, (unsigned long)bpr, (unsigned long)base,
                  (SysBase->AttnFlags & (1u << 10)) != 0, (void *)g_fl_mem, (unsigned long)AvailMem(MEMF_FAST | MEMF_LARGEST));
        { extern void arena_where(char *, int); char aw[256]; arena_where(aw, sizeof aw); amiga_log("memory: %s", aw); }
    }
    if (!g_fl_ok) return NULL;
    const uint64_t show0 = g_ph_on > 0 ? SDL_GetPerformanceCounter() : 0;
    int k = -1;
    for (int i = 0; i < 3; i++) if (pixels == g_fl_buf[i]) k = i;
    if (k < 0) {                                        /* (the first: the picture into a buffer of ours) */
        k = (g_fl_cur + 1) % 3;
        memcpy(g_fl_buf[k], pixels, (size_t)w * (size_t)h);
    }
    load_palette(pal);                                  /* (only when it changed) */
    {   static int sum_ = -1, n_;                       /* OS_FBSUM=1: every picture's sum in the log (sdl_null.c's, the
                                                           same numbers): two builds or switches compared on the machine */
        if (sum_ < 0) sum_ = getenv("OS_FBSUM") != NULL;
        if (sum_) {
            const uint8_t *b_ = g_fl_buf[k];
            uint32_t a_ = 1, c_ = 0, q_ = 0;
            for (int i = 0; i < w * h; i++) { a_ = (a_ + b_[i]) % 65521u; c_ = (c_ + a_) % 65521u; }
            for (int i = 0; i < 256; i++) q_ = q_ * 31u + pal[i];
            amiga_log("fbsum %d %08x %08x", n_++, (unsigned)(c_ << 16 | a_), (unsigned)q_);
        }
    }
    SAGA_GFXPTR = (ULONG)g_fl_buf[k];
    g_fl_on = 1;
    g_fl_cur = k;
    phases_frame(show0, g_ph_on > 0 ? SDL_GetPerformanceCounter() : 0);
    g_frames++;
    if (g_shot_cfg < 0) shot_config();
    if (g_shot_cfg > 0 && (g_frames == g_shot_at || (g_shot_every && g_frames % g_shot_every == 0))) shot_write();
    return g_fl_buf[(k + 1) % 3];                       /* (shown two pictures ago: off the screen) */
}

/* a colour -> a pixel in the window bitmap's format (g_wfmt) */
static uint32_t win_pixel(uint32_t rgb)
{
    uint32_t r = rgb >> 16 & 255, g = rgb >> 8 & 255, b = rgb & 255, v;
    switch (g_wfmt) {
    case PIXFMT_RGB15: case PIXFMT_RGB15PC: v = (r >> 3) << 10 | (g >> 3) << 5 | b >> 3; break;
    case PIXFMT_BGR15: case PIXFMT_BGR15PC: v = (b >> 3) << 10 | (g >> 3) << 5 | r >> 3; break;
    case PIXFMT_RGB16: case PIXFMT_RGB16PC: v = (r >> 3) << 11 | (g >> 2) << 5 | b >> 3; break;
    case PIXFMT_BGR16: case PIXFMT_BGR16PC: v = (b >> 3) << 11 | (g >> 2) << 5 | r >> 3; break;
    case PIXFMT_ARGB32: return 0xff000000u | r << 16 | g << 8 | b;
    case PIXFMT_BGRA32: return b << 24 | g << 16 | r << 8 | 0xffu;
    default: return r << 24 | g << 16 | b << 8 | 0xffu;              /* RGBA32 */
    }
    if (g_wfmt == PIXFMT_RGB15PC || g_wfmt == PIXFMT_BGR15PC || g_wfmt == PIXFMT_RGB16PC || g_wfmt == PIXFMT_BGR16PC)
        v = (v >> 8 | v << 8) & 0xffffu;                              /* the PC formats: little endian */
    return v << 16 | v;                                               /* doubled: a long word = 2 pixels (2x) */
}

/* a row -> the screen's format through g_wpix, n a multiple of 4 (win_68k.s; MorphOS: the same in C, mos_stubs.c) */
void win_row16x1(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *t);
void win_row32x1(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *t);
void win_row32x2(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *t, uint32_t bpr);

/* the picture into the window with the own conversion: a target row in the screen's format (scaled) a source row,
 * copied n - 1 times, then one WritePixelArray RECTFMT_RAW for the whole picture */
static void win_show_raw(const uint8_t *pixels, int w, int h)
{
    const int sc = g_wscale, iw = w * sc;
    if (g_wpix_dirty) {
        for (int i = 0; i < 256; i++) g_wpix[i] = win_pixel(g_lut[i]);
        g_wpix_dirty = 0;
    }
    const int bpr = iw * g_wbpp;
    for (int y = 0; y < h; y++) {
        const uint8_t *s = pixels + (size_t)y * w;
        uint8_t *row = g_wbuf + (uint32_t)y * sc * bpr;
        if (g_wbpp == 2 && sc < 3) {
            if (sc == 2) {
                win_row32x2((uint32_t *)row, s, (uint32_t)w, g_wpix, (uint32_t)bpr);
                continue;                               /* both rows written */
            } else
                win_row16x1((uint32_t *)row, s, (uint32_t)w, g_wpix);
        } else if (g_wbpp == 4 && sc == 1) {
            win_row32x1((uint32_t *)row, s, (uint32_t)w, g_wpix);
        } else if (g_wbpp == 2) {
            uint16_t *d = (uint16_t *)row;
            for (int x = 0; x < w; x++, d += sc) {
                uint16_t p = (uint16_t)g_wpix[s[x]];
                d[0] = p;
                if (sc == 3) d[1] = d[2] = p;
            }
        } else {
            uint32_t *d = (uint32_t *)row;
            for (int x = 0; x < w; x++, d += sc) {
                uint32_t p = g_wpix[s[x]];
                d[0] = p;
                if (sc > 1) d[1] = p;
                if (sc > 2) d[2] = p;
            }
        }
        for (int k = 1; k < sc; k++) os_copy(row + (size_t)k * bpr, row, (uint32_t)bpr);
    }
    WritePixelArray(g_wbuf, 0, 0, (UWORD)bpr, g_win->RPort, (UWORD)g_win->BorderLeft, (UWORD)g_win->BorderTop, (UWORD)iw,
                    (UWORD)(h * sc), RECTFMT_RAW);
}

void amiga_show(const void *pixels, const uint32_t *pal, int w, int h)
{
    if (w <= 0 || h <= 0) return;
    flip_off();
    const uint64_t show0 = g_ph_on > 0 ? SDL_GetPerformanceCounter() : 0;
    if (((!g_scr && !g_inwin) || w != g_w || h != g_h) && video_open(w, h)) return;
    if (g_inwin) {                                      /* the window: through the palette, scaled */
        load_palette(pal);
        if (g_wbpp) {
            win_show_raw(pixels, w, h);
            phases_frame(show0, g_ph_on > 0 ? SDL_GetPerformanceCounter() : 0);
            g_frames++;
            return;
        }
        const uint8_t *src = pixels;
        const int n = g_wscale, ww = w * n;
        if (n > 1 && g_wbuf) {
            extern void scale_row68k(uint8_t *dst, const uint8_t *src, uint32_t w, uint32_t n);
            for (int y = 0; y < h; y++) {
                uint8_t *d = g_wbuf + (size_t)y * n * ww;
                scale_row68k(d, src + (size_t)y * w, (uint32_t)w, (uint32_t)n);
                for (int k = 1; k < n; k++) os_copy(d + (size_t)k * ww, d, (uint32_t)ww);
            }
            src = g_wbuf;
        }
        WriteLUTPixelArray((APTR)src, 0, 0, (UWORD)ww, g_win->RPort, g_lut, (UWORD)g_win->BorderLeft,
                           (UWORD)g_win->BorderTop, (UWORD)ww, (UWORD)(h * n), CTABFMT_XRGB8);
        phases_frame(show0, g_ph_on > 0 ? SDL_GetPerformanceCounter() : 0);
        g_frames++;
        return;
    }
    {   static const void *told;              /* where the picture is rendered (Fast RAM: the arena, port/amiga/sys/arena.c) */
        if (told != pixels) { told = pixels;
            { extern void arena_where(char *, int); char aw[256]; arena_where(aw, sizeof aw); amiga_log("picture rendered at %p (%s RAM), copied with LockBitMap; memory: %s", pixels, (TypeOfMem((APTR)pixels) & MEMF_FAST) ? "Fast" : "CHIP", aw); } } }
    if (g_shot_cfg < 0) shot_config();
    load_palette(pal);
    const uint8_t *src = pixels;
    if (g_rtg) {
        ULONG bpr = 0, base = 0;
        struct TagItem lt[] = {{LBMI_BYTESPERROW, (ULONG)&bpr}, {LBMI_BASEADDRESS, (ULONG)&base}, {TAG_DONE, 0}};
        APTR lock = LockBitMapTagList(g_scr->RastPort.BitMap, lt);
        if (lock) {                                     /* (nothing but copying while it is locked) */
            for (int y = 0; y < h; y++)
                copy_row((uint8_t *)(base + (ULONG)(y + g_y0) * bpr + (ULONG)g_x0), src + y * w, w);
            UnLockBitMap(lock);
        } else
            WritePixelArray8(&g_scr->RastPort, (UWORD)g_x0, (UWORD)g_y0, (UWORD)(g_x0 + w - 1), (UWORD)(g_y0 + h - 1),
                             (UBYTE *)src, NULL);
    } else if (g_aga) {                                 /* into the hidden planes, shown at the next frame */
        const int nb = g_aga_cur ^ 1;
        aga_wait_safe();                                /* (nb was shown before the last change: free after its SafeMessage) */
        uint8_t *pl = g_aga_pl[nb];
        const unsigned f = ++g_c2p_f;
        const unsigned m = g_c2p_delta && 2 * g_c2p_td < g_c2p_tw ? 63 : 15;   /* (the other way every 16th picture, its
                                                                                  time; every 64th when delta is far ahead) */
        int delta = g_aga_shmem && g_aga_sh_ok[nb] && (g_c2p_delta ? (f & m) != 0 : (f & m) == 0);
        const uint64_t tc0 = SDL_GetPerformanceCounter();
        if (delta) c2pl_delta(src, pl, g_aga_sh[nb], (uint32_t)(g_w * g_h), g_aga_bpl, (uint32_t)(g_w / 8));
        else {
#ifdef OS_V080
            if (g_c2p080) c2p_conv080(src, pl, (uint32_t)(g_w * g_h / 64));
            else
#endif
            {   if (!g_aga_kfull) { c2p_init((uint32_t)g_w, (uint32_t)g_h, g_aga_bpl); g_aga_kfull = 1; }
                c2p_conv(src, pl);
            }
        }
        const uint64_t tc = SDL_GetPerformanceCounter() - tc0;
        if (g_aga_shmem) {
            uint64_t *t = delta ? &g_c2p_td : &g_c2p_tw;
            *t = *t ? (*t * 3 + tc) / 4 : tc;
            if (!delta) {                               /* the copy: wanted in the delta way, and before a try of it */
                g_aga_sh_ok[nb] = g_c2p_delta || ((f + 2) & m) == 0;
                if (g_aga_sh_ok[nb]) memcpy(g_aga_sh[nb], src, (size_t)g_w * (size_t)g_h);
            }
            if (g_c2p_tw && g_c2p_td) g_c2p_delta = g_c2p_td < g_c2p_tw;
        }
        {   static int lg = -1; static uint64_t sum; static unsigned nd;      /* OS_C2PLOG=1 (the test): every 100 pictures */
            if (lg < 0) lg = getenv("OS_C2PLOG") != NULL;
            if (lg) {
                sum += tc; nd += delta;
                if (f % 100 == 0) {
                    const double k = 1000.0 / (double)SDL_GetPerformanceFrequency();
                    amiga_log("c2plog: %.3f ms a picture, %u of 100 delta; whole %.3f ms, delta %.3f ms", (double)sum * k / 100.0, nd,
                              (double)g_c2p_tw * k, (double)g_c2p_td * k);
                    sum = 0; nd = 0;
                }
            }
        }
        {   static int check = -1; static uint8_t *ref; static unsigned bad, seen;   /* OS_C2PCHECK=1 (the test): the planes
                                                                                         against the whole picture's c2p */
            if (check < 0) check = getenv("OS_C2PCHECK") != NULL;
            if (check && (ref || (ref = AllocVec(8 * g_aga_bpl, MEMF_ANY)))) {
                if (!g_aga_kfull) { c2p_init((uint32_t)g_w, (uint32_t)g_h, g_aga_bpl); g_aga_kfull = 1; }
                c2p_conv(src, ref);
                if (memcmp(ref, pl, 8 * g_aga_bpl)) bad++;
                if (++seen % 100 == 0) amiga_log("c2pcheck: %u of %u pictures differ from the whole picture's c2p", bad, seen);
            }
        }
        while (!ChangeScreenBuffer(g_scr, g_aga_sb[nb])) WaitTOF();
        g_aga_busy = 1;
        g_aga_cur = nb;
    } else
        WriteChunkyPixels(&g_scr->RastPort, 0, 0, (LONG)w - 1, (LONG)h - 1, (UBYTE *)src, (LONG)w);
    phases_frame(show0, g_ph_on > 0 ? SDL_GetPerformanceCounter() : 0);
    g_frames++;
    static int showlog = -1;
    if (showlog < 0) showlog = getenv("OS_SHOWLOG") != NULL;
    if (showlog) {
        unsigned sum = 0;
        for (int i = 0; i < 256; i++) sum += (pal[i] >> 16 & 255) + (pal[i] >> 8 & 255) + (pal[i] & 255);
        amiga_log("amiga: picture %u at %u ms, palette sum %u", g_frames, (unsigned)SDL_GetTicks(), sum);
    }
    if (g_shot_cfg > 0 && (g_frames == g_shot_at || (g_shot_every && g_frames % g_shot_every == 0))) shot_write();
}

void amiga_video_mouse(int relative) { g_mouse_rel = relative; }

void amiga_video_pump(void)
{
    if (!g_win) return;
    struct IntuiMessage *m;
    while ((m = (struct IntuiMessage *)GetMsg(g_win->UserPort))) {
        ULONG cls = m->Class;
        UWORD code = m->Code, qual = m->Qualifier;
        WORD mx = m->MouseX, my = m->MouseY;
        ReplyMsg((struct Message *)m);
        if (cls == IDCMP_RAWKEY) amiga_key(code, qual);
        else if (cls == IDCMP_INACTIVEWINDOW) amiga_keys_released();
        else if (cls == IDCMP_CLOSEWINDOW) amiga_quit_event();          /* (the window's close gadget) */
        else if (cls == IDCMP_MOUSEMOVE && g_mouse_rel) amiga_mouse_moved(mx, my);   /* (DELTAMOVE: the steps) */
    }
}

