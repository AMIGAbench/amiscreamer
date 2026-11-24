/* THE RELEASE BUILD (Amiga, MorphOS; not DEBUG=1, which is amiscreamer_debug_*): the test switches are not in it.
 *
 * Nearly all of the program's test switches are environment variables, OS_<name>, read with getenv() and a
 * string written into the call.  Here getenv() of every OS_ name that is not in the list below is a constant
 * NULL -- gcc folds the comparisons of the two written strings -- so each switch is "not set" and the compiler
 * leaves out the code it guards (the logs, dumps, screenshots, test drives, comparisons, timers ...).
 *
 * The list: what the program does need -- the variables it hands from one of its parts to the next (menu ->
 * race -> menu, set by itself), and the settings of the launcher / CONFIG/AMIGA.CFG / the launcher's options
 * (amiga/oldargs.c).  Names that are not OS_ (SCREAMER_*, OPENSCREAMER_*, HOME ...) are all kept. */
#ifndef OS_RELEASE_H
#define OS_RELEASE_H
#include <stdlib.h>
#include <string.h>

#define OS_REL_IS(n, s) (strcmp((n), s) == 0)
static inline __attribute__((always_inline)) int os_rel_keep(const char *n)
{
    if (strncmp(n, "OS_", 3) != 0) return 1;
    return
        /* handed on between the program's parts (setenv in main.c / port.c) */
        OS_REL_IS(n, "OS_DIFF") || OS_REL_IS(n, "OS_LAPS") || OS_REL_IS(n, "OS_MODE") || OS_REL_IS(n, "OS_RES") ||
        OS_REL_IS(n, "OS_AGA") || OS_REL_IS(n, "OS_REPLAYFILE") || OS_REL_IS(n, "OS_FROM_MENU") ||
        OS_REL_IS(n, "OS_CHEAT") || OS_REL_IS(n, "OS_CHAMP") || OS_REL_IS(n, "OS_CHAMP_RESULT") ||
        OS_REL_IS(n, "OS_CAR") || OS_REL_IS(n, "OS_TRACK") || OS_REL_IS(n, "OS_TEAM") || OS_REL_IS(n, "OS_COND") ||
        OS_REL_IS(n, "OS_KEEP_LAPS") || OS_REL_IS(n, "OS_KEEP_DIFF") || OS_REL_IS(n, "OS_KEEP_CHEAT") ||
        OS_REL_IS(n, "OS_INTRO") || OS_REL_IS(n, "OS_INTRO_DONE") || OS_REL_IS(n, "OS_GHOST") ||
        OS_REL_IS(n, "OS_NOSPEECH") || OS_REL_IS(n, "OS_NOMUSIC") || OS_REL_IS(n, "OS_MENU_GOTO") ||
        OS_REL_IS(n, "OS_FPS") || OS_REL_IS(n, "OS_ONETHREAD") || OS_REL_IS(n, "OS_GAME_CHOSEN") ||
        OS_REL_IS(n, "OS_FROM_RACE_OPTS") ||
        /* the launcher, CONFIG/AMIGA.CFG, the launcher's options (oldargs.c) */
        OS_REL_IS(n, "OS_NETMODE") || OS_REL_IS(n, "OS_NETHOST") || OS_REL_IS(n, "OS_MUSICDIR") ||
        OS_REL_IS(n, "OS_WINDOW") || OS_REL_IS(n, "OS_FREEFLY") ||
        OS_REL_IS(n, "OS_PADGAS") || OS_REL_IS(n, "OS_PADBRAKE") || OS_REL_IS(n, "OS_PADLEFT") ||
        OS_REL_IS(n, "OS_PADRIGHT") || OS_REL_IS(n, "OS_PADUP") || OS_REL_IS(n, "OS_PADDOWN") ||
        OS_REL_IS(n, "OS_PADPAUSE")
#ifdef OS_REL_TEST      /* (tools/qemu_test.sh REL=2: the release with only the switches that take a picture of the
                           same drive -- to compare it with the debug build's) */
        || OS_REL_IS(n, "OS_SHOTAT") || OS_REL_IS(n, "OS_TICKS") || OS_REL_IS(n, "OS_DRIVE_DEMO") ||
        OS_REL_IS(n, "OS_NOSOUND")
#endif
        ;
}
#define getenv(n) (os_rel_keep(n) ? (getenv)(n) : (char *)0)

/* AND NOT ITS REPORTS IN THE SHELL: printf, fprintf(stderr, ...) and amiga_log (amiga_video.c) give nothing, the
 * compiler leaves out the call and its text -- what was loaded, which routines are on, the test results, the
 * timings.  A message for the player -- the version, the check of the game's files, --help, and what went wrong
 * (a file missing or damaged, no screen, no sound, no memory) -- is written (printf)(...) / (fprintf)(stderr, ...)
 * / (amiga_log)(...): the brackets keep the name from this macro, and it stays.  fprintf to a file stays. */
#include <stdio.h>
#define OS_REL_P_stderr ~, 1                         /* (fprintf's first argument written "stderr": 1, else 0) */
#define OS_REL_2ND(a, b, ...) b
#define OS_REL_2ND_(...) OS_REL_2ND(__VA_ARGS__)
#define OS_REL_CAT_(a, b) a##b
#define OS_REL_CAT(a, b) OS_REL_CAT_(a, b)
#define OS_REL_FPSEL(p, f, ...) OS_REL_CAT(OS_REL_FP_, OS_REL_2ND_(p, 0, ~))(f, __VA_ARGS__)
#define OS_REL_FP_0(f, ...) (fprintf)(f, __VA_ARGS__)
#define OS_REL_FP_1(f, ...) 0
#define fprintf(f, ...) OS_REL_FPSEL(OS_REL_P_##f, f, __VA_ARGS__)
#define printf(...) 0
#define amiga_log(...) ((void)0)
#endif
