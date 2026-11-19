#define OS_PORT_IMPL
#define _GNU_SOURCE
#include "os_version.h"
#include "port.h"
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <strings.h>
#ifdef MISTER_HYBRID
#include "mister.h"
#endif
#ifdef _WIN32
/*
 * WINDOWS (MinGW-w64; tools/release_windows.sh).  What differs is all in this
 * file:
 *   - a stream over a container's bytes: Linux has fopencookie; here the bytes
 *     go to a temporary file that deletes itself when it is closed;
 *   - the ends of the program's own statics, for putting them back between
 *     its parts: the names MinGW's linker gives them.  SDL is a DLL, so its
 *     statics are not among them;
 *   - where the program is, where settings go (%APPDATA%\openscreamer), the
 *     environment, mkdir;
 *   - files are opened as they are (no translation of line ends), as on Linux;
 *   - there is no console: what the program prints goes to the terminal it
 *     was started from, or else to openscreamer.log in the settings folder.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fcntl.h>
#include <direct.h>
#undef mkdir
#define mkdir(path, mode) _mkdir(path)
#define setenv(name, value, overwrite) _putenv_s(name, value)
#define unsetenv(name) _putenv_s(name, "")
#endif

/* a block the port allocated: on a list, so that all of them can be let go at once */
typedef struct block { struct block *prev, *next; size_t size; uint64_t magic; } __attribute__((aligned(16))) block;   /* (16: the data after it 16-aligned, as the arena's blocks) */
#define MAGIC 0x4f53626c6f636b21ull

#if defined(AMIGA) || defined(AMIGA_NULL)
/* AMIGA: every container's list kept for the run -- the DATA ones whole (2.4 MB in all), of the GFX ones only the
   list: an entry is read from the disk when it is opened.  Before, six whole containers at a
   time (GRAF 3.7 MB, MENU 2.2 MB, ...) pushed each other out and a race read 9-11 MB of them. */
#define PACK_LISTS 1
#define PACKS 40
#else
#define PACKS 6          /* containers kept in memory at once */
#endif

/* everything that must outlive os_state_restore() lives in this one block */
typedef struct {
    char   data[768], home[768];
    int    dev, argc, has_next, next_argc;
    char  *argv[16];
    char   next_store[3][768];
    char  *next_argv[4];
    block *blocks;
    unsigned char *data_copy;           /* the program's initialised statics as they were */
    size_t data_len;
    size_t *bss_at; uintptr_t *bss_val; size_t bss_n;   /* the few non-zero words of the rest */
    unsigned once[4];
    void  *slot[16];
    /* the game's own containers, read as they are (see packed_open) */
    int    packed;                      /* the data directory is a copy of the GAME, with its DATA and GFX folders */
    int    game;                        /* 1 = Screamer, 2 = Screamer 2 */
    int    both;                        /* both games were found and none was asked for */
    char   other[800];                  /* (then the other game's folder: os_select_game) */
    char   dir_data[800], dir_gfx[800], dir_anims[800];
    struct pack { char name[16]; unsigned char *bytes; long len, dir; int nent; unsigned stamp;
#ifdef PACK_LISTS
                  long end; int whole; char path[1024];   /* end: where the list starts in the file; whole: bytes = the file */
#endif
                } pack[PACKS];
    unsigned pack_clock;
#ifdef OS_MEMFILES
    struct memfile { unsigned char *bytes; long len, at; int eof; } *memfile[64];   /* the open ones (packed_open) */
#endif
} keep;
static keep *K;

/* the program's own writable statics: GNU ld gives their ends these names */
#ifdef OS_OWN_SECTIONS
/* the build has put the port's own statics into sections of their own
   (CMakeLists.txt): what is saved and put back is those and nothing of the
   libraries linked in */
extern char __start_osdata[], __stop_osdata[], __start_osbss[], __stop_osbss[];
#define __data_start __start_osdata
#define _edata       __stop_osdata
#define __bss_start  __start_osbss
#define _end         __stop_osbss
#elif defined(_WIN32)
extern char __data_start__[], __data_end__[], __bss_start__[], __bss_end__[];
#define __data_start __data_start__
#define _edata       __data_end__
#define __bss_start  __bss_start__
#define _end         __bss_end__
#else
extern char __data_start[], _edata[], __bss_start[], _end[];
#endif

#ifdef _WIN32
static void win_fatal(const char *text);
#endif

static int is_dir(const char *p)
{
    struct stat st;
    return stat(p, &st) == 0 && S_ISDIR(st.st_mode);
}

static int is_file(const char *dir, const char *name)
{
    char p[1024];
    struct stat st;
    snprintf(p, sizeof p, "%s/%s", dir, name);
    return stat(p, &st) == 0;
}

/*
 * THE GAME'S CONTAINERS, READ DIRECTLY.
 *
 * The port's code asks for "build/dec/<CONTAINER>/<FILE>" -- the layout the
 * unpacking tool makes (tools/extract.sh).  When the data directory is a copy
 * of the game itself, that same name is answered straight out of
 * DATA/<CONTAINER>.DAT or GFX/<CONTAINER>.DAT, so nothing has to be unpacked
 * first.  A container (see tools/dat_container.py, and CLAUDE.md):
 *     [ file data ][ directory: 32-byte records ][ uint32 directory size ]
 *     record: 16-byte name XOR 0x3A (0x3A ends it), offset, stored size,
 *             real size, method (0 = as it is, else LZW)
 * and the LZW is the game's own (0x4d120...): codes of 9 to 12 bits, lowest
 * bit first, 256 = start again, 257 = end, first free code 258, one more bit
 * when the next free code reaches 512 / 1024 / 2048.
 */
static int ci_find(const char *dir, const char *name, char *out, size_t outsize)
{
    DIR *d = opendir(dir);
    if (!d) return 0;
    struct dirent *e;
    int ok = 0;
    while ((e = readdir(d)) != NULL)
        if (!strcasecmp(e->d_name, name)) { snprintf(out, outsize, "%s/%s", dir, e->d_name); ok = 1; break; }
    closedir(d);
    return ok;
}

static uint32_t le32(const unsigned char *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

static long lzw_decode_c(const unsigned char *src, long n, unsigned char *out, long want)
{
    static const unsigned mask[13] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x1ff, 0x3ff, 0x7ff, 0xfff };
    short prefix[4096];
    unsigned char suffix[4096], stack[4100];
    long bit = 0, got = 0;
    int width = 9, threshold = 0x200, next = 0x102, prev = -1;
    while (got < want) {
        long at = bit >> 3;
        if (bit + width > n * 8) break;
        unsigned v = src[at] | (at + 1 < n ? (unsigned)src[at + 1] << 8 : 0) | (at + 2 < n ? (unsigned)src[at + 2] << 16 : 0);
        int code = (int)((v >> (bit & 7)) & mask[width]);
        bit += width;
        if (code == 0x101) break;
        if (code == 0x100) { width = 9; threshold = 0x200; next = 0x102; prev = -1; continue; }
        int sp = 0, c = code, first;
        if (code >= next) {                         /* the code about to be made: the last string + its own first byte */
            if (prev < 0 || code > next) return -1;
            c = prev;
        }
        while (c > 0xff) { if (sp >= 4096) return -1; stack[sp++] = suffix[c]; c = prefix[c]; }
        first = c;
        stack[sp++] = (unsigned char)c;
        while (sp > 0 && got < want) out[got++] = stack[--sp];
        if (code >= next && got < want) out[got++] = (unsigned char)first;
        if (prev >= 0 && next < 4096) {
            prefix[next] = (short)prev; suffix[next] = (unsigned char)first;
            next++;
            if (next >= threshold && width != 12) { width++; threshold *= 2; }
        }
        prev = code;
    }
    return got;
}

/* AMIGA (and its qemu test): the LZW in vasm (amiga/sys/lzw_68k.s), the C above the reference: OS_LZWASM=0 the C,
   =c both, the answers and the bytes compared ("lzwcheck") */
#if (defined(AMIGA) || defined(AMIGA_NULL)) && (defined(__m68k__) || defined(__mc68000__)) && !defined(GEO_C_ONLY) && !defined(SPAN_C_ONLY)
long lzw68k(const unsigned char *src, long n, unsigned char *out, long want);
static long lzw_decode(const unsigned char *src, long n, unsigned char *out, long want)
{
    static int mode = -1;
    if (mode < 0) { const char *e = getenv("OS_LZWASM"); mode = e && e[0] == '0' ? 0 : e && e[0] == 'c' ? 2 : 1; }
    if (mode == 1) return lzw68k(src, n, out, want);
    if (mode == 0) return lzw_decode_c(src, n, out, want);
    static long calls, bad;
    unsigned char *b = malloc(want > 0 ? (size_t)want : 1);
    const long a = lzw68k(src, n, out, want), c = b ? lzw_decode_c(src, n, b, want) : a;
    calls++;
    if (b && (a != c || (c > 0 && memcmp(out, b, (size_t)c)))) {
        if (bad++ < 10) {
            long k = 0;
            while (k < c && k < a && out[k] == b[k]) k++;
            printf("lzwcheck: DIFFERS (call %ld): asm %ld C %ld bytes, first difference at %ld\n", calls, a, c, k);
        }
    }
    if ((calls & 255) == 0) printf("lzwcheck: %ld calls, %ld different\n", calls, bad);
    free(b);
    return a;
}
#else
#define lzw_decode lzw_decode_c
#endif

#ifdef PACK_LISTS
static struct pack *pack_get(const char *name)
{
    struct pack *use = NULL;
    for (int i = 0; i < PACKS; i++) {
        struct pack *p = &K->pack[i];
        if (p->bytes && !strcasecmp(p->name, name)) return p;
        if (!p->bytes && !use) use = p;
    }
    if (!use) return NULL;
    char file[32], path[1024];
    snprintf(file, sizeof file, "%.15s.DAT", name);
    const int whole = ci_find(K->dir_data, file, path, sizeof path);
    if (!whole && !ci_find(K->dir_gfx, file, path, sizeof path) &&
        !(K->dir_anims[0] && ci_find(K->dir_anims, file, path, sizeof path))) return NULL;
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    const long len = fseek(f, 0, SEEK_END) == 0 ? ftell(f) : -1;
    unsigned char *b = NULL, t[4];
    long dsize = 0;
    int ok = len >= 36;
    if (ok && whole) {
        ok = fseek(f, 0, SEEK_SET) == 0 && (b = malloc((size_t)len)) != NULL && fread(b, 1, (size_t)len, f) == (size_t)len;
        if (ok) dsize = (long)le32(b + len - 4);
    } else if (ok) {
        ok = fseek(f, len - 4, SEEK_SET) == 0 && fread(t, 1, 4, f) == 4;
        if (ok) dsize = (long)le32(t);
    }
    ok = ok && dsize > 0 && dsize % 32 == 0 && dsize <= len - 4;
    if (ok && !whole)
        ok = fseek(f, len - 4 - dsize, SEEK_SET) == 0 && (b = malloc((size_t)dsize)) != NULL && fread(b, 1, (size_t)dsize, f) == (size_t)dsize;
    fclose(f);
    if (!ok) { free(b); return NULL; }
    snprintf(use->name, sizeof use->name, "%.15s", name);
    snprintf(use->path, sizeof use->path, "%s", path);
    use->bytes = b; use->whole = whole; use->end = len - 4 - dsize;
    use->len = whole ? len : dsize; use->dir = whole ? use->end : 0; use->nent = (int)(dsize / 32);
    return use;
}
#else
static struct pack *pack_get(const char *name)
{
    struct pack *use = NULL;
    for (int i = 0; i < PACKS; i++) {
        struct pack *p = &K->pack[i];
        if (p->bytes && !strcasecmp(p->name, name)) { p->stamp = ++K->pack_clock; return p; }
    }
    for (int i = 0; i < PACKS; i++) {               /* an empty place, else the one longest unused */
        struct pack *p = &K->pack[i];
        if (!p->bytes) { use = p; break; }
        if (!use || p->stamp < use->stamp) use = p;
    }
    char file[32], path[1024];
    snprintf(file, sizeof file, "%.15s.DAT", name);
    if (!ci_find(K->dir_data, file, path, sizeof path) && !ci_find(K->dir_gfx, file, path, sizeof path) &&
        !(K->dir_anims[0] && ci_find(K->dir_anims, file, path, sizeof path))) return NULL;
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *b = len >= 36 ? malloc((size_t)len) : NULL;
    if (!b || fread(b, 1, (size_t)len, f) != (size_t)len) { free(b); fclose(f); return NULL; }
    fclose(f);
    long dsize = (long)le32(b + len - 4);
    if (dsize <= 0 || dsize % 32 || dsize > len - 4) { free(b); return NULL; }
    free(use->bytes);
    use->bytes = NULL;
    snprintf(use->name, sizeof use->name, "%.15s", name);
    use->bytes = b; use->len = len; use->dir = len - 4 - dsize; use->nent = (int)(dsize / 32);
    use->stamp = ++K->pack_clock;
    return use;
}
#endif

void os_le32(void *p, size_t n)
{
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    uint32_t *w = p;
    for (size_t i = 0; i < n; i++) w[i] = __builtin_bswap32(w[i]);
#else
    (void)p; (void)n;
#endif
}

void os_le16(void *p, size_t n)
{
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    uint16_t *w = p;
    for (size_t i = 0; i < n; i++) w[i] = __builtin_bswap16(w[i]);
#else
    (void)p; (void)n;
#endif
}

/* a file out of a container, held in memory and read like any other file */
#if !defined(_WIN32) && !defined(OS_MEMFILES)
#ifdef AMIGA
typedef _off64_t off64_t;   /* AMIGA: newlib's name for fopencookie's seek position */
#endif
typedef struct { unsigned char *bytes; long len, at; } membuf;

static ssize_t mem_read(void *c, char *out, size_t n)
{
    membuf *m = c;
    long left = m->len - m->at;
    if (left <= 0) return 0;
    if ((long)n > left) n = (size_t)left;
    memcpy(out, m->bytes + m->at, n);
    m->at += (long)n;
    return (ssize_t)n;
}

static int mem_seek(void *c, off64_t *pos, int whence)
{
    membuf *m = c;
    long to = whence == SEEK_SET ? (long)*pos : whence == SEEK_CUR ? m->at + (long)*pos : m->len + (long)*pos;
    if (to < 0) return -1;
    m->at = to;
    *pos = to;
    return 0;
}

static int mem_close(void *c)
{
    membuf *m = c;
    free(m->bytes);
    free(m);
    return 0;
}

#endif

#ifdef OS_MEMFILES
/* ---- files out of the containers, read from memory (port.h) ---- */
typedef struct memfile memfile;

static memfile *memfile_of(FILE *f)
{
    if (!K || !f) return NULL;
    for (int i = 0; i < 64; i++) if (K->memfile[i] && (FILE *)K->memfile[i] == f) return K->memfile[i];
    return NULL;
}

static FILE *memfile_new(unsigned char *bytes, long len)
{
    for (int i = 0; i < 64; i++)
        if (!K->memfile[i]) {
            memfile *m = calloc(1, sizeof *m);
            if (!m) break;
            m->bytes = bytes; m->len = len;
            K->memfile[i] = m;
            return (FILE *)m;
        }
    (fprintf)(stderr, "openscreamer: too many files open out of the containers\n");
    free(bytes);
    return NULL;
}

size_t os_fread(void *p, size_t size, size_t n, FILE *f)
{
    memfile *m = memfile_of(f);
    if (!m) return fread(p, size, n, f);
    if (!size || !n) return 0;
    const long left = m->len - m->at;
    size_t want = size * n, got = left > 0 ? (size_t)left : 0;
    if (got > want) got = want;
    if (got < want) m->eof = 1;
    memcpy(p, m->bytes + m->at, got);
    m->at += (long)got;
    return got / size;
}

char *os_fgets(char *s, int n, FILE *f)
{
    memfile *m = memfile_of(f);
    if (!m) return fgets(s, n, f);
    if (n <= 0) return NULL;
    if (m->at >= m->len) { m->eof = 1; return NULL; }
    int k = 0;
    while (k < n - 1 && m->at < m->len) {
        const char c = (char)m->bytes[m->at++];
        s[k++] = c;
        if (c == '\n') break;
    }
    s[k] = 0;
    return s;
}

int os_fgetc(FILE *f)
{
    memfile *m = memfile_of(f);
    if (!m) return fgetc(f);
    if (m->at >= m->len) { m->eof = 1; return EOF; }
    return m->bytes[m->at++];
}

int os_fseek(FILE *f, long off, int whence)
{
    memfile *m = memfile_of(f);
    if (!m) return fseek(f, off, whence);
    const long to = whence == SEEK_SET ? off : whence == SEEK_CUR ? m->at + off : m->len + off;
    if (to < 0) return -1;
    m->at = to; m->eof = 0;
    return 0;
}

long os_ftell(FILE *f)
{
    memfile *m = memfile_of(f);
    return m ? m->at : ftell(f);
}

void os_rewind(FILE *f)
{
    memfile *m = memfile_of(f);
    if (!m) { rewind(f); return; }
    m->at = 0; m->eof = 0;
}

int os_feof(FILE *f)
{
    memfile *m = memfile_of(f);
    return m ? m->eof : feof(f);
}

int os_fclose(FILE *f)
{
    memfile *m = memfile_of(f);
    if (!m) return fclose(f);
    for (int i = 0; i < 64; i++) if (K->memfile[i] == m) K->memfile[i] = NULL;
    free(m->bytes);
    free(m);
    return 0;
}
#endif

/* "<CONTAINER>/<FILE>" out of the game's containers, as a stream to read; NULL if it is not there */
static FILE *packed_open(const char *rel)
{
    char cname[16];
    const char *slash = strchr(rel, '/');
    if (!slash || slash == rel || slash - rel >= (long)sizeof cname || !slash[1]) return NULL;
    memcpy(cname, rel, (size_t)(slash - rel));
    cname[slash - rel] = 0;
    struct pack *p = pack_get(cname);
    if (!p) return NULL;
    for (int i = 0; i < p->nent; i++) {
        const unsigned char *r = p->bytes + p->dir + 32L * i;
        char nm[17];
        int k = 0;
        while (k < 16 && r[k] != 0x3a) { nm[k] = (char)(r[k] ^ 0x3a); k++; }
        nm[k] = 0;
        if (!k || strcasecmp(nm, slash + 1)) continue;
        long off = (long)le32(r + 16), stored = (long)le32(r + 20), real = (long)le32(r + 24);
        uint32_t method = le32(r + 28);
#ifdef PACK_LISTS
        const long end = p->end;
#else
        const long end = p->dir;
#endif
        if (off < 0 || stored < 0 || off + stored > end || real < 0 || real > (64L << 20)) return NULL;
        unsigned char *buf = malloc((size_t)real + 1);
        if (!buf) return NULL;
        const unsigned char *src = p->bytes + off;
#ifdef PACK_LISTS
        unsigned char *tmp = NULL;
        if (!p->whole) {                       /* the entry's own bytes, from the container on the disk */
            const long n = method ? stored : stored < real ? stored : real;
            unsigned char *to = method ? (tmp = malloc((size_t)stored + 1)) : buf;
            FILE *f = to ? fopen(p->path, "rb") : NULL;
            const int ok = f && fseek(f, off, SEEK_SET) == 0 && (long)fread(to, 1, (size_t)n, f) == n;
            if (f) fclose(f);
            if (!ok) { free(tmp); free(buf); (fprintf)(stderr, "openscreamer: %s cannot be read\n", rel); return NULL; }
            src = method ? tmp : NULL;         /* (stored: already in buf) */
        }
#endif
        long got;
        if (method) got = lzw_decode(src, stored, buf, real);
        else { got = stored < real ? stored : real; if (src) memcpy(buf, src, (size_t)got); }
#ifdef PACK_LISTS
        free(tmp);
#endif
        if (got != real) {
            (fprintf)(stderr, "openscreamer: %s is damaged in the game's files (%ld of %ld bytes)\n", rel, got, real);
            free(buf);
            return NULL;
        }
        if (getenv("OS_PACKDUMP")) {             /* testing: write what was read out of the container */
            char dn[900], fn[1000];
            snprintf(dn, sizeof dn, "%s/%s", getenv("OS_PACKDUMP"), cname);
            mkdir(dn, 0755);
            snprintf(fn, sizeof fn, "%s/%s", dn, nm);
            FILE *o = fopen(fn, "wb");
            if (o) { fwrite(buf, 1, (size_t)real, o); fclose(o); }
        }
#ifdef _WIN32
        {
            /* WINDOWS: the bytes in a temporary file ("T": kept in memory if
               it can be; "D": gone when it is closed) */
            char dir[MAX_PATH], name[MAX_PATH];
            FILE *f = NULL;
            if (GetTempPathA(sizeof dir, dir) && GetTempFileNameA(dir, "osc", 0, name)) f = fopen(name, "w+bTD");
            if (f && (fwrite(buf, 1, (size_t)real, f) != (size_t)real || fflush(f) != 0)) { fclose(f); f = NULL; }
            if (f) rewind(f);
            free(buf);
            return f;
        }
#elif defined(OS_MEMFILES)
        /* the bytes themselves, read by os_fread & co.; they go when it is closed (os_fclose) */
        return memfile_new(buf, real);
#else
        /* a stream over the bytes, which go when it is closed (mem_close) */
        membuf *m = malloc(sizeof *m);
        if (!m) { free(buf); return NULL; }
        m->bytes = buf; m->len = real; m->at = 0;
        static const cookie_io_functions_t io = { mem_read, NULL, mem_seek, mem_close };
        FILE *f = fopencookie(m, "rb", io);
        if (!f) { free(buf); free(m); }
        return f;
#endif
    }
    return NULL;
}

/*
 * IS THE GAME ALL THERE?  Asked once, when the program starts.
 *
 * Needed: the sixteen containers of DATA (GEN, LOCAL, MUSIC, SOUND, the six
 * tracks and the six tracks driven the other way) and nine of GFX (GAME,
 * GRAF, MENU and the six tracks' low-resolution pictures).  The six
 * high-resolution containers are wanted too but the game runs without them
 * (it stays in low resolution).  A container counts when it is there, its
 * list of contents is sound, and EVERY file in it unpacks to the size the
 * list gives -- so a copy cut short or damaged is caught here, not half way
 * through a race.
 */
#ifdef AMIGA
/* AMIGA: unpacking every file of every container took 55 s on an emulated 68060 before
   anything was on the screen.  Here only each container's list is read and checked (every
   entry within the file); a damaged file is still caught where it is opened (packed_open).
   OS_FULLCHECK=1: the whole check, as on the PC. */
static int pack_list(const char *path, int *files)
{
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    unsigned char t[4];
    int ok = fseek(f, 0, SEEK_END) == 0;
    long len = ok ? ftell(f) : 0;
    ok = ok && len >= 36 && fseek(f, len - 4, SEEK_SET) == 0 && fread(t, 1, 4, f) == 4;
    long dsize = ok ? (long)le32(t) : 0;
    if (ok && (dsize <= 0 || dsize % 32 || dsize > len - 4)) ok = 0;
    long dir = len - 4 - dsize;
    unsigned char *d = ok ? malloc((size_t)dsize) : NULL;
    ok = ok && d && fseek(f, dir, SEEK_SET) == 0 && fread(d, 1, (size_t)dsize, f) == (size_t)dsize;
    fclose(f);
    for (long i = 0; ok && i < dsize / 32; i++) {
        const unsigned char *r = d + 32 * i;
        if (r[0] == 0x3a) continue;
        long off = (long)le32(r + 16), stored = (long)le32(r + 20), real = (long)le32(r + 24);
        if (off < 0 || stored < 0 || off + stored > dir || real < 0 || real > (64L << 20)) ok = 0;
        else if (!le32(r + 28) && stored != real) ok = 0;
        else (*files)++;
    }
    free(d);
    return ok;
}
#endif

static int pack_whole(const char *path, int *files)
{
#ifdef AMIGA
    if (!getenv("OS_FULLCHECK")) return pack_list(path, files);
#endif
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *b = len >= 36 ? malloc((size_t)len) : NULL;
    int ok = b && fread(b, 1, (size_t)len, f) == (size_t)len;
    fclose(f);
    long dsize = ok ? (long)le32(b + len - 4) : 0;
    if (ok && (dsize <= 0 || dsize % 32 || dsize > len - 4)) ok = 0;
    long dir = len - 4 - dsize;
    unsigned char *out = NULL;
    long room = 0;
    for (long i = 0; ok && i < dsize / 32; i++) {
        const unsigned char *r = b + dir + 32 * i;
        if (r[0] == 0x3a) continue;                 /* the empty record that ends the list */
        long off = (long)le32(r + 16), stored = (long)le32(r + 20), real = (long)le32(r + 24);
        if (off < 0 || stored < 0 || off + stored > dir || real < 0 || real > (64L << 20)) { ok = 0; break; }
        if (le32(r + 28)) {
            if (real > room) { free(out); out = malloc((size_t)real + 1); room = real; if (!out) { ok = 0; break; } }
            if (lzw_decode(b + off, stored, out, real) != real) ok = 0;
        } else if (stored != real) ok = 0;
        (*files)++;
    }
    free(out);
    free(b);
    return ok;
}

/* the game itself (its DATA and GFX folders, whatever their letters' case), or files unpacked
   from it? */
static void game_dirs(void)
{
    K->packed = ci_find(K->data, "DATA", K->dir_data, sizeof K->dir_data)
             && ci_find(K->data, "GFX", K->dir_gfx, sizeof K->dir_gfx)
             && is_dir(K->dir_data) && is_dir(K->dir_gfx);
    if (!K->packed || !ci_find(K->data, "ANIMS", K->dir_anims, sizeof K->dir_anims) || !is_dir(K->dir_anims)) K->dir_anims[0] = 0;
}

#ifdef MISTER_HYBRID
/* MISTER: a file's name onto the core's message, whole or not at all (the message has 4 lines
   of 71 characters); those left out are counted */
#define NAMES_ROOM MISTER_NAMES
static void name_add(char *names, int *more, const char *name)
{
    size_t at = strlen(names);
    if (*more || at + 2 + strlen(name) > NAMES_ROOM) { (*more)++; return; }
    snprintf(names + at, NAMES_ROOM + 1 - at, "%s%s", at ? ", " : "", name);
}
#endif

/* what game_check (and the MiSTer's check before the pick) looks for, set by set */
static const char *const data1[] = { "GEN", "LOCAL", "MUSIC", "SOUND", "MAP1", "MAP2", "MAP3", "MAP4", "MAP5", "MAP6",
                                     "MAP1I", "MAP2I", "MAP3I", "MAP4I", "MAP5I", "MAP6I", NULL };
static const char *const gfx1[]  = { "GAME", "GRAF", "MENU", "MAP1L", "MAP2L", "MAP3L", "MAP4L", "MAP5L", "MAP6L", NULL };
static const char *const high1[] = { "MAP1H", "MAP2H", "MAP3H", "MAP4H", "MAP5H", "MAP6H", NULL };
static const char *const none[]  = { NULL };
/* SCREAMER 2: every container the port opens -- the 256-colour sets, the names ending in 1
   (s2r_car.h passes '1' wherever the game's names take the set); the 65K-colour ones, ending
   in 2, never.  A missing menu room or menu car was a black picture and no message.  Those
   of the menus and the second look are only looked for, not read: reading them all through
   too took another 2.6 s from the MiSTer's SD card (36 MB, 2026-10-18) */
static const char *const data2[] = { "GEN", "GAME", "LOCAL", "SOUND", "MAP1", "MAP2", "MAP3", "MAP4", "MAP5", "MAP6", "MAP7", NULL };
static const char *const gfx2[]  = { "GAME1", "GRAF1", "MAP1L01", "MAP2L01", "MAP3L01", "MAP4L01", "MAP5L01", "MAP6L01", "MAP7L01",
                                     "MAP1L11", "MAP2L11", "MAP3L11", "MAP4L11", "MAP6L11",
                                     "CARS101", "CARS201", "CARS301", "CARS401", NULL };
static const char *const there2[] = { "CARS111", "CARS211", "CARS311", "CARS411",
                                      "MENU11", "MENU21", "MENU31", "MENU41", "ENVM11", "ENVM21", "ENVM31", "ENVM41",
                                      "ENVP101", "ENVP111", "ENVP201", "ENVP211", "ENVP301", "ENVP311", "ENVP401", "ENVP411",
                                      "ENVP501", "ENVP601", "ENVP611", "ENVP701", "LOGO1", "MAPS1", "PLATES1", NULL };
static const char *const anims2[] = { "SCENE011", "SCENE021", "SCENE031", "SCENE041", "SCCAR11", "SCCAR21", "SCCAR31", "SCCAR41", NULL };
static const char *const high2[] = { "MAP1H01", "MAP2H01", "MAP3H01", "MAP4H01", "MAP5H01", "MAP6H01", "MAP7H01", NULL };
/* the sets: their folder; read through (1) or only looked for (0); 4 the optional one */
static const char *const folder[] = { "DATA", "GFX", "GFX", "ANIMS", "GFX" };
static const int whole[] = { 1, 1, 0, 0, 1 };
static const char *const *const sets1[] = { data1, gfx1, none, none, high1 }, *const *const sets2[] = { data2, gfx2, there2, anims2, high2 };

#ifdef MISTER_HYBRID
/* MISTER: is every container game_check asks for there, in `dir` (game 1 or 2)?  Looked for
   only, not read through (that is game_check's, after the pick): asked before the core's pick
   (mister_pick_game), so that a game with files missing gets the message naming them and no
   logo.  The number missing (-1: no DATA, GFX or ANIMS folder at all), their names in `names`
   (NAMES_ROOM + 1), *more those left out */
int os_game_missing(const char *dir, int game, char *names, int *more)
{
    static const char *const kind[3] = { "DATA", "GFX", "ANIMS" };
    char sub[3][1024], path[1024], file[32], name[48];
    int have[3], n = 0;
    names[0] = 0;
    *more = 0;
    for (int k = 0; k < 3; k++) have[k] = ci_find(dir, kind[k], sub[k], sizeof sub[k]) && is_dir(sub[k]);
    if (!have[0] && !have[1] && !have[2]) return -1;
    for (int set = 0; set < 4; set++) {             /* not the optional high-resolution files */
        const char *const *list = (game == 2 ? sets2 : sets1)[set];
        const int k = set == 0 ? 0 : set == 3 ? 2 : 1;
        if (!list[0]) continue;
        if (!have[k]) {
            snprintf(name, sizeof name, "%s/ (the folder)", kind[k]);
            name_add(names, more, name);
            n++;
            continue;
        }
        for (int i = 0; list[i]; i++) {
            snprintf(file, sizeof file, "%s.DAT", list[i]);
            if (ci_find(sub[k], file, path, sizeof path)) continue;
            snprintf(name, sizeof name, "%s/%s", kind[k], file);
            name_add(names, more, name);
            n++;
        }
    }
    return n;
}
#endif

static void game_check(void)
{
    char bad[2400] = "", path[1024], file[32];
#ifdef MISTER_HYBRID
    char names[NAMES_ROOM + 1] = "", name[48];  /* MISTER: the same, short, for the core's message */
    int more = 0;
#endif
    int files = 0, nbad = 0, hi = 1, packs = 0;
#if defined(AMIGA) || defined(AMIGA_NULL)
    (printf)("AmiScreamer %s\n", OS_VERSION);
#else
    (printf)("OpenScreamer %s\n", OS_VERSION);
#endif
    (printf)("Checking %s data in %s ... ", K->game == 2 ? "Screamer 2" : "Screamer", K->data);
    fflush(stdout);
    for (int set = 0; set < 5; set++) {             /* DATA, GFX, more GFX, ANIMS, the optional high-resolution files */
        const char *const *list = (K->game == 2 ? sets2 : sets1)[set];
        const char *dir = set == 0 ? K->dir_data : set == 3 ? K->dir_anims : K->dir_gfx;
        if (K->packed && !dir[0] && list[0]) {      /* no ANIMS folder at all: said once, not file by file */
            size_t at = strlen(bad);
            snprintf(bad + at, sizeof bad - at, "\n  %s/  missing (the whole folder)", folder[set]);
#ifdef MISTER_HYBRID
            snprintf(name, sizeof name, "%s/ (the folder)", folder[set]);
            name_add(names, &more, name);
#endif
            nbad++;
            continue;
        }
        for (int i = 0; list[i]; i++) {
            int ok;
            const char *what = "missing";
            if (K->packed) {
                snprintf(file, sizeof file, "%s.DAT", list[i]);
                ok = ci_find(dir, file, path, sizeof path);
                if (ok && whole[set] && !pack_whole(path, &files)) { ok = 0; what = "damaged"; }
            } else {                                /* files unpacked by tools/extract.sh: the folder must be there */
                snprintf(path, sizeof path, "%s/%s", K->data, list[i]);
                ok = is_dir(path);
            }
            if (ok) { packs++; continue; }
            if (set == 4) { hi = 0; continue; }
            size_t at = strlen(bad);
            snprintf(bad + at, sizeof bad - at, "\n  %s/%s%s  %s", folder[set], list[i],
                     K->packed ? ".DAT" : " (unpacked folder)", what);
#ifdef MISTER_HYBRID
            snprintf(name, sizeof name, "%s/%s%s", folder[set], list[i], K->packed ? ".DAT" : "");
            name_add(names, &more, name);
#endif
            nbad++;
        }
    }
    if (nbad) {
        (printf)("FAILED\n");
        fflush(stdout);
#ifdef MISTER_HYBRID
        {
            /* MISTER: the files that cannot be used, on the core's picture */
            char text[400], rest[24] = "";
            if (more) snprintf(rest, sizeof rest, " and %d more", more);
            snprintf(text, sizeof text, "%s's files in %s/ are missing or damaged: %s%s. Copy the game's whole folder again.",
                     K->game == 2 ? "Screamer 2" : "Screamer", mister_game_path(K->data), names, rest);
            mister_fatal(text);
        }
#endif
        (fprintf)(stderr, "openscreamer: %d of the game's files cannot be used:%s\n"
                        "Say where a complete copy of the game is with -data DIR (the folder that holds its\n"
                        "DATA and GFX folders), or put it next to the program as \"%s\".\n", nbad, bad,
                        K->game == 2 ? "screamer2" : "screamer");
#ifdef _WIN32
        {
            char text[2600];
            snprintf(text, sizeof text, "%d of the game's files are missing or damaged:%.1800s\n\nPut a complete copy of the "
                     "original Screamer (the folder that holds DATA and GFX) next to openscreamer.exe, named \"screamer\".", nbad, bad);
            win_fatal(text);
        }
#endif
        exit(1);
    }
    if (K->packed) (printf)("OK (%d containers, %d files", packs, files);
    else           (printf)("OK (unpacked files");
    (printf)("%s)\n", hi ? "" : "; no high-resolution files: low resolution only");
    fflush(stdout);
}

#ifdef PACK_LISTS
static int packed_has(const char *rel)          /* in its container's list? (not unpacked to find out) */
{
    char cname[16];
    const char *slash = strchr(rel, '/');
    if (!slash || slash == rel || slash - rel >= (long)sizeof cname || !slash[1]) return 0;
    memcpy(cname, rel, (size_t)(slash - rel));
    cname[slash - rel] = 0;
    struct pack *p = pack_get(cname);
    for (int i = 0; p && i < p->nent; i++) {
        const unsigned char *r = p->bytes + p->dir + 32L * i;
        char nm[17]; int k = 0;
        while (k < 16 && r[k] != 0x3a) { nm[k] = (char)(r[k] ^ 0x3a); k++; }
        nm[k] = 0;
        if (k && !strcasecmp(nm, slash + 1)) return 1;
    }
    return 0;
}
#endif
int os_exists(const char *path)
{
#ifdef PACK_LISTS
    if (K && K->packed && path && !strncmp(path, "build/dec/", 10)) return packed_has(path + 10);
#endif
    FILE *f = os_fopen(path, "rb");
#ifdef OS_MEMFILES
    if (f) os_fclose(f);
#else
    if (f) fclose(f);
#endif
    return f != NULL;
}

static void os_help(const char *me)
{
    (printf)(
#if defined(AMIGA) || defined(AMIGA_NULL)
"AmiScreamer " OS_VERSION " -- Screamer (1995) for the Amiga.  It needs a copy of the original game:\n"
#else
"OpenScreamer " OS_VERSION " -- Screamer (1995) for Linux.  It needs a copy of the original game:\n"
#endif
"put the game's folder next to the program as \"screamer\" (or name it with -data).\n"
"\n"
"USAGE\n"
"  %s [options]                     the game: intro, menu, races\n"
"  %s [options] build/dec/MAPn n    straight into a race on track n (1-6)\n"
"  %s [options] build/dec/MAPnI n   the same track driven the other way\n"
"  %s ... --shot FILE [t]           save one picture (PPM) from sample t of the lap and leave\n"
"\n"
"OPTIONS\n"
"  -h, --help     this text\n""  --version      the version, and nothing else\n"
"  -data DIR      your copy of the game: the folder that holds its DATA and GFX folders\n"
"                 default: $OPENSCREAMER_DATA, ./screamer, <program>/screamer\n"
"                 (a folder of files already unpacked with tools/extract.sh works too)\n"
"  -game N        1 = Screamer, 2 = Screamer 2.  Default: the one whose files are found\n"
"                 (./screamer, ./screamer2); both found: a first page chooses (the last\n"
"                 choice lit); -data DIR names either game's folder\n"
"  -res low|high  320 x 200 or 640 x 400 for this run (Screamer 2's high is STARTH.EXE's);\n"
"                 the one kept is RESOLUTION in Screamer's OPTIONS or Screamer 2's GAME\n"
"                 SETTINGS, in openscreamer.cfg\n"
"  -home DIR      where settings and saves are kept\n"
"                 default: $OPENSCREAMER_HOME, this directory if it already holds them,\n"
"                 else ~/.config/openscreamer\n"
"  -d             developer mode: walk / fly round the track, inspection keys\n"
"\n"
"\"build/dec/MAPn\" is only a name for track n: it is found in the game's folder, wherever that is.\n"
"Nothing has to be unpacked: the game's own files are read as they are.\n"
"\n"
"IN THE MENU\n"
"  UP / DOWN      choose a line           LEFT / RIGHT  change an option, the car, the track\n"
"  ENTER          go on                   ESC           back (on the first page: leave)\n"
#ifdef MISTER_HYBRID
"  OPTIONS has: DETAIL (LOW, MID, HI as the original),\n"
#else
"  OPTIONS has: DETAIL (LOW, MID, HI as the original; ULTRA draws much further),\n"
#endif
"  RESOLUTION (320x200 or 640x400), difficulty, laps, speech, music, records.\n"
"\n"
"IN A RACE\n"
"  UP / DOWN      accelerate / brake      LEFT / RIGHT  steer\n"
"  ALT / CTRL     gear up / down (cars with manual transmission); A / Z do the same\n"
"                 (these six are the game's own CONFIG/CONTROLS.CFG; to change one, a line\n"
"                 in openscreamer.cfg: key_accelerate= key_brake= key_left= key_right=\n"
"                 key_gear_up= key_gear_down=  with a key's name, such as  key_brake=Space)\n"
"  C              next view              F1 bumper cam  F2 cockpit  F3 near chase  F4 far chase\n"
"  M              radar zoom             P   the CD player (music and volumes)\n"
"Game controller (in a race):\n"
"  left stick     steer                   right / left trigger   accelerate / brake\n"
"  d-pad          steer                   A / B                  accelerate / brake\n"
"  shoulders      gear up (right) / down (left)      Y  change view\n"
"  START = ENTER, BACK = ESC; in the menus the d-pad or stick moves, A chooses, B goes back\n"
"  BACKSPACE      back onto the road     ESC leave the race (it asks first)\n"
#ifdef MISTER_HYBRID
"  F12            screenshot (shot_NNN.ppm)\n"
#else
"  F5             FPS counter            F11 full screen    F12 screenshot (shot_NNN.ppm)\n"
#endif
"\n"
"FILES IT KEEPS (in the home directory)\n"
"  openscreamer.cfg       settings        openscreamer.records   best times, name, what is unlocked\n"
"  openscreamer.champ     championship    openscreamer.replays/  replays of record races\n"
"  openscreamer.ghosts/   time-attack ghosts\n"
"\n"
"SCREAMER 2'S MUSIC is its CD's audio tracks: put them, as files, in the game's folder's\n"
"  music folder (or the game's folder, or the home's music folder), named track_02.ogg ..\n"
"  track_09.ogg -- .mp3 or .wav do as well.  Track 2 is the menu's; the races' are 3 to 9.\n"
"\n"
"SWITCHES FOR ONE RUN (environment variables)\n"
"  OS_RES=low|high    OS_DETAIL=0..3    OS_LAPS=n    OS_DIFF=0..3    OS_CAR=n\n"
"  OS_MODE=cones|slalom|attack    OS_NOINTRO=1    OS_NOMUSIC=1    OS_NOSOUND=1\n"
"  OS_S2PLAINMENU=1   Screamer 2 with the port's plain menu instead of the game's own\n",
        me, me, me, me);
}

#ifdef _WIN32
/* WINDOWS: a program without a console prints nowhere.  Started from a
   terminal, what it prints goes there; else to openscreamer.log in the
   settings folder.  If the game is not found, a box says so. */
static int win_console;
static void win_attach(void)
{
    _set_fmode(_O_BINARY);                           /* files as they are, as on Linux */
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h && h != INVALID_HANDLE_VALUE && GetFileType(h) != FILE_TYPE_UNKNOWN) win_console = 1;   /* sent to a file or a pipe */
    else if (AttachConsole(ATTACH_PARENT_PROCESS)) {
        freopen("CONOUT$", "w", stdout); freopen("CONOUT$", "w", stderr);
        win_console = 1;
    }
    setvbuf(stdout, NULL, _IONBF, 0); setvbuf(stderr, NULL, _IONBF, 0);
}

static void win_output(void)
{
    char log[900];
    if (win_console) return;
    snprintf(log, sizeof log, "%s/openscreamer.log", K->home);
    if (freopen(log, "w", stdout)) freopen(log, "a", stderr);
    setvbuf(stdout, NULL, _IONBF, 0); setvbuf(stderr, NULL, _IONBF, 0);
}

static void win_fatal(const char *text)
{
    if (!win_console && !getenv("SDL_VIDEODRIVER"))
        MessageBoxA(NULL, text, "OpenScreamer", MB_OK | MB_ICONERROR);
}
#endif

/* which game a data directory holds: Screamer 2's tracks are MAP1L01 (track, resolution,
   look, colours), Screamer's MAP1L.  0 = neither */
static int which_game(const char *dir)
{
    char gfx[800], path[1024];
    if (!is_dir(dir)) return 0;
#ifdef OS_NO_S2
    /* (a build without Screamer 2: its folder is not a game here) */
    if (ci_find(dir, "GFX", gfx, sizeof gfx) && is_dir(gfx) && ci_find(gfx, "MAP1L.DAT", path, sizeof path)) return 1;
    if (ci_find(dir, "MAP1L", path, sizeof path) && is_dir(path)) return 1;
    return 0;
#endif
    if (ci_find(dir, "GFX", gfx, sizeof gfx) && is_dir(gfx)) {
        if (ci_find(gfx, "MAP1L01.DAT", path, sizeof path)) return 2;
        if (ci_find(gfx, "MAP1L.DAT", path, sizeof path)) return 1;
    }
    if (ci_find(dir, "MAP1L01", path, sizeof path) && is_dir(path)) return 2;
    if (ci_find(dir, "MAP1L", path, sizeof path) && is_dir(path)) return 1;
    return 0;
}

void os_init(int argc, char **argv)
{
#ifdef _WIN32
    win_attach();
#endif
    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "--version")) {
#if defined(AMIGA) || defined(AMIGA_NULL)
            (printf)("AmiScreamer %s\n", OS_VERSION); exit(0);
#else
            (printf)("OpenScreamer %s\n", OS_VERSION); exit(0);
#endif
        }
    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h") || !strcmp(argv[i], "-help")) {
            const char *me = strrchr(argv[0], '/');
            os_help(me ? me + 1 : argv[0]);
            exit(0);
        }
#ifdef MISTER_HYBRID
    setvbuf(stdout, NULL, _IOLBF, 0);       /* MISTER: the log a line at a time (the launch script keeps it in /tmp) */
#endif
    K = calloc(1, sizeof *K);
    if (!K) exit(1);
    const char *data = getenv("OPENSCREAMER_DATA"), *home = getenv("OPENSCREAMER_HOME");
    int game = getenv("OPENSCREAMER_GAME") ? atoi(getenv("OPENSCREAMER_GAME")) : 0;    /* 0: whichever is found */
    K->argv[K->argc++] = argv[0];
    for (int i = 1; i < argc && K->argc < 15; i++) {
        if (!strcmp(argv[i], "-d")) K->dev = 1;
        else if (!strcmp(argv[i], "-data") && i + 1 < argc) data = argv[++i];
        else if (!strcmp(argv[i], "-home") && i + 1 < argc) home = argv[++i];
        else if (!strcmp(argv[i], "-game") && i + 1 < argc) game = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-res") && i + 1 < argc) { i++; if (!strcmp(argv[i], "high") || !strcmp(argv[i], "low")) setenv("OS_RES", argv[i], 1); }
        else K->argv[K->argc++] = argv[i];
    }
    char exe[600] = "";
#ifdef _WIN32
    DWORD n = GetModuleFileNameA(NULL, exe, sizeof exe - 1);
    exe[n < sizeof exe ? n : 0] = 0;
    for (char *c = exe; *c; c++) if (*c == '\\') *c = '/';
    { char *s = strrchr(exe, '/'); if (n > 0 && s) *s = 0; else strcpy(exe, "."); }
#elif defined(AMIGA)
    strcpy(exe, "PROGDIR:");                   /* AMIGA: the program's own directory, by its name in AmigaDOS */
#else
    ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n > 0) { exe[n] = 0; char *s = strrchr(exe, '/'); if (s) *s = 0; } else strcpy(exe, ".");
#endif
    if (game != 1 && game != 2) game = 0;
#ifdef OS_NO_S2
    if (game == 2) { (fprintf)(stderr, "openscreamer: this build has Screamer 1 only\n"); game = 1; }
#endif
#ifdef MISTER_HYBRID
    /* MISTER: the game is the core's menu entry's, or the one picked from the core's list of
       those found (mister.c); there is no first page choosing it */
    static char picked[64];
    if (!data && !game && mister_on()) {
        game = mister_pick_game(picked, sizeof picked);
        if (!game) exit(0);                  /* (the core says what is missing, until the player leaves it) */
        data = picked;
    }
#endif
    if (data) {
        snprintf(K->data, sizeof K->data, "%s", data);
        if (!game) game = which_game(K->data);
    } else {
        /* a copy of the game first, then files already unpacked; Screamer 2's are
           the same places with a 2 at the end of the name */
#ifdef AMIGA
        /* AMIGA: the program's directory is a volume-like name ("PROGDIR:"), joined without a '/';
           a '/' at the start of an AmigaDOS path would be the directory above */
        /* (first the program's own directory itself: the programs and the game's DATA/ GFX/ CONFIG/ MUSIC/ in one
           drawer) */
        static const char *const where[] = { "%s%.0s", "screamer%s", "%sscreamer%s", "%sdata%s", "build/dec%s",
                                             "data%s", "%sScreamer%s", "Screamer%s" };
#else
        static const char *const where[] = { "screamer%s", "%s/screamer%s", "%s/../../screamer%s", "build/dec%s",
                                             "%s/data%s", "%s/../../build/dec%s", "data%s" };
#endif
        enum { NWHERE = (int)(sizeof where / sizeof where[0]) };
        char found[3][700] = { "", "", "" };
        for (int g = 1; g <= 2; g++)
            for (int i = 0; i < NWHERE && !found[g][0]; i++) {
                char cand[700];
                if (where[i][0] == '%' && where[i][1] == 's') snprintf(cand, sizeof cand, where[i], exe, g == 2 ? "2" : "");
                else snprintf(cand, sizeof cand, where[i], g == 2 ? "2" : "");
                if (is_dir(cand) && which_game(cand) == g) snprintf(found[g], 700, "%s", cand);
            }
        /* no -game: the one that is there; both there: Screamer (the choice between them is the menu's) */
        if (!game) { K->both = found[1][0] && found[2][0]; game = found[1][0] || !found[2][0] ? 1 : 2; }
        snprintf(K->data, sizeof K->data, "%.700s", found[game][0] ? found[game] : game == 2 ? "screamer2" : "screamer");
        if (K->both) snprintf(K->other, sizeof K->other, "%.700s", found[3 - game]);
    }
    K->game = game ? game : 1;
    game_dirs();
    if (home) snprintf(K->home, sizeof K->home, "%s", home);
#ifdef AMIGA
    else strcpy(K->home, "PROGDIR:");          /* AMIGA: the settings, records and replays in the game's drawer
                                                  (wherever it is started from) */
#else
    else if (is_file(".", "openscreamer.cfg") || is_file(".", "openscreamer.records") || is_file(".", "openscreamer.champ"))
        strcpy(K->home, ".");
    else {
        const char *xdg = getenv("XDG_CONFIG_HOME"), *h = getenv("HOME");
#ifdef _WIN32
        char appdata[700];
        xdg = getenv("APPDATA");                  /* WINDOWS: %APPDATA%\openscreamer */
        if (xdg && *xdg) {
            snprintf(appdata, sizeof appdata, "%s", xdg);
            for (char *c = appdata; *c; c++) if (*c == '\\') *c = '/';
            xdg = appdata;
        }
        h = NULL;
#endif
        if (xdg && *xdg) snprintf(K->home, sizeof K->home, "%s/openscreamer", xdg);
        else if (h && *h) snprintf(K->home, sizeof K->home, "%s/.config/openscreamer", h);
        else strcpy(K->home, ".");
    }
#endif
    if (strcmp(K->home, ".") && strcmp(K->home, "PROGDIR:")) {
        char up[768];
        snprintf(up, sizeof up, "%s", K->home);
        char *s = strrchr(up, '/');
        if (s && s != up) { *s = 0; mkdir(up, 0755); }
        mkdir(K->home, 0755);
    }
#ifdef _WIN32
    win_output();
#endif
    if (!is_dir(K->data)) {
        (printf)("Checking game data ... FAILED\n");
        fflush(stdout);
        (fprintf)(stderr, "openscreamer: no game at \"%s\".\n"
                        "Say where your copy of Screamer is with -data DIR (the folder that holds its DATA and\n"
                        "GFX folders), or put it next to the program as \"screamer\".\n", K->data);
#ifdef _WIN32
        win_fatal("The game was not found.\n\nOpenScreamer needs a copy of the original Screamer: put the game's folder "
                  "(the one that holds DATA and GFX) next to openscreamer.exe, named \"screamer\".");
#endif
        exit(1);
    }
    game_check();
}

int   os_dev(void)  { return K && K->dev; }
int   (os_game)(void) { return K ? K->game : 1; }
int   os_both_games(void) { return K && K->both; }
/* BOTH GAMES FOUND (the chooser, main.c): from now on the other one -- its folders, its check,
   and none of the first one's containers kept */
void  os_select_game(int g)
{
    if (!K || !K->both || (g != 1 && g != 2) || g == K->game) return;
    char was[800];
    snprintf(was, sizeof was, "%s", K->data);
    snprintf(K->data, sizeof K->data, "%s", K->other);
    snprintf(K->other, sizeof K->other, "%s", was);
    K->game = g;
    game_dirs();
    for (int i = 0; i < PACKS; i++) { free(K->pack[i].bytes); memset(&K->pack[i], 0, sizeof K->pack[i]); }
    game_check();
}
int   os_argc(void) { return K->has_next ? K->next_argc : K->argc; }
char **os_argv(void) { return K->has_next ? K->next_argv : K->argv; }
const char *os_data_dir(void) { return K ? K->data : "build/dec"; }
const char *os_home_dir(void) { return K ? K->home : "."; }
int   os_has_next(void) { return K->has_next; }
void  os_next_done(void) { K->has_next = 0; }
void *os_slot(int id) { return K->slot[id & 15]; }
void  os_slot_set(int id, void *p) { K->slot[id & 15] = p; }

int os_once(int id)
{
    unsigned bit = 1u << (id & 31), *w = &K->once[(id >> 5) & 3];
    if (*w & bit) return 0;
    *w |= bit;
    return 1;
}

void os_next(int argc, const char *a1, const char *a2)
{
    K->next_argv[0] = K->argv[0];
    if (a1) { snprintf(K->next_store[0], 768, "%s", a1); K->next_argv[1] = K->next_store[0]; }
    if (a2) { snprintf(K->next_store[1], 768, "%s", a2); K->next_argv[2] = K->next_store[1]; }
    K->next_argv[argc] = NULL;
    K->next_argc = argc;
    K->has_next = argc > 0;
}

#if defined(AMIGA) || defined(AMIGA_NULL)
/* AMIGA: the program is AmiScreamer -- its own files are amiscreamer.*; one of an earlier
   version (openscreamer.*) is renamed to the new name the first time it is asked for */
#define OS_OWN "amiscreamer."
static void own_name(char *out, size_t n, const char *rest)
{
    char old[1024];
    snprintf(out, n, "%s/" OS_OWN "%s", K->home, rest);
    snprintf(old, sizeof old, "%s/openscreamer.%s", K->home, rest);
    struct stat st;
    if (stat(out, &st) != 0 && stat(old, &st) == 0) rename(old, out);
}
#else
#define OS_OWN "openscreamer."
static void own_name(char *out, size_t n, const char *rest) { snprintf(out, n, "%s/" OS_OWN "%s", K->home, rest); }
#endif

const char *os_path(const char *path)
{
    static char buf[8][1024];
    static int at;
    if (!K || !path) return path;
    char *out = buf[at++ & 7];
    if (!strncmp(path, "build/dec/", 10)) snprintf(out, 1024, "%s/%s", K->data, path + 10);
    else if (!strcmp(path, "build/dec")) snprintf(out, 1024, "%s", K->data);
    else if (!strncmp(path, "openscreamer.", 13)) {
        const char *rest = path + 13, *sl = strchr(rest, '/');
        if (sl) {                                         /* a file in one of the own folders */
            char dir[64];
            snprintf(dir, sizeof dir, "%.*s", (int)(sl - rest), rest);
            own_name(out, 1024, dir);
            snprintf(out, 1024, "%s/" OS_OWN "%s", K->home, rest);
        } else own_name(out, 1024, rest);
    }
    else if (!strncmp(path, "S2REPLAYS/", 10)) {          /* Screamer 2's replays (the game's REPLAYS folder, its files as they are) */
        own_name(out, 1024, "s2replays");
        mkdir(out, 0755);
        snprintf(out, 1024, "%s/" OS_OWN "s2replays/%s", K->home, path + 10);
    }
    else if (!strncmp(path, "REPLAYS/", 8)) {            /* time-attack ghosts: the port's own, not the game's directory */
        own_name(out, 1024, "ghosts");
        mkdir(out, 0755);
        snprintf(out, 1024, "%s/" OS_OWN "ghosts/%s", K->home, path + 8);
    }
    else return path;
    return out;
}

/* a file of the game's CONFIG folder (CONTROLS.CFG), any letter case; NULL when
   the data directory is not a copy of the game or has no such file */
FILE *os_config_open(const char *name)
{
    char dir[1024], file[1300];
    if (!K || !ci_find(K->data, "CONFIG", dir, sizeof dir) || !ci_find(dir, name, file, sizeof file)) return NULL;
    return fopen(file, "rb");
}

FILE *os_fopen(const char *path, const char *mode)
{
    if (K && K->packed && path && mode && mode[0] == 'r' && !strncmp(path, "build/dec/", 10))
        return packed_open(path + 10);
    return fopen(os_path(path), mode);
}

void *os_malloc(size_t n)
{
    block *b = malloc(sizeof *b + n);
    if (!b) return NULL;
    b->size = n; b->magic = MAGIC; b->prev = NULL;
    b->next = K ? K->blocks : NULL;
    if (b->next) b->next->prev = b;
    if (K) K->blocks = b;
    return b + 1;
}

/* memory that outlives the parts (what an os_slot points at): the C library's own, which
   os_state_restore() does not free */
void *os_keep_calloc(size_t n, size_t each)
{
    return calloc(n, each);
}

void *os_calloc(size_t n, size_t each)
{
    void *p = os_malloc(n * each);
    if (p) memset(p, 0, n * each);
    return p;
}

static void unlink_block(block *b)
{
    if (b->prev) b->prev->next = b->next; else if (K) K->blocks = b->next;
    if (b->next) b->next->prev = b->prev;
}

void os_free(void *p)
{
    if (!p) return;
    block *b = (block *)p - 1;
    if (b->magic != MAGIC) { free(p); return; }          /* not one of ours */
    unlink_block(b);
    b->magic = 0;
    free(b);
}

void *os_realloc(void *p, size_t n)
{
    if (!p) return os_malloc(n);
    block *b = (block *)p - 1;
    if (b->magic != MAGIC) return realloc(p, n);
    void *q = os_malloc(n);
    if (!q) return NULL;
    memcpy(q, p, b->size < n ? b->size : n);
    os_free(p);
    return q;
}

#if (defined(AMIGA) || defined(AMIGA_NULL)) && (defined(__m68k__) || defined(__mc68000__)) && !defined(GEO_C_ONLY) && !defined(SPAN_C_ONLY)
uintptr_t nz68k(const uintptr_t *p, const uintptr_t *end);
#endif
void os_state_save(void)
{
    keep *k = K;
    k->data_len = (size_t)(_edata - __data_start);
    k->data_copy = malloc(k->data_len ? k->data_len : 1);
    memcpy(k->data_copy, __data_start, k->data_len);
    /* the zero-filled statics: a handful of words are not zero already (the
       C library's stdout / stderr, and this file's own K) -- note which */
    uintptr_t *w = (uintptr_t *)(((uintptr_t)__bss_start + sizeof(uintptr_t) - 1) & ~(sizeof(uintptr_t) - 1));
    uintptr_t *end = (uintptr_t *)((uintptr_t)_end & ~(sizeof(uintptr_t) - 1));
    size_t n = 0, cap = 64;
    k->bss_at = malloc(cap * sizeof *k->bss_at);
    k->bss_val = malloc(cap * sizeof *k->bss_val);
    for (uintptr_t *p = w; p < end; p++) {
#if (defined(AMIGA) || defined(AMIGA_NULL)) && (defined(__m68k__) || defined(__mc68000__)) && !defined(GEO_C_ONLY) && !defined(SPAN_C_ONLY)
        p = (uintptr_t *)nz68k(p, end);                 /* (the zeros skipped in vasm: amiga/sys/lzw_68k.s) */
        if (p >= end) break;
#endif
        if (!*p) continue;
        if (n == cap) {
            cap *= 2;
            k->bss_at = realloc(k->bss_at, cap * sizeof *k->bss_at);
            k->bss_val = realloc(k->bss_val, cap * sizeof *k->bss_val);
        }
        k->bss_at[n] = (size_t)(p - w); k->bss_val[n] = *p; n++;
    }
    k->bss_n = n;
    if (getenv("OS_BSSLOG")) printf("state: %lu bytes of zero-filled statics, %lu words not zero\n", (unsigned long)((end - w) * sizeof *w), (unsigned long)n);
}

void os_state_restore(void)
{
    keep *k = K;
    while (k->blocks) {                                  /* everything a part allocated */
        block *b = k->blocks;
        k->blocks = b->next;
        b->magic = 0;
        free(b);
    }
    memcpy(__data_start, k->data_copy, k->data_len);
    memset(__bss_start, 0, (size_t)(_end - __bss_start));
    uintptr_t *w = (uintptr_t *)(((uintptr_t)__bss_start + sizeof(uintptr_t) - 1) & ~(sizeof(uintptr_t) - 1));
    for (size_t i = 0; i < k->bss_n; i++) w[k->bss_at[i]] = k->bss_val[i];
}

/* ---- the environment, remembered (port.h) ---- */

#define ENV_SLOTS 1024
static struct { const char *name; const char *value; unsigned age; } env_slot[ENV_SLOTS];
static unsigned env_age = 1;

const char *os_getenv(const char *name)
{
    unsigned at = (unsigned)(((uintptr_t)name >> 2) * 2654435761u) >> 22;
    for (int k = 0; k < 4; k++, at = (at + 1) & (ENV_SLOTS - 1)) {
        if (env_slot[at].name == name && env_slot[at].age == env_age) return env_slot[at].value;
        if (env_slot[at].name == name || !env_slot[at].name || env_slot[at].age != env_age) {
            env_slot[at].name = name;
            env_slot[at].value = getenv(name);
            env_slot[at].age = env_age;
            return env_slot[at].value;
        }
    }
    return getenv(name);
}

int os_setenv(const char *name, const char *value, int overwrite)
{
    env_age++;
#ifdef OS_MOS
    setenv(name, value, overwrite);             /* (MorphOS: a void setenv) */
    return 0;
#else
    return setenv(name, value, overwrite);
#endif
}

int os_unsetenv(const char *name)
{
    env_age++;
#ifdef OS_MOS
    unsetenv(name);
    return 0;
#else
    return unsetenv(name);
#endif
}
