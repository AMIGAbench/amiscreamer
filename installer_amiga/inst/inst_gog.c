/* GOG-Installationsprogramm (setup_screamer_*.exe) als Installationsquelle.
 * Aufbau (am PC ausgelesen, 1.01 GOG v2):
 *  - Inno Setup 5.6 (Unicode). Offset-Tabelle "rDlPtS..." (Version 1) im Programm -> Offset0 (Kopf), Offset1 (Daten).
 *  - Kopf: Kennung (64 Byte), dann zwei Blöcke {CRC32, Größe, komprimiert} aus 4-KB-Stücken mit je eigener CRC32,
 *    LZMA1 (5 Byte Props vorn). Block 1: Setup-Kopf + Einträge, Block 2: Dateiorte (74 Byte je Eintrag, StartOffset @8,
 *    OriginalSize @20).
 *  - GOG-Teile: jede Inno-Datei ist ein zlib-Strom (ein Teil, entpackt <= 8 MiB), Inno speichert ihn unkomprimiert
 *    (Chunk "zlb\x1a" + Daten). Datei-Einträge tragen AfterInstall "after_install('<md5 Teil>', <gepackt>, <entpackt>)",
 *    beim ersten Teil einer Datei zusätzlich BeforeInstall "before_install('<md5 Datei>', '<Name>', <Teile>)";
 *    LocationEntry (int32) liegt 20 Byte hinter dem Ende des BeforeInstall-Strings (MinVersion/OnlyBelowVersion).
 *    Teile einer Datei folgen in Kopf-Reihenfolge. Jede Zuordnung wird über die Größe des Dateiorts geprüft. */
#include "inst_gog.h"
#include "inst_core.h"
#include "lzmadec.h"
#include "md5.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

typedef struct {
    uint32_t off;                               /* Datei-Offset der Daten (nach "zlb\x1a") */
    uint32_t csize, usize;
    uint8_t md5[16];
} Part;
typedef struct {
    char name[96];
    uint8_t md5[16];
    uint64_t size;
    int first, n;                               /* Teile parts[first .. first + n - 1] */
} GFile;
struct GogSetup {
    FILE *f;
    Part *parts;
    int nparts;
    GFile *files;
    int nfiles;
    uint8_t *ibuf, *obuf;
};
enum { IBUF = 65536, OBUF = 262144 };

static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

static int rd(FILE *f, uint32_t off, void *p, size_t n)
{
    return fseek(f, (long)off, SEEK_SET) != 0 || fread(p, 1, n, f) != n;
}

/* Kopfblock bei off: Daten (ohne Stück-CRCs) entpacken; *next = Ende des Blocks */
static int hdr_block(FILE *f, uint32_t off, uint8_t **out, size_t *outn, uint32_t *next)
{
    uint8_t h[9];
    if (rd(f, off, h, 9) || crc32(0, h + 4, 5) != le32(h))
        return -1;
    uint32_t stored = le32(h + 4);
    if (!h[8] || stored < 9 || stored > 16u << 20)
        return -1;
    uint8_t *raw = malloc(stored), *d = malloc(stored);
    if (!raw || !d || rd(f, off + 9, raw, stored)) {
        free(raw);
        free(d);
        return -1;
    }
    size_t dn = 0;
    for (uint32_t p = 0; p < stored;) {          /* 4-KB-Stücke mit CRC32 davor */
        uint32_t n = stored - p < 4096 + 4 ? stored - p : 4096 + 4;
        if (n < 5 || crc32(0, raw + p + 4, n - 4) != le32(raw + p)) {
            free(raw);
            free(d);
            return -2;
        }
        memcpy(d + dn, raw + p + 4, n - 4);
        dn += n - 4;
        p += n;
    }
    free(raw);
    int rc = dn > 5 ? lzma_decode(d, d + 5, dn - 5, out, outn) : -1;
    free(d);
    *next = off + 9 + stored;
    return rc;
}

/* UTF-16LE (nur ASCII) in char */
static void u16(const uint8_t *p, uint32_t bytes, char *o, size_t on)
{
    size_t k = 0;
    for (uint32_t i = 0; i + 1 < bytes && k + 1 < on; i += 2)
        o[k++] = p[i + 1] ? '?' : (char)p[i];
    o[k] = 0;
}
static int hex16(const char *s, uint8_t md[16])
{
    for (int i = 0; i < 16; i++) {
        unsigned v;
        if (sscanf(s + 2 * i, "%2x", &v) != 1)
            return -1;
        md[i] = (uint8_t)v;
    }
    return 0;
}

GogSetup *gog_open(const char *path, char *err, size_t errn)
{
    static const uint8_t id[12] = {'r', 'D', 'l', 'P', 't', 'S', 0xcd, 0xe6, 0xd7, 0x7b, 0x0b, 0x2a};
    GogSetup *g = calloc(1, sizeof *g);
    uint8_t *buf = malloc(IBUF + 64), *h1 = NULL, *h2 = NULL;
    size_t n1 = 0, n2 = 0;
    const char *why = "cannot read the file";
    if (!g || !buf || !(g->f = fopen(path, "rb")))
        goto fail;
    setvbuf(g->f, NULL, _IOFBF, 65536);
    /* Offset-Tabelle in den ersten 4 MB suchen */
    uint32_t tab = 0, base = 0;
    int found = 0;
    size_t have = 0;
    while (!found && base < (4u << 20)) {
        size_t n = fread(buf + have, 1, IBUF, g->f);
        if (!n)
            break;
        have += n;
        for (size_t i = 0; i + 44 <= have; i++)
            if (!memcmp(buf + i, id, 12)) {
                tab = base + (uint32_t)i;
                found = 1;
                break;
            }
        if (!found && have > 64) {
            memmove(buf, buf + have - 64, 64);
            base += (uint32_t)(have - 64);
            have = 64;
        }
    }
    why = "no Inno Setup installer (not a GOG setup_screamer_*.exe?)";
    uint8_t t[44];
    if (!found || rd(g->f, tab, t, 44) || le32(t + 12) != 1)
        goto fail;
    uint32_t off0 = le32(t + 32), off1 = le32(t + 36);
    char vid[65];
    if (rd(g->f, off0, vid, 64))
        goto fail;
    vid[64] = 0;
    why = "unsupported installer version (Inno Setup 5.6 Unicode expected)";
    if (strncmp(vid, "Inno Setup Setup Data (5.6.", 27) || !strstr(vid, "(u)"))
        goto fail;
    uint32_t next;
    why = "installer header damaged";
    if (hdr_block(g->f, off0 + 64, &h1, &n1, &next) || hdr_block(g->f, next, &h2, &n2, &next) || n2 % 74)
        goto fail;
    uint32_t nloc = (uint32_t)(n2 / 74);
    /* Teile: UTF-16 "after_install(" mit Längenpräfix */
    static const char key[] = "after_install(";
    uint8_t k16[28];
    for (int i = 0; i < 14; i++) {
        k16[2 * i] = (uint8_t)key[i];
        k16[2 * i + 1] = 0;
    }
    int cap = 64;
    g->parts = malloc(cap * sizeof *g->parts);
    g->files = malloc(cap * sizeof *g->files);
    int fcap = cap;
    why = "unknown GOG installer layout";
    for (size_t s = 4; s + 28 < n1; s++) {
        if (h1[s] != 'a' || memcmp(h1 + s, k16, 28))
            continue;
        uint32_t L = le32(h1 + s - 4), e = (uint32_t)s + L;
        if (L & 1 || L > 400 || e + 8 > n1)
            continue;
        char a[220], b[400];
        u16(h1 + s, L, a, sizeof a);
        uint32_t L2 = le32(h1 + e);
        if (L2 & 1 || L2 > 780 || e + 4 + L2 + 24 > n1)
            goto fail;
        u16(h1 + e + 4, L2, b, sizeof b);
        uint32_t loc = le32(h1 + e + 4 + L2 + 20);
        char md[33];
        unsigned long cs, us;
        if (sscanf(a, "after_install('%32[0-9a-f]', %lu, %lu)", md, &cs, &us) != 3 || loc >= nloc)
            goto fail;
        const uint8_t *le = h2 + 74 * loc;
        if (le32(le + 20) != cs || le32(le + 24) != 0 || cs < 6)   /* Größe des Dateiorts */
            goto fail;
        if (g->nparts == cap) {
            cap *= 2;
            g->parts = realloc(g->parts, cap * sizeof *g->parts);
        }
        Part *p = &g->parts[g->nparts];
        p->off = off1 + le32(le + 8) + 4;
        p->csize = (uint32_t)cs;
        p->usize = (uint32_t)us;
        if (hex16(md, p->md5))
            goto fail;
        if (b[0]) {                             /* erster Teil einer Datei */
            char nm[96];
            int np;
            if (sscanf(b, "before_install('%32[0-9a-f]', '%95[^']', %d)", md, nm, &np) != 3 || np < 1)
                goto fail;
            if (g->nfiles && g->files[g->nfiles - 1].n != g->nparts - g->files[g->nfiles - 1].first)
                goto fail;
            if (g->nfiles == fcap) {
                fcap *= 2;
                g->files = realloc(g->files, fcap * sizeof *g->files);
            }
            GFile *gf = &g->files[g->nfiles++];
            snprintf(gf->name, sizeof gf->name, "%s", nm);
            hex16(md, gf->md5);
            gf->first = g->nparts;
            gf->n = np;
            gf->size = 0;
        } else if (!g->nfiles)
            goto fail;
        g->files[g->nfiles - 1].size += us;
        g->nparts++;
    }
    if (!g->nfiles || g->files[g->nfiles - 1].n != g->nparts - g->files[g->nfiles - 1].first)
        goto fail;
    for (int i = 0; i < g->nfiles; i++)           /* Teilanzahlen */
        if (i + 1 < g->nfiles && g->files[i + 1].first - g->files[i].first != g->files[i].n)
            goto fail;
    free(h1);
    free(h2);
    free(buf);
    g->ibuf = malloc(IBUF);
    g->obuf = malloc(OBUF);
    if (!g->ibuf || !g->obuf) {
        why = "out of memory";
        gog_close(g);
        snprintf(err, errn, "%s", why);
        return NULL;
    }
    return g;
fail:
    snprintf(err, errn, "%s", why);
    free(h1);
    free(h2);
    free(buf);
    gog_close(g);
    return NULL;
}

void gog_close(GogSetup *g)
{
    if (!g)
        return;
    if (g->f)
        fclose(g->f);
    free(g->parts);
    free(g->files);
    free(g->ibuf);
    free(g->obuf);
    free(g);
}

int gog_count(const GogSetup *g) { return g->nfiles; }
const char *gog_name(const GogSetup *g, int i) { return g->files[i].name; }
uint64_t gog_size(const GogSetup *g, int i) { return g->files[i].size; }

int gog_find(const GogSetup *g, const char *name)
{
    for (int i = 0; i < g->nfiles; i++) {
        const char *a = g->files[i].name, *b = name;
        for (;; a++, b++) {
            int x = *a == '/' ? '\\' : *a, y = *b == '/' ? '\\' : *b;
            if (x >= 'a' && x <= 'z')
                x -= 32;
            if (y >= 'a' && y <= 'z')
                y -= 32;
            if (x != y)
                break;
            if (!x)
                return i;
        }
    }
    return -1;
}

int gog_read(GogSetup *g, int i, gog_out_fn out, void *ctx)
{
    GFile *gf = &g->files[i];
    Md5 fm;
    md5_init(&fm);
    for (int k = 0; k < gf->n; k++) {
        Part *p = &g->parts[gf->first + k];
        uint8_t sig[4];
        if (rd(g->f, p->off - 4, sig, 4))
            return 2;
        if (memcmp(sig, "zlb\x1a", 4))
            return 3;
        z_stream z;
        memset(&z, 0, sizeof z);
        if (inflateInit(&z) != Z_OK)
            return 3;
        Md5 pm;
        md5_init(&pm);
        uint32_t left = p->csize, got = 0;
        int zr = Z_OK, rc = 0;
        while (zr != Z_STREAM_END && !rc) {
            if (!z.avail_in) {
                uint32_t n = left < IBUF ? left : IBUF;
                if (!n) {
                    rc = 3;
                    break;
                }
                if (fread(g->ibuf, 1, n, g->f) != n) {
                    rc = 2;
                    break;
                }
                left -= n;
                z.next_in = g->ibuf;
                z.avail_in = n;
            }
            z.next_out = g->obuf;
            z.avail_out = OBUF;
            zr = inflate(&z, Z_NO_FLUSH);
            if (zr != Z_OK && zr != Z_STREAM_END) {
                rc = 3;
                break;
            }
            size_t n = OBUF - z.avail_out;
            if (n) {
                md5_update(&pm, g->obuf, n);
                md5_update(&fm, g->obuf, n);
                got += (uint32_t)n;
                if (out(ctx, g->obuf, n))
                    rc = 1;
            }
        }
        inflateEnd(&z);
        if (rc)
            return rc;
        uint8_t d[16];
        md5_final(&pm, d);
        if (got != p->usize || memcmp(d, p->md5, 16))
            return 3;
    }
    uint8_t d[16];
    md5_final(&fm, d);
    return memcmp(d, gf->md5, 16) ? 3 : 0;
}

void gog_join(char *o, size_t n, const char *dir, const char *rel)
{
    size_t l = strlen(dir);
    const char *sep = !l || dir[l - 1] == ':' || dir[l - 1] == '/' ? "" : "/";
    snprintf(o, n, "%s%s%s", dir, sep, rel);
}

/* Datei aus dem GOG-Paket installieren? rel = Zielpfad relativ zum Spielverzeichnis ('/') */
static int wanted(const char *name, char *rel, size_t n)
{
    static const char *const dirs[] = {"DATA\\", "GFX\\", "TABS\\", "REPLAYS\\"};
    static const char *const single[] = {"STARTH.EXE", "STARTL.EXE", "CONFIG\\DEFCTRL.CFG", "CONFIG\\SETUP.DAT"};
    int ok = 0;
    for (int i = 0; i < 4 && !ok; i++)
        ok = !strncmp(name, dirs[i], strlen(dirs[i])) || !strcmp(name, single[i]);
    size_t l = strlen(name);
    if (!ok && !strncmp(name, "CONFIG\\", 7) && l > 4 && !strcmp(name + l - 4, ".ICO"))
        ok = 1;
    if (!ok)
        return 0;
    snprintf(rel, n, "%s", name);
    for (char *c = rel; *c; c++)
        if (*c == '\\')
            *c = '/';
    return 1;
}

typedef struct {
    FILE *f;
    const GogCb *cb;
    const char *name;
    uint64_t done, size;
    int last, err;
} FileOut;
static int file_out(void *ctx, const uint8_t *p, size_t n)
{
    FileOut *o = ctx;
    if (fwrite(p, 1, n, o->f) != n) {
        o->err = 1;
        return 1;
    }
    o->done += n;
    int pct = o->size ? (int)(o->done * 100 / o->size) : 100;
    if (pct != o->last) {
        o->last = pct;
        if (o->cb->file && o->cb->file(o->cb->ctx, o->name, pct))
            return 1;
    }
    return 0;
}

int gog_install(GogSetup *g, const char *dir, const GogCb *cb)
{
    char rel[128], path[400];
    int any = 0;
    for (int i = 0; i < g->nfiles; i++) {
        if (!wanted(g->files[i].name, rel, sizeof rel))
            continue;
        char *sl = strchr(rel, '/');
        if (sl) {                               /* Unterverzeichnis (eine Ebene) */
            *sl = 0;
            gog_join(path, sizeof path, dir, rel);
            *sl = '/';
            if (cb->mkdir && cb->mkdir(cb->ctx, path))
                return 4;
        }
        gog_join(path, sizeof path, dir, rel);
        FileOut o = {fopen(path, "wb"), cb, rel, 0, g->files[i].size, -1, 0};
        if (!o.f)
            return 4;
        setvbuf(o.f, NULL, _IOFBF, 65536);
        int rc = gog_read(g, i, file_out, &o);
        if (fclose(o.f) && !rc)
            rc = 4;
        if (o.err)
            rc = 4;
        if (rc) {
            remove(path);
            return rc;
        }
        any = 1;
    }
    return any && gog_find(g, "STARTH.EXE") >= 0 ? 0 : 5;
}

/* ---------------------------------------------------------------- Musik aus SCREAM.gog */
enum { MAXTR = 99 };
typedef struct {
    char *t;
    size_t n, cap;
} Mem;
static int mem_out(void *ctx, const uint8_t *p, size_t n)
{
    Mem *m = ctx;
    if (m->n + n > m->cap)
        return 1;
    memcpy(m->t + m->n, p, n);
    m->n += n;
    return 0;
}
static int raw_out(void *ctx, const uint8_t *p, size_t n) { return fwrite(p, 1, n, (FILE *)ctx) != n; }

typedef struct {
    const GogCb *cb;
    const char *dir;
    int ntr, num[MAXTR];
    uint32_t start[MAXTR + 1];                  /* Sektor; start[ntr] = Ende des Abbilds */
    uint64_t pos;                               /* Bytes des Abbilds bisher */
    int cur;                                    /* Spur in Arbeit (-1 = keine) */
    MusConv *m;
    FILE *f;
    char path[400];
    uint8_t carry[4];
    int ncarry, last, err, done;
} MusRun;

static int track_end(MusRun *r, int ok)
{
    int rc = 0;
    if (r->m) {
        if (ok)
            rc = mus_end(r->m) ? 4 : 0;
        else
            mus_abort(r->m);
        r->m = NULL;
    }
    if (r->f) {
        if (fclose(r->f) && !rc)
            rc = 4;
        r->f = NULL;
        if (!ok || rc)
            remove(r->path);
    }
    return rc;
}

static int mus_out_cb(void *ctx, const uint8_t *p, size_t n)
{
    MusRun *r = ctx;
    while (n) {
        uint32_t sec = (uint32_t)(r->pos / 2352);
        int t = -1;
        for (int i = 0; i < r->ntr; i++)
            if (sec >= r->start[i] && sec < r->start[i + 1])
                t = i;
        if (t != r->cur) {                      /* Spurwechsel */
            if (r->cur >= 0) {
                if ((r->err = track_end(r, 1)))
                    return 1;
                r->done++;
                if (r->cb->track && r->cb->track(r->cb->ctx, r->num[r->cur], 101, r->start[r->cur + 1] - r->start[r->cur]))
                    return 1;
            }
            r->cur = t;
            r->last = -1;
            if (t >= 0) {
                char nm[16];
                snprintf(nm, sizeof nm, "track%02d.raw", r->num[t]);
                gog_join(r->path, sizeof r->path, r->dir, nm);
                if (!(r->f = fopen(r->path, "wb"))) {
                    r->err = 4;
                    return 1;
                }
                setvbuf(r->f, NULL, _IOFBF, 65536);
                if (!(r->m = mus_begin((r->start[t + 1] - r->start[t]) * 588, raw_out, r->f))) {
                    r->err = 4;
                    return 1;
                }
            }
        }
        /* bis zum Ende der Spur bzw. bis zur ersten Audiospur (Datenspur überspringen) */
        uint32_t limsec = t >= 0 ? r->start[t + 1] : sec < r->start[0] ? r->start[0] : sec + 1;
        uint64_t lim = (uint64_t)limsec * 2352;
        size_t k = lim - r->pos < n ? (size_t)(lim - r->pos) : n;
        if (r->cur >= 0) {
            size_t i = 0;
            while (r->ncarry && i < k) {        /* angefangenes Abtastpaar */
                r->carry[r->ncarry++] = p[i++];
                if (r->ncarry == 4) {
                    if (mus_feed(r->m, r->carry, 1)) {
                        r->err = 4;
                        return 1;
                    }
                    r->ncarry = 0;
                }
            }
            size_t pairs = (k - i) / 4;
            if (pairs && mus_feed(r->m, p + i, pairs)) {
                r->err = 4;
                return 1;
            }
            for (size_t j = i + pairs * 4; j < k; j++)
                r->carry[r->ncarry++] = p[j];
            uint32_t tot = r->start[r->cur + 1] - r->start[r->cur];
            int pct = (int)((r->pos + k - (uint64_t)r->start[r->cur] * 2352) * 100 / ((uint64_t)tot * 2352));
            if (r->cb->track && r->cb->track(r->cb->ctx, r->num[r->cur], pct, tot))   /* je Block (Abbruch) */
                return 1;
        }
        r->pos += k;
        p += k;
        n -= k;
    }
    return 0;
}

int gog_music(GogSetup *g, const char *dir, const GogCb *cb, int *ntracks)
{
    *ntracks = 0;
    int ic = gog_find(g, "SCREAM.DAT"), ib = gog_find(g, "SCREAM.gog");
    if (ic < 0 || ib < 0 || g->files[ic].size > 8192)
        return 5;
    static char cue[8193];                      /* nicht auf den Stapel: Amiga-Shell gibt nur 4 KB */
    Mem mm = {cue, 0, 8192};
    int rc = gog_read(g, ic, mem_out, &mm);
    if (rc)
        return rc;
    cue[mm.n] = 0;
    static MusRun r;
    memset(&r, 0, sizeof r);
    r.cb = cb;
    r.dir = dir;
    r.cur = -1;
    int tr = -1, audio = 0;
    for (char *l = cue; *l;) {
        char *e = l + strcspn(l, "\r\n");
        char save = *e;
        *e = 0;
        int a, mi, se, fr;
        char kind[16];
        if (sscanf(l, " TRACK %d %15s", &a, kind) == 2) {
            tr = a;
            audio = !strcmp(kind, "AUDIO");
        } else if (sscanf(l, " INDEX 01 %d:%d:%d", &mi, &se, &fr) == 3 && audio && r.ntr < MAXTR) {
            r.num[r.ntr] = tr;
            r.start[r.ntr++] = (uint32_t)((mi * 60 + se) * 75 + fr);
        }
        *e = save;
        l = e;
        while (*l == '\r' || *l == '\n')
            l++;
    }
    uint64_t sz = g->files[ib].size;
    if (!r.ntr || sz % 2352)
        return 5;
    r.start[r.ntr] = (uint32_t)(sz / 2352);
    for (int i = 0; i < r.ntr; i++)
        if (r.start[i] >= r.start[i + 1])
            return 5;
    rc = gog_read(g, ib, mus_out_cb, &r);
    if (!rc && r.cur >= 0) {                    /* letzte Spur */
        rc = track_end(&r, 1);
        if (!rc) {
            r.done++;
            if (cb->track)
                cb->track(cb->ctx, r.num[r.cur], 101, r.start[r.cur + 1] - r.start[r.cur]);
        }
    } else if (rc) {
        track_end(&r, 0);
        if (r.err)
            rc = r.err;
    }
    *ntracks = r.done;
    return rc;
}
