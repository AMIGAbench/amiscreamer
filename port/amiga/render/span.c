/*
 * span.c - the Amiga's row rasteriser: the polygon's set-up, and the rows in C (see span.h).
 *
 * span_poly_c (the chains and the extra row of the original's columns) and span_row: the C reference of
 * raster_span_poly.  span_draw adds what is needed before it: the winding, and the cut to the
 * picture (corners on the screen, which the assembler needs).
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "span.h"
#ifdef AMIGA
#include "../amiga.h"
#endif

static int32_t g_span_rcp[2048];                /* [w] = 65536 / w, [1024 + w] = (65536 / w) << 16 (w >= 3) */

#if (defined(__m68k__) || defined(__mc68000__)) && !defined(SPAN_C_ONLY)
extern int32_t raster_cgrad;            /* span_68k.s: 1 = a triangle's rows with one gradient (the faster way) */
#endif

#ifdef OS_V080
/*
 * THE 68080 (the Vampire build, amiga/Makefile CPU=68080): span_68k.s assembled for the 080 fills with
 * TEX8 and, after their own tests, AMMX stores (raster_sm8: TEX rows 8 at a time, raster_sm3: KEY rows).
 * The task is made an AMMX user first (SR bit 11: VampireSupport's task switch keeps the E registers;
 * span_68k.s ammx_ctx_on), then the kernel is tried against span_poly_c on random polygons of
 * every kind; if it differs, the rows are C's.
 */
#include <exec/execbase.h>
#include <exec/resident.h>
#include <proto/exec.h>
#include <stdio.h>
extern int32_t raster_sm3, raster_sm8;
void ammx_ctx_on(void);
void (*g_span_poly)(const span_ctx *c) = span_poly_c;

/* (the tests' buffers compared and filled a long word at a time: libnix's memcmp goes byte by byte -- the tests were
   seconds of the first race's start on the V1200) */
static int same32(const void *a, const void *b, size_t n)
{
    const uint32_t *p = a, *q = b;
    for (size_t i = 0; i < n / 4; i++) if (p[i] != q[i]) return 0;
    return 1;
}
static void fill32(void *a, uint8_t v, size_t n)
{
    uint32_t *p = a; const uint32_t w = v * 0x01010101u;
    for (size_t i = 0; i < n / 4; i++) p[i] = w;
}
static int span_try(int kind, int tries)
{
    enum { P = 320, H = 240 };
    static uint8_t ta[P * H], tb[P * H], smg[65536], remap[256];
    static uint8_t tex[65536 + 16];
    uint32_t seed = 0x5eed1234u + (uint32_t)kind;
    for (int i = 0; i < 65536; i++) { seed = seed * 1103515245u + 12345u; tex[i] = (seed >> 16) % 5u < 2u ? 0 : (uint8_t)(seed >> 8); smg[i] = (uint8_t)(i * 7 + 3); }
    for (int i = 0; i < 256; i++) remap[i] = (uint8_t)(255 - i);
    for (int i = 0; i < P * H; i++) ta[i] = tb[i] = (uint8_t)(i * 13);
    for (int r = 0; r < tries; r++) {
        span_v v[4];
        const int n = 3 + (r & 1);
        /* (one in five as big as the screen, the others small at any place, over the edges too: the same paths and
           cuts for a tenth of the C reference's pixels) */
        const int big = r % 5 == 0;
        seed = seed * 1103515245u + 12345u; const int32_t cx = (int32_t)((seed >> 8) % 340u) - 10;
        seed = seed * 1103515245u + 12345u; const int32_t cy = (int32_t)((seed >> 8) % 230u) - 10;
        for (int i = 0; i < n; i++) {
            seed = seed * 1103515245u + 12345u; v[i].x = big ? (int32_t)((seed >> 8) % 340u) - 10 : cx + (int32_t)((seed >> 8) % 97u) - 48;
            seed = seed * 1103515245u + 12345u; v[i].y = big ? (int32_t)((seed >> 8) % 230u) - 10 : cy + (int32_t)((seed >> 8) % 61u) - 30;
            seed = seed * 1103515245u + 12345u; v[i].u = (int32_t)(seed >> 6) - 0x2000000;
            seed = seed * 1103515245u + 12345u; v[i].v = (int32_t)(seed >> 6) - 0x2000000;
        }
        span_target t;
        t.pitch = P; t.w = P; t.h = 200; t.smg = smg; t.remap = remap;
        t.buf = ta; g_span_poly = span_poly_c; span_draw(&t, v, n, kind, tex, 0x55);
        t.buf = tb; g_span_poly = raster_span_poly; span_draw(&t, v, n, kind, tex, 0x55);
        if (!same32(ta, tb, sizeof ta)) return 0;
    }
    return 1;
}

/* the registration at the program's start (a constructor, before main): the main task an AMMX user (SR bit 11,
   kept by VampireSupport's task switch); 1 = registered, 0 = not a 68080 or not possible */
static int g_v080_reg = -1;
static const char *g_v080_why;
__attribute__((constructor)) static void span_v080_register(void)
{
    if (!(SysBase->AttnFlags & (1u << 10))) { g_v080_reg = 0; g_v080_why = "no 68080"; return; }
    struct Library *vr = (struct Library *)OpenResource((CONST_STRPTR)"vampire.resource");
    if (vr && vr->lib_Version >= 45 && FindResident((CONST_STRPTR)"VampireSupport")) {
        Supervisor((ULONG (*)())ammx_ctx_on);
        g_v080_reg = 1;
    } else {
        g_v080_reg = 0;
        g_v080_why = "AMMX not registered (vampire.resource >= 45 / VampireSupport missing)";
    }
}

int span_ammx_on(void)                          /* (amiga_video.c's AMMX c2p: the task an AMMX user) */
{
    if (g_v080_reg < 0) span_v080_register();
    const char *e = getenv("OS_AMMX");
    return g_v080_reg == 1 && !(e && e[0] == '0');
}
static void span_v080_init(void)
{
    /* without the registration the task switch does not keep SR bit 11 (and the E registers): the kernel's 080
       instructions (E registers, TEX8, AMMX) would be a Line-A guru after the next switch -- then C's rows */
    if (g_v080_reg < 0) span_v080_register();
    if (!g_v080_reg) {
        fprintf(stderr, "span: %s -- the rows in C\n", g_v080_why);
        return;
    }
    raster_sm3 = raster_sm8 = 0;
    const char *e = getenv("OS_AMMX");
    const int ammx = !(e && e[0] == '0');
    /* (every start, like the AMMX c2p's and MOVE16's tests -- no result kept on disk) */
    const int32_t grad = raster_cgrad;
    raster_cgrad = 0;
    int ok = 1;
    extern uint32_t SDL_GetTicks(void);
    uint32_t tt = SDL_GetTicks();
    static const int kinds[] = { SPAN_TEX, SPAN_KEY, SPAN_FLAT, SPAN_SMG, SPAN_SHADOW };
    for (unsigned k = 0; k < sizeof kinds / sizeof kinds[0] && ok; k++) ok = span_try(kinds[k], 60);
    raster_cgrad = grad;
    g_span_poly = ok ? raster_span_poly : span_poly_c;
    fprintf(stderr, "span: 68080 kernel %s (tested in %u ms)\n", ok ? "on (the same as C)" : "OFF (differs from C)", (unsigned)(SDL_GetTicks() - tt));
    tt = SDL_GetTicks();
    if (!ok) return;
    /* the AMMX stores: each against the kernel without them (raster_cgrad as it will run) */
    if (!ammx) return;
    { extern void os_copy_ammx(void); os_copy_ammx(); }   /* (mem.c: os_copy 64 bits a step, after its own test) */
    fprintf(stderr, "copy: tested in %u ms\n", (unsigned)(SDL_GetTicks() - tt));
    for (int which = 0; which < 2; which++) {
        int32_t *flag = which ? &raster_sm3 : &raster_sm8;
        const int kind = which ? SPAN_KEY : SPAN_TEX;
        enum { P = 320, H = 240 };
        static uint8_t a[P * H], b[P * H], tex[65536 + 16];
        uint32_t seed = 0xabcdef1u + (uint32_t)which;
        for (int i = 0; i < 65536; i++) { seed = seed * 1103515245u + 12345u; tex[i] = (seed >> 16) % 5u < 2u ? 0 : (uint8_t)(seed >> 8); }
        int same = 1;
        tt = SDL_GetTicks();
        for (int r = 0; r < 80 && same; r++) {
            span_v v[3];
            const int big = r % 5 == 0;                        /* (as span_try's: most of them small) */
            seed = seed * 1103515245u + 12345u; const int32_t cx = (int32_t)((seed >> 8) % 320u);
            seed = seed * 1103515245u + 12345u; const int32_t cy = (int32_t)((seed >> 8) % 200u);
            for (int i = 0; i < 3; i++) {
                int32_t x, y;
                seed = seed * 1103515245u + 12345u; x = big ? (int32_t)((seed >> 8) % 320u) : cx + (int32_t)((seed >> 8) % 129u) - 64;
                seed = seed * 1103515245u + 12345u; y = big ? (int32_t)((seed >> 8) % 200u) : cy + (int32_t)((seed >> 8) % 61u) - 30;
                v[i].x = x < 0 ? 0 : x > 319 ? 319 : x; v[i].y = y < 0 ? 0 : y > 199 ? 199 : y;
                seed = seed * 1103515245u + 12345u; v[i].u = (int32_t)(seed >> 6) - 0x2000000;
                seed = seed * 1103515245u + 12345u; v[i].v = (int32_t)(seed >> 6) - 0x2000000;
            }
            span_target t;
            t.pitch = P; t.w = P; t.h = 200; t.smg = NULL; t.remap = NULL;
            fill32(a, 0x5a, sizeof a); fill32(b, 0x5a, sizeof b);
            *flag = 0; t.buf = a; span_draw(&t, v, 3, kind, tex, 0);
            *flag = 1; t.buf = b; span_draw(&t, v, 3, kind, tex, 0);
            same = same32(a, b, sizeof a);
        }
        *flag = same;
        fprintf(stderr, "span: AMMX %s rows %s (%u ms)\n", which ? "KEY (storem3)" : "TEX (store)", same ? "on" : "OFF (differ)", (unsigned)(SDL_GetTicks() - tt));
    }
}
#endif

void span_init(void)
{
#if (defined(__m68k__) || defined(__mc68000__)) && !defined(SPAN_C_ONLY)
    /* OS_SPANGRAD=0: every row's own steps, as span_poly_c (a test: the picture byte for byte the C one's) */
    const char *g = getenv("OS_SPANGRAD");
    if (g) raster_cgrad = atoi(g) != 0;
#endif
    for (int i = 1; i < 1024; i++) {
        g_span_rcp[i] = 65536 / i;
        g_span_rcp[1024 + i] = i >= 3 ? (int32_t)((uint32_t)(65536 / i) << 16) : 0;
    }
#ifdef OS_V080
    static int v080_tested;            /* once a run: what it decides lives outside the parts' statics (each part's
                                          tests compared 35 MB byte by byte: a second or two a race start) */
    if (!v080_tested) {
        v080_tested = 1;
#ifdef PMKON
        extern long raster_zuv;        /* (the measuring build's OS_ZUV: the tests with the real texture steps) */
        const long zuv = raster_zuv; raster_zuv = 0;
        span_v080_init();
        raster_zuv = zuv;
#else
        span_v080_init();
#endif
    }
#endif
}

static inline int32_t span_rcp(int32_t w) { return w >= 1024 ? 65536 / w : g_span_rcp[w]; }

/* (a * b) >> 16, b in 0..65536, without a 64-bit product */
static inline int32_t mulsh16(int32_t a, int32_t b)
{
    const int32_t hi = a >> 16;
    const uint32_t lo = (uint32_t)a & 0xffffu;
    return (int32_t)((uint32_t)(hi * b) + ((lo * (uint32_t)b) >> 16));
}

static inline uint8_t texel(const uint8_t *tp, int32_t u, int32_t v)
{
    return tp[((uint32_t)v >> 16 & 255u) << 8 | ((uint32_t)u >> 16 & 255u)];
}

/* one row: pixels xl..xr (both drawn), u / v at the left end, steps du / dv */
long g_span_px, g_span_uniq, g_span_see;
uint16_t *g_span_seen;          /* (OS_PTSTAT: 1024 a row, the picture's stamp where drawn) */
unsigned g_span_stamp;
static void span_row(const span_ctx *c, int32_t y, int32_t xl, int32_t xr, int32_t u, int32_t v, int32_t du, int32_t dv)
{
    if (y < 0 || y >= c->vrows) return;
    if (xl < 0) { u += du * -xl; v += dv * -xl; xl = 0; }
    if (xr > c->xmax) xr = c->xmax;
    if (c->kind == SPAN_SMG || c->kind == SPAN_SHADOW) xr--;       /* see-through: half open, a shared edge once */
    if (xl > xr) return;
    g_span_px += xr - xl + 1;                   /* (OS_PTSTAT: pixels written, the C rows only) */
    if (g_span_seen) {                          /* (... and how many different ones: the overdraw) */
        uint16_t *s_ = g_span_seen + y * 1024 + xl;
        for (int32_t x = xl; x <= xr; x++, s_++) if (*s_ != g_span_stamp) { *s_ = (uint16_t)g_span_stamp; g_span_uniq++; }
        if (c->kind == SPAN_KEY || c->kind == SPAN_SMG || c->kind == SPAN_SHADOW) g_span_see += xr - xl + 1;
    }
    uint8_t *q = c->base + y * c->pitch + xl;
    switch (c->kind) {
    case SPAN_TEX:
        for (int32_t x = xl; x <= xr; x++, u += du, v += dv) *q++ = texel(c->tp, u, v);
        break;
    case SPAN_KEY:
        for (int32_t x = xl; x <= xr; x++, u += du, v += dv, q++) { const uint8_t k = texel(c->tp, u, v); if (k) *q = k; }
        break;
    case SPAN_SMG:
        for (int32_t x = xl; x <= xr; x++, u += du, v += dv, q++) {
            const uint32_t idx = ((uint32_t)texel(c->tp, u, v) << 8 | *q) & 0xffffu;
            *q = idx < 16384u ? c->smg[idx] : c->ramk[idx];
        }
        break;
    case SPAN_FLAT:
        memset(q, c->color, (size_t)(xr - xl + 1));
        break;
    case SPAN_SHADOW:
        for (int32_t x = xl; x <= xr; x++, q++) *q = c->remap[*q];
        break;
    default:
        break;
    }
}

typedef struct { int32_t x, u, v, dx, du, dv; } edge;

static void edge_set(edge *e, const span_v *a, const span_v *b)
{
    const int32_t r = span_rcp(b->y - a->y);
    e->x = a->x << 16; e->u = a->u; e->v = a->v;
    e->dx = (b->x - a->x) * r;
    e->du = mulsh16(b->u - a->u, r);
    e->dv = mulsh16(b->v - a->v, r);
}

/* rows ytop .. ybot-1; the left chain backwards, the right forwards from the top corner */
void span_poly_c(const span_ctx *c)
{
    const span_v *P = c->P;
    const int np = c->np;
    int top = 0, li, ri, guard = 4 * np;
    int32_t ybot = P[0].y, y, lend, rend;
    edge L, R;
    for (int i = 1; i < np; i++) {
        if (P[i].y < P[top].y) top = i;
        if (P[i].y > ybot) ybot = P[i].y;
    }
    li = ri = top;
    y = lend = rend = P[top].y;
    memset(&L, 0, sizeof L);
    memset(&R, 0, sizeof R);
    for (; y < ybot; y++) {
        while (lend <= y && guard-- > 0) {
            const int nx = li == 0 ? np - 1 : li - 1;
            if (P[nx].y > P[li].y) { edge_set(&L, &P[li], &P[nx]); lend = P[nx].y; }
            li = nx;
        }
        while (rend <= y && guard-- > 0) {
            const int nx = ri + 1 == np ? 0 : ri + 1;
            if (P[nx].y > P[ri].y) { edge_set(&R, &P[ri], &P[nx]); rend = P[nx].y; }
            ri = nx;
        }
        if (guard <= 0) return;
        const edge *a = &L, *b = &R;
        if (L.x > R.x) { a = &R; b = &L; }
        const int32_t xl = a->x >> 16, xr = b->x >> 16, w = xr - xl;
        const int32_t du = w > 0 ? mulsh16(b->u - a->u, span_rcp(w)) : 0;
        const int32_t dv = w > 0 ? mulsh16(b->v - a->v, span_rcp(w)) : 0;
        span_row(c, y, xl, xr, a->u, a->v, du, dv);
        L.x += L.dx; L.u += L.du; L.v += L.dv;
        R.x += R.dx; R.u += R.du; R.v += R.dv;
    }
}

/* ---- the cut to the picture: x in 0 .. w-1, y in 0 .. h (Sutherland-Hodgman, u / v along) ---- */
static int clip_side(const span_v *in, int n, span_v *out, int axis, int32_t lim, int keep_below)
{
    int m = 0;
    for (int i = 0; i < n; i++) {
        const span_v *p = &in[i], *q = &in[i + 1 == n ? 0 : i + 1];
        const int32_t pv = axis ? p->y : p->x, qv = axis ? q->y : q->x;
        const int pin = keep_below ? pv <= lim : pv >= lim, qin = keep_below ? qv <= lim : qv >= lim;
        if (pin) out[m++] = *p;
        if (pin != qin) {
            /* the crossing, worked out from the corner that is inside (the same point either way round) */
            const span_v *a = pin ? p : q, *b = pin ? q : p;
            const int32_t av = axis ? a->y : a->x, bv = axis ? b->y : b->x, d = bv - av;
            span_v *o = &out[m++];
            const int32_t t0 = lim - av;
            /* (no 64-bit sums: a 68060 has no 64-bit multiply or divide, libgcc's are slow.  The corners
               are whole pixels within +-32767, so the other coordinate fits 32 bits; u, v (16.16 that may
               use all 32 bits) by one float division) */
            o->x = axis ? a->x + (b->x - a->x) * t0 / d : lim;
            o->y = axis ? lim : a->y + (b->y - a->y) * t0 / d;
            const float t = (float)t0 / (float)d;
            o->u = a->u + (int32_t)((float)(b->u - a->u) * t);
            o->v = a->v + (int32_t)((float)(b->v - a->v) * t);
        }
    }
    return m;
}

#define MAXV 8

void span_draw(const span_target *t, const span_v *V0, int n, int kind, const uint8_t *tex, int color)
{
    span_v A[MAXV * 2 + 8], B[MAXV * 2 + 8];
    if (n < 3 || n > MAXV) return;
    /* the winding the chains expect (the original's: area > 0); the caller has dropped the faces
       turned away already, so the other winding is turned round, not dropped */
    int32_t area = 0, minx = V0[0].x, maxx = V0[0].x, miny = V0[0].y, maxy = V0[0].y;
    for (int i = 0; i < n; i++) {
        const span_v *a = &V0[i], *b = &V0[i + 1 == n ? 0 : i + 1];
        area += a->x * b->y - b->x * a->y;
        if (a->x < minx) minx = a->x;
        if (a->x > maxx) maxx = a->x;
        if (a->y < miny) miny = a->y;
        if (a->y > maxy) maxy = a->y;
    }
    if (area == 0 || maxx < 0 || minx >= t->w || maxy < 0 || miny > t->h || minx == maxx) return;
    for (int i = 0; i < n; i++) A[i] = area > 0 ? V0[i] : V0[n - 1 - i];
    /* corners off the picture: cut (the assembler wants them on it) */
    if (minx < 0 || maxx >= t->w || miny < 0 || maxy > t->h) {
        n = clip_side(A, n, B, 0, 0, 0);
        if (n >= 3) n = clip_side(B, n, A, 0, t->w - 1, 1);
        if (n >= 3) n = clip_side(A, n, B, 1, 0, 0);
        if (n >= 3) n = clip_side(B, n, A, 1, t->h, 1);
        if (n < 3) return;
        minx = maxx = A[0].x;
        for (int i = 1; i < n; i++) { if (A[i].x < minx) minx = A[i].x; if (A[i].x > maxx) maxx = A[i].x; }
        if (minx == maxx) return;
    }
    /* the chains: from the corner with the least x (then least y), the upper
       chain A while x does not fall; then the rest, and for the kinds the original draws a pixel
       longer at the bottom of each column, the lower chain one row lower */
    span_v P[MAXV * 2 + 8];
    int np = 0, m = 0, k;
    for (int i = 1; i < n; i++)
        if (A[i].x < A[m].x || (A[i].x == A[m].x && A[i].y <= A[m].y)) m = i;
    const int ext = (kind == SPAN_TEX || kind == SPAN_KEY || kind == SPAN_FLAT) ? 1 : 0;
    k = m;
    P[np++] = A[k];
    for (int i = 1; i < n; i++) {
        const int nk = k + 1 == n ? 0 : k + 1;
        if (nk == m || A[nk].x < A[k].x) break;
        k = nk;
        P[np++] = A[k];
    }
    if (ext) {
        int j = k;
        for (int i = 0; i <= n; i++) {
            P[np] = A[j]; P[np].y += ext; np++;
            if (j == m) break;
            j = j + 1 == n ? 0 : j + 1;
        }
    } else
        for (int j = k + 1 == n ? 0 : k + 1; j != m; j = j + 1 == n ? 0 : j + 1) P[np++] = A[j];
    span_ctx c;
    c.P = P; c.np = np; c.kind = kind; c.tp = tex;
    c.base = t->buf; c.pitch = t->pitch; c.xmax = t->w - 1; c.vrows = t->h;
    c.rcp = g_span_rcp; c.color = color;
    c.smg = t->smg; c.remap = t->remap; c.ramk = t->smg; c.cov = NULL;
#ifdef AMIGA
    AMIGA_CCC_IN(tk_);
    SPAN_POLY(&c);
    AMIGA_CCC_OUT(tk_, 6);                      /* (OS_CCC: the rows themselves) */
#else
    SPAN_POLY(&c);
#endif
}

const int32_t *span_rcp_table(void) { return g_span_rcp; }

/* the list in vasm only where the vasm rows are the ones in force (the 68080's build: after its test) */
int span_list_ok(void)
{
#if (defined(__m68k__) || defined(__mc68000__)) && !defined(SPAN_C_ONLY)
#ifdef OS_V080
    return g_span_poly == raster_span_poly;
#else
    return 1;
#endif
#else
    return 0;
#endif
}
#if !((defined(__m68k__) || defined(__mc68000__)) && !defined(SPAN_C_ONLY))
void pt_draw_list(const pt_lctx *c) { (void)c; }      /* (never called: span_list_ok() is 0 here) */
#endif
