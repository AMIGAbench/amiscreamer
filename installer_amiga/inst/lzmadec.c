/* LZMA1-Decoder (eigene Umsetzung nach der LZMA-Beschreibung von Igor Pavlov) für den Kopf von Inno-Setup-Installern
 * (GOG, inst_gog.c). Ganzer Strom in einen Speicherbereich; kein Streaming nötig (Kopf < 1 MB). */
#include "lzmadec.h"
#include <stdlib.h>
#include <string.h>

typedef uint16_t Prob;
enum { BITS = 11, ONE = 1 << BITS, MOVE = 5, NSTATES = 12, POSB_MAX = 4 };

typedef struct {
    const uint8_t *in, *end;
    uint32_t range, code;
    int over;                                   /* Eingabe zu Ende gelesen */
} Rc;

static uint8_t rc_byte(Rc *r)
{
    if (r->in < r->end)
        return *r->in++;
    r->over++;
    return 0;
}
static void rc_norm(Rc *r)
{
    if (r->range < (1u << 24)) {
        r->range <<= 8;
        r->code = r->code << 8 | rc_byte(r);
    }
}
static int rc_bit(Rc *r, Prob *p)
{
    uint32_t bound = (r->range >> BITS) * *p;
    int b;
    if (r->code < bound) {
        r->range = bound;
        *p += (ONE - *p) >> MOVE;
        b = 0;
    } else {
        r->range -= bound;
        r->code -= bound;
        *p -= *p >> MOVE;
        b = 1;
    }
    rc_norm(r);
    return b;
}
static uint32_t rc_direct(Rc *r, int n)
{
    uint32_t v = 0;
    while (n--) {
        r->range >>= 1;
        uint32_t b = r->code >= r->range;
        if (b)
            r->code -= r->range;
        v = v << 1 | b;
        rc_norm(r);
    }
    return v;
}
static uint32_t tree(Rc *r, Prob *p, int n)
{
    uint32_t m = 1;
    for (int i = 0; i < n; i++)
        m = m << 1 | (uint32_t)rc_bit(r, &p[m]);
    return m - (1u << n);
}
static uint32_t tree_rev(Rc *r, Prob *p, int n)
{
    uint32_t m = 1, s = 0;
    for (int i = 0; i < n; i++) {
        uint32_t b = (uint32_t)rc_bit(r, &p[m]);
        m = m << 1 | b;
        s |= b << i;
    }
    return s;
}

typedef struct {
    Prob choice, choice2, low[1 << POSB_MAX][8], mid[1 << POSB_MAX][8], high[256];
} Len;
static uint32_t len_dec(Rc *r, Len *l, uint32_t ps)
{
    if (!rc_bit(r, &l->choice))
        return tree(r, l->low[ps], 3);
    if (!rc_bit(r, &l->choice2))
        return 8 + tree(r, l->mid[ps], 3);
    return 16 + tree(r, l->high, 8);
}

typedef struct {
    Prob is_match[NSTATES][1 << POSB_MAX], is_rep[NSTATES], rep_g0[NSTATES], rep_g1[NSTATES], rep_g2[NSTATES];
    Prob rep0_long[NSTATES][1 << POSB_MAX], pos_slot[4][64], spec_pos[115], align[16];
    Len len, rep_len;
} Model;

int lzma_decode(const uint8_t *props, const uint8_t *in, size_t inlen, uint8_t **out, size_t *outlen)
{
    unsigned d = props[0];
    if (d >= 9 * 5 * 5)
        return -1;
    unsigned lc = d % 9, lp = d / 9 % 5, pb = d / 45;
    Model *m = malloc(sizeof *m);
    size_t nlit = (size_t)0x300 << (lc + lp);
    Prob *lit = malloc(nlit * sizeof *lit);
    size_t cap = inlen * 4 + 4096, n = 0;
    uint8_t *o = malloc(cap);
    if (!m || !lit || !o) {
        free(m);
        free(lit);
        free(o);
        return -2;
    }
    Prob *pm = (Prob *)m;
    for (size_t i = 0; i < sizeof *m / sizeof(Prob); i++)
        pm[i] = ONE / 2;
    for (size_t i = 0; i < nlit; i++)
        lit[i] = ONE / 2;
    Rc r = {in, in + inlen, 0xffffffffu, 0, 0};
    for (int i = 0; i < 5; i++)
        r.code = r.code << 8 | rc_byte(&r);
    uint32_t rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0, state = 0;
    uint32_t pbm = (1u << pb) - 1, lpm = (1u << lp) - 1;
    int rc = 0;
    for (;;) {
        if (r.over > 4)                         /* Strom ohne Endmarke: Eingabe verbraucht */
            break;
        if (n + 300 > cap) {
            cap *= 2;
            uint8_t *t = realloc(o, cap);
            if (!t) {
                rc = -2;
                break;
            }
            o = t;
        }
        uint32_t ps = (uint32_t)n & pbm;
        if (!rc_bit(&r, &m->is_match[state][ps])) {
            uint8_t prev = n ? o[n - 1] : 0;
            Prob *p = lit + 0x300 * ((((uint32_t)n & lpm) << lc) + (prev >> (8 - lc)));
            uint32_t s = 1;
            if (state >= 7) {
                uint32_t mb = o[n - rep0 - 1];
                do {
                    uint32_t bit = mb >> 7 & 1;
                    mb <<= 1;
                    uint32_t b = (uint32_t)rc_bit(&r, &p[0x100 + (bit << 8) + s]);
                    s = s << 1 | b;
                    if (b != bit)
                        break;
                } while (s < 0x100);
            }
            while (s < 0x100)
                s = s << 1 | (uint32_t)rc_bit(&r, &p[s]);
            o[n++] = (uint8_t)s;
            state = state < 4 ? 0 : state < 10 ? state - 3 : state - 6;
            continue;
        }
        uint32_t len;
        if (rc_bit(&r, &m->is_rep[state])) {
            if (!n) {
                rc = -3;
                break;
            }
            if (!rc_bit(&r, &m->rep_g0[state])) {
                if (!rc_bit(&r, &m->rep0_long[state][ps])) {   /* ein Byte von rep0 */
                    state = state < 7 ? 9 : 11;
                    o[n] = o[n - rep0 - 1];
                    n++;
                    continue;
                }
            } else {
                uint32_t dist;
                if (!rc_bit(&r, &m->rep_g1[state]))
                    dist = rep1;
                else {
                    if (!rc_bit(&r, &m->rep_g2[state]))
                        dist = rep2;
                    else {
                        dist = rep3;
                        rep3 = rep2;
                    }
                    rep2 = rep1;
                }
                rep1 = rep0;
                rep0 = dist;
            }
            len = len_dec(&r, &m->rep_len, ps);
            state = state < 7 ? 8 : 11;
        } else {
            rep3 = rep2;
            rep2 = rep1;
            rep1 = rep0;
            len = len_dec(&r, &m->len, ps);
            state = state < 7 ? 7 : 10;
            uint32_t slot = tree(&r, m->pos_slot[len < 4 ? len : 3], 6), dist;
            if (slot < 4)
                dist = slot;
            else {
                int nd = (int)(slot >> 1) - 1;
                dist = (2 | (slot & 1)) << nd;
                if (slot < 14)
                    dist += tree_rev(&r, m->spec_pos + dist - slot, nd);
                else {
                    dist += rc_direct(&r, nd - 4) << 4;
                    dist += tree_rev(&r, m->align, 4);
                }
            }
            if (dist == 0xffffffffu)            /* Endmarke */
                break;
            rep0 = dist;
        }
        len += 2;
        if (rep0 >= n) {
            rc = -3;
            break;
        }
        if (n + len > cap) {
            cap = (n + len) * 2;
            uint8_t *t = realloc(o, cap);
            if (!t) {
                rc = -2;
                break;
            }
            o = t;
        }
        for (uint32_t i = 0; i < len; i++, n++)
            o[n] = o[n - rep0 - 1];
    }
    free(m);
    free(lit);
    if (rc) {
        free(o);
        return rc;
    }
    *out = o;
    *outlen = n;
    return 0;
}
