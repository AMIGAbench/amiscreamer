/*
 * padkeys.h - THE KEYS AND THE CD32 PAD AS THE LAUNCHER HAS THEM.
 * (Included ONCE, by sdl_amiga.c -- or by sdl_null.c in the big-endian qemu test build, so that the tables can be
 * checked there: OS_CTRLLOG=1.  Its amiga_* functions are not static: controls.c calls them.)
 *
 * KEYS.  The launcher ("Screamer Starter", installer_amiga/launcher) turns an Amiga raw key into a DOS set-1 scan
 * code with ONE table (installer_amiga/launcher/rawkey.h, s_raw2set1 below, unchanged); CONFIG/CONTROLS.CFG keeps the
 * set-1 code.  A control then belongs to every raw key whose set-1 code is the file's -- e.g. 0x48 is Cursor Up AND
 * the keypad's 8, 0x2b is "\" AND the German "#" key, 0x35 is "/" AND the keypad's "/".  Here a raw key is an SDL
 * scancode (raw2sc, by position), so the file's code is turned back into those raw keys' scancodes (amiga_set1_keys):
 * exactly the launcher's keys.  The keypad's ( and ), this port's PAUSE and F12, are only their control's when the
 * launcher made them one.
 *
 * PAD.  CONFIG/AMIGA.CFG PADGAS PADBRAKE PADLEFT PADRIGHT PADUP PADDOWN PADPAUSE (the launcher's; oldargs.c makes
 * them OS_PADGAS ...) = the button of each action in a race: LEFT RIGHT UP DOWN (the d-pad) RED BLUE GREEN YELLOW
 * PLAY FWD REV, or NONE; without them RED BLUE LEFT RIGHT FWD REV PLAY.
 * In a race a button does its action and nothing else, a button of
 * no action does nothing -- except green and yellow, which keep this port's own radar zoom / view (X / Y), when no
 * action has them.  Out of a race (menus, the end, a replay, the pause screen) the pad is the menus': the d-pad the
 * arrows, red / play ENTER, blue / reverse ESC.  A button held as the race starts or ends does
 * nothing until it has been let go.
 */

/* Amiga raw key -> DOS set 1 (the launcher's rawkey.h, unchanged; 0 = no key) */
static const uint8_t s_raw2set1[0x68] = {
    /* 00 */ 0x29, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x2b, 0x00, 0x52,
    /* 10 */ 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x00, 0x4f, 0x50, 0x51,
    /* 20 */ 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2b, 0x00, 0x4b, 0x4c, 0x4d,
    /* 30 */ 0x56, 0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x00, 0x53, 0x47, 0x48, 0x49,
    /* 40 */ 0x39, 0x0e, 0x0f, 0x1c, 0x1c, 0x01, 0x53, 0x00, 0x00, 0x00, 0x4a, 0x00, 0x48, 0x50, 0x4d, 0x4b,
    /* 50 */ 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x35, 0x37, 0x4e, 0x57,
    /* 60 */ 0x2a, 0x36, 0x3a, 0x1d, 0x38, 0x38, 0x00, 0x00,
};

/* Amiga raw key (by position) -> SDL scancode */
static const Uint16 raw2sc[0x68] = {
    [0x00] = SDL_SCANCODE_GRAVE,
    [0x01] = SDL_SCANCODE_1, [0x02] = SDL_SCANCODE_2, [0x03] = SDL_SCANCODE_3, [0x04] = SDL_SCANCODE_4,
    [0x05] = SDL_SCANCODE_5, [0x06] = SDL_SCANCODE_6, [0x07] = SDL_SCANCODE_7, [0x08] = SDL_SCANCODE_8,
    [0x09] = SDL_SCANCODE_9, [0x0a] = SDL_SCANCODE_0, [0x0b] = SDL_SCANCODE_MINUS, [0x0c] = SDL_SCANCODE_EQUALS,
    [0x0d] = SDL_SCANCODE_BACKSLASH, [0x0f] = SDL_SCANCODE_KP_0,
    [0x10] = SDL_SCANCODE_Q, [0x11] = SDL_SCANCODE_W, [0x12] = SDL_SCANCODE_E, [0x13] = SDL_SCANCODE_R,
    [0x14] = SDL_SCANCODE_T, [0x15] = SDL_SCANCODE_Y, [0x16] = SDL_SCANCODE_U, [0x17] = SDL_SCANCODE_I,
    [0x18] = SDL_SCANCODE_O, [0x19] = SDL_SCANCODE_P, [0x1a] = SDL_SCANCODE_LEFTBRACKET,
    [0x1b] = SDL_SCANCODE_RIGHTBRACKET, [0x1d] = SDL_SCANCODE_KP_1, [0x1e] = SDL_SCANCODE_KP_2,
    [0x1f] = SDL_SCANCODE_KP_3,
    [0x20] = SDL_SCANCODE_A, [0x21] = SDL_SCANCODE_S, [0x22] = SDL_SCANCODE_D, [0x23] = SDL_SCANCODE_F,
    [0x24] = SDL_SCANCODE_G, [0x25] = SDL_SCANCODE_H, [0x26] = SDL_SCANCODE_J, [0x27] = SDL_SCANCODE_K,
    [0x28] = SDL_SCANCODE_L, [0x29] = SDL_SCANCODE_SEMICOLON, [0x2a] = SDL_SCANCODE_APOSTROPHE,
    [0x2b] = SDL_SCANCODE_NONUSHASH, [0x2d] = SDL_SCANCODE_KP_4, [0x2e] = SDL_SCANCODE_KP_5,
    [0x2f] = SDL_SCANCODE_KP_6,
    [0x30] = SDL_SCANCODE_NONUSBACKSLASH,
    [0x31] = SDL_SCANCODE_Z, [0x32] = SDL_SCANCODE_X, [0x33] = SDL_SCANCODE_C, [0x34] = SDL_SCANCODE_V,
    [0x35] = SDL_SCANCODE_B, [0x36] = SDL_SCANCODE_N, [0x37] = SDL_SCANCODE_M, [0x38] = SDL_SCANCODE_COMMA,
    [0x39] = SDL_SCANCODE_PERIOD, [0x3a] = SDL_SCANCODE_SLASH, [0x3c] = SDL_SCANCODE_KP_PERIOD,
    [0x3d] = SDL_SCANCODE_KP_7, [0x3e] = SDL_SCANCODE_KP_8, [0x3f] = SDL_SCANCODE_KP_9,
    [0x40] = SDL_SCANCODE_SPACE, [0x41] = SDL_SCANCODE_BACKSPACE, [0x42] = SDL_SCANCODE_TAB,
    [0x43] = SDL_SCANCODE_KP_ENTER, [0x44] = SDL_SCANCODE_RETURN, [0x45] = SDL_SCANCODE_ESCAPE,
    [0x46] = SDL_SCANCODE_DELETE, [0x47] = SDL_SCANCODE_INSERT, [0x48] = SDL_SCANCODE_PAGEUP,
    [0x49] = SDL_SCANCODE_PAGEDOWN, [0x4a] = SDL_SCANCODE_KP_MINUS, [0x4b] = SDL_SCANCODE_F11,
    [0x4c] = SDL_SCANCODE_UP, [0x4d] = SDL_SCANCODE_DOWN, [0x4e] = SDL_SCANCODE_RIGHT, [0x4f] = SDL_SCANCODE_LEFT,
    [0x50] = SDL_SCANCODE_F1, [0x51] = SDL_SCANCODE_F2, [0x52] = SDL_SCANCODE_F3, [0x53] = SDL_SCANCODE_F4,
    [0x54] = SDL_SCANCODE_F5, [0x55] = SDL_SCANCODE_F6, [0x56] = SDL_SCANCODE_F7, [0x57] = SDL_SCANCODE_F8,
    [0x58] = SDL_SCANCODE_F9, [0x59] = SDL_SCANCODE_F10,
    /* the keypad's ( and ): the PC's PAUSE and F12 (the Amiga has neither); HELP = F11 */
    [0x5a] = SDL_SCANCODE_PAUSE, [0x5b] = SDL_SCANCODE_F12,
    [0x5c] = SDL_SCANCODE_KP_DIVIDE, [0x5d] = SDL_SCANCODE_KP_MULTIPLY, [0x5e] = SDL_SCANCODE_KP_PLUS,
    [0x5f] = SDL_SCANCODE_F11,
    [0x60] = SDL_SCANCODE_LSHIFT, [0x61] = SDL_SCANCODE_RSHIFT, [0x62] = SDL_SCANCODE_CAPSLOCK,
    [0x63] = SDL_SCANCODE_LCTRL, [0x64] = SDL_SCANCODE_LALT, [0x65] = SDL_SCANCODE_RALT,
    [0x66] = SDL_SCANCODE_LGUI, [0x67] = SDL_SCANCODE_RGUI,
};

/* CONTROLS.CFG's set-1 code -> the scancodes of the Amiga keys that are it (up to two; the rest UNKNOWN) */
int amiga_set1_keys(int set1, SDL_Scancode out[2])
{
    int n = 0;
    out[0] = out[1] = SDL_SCANCODE_UNKNOWN;
    if (set1 <= 0 || set1 > 0x7f) return 0;
    for (unsigned r = 0; r < sizeof s_raw2set1 && n < 2; r++)
        if (s_raw2set1[r] == set1 && raw2sc[r]) out[n++] = (SDL_Scancode)raw2sc[r];
    return n;
}

/* ------------------------------------------------------------------ the pad */

/* the pad's eleven, in the launcher's order (its PB_*, AMIGA.CFG's names) */
enum { PK_LEFT, PK_RIGHT, PK_UP, PK_DOWN, PK_RED, PK_BLUE, PK_GREEN, PK_YELLOW, PK_PLAY, PK_FWD, PK_REV, PK_N };
static const char *const pk_name[PK_N] = { "LEFT", "RIGHT", "UP", "DOWN", "RED", "BLUE", "GREEN", "YELLOW", "PLAY",
                                           "FWD", "REV" };
/* the actions (AMIGA.CFG's order) and what controls.c reads for each in a race */
static const char *const pk_act_env[7] = { "OS_PADGAS", "OS_PADBRAKE", "OS_PADLEFT", "OS_PADRIGHT", "OS_PADUP",
                                           "OS_PADDOWN", "OS_PADPAUSE" };
static const int pk_act_sdl[7] = { SDL_CONTROLLER_BUTTON_A, SDL_CONTROLLER_BUTTON_B, SDL_CONTROLLER_BUTTON_DPAD_LEFT,
                                   SDL_CONTROLLER_BUTTON_DPAD_RIGHT, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER,
                                   SDL_CONTROLLER_BUTTON_LEFTSHOULDER, SDL_CONTROLLER_BUTTON_START };
static const signed char pk_act_def[7] = { PK_RED, PK_BLUE, PK_LEFT, PK_RIGHT, PK_FWD, PK_REV, PK_PLAY };
/* out of a race: the menus' (controls.c button_key: A ENTER, B / BACK ESC, START ENTER, the d-pad the arrows) */
static const int pk_menu_sdl[PK_N] = {
    SDL_CONTROLLER_BUTTON_DPAD_LEFT, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, SDL_CONTROLLER_BUTTON_DPAD_UP,
    SDL_CONTROLLER_BUTTON_DPAD_DOWN, SDL_CONTROLLER_BUTTON_A, SDL_CONTROLLER_BUTTON_B, SDL_CONTROLLER_BUTTON_X,
    SDL_CONTROLLER_BUTTON_Y, SDL_CONTROLLER_BUTTON_START, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER,
    SDL_CONTROLLER_BUTTON_BACK,
};

static signed char pk_act[PK_N];           /* each button's action in a race (-1 none) */
static int pk_read_done, pk_menu = 1;
static unsigned pk_state, pk_lock;         /* the buttons down (1 << PK_*); held over a change of race / menu */
static int pk_down_as[PK_N];               /* the SDL button each went down as (-1 none) */

static void pk_read(void)
{
    signed char a_of[7];
    int any = 0;
    pk_read_done = 1;
    for (int a = 0; a < 7; a++) {
        a_of[a] = pk_act_def[a];
        const char *v = getenv(pk_act_env[a]);
        if (!v || !*v) continue;
        if (!strcmp(v, "NONE")) { a_of[a] = -1; any = 1; continue; }
        for (int k = 0; k < PK_N; k++)
            if (!strcmp(v, pk_name[k])) { a_of[a] = (signed char)k; any = 1; }
    }
    for (int k = 0; k < PK_N; k++) { pk_act[k] = -1; pk_down_as[k] = -1; }
    for (int a = 0; a < 7; a++)                                        /* (one button, two actions: the later, as input.c) */
        if (a_of[a] >= 0) pk_act[a_of[a]] = (signed char)a;
    if (any) printf("pad: the buttons from CONFIG/AMIGA.CFG (the launcher's)\n");
}

/* a button's SDL button in a race: its action's; none for one of no action -- but green / yellow keep X / Y */
static int pk_race_sdl(int k)
{
    if (pk_act[k] >= 0) return pk_act_sdl[pk_act[k]];
    if (k == PK_GREEN) return SDL_CONTROLLER_BUTTON_X;
    if (k == PK_YELLOW) return SDL_CONTROLLER_BUTTON_Y;
    return -1;
}

/* controls.c: a race is being driven (0) or not (1) */
void amiga_pad_menu(int on)
{
    on = on != 0;
    if (on == pk_menu) return;
    pk_menu = on;
    pk_lock = pk_state;                                               /* (held buttons: nothing until let go) */
}

/* the pad's buttons now (1 << PK_*): its events, each button's up as the button it went down as */
static void pk_update(unsigned now, void (*emit)(int sdl_button, int down))
{
    if (!pk_read_done) pk_read();
    const unsigned changed = now ^ pk_state;
    pk_state = now;
    pk_lock &= now;
    for (int k = 0; k < PK_N; k++) {
        if (!(changed & 1u << k)) continue;
        if (now & 1u << k) {
            const int b = (pk_lock & 1u << k) ? -1 : pk_menu ? pk_menu_sdl[k] : pk_race_sdl(k);
            pk_down_as[k] = b;
            if (b >= 0) emit(b, 1);
        } else {
            if (pk_down_as[k] >= 0) emit(pk_down_as[k], 0);
            pk_down_as[k] = -1;
        }
    }
}

/* SDL_GameControllerGetButton: held in a race -- any button whose action is that button's (none held over) */
static int pk_button(int sdl_button)
{
    if (!pk_read_done) pk_read();
    const unsigned live = pk_state & ~pk_lock;
    for (int k = 0; k < PK_N; k++)
        if ((live & 1u << k) && pk_race_sdl(k) == sdl_button) return 1;
    return 0;
}

/* the keypad's ( and ) are this port's PAUSE and F12 (raw2sc); as set-1 0x45 / 0x46 they did nothing
   else, so one the launcher has made a control's key is only that control's: amiga_key sends it as no key */
static int pk_bound_pause, pk_bound_f12;
static int pk_quiet_raw(unsigned raw)
{
    return (raw == 0x5a && pk_bound_pause) || (raw == 0x5b && pk_bound_f12);
}

/* controls.c, once the keys are known: the keys of the six controls; OS_CTRLLOG=1: the keys and the pad as they will
   be */
static void amiga_controls_log(const int set1[6], const SDL_Scancode key[6][2]);
void amiga_controls_set(const int set1[6], const SDL_Scancode key[6][2])
{
    pk_bound_pause = pk_bound_f12 = 0;
    for (int i = 0; i < 6; i++)
        for (int j = 0; j < 2; j++) {
            if (key[i][j] == SDL_SCANCODE_PAUSE) pk_bound_pause = 1;
            if (key[i][j] == SDL_SCANCODE_F12) pk_bound_f12 = 1;
        }
    if (getenv("OS_CTRLLOG")) amiga_controls_log(set1, key);
}

static void amiga_controls_log(const int set1[6], const SDL_Scancode key[6][2])
{
    static const char *const act[7] = { "gas", "brake", "left", "right", "gear up", "gear down", "pause" };
    static const char *const sdlb[SDL_CONTROLLER_BUTTON_MAX] = {
        [SDL_CONTROLLER_BUTTON_A] = "A", [SDL_CONTROLLER_BUTTON_B] = "B", [SDL_CONTROLLER_BUTTON_X] = "X",
        [SDL_CONTROLLER_BUTTON_Y] = "Y", [SDL_CONTROLLER_BUTTON_BACK] = "BACK", [SDL_CONTROLLER_BUTTON_START] = "START",
        [SDL_CONTROLLER_BUTTON_LEFTSHOULDER] = "LSHOULDER", [SDL_CONTROLLER_BUTTON_RIGHTSHOULDER] = "RSHOULDER",
        [SDL_CONTROLLER_BUTTON_DPAD_UP] = "DPAD_UP", [SDL_CONTROLLER_BUTTON_DPAD_DOWN] = "DPAD_DOWN",
        [SDL_CONTROLLER_BUTTON_DPAD_LEFT] = "DPAD_LEFT", [SDL_CONTROLLER_BUTTON_DPAD_RIGHT] = "DPAD_RIGHT",
    };
    if (!pk_read_done) pk_read();
    for (int i = 0; i < 6; i++) {
        printf("ctrl: key %-9s set1 0x%02x -> amiga raw", act[i], set1[i]);
        for (int j = 0; j < 2; j++)
            for (unsigned r = 0; r < sizeof raw2sc / sizeof raw2sc[0]; r++)
                if (key[i][j] != SDL_SCANCODE_UNKNOWN && raw2sc[r] == key[i][j]) printf(" 0x%02x(sc %d)", r, (int)key[i][j]);
        printf("\n");
    }
    for (int k = 0; k < PK_N; k++) {
        const int r = pk_race_sdl(k);
        printf("ctrl: pad %-6s race: %-9s (%s)  menu: %s\n", pk_name[k], pk_act[k] >= 0 ? act[(int)pk_act[k]] : "-",
               r >= 0 ? sdlb[r] : "none", sdlb[pk_menu_sdl[k]]);
    }
}
