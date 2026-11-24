/*
 * sdl_amiga.c - THE AMIGA'S SDL (AmigaOS 3.x, 68040 / 68060 / 68080).
 *
 * The game is written against SDL2.  On the Amiga there is no SDL: this file
 * is the part of SDL2 the game uses, written on AmigaOS -- SDL2's own headers
 * (port/amiga/include, for the types, constants and events), these functions.
 *
 *   picture   a screen of its own, 8 bits a pixel, the game's palette numbers
 *             (amiga_show from main.c's show_pixels, like the MiSTer's
 *             mister_show): an RTG screen (CyberGraphX / Picasso96) copied
 *             into with LockBitMap, else an AGA screen (C2P, amiga_c2p.c).
 *   keys      a borderless backdrop window on that screen: IDCMP_RAWKEY ->
 *             SDL scancodes (by position, an US keyboard's names).
 *   time      timer.device's E-clock.
 *   threads   none: SDL_CreateThread answers NULL and the game fills its
 *             triangles itself (OS_ONETHREAD).  One processor.
 *   sound     amiga_audio.c (SDL_OpenAudio).
 *   pad       a CD32 pad / joystick in port 2 (lowlevel.library) as SDL's game
 *             controller.
 *
 * This file is NOT among the objects whose statics port.c puts back between
 * the parts of the program (it is linked beside os_all.o): what it keeps
 * outlives the parts, as SDL's own did.
 */
#include <SDL.h>

#include <exec/types.h>
#include <exec/memory.h>
#include <exec/execbase.h>
#include <dos/dos.h>
#include <devices/timer.h>
#include <devices/inputevent.h>
#include <intuition/intuition.h>
#include <intuition/screens.h>
#include <graphics/modeid.h>
#include <graphics/gfxbase.h>
#include <graphics/displayinfo.h>
#include <cybergraphx/cybergraphics.h>
#include <libraries/lowlevel.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <proto/graphics.h>
#include <proto/cybergraphics.h>
#include <proto/lowlevel.h>
#include <proto/timer.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "amiga.h"

#include "os_version.h"
#ifdef OS_VERSTAG
/* the AmigaDOS version string ("Version amiscreamer_080": 1.03 and the date of the source) */
static const char s_verstag[] __attribute__((used)) = OS_VERSTAG;
#endif
struct Library *CyberGfxBase;
struct Library *LowLevelBase;
#ifdef OS_MOS
struct Library *TimerBase;                      /* (MorphOS' type for it) */
#else
struct Device  *TimerBase;
#endif

static char g_err[160] = "";

static void set_err(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(g_err, sizeof g_err, fmt, ap);
    va_end(ap);
}

const char *SDL_GetError(void) { return g_err; }

/* ------------------------------------------------------------------ time */

static struct timerequest  t_eclock;   /* UNIT_ECLOCK: only for TimerBase / ReadEClock */
static struct MsgPort     *t_port;
static struct timerequest *t_req;      /* UNIT_MICROHZ: waiting */
static int                 t_open;
static ULONG               t_efreq;
static uint64_t            t_start;

static uint64_t eclock_now(void)
{
    struct EClockVal ev;
    ReadEClock(&ev);
    return (uint64_t)ev.ev_hi << 32 | ev.ev_lo;
}

static int timer_init(void)
{
    if (t_open) return 0;
    memset(&t_eclock, 0, sizeof t_eclock);
    if (OpenDevice((CONST_STRPTR)TIMERNAME, UNIT_ECLOCK, (struct IORequest *)&t_eclock, 0)) return -1;
    TimerBase = (void *)t_eclock.tr_node.io_Device;
    if (!(t_port = CreateMsgPort())) return -1;
    if (!(t_req = (struct timerequest *)CreateIORequest(t_port, sizeof *t_req))) return -1;
    if (OpenDevice((CONST_STRPTR)TIMERNAME, UNIT_MICROHZ, (struct IORequest *)t_req, 0)) return -1;
    struct EClockVal ev;
    t_efreq = ReadEClock(&ev);
    t_start = (uint64_t)ev.ev_hi << 32 | ev.ev_lo;
    t_open = 1;
    return 0;
}

static void timer_close(void)
{
    if (!t_open) return;
    CloseDevice((struct IORequest *)t_req);
    DeleteIORequest((struct IORequest *)t_req);
    DeleteMsgPort(t_port);
    CloseDevice((struct IORequest *)&t_eclock);
    t_open = 0;
    TimerBase = NULL;
}

Uint32 SDL_GetTicks(void)
{
    if (timer_init()) return 0;
    return (Uint32)((eclock_now() - t_start) * 1000u / t_efreq);
}

Uint64 SDL_GetTicks64(void)
{
    if (timer_init()) return 0;
    return (eclock_now() - t_start) * 1000u / t_efreq;
}

Uint64 SDL_GetPerformanceCounter(void)
{
    if (timer_init()) return 0;
    return eclock_now();
}

Uint64 SDL_GetPerformanceFrequency(void)
{
    if (timer_init()) return 1;
    return t_efreq;
}

void SDL_Delay(Uint32 ms)
{
    if (timer_init()) { Delay(ms / 20 + 1); return; }
    if (!ms) return;
    t_req->tr_node.io_Command = TR_ADDREQUEST;
    t_req->tr_time.tv_secs = ms / 1000;
    t_req->tr_time.tv_micro = (ms % 1000) * 1000;
    DoIO((struct IORequest *)t_req);
}

/* ------------------------------------------------------------------ start, hints */

static Uint32 g_inited;
static int    g_cleanup_set;

static void amiga_quit(void)
{
    amiga_audio_close();
    amiga_video_close();
    if (LowLevelBase) { CloseLibrary(LowLevelBase); LowLevelBase = NULL; }
    if (CyberGfxBase) { CloseLibrary(CyberGfxBase); CyberGfxBase = NULL; }
    timer_close();
}

void os_copy_init(void);
int SDL_Init(Uint32 flags) { return SDL_InitSubSystem(flags); }

int SDL_InitSubSystem(Uint32 flags)
{
    if (!g_cleanup_set) { atexit(amiga_quit); g_cleanup_set = 1; }
    os_copy_init();                     /* (mem_68k.s: the copy for this processor, MOVE16 tested) */
    if (timer_init()) { set_err("timer.device cannot be opened"); return -1; }
    if (flags & SDL_INIT_AUDIO) {
        if (amiga_audio_init()) return -1;
        g_inited |= SDL_INIT_AUDIO;
    }
    if (flags & (SDL_INIT_GAMECONTROLLER | SDL_INIT_JOYSTICK)) {
        if (!LowLevelBase) LowLevelBase = OpenLibrary((CONST_STRPTR)"lowlevel.library", 40);
        g_inited |= SDL_INIT_GAMECONTROLLER | SDL_INIT_JOYSTICK;
    }
    if (flags & SDL_INIT_VIDEO) g_inited |= SDL_INIT_VIDEO;
    g_inited |= flags & (SDL_INIT_TIMER | SDL_INIT_EVENTS);
    return 0;
}

Uint32 SDL_WasInit(Uint32 flags) { return flags ? (g_inited & flags) : g_inited; }
void SDL_Quit(void) { amiga_quit(); }
SDL_bool SDL_SetHint(const char *name, const char *value) { (void)name; (void)value; return SDL_TRUE; }
const char *SDL_GetCurrentVideoDriver(void) { return "amiga"; }

/* ------------------------------------------------------------------ the window: the picture's size */

struct SDL_Window { int w, h; Uint32 flags; };
static struct SDL_Window g_window;

SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, Uint32 flags)
{
    (void)title; (void)x; (void)y; (void)flags;
    g_window.w = w; g_window.h = h;
    g_window.flags = SDL_WINDOW_FULLSCREEN | SDL_WINDOW_SHOWN;
    return &g_window;
}

void SDL_GetWindowSize(SDL_Window *win, int *w, int *h)
{
    if (w) *w = win ? win->w : 0;
    if (h) *h = win ? win->h : 0;
}

void SDL_SetWindowSize(SDL_Window *win, int w, int h) { if (win) { win->w = w; win->h = h; } }
void SDL_SetWindowTitle(SDL_Window *win, const char *title) { (void)win; (void)title; }
Uint32 SDL_GetWindowFlags(SDL_Window *win) { return win ? win->flags : 0; }
int SDL_SetWindowFullscreen(SDL_Window *win, Uint32 flags) { (void)win; (void)flags; return 0; }

/* (the PC's renderer and texture: not used on the Amiga -- main.c takes the
   MiSTer's way, the picture straight to the screen -- but still named in it) */
SDL_Renderer *SDL_CreateRenderer(SDL_Window *w, int i, Uint32 f) { (void)w; (void)i; (void)f; return (SDL_Renderer *)&g_window; }
int SDL_GetRendererInfo(SDL_Renderer *r, SDL_RendererInfo *info) { (void)r; memset(info, 0, sizeof *info); info->name = "amiga"; return 0; }
int SDL_RenderSetLogicalSize(SDL_Renderer *r, int w, int h) { (void)r; (void)w; (void)h; return 0; }
SDL_Texture *SDL_CreateTexture(SDL_Renderer *r, Uint32 f, int a, int w, int h) { (void)r; (void)f; (void)a; (void)w; (void)h; return NULL; }
int SDL_QueryTexture(SDL_Texture *t, Uint32 *f, int *a, int *w, int *h) { (void)t; (void)f; (void)a; if (w) *w = 0; if (h) *h = 0; return -1; }
void SDL_DestroyTexture(SDL_Texture *t) { (void)t; }
int SDL_UpdateTexture(SDL_Texture *t, const SDL_Rect *r, const void *p, int pitch) { (void)t; (void)r; (void)p; (void)pitch; return -1; }
int SDL_RenderClear(SDL_Renderer *r) { (void)r; return 0; }
int SDL_RenderCopy(SDL_Renderer *r, SDL_Texture *t, const SDL_Rect *a, const SDL_Rect *b) { (void)r; (void)t; (void)a; (void)b; return 0; }
void SDL_RenderPresent(SDL_Renderer *r) { (void)r; }
int SDL_SetRelativeMouseMode(SDL_bool on) { amiga_video_mouse(on); return 0; }

/* ------------------------------------------------------------------ threads, atomics (one processor) */

SDL_Thread *SDL_CreateThread(SDL_ThreadFunction fn, const char *name, void *data)
{
    (void)fn; (void)name; (void)data;
    set_err("no threads on the Amiga");
    return NULL;
}

struct SDL_semaphore { Uint32 n; };
SDL_sem *SDL_CreateSemaphore(Uint32 n) { SDL_sem *s = calloc(1, sizeof *s); if (s) s->n = n; return s; }
int SDL_SemPost(SDL_sem *s) { if (s) s->n++; return 0; }
int SDL_SemWait(SDL_sem *s) { if (s && s->n) s->n--; return 0; }

int SDL_AtomicSet(SDL_atomic_t *a, int v) { int old = a->value; a->value = v; return old; }
int SDL_AtomicGet(SDL_atomic_t *a) { return a->value; }
SDL_bool SDL_AtomicTryLock(SDL_SpinLock *l) { if (*l) return SDL_FALSE; *l = 1; return SDL_TRUE; }
void SDL_AtomicUnlock(SDL_SpinLock *l) { *l = 0; }

/* ------------------------------------------------------------------ keys */

/* Amiga raw key -> SDL scancode (raw2sc), CONTROLS.CFG's scan codes and the pad's buttons: padkeys.h */
#include "padkeys.h"

/* SDL's own names (SDL_GetScancodeName), for the keys there are */
static const struct { Uint16 sc; const char *name; } sc_names[] = {
    {SDL_SCANCODE_A, "A"}, {SDL_SCANCODE_B, "B"}, {SDL_SCANCODE_C, "C"}, {SDL_SCANCODE_D, "D"},
    {SDL_SCANCODE_E, "E"}, {SDL_SCANCODE_F, "F"}, {SDL_SCANCODE_G, "G"}, {SDL_SCANCODE_H, "H"},
    {SDL_SCANCODE_I, "I"}, {SDL_SCANCODE_J, "J"}, {SDL_SCANCODE_K, "K"}, {SDL_SCANCODE_L, "L"},
    {SDL_SCANCODE_M, "M"}, {SDL_SCANCODE_N, "N"}, {SDL_SCANCODE_O, "O"}, {SDL_SCANCODE_P, "P"},
    {SDL_SCANCODE_Q, "Q"}, {SDL_SCANCODE_R, "R"}, {SDL_SCANCODE_S, "S"}, {SDL_SCANCODE_T, "T"},
    {SDL_SCANCODE_U, "U"}, {SDL_SCANCODE_V, "V"}, {SDL_SCANCODE_W, "W"}, {SDL_SCANCODE_X, "X"},
    {SDL_SCANCODE_Y, "Y"}, {SDL_SCANCODE_Z, "Z"},
    {SDL_SCANCODE_1, "1"}, {SDL_SCANCODE_2, "2"}, {SDL_SCANCODE_3, "3"}, {SDL_SCANCODE_4, "4"},
    {SDL_SCANCODE_5, "5"}, {SDL_SCANCODE_6, "6"}, {SDL_SCANCODE_7, "7"}, {SDL_SCANCODE_8, "8"},
    {SDL_SCANCODE_9, "9"}, {SDL_SCANCODE_0, "0"},
    {SDL_SCANCODE_RETURN, "Return"}, {SDL_SCANCODE_ESCAPE, "Escape"}, {SDL_SCANCODE_BACKSPACE, "Backspace"},
    {SDL_SCANCODE_TAB, "Tab"}, {SDL_SCANCODE_SPACE, "Space"}, {SDL_SCANCODE_MINUS, "-"},
    {SDL_SCANCODE_EQUALS, "="}, {SDL_SCANCODE_LEFTBRACKET, "["}, {SDL_SCANCODE_RIGHTBRACKET, "]"},
    {SDL_SCANCODE_BACKSLASH, "\\"}, {SDL_SCANCODE_NONUSHASH, "#"}, {SDL_SCANCODE_SEMICOLON, ";"},
    {SDL_SCANCODE_APOSTROPHE, "'"}, {SDL_SCANCODE_GRAVE, "`"}, {SDL_SCANCODE_COMMA, ","},
    {SDL_SCANCODE_PERIOD, "."}, {SDL_SCANCODE_SLASH, "/"}, {SDL_SCANCODE_CAPSLOCK, "CapsLock"},
    {SDL_SCANCODE_F1, "F1"}, {SDL_SCANCODE_F2, "F2"}, {SDL_SCANCODE_F3, "F3"}, {SDL_SCANCODE_F4, "F4"},
    {SDL_SCANCODE_F5, "F5"}, {SDL_SCANCODE_F6, "F6"}, {SDL_SCANCODE_F7, "F7"}, {SDL_SCANCODE_F8, "F8"},
    {SDL_SCANCODE_F9, "F9"}, {SDL_SCANCODE_F10, "F10"}, {SDL_SCANCODE_F11, "F11"}, {SDL_SCANCODE_F12, "F12"},
    {SDL_SCANCODE_PAUSE, "Pause"}, {SDL_SCANCODE_INSERT, "Insert"}, {SDL_SCANCODE_HOME, "Home"},
    {SDL_SCANCODE_PAGEUP, "PageUp"}, {SDL_SCANCODE_DELETE, "Delete"}, {SDL_SCANCODE_END, "End"},
    {SDL_SCANCODE_PAGEDOWN, "PageDown"}, {SDL_SCANCODE_RIGHT, "Right"}, {SDL_SCANCODE_LEFT, "Left"},
    {SDL_SCANCODE_DOWN, "Down"}, {SDL_SCANCODE_UP, "Up"},
    {SDL_SCANCODE_KP_DIVIDE, "Keypad /"}, {SDL_SCANCODE_KP_MULTIPLY, "Keypad *"},
    {SDL_SCANCODE_KP_MINUS, "Keypad -"}, {SDL_SCANCODE_KP_PLUS, "Keypad +"},
    {SDL_SCANCODE_KP_ENTER, "Keypad Enter"}, {SDL_SCANCODE_KP_1, "Keypad 1"}, {SDL_SCANCODE_KP_2, "Keypad 2"},
    {SDL_SCANCODE_KP_3, "Keypad 3"}, {SDL_SCANCODE_KP_4, "Keypad 4"}, {SDL_SCANCODE_KP_5, "Keypad 5"},
    {SDL_SCANCODE_KP_6, "Keypad 6"}, {SDL_SCANCODE_KP_7, "Keypad 7"}, {SDL_SCANCODE_KP_8, "Keypad 8"},
    {SDL_SCANCODE_KP_9, "Keypad 9"}, {SDL_SCANCODE_KP_0, "Keypad 0"}, {SDL_SCANCODE_KP_PERIOD, "Keypad ."},
    {SDL_SCANCODE_NONUSBACKSLASH, "<"},
    {SDL_SCANCODE_LCTRL, "Left Ctrl"}, {SDL_SCANCODE_LSHIFT, "Left Shift"}, {SDL_SCANCODE_LALT, "Left Alt"},
    {SDL_SCANCODE_LGUI, "Left GUI"}, {SDL_SCANCODE_RCTRL, "Right Ctrl"}, {SDL_SCANCODE_RSHIFT, "Right Shift"},
    {SDL_SCANCODE_RALT, "Right Alt"}, {SDL_SCANCODE_RGUI, "Right GUI"},
};

const char *SDL_GetScancodeName(SDL_Scancode sc)
{
    for (size_t i = 0; i < sizeof sc_names / sizeof sc_names[0]; i++)
        if (sc_names[i].sc == sc) return sc_names[i].name;
    return "";
}

SDL_Scancode SDL_GetScancodeFromName(const char *name)
{
    if (!name || !*name) return SDL_SCANCODE_UNKNOWN;
    for (size_t i = 0; i < sizeof sc_names / sizeof sc_names[0]; i++)
        if (!strcasecmp(sc_names[i].name, name)) return (SDL_Scancode)sc_names[i].sc;
    return SDL_SCANCODE_UNKNOWN;
}

/* SDL's default key for a scancode (an US keyboard) */
static SDL_Keycode sc_key(SDL_Scancode sc)
{
    if (sc >= SDL_SCANCODE_A && sc <= SDL_SCANCODE_Z) return 'a' + (sc - SDL_SCANCODE_A);
    if (sc >= SDL_SCANCODE_1 && sc <= SDL_SCANCODE_9) return '1' + (sc - SDL_SCANCODE_1);
    switch (sc) {
    case SDL_SCANCODE_0: return '0';
    case SDL_SCANCODE_RETURN: return SDLK_RETURN;
    case SDL_SCANCODE_ESCAPE: return SDLK_ESCAPE;
    case SDL_SCANCODE_BACKSPACE: return SDLK_BACKSPACE;
    case SDL_SCANCODE_TAB: return SDLK_TAB;
    case SDL_SCANCODE_SPACE: return SDLK_SPACE;
    case SDL_SCANCODE_MINUS: return '-';
    case SDL_SCANCODE_EQUALS: return '=';
    case SDL_SCANCODE_LEFTBRACKET: return '[';
    case SDL_SCANCODE_RIGHTBRACKET: return ']';
    case SDL_SCANCODE_BACKSLASH: return '\\';
    case SDL_SCANCODE_NONUSHASH: return '#';
    case SDL_SCANCODE_SEMICOLON: return ';';
    case SDL_SCANCODE_APOSTROPHE: return '\'';
    case SDL_SCANCODE_GRAVE: return '`';
    case SDL_SCANCODE_COMMA: return ',';
    case SDL_SCANCODE_PERIOD: return '.';
    case SDL_SCANCODE_SLASH: return '/';
    case SDL_SCANCODE_NONUSBACKSLASH: return '<';
    case SDL_SCANCODE_DELETE: return SDLK_DELETE;
    default: return SDL_SCANCODE_TO_KEYCODE(sc);
    }
}

SDL_Keycode SDL_GetKeyFromScancode(SDL_Scancode sc) { return sc_key(sc); }

SDL_Scancode SDL_GetScancodeFromKey(SDL_Keycode key)
{
    for (int sc = 0; sc < SDL_NUM_SCANCODES; sc++)
        if (sc_key((SDL_Scancode)sc) == key) return (SDL_Scancode)sc;
    return SDL_SCANCODE_UNKNOWN;
}

static Uint8 g_keystate[SDL_NUM_SCANCODES];
const Uint8 *SDL_GetKeyboardState(int *n) { if (n) *n = SDL_NUM_SCANCODES; amiga_video_pump(); return g_keystate; }

/* ------------------------------------------------------------------ events */

#define EVQ 128
static SDL_Event g_evq[EVQ];
static int g_evq_head, g_evq_tail;

static void ev_put(const SDL_Event *e)
{
    int n = (g_evq_head + 1) % EVQ;
    if (n == g_evq_tail) return;                        /* full: dropped */
    g_evq[g_evq_head] = *e;
    g_evq_head = n;
}

int SDL_PushEvent(SDL_Event *e) { ev_put(e); return 1; }

/* a raw key from the window (amiga_video.c) */
void amiga_key(unsigned code, unsigned qual)
{
    unsigned raw = code & 0x7f;
    int up = (code & IECODE_UP_PREFIX) != 0;
    if (raw >= sizeof raw2sc / sizeof raw2sc[0] || !raw2sc[raw]) return;
    SDL_Scancode sc = (SDL_Scancode)raw2sc[raw];
    SDL_Event e;
    memset(&e, 0, sizeof e);
    e.type = up ? SDL_KEYUP : SDL_KEYDOWN;
    e.key.timestamp = SDL_GetTicks();
    e.key.state = up ? SDL_RELEASED : SDL_PRESSED;
    e.key.repeat = !up && (qual & IEQUALIFIER_REPEAT) && g_keystate[sc];
    e.key.keysym.scancode = sc;
    e.key.keysym.sym = pk_quiet_raw(raw) ? SDLK_UNKNOWN : sc_key(sc);   /* (a control's keypad ( / ): only that, padkeys.h) */
    g_keystate[sc] = !up;
    ev_put(&e);
}

/* the window lost the keyboard: every key is let go */
void amiga_keys_released(void)
{
    for (int sc = 0; sc < SDL_NUM_SCANCODES; sc++) {
        if (!g_keystate[sc]) continue;
        SDL_Event e;
        memset(&e, 0, sizeof e);
        e.type = SDL_KEYUP;
        e.key.timestamp = SDL_GetTicks();
        e.key.state = SDL_RELEASED;
        e.key.keysym.scancode = (SDL_Scancode)sc;
        e.key.keysym.sym = sc_key((SDL_Scancode)sc);
        g_keystate[sc] = 0;
        ev_put(&e);
    }
}

void amiga_mouse_moved(int dx, int dy)
{
    SDL_Event e;
    memset(&e, 0, sizeof e);
    e.type = SDL_MOUSEMOTION;
    e.motion.timestamp = SDL_GetTicks();
    e.motion.xrel = dx; e.motion.yrel = dy;
    ev_put(&e);
}

void amiga_quit_event(void)
{
    SDL_Event e;
    memset(&e, 0, sizeof e);
    e.type = SDL_QUIT;
    e.quit.timestamp = SDL_GetTicks();
    ev_put(&e);
}

static void pad_poll(void);

void SDL_PumpEvents(void)
{
    if (SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C) amiga_quit_event();   /* BREAK from the shell */
    amiga_video_pump();
    pad_poll();
}

int SDL_PollEvent(SDL_Event *e)
{
    SDL_PumpEvents();
    if (g_evq_tail == g_evq_head) return 0;
    if (e) { *e = g_evq[g_evq_tail]; g_evq_tail = (g_evq_tail + 1) % EVQ; }
    return 1;
}

/* ------------------------------------------------------------------ the pad: a CD32 pad or joystick in port 2 */

struct _SDL_GameController { int open; };
static struct _SDL_GameController g_pad;
static int g_pad_kind = -1;                          /* port 2's: JP_TYPE_*, -1 not yet asked */

/* (lowlevel.library's first ReadJoyPort of a port answers JP_TYPE_UNKNOWN -- FS-UAE with a CD32 pad: 0x40000000,
   then 0x10000000 from the second call on --: so the first time it is asked again until it knows (a few
   frames at most), later once a call -- the game asks every frame while it has no pad --, and "none" is never kept) */
static int pad_kind(void)
{
    static int asked;
    if (!LowLevelBase) return 0;
    ULONG t = JP_TYPE_UNKNOWN;
    for (int i = 0; i < (asked ? 1 : 8) && t == JP_TYPE_UNKNOWN; i++) {
        if (i >= 2) Delay(1);
        t = ReadJoyPort(1) & JP_TYPE_MASK;
    }
    asked = 1;
    return t == JP_TYPE_GAMECTLR || t == JP_TYPE_JOYSTK ? (int)t : 0;
}

int SDL_NumJoysticks(void)
{
    if (g_pad_kind <= 0) g_pad_kind = pad_kind();
    return g_pad_kind ? 1 : 0;
}

SDL_bool SDL_IsGameController(int i) { return i == 0 && SDL_NumJoysticks() ? SDL_TRUE : SDL_FALSE; }
SDL_GameController *SDL_GameControllerOpen(int i)
{
    if (!SDL_IsGameController(i)) return NULL;
    g_pad.open = 1;
    amiga_log("pad: %s in port 2\n", SDL_JoystickNameForIndex(0));
    return (SDL_GameController *)&g_pad;
}
void SDL_GameControllerClose(SDL_GameController *c) { (void)c; g_pad.open = 0; }
void SDL_GameControllerUpdate(void) { pad_poll(); }
SDL_Joystick *SDL_GameControllerGetJoystick(SDL_GameController *c) { return (SDL_Joystick *)c; }
SDL_JoystickID SDL_JoystickInstanceID(SDL_Joystick *j) { (void)j; return 0; }
int SDL_GameControllerRumble(SDL_GameController *c, Uint16 a, Uint16 b, Uint32 ms) { (void)c; (void)a; (void)b; (void)ms; return -1; }
int SDL_GameControllerAddMapping(const char *m) { (void)m; return 0; }
const char *SDL_JoystickNameForIndex(int i) { (void)i; return g_pad_kind == JP_TYPE_GAMECTLR ? "CD32 pad" : "Joystick"; }
SDL_JoystickGUID SDL_JoystickGetDeviceGUID(int i) { SDL_JoystickGUID g; (void)i; memset(&g, 0, sizeof g); return g; }
void SDL_JoystickGetGUIDString(SDL_JoystickGUID g, char *s, int n) { (void)g; if (n > 0) s[0] = 0; }

/* the CD32 pad's buttons (lowlevel.library) in padkeys.h's order: in a race the launcher's actions
   (CONFIG/AMIGA.CFG PADGAS .. PADPAUSE), out of it the menus' -- padkeys.h */
static const ULONG pad_jpf[PK_N] = {
    JPF_JOY_LEFT, JPF_JOY_RIGHT, JPF_JOY_UP, JPF_JOY_DOWN, JPF_BUTTON_RED, JPF_BUTTON_BLUE, JPF_BUTTON_GREEN,
    JPF_BUTTON_YELLOW, JPF_BUTTON_PLAY, JPF_BUTTON_FORWARD, JPF_BUTTON_REVERSE,
};

static void pad_emit(int button, int down)
{
    SDL_Event e;
    memset(&e, 0, sizeof e);
    e.type = down ? SDL_CONTROLLERBUTTONDOWN : SDL_CONTROLLERBUTTONUP;
    e.cbutton.timestamp = SDL_GetTicks();
    e.cbutton.button = (Uint8)button;
    e.cbutton.state = down ? SDL_PRESSED : SDL_RELEASED;
    ev_put(&e);
}

static void pad_poll(void)
{
    if (!g_pad.open || !LowLevelBase) return;
    ULONG st = ReadJoyPort(1);
    ULONG t = st & JP_TYPE_MASK;
    if (t != JP_TYPE_GAMECTLR && t != JP_TYPE_JOYSTK) st = 0;
    unsigned now = 0;
    for (int k = 0; k < PK_N; k++)
        if (st & pad_jpf[k]) now |= 1u << k;
    pk_update(now, pad_emit);
}

Uint8 SDL_GameControllerGetButton(SDL_GameController *c, SDL_GameControllerButton b)
{
    (void)c;
    return (Uint8)pk_button((int)b);
}

/* (a joystick has no sticks or triggers to measure: the d-pad is its steering) */
Sint16 SDL_GameControllerGetAxis(SDL_GameController *c, SDL_GameControllerAxis a) { (void)c; (void)a; return 0; }

/* (SDL's own allocations: the C library's, which the change of part does not free) */
#undef SDL_calloc
#undef SDL_free
void *SDL_calloc(size_t n, size_t each) { return calloc(n, each); }
void SDL_free(void *p) { free(p); }
