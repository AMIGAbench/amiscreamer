/*
 * geo.c - the painter's corners (geo.h): the C reference, and the choice of the assembler (geo_68k.s)
 * after a test of it against this on random blocks.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "geo.h"

/* floor((n) / d) for d > 0, as divs.l and the assembler do it */
static inline int32_t geo_floordiv(int32_t n, int32_t d) { return n >= 0 ? n / d : -((-n + d - 1) / d); }

void geo_block_c(const geo_blk *g)
{
    const int16_t *l = g->v;
    for (int32_t i = 0; i < g->n; i++, l += 3) {
        const int32_t lx = l[0], ly = l[1], lz = l[2];
        const int32_t x = ((lx * g->R[0] + ly * g->R[3] + lz * g->R[6]) >> 14) + g->T[0];
        const int32_t y = ((lx * g->R[1] + ly * g->R[4] + lz * g->R[7]) >> 14) + g->T[1];
        const int32_t z = ((lx * g->R[2] + ly * g->R[5] + lz * g->R[8]) >> 14) + g->T[2];
        g->vv[3 * i] = x; g->vv[3 * i + 1] = y; g->vv[3 * i + 2] = z;
        /* THE QUICK WAY: behind the near plane only marked; else the table (rcp[z]) with the
           multiplications' overflow as the test (muls.l's V), and the sides from the picture's column and row */
        {
            unsigned q = g->far && z >= g->far ? 2u : 0u;
            if (z < 24) { g->out[i] = (uint8_t)(q | 1u); continue; }
            if ((uint32_t)z < (uint32_t)g->nrcp) {
                const int32_t t = g->rcp[z];
                const int64_t px = (int64_t)x * t, py = (int64_t)y * t;
                if (px == (int32_t)px && py == (int32_t)py) {
                    const int32_t ix = ((int32_t)((uint32_t)(int32_t)px + 0x8000u) >> 16) + g->hw;
                    const int32_t iy = ((int32_t)(0x8000u - (uint32_t)(int32_t)py) >> 16) + g->cy;
                    g->ix[i] = ix; g->iy[i] = iy;
                    q |= ix < 0 ? 8u : ix > 2 * g->hw ? 4u : 0u;
                    q |= iy < 0 ? 16u : iy > g->cy + g->cyb ? 32u : 0u;
                    g->out[i] = (uint8_t)q;
                    continue;
                }
            }
        }
        /* (else as before: the sides exactly, the table within 16384 columns / rows, or two divisions) */
        unsigned o = z < 24 ? 1u : 0u;
        if (g->far && z >= g->far) o |= 2;
        const int32_t xf = x * g->fx, zx = z * g->hw;
        if (xf > zx) o |= 4; else if (-xf > zx) o |= 8;
        const int32_t yf = y * g->fx;
        if (yf > z * g->cy) o |= 16; else if (-yf > z * g->cyb) o |= 32;
        g->out[i] = (uint8_t)o;
        if (o & 1) continue;
        /* the table (rcp[z], no division): a corner within 16384 columns / rows of the middle */
        const int32_t lim = z << 14;
        if ((uint32_t)z < (uint32_t)g->nrcp && (uint32_t)(xf < 0 ? -xf : xf) < (uint32_t)lim &&
            (uint32_t)(yf < 0 ? -yf : yf) < (uint32_t)lim) {
            const int32_t t = g->rcp[z];
            g->ix[i] = ((x * t + 0x8000) >> 16) + g->hw;
            g->iy[i] = ((0x8000 - y * t) >> 16) + g->cy;
            continue;
        }
        const int32_t d2 = z + z;
        g->ix[i] = geo_floordiv(xf + xf + z, d2) + g->hw;
        g->iy[i] = geo_floordiv(z - (yf + yf), d2) + g->cy;
    }
}

static const int32_t *geo_rcp_make(int32_t fx)
{
    static int32_t *tab, tab_fx;
    if (!tab) tab = malloc(GEO_NRCP * sizeof *tab);
    if (tab && tab_fx != fx) {
        tab[0] = 0;
        for (int32_t z = 1; z < GEO_NRCP; z++) tab[z] = (int32_t)(((uint32_t)fx * 65536u + (uint32_t)z / 2) / (uint32_t)z);
        tab_fx = fx;
    }
    return tab;
}

const int32_t *geo_rcp(int32_t fx)
{
    static int off = -1;
    if (off < 0) { const char *e = getenv("OS_GEORCP"); off = e && e[0] == '0'; }   /* 0: divided, as before */
    return off ? NULL : geo_rcp_make(fx);
}

void (*g_geo_block)(const geo_blk *g) = geo_block_c;

#if (defined(__m68k__) || defined(__mc68000__)) && !defined(GEO_C_ONLY)
void geo_block_68k(const geo_blk *g);

/* random blocks through both, every output compared */
static int geo_try(void)
{
    enum { N = 256 };
    static int16_t v[N * 3];
    static int32_t ixa[N], iya[N], vva[N * 3], ixb[N], iyb[N], vvb[N * 3];
    static uint8_t oa[N], ob[N];
    uint32_t seed = 0x6e0b10c5u;
    for (int round = 0; round < 64; round++) {
        geo_blk a, b;
        memset(&a, 0, sizeof a);
        for (int i = 0; i < N * 3; i++) { seed = seed * 1103515245u + 12345u; v[i] = (int16_t)(seed >> 16); }
        for (int i = 0; i < 9; i++) { seed = seed * 1103515245u + 12345u; a.R[i] = (int16_t)((int32_t)(seed >> 17) - 16384); }
        for (int i = 0; i < 3; i++) { seed = seed * 1103515245u + 12345u; a.T[i] = (int32_t)(seed >> 14) - 131072; }
        a.T[2] += round & 1 ? 40000 : 0;
        a.v = v; a.n = N; a.fx = 128; a.rcp = geo_rcp_make(128); a.nrcp = round & 4 ? 0 : GEO_NRCP; a.hw = 160; a.cy = 130; a.cyb = 70; a.far = round & 2 ? 43808 : 0;
        b = a;
        memset(ixa, 0, sizeof ixa); memset(iya, 0, sizeof iya); memset(ixb, 0, sizeof ixb); memset(iyb, 0, sizeof iyb);
        a.ix = ixa; a.iy = iya; a.vv = vva; a.out = oa;
        b.ix = ixb; b.iy = iyb; b.vv = vvb; b.out = ob;
        geo_block_c(&a);
        geo_block_68k(&b);
        if (memcmp(ixa, ixb, sizeof ixa) || memcmp(iya, iyb, sizeof iya) || memcmp(vva, vvb, sizeof vva) || memcmp(oa, ob, sizeof oa))
            return 0;
    }
    return 1;
}
#endif

#if defined(AMIGA) && !defined(GEO_C_ONLY)
#include "amiga.h"
static void geo_block_ccc(const geo_blk *g)
{
    AMIGA_CCC_IN(t_);
    geo_block_68k(g);
    AMIGA_CCC_OUT(t_, 1);
}
#endif

void geo_init(void)
{
#if (defined(__m68k__) || defined(__mc68000__)) && !defined(GEO_C_ONLY)
    static int tested;                 /* once a run (g_geo_block outlives the parts) */
    if (tested) return;
    tested = 1;
    const char *e = getenv("OS_GEOASM");
    if (e && e[0] == '0') { fprintf(stderr, "geo: the corners in C (OS_GEOASM=0)\n"); return; }
    extern uint32_t SDL_GetTicks(void);
    const uint32_t tt = SDL_GetTicks();
    const int ok = geo_try();
    g_geo_block = ok ? geo_block_68k : geo_block_c;
    fprintf(stderr, "geo: the corners in %s (tested in %u ms)\n", ok ? "assembler (the same as C)" : "C (the assembler DIFFERS)",
            (unsigned)(SDL_GetTicks() - tt));
#ifdef AMIGA
    if (ok && getenv("OS_CCC")) g_geo_block = geo_block_ccc;      /* (OS_CCC: the corners' cycles in slot 1) */
#endif
#endif
}
