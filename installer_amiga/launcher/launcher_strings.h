#ifndef SCREAMER_LAUNCHER_STRINGS_H
#define SCREAMER_LAUNCHER_STRINGS_H
/* Texte des Starters: Nummer, eingebaute englische Fassung. Übersetzungen per Katalog amiscreamer_launcher.catalog
 * (src/launcher/<sprache>.ct, tools/catgen.py liest diese Liste). Nummern nie umbelegen, nur anhängen. */
#define LAUNCHER_STRINGS \
    S(MSG_TITLE,        0, "Screamer Launcher") \
    S(MSG_DESC,         1, "Starts Screamer with your settings") \
    S(MSG_G_PROGRAM,    2, "Program") \
    S(MSG_PROGRAM,      3, "Game program") \
    S(MSG_ASL_TITLE,    4, "Select the Screamer program") \
    S(MSG_G_GRAPHICS,   5, "Graphics") \
    S(MSG_SCREEN,       6, "Screen") \
    S(MSG_RTG640,       7, "RTG 640x400") \
    S(MSG_RTG320,       8, "RTG 320x200") \
    S(MSG_AGA320,       9, "AGA 320x200") \
    S(MSG_WINDOW,      10, "WB window") \
    S(MSG_SCALE,       11, "Window scale") \
    S(MSG_G_SOUND,     12, "Sound") \
    S(MSG_OUTPUT,      13, "Output") \
    S(MSG_PAULA,       14, "Paula") \
    S(MSG_AHI,         15, "AHI") \
    S(MSG_OFF,         16, "Off") \
    S(MSG_AHIMODE,     17, "AHI mode") \
    S(MSG_AHI_SELECT,  18, "_Select...") \
    S(MSG_AHI_DEFAULT, 19, "Default mode") \
    S(MSG_G_GAME,      21, "Game") \
    S(MSG_SINGLE,      22, "Single player") \
    S(MSG_MULTI,       23, "Multiplayer (network)") \
    S(MSG_HOST,        24, "Host") \
    S(MSG_JOIN,        25, "Join") \
    S(MSG_ADDRESS,     26, "Address") \
    S(MSG_PORT,        27, "Port") \
    S(MSG_START,       28, "_Start") \
    S(MSG_SAVE,        29, "S_ave") \
    S(MSG_QUIT,        30, "_Quit") \
    S(MSG_M_PROJECT,   31, "Project") \
    S(MSG_M_ABOUT,     32, "About...") \
    S(MSG_M_ABOUTMUI,  33, "About MUI...") \
    S(MSG_M_QUIT,      34, "Quit") \
    S(MSG_OK,          35, "_OK") \
    S(MSG_ABOUT_TEXT,  36, "Screamer Launcher %s\n\nAmiga port of Screamer (1995)\nSettings: CONFIG/AMIGA.CFG of the game") \
    S(MSG_ERR_PROG,    37, "Program '%s' not found.") \
    S(MSG_ERR_RUN,     38, "Program could not be started.") \
    S(MSG_ERR_RC,      39, "Program ended with error %ld.") \
    S(MSG_ERR_SAVE,    40, "Could not write '%s'.") \
    S(MSG_ERR_HOST,    41, "Please enter the address of the host or server.") \
    S(MSG_AHI_REQ,     42, "Select AHI mode") \
    S(MSG_ERR_MUI,     43, "Needs muimaster.library V19 (MUI 3.8) or newer.") \
    S(MSG_HOST_HINT,   44, "Others join with your address, UDP port 10623") \
    S(MSG_G_CONTROLS,  45, "Controls") \
    S(MSG_CONTROLS_BTN, 46, "_Keys and joypad...") \
    S(MSG_CTRL_TITLE,  47, "Screamer controls") \
    S(MSG_G_KEYS,      48, "Keyboard") \
    S(MSG_G_PAD,       49, "Joypad/joystick in the race") \
    S(MSG_A_GAS,       50, "Accelerate") \
    S(MSG_A_BRAKE,     51, "Brake") \
    S(MSG_A_LEFT,      52, "Steer left") \
    S(MSG_A_RIGHT,     53, "Steer right") \
    S(MSG_A_UP,        54, "Gear up") \
    S(MSG_A_DOWN,      55, "Gear down") \
    S(MSG_A_PAUSE,     56, "Pause") \
    S(MSG_CHANGE,      57, "Change") \
    S(MSG_DEFAULTS,    58, "Defaults") \
    S(MSG_CLOSE,       59, "_Close") \
    S(MSG_PRESS_KEY,   60, "Press a key for: %s  (Esc cancels)") \
    S(MSG_KEY_NONE,    61, "(none)") \
    S(MSG_PB_NONE,     62, "None") \
    S(MSG_PB_LEFT,     63, "Left") \
    S(MSG_PB_RIGHT,    64, "Right") \
    S(MSG_PB_UP,       65, "Up") \
    S(MSG_PB_DOWN,     66, "Down") \
    S(MSG_PB_RED,      67, "Red") \
    S(MSG_PB_BLUE,     68, "Blue") \
    S(MSG_PB_GREEN,    69, "Green") \
    S(MSG_PB_YELLOW,   70, "Yellow") \
    S(MSG_PB_PLAY,     71, "Play") \
    S(MSG_PB_FWD,      72, "Right shoulder") \
    S(MSG_PB_REV,      73, "Left shoulder") \
    S(MSG_ERR_CTRL,    74, "No CONFIG/CONTROLS.CFG or DEFCTRL.CFG next to '%s': keys are not saved.") \
    S(MSG_PRESS_KEY2,  75, "Press key...") \
    S(MSG_MODE,        76, "Mode") \
    S(MSG_NETROLE,     77, "Network") \
    S(MSG_CTRL_LABEL,  78, "Assignment")

#define S(name, id, txt) name = id,
enum { LAUNCHER_STRINGS MSG_COUNT };
#undef S

#endif
