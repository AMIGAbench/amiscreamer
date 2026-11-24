/*
 * amiga_path.c - UNIX PATHS AND THE ENVIRONMENT on AmigaOS (newlib).
 *
 * PATHS.  The game writes its paths as on Linux: "./x", ".", "dir/./x",
 * "PROGDIR:/screamer" (a directory and a name joined with '/').  AmigaDOS
 * knows none of that: "." is a name like any other, and a '/' at the start
 * (or after a ':') is the directory above.  newlib hands paths over as they
 * are.  So the C library's calls that take a path are wrapped (amiga/Makefile:
 * -Wl,--wrap=...) and the path is made an AmigaDOS one first:
 *     "." / "./"  -> ""  (the current directory)     "a/./b" -> "a/b"
 *     "VOL:/x"    -> "VOL:x"                         "../x"  -> "/x"
 *     "a//b"      -> "a/b"
 *
 * THE ENVIRONMENT.  newlib's getenv sees nothing of AmigaDOS's variables
 * (SetEnv, Set).  The game reads its switches with getenv (OS_..., the
 * OPENSCREAMER_... directories); at start-up those variables -- global ones
 * from ENV:, then the shell's local ones, which win -- are copied into
 * newlib's environment.  The game's own setenv stays inside the program.
 */
#include <exec/types.h>
#include <exec/lists.h>
#include <dos/dos.h>
#include <dos/dosextens.h>
#include <dos/var.h>
#include <proto/exec.h>
#include <proto/dos.h>

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "amiga.h"

/* ------------------------------------------------------------------ paths */

static const char *amiga_path(const char *in, char *out, size_t size)
{
    if (!in) return in;
    size_t o = 0;
    const char *p = in;
    const char *colon = strchr(in, ':');
    if (colon) {                                     /* the volume or assign, as it is */
        size_t n = (size_t)(colon - in) + 1;
        if (n >= size) return in;
        memcpy(out, in, n);
        o = n;
        p = colon + 1;
        while (*p == '/') p++;                       /* "VOL:/x": the '/' was only the joining */
    }
    while (*p) {
        const char *e = strchr(p, '/');
        size_t n = e ? (size_t)(e - p) : strlen(p);
        if (n == 0 || (n == 1 && p[0] == '.')) {     /* "" (a doubled '/') or "." */
        } else if (n == 2 && p[0] == '.' && p[1] == '.') {
            if (o + 1 >= size) return in;            /* "..": the directory above */
            out[o++] = '/';
        } else {
            if (o && out[o - 1] != ':' && out[o - 1] != '/') { if (o + 1 >= size) return in; out[o++] = '/'; }
            if (o + n >= size) return in;
            memcpy(out + o, p, n);
            o += n;
        }
        if (!e) break;
        p = e + 1;
    }
    out[o] = 0;
    return out;
}

/* (an empty name is the current directory: right for stat and opendir, not for a file) */
#define AP(path) char ap_[1024]; const char *const ap = amiga_path(path, ap_, sizeof ap_)

FILE *__real_fopen(const char *, const char *);
FILE *__wrap_fopen(const char *path, const char *mode) { AP(path); return __real_fopen(ap, mode); }

FILE *__real_freopen(const char *, const char *, FILE *);
FILE *__wrap_freopen(const char *path, const char *mode, FILE *f) { AP(path); return __real_freopen(ap, mode, f); }

int __real_stat(const char *, struct stat *);
int __wrap_stat(const char *path, struct stat *st)
{
    AP(path);
    if (!*ap) {                                      /* the current directory: it is one */
        memset(st, 0, sizeof *st);
        st->st_mode = S_IFDIR | 0755;
        return 0;
    }
    return __real_stat(ap, st);
}

DIR *__real_opendir(const char *);
DIR *__wrap_opendir(const char *path)
{
    AP(path);
    if (!*ap) {                                      /* the current directory, by its full name */
        static char here[512];
        if (NameFromLock(((struct Process *)FindTask(NULL))->pr_CurrentDir, (STRPTR)here, sizeof here))
            return __real_opendir(here);
    }
    return __real_opendir(ap);
}

int __real_mkdir(const char *, mode_t);
int __wrap_mkdir(const char *path, mode_t mode) { AP(path); return *ap ? __real_mkdir(ap, mode) : 0; }

int __real_remove(const char *);
int __wrap_remove(const char *path) { AP(path); return __real_remove(ap); }

int __real_rename(const char *, const char *);
int __wrap_rename(const char *from, const char *to)
{
    char b[1024];
    const char *t = amiga_path(to, b, sizeof b);
    AP(from);
    return __real_rename(ap, t);
}

int __real_unlink(const char *);
int __wrap_unlink(const char *path) { AP(path); return __real_unlink(ap); }

/* ------------------------------------------------------------------ the environment */

/* the stack: libnix's swapstack gives the program this much whatever it is started with -- a launcher
   may start it with NP_StackSize 65536 (SystemTags), Workbench with the icon's; this __stack, larger (the
   painter's and the menu's frames; PowerPC's frames larger still) */
#ifdef OS_MOS
unsigned long __stack = 2097152;
#else
unsigned long __stack = 1048576;
#endif

static int wanted(const char *name)
{
    return !strncmp(name, "OS_", 3) || !strncmp(name, "OPENSCREAMER", 12) || !strncmp(name, "SDL_", 4) ||
           !strncmp(name, "SCREAMER_", 9);           /* (SCREAMER_SND, _AHIMODE, ...) */
}

static void import_var(const char *name)
{
    char val[1024];
    LONG n = GetVar((CONST_STRPTR)name, (STRPTR)val, sizeof val, GVF_BINARY_VAR);
    if (n >= 0) {
        val[n < (LONG)sizeof val ? n : (LONG)sizeof val - 1] = 0;
        while (n > 0 && (val[n - 1] == '\n' || val[n - 1] == '\r')) val[--n] = 0;
        setenv(name, val, 1);
    }
}

__attribute__((constructor)) static void amiga_env(void)
{
    /* the FPU's control register as the program wants it: to nearest, extended, no traps.  A
       process inherits it from whoever started it (0x10 -- cutting -- has been found
       on the V1200), and the game's sums would come out otherwise */
#ifndef OS_MOS
    __asm__ volatile("fmove%.l %0,%%fpcr" : : "d"(0ul));
#endif
    /* global variables: the files in ENV: */
    BPTR lock = Lock((CONST_STRPTR)"ENV:", ACCESS_READ);
    if (lock) {
        struct FileInfoBlock *fib = AllocDosObject(DOS_FIB, NULL);
        if (fib && Examine(lock, fib))
            while (ExNext(lock, fib))
                if (fib->fib_DirEntryType < 0 && wanted((const char *)fib->fib_FileName)) import_var((const char *)fib->fib_FileName);
        if (fib) FreeDosObject(DOS_FIB, fib);
        UnLock(lock);
    }
    /* the shell's local ones (Set): after the global ones, so that they win */
    struct Process *me = (struct Process *)FindTask(NULL);
    struct LocalVar *v;
    for (v = (struct LocalVar *)me->pr_LocalVars.mlh_Head; v->lv_Node.ln_Succ; v = (struct LocalVar *)v->lv_Node.ln_Succ)
        if (v->lv_Node.ln_Type == LV_VAR && v->lv_Node.ln_Name && wanted(v->lv_Node.ln_Name)) import_var(v->lv_Node.ln_Name);
    /* OS_LOGFILE=<file>: what the program prints goes there (the emulator's tests read it from
       the shared volume), unbuffered */
    const char *log = getenv("OS_LOGFILE");
    if (log && *log && freopen(log, "w", stdout)) {
        setvbuf(stdout, NULL, _IONBF, 0);
        stderr = stdout;                             /* (AmigaDOS opens a file for writing once only: one stream for both) */
    }
}
