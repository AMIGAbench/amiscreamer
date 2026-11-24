/*
 * span.h - THE AMIGA'S ROW RASTERISER (port/amiga/render).
 *
 * The original's way of filling a polygon (span.c / span_68k.s raster_span_poly):
 * no depth buffer -- polygons are painted in the order they come (far to near: the
 * caller's business) -- whole-pixel corners, texture coordinates straight along each
 * row (affine), 16.16 fixed point, the steps from a table of reciprocals (no division).
 *
 * On the Amiga the rows are filled by the assembler (span_68k.s, the 68060
 * form); elsewhere by span.c's C, the same arithmetic (tools/qemu_test.sh compares them).
 */
#ifndef OS_SPAN_H
#define OS_SPAN_H

#include <stdint.h>

/* a corner: x, y whole pixels; u, v texels 16.16 */
typedef struct { int32_t x, y, u, v; } span_v;

/* what the assembler reads (span_68k.s SpanCtx: offsets 0..52, do not reorder) */
typedef struct {
    const span_v *P;
    int32_t np, kind;               /* kind: 0 TEX/ENV, 1 KEY, 2 FLAT, 3 none (a test), 4 SMG, 5 shadow */
    const uint8_t *tp;              /* the texture's frame, 256 bytes a row, 64 KB readable from here */
    uint8_t *base;                  /* the picture's (0, 0) */
    int32_t pitch, xmax, vrows;
    const int32_t *rcp;             /* [w] = 65536 / w, [1024 + w] = (65536 / w) << 16 */
    int32_t color;                  /* FLAT */
    const uint8_t *smg, *remap, *ramk;
    uint8_t *cov;                   /* (a coverage test: NULL) */
} span_ctx;

enum { SPAN_TEX = 0, SPAN_KEY = 1, SPAN_FLAT = 2, SPAN_SMG = 4, SPAN_SHADOW = 5 };

typedef struct {
    uint8_t *buf;                   /* the picture, `pitch` bytes a row */
    int32_t pitch, w, h;            /* rows 0..h-1 are drawn */
    const uint8_t *smg;             /* 256 rows of 256 (rows 64.. as row 63): the see-through table */
    const uint8_t *remap;           /* 256: the shadow's darkening */
} span_target;

void span_init(void);
/* one polygon of n corners (3..8), in either winding; u, v ignored for FLAT / shadow */
void span_draw(const span_target *t, const span_v *V, int n, int kind, const uint8_t *tex, int color);

/* THE PAINTER'S LIST in vasm (span_68k.s pt_draw_list): every polygon of the sorted objects straight into the
   row engine; span_list_ok() says whether it may be used (the assembler's rows are the ones in force) */
typedef struct {
    const void *objs;               /*  0 pt_obj[]: first, count, key, order */
    int32_t nobj;                   /*  4 */
    const void *polys;              /*  8 pt_poly[] (136 bytes each) */
    const span_target *t;           /* 12 */
    void (*clip)(const span_target *, const span_v *, int, int, const uint8_t *, int);  /* 16 span_draw */
    uint8_t *base;                  /* 20 */
    int32_t pitch, w, h;            /* 24 28 32 */
    const int32_t *rcp;             /* 36 */
    const uint8_t *smg, *remap, *ramk;   /* 40 44 48 */
} pt_lctx;
int span_list_ok(void);
const int32_t *span_rcp_table(void);
void pt_draw_list(const pt_lctx *c);

/* the row loop: span_68k.s on the Amiga, span_poly_c elsewhere */
void span_poly_c(const span_ctx *c);
#if (defined(__m68k__) || defined(__mc68000__)) && !defined(SPAN_C_ONLY)
void raster_span_poly(const span_ctx *c);      /* (arguments on the stack: the Amiga gcc's default) */
#ifdef OS_V080
/* the 68080's build: the kernel with TEX8 / AMMX, taken only after its test on the machine (span_init) */
extern void (*g_span_poly)(const span_ctx *c);
#define SPAN_POLY g_span_poly
#else
#define SPAN_POLY raster_span_poly
#endif
#else
#define SPAN_POLY span_poly_c
#endif

#endif
