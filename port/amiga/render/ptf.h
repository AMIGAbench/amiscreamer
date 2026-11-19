/*
 * ptf.h - the painter's quick face loop (main.c draw_object_; the C reference pt_faces_c in main.c,
 * the assembler pt_faces_68k in pt_68k.s: the offsets below are the assembler's).
 */
#ifndef PTF_H
#define PTF_H
#include <stdint.h>

enum { PTF_VALID = 1, PTF_SEE = 2, PTF_FLAT = 4, PTF_NORMAL = 8, PTF_CORNERS = 16, PTF_HARD = 32, PTF_INBLK = 64, PTF_MIRROR = 128 };

/* one face, 24 bytes */
typedef struct {
    int16_t  v[4];      /*  0 its corners (a triangle's last twice) */
    int32_t  D;         /*  8 normal . first corner (whole numbers, 32 bits round) */
    int16_t  n[3];      /* 12 the normal (4096 = 1) */
    uint8_t  nc;        /* 18 corners */
    uint8_t  fl;        /* 19 PTF_* */
    uint16_t mi;        /* 20 material */
    uint8_t  colour;    /* 22 a flat face's colour */
    uint8_t  block;     /* 23 */
} pt_frec;

/* a material's texture choice for the phases in force, 16 bytes */
typedef struct {
    const uint8_t *tex; /*  0 */
    int32_t  su8, sv8;  /*  4  8 */
    uint32_t stamp : 24;/* 12 (bits 31..8) */
    uint32_t kind  : 8; /* 15 */
} pt_mt;

#define PTP_SIZE 136    /* the painter's polygon: tex 0, n 4, kind 5, color 6, corners 8 (x y u v, 16 each) */

typedef struct {
    const int16_t  *ford;   /*  0 the faces in painting order */
    int32_t         nford;  /*  4 */
    const pt_frec  *rec;    /*  8 */
    const uint32_t *blk_at; /* 12 the blocks' stamps */
    uint32_t        stamp;  /* 16 this object's */
    int32_t         see;    /* 20 the pass: 0 or PTF_SEE */
    int32_t         cull;   /* 24 */
    int32_t         E[3];   /* 28 the eye in the object's frame */
    const uint8_t  *out;    /* 40 the corners' outcodes */
    const int32_t  *ix;     /* 44 */
    const int32_t  *iy;     /* 48 */
    const int16_t (*uv)[2]; /* 52 */
    const pt_mt    *mt;     /* 56 */
    uint32_t        mt_stamp;/*60 */
    void           *buf;    /* 64 the polygons */
    int32_t         npoly;  /* 68 in and out */
    int32_t         maxpoly;/* 72 */
    int32_t         count;  /* 76 added, out */
    int32_t         at;     /* 80 the first face to look at */
    /* (pt_cfaces, a car's or prop's faces: blk_at / stamp are the blocks' projections, these their turns) */
    const uint32_t *qb_at;  /* 84 the blocks' turns made (q_block_at) */
    const float    *q_eye;  /* 88 the eye in each block's frame, 3 floats a block */
    const float    *fnorm;  /* 92 the faces' normals, 3 floats */
    const float    *fvert;  /* 96 the corners, 3 floats */
    int32_t         ieye;   /* 100 q_eye is whole numbers (int32): the cull as pt_faces' (D - n.E < 0), fnorm / fvert unused */
} pt_fctx;

#endif
