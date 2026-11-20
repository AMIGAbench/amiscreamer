/*
 * oldargs.c - THE LAUNCHER'S WAY OF STARTING THE GAME (its options and CONFIG/AMIGA.CFG), so that the MUI launcher
 * (screamer_launcher) starts this port unchanged.
 *
 *  - Its options become this port's (main.c calls amiga_oldargs before os_init):
 *      --data DIR -> -data DIR          --music DIR -> OS_MUSICDIR      --lo / --hi -> OS_RES low / high
 *      --aga -> OS_AGA + low            --host / --join A[:P] -> OS_NETMODE host / join, OS_NETHOST
 *      --window / --scale N -> OS_WINDOW (1..3)   --race N -> a race on track N (as "build/dec/MAPn n")
 *      --track N -> a free flight over track N (OS_FREEFLY)   --car C -> OS_CAR   --mode M -> OS_MODE
 *    the launcher's test options (--fix-50fps --orig-50fps-bug --hudmap --prof --selftest --quick --st-* --span --rec
 *    --play --rec-frames --view) are taken and passed over, with a note.
 *  - CONFIG/AMIGA.CFG (the launcher's; in the data drawer: --data's, else PROGDIR:): SCREEN=RTG640|RTG320|AGA320,
 *    SOUND=PAULA|AHI|OFF, AHIMODE=<hex>, MUSIC=OFF, NETMODE=OFF|HOST|JOIN, NETHOST=, PADGAS..PADPAUSE -- as the
 *    variables above (and SCREAMER_SND, SCREAMER_AHIMODE, SCREAMER_MUSIC, OS_PAD*), never over one already set: the
 *    command line first, then the environment, then the file.
 * SCREAMER_SND / SCREAMER_AHIMODE / SCREAMER_AHIFREQ / SCREAMER_MUSIC are read where they act.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static void put(const char *name, const char *value, int over)
{
    setenv(name, value, over);
}

static void cfg_line(char *line)
{
    char *eq = strchr(line, '=');
    if (!eq) return;
    *eq = 0;
    char *k = line, *v = eq + 1;
    while (*k == ' ' || *k == '\t') k++;
    for (char *e = k + strlen(k); e > k && (e[-1] == ' ' || e[-1] == '\t'); ) *--e = 0;
    while (*v == ' ' || *v == '\t') v++;
    for (char *e = v + strlen(v); e > v && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\r' || e[-1] == '\n'); ) *--e = 0;
    char up[32];
    size_t n = strlen(v) < sizeof up - 1 ? strlen(v) : sizeof up - 1;
    for (size_t i = 0; i < n; i++) up[i] = (char)toupper((unsigned char)v[i]);
    up[n] = 0;
    if (!strcmp(k, "SCREEN")) {
        if (!strcmp(up, "RTG640")) put("OS_RES", "high", 0);
        else if (!strcmp(up, "RTG320")) put("OS_RES", "low", 0);
        else if (!strcmp(up, "AGA320")) {
            if (!getenv("OS_RES")) { put("OS_RES", "low", 0); put("OS_AGA", "1", 0); }
        }
    } else if (!strcmp(k, "SOUND")) {
        if (!strcmp(up, "AHI")) put("SCREAMER_SND", "ahi", 0);
        else if (!strcmp(up, "OFF")) put("SCREAMER_SND", "off", 0);
        else put("SCREAMER_SND", "paula", 0);
    } else if (!strcmp(k, "AHIMODE")) {
        if (*v) put("SCREAMER_AHIMODE", v, 0);
    } else if (!strcmp(k, "MUSIC")) {
        if (!strcmp(up, "OFF")) put("SCREAMER_MUSIC", "off", 0);
    } else if (!strcmp(k, "NETMODE")) {
        if (!strcmp(up, "HOST")) put("OS_NETMODE", "host", 0);
        else if (!strcmp(up, "JOIN")) put("OS_NETMODE", "join", 0);
    } else if (!strcmp(k, "NETHOST")) {
        if (*v) put("OS_NETHOST", v, 0);
    } else if (!strncmp(k, "PAD", 3) && strlen(k) < 16) {
        char name[24];
        snprintf(name, sizeof name, "OS_%s", k);           /* OS_PADGAS ... OS_PADPAUSE (sdl_amiga.c) */
        if (*up) put(name, up, 0);
    }
}

static void cfg_read(const char *dir)
{
    char path[600];
    if (!dir || !*dir) snprintf(path, sizeof path, "PROGDIR:CONFIG/AMIGA.CFG");
    else {
        const size_t n = strlen(dir);
        snprintf(path, sizeof path, "%s%sCONFIG/AMIGA.CFG", dir, dir[n - 1] == ':' || dir[n - 1] == '/' ? "" : "/");
    }
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[256];
    while (fgets(line, sizeof line, f)) cfg_line(line);
    fclose(f);
}

void amiga_oldargs(int *pargc, char ***pargv)
{
    static char *out[24];
    static char trk[2][24];
    int argc = *pargc, n = 0;
    char **argv = *pargv;
    const char *data = NULL;
    out[n++] = argv[0];
    int race = 0, fly = 0, any = 0;
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        const int more = i + 1 < argc;
        if (strncmp(a, "--", 2)) {                  /* this port's own (-data, a track, ...): as they are */
            if (n < 22) out[n++] = argv[i];
            continue;
        }
        any = 1;
        if (!strcmp(a, "--data") && more) { data = argv[++i]; if (n < 21) { out[n++] = "-data"; out[n++] = argv[i]; } }
        else if (!strcmp(a, "--music") && more) put("OS_MUSICDIR", argv[++i], 1);
        else if (!strcmp(a, "--lo")) put("OS_RES", "low", 1);
        else if (!strcmp(a, "--hi")) { put("OS_RES", "high", 1); unsetenv("OS_AGA"); }
        else if (!strcmp(a, "--aga")) { put("OS_AGA", "1", 1); put("OS_RES", "low", 1); }
        else if (!strcmp(a, "--host")) put("OS_NETMODE", "host", 1);
        else if (!strcmp(a, "--join") && more) { put("OS_NETMODE", "join", 1); put("OS_NETHOST", argv[++i], 1); }
        else if (!strcmp(a, "--window")) { if (!getenv("OS_WINDOW")) put("OS_WINDOW", "1", 1); }
        else if (!strcmp(a, "--scale") && more) {
            int s = atoi(argv[++i]);
            char b[4];
            snprintf(b, sizeof b, "%d", s < 1 ? 1 : s > 3 ? 3 : s);
            put("OS_WINDOW", b, 1);
        }
        else if (!strcmp(a, "--race") && more) race = atoi(argv[++i]);
        else if (!strcmp(a, "--track") && more) { race = atoi(argv[++i]); fly = 1; }
        else if (!strcmp(a, "--car") && more) put("OS_CAR", argv[++i], 1);
        else if (!strcmp(a, "--mode") && more) {
            const long m = strtol(argv[++i], NULL, 0);
            if (m == 4) put("OS_MODE", "attack", 1);
            else if (m == 0x20) put("OS_MODE", "cones", 1);
            else if (m == 0x40) put("OS_MODE", "slalom", 1);
            else unsetenv("OS_MODE");
        }
        else if (!strcmp(a, "--fix-50fps") || !strcmp(a, "--orig-50fps-bug") || !strcmp(a, "--view") ||
                 !strcmp(a, "--selftest") || !strcmp(a, "--quick"))
            (fprintf)(stderr, "amiscreamer: %s is not used here\n", a);
        else if ((!strcmp(a, "--hudmap") || !strcmp(a, "--prof") || !strcmp(a, "--span") || !strcmp(a, "--rec") ||
                  !strcmp(a, "--play") || !strcmp(a, "--rec-frames") || !strncmp(a, "--st-", 5)) && more) {
            (fprintf)(stderr, "amiscreamer: %s %s is not used here\n", a, argv[i + 1]);
            i++;
        }
        else if (n < 22) out[n++] = argv[i];        /* (--version, --help: this port's) */
    }
    cfg_read(data);
    {   const char *m = getenv("SCREAMER_MUSIC");      /* (MUSIC=OFF / SCREAMER_MUSIC=off: no CD music) */
        if (m && (!strcmp(m, "off") || !strcmp(m, "OFF") || !strcmp(m, "0"))) put("OS_NOMUSIC", "1", 1); }
    if (race >= 1 && race <= 6 && n < 21) {
        snprintf(trk[0], sizeof trk[0], "build/dec/MAP%d", race);
        snprintf(trk[1], sizeof trk[1], "%d", race);
        out[n++] = trk[0];
        out[n++] = trk[1];
        if (fly) put("OS_FREEFLY", "1", 1);
    }
    out[n] = NULL;
    if (any || race) { *pargc = n; *pargv = out; }
}
