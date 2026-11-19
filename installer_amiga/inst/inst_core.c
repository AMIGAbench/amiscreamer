/* Installer-Kern, siehe inst_core.h */
#include "inst_core.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void be16(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }
static void be32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v; }
static void sle32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }

/* ---------------------------------------------------------------- Archiv (orig 0x4c128 Verzeichnis, 0x4d4c4 LZW) */
/* LZW wie Unix compress, LSB zuerst, 9..12 Bit, 0x100 = Neuanfang, 0x101 = Ende, erster freier Code 0x102 */
static size_t lzw_decode(const uint8_t *src, size_t sn, uint8_t *out, size_t outsize)
{
    static uint16_t prefix[4096];
    static uint8_t suffix[4096], stack[4096];
    for (int i = 0; i < 256; i++)
        suffix[i] = (uint8_t)i;
    int bits = 9, maxc = 0x200, nextc = 0x102, old = -1, fin = 0;
    size_t bitpos = 0, nbits = sn * 8, o = 0;
    while (o < outsize && bitpos + (size_t)bits <= nbits) {
        size_t by = bitpos >> 3;
        uint32_t v = src[by] | (by + 1 < sn ? src[by + 1] << 8 : 0) | (by + 2 < sn ? (uint32_t)src[by + 2] << 16 : 0);
        int code = (int)(v >> (bitpos & 7) & ((1u << bits) - 1));
        bitpos += (size_t)bits;
        if (code == 0x101)
            break;
        if (code == 0x100) {
            bits = 9, maxc = 0x200, nextc = 0x102;
            if (bitpos + (size_t)bits > nbits)
                break;
            by = bitpos >> 3;
            v = src[by] | (by + 1 < sn ? src[by + 1] << 8 : 0) | (by + 2 < sn ? (uint32_t)src[by + 2] << 16 : 0);
            old = fin = (int)(v >> (bitpos & 7) & ((1u << bits) - 1));
            bitpos += (size_t)bits;
            out[o++] = (uint8_t)old;
            continue;
        }
        int incode = code, sp = 0;
        if (code >= nextc) {                    /* KwKwK */
            stack[sp++] = (uint8_t)fin;
            code = old;
        }
        while (code > 0xff && sp < 4095) {
            stack[sp++] = suffix[code];
            code = prefix[code];
        }
        fin = code;
        stack[sp++] = (uint8_t)code;
        while (sp && o < outsize)
            out[o++] = stack[--sp];
        if (old >= 0 && nextc < 4096) {
            prefix[nextc] = (uint16_t)old;
            suffix[nextc] = (uint8_t)fin;
            nextc++;
            if (nextc >= maxc && bits != 12) {
                bits++;
                maxc *= 2;
            }
        }
        old = incode;
    }
    return o;
}

/* Verzeichnis am Dateiende: u32 Größe, davor Einträge zu 32 Byte (Name XOR 0x3a, Versatz, gepackt, Größe, Flaggen) */
uint8_t *arc_load(const uint8_t *arc, size_t arcn, const char *name, size_t *n)
{
    if (arcn < 4)
        return NULL;
    uint32_t ds = le32(arc + arcn - 4);
    if (ds > arcn - 4)
        return NULL;
    const uint8_t *dir = arc + arcn - 4 - ds;
    for (uint32_t i = 0; i + 32 <= ds; i += 32) {
        char nm[17];
        for (int k = 0; k < 16; k++)
            nm[k] = (char)(dir[i + k] ^ 0x3a);
        nm[16] = 0;
        size_t l = strlen(name);
        int eq = strlen(nm) == l;
        for (size_t k = 0; eq && k < l; k++) {
            char a = nm[k], b = name[k];
            if (a >= 'a' && a <= 'z') a = (char)(a - 32);
            if (b >= 'a' && b <= 'z') b = (char)(b - 32);
            eq = a == b;
        }
        if (!eq)
            continue;
        uint32_t off = le32(dir + i + 16), packed = le32(dir + i + 20), size = le32(dir + i + 24), fl = le32(dir + i + 28);
        if ((uint64_t)off + packed > arcn)
            return NULL;
        uint8_t *o = malloc(size ? size : 1);
        if (!o)
            return NULL;
        if (fl & 2)
            *n = lzw_decode(arc + off, packed, o, size);
        else
            memcpy(o, arc + off, *n = packed < size ? packed : size);
        return o;
    }
    return NULL;
}

/* ---------------------------------------------------------------- Titellogo */
int logo_build(const uint8_t *graf, size_t grafn, uint8_t blk[LOGO_BLOCK])
{
    size_t sn = 0, pn = 0;
    uint8_t *spr = arc_load(graf, grafn, "MENUL.SPR", &sn), *pcx = arc_load(graf, grafn, "MENU1L.PCX", &pn);
    int rc = 1;
    if (!spr || !pcx || sn < 8 || pn < 769 || pcx[pn - 769] != 0x0c)
        goto out;
    const uint8_t *pal = pcx + pn - 768;
    uint32_t cnt = le32(spr), base = 8 + 20 * cnt;
    if (cnt < 16 || base > sn)
        goto out;
    struct { int32_t x, y, w, h; const uint8_t *p; } pt[2];
    for (int k = 0; k < 2; k++) {               /* 15 orange bei ((320 - w)/2 + 4, 0), 14 weiß bei ((320 - w)/2, 16) */
        int i = k ? 14 : 15;
        const uint8_t *e = spr + 8 + 20 * i;
        int32_t ox = (int32_t)le32(e), oy = (int32_t)le32(e + 4), w = (int32_t)le32(e + 8), h = (int32_t)le32(e + 12);
        uint32_t o = le32(e + 16);
        if (w <= 0 || h <= 0 || (uint64_t)base + o + (uint64_t)w * h > sn)
            goto out;
        pt[k].x = (320 - w) / 2 + (k ? 0 : 4) + ox;
        pt[k].y = (k ? 16 : 0) + oy;
        pt[k].w = w, pt[k].h = h, pt[k].p = spr + base + o;
    }
    int32_t x0 = pt[0].x < pt[1].x ? pt[0].x : pt[1].x, y0 = pt[0].y < pt[1].y ? pt[0].y : pt[1].y;
    int32_t x1 = pt[0].x + pt[0].w > pt[1].x + pt[1].w ? pt[0].x + pt[0].w : pt[1].x + pt[1].w;
    int32_t y1 = pt[0].y + pt[0].h > pt[1].y + pt[1].h ? pt[0].y + pt[0].h : pt[1].y + pt[1].h;
    int32_t w = x1 - x0, h = y1 - y0;
    if (h != LOGO_MAXW || w != LOGO_MAXH)       /* nach der Drehung 44 x 320 */
        goto out;
    static uint8_t img[LOGO_MAXW * LOGO_MAXH], rot[LOGO_MAXW * LOGO_MAXH];
    memset(img, 0, sizeof img);
    for (int k = 0; k < 2; k++)
        for (int32_t yy = 0; yy < pt[k].h; yy++)
            for (int32_t xx = 0; xx < pt[k].w; xx++) {
                uint8_t c = pt[k].p[yy * pt[k].w + xx];
                if (c)
                    img[(pt[k].y - y0 + yy) * w + pt[k].x - x0 + xx] = c;
            }
    for (int32_t y = 0; y < h; y++)             /* 90 Grad gegen den Uhrzeigersinn: (x, y) -> (y, w - 1 - x) */
        for (int32_t x = 0; x < w; x++)
            rot[(w - 1 - x) * h + y] = img[y * w + x];
    uint8_t map[256] = {0};
    int ncol = 1;
    for (int c = 1; c < 256; c++)               /* benutzte Farben aufsteigend -> 1, 2, ... */
        for (size_t i = 0; i < sizeof rot; i++)
            if (rot[i] == c) {
                if (ncol >= LOGO_MAXC)
                    goto out;
                map[c] = (uint8_t)ncol++;
                break;
            }
    int32_t wx0 = pt[0].x - x0, wx1 = wx0 + pt[0].w - 1;
    memset(blk, 0, LOGO_BLOCK);
    memcpy(blk, "SCRLOGO1", 8);
    be16(blk + 8, LOGO_MAXW);
    be16(blk + 10, LOGO_MAXH);
    be16(blk + 12, (uint32_t)ncol);
    be16(blk + 14, (uint32_t)(w - 1 - wx1));
    be16(blk + 16, (uint32_t)(w - 1 - wx0));
    for (int c = 1; c < 256; c++)
        if (map[c])
            memcpy(blk + 20 + 3 * (map[c] - 1), pal + 3 * c, 3);
    for (size_t i = 0; i < sizeof rot; i++)
        blk[20 + 3 * LOGO_MAXC + i] = map[rot[i]];
    memcpy(blk + LOGO_BLOCK - 8, "SCRLOGOE", 8);
    rc = 0;
out:
    free(spr);
    free(pcx);
    return rc;
}

long logo_find(const uint8_t *prog, size_t n)
{
    for (size_t i = 0; i + LOGO_BLOCK <= n; i += 2)
        if ((!memcmp(prog + i, "SCRLOGO0", 8) || !memcmp(prog + i, "SCRLOGO1", 8)) &&
            !memcmp(prog + i + LOGO_BLOCK - 8, "SCRLOGOE", 8))
            return (long)i;
    return -1;
}

/* ---------------------------------------------------------------- Konfiguration */
void setup_cfg(uint8_t o[0x90])
{
    memset(o, 0, 0x90);
    sle32(o + 0x00, 0xe016);                    /* Digi-Treiber (Port: Effekte an) */
    sle32(o + 0x04, 0x12);
    sle32(o + 0x08, 0x220);
    sle32(o + 0x0c, 7);
    sle32(o + 0x10, 1);
    sle32(o + 0x40, 9);                         /* Modemtyp */
    memcpy(o + 0x44, "AT Z\\N0", 8);
    sle32(o + 0x8c, 1);                         /* Steuergeräte: Tastatur */
}
const char screamer_cfg[] = "C:\\SCREAMER\tD:\tC:\\SCREAMER\tc";

/* ---------------------------------------------------------------- Musik (als Strom)
 * Alles in Ganzzahl (V1200: double-Fassung lief mit 1,3facher Abspielzeit). Der Ring hält die Eingangswerte halbiert
 * (x >> 1), so passt die Paarsumme in 16 Bit. Filter symmetrisch (h[k] = h[62 - k]): je Ausgabewert und Kanal 31 Paare
 * (x[k] + x[62 - k]) * h[k] + x[31] * h[31], alle h in Q16, Summe Q30 (höchstens 1,97e9). fir2 (C) bzw. fir2_68k
 * (inst_68k.s, ganz ausgerollt) rechnen beide Kanäle gleich. Pegel, Begrenzer, Dither und Runden wie music_conv, aber in
 * Festkomma (Q16, Hüllkurve Q20). Gegen music_conv weichen einzelne Werte um 1 LSB ab. */
enum { BLOCK = 4096, TAPS = 63, RING = 256 };
enum {
    GAIN_Q12 = 16306,                           /* 10^(12/20) = 3,981 */
    LIM_Q16 = 63570,                            /* 0,97 */
    REL_Q16 = 50,                               /* 1 - exp(-1 / (0,060 * 22050)) = 7,56e-4 */
};
#define LIM_Q31 2083059139u                     /* 0,97 * 2^31: g (Q15) = LIM_Q31 / Hüllkurve (Q16) */
struct MusConv {
    uint32_t nin, nout, have, done, rng, env;   /* env: Hüllkurve Q20 */
    int16_t hq[32];                             /* h[0..31] Q16 */
    int16_t ring[2][2 * RING];                  /* je Kanal gespiegelt: Fenster ab (j & 255) liegt am Stück */
    int8_t bl[BLOCK], br[BLOCK];
    mus_out_fn out;
    void *ctx;
    int err;
};

#if defined(__m68k__) && defined(INST_ASM)
void fir2_68k(const int16_t *x, const int16_t *h, int32_t *acc);        /* inst_68k.s */
#define fir2 fir2_68k
#else
static void fir2(const int16_t *x, const int16_t *h, int32_t *acc)     /* x: Kanal 0, Kanal 1 bei x + 2 * RING */
{
    for (int c = 0; c < 2; c++, x += 2 * RING) {
        int32_t s = 0;
        for (int k = 0; k < 31; k++)
            s += (int32_t)(int16_t)(x[k] + x[62 - k]) * h[k];
        acc[c] = s + (int32_t)x[31] * h[31];
    }
}
#endif

static int32_t dither(MusConv *m)               /* (rnd - rnd) in Q16 */
{
    int32_t d = 0;
    for (int n = 0; n < 2; n++) {
        m->rng ^= m->rng << 13;
        m->rng ^= m->rng >> 17;
        m->rng ^= m->rng << 5;
        d = (int32_t)(m->rng >> 16) - d;
    }
    return -d;
}

MusConv *mus_begin(uint32_t nin, mus_out_fn out, void *ctx)
{
    MusConv *m = calloc(1, sizeof *m);
    if (!m)
        return NULL;
    m->nin = nin;
    m->nout = nin / 2;
    m->rng = 0x12345678u;
    m->out = out;
    m->ctx = ctx;
    for (int k = 0; k < 32; k++) {
        double x = k - (TAPS - 1) / 2.0, fc = 10000.0 / 44100.0;
        double s = x == 0 ? 2 * fc : sin(2 * M_PI * fc * x) / (M_PI * x);
        double win = 0.42 - 0.5 * cos(2 * M_PI * k / (TAPS - 1)) + 0.08 * cos(4 * M_PI * k / (TAPS - 1));
        m->hq[k] = (int16_t)lround(s * win * 65536.0);
    }
    uint8_t hd[16];
    memcpy(hd, "SMUS", 4);
    be32(hd + 4, 22050);
    be32(hd + 8, BLOCK);
    be32(hd + 12, m->nout);
    if (out(ctx, hd, 16))
        m->err = 1;
    return m;
}

static void flush_block(MusConv *m, uint32_t n)
{
    if (n < BLOCK) {                            /* letzter Block mit Nullen aufgefüllt */
        memset(m->bl + n, 0, BLOCK - n);
        memset(m->br + n, 0, BLOCK - n);
    }
    if (!m->err && (m->out(m->ctx, (const uint8_t *)m->bl, BLOCK) || m->out(m->ctx, (const uint8_t *)m->br, BLOCK)))
        m->err = 1;
}

static void put(MusConv *m, uint32_t j, int16_t l, int16_t r)
{
    uint32_t k = j & (RING - 1);
    m->ring[0][k] = m->ring[0][k + RING] = (int16_t)(l >> 1);
    m->ring[1][k] = m->ring[1][k + RING] = (int16_t)(r >> 1);
}

/* Ausgangswerte berechnen, für die alle nötigen Eingangswerte (bis 2i + 31) da sind bzw. das Ende erreicht ist; vor
 * dem Anfang stehen im Ring Nullen (nie beschrieben), nach dem Ende schreibt mus_end Nullen */
static void produce(MusConv *m, int final)
{
    while (m->done < m->nout && (final || m->done * 2 + (TAPS - 1) / 2 < m->have)) {
        uint32_t i = m->done, b = (i * 2 - (TAPS - 1) / 2) & (RING - 1);
        int32_t acc[2], y[2];
        fir2(m->ring[0] + b, m->hq, acc);
        for (int c = 0; c < 2; c++)             /* Q30 -> Q16, Pegel: |y| < 2^19 */
            y[c] = ((acc[c] >> 14) * GAIN_Q12) >> 12;
        uint32_t al = y[0] < 0 ? -y[0] : y[0], ar = y[1] < 0 ? -y[1] : y[1], pk = (al > ar ? al : ar) << 4;
        if (pk > m->env)                        /* Hüllkurve: sofort hoch, langsam (aufgerundet) zurück */
            m->env = pk;
        else
            m->env -= ((m->env - pk) * REL_Q16 + 65535) >> 16;
        uint32_t e = m->env >> 4;               /* Q16, >= |y| */
        int32_t g = e > LIM_Q16 ? (int32_t)(LIM_Q31 / e) : 0;   /* Q15; 0 = kein Begrenzen */
        for (int c = 0; c < 2; c++) {
            int32_t x = g ? (y[c] * g) >> 15 : y[c];
            if (x > 65536) x = 65536;
            if (x < -65536) x = -65536;
            int32_t q = (x * 127 + dither(m) + 32768) >> 16;
            if (q > 127) q = 127;
            if (q < -128) q = -128;
            (c ? m->br : m->bl)[i % BLOCK] = (int8_t)q;
        }
        m->done++;
        if (m->done % BLOCK == 0)
            flush_block(m, BLOCK);
    }
}

int mus_feed(MusConv *m, const uint8_t *pcm, size_t pairs)
{
    for (size_t p = 0; p < pairs; p++) {
        if (m->have >= m->nin)
            break;
        put(m, m->have, (int16_t)(pcm[4 * p] | pcm[4 * p + 1] << 8), (int16_t)(pcm[4 * p + 2] | pcm[4 * p + 3] << 8));
        m->have++;
        if ((m->have & 63) == 0)                /* Ring fasst 256: rechtzeitig verbrauchen */
            produce(m, 0);
    }
    produce(m, 0);
    return m->err;
}

int mus_end(MusConv *m)
{
    for (uint32_t j = m->have; j < m->have + TAPS; j++)   /* fehlende/folgende Werte = Stille */
        put(m, j, 0, 0);
    produce(m, 1);
    if (m->done % BLOCK)
        flush_block(m, m->done % BLOCK);
    int e = m->err;
    free(m);
    return e;
}

void mus_abort(MusConv *m)
{
    free(m);
}
