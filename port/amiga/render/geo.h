/*
 * geo.h - THE PAINTER'S CORNERS: a block's corners turned, shifted and projected, all at once, in
 * whole numbers (OpenScreamer's lens: middle of the picture + x * f / z, rounded).  geo_block_c is the
 * reference; geo_68k.s the same in assembler (the 68k builds), taken after its test on the machine (geo_init).  main.c's painter calls g_geo_block.
 */
#ifndef OS_GEO_H
#define OS_GEO_H

#include <stdint.h>

/* the block: what the assembler reads (offsets in geo_68k.s, do not reorder) */
typedef struct {
    const int16_t *v;       /*  0  the corners, x y z (int16) */
    int32_t n;              /*  4  how many */
    int32_t *ix, *iy;       /*  8 12  out: the picture's column and row (only where out & 1 is 0) */
    uint8_t *out;           /* 16  out: 1 nearer than NEAR (24), 2 beyond far, 4 8 right / left of the picture,
                                   16 32 above / below it */
    int32_t *vv;            /* 20  out: x y z in view space, three a corner */
    int16_t R[9];           /* 24  the turn, 2.14: x' = (lx R0 + ly R3 + lz R6) >> 14 + T0, y' with R1 R4 R7, z' R2 R5 R8 */
    int16_t pad;            /* 42 */
    int32_t T[3];           /* 44  the shift */
    int32_t fx, hw, cy, cyb, far;   /* 56..  lens, half the width, the eye line, rows below it, far plane (0: none) */
    const int32_t *rcp;     /* 76  the lens's table: rcp[z] = (fx * 65536 + z / 2) / z */
    int32_t nrcp;           /* 80  its length: a corner deeper, or far off to one side, is divided as before */
} geo_blk;

void geo_block_c(const geo_blk *g);
const int32_t *geo_rcp(int32_t fx);     /* the table for this lens (made once, again when the lens changes) */
enum { GEO_NRCP = 65536 };
void geo_init(void);
extern void (*g_geo_block)(const geo_blk *g);

#endif
