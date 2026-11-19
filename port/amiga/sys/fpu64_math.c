/* (OpenScreamer Amiga: os_math.c wraps it.)
 * Transzendente Funktionen des 64-Bit-FPU-Modells: sin, cos, tan, atan, atan2,
 * exp2, log2 in portablem C – nur IEEE-double-Grundrechenarten und Ganzzahlbefehle. Damit rechnen Host
 * (SSE), FS-UAE (FPU in double) und Vampire/68080 (FPU in double) Bit für Bit gleich; die FPU-Befehle
 * fsin/fcos/... liefern auf jeder dieser Plattformen andere letzte Bits (68040-FPSP auf einer 64-Bit-FPU
 * sogar Unsinn für |x| > ~10, 68080-Mikrocode eigene Näherung).
 * Voraussetzung: double-Auswertung ohne FMA (Host x86-64: SSE2, -ffp-contract=off; 68080/FS-UAE: FPU in
 * double, -fexcess-precision=fast). Auf einer 80-Bit-FPU (68040/060) wäre das Ergebnis nicht gleich.
 *
 * Quelle: musl 1.2.5 src/math (fdlibm/Sun bzw. Arm optimized-routines), maschinell zusammengeführt:
 * Namen mit m64_-Präfix, double_t -> double, __rem_pio2 fest auf den FLT_EVAL_METHOD-0-Weg.
 * Lizenz: MIT (musl, Copyright © 2005-2020 Rich Felker, et al.; Arm Limited 2018) bzw. die freie
 * Sun-Lizenz von fdlibm ("Permission to use, copy, modify, and distribute this software is freely granted,
 * provided that this notice is preserved.") – Hinweise der Einzeldateien unten erhalten. */
#include <float.h>
#include <math.h>
#include <stdint.h>
#include "fpu64_math.h"

#pragma GCC diagnostic ignored "-Wmaybe-uninitialized"   /* fq in m64_rem_pio2_large: Fehlalarm (wie in musl) */

/* ---- musl src/internal/libm.h (Auszug) ---- */
#define WANT_ROUNDING 1
#define predict_false(x) __builtin_expect(x, 0)
#define asuint64(f) ((union{double _f; uint64_t _i;}){f})._i
#define asdouble(i) ((union{uint64_t _i; double _f;}){i})._f
#define EXTRACT_WORDS(hi,lo,d) do { uint64_t __u = asuint64(d); (hi) = __u >> 32; (lo) = (uint32_t)__u; } while (0)
#define GET_HIGH_WORD(hi,d) do { (hi) = asuint64(d) >> 32; } while (0)
#define SET_LOW_WORD(d,lo) do { uint64_t __u = asuint64(d); __u &= 0xffffffff00000000ull; __u |= (uint32_t)(lo); (d) = asdouble(__u); } while (0)
#define FORCE_EVAL(x) do { volatile double __x = (x); (void)__x; } while (0)
static inline double eval_as_double(double x) { return x; }
static inline double fp_barrier(double x) { volatile double y = x; return y; }
static inline void fp_force_eval(double x) { volatile double y = x; (void)y; }
static double m64_math_xflow(uint32_t sign, double y) { y = fp_barrier(sign ? -y : y) * y; return y; }
static double __math_oflow(uint32_t sign) { return m64_math_xflow(sign, 0x1p769); }
static double __math_uflow(uint32_t sign) { return m64_math_xflow(sign, 0x1p-767); }
static double __math_divzero(uint32_t sign) { return fp_barrier(sign ? -1.0 : 1.0) / 0.0; }
static double __math_invalid(double x) { return (x - x) / (x - x); }

/* ---- musl src/math/scalbn.c ---- */
static double m64_scalbn(double x, int n)
{
	union {double f; uint64_t i;} u;
	double y = x;

	if (n > 1023) {
		y *= 0x1p1023;
		n -= 1023;
		if (n > 1023) {
			y *= 0x1p1023;
			n -= 1023;
			if (n > 1023)
				n = 1023;
		}
	} else if (n < -1022) {
		y *= 0x1p-1022 * 0x1p53;
		n += 1022 - 53;
		if (n < -1022) {
			y *= 0x1p-1022 * 0x1p53;
			n += 1022 - 53;
			if (n < -1022)
				n = -1022;
		}
	}
	u.i = (uint64_t)(0x3ff+n)<<52;
	x = y * u.f;
	return x;
}

/* ---- musl src/math/exp_data.h, log2_data.h ---- */
#define EXP_TABLE_BITS 7
#define EXP_POLY_ORDER 5
#define EXP_USE_TOINT_NARROW 0
#define EXP2_POLY_ORDER 5
struct exp_data {
	double invln2N;
	double shift;
	double negln2hiN;
	double negln2loN;
	double poly[4];
	double exp2_shift;
	double exp2_poly[EXP2_POLY_ORDER];
	uint64_t tab[2*(1 << EXP_TABLE_BITS)];
};
#define LOG2_TABLE_BITS 6
#define LOG2_POLY_ORDER 7
#define LOG2_POLY1_ORDER 11
struct log2_data {
	double invln2hi;
	double invln2lo;
	double poly[LOG2_POLY_ORDER - 1];
	double poly1[LOG2_POLY1_ORDER - 1];
	struct {
		double invc, logc;
	} tab[1 << LOG2_TABLE_BITS];
	struct {
		double chi, clo;
	} tab2[1 << LOG2_TABLE_BITS];
};

/* ---- musl src/math/__rem_pio2_large.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/k_rem_pio2.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/*
 * m64_rem_pio2_large(x,y,e0,nx,prec)
 * double x[],y[]; int e0,nx,prec;
 *
 * m64_rem_pio2_large return the last three digits of N with
 *              y = x - N*pi/2
 * so that |y| < pi/2.
 *
 * The method is to compute the integer (mod 8) and fraction parts of
 * (2/pi)*x without doing the full multiplication. In general we
 * skip the part of the product that are known to be a huge integer (
 * more accurately, = 0 mod 8 ). Thus the number of operations are
 * independent of the exponent of the input.
 *
 * (2/pi) is represented by an array of 24-bit integers in ipio2[].
 *
 * Input parameters:
 *      x[]     The input value (must be positive) is broken into nx
 *              pieces of 24-bit integers in double precision format.
 *              x[i] will be the i-th 24 bit of x. The scaled exponent
 *              of x[0] is given in input parameter e0 (i.e., x[0]*2^e0
 *              match x's up to 24 bits.
 *
 *              Example of breaking a double positive z into x[0]+x[1]+x[2]:
 *                      e0 = ilogb(z)-23
 *                      z  = m64_scalbn(z,-e0)
 *              for i = 0,1,2
 *                      x[i] = __builtin_floor(z)
 *                      z    = (z-x[i])*2**24
 *
 *
 *      y[]     ouput result in an array of double precision numbers.
 *              The dimension of y[] is:
 *                      24-bit  precision       1
 *                      53-bit  precision       2
 *                      64-bit  precision       2
 *                      113-bit precision       3
 *              The actual value is the sum of them. Thus for 113-bit
 *              precison, one may have to do something like:
 *
 *              long double t,w,r_head, r_tail;
 *              t = (long double)y[2] + (long double)y[1];
 *              w = (long double)y[0];
 *              r_head = t+w;
 *              r_tail = w - (r_head - t);
 *
 *      e0      The exponent of x[0]. Must be <= 16360 or you need to
 *              expand the ipio2 table.
 *
 *      nx      dimension of x[]
 *
 *      prec    an integer indicating the precision:
 *                      0       24  bits (single)
 *                      1       53  bits (double)
 *                      2       64  bits (extended)
 *                      3       113 bits (quad)
 *
 * External function:
 *      double m64_scalbn(), __builtin_floor();
 *
 *
 * Here is the description of some local variables:
 *
 *      jk      jk+1 is the initial number of terms of ipio2[] needed
 *              in the computation. The minimum and recommended value
 *              for jk is 3,4,4,6 for single, double, extended, and quad.
 *              jk+1 must be 2 larger than you might expect so that our
 *              recomputation test works. (Up to 24 bits in the integer
 *              part (the 24 bits of it that we compute) and 23 bits in
 *              the fraction part may be lost to cancelation before we
 *              recompute.)
 *
 *      jz      local integer variable indicating the number of
 *              terms of ipio2[] used.
 *
 *      jx      nx - 1
 *
 *      jv      index for pointing to the suitable ipio2[] for the
 *              computation. In general, we want
 *                      ( 2^e0*x[0] * ipio2[jv-1]*2^(-24jv) )/8
 *              is an integer. Thus
 *                      e0-3-24*jv >= 0 or (e0-3)/24 >= jv
 *              Hence jv = max(0,(e0-3)/24).
 *
 *      jp      jp+1 is the number of terms in PIo2[] needed, jp = jk.
 *
 *      q[]     double array with integral value, representing the
 *              24-bits chunk of the product of x and 2/pi.
 *
 *      q0      the corresponding exponent of q[0]. Note that the
 *              exponent for q[i] would be q0-24*i.
 *
 *      PIo2[]  double precision array, obtained by cutting pi/2
 *              into 24 bits chunks.
 *
 *      f[]     ipio2[] in floating point
 *
 *      iq[]    integer array by breaking up q[] in 24-bits chunk.
 *
 *      fq[]    final product of x*(2/pi) in fq[0],..,fq[jk]
 *
 *      ih      integer. If >0 it indicates q[] is >= 0.5, hence
 *              it also indicates the *sign* of the result.
 *
 */
/*
 * Constants:
 * The hexadecimal values are the intended ones for the following
 * constants. The decimal values may be used, provided that the
 * compiler will convert from decimal to binary accurately enough
 * to produce the hexadecimal values shown.
 */


static const int init_jk[] = {3,4,4,6}; /* initial value for jk */

/*
 * Table of constants for 2/pi, 396 Hex digits (476 decimal) of 2/pi
 *
 *              integer array, contains the (24*i)-th to (24*i+23)-th
 *              bit of 2/pi after binary point. The corresponding
 *              floating value is
 *
 *                      ipio2[i] * 2^(-24(i+1)).
 *
 * NB: This table must have at least (e0-3)/24 + jk terms.
 *     For quad precision (e0 <= 16360, jk = 6), this is 686.
 */
static const int32_t ipio2[] = {
0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62,
0x95993C, 0x439041, 0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A,
0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C, 0xFE1DEB, 0x1CB129,
0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C, 0x7026B4, 0x5F7E41,
0x3991D6, 0x398353, 0x39F49C, 0x845F8B, 0xBDF928, 0x3B1FF8,
0x97FFDE, 0x05980F, 0xEF2F11, 0x8B5A0A, 0x6D1F6D, 0x367ECF,
0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5,
0xF17B3D, 0x0739F7, 0x8A5292, 0xEA6BFB, 0x5FB11F, 0x8D5D08,
0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3,
0x91615E, 0xE61B08, 0x659985, 0x5F14A0, 0x68408D, 0xFFD880,
0x4D7327, 0x310606, 0x1556CA, 0x73A8C9, 0x60E27B, 0xC08C6B,

#if LDBL_MAX_EXP > 1024
0x47C419, 0xC367CD, 0xDCE809, 0x2A8359, 0xC4768B, 0x961CA6,
0xDDAF44, 0xD15719, 0x053EA5, 0xFF0705, 0x3F7E33, 0xE832C2,
0xDE4F98, 0x327DBB, 0xC33D26, 0xEF6B1E, 0x5EF89F, 0x3A1F35,
0xCAF27F, 0x1D87F1, 0x21907C, 0x7C246A, 0xFA6ED5, 0x772D30,
0x433B15, 0xC614B5, 0x9D19C3, 0xC2C4AD, 0x414D2C, 0x5D000C,
0x467D86, 0x2D71E3, 0x9AC69B, 0x006233, 0x7CD2B4, 0x97A7B4,
0xD55537, 0xF63ED7, 0x1810A3, 0xFC764D, 0x2A9D64, 0xABD770,
0xF87C63, 0x57B07A, 0xE71517, 0x5649C0, 0xD9D63B, 0x3884A7,
0xCB2324, 0x778AD6, 0x23545A, 0xB91F00, 0x1B0AF1, 0xDFCE19,
0xFF319F, 0x6A1E66, 0x615799, 0x47FBAC, 0xD87F7E, 0xB76522,
0x89E832, 0x60BFE6, 0xCDC4EF, 0x09366C, 0xD43F5D, 0xD7DE16,
0xDE3B58, 0x929BDE, 0x2822D2, 0xE88628, 0x4D58E2, 0x32CAC6,
0x16E308, 0xCB7DE0, 0x50C017, 0xA71DF3, 0x5BE018, 0x34132E,
0x621283, 0x014883, 0x5B8EF5, 0x7FB0AD, 0xF2E91E, 0x434A48,
0xD36710, 0xD8DDAA, 0x425FAE, 0xCE616A, 0xA4280A, 0xB499D3,
0xF2A606, 0x7F775C, 0x83C2A3, 0x883C61, 0x78738A, 0x5A8CAF,
0xBDD76F, 0x63A62D, 0xCBBFF4, 0xEF818D, 0x67C126, 0x45CA55,
0x36D9CA, 0xD2A828, 0x8D61C2, 0x77C912, 0x142604, 0x9B4612,
0xC459C4, 0x44C5C8, 0x91B24D, 0xF31700, 0xAD43D4, 0xE54929,
0x10D5FD, 0xFCBE00, 0xCC941E, 0xEECE70, 0xF53E13, 0x80F1EC,
0xC3E7B3, 0x28F8C7, 0x940593, 0x3E71C1, 0xB3092E, 0xF3450B,
0x9C1288, 0x7B20AB, 0x9FB52E, 0xC29247, 0x2F327B, 0x6D550C,
0x90A772, 0x1FE76B, 0x96CB31, 0x4A1679, 0xE27941, 0x89DFF4,
0x9794E8, 0x84E6E2, 0x973199, 0x6BED88, 0x365F5F, 0x0EFDBB,
0xB49A48, 0x6CA467, 0x427271, 0x325D8D, 0xB8159F, 0x09E5BC,
0x25318D, 0x3974F7, 0x1C0530, 0x010C0D, 0x68084B, 0x58EE2C,
0x90AA47, 0x02E774, 0x24D6BD, 0xA67DF7, 0x72486E, 0xEF169F,
0xA6948E, 0xF691B4, 0x5153D1, 0xF20ACF, 0x339820, 0x7E4BF5,
0x6863B2, 0x5F3EDD, 0x035D40, 0x7F8985, 0x295255, 0xC06437,
0x10D86D, 0x324832, 0x754C5B, 0xD4714E, 0x6E5445, 0xC1090B,
0x69F52A, 0xD56614, 0x9D0727, 0x50045D, 0xDB3BB4, 0xC576EA,
0x17F987, 0x7D6B49, 0xBA271D, 0x296996, 0xACCCC6, 0x5414AD,
0x6AE290, 0x89D988, 0x50722C, 0xBEA404, 0x940777, 0x7030F3,
0x27FC00, 0xA871EA, 0x49C266, 0x3DE064, 0x83DD97, 0x973FA3,
0xFD9443, 0x8C860D, 0xDE4131, 0x9D3992, 0x8C70DD, 0xE7B717,
0x3BDF08, 0x2B3715, 0xA0805C, 0x93805A, 0x921110, 0xD8E80F,
0xAF806C, 0x4BFFDB, 0x0F9038, 0x761859, 0x15A562, 0xBBCB61,
0xB989C7, 0xBD4010, 0x04F2D2, 0x277549, 0xF6B6EB, 0xBB22DB,
0xAA140A, 0x2F2689, 0x768364, 0x333B09, 0x1A940E, 0xAA3A51,
0xC2A31D, 0xAEEDAF, 0x12265C, 0x4DC26D, 0x9C7A2D, 0x9756C0,
0x833F03, 0xF6F009, 0x8C402B, 0x99316D, 0x07B439, 0x15200C,
0x5BC3D8, 0xC492F5, 0x4BADC6, 0xA5CA4E, 0xCD37A7, 0x36A9E6,
0x9492AB, 0x6842DD, 0xDE6319, 0xEF8C76, 0x528B68, 0x37DBFC,
0xABA1AE, 0x3115DF, 0xA1AE00, 0xDAFB0C, 0x664D64, 0xB705ED,
0x306529, 0xBF5657, 0x3AFF47, 0xB9F96A, 0xF3BE75, 0xDF9328,
0x3080AB, 0xF68C66, 0x15CB04, 0x0622FA, 0x1DE4D9, 0xA4B33D,
0x8F1B57, 0x09CD36, 0xE9424E, 0xA4BE13, 0xB52333, 0x1AAAF0,
0xA8654F, 0xA5C1D2, 0x0F3F0B, 0xCD785B, 0x76F923, 0x048B7B,
0x721789, 0x53A6C6, 0xE26E6F, 0x00EBEF, 0x584A9B, 0xB7DAC4,
0xBA66AA, 0xCFCF76, 0x1D02D1, 0x2DF1B1, 0xC1998C, 0x77ADC3,
0xDA4886, 0xA05DF7, 0xF480C6, 0x2FF0AC, 0x9AECDD, 0xBC5C3F,
0x6DDED0, 0x1FC790, 0xB6DB2A, 0x3A25A3, 0x9AAF00, 0x9353AD,
0x0457B6, 0xB42D29, 0x7E804B, 0xA707DA, 0x0EAA76, 0xA1597B,
0x2A1216, 0x2DB7DC, 0xFDE5FA, 0xFEDB89, 0xFDBE89, 0x6C76E4,
0xFCA906, 0x70803E, 0x156E85, 0xFF87FD, 0x073E28, 0x336761,
0x86182A, 0xEABD4D, 0xAFE7B3, 0x6E6D8F, 0x396795, 0x5BBF31,
0x48D784, 0x16DF30, 0x432DC7, 0x356125, 0xCE70C9, 0xB8CB30,
0xFD6CBF, 0xA200A4, 0xE46C05, 0xA0DD5A, 0x476F21, 0xD21262,
0x845CB9, 0x496170, 0xE0566B, 0x015299, 0x375550, 0xB7D51E,
0xC4F133, 0x5F6E13, 0xE4305D, 0xA92E85, 0xC3B21D, 0x3632A1,
0xA4B708, 0xD4B1EA, 0x21F716, 0xE4698F, 0x77FF27, 0x80030C,
0x2D408D, 0xA0CD4F, 0x99A520, 0xD3A2B3, 0x0A5D2F, 0x42F9B4,
0xCBDA11, 0xD0BE7D, 0xC1DB9B, 0xBD17AB, 0x81A2CA, 0x5C6A08,
0x17552E, 0x550027, 0xF0147F, 0x8607E1, 0x640B14, 0x8D4196,
0xDEBE87, 0x2AFDDA, 0xB6256B, 0x34897B, 0xFEF305, 0x9EBFB9,
0x4F6A68, 0xA82A4A, 0x5AC44F, 0xBCF82D, 0x985AD7, 0x95C7F4,
0x8D4D0D, 0xA63A20, 0x5F57A4, 0xB13F14, 0x953880, 0x0120CC,
0x86DD71, 0xB6DEC9, 0xF560BF, 0x11654D, 0x6B0701, 0xACB08C,
0xD0C0B2, 0x485551, 0x0EFB1E, 0xC37295, 0x3B06A3, 0x3540C0,
0x7BDC06, 0xCC45E0, 0xFA294E, 0xC8CAD6, 0x41F3E8, 0xDE647C,
0xD8649B, 0x31BED9, 0xC397A4, 0xD45877, 0xC5E369, 0x13DAF0,
0x3C3ABA, 0x461846, 0x5F7555, 0xF5BDD2, 0xC6926E, 0x5D2EAC,
0xED440E, 0x423E1C, 0x87C461, 0xE9FD29, 0xF3D6E7, 0xCA7C22,
0x35916F, 0xC5E008, 0x8DD7FF, 0xE26A6E, 0xC6FDB0, 0xC10893,
0x745D7C, 0xB2AD6B, 0x9D6ECD, 0x7B723E, 0x6A11C6, 0xA9CFF7,
0xDF7329, 0xBAC9B5, 0x5100B7, 0x0DB2E2, 0x24BA74, 0x607DE5,
0x8AD874, 0x2C150D, 0x0C1881, 0x94667E, 0x162901, 0x767A9F,
0xBEFDFD, 0xEF4556, 0x367ED9, 0x13D9EC, 0xB9BA8B, 0xFC97C4,
0x27A831, 0xC36EF1, 0x36C594, 0x56A8D8, 0xB5A8B4, 0x0ECCCF,
0x2D8912, 0x34576F, 0x89562C, 0xE3CE99, 0xB920D6, 0xAA5E6B,
0x9C2A3E, 0xCC5F11, 0x4A0BFD, 0xFBF4E1, 0x6D3B8E, 0x2C86E2,
0x84D4E9, 0xA9B4FC, 0xD1EEEF, 0xC9352E, 0x61392F, 0x442138,
0xC8D91B, 0x0AFC81, 0x6A4AFB, 0xD81C2F, 0x84B453, 0x8C994E,
0xCC2254, 0xDC552A, 0xD6C6C0, 0x96190B, 0xB8701A, 0x649569,
0x605A26, 0xEE523F, 0x0F117F, 0x11B5F4, 0xF5CBFC, 0x2DBC34,
0xEEBC34, 0xCC5DE8, 0x605EDD, 0x9B8E67, 0xEF3392, 0xB817C9,
0x9B5861, 0xBC57E1, 0xC68351, 0x103ED8, 0x4871DD, 0xDD1C2D,
0xA118AF, 0x462C21, 0xD7F359, 0x987AD9, 0xC0549E, 0xFA864F,
0xFC0656, 0xAE79E5, 0x362289, 0x22AD38, 0xDC9367, 0xAAE855,
0x382682, 0x9BE7CA, 0xA40D51, 0xB13399, 0x0ED7A9, 0x480569,
0xF0B265, 0xA7887F, 0x974C88, 0x36D1F9, 0xB39221, 0x4A827B,
0x21CF98, 0xDC9F40, 0x5547DC, 0x3A74E1, 0x42EB67, 0xDF9DFE,
0x5FD45E, 0xA4677B, 0x7AACBA, 0xA2F655, 0x23882B, 0x55BA41,
0x086E59, 0x862A21, 0x834739, 0xE6E389, 0xD49EE5, 0x40FB49,
0xE956FF, 0xCA0F1C, 0x8A59C5, 0x2BFA94, 0xC5C1D3, 0xCFC50F,
0xAE5ADB, 0x86C547, 0x624385, 0x3B8621, 0x94792C, 0x876110,
0x7B4C2A, 0x1A2C80, 0x12BF43, 0x902688, 0x893C78, 0xE4C4A8,
0x7BDBE5, 0xC23AC4, 0xEAF426, 0x8A67F7, 0xBF920D, 0x2BA365,
0xB1933D, 0x0B7CBD, 0xDC51A4, 0x63DD27, 0xDDE169, 0x19949A,
0x9529A8, 0x28CE68, 0xB4ED09, 0x209F44, 0xCA984E, 0x638270,
0x237C7E, 0x32B90F, 0x8EF5A7, 0xE75614, 0x08F121, 0x2A9DB5,
0x4D7E6F, 0x5119A5, 0xABF9B5, 0xD6DF82, 0x61DD96, 0x023616,
0x9F3AC4, 0xA1A283, 0x6DED72, 0x7A8D39, 0xA9B882, 0x5C326B,
0x5B2746, 0xED3400, 0x7700D2, 0x55F4FC, 0x4D5901, 0x8071E0,
#endif
};

static const double PIo2[] = {
  1.57079625129699707031e+00, /* 0x3FF921FB, 0x40000000 */
  7.54978941586159635335e-08, /* 0x3E74442D, 0x00000000 */
  5.39030252995776476554e-15, /* 0x3CF84698, 0x80000000 */
  3.28200341580791294123e-22, /* 0x3B78CC51, 0x60000000 */
  1.27065575308067607349e-29, /* 0x39F01B83, 0x80000000 */
  1.22933308981111328932e-36, /* 0x387A2520, 0x40000000 */
  2.73370053816464559624e-44, /* 0x36E38222, 0x80000000 */
  2.16741683877804819444e-51, /* 0x3569F31D, 0x00000000 */
};

static int m64_rem_pio2_large(double *x, double *y, int e0, int nx, int prec)
{
	int32_t jz,jx,jv,jp,jk,carry,n,iq[20],i,j,k,m,q0,ih;
	double z,fw,f[20],fq[20],q[20];

	/* initialize jk*/
	jk = init_jk[prec];
	jp = jk;

	/* determine jx,jv,q0, note that 3>q0 */
	jx = nx-1;
	jv = (e0-3)/24;  if(jv<0) jv=0;
	q0 = e0-24*(jv+1);

	/* set up f[0] to f[jx+jk] where f[jx+jk] = ipio2[jv+jk] */
	j = jv-jx; m = jx+jk;
	for (i=0; i<=m; i++,j++)
		f[i] = j<0 ? 0.0 : (double)ipio2[j];

	/* compute q[0],q[1],...q[jk] */
	for (i=0; i<=jk; i++) {
		for (j=0,fw=0.0; j<=jx; j++)
			fw += x[j]*f[jx+i-j];
		q[i] = fw;
	}

	jz = jk;
recompute:
	/* distill q[] into iq[] reversingly */
	for (i=0,j=jz,z=q[jz]; j>0; i++,j--) {
		fw    = (double)(int32_t)(0x1p-24*z);
		iq[i] = (int32_t)(z - 0x1p24*fw);
		z     = q[j-1]+fw;
	}

	/* compute n */
	z  = m64_scalbn(z,q0);       /* actual value of z */
	z -= 8.0*__builtin_floor(z*0.125); /* trim off integer >= 8 */
	n  = (int32_t)z;
	z -= (double)n;
	ih = 0;
	if (q0 > 0) {  /* need iq[jz-1] to determine n */
		i  = iq[jz-1]>>(24-q0); n += i;
		iq[jz-1] -= i<<(24-q0);
		ih = iq[jz-1]>>(23-q0);
	}
	else if (q0 == 0) ih = iq[jz-1]>>23;
	else if (z >= 0.5) ih = 2;

	if (ih > 0) {  /* q > 0.5 */
		n += 1; carry = 0;
		for (i=0; i<jz; i++) {  /* compute 1-q */
			j = iq[i];
			if (carry == 0) {
				if (j != 0) {
					carry = 1;
					iq[i] = 0x1000000 - j;
				}
			} else
				iq[i] = 0xffffff - j;
		}
		if (q0 > 0) {  /* rare case: chance is 1 in 12 */
			switch(q0) {
			case 1:
				iq[jz-1] &= 0x7fffff; break;
			case 2:
				iq[jz-1] &= 0x3fffff; break;
			}
		}
		if (ih == 2) {
			z = 1.0 - z;
			if (carry != 0)
				z -= m64_scalbn(1.0,q0);
		}
	}

	/* check if recomputation is needed */
	if (z == 0.0) {
		j = 0;
		for (i=jz-1; i>=jk; i--) j |= iq[i];
		if (j == 0) {  /* need recomputation */
			for (k=1; iq[jk-k]==0; k++);  /* k = no. of terms needed */

			for (i=jz+1; i<=jz+k; i++) {  /* add q[jz+1] to q[jz+k] */
				f[jx+i] = (double)ipio2[jv+i];
				for (j=0,fw=0.0; j<=jx; j++)
					fw += x[j]*f[jx+i-j];
				q[i] = fw;
			}
			jz += k;
			goto recompute;
		}
	}

	/* chop off zero terms */
	if (z == 0.0) {
		jz -= 1;
		q0 -= 24;
		while (iq[jz] == 0) {
			jz--;
			q0 -= 24;
		}
	} else { /* break z into 24-bit if necessary */
		z = m64_scalbn(z,-q0);
		if (z >= 0x1p24) {
			fw = (double)(int32_t)(0x1p-24*z);
			iq[jz] = (int32_t)(z - 0x1p24*fw);
			jz += 1;
			q0 += 24;
			iq[jz] = (int32_t)fw;
		} else
			iq[jz] = (int32_t)z;
	}

	/* convert integer "bit" chunk to floating-point value */
	fw = m64_scalbn(1.0,q0);
	for (i=jz; i>=0; i--) {
		q[i] = fw*(double)iq[i];
		fw *= 0x1p-24;
	}

	/* compute PIo2[0,...,jp]*q[jz,...,0] */
	for(i=jz; i>=0; i--) {
		for (fw=0.0,k=0; k<=jp && k<=jz-i; k++)
			fw += PIo2[k]*q[i+k];
		fq[jz-i] = fw;
	}

	/* compress fq[] into y[] */
	switch(prec) {
	case 0:
		fw = 0.0;
		for (i=jz; i>=0; i--)
			fw += fq[i];
		y[0] = ih==0 ? fw : -fw;
		break;
	case 1:
	case 2:
		fw = 0.0;
		for (i=jz; i>=0; i--)
			fw += fq[i];
		// TODO: drop excess precision here once double is used
		fw = (double)fw;
		y[0] = ih==0 ? fw : -fw;
		fw = fq[0]-fw;
		for (i=1; i<=jz; i++)
			fw += fq[i];
		y[1] = ih==0 ? fw : -fw;
		break;
	case 3:  /* painful */
		for (i=jz; i>0; i--) {
			fw      = fq[i-1]+fq[i];
			fq[i]  += fq[i-1]-fw;
			fq[i-1] = fw;
		}
		for (i=jz; i>1; i--) {
			fw      = fq[i-1]+fq[i];
			fq[i]  += fq[i-1]-fw;
			fq[i-1] = fw;
		}
		for (fw=0.0,i=jz; i>=2; i--)
			fw += fq[i];
		if (ih==0) {
			y[0] =  fq[0]; y[1] =  fq[1]; y[2] =  fw;
		} else {
			y[0] = -fq[0]; y[1] = -fq[1]; y[2] = -fw;
		}
	}
	return n&7;
}

/* ---- musl src/math/__rem_pio2.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/e_rem_pio2.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 *
 * Optimized by Bruce D. Evans.
 */
/* m64_rem_pio2(x,y)
 *
 * return the remainder of x rem pi/2 in y[0]+y[1]
 * use m64_rem_pio2_large() for large x
 */


#if 1
#define EPS DBL_EPSILON
#elif FLT_EVAL_METHOD==2
#define EPS LDBL_EPSILON
#endif

/*
 * invpio2:  53 bits of 2/pi
 * pio2_1:   first  33 bit of pi/2
 * pio2_1t:  pi/2 - pio2_1
 * pio2_2:   second 33 bit of pi/2
 * pio2_2t:  pi/2 - (pio2_1+pio2_2)
 * pio2_3:   third  33 bit of pi/2
 * pio2_3t:  pi/2 - (pio2_1+pio2_2+pio2_3)
 */
static const double
toint   = 1.5/EPS,
rp_pio4    = 0x1.921fb54442d18p-1,
invpio2 = 6.36619772367581382433e-01, /* 0x3FE45F30, 0x6DC9C883 */
pio2_1  = 1.57079632673412561417e+00, /* 0x3FF921FB, 0x54400000 */
pio2_1t = 6.07710050650619224932e-11, /* 0x3DD0B461, 0x1A626331 */
pio2_2  = 6.07710050630396597660e-11, /* 0x3DD0B461, 0x1A600000 */
pio2_2t = 2.02226624879595063154e-21, /* 0x3BA3198A, 0x2E037073 */
pio2_3  = 2.02226624871116645580e-21, /* 0x3BA3198A, 0x2E000000 */
pio2_3t = 8.47842766036889956997e-32; /* 0x397B839A, 0x252049C1 */

/* caller must handle the case when reduction is not needed: |x| ~<= pi/4 */
static int m64_rem_pio2(double x, double *y)
{
	union {double f; uint64_t i;} u = {x};
	double z,w,t,r,fn;
	double tx[3],ty[2];
	uint32_t ix;
	int sign, n, ex, ey, i;

	sign = u.i>>63;
	ix = u.i>>32 & 0x7fffffff;
	if (ix <= 0x400f6a7a) {  /* |x| ~<= 5pi/4 */
		if ((ix & 0xfffff) == 0x921fb)  /* |x| ~= pi/2 or 2pi/2 */
			goto medium;  /* cancellation -- use medium case */
		if (ix <= 0x4002d97c) {  /* |x| ~<= 3pi/4 */
			if (!sign) {
				z = x - pio2_1;  /* one round good to 85 bits */
				y[0] = z - pio2_1t;
				y[1] = (z-y[0]) - pio2_1t;
				return 1;
			} else {
				z = x + pio2_1;
				y[0] = z + pio2_1t;
				y[1] = (z-y[0]) + pio2_1t;
				return -1;
			}
		} else {
			if (!sign) {
				z = x - 2*pio2_1;
				y[0] = z - 2*pio2_1t;
				y[1] = (z-y[0]) - 2*pio2_1t;
				return 2;
			} else {
				z = x + 2*pio2_1;
				y[0] = z + 2*pio2_1t;
				y[1] = (z-y[0]) + 2*pio2_1t;
				return -2;
			}
		}
	}
	if (ix <= 0x401c463b) {  /* |x| ~<= 9pi/4 */
		if (ix <= 0x4015fdbc) {  /* |x| ~<= 7pi/4 */
			if (ix == 0x4012d97c)  /* |x| ~= 3pi/2 */
				goto medium;
			if (!sign) {
				z = x - 3*pio2_1;
				y[0] = z - 3*pio2_1t;
				y[1] = (z-y[0]) - 3*pio2_1t;
				return 3;
			} else {
				z = x + 3*pio2_1;
				y[0] = z + 3*pio2_1t;
				y[1] = (z-y[0]) + 3*pio2_1t;
				return -3;
			}
		} else {
			if (ix == 0x401921fb)  /* |x| ~= 4pi/2 */
				goto medium;
			if (!sign) {
				z = x - 4*pio2_1;
				y[0] = z - 4*pio2_1t;
				y[1] = (z-y[0]) - 4*pio2_1t;
				return 4;
			} else {
				z = x + 4*pio2_1;
				y[0] = z + 4*pio2_1t;
				y[1] = (z-y[0]) + 4*pio2_1t;
				return -4;
			}
		}
	}
	if (ix < 0x413921fb) {  /* |x| ~< 2^20*(pi/2), medium size */
medium:
		/* rint(x/(pi/2)) */
		fn = (double)x*invpio2 + toint - toint;
		n = (int32_t)fn;
		r = x - fn*pio2_1;
		w = fn*pio2_1t;  /* 1st round, good to 85 bits */
		/* Matters with directed rounding. */
		if (predict_false(r - w < -rp_pio4)) {
			n--;
			fn--;
			r = x - fn*pio2_1;
			w = fn*pio2_1t;
		} else if (predict_false(r - w > rp_pio4)) {
			n++;
			fn++;
			r = x - fn*pio2_1;
			w = fn*pio2_1t;
		}
		y[0] = r - w;
		u.f = y[0];
		ey = u.i>>52 & 0x7ff;
		ex = ix>>20;
		if (ex - ey > 16) { /* 2nd round, good to 118 bits */
			t = r;
			w = fn*pio2_2;
			r = t - w;
			w = fn*pio2_2t - ((t-r)-w);
			y[0] = r - w;
			u.f = y[0];
			ey = u.i>>52 & 0x7ff;
			if (ex - ey > 49) {  /* 3rd round, good to 151 bits, covers all cases */
				t = r;
				w = fn*pio2_3;
				r = t - w;
				w = fn*pio2_3t - ((t-r)-w);
				y[0] = r - w;
			}
		}
		y[1] = (r - y[0]) - w;
		return n;
	}
	/*
	 * all other (large) arguments
	 */
	if (ix >= 0x7ff00000) {  /* x is inf or NaN */
		y[0] = y[1] = x - x;
		return 0;
	}
	/* set z = m64_scalbn(|x|,-ilogb(x)+23) */
	u.f = x;
	u.i &= (uint64_t)-1>>12;
	u.i |= (uint64_t)(0x3ff + 23)<<52;
	z = u.f;
	for (i=0; i < 2; i++) {
		tx[i] = (double)(int32_t)z;
		z     = (z-tx[i])*0x1p24;
	}
	tx[i] = z;
	/* skip zero terms, first term is non-zero */
	while (tx[i] == 0.0)
		i--;
	n = m64_rem_pio2_large(tx,ty,(int)(ix>>20)-(0x3ff+23),i+1,1);
	if (sign) {
		y[0] = -ty[0];
		y[1] = -ty[1];
		return -n;
	}
	y[0] = ty[0];
	y[1] = ty[1];
	return n;
}
#undef EPS

/* ---- musl src/math/__sin.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/k_sin.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* m64_ksin( x, y, iy)
 * kernel sin function on ~[-pi/4, pi/4] (except on -0), pi/4 ~ 0.7854
 * Input x is assumed to be bounded by ~pi/4 in magnitude.
 * Input y is the tail of x.
 * Input iy indicates whether y is 0. (if iy=0, y assume to be 0).
 *
 * Algorithm
 *      1. Since m64_sin(-x) = -m64_sin(x), we need only to consider positive x.
 *      2. Callers must return m64_sin(-0) = -0 without calling here since our
 *         odd polynomial is not evaluated in a way that preserves -0.
 *         Callers may do the optimization m64_sin(x) ~ x for tiny x.
 *      3. m64_sin(x) is approximated by a polynomial of degree 13 on
 *         [0,pi/4]
 *                               3            13
 *              m64_sin(x) ~ x + S1*x + ... + S6*x
 *         where
 *
 *      |m64_sin(x)         2     4     6     8     10     12  |     -58
 *      |----- - (1+S1*x +S2*x +S3*x +S4*x +S5*x  +S6*x   )| <= 2
 *      |  x                                               |
 *
 *      4. m64_sin(x+y) = m64_sin(x) + sin'(x')*y
 *                  ~ m64_sin(x) + (1-x*x/2)*y
 *         For better accuracy, let
 *                   3      2      2      2      2
 *              r = x *(S2+x *(S3+x *(S4+x *(S5+x *S6))))
 *         then                   3    2
 *              m64_sin(x) = x + (S1*x + (x *(r-y/2)+y))
 */


static const double
S1  = -1.66666666666666324348e-01, /* 0xBFC55555, 0x55555549 */
S2  =  8.33333333332248946124e-03, /* 0x3F811111, 0x1110F8A6 */
S3  = -1.98412698298579493134e-04, /* 0xBF2A01A0, 0x19C161D5 */
S4  =  2.75573137070700676789e-06, /* 0x3EC71DE3, 0x57B1FE7D */
S5  = -2.50507602534068634195e-08, /* 0xBE5AE5E6, 0x8A2B9CEB */
S6  =  1.58969099521155010221e-10; /* 0x3DE5D93A, 0x5ACFD57C */

static double m64_ksin(double x, double y, int iy)
{
	double z,r,v,w;

	z = x*x;
	w = z*z;
	r = S2 + z*(S3 + z*S4) + z*w*(S5 + z*S6);
	v = z*x;
	if (iy == 0)
		return x + v*(S1 + z*r);
	else
		return x - ((z*(0.5*y - v*r) - y) - v*S1);
}

/* ---- musl src/math/__cos.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/k_cos.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/*
 * m64_kcos( x,  y )
 * kernel cos function on [-pi/4, pi/4], pi/4 ~ 0.785398164
 * Input x is assumed to be bounded by ~pi/4 in magnitude.
 * Input y is the tail of x.
 *
 * Algorithm
 *      1. Since m64_cos(-x) = m64_cos(x), we need only to consider positive x.
 *      2. if x < 2^-27 (hx<0x3e400000 0), return 1 with inexact if x!=0.
 *      3. m64_cos(x) is approximated by a polynomial of degree 14 on
 *         [0,pi/4]
 *                                       4            14
 *              m64_cos(x) ~ 1 - x*x/2 + C1*x + ... + C6*x
 *         where the remez error is
 *
 *      |              2     4     6     8     10    12     14 |     -58
 *      |m64_cos(x)-(1-.5*x +C1*x +C2*x +C3*x +C4*x +C5*x  +C6*x  )| <= 2
 *      |                                                      |
 *
 *                     4     6     8     10    12     14
 *      4. let r = C1*x +C2*x +C3*x +C4*x +C5*x  +C6*x  , then
 *             m64_cos(x) ~ 1 - x*x/2 + r
 *         since m64_cos(x+y) ~ m64_cos(x) - m64_sin(x)*y
 *                        ~ m64_cos(x) - x*y,
 *         a correction term is necessary in m64_cos(x) and hence
 *              m64_cos(x+y) = 1 - (x*x/2 - (r - x*y))
 *         For better accuracy, rearrange to
 *              m64_cos(x+y) ~ w + (tmp + (r-x*y))
 *         where w = 1 - x*x/2 and tmp is a tiny correction term
 *         (1 - x*x/2 == w + tmp exactly in infinite precision).
 *         The exactness of w + tmp in infinite precision depends on w
 *         and tmp having the same precision as x.  If they have extra
 *         precision due to compiler bugs, then the extra precision is
 *         only good provided it is retained in all terms of the final
 *         expression for m64_cos().  Retention happens in all cases tested
 *         under FreeBSD, so don't pessimize things by forcibly clipping
 *         any extra precision in w.
 */


static const double
C1  =  4.16666666666666019037e-02, /* 0x3FA55555, 0x5555554C */
C2  = -1.38888888888741095749e-03, /* 0xBF56C16C, 0x16C15177 */
C3  =  2.48015872894767294178e-05, /* 0x3EFA01A0, 0x19CB1590 */
C4  = -2.75573143513906633035e-07, /* 0xBE927E4F, 0x809C52AD */
C5  =  2.08757232129817482790e-09, /* 0x3E21EE9E, 0xBDB4B1C4 */
C6  = -1.13596475577881948265e-11; /* 0xBDA8FAE9, 0xBE8838D4 */

static double m64_kcos(double x, double y)
{
	double hz,z,r,w;

	z  = x*x;
	w  = z*z;
	r  = z*(C1+z*(C2+z*C3)) + w*w*(C4+z*(C5+z*C6));
	hz = 0.5*z;
	w  = 1.0-hz;
	return w + (((1.0-w)-hz) + (z*r-x*y));
}

/* ---- musl src/math/__tan.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/k_tan.c */
/*
 * ====================================================
 * Copyright 2004 Sun Microsystems, Inc.  All Rights Reserved.
 *
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* m64_ktan( x, y, k )
 * kernel tan function on ~[-pi/4, pi/4] (except on -0), pi/4 ~ 0.7854
 * Input x is assumed to be bounded by ~pi/4 in magnitude.
 * Input y is the tail of x.
 * Input odd indicates whether m64_tan (if odd = 0) or -1/m64_tan (if odd = 1) is returned.
 *
 * Algorithm
 *      1. Since m64_tan(-x) = -m64_tan(x), we need only to consider positive x.
 *      2. Callers must return m64_tan(-0) = -0 without calling here since our
 *         odd polynomial is not evaluated in a way that preserves -0.
 *         Callers may do the optimization m64_tan(x) ~ x for tiny x.
 *      3. m64_tan(x) is approximated by a odd polynomial of degree 27 on
 *         [0,0.67434]
 *                               3             27
 *              m64_tan(x) ~ x + T1*x + ... + T13*x
 *         where
 *
 *              |m64_tan(x)         2     4            26   |     -59.2
 *              |----- - (1+T1*x +T2*x +.... +T13*x    )| <= 2
 *              |  x                                    |
 *
 *         Note: m64_tan(x+y) = m64_tan(x) + tan'(x)*y
 *                        ~ m64_tan(x) + (1+x*x)*y
 *         Therefore, for better accuracy in computing m64_tan(x+y), let
 *                   3      2      2       2       2
 *              r = x *(T2+x *(T3+x *(...+x *(T12+x *T13))))
 *         then
 *                                  3    2
 *              m64_tan(x+y) = x + (T1*x + (x *(r+y)+y))
 *
 *      4. For x in [0.67434,pi/4],  let y = pi/4 - x, then
 *              m64_tan(x) = m64_tan(pi/4-y) = (1-m64_tan(y))/(1+m64_tan(y))
 *                     = 1 - 2*(m64_tan(y) - (m64_tan(y)^2)/(1+m64_tan(y)))
 */


static const double T[] = {
             3.33333333333334091986e-01, /* 3FD55555, 55555563 */
             1.33333333333201242699e-01, /* 3FC11111, 1110FE7A */
             5.39682539762260521377e-02, /* 3FABA1BA, 1BB341FE */
             2.18694882948595424599e-02, /* 3F9664F4, 8406D637 */
             8.86323982359930005737e-03, /* 3F8226E3, E96E8493 */
             3.59207910759131235356e-03, /* 3F6D6D22, C9560328 */
             1.45620945432529025516e-03, /* 3F57DBC8, FEE08315 */
             5.88041240820264096874e-04, /* 3F4344D8, F2F26501 */
             2.46463134818469906812e-04, /* 3F3026F7, 1A8D1068 */
             7.81794442939557092300e-05, /* 3F147E88, A03792A6 */
             7.14072491382608190305e-05, /* 3F12B80F, 32F0A7E9 */
            -1.85586374855275456654e-05, /* BEF375CB, DB605373 */
             2.59073051863633712884e-05, /* 3EFB2A70, 74BF7AD4 */
},
pio4 =       7.85398163397448278999e-01, /* 3FE921FB, 54442D18 */
pio4lo =     3.06161699786838301793e-17; /* 3C81A626, 33145C07 */

static double m64_ktan(double x, double y, int odd)
{
	double z, r, v, w, s, a;
	double w0, a0;
	uint32_t hx;
	int big, sign;

	GET_HIGH_WORD(hx,x);
	big = (hx&0x7fffffff) >= 0x3FE59428; /* |x| >= 0.6744 */
	if (big) {
		sign = hx>>31;
		if (sign) {
			x = -x;
			y = -y;
		}
		x = (pio4 - x) + (pio4lo - y);
		y = 0.0;
	}
	z = x * x;
	w = z * z;
	/*
	 * Break x^5*(T[1]+x^2*T[2]+...) into
	 * x^5(T[1]+x^4*T[3]+...+x^20*T[11]) +
	 * x^5(x^2*(T[2]+x^4*T[4]+...+x^22*[T12]))
	 */
	r = T[1] + w*(T[3] + w*(T[5] + w*(T[7] + w*(T[9] + w*T[11]))));
	v = z*(T[2] + w*(T[4] + w*(T[6] + w*(T[8] + w*(T[10] + w*T[12])))));
	s = z * x;
	r = y + z*(s*(r + v) + y) + s*T[0];
	w = x + r;
	if (big) {
		s = 1 - 2*odd;
		v = s - 2.0 * (x + (r - w*w/(w + s)));
		return sign ? -v : v;
	}
	if (!odd)
		return w;
	/* -1.0/(x+r) has up to 2ulp error, so compute it accurately */
	w0 = w;
	SET_LOW_WORD(w0, 0);
	v = r - (w0 - x);       /* w0+v = r+x */
	a0 = a = -1.0 / w;
	SET_LOW_WORD(a0, 0);
	return a0 + a*(1.0 + a0*w0 + a0*v);
}

/* ---- musl src/math/sin.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/s_sin.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* m64_sin(x)
 * Return sine function of x.
 *
 * kernel function:
 *      m64_ksin            ... sine function on [-pi/4,pi/4]
 *      m64_kcos            ... cose function on [-pi/4,pi/4]
 *      m64_rem_pio2       ... argument reduction routine
 *
 * Method.
 *      Let S,C and T denote the sin, cos and tan respectively on
 *      [-PI/4, +PI/4]. Reduce the argument x to y1+y2 = x-k*pi/2
 *      in [-pi/4 , +pi/4], and let n = k mod 4.
 *      We have
 *
 *          n        m64_sin(x)      m64_cos(x)        m64_tan(x)
 *     ----------------------------------------------------------
 *          0          S           C             T
 *          1          C          -S            -1/T
 *          2         -S          -C             T
 *          3         -C           S            -1/T
 *     ----------------------------------------------------------
 *
 * Special cases:
 *      Let trig be any of sin, cos, or tan.
 *      trig(+-INF)  is NaN, with signals;
 *      trig(NaN)    is that NaN;
 *
 * Accuracy:
 *      TRIG(x) returns trig(x) nearly rounded
 */


static double m64_sin_(double x);
double m64_sin(double x)
{
    return m64_sin_(x);
}
static double m64_sin_(double x)
{
	double y[2];
	uint32_t ix;
	unsigned n;

	/* High word of x. */
	GET_HIGH_WORD(ix, x);
	ix &= 0x7fffffff;

	/* |x| ~< pi/4 */
	if (ix <= 0x3fe921fb) {
		if (ix < 0x3e500000) {  /* |x| < 2**-26 */
			/* raise inexact if x != 0 and underflow if subnormal*/
			FORCE_EVAL(ix < 0x00100000 ? x/0x1p120f : x+0x1p120f);
			return x;
		}
		return m64_ksin(x, 0.0, 0);
	}

	/* m64_sin(Inf or NaN) is NaN */
	if (ix >= 0x7ff00000)
		return x - x;

	/* argument reduction needed */
	n = m64_rem_pio2(x, y);
	switch (n&3) {
	case 0: return  m64_ksin(y[0], y[1], 1);
	case 1: return  m64_kcos(y[0], y[1]);
	case 2: return -m64_ksin(y[0], y[1], 1);
	default:
		return -m64_kcos(y[0], y[1]);
	}
}

/* ---- musl src/math/cos.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/s_cos.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* m64_cos(x)
 * Return cosine function of x.
 *
 * kernel function:
 *      m64_ksin           ... sine function on [-pi/4,pi/4]
 *      m64_kcos           ... cosine function on [-pi/4,pi/4]
 *      m64_rem_pio2      ... argument reduction routine
 *
 * Method.
 *      Let S,C and T denote the sin, cos and tan respectively on
 *      [-PI/4, +PI/4]. Reduce the argument x to y1+y2 = x-k*pi/2
 *      in [-pi/4 , +pi/4], and let n = k mod 4.
 *      We have
 *
 *          n        m64_sin(x)      m64_cos(x)        m64_tan(x)
 *     ----------------------------------------------------------
 *          0          S           C             T
 *          1          C          -S            -1/T
 *          2         -S          -C             T
 *          3         -C           S            -1/T
 *     ----------------------------------------------------------
 *
 * Special cases:
 *      Let trig be any of sin, cos, or tan.
 *      trig(+-INF)  is NaN, with signals;
 *      trig(NaN)    is that NaN;
 *
 * Accuracy:
 *      TRIG(x) returns trig(x) nearly rounded
 */


static double m64_cos_(double x);
double m64_cos(double x)
{
    return m64_cos_(x);
}
static double m64_cos_(double x)
{
	double y[2];
	uint32_t ix;
	unsigned n;

	GET_HIGH_WORD(ix, x);
	ix &= 0x7fffffff;

	/* |x| ~< pi/4 */
	if (ix <= 0x3fe921fb) {
		if (ix < 0x3e46a09e) {  /* |x| < 2**-27 * sqrt(2) */
			/* raise inexact if x!=0 */
			FORCE_EVAL(x + 0x1p120f);
			return 1.0;
		}
		return m64_kcos(x, 0);
	}

	/* m64_cos(Inf or NaN) is NaN */
	if (ix >= 0x7ff00000)
		return x-x;

	/* argument reduction */
	n = m64_rem_pio2(x, y);
	switch (n&3) {
	case 0: return  m64_kcos(y[0], y[1]);
	case 1: return -m64_ksin(y[0], y[1], 1);
	case 2: return -m64_kcos(y[0], y[1]);
	default:
		return  m64_ksin(y[0], y[1], 1);
	}
}

/* ---- musl src/math/tan.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/s_tan.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* m64_tan(x)
 * Return tangent function of x.
 *
 * kernel function:
 *      m64_ktan           ... tangent function on [-pi/4,pi/4]
 *      m64_rem_pio2      ... argument reduction routine
 *
 * Method.
 *      Let S,C and T denote the sin, cos and tan respectively on
 *      [-PI/4, +PI/4]. Reduce the argument x to y1+y2 = x-k*pi/2
 *      in [-pi/4 , +pi/4], and let n = k mod 4.
 *      We have
 *
 *          n        m64_sin(x)      m64_cos(x)        m64_tan(x)
 *     ----------------------------------------------------------
 *          0          S           C             T
 *          1          C          -S            -1/T
 *          2         -S          -C             T
 *          3         -C           S            -1/T
 *     ----------------------------------------------------------
 *
 * Special cases:
 *      Let trig be any of sin, cos, or tan.
 *      trig(+-INF)  is NaN, with signals;
 *      trig(NaN)    is that NaN;
 *
 * Accuracy:
 *      TRIG(x) returns trig(x) nearly rounded
 */


static double m64_tan_(double x);
double m64_tan(double x)
{
    return m64_tan_(x);
}
static double m64_tan_(double x)
{
	double y[2];
	uint32_t ix;
	unsigned n;

	GET_HIGH_WORD(ix, x);
	ix &= 0x7fffffff;

	/* |x| ~< pi/4 */
	if (ix <= 0x3fe921fb) {
		if (ix < 0x3e400000) { /* |x| < 2**-27 */
			/* raise inexact if x!=0 and underflow if subnormal */
			FORCE_EVAL(ix < 0x00100000 ? x/0x1p120f : x+0x1p120f);
			return x;
		}
		return m64_ktan(x, 0.0, 0);
	}

	/* m64_tan(Inf or NaN) is NaN */
	if (ix >= 0x7ff00000)
		return x - x;

	/* argument reduction */
	n = m64_rem_pio2(x, y);
	return m64_ktan(y[0], y[1], n&1);
}

/* ---- musl src/math/atan.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/s_atan.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* m64_atan(x)
 * Method
 *   1. Reduce x to positive by m64_atan(x) = -m64_atan(-x).
 *   2. According to the integer k=4t+0.25 chopped, t=x, the argument
 *      is further reduced to one of the following intervals and the
 *      arctangent of t is evaluated by the corresponding formula:
 *
 *      [0,7/16]      m64_atan(x) = t-t^3*(a1+t^2*(a2+...(a10+t^2*a11)...)
 *      [7/16,11/16]  m64_atan(x) = m64_atan(1/2) + m64_atan( (t-0.5)/(1+t/2) )
 *      [11/16.19/16] m64_atan(x) = m64_atan( 1 ) + m64_atan( (t-1)/(1+t) )
 *      [19/16,39/16] m64_atan(x) = m64_atan(3/2) + m64_atan( (t-1.5)/(1+1.5t) )
 *      [39/16,INF]   m64_atan(x) = m64_atan(INF) + m64_atan( -1/t )
 *
 * Constants:
 * The hexadecimal values are the intended ones for the following
 * constants. The decimal values may be used, provided that the
 * compiler will convert from decimal to binary accurately enough
 * to produce the hexadecimal values shown.
 */



static const double atanhi[] = {
  4.63647609000806093515e-01, /* m64_atan(0.5)hi 0x3FDDAC67, 0x0561BB4F */
  7.85398163397448278999e-01, /* m64_atan(1.0)hi 0x3FE921FB, 0x54442D18 */
  9.82793723247329054082e-01, /* m64_atan(1.5)hi 0x3FEF730B, 0xD281F69B */
  1.57079632679489655800e+00, /* m64_atan(inf)hi 0x3FF921FB, 0x54442D18 */
};

static const double atanlo[] = {
  2.26987774529616870924e-17, /* m64_atan(0.5)lo 0x3C7A2B7F, 0x222F65E2 */
  3.06161699786838301793e-17, /* m64_atan(1.0)lo 0x3C81A626, 0x33145C07 */
  1.39033110312309984516e-17, /* m64_atan(1.5)lo 0x3C700788, 0x7AF0CBBD */
  6.12323399573676603587e-17, /* m64_atan(inf)lo 0x3C91A626, 0x33145C07 */
};

static const double aT[] = {
  3.33333333333329318027e-01, /* 0x3FD55555, 0x5555550D */
 -1.99999999998764832476e-01, /* 0xBFC99999, 0x9998EBC4 */
  1.42857142725034663711e-01, /* 0x3FC24924, 0x920083FF */
 -1.11111104054623557880e-01, /* 0xBFBC71C6, 0xFE231671 */
  9.09088713343650656196e-02, /* 0x3FB745CD, 0xC54C206E */
 -7.69187620504482999495e-02, /* 0xBFB3B0F2, 0xAF749A6D */
  6.66107313738753120669e-02, /* 0x3FB10D66, 0xA0D03D51 */
 -5.83357013379057348645e-02, /* 0xBFADDE2D, 0x52DEFD9A */
  4.97687799461593236017e-02, /* 0x3FA97B4B, 0x24760DEB */
 -3.65315727442169155270e-02, /* 0xBFA2B444, 0x2C6A6C2F */
  1.62858201153657823623e-02, /* 0x3F90AD3A, 0xE322DA11 */
};

static double m64_atan_(double x);
double m64_atan(double x)
{
    return m64_atan_(x);
}
static double m64_atan_(double x)
{
	double w,s1,s2,z;
	uint32_t ix,sign;
	int id;

	GET_HIGH_WORD(ix, x);
	sign = ix >> 31;
	ix &= 0x7fffffff;
	if (ix >= 0x44100000) {   /* if |x| >= 2^66 */
		if (isnan(x))
			return x;
		z = atanhi[3] + 0x1p-120f;
		return sign ? -z : z;
	}
	if (ix < 0x3fdc0000) {    /* |x| < 0.4375 */
		if (ix < 0x3e400000) {  /* |x| < 2^-27 */
			if (ix < 0x00100000)
				/* raise underflow for subnormal x */
				FORCE_EVAL((float)x);
			return x;
		}
		id = -1;
	} else {
		x = __builtin_fabs(x);
		if (ix < 0x3ff30000) {  /* |x| < 1.1875 */
			if (ix < 0x3fe60000) {  /*  7/16 <= |x| < 11/16 */
				id = 0;
				x = (2.0*x-1.0)/(2.0+x);
			} else {                /* 11/16 <= |x| < 19/16 */
				id = 1;
				x = (x-1.0)/(x+1.0);
			}
		} else {
			if (ix < 0x40038000) {  /* |x| < 2.4375 */
				id = 2;
				x = (x-1.5)/(1.0+1.5*x);
			} else {                /* 2.4375 <= |x| < 2^66 */
				id = 3;
				x = -1.0/x;
			}
		}
	}
	/* end of argument reduction */
	z = x*x;
	w = z*z;
	/* break sum from i=0 to 10 aT[i]z**(i+1) into odd and even poly */
	s1 = z*(aT[0]+w*(aT[2]+w*(aT[4]+w*(aT[6]+w*(aT[8]+w*aT[10])))));
	s2 = w*(aT[1]+w*(aT[3]+w*(aT[5]+w*(aT[7]+w*aT[9]))));
	if (id < 0)
		return x - x*(s1+s2);
	z = atanhi[id] - (x*(s1+s2) - atanlo[id] - x);
	return sign ? -z : z;
}

/* ---- musl src/math/atan2.c ---- */
/* origin: FreeBSD /usr/src/lib/msun/src/e_atan2.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 *
 */
/* m64_atan2(y,x)
 * Method :
 *      1. Reduce y to positive by m64_atan2(y,x)=-m64_atan2(-y,x).
 *      2. Reduce x to positive by (if x and y are unexceptional):
 *              ARG (x+iy) = arctan(y/x)           ... if x > 0,
 *              ARG (x+iy) = pi - arctan[y/(-x)]   ... if x < 0,
 *
 * Special cases:
 *
 *      ATAN2((anything), NaN ) is NaN;
 *      ATAN2(NAN , (anything) ) is NaN;
 *      ATAN2(+-0, +(anything but NaN)) is +-0  ;
 *      ATAN2(+-0, -(anything but NaN)) is +-pi ;
 *      ATAN2(+-(anything but 0 and NaN), 0) is +-pi/2;
 *      ATAN2(+-(anything but INF and NaN), +INF) is +-0 ;
 *      ATAN2(+-(anything but INF and NaN), -INF) is +-pi;
 *      ATAN2(+-INF,+INF ) is +-pi/4 ;
 *      ATAN2(+-INF,-INF ) is +-3pi/4;
 *      ATAN2(+-INF, (anything but,0,NaN, and INF)) is +-pi/2;
 *
 * Constants:
 * The hexadecimal values are the intended ones for the following
 * constants. The decimal values may be used, provided that the
 * compiler will convert from decimal to binary accurately enough
 * to produce the hexadecimal values shown.
 */


static const double
pi     = 3.1415926535897931160E+00, /* 0x400921FB, 0x54442D18 */
pi_lo  = 1.2246467991473531772E-16; /* 0x3CA1A626, 0x33145C07 */

static double m64_atan2_(double y, double x);
double m64_atan2(double y, double x)
{
    return m64_atan2_(y, x);
}
static double m64_atan2_(double y, double x)
{
	double z;
	uint32_t m,lx,ly,ix,iy;

	if (isnan(x) || isnan(y))
		return x+y;
	EXTRACT_WORDS(ix, lx, x);
	EXTRACT_WORDS(iy, ly, y);
	if (((ix-0x3ff00000) | lx) == 0)  /* x = 1.0 */
		return m64_atan(y);
	m = ((iy>>31)&1) | ((ix>>30)&2);  /* 2*sign(x)+sign(y) */
	ix = ix & 0x7fffffff;
	iy = iy & 0x7fffffff;

	/* when y = 0 */
	if ((iy|ly) == 0) {
		switch(m) {
		case 0:
		case 1: return y;   /* m64_atan(+-0,+anything)=+-0 */
		case 2: return  pi; /* m64_atan(+0,-anything) = pi */
		case 3: return -pi; /* m64_atan(-0,-anything) =-pi */
		}
	}
	/* when x = 0 */
	if ((ix|lx) == 0)
		return m&1 ? -pi/2 : pi/2;
	/* when x is INF */
	if (ix == 0x7ff00000) {
		if (iy == 0x7ff00000) {
			switch(m) {
			case 0: return  pi/4;   /* m64_atan(+INF,+INF) */
			case 1: return -pi/4;   /* m64_atan(-INF,+INF) */
			case 2: return  3*pi/4; /* m64_atan(+INF,-INF) */
			case 3: return -3*pi/4; /* m64_atan(-INF,-INF) */
			}
		} else {
			switch(m) {
			case 0: return  0.0; /* m64_atan(+...,+INF) */
			case 1: return -0.0; /* m64_atan(-...,+INF) */
			case 2: return  pi;  /* m64_atan(+...,-INF) */
			case 3: return -pi;  /* m64_atan(-...,-INF) */
			}
		}
	}
	/* |y/x| > 0x1p64 */
	if (ix+(64<<20) < iy || iy == 0x7ff00000)
		return m&1 ? -pi/2 : pi/2;

	/* z = m64_atan(|y/x|) without spurious underflow */
	if ((m&2) && iy+(64<<20) < ix)  /* |y/x| < 0x1p-64, x<0 */
		z = 0;
	else
		z = m64_atan(__builtin_fabs(y/x));
	switch (m) {
	case 0: return z;              /* m64_atan(+,+) */
	case 1: return -z;             /* m64_atan(-,+) */
	case 2: return pi - (z-pi_lo); /* m64_atan(+,-) */
	default: /* case 3 */
		return (z-pi_lo) - pi; /* m64_atan(-,-) */
	}
}

/* ---- musl src/math/exp_data.c ---- */
/*
 * Shared data between exp, exp2 and pow.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */


#define N (1 << EXP_TABLE_BITS)

static const struct exp_data m64_exp_data = {
// N/ln2
.invln2N = 0x1.71547652b82fep0 * N,
// -ln2/N
.negln2hiN = -0x1.62e42fefa0000p-8,
.negln2loN = -0x1.cf79abc9e3b3ap-47,
// Used for rounding when !TOINT_INTRINSICS
#if EXP_USE_TOINT_NARROW
.shift = 0x1800000000.8p0,
#else
.shift = 0x1.8p52,
#endif
// exp polynomial coefficients.
.poly = {
// abs error: 1.555*2^-66
// ulp error: 0.509 (0.511 without fma)
// if |x| < ln2/256+eps
// abs error if |x| < ln2/256+0x1p-15: 1.09*2^-65
// abs error if |x| < ln2/128: 1.7145*2^-56
0x1.ffffffffffdbdp-2,
0x1.555555555543cp-3,
0x1.55555cf172b91p-5,
0x1.1111167a4d017p-7,
},
.exp2_shift = 0x1.8p52 / N,
// exp2 polynomial coefficients.
.exp2_poly = {
// abs error: 1.2195*2^-65
// ulp error: 0.507 (0.511 without fma)
// if |x| < 1/256
// abs error if |x| < 1/128: 1.9941*2^-56
0x1.62e42fefa39efp-1,
0x1.ebfbdff82c424p-3,
0x1.c6b08d70cf4b5p-5,
0x1.3b2abd24650ccp-7,
0x1.5d7e09b4e3a84p-10,
},
// 2^(k/N) ~= H[k]*(1 + T[k]) for int k in [0,N)
// tab[2*k] = asuint64(T[k])
// tab[2*k+1] = asuint64(H[k]) - (k << 52)/N
.tab = {
0x0, 0x3ff0000000000000,
0x3c9b3b4f1a88bf6e, 0x3feff63da9fb3335,
0xbc7160139cd8dc5d, 0x3fefec9a3e778061,
0xbc905e7a108766d1, 0x3fefe315e86e7f85,
0x3c8cd2523567f613, 0x3fefd9b0d3158574,
0xbc8bce8023f98efa, 0x3fefd06b29ddf6de,
0x3c60f74e61e6c861, 0x3fefc74518759bc8,
0x3c90a3e45b33d399, 0x3fefbe3ecac6f383,
0x3c979aa65d837b6d, 0x3fefb5586cf9890f,
0x3c8eb51a92fdeffc, 0x3fefac922b7247f7,
0x3c3ebe3d702f9cd1, 0x3fefa3ec32d3d1a2,
0xbc6a033489906e0b, 0x3fef9b66affed31b,
0xbc9556522a2fbd0e, 0x3fef9301d0125b51,
0xbc5080ef8c4eea55, 0x3fef8abdc06c31cc,
0xbc91c923b9d5f416, 0x3fef829aaea92de0,
0x3c80d3e3e95c55af, 0x3fef7a98c8a58e51,
0xbc801b15eaa59348, 0x3fef72b83c7d517b,
0xbc8f1ff055de323d, 0x3fef6af9388c8dea,
0x3c8b898c3f1353bf, 0x3fef635beb6fcb75,
0xbc96d99c7611eb26, 0x3fef5be084045cd4,
0x3c9aecf73e3a2f60, 0x3fef54873168b9aa,
0xbc8fe782cb86389d, 0x3fef4d5022fcd91d,
0x3c8a6f4144a6c38d, 0x3fef463b88628cd6,
0x3c807a05b0e4047d, 0x3fef3f49917ddc96,
0x3c968efde3a8a894, 0x3fef387a6e756238,
0x3c875e18f274487d, 0x3fef31ce4fb2a63f,
0x3c80472b981fe7f2, 0x3fef2b4565e27cdd,
0xbc96b87b3f71085e, 0x3fef24dfe1f56381,
0x3c82f7e16d09ab31, 0x3fef1e9df51fdee1,
0xbc3d219b1a6fbffa, 0x3fef187fd0dad990,
0x3c8b3782720c0ab4, 0x3fef1285a6e4030b,
0x3c6e149289cecb8f, 0x3fef0cafa93e2f56,
0x3c834d754db0abb6, 0x3fef06fe0a31b715,
0x3c864201e2ac744c, 0x3fef0170fc4cd831,
0x3c8fdd395dd3f84a, 0x3feefc08b26416ff,
0xbc86a3803b8e5b04, 0x3feef6c55f929ff1,
0xbc924aedcc4b5068, 0x3feef1a7373aa9cb,
0xbc9907f81b512d8e, 0x3feeecae6d05d866,
0xbc71d1e83e9436d2, 0x3feee7db34e59ff7,
0xbc991919b3ce1b15, 0x3feee32dc313a8e5,
0x3c859f48a72a4c6d, 0x3feedea64c123422,
0xbc9312607a28698a, 0x3feeda4504ac801c,
0xbc58a78f4817895b, 0x3feed60a21f72e2a,
0xbc7c2c9b67499a1b, 0x3feed1f5d950a897,
0x3c4363ed60c2ac11, 0x3feece086061892d,
0x3c9666093b0664ef, 0x3feeca41ed1d0057,
0x3c6ecce1daa10379, 0x3feec6a2b5c13cd0,
0x3c93ff8e3f0f1230, 0x3feec32af0d7d3de,
0x3c7690cebb7aafb0, 0x3feebfdad5362a27,
0x3c931dbdeb54e077, 0x3feebcb299fddd0d,
0xbc8f94340071a38e, 0x3feeb9b2769d2ca7,
0xbc87deccdc93a349, 0x3feeb6daa2cf6642,
0xbc78dec6bd0f385f, 0x3feeb42b569d4f82,
0xbc861246ec7b5cf6, 0x3feeb1a4ca5d920f,
0x3c93350518fdd78e, 0x3feeaf4736b527da,
0x3c7b98b72f8a9b05, 0x3feead12d497c7fd,
0x3c9063e1e21c5409, 0x3feeab07dd485429,
0x3c34c7855019c6ea, 0x3feea9268a5946b7,
0x3c9432e62b64c035, 0x3feea76f15ad2148,
0xbc8ce44a6199769f, 0x3feea5e1b976dc09,
0xbc8c33c53bef4da8, 0x3feea47eb03a5585,
0xbc845378892be9ae, 0x3feea34634ccc320,
0xbc93cedd78565858, 0x3feea23882552225,
0x3c5710aa807e1964, 0x3feea155d44ca973,
0xbc93b3efbf5e2228, 0x3feea09e667f3bcd,
0xbc6a12ad8734b982, 0x3feea012750bdabf,
0xbc6367efb86da9ee, 0x3fee9fb23c651a2f,
0xbc80dc3d54e08851, 0x3fee9f7df9519484,
0xbc781f647e5a3ecf, 0x3fee9f75e8ec5f74,
0xbc86ee4ac08b7db0, 0x3fee9f9a48a58174,
0xbc8619321e55e68a, 0x3fee9feb564267c9,
0x3c909ccb5e09d4d3, 0x3feea0694fde5d3f,
0xbc7b32dcb94da51d, 0x3feea11473eb0187,
0x3c94ecfd5467c06b, 0x3feea1ed0130c132,
0x3c65ebe1abd66c55, 0x3feea2f336cf4e62,
0xbc88a1c52fb3cf42, 0x3feea427543e1a12,
0xbc9369b6f13b3734, 0x3feea589994cce13,
0xbc805e843a19ff1e, 0x3feea71a4623c7ad,
0xbc94d450d872576e, 0x3feea8d99b4492ed,
0x3c90ad675b0e8a00, 0x3feeaac7d98a6699,
0x3c8db72fc1f0eab4, 0x3feeace5422aa0db,
0xbc65b6609cc5e7ff, 0x3feeaf3216b5448c,
0x3c7bf68359f35f44, 0x3feeb1ae99157736,
0xbc93091fa71e3d83, 0x3feeb45b0b91ffc6,
0xbc5da9b88b6c1e29, 0x3feeb737b0cdc5e5,
0xbc6c23f97c90b959, 0x3feeba44cbc8520f,
0xbc92434322f4f9aa, 0x3feebd829fde4e50,
0xbc85ca6cd7668e4b, 0x3feec0f170ca07ba,
0x3c71affc2b91ce27, 0x3feec49182a3f090,
0x3c6dd235e10a73bb, 0x3feec86319e32323,
0xbc87c50422622263, 0x3feecc667b5de565,
0x3c8b1c86e3e231d5, 0x3feed09bec4a2d33,
0xbc91bbd1d3bcbb15, 0x3feed503b23e255d,
0x3c90cc319cee31d2, 0x3feed99e1330b358,
0x3c8469846e735ab3, 0x3feede6b5579fdbf,
0xbc82dfcd978e9db4, 0x3feee36bbfd3f37a,
0x3c8c1a7792cb3387, 0x3feee89f995ad3ad,
0xbc907b8f4ad1d9fa, 0x3feeee07298db666,
0xbc55c3d956dcaeba, 0x3feef3a2b84f15fb,
0xbc90a40e3da6f640, 0x3feef9728de5593a,
0xbc68d6f438ad9334, 0x3feeff76f2fb5e47,
0xbc91eee26b588a35, 0x3fef05b030a1064a,
0x3c74ffd70a5fddcd, 0x3fef0c1e904bc1d2,
0xbc91bdfbfa9298ac, 0x3fef12c25bd71e09,
0x3c736eae30af0cb3, 0x3fef199bdd85529c,
0x3c8ee3325c9ffd94, 0x3fef20ab5fffd07a,
0x3c84e08fd10959ac, 0x3fef27f12e57d14b,
0x3c63cdaf384e1a67, 0x3fef2f6d9406e7b5,
0x3c676b2c6c921968, 0x3fef3720dcef9069,
0xbc808a1883ccb5d2, 0x3fef3f0b555dc3fa,
0xbc8fad5d3ffffa6f, 0x3fef472d4a07897c,
0xbc900dae3875a949, 0x3fef4f87080d89f2,
0x3c74a385a63d07a7, 0x3fef5818dcfba487,
0xbc82919e2040220f, 0x3fef60e316c98398,
0x3c8e5a50d5c192ac, 0x3fef69e603db3285,
0x3c843a59ac016b4b, 0x3fef7321f301b460,
0xbc82d52107b43e1f, 0x3fef7c97337b9b5f,
0xbc892ab93b470dc9, 0x3fef864614f5a129,
0x3c74b604603a88d3, 0x3fef902ee78b3ff6,
0x3c83c5ec519d7271, 0x3fef9a51fbc74c83,
0xbc8ff7128fd391f0, 0x3fefa4afa2a490da,
0xbc8dae98e223747d, 0x3fefaf482d8e67f1,
0x3c8ec3bc41aa2008, 0x3fefba1bee615a27,
0x3c842b94c3a9eb32, 0x3fefc52b376bba97,
0x3c8a64a931d185ee, 0x3fefd0765b6e4540,
0xbc8e37bae43be3ed, 0x3fefdbfdad9cbe14,
0x3c77893b4d91cd9d, 0x3fefe7c1819e90d8,
0x3c5305c14160cc89, 0x3feff3c22b8f71f1,
},
};
#undef N

/* ---- musl src/math/exp2.c ---- */
/*
 * Double-precision 2^x function.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */


#define N (1 << EXP_TABLE_BITS)
#define Shift m64_exp_data.exp2_shift
#define T m64_exp_data.tab
#define C1 m64_exp_data.exp2_poly[0]
#define C2 m64_exp_data.exp2_poly[1]
#define C3 m64_exp_data.exp2_poly[2]
#define C4 m64_exp_data.exp2_poly[3]
#define C5 m64_exp_data.exp2_poly[4]

/* Handle cases that may overflow or underflow when computing the result that
   is scale*(1+TMP) without intermediate rounding.  The bit representation of
   scale is in SBITS, however it has a computed exponent that may have
   overflown into the sign bit so that needs to be adjusted before using it as
   a double.  (int32_t)KI is the k used in the argument reduction and exponent
   adjustment of scale, positive k here means the result may overflow and
   negative k means the result may underflow.  */
static inline double m64_exp2_special(double tmp, uint64_t sbits, uint64_t ki)
{
	double scale, y;

	if ((ki & 0x80000000) == 0) {
		/* k > 0, the exponent of scale might have overflowed by 1.  */
		sbits -= 1ull << 52;
		scale = asdouble(sbits);
		y = 2 * (scale + scale * tmp);
		return eval_as_double(y);
	}
	/* k < 0, need special care in the subnormal range.  */
	sbits += 1022ull << 52;
	scale = asdouble(sbits);
	y = scale + scale * tmp;
	if (y < 1.0) {
		/* Round y to the right precision before scaling it into the subnormal
		   range to avoid double rounding that can cause 0.5+E/2 ulp error where
		   E is the worst-case ulp error outside the subnormal range.  So this
		   is only useful if the goal is better than 1 ulp worst-case error.  */
		double hi, lo;
		lo = scale - y + scale * tmp;
		hi = 1.0 + y;
		lo = 1.0 - hi + y + lo;
		y = eval_as_double(hi + lo) - 1.0;
		/* Avoid -0.0 with downward rounding.  */
		if (WANT_ROUNDING && y == 0.0)
			y = 0.0;
		/* The underflow exception needs to be signaled explicitly.  */
		fp_force_eval(fp_barrier(0x1p-1022) * 0x1p-1022);
	}
	y = 0x1p-1022 * y;
	return eval_as_double(y);
}

/* Top 12 bits of a double (sign and exponent bits).  */
static inline uint32_t m64_top12(double x)
{
	return asuint64(x) >> 52;
}

static double m64_exp2_(double x);
double m64_exp2(double x)
{
    return m64_exp2_(x);
}
static double m64_exp2_(double x)
{
	uint32_t abstop;
	uint64_t ki, idx, top, sbits;
	double kd, r, r2, scale, tail, tmp;

	abstop = m64_top12(x) & 0x7ff;
	if (predict_false(abstop - m64_top12(0x1p-54) >= m64_top12(512.0) - m64_top12(0x1p-54))) {
		if (abstop - m64_top12(0x1p-54) >= 0x80000000)
			/* Avoid spurious underflow for tiny x.  */
			/* Note: 0 is common input.  */
			return WANT_ROUNDING ? 1.0 + x : 1.0;
		if (abstop >= m64_top12(1024.0)) {
			if (asuint64(x) == asuint64(-INFINITY))
				return 0.0;
			if (abstop >= m64_top12(INFINITY))
				return 1.0 + x;
			if (!(asuint64(x) >> 63))
				return __math_oflow(0);
			else if (asuint64(x) >= asuint64(-1075.0))
				return __math_uflow(0);
		}
		if (2 * asuint64(x) > 2 * asuint64(928.0))
			/* Large x is special cased below.  */
			abstop = 0;
	}

	/* m64_exp2(x) = 2^(k/N) * 2^r, with 2^r in [2^(-1/2N),2^(1/2N)].  */
	/* x = k/N + r, with int k and r in [-1/2N, 1/2N].  */
	kd = eval_as_double(x + Shift);
	ki = asuint64(kd); /* k.  */
	kd -= Shift; /* k/N for int k.  */
	r = x - kd;
	/* 2^(k/N) ~= scale * (1 + tail).  */
	idx = 2 * (ki % N);
	top = ki << (52 - EXP_TABLE_BITS);
	tail = asdouble(T[idx]);
	/* This is only a valid scale when -1023*N < k < 1024*N.  */
	sbits = T[idx + 1] + top;
	/* m64_exp2(x) = 2^(k/N) * 2^r ~= scale + scale * (tail + 2^r - 1).  */
	/* Evaluation is optimized assuming superscalar pipelined execution.  */
	r2 = r * r;
	/* Without fma the worst case error is 0.5/N ulp larger.  */
	/* Worst case error is less than 0.5+0.86/N+(abs poly error * 2^53) ulp.  */
	tmp = tail + r * C1 + r2 * (C2 + r * C3) + r2 * r2 * (C4 + r * C5);
	if (predict_false(abstop == 0))
		return m64_exp2_special(tmp, sbits, ki);
	scale = asdouble(sbits);
	/* Note: tmp == 0 or |tmp| > 2^-65 and scale > 2^-928, so there
	   is no spurious underflow here even without fma.  */
	return eval_as_double(scale + scale * tmp);
}
#undef N
#undef Shift
#undef T
#undef C1
#undef C2
#undef C3
#undef C4
#undef C5

/* ---- musl src/math/log2_data.c ---- */
/*
 * Data for log2.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */


#define N (1 << LOG2_TABLE_BITS)

static const struct log2_data m64_log2_data = {
// First coefficient: 0x1.71547652b82fe1777d0ffda0d24p0
.invln2hi = 0x1.7154765200000p+0,
.invln2lo = 0x1.705fc2eefa200p-33,
.poly1 = {
// relative error: 0x1.2fad8188p-63
// in -0x1.5b51p-5 0x1.6ab2p-5
-0x1.71547652b82fep-1,
0x1.ec709dc3a03f7p-2,
-0x1.71547652b7c3fp-2,
0x1.2776c50f05be4p-2,
-0x1.ec709dd768fe5p-3,
0x1.a61761ec4e736p-3,
-0x1.7153fbc64a79bp-3,
0x1.484d154f01b4ap-3,
-0x1.289e4a72c383cp-3,
0x1.0b32f285aee66p-3,
},
.poly = {
// relative error: 0x1.a72c2bf8p-58
// abs error: 0x1.67a552c8p-66
// in -0x1.f45p-8 0x1.f45p-8
-0x1.71547652b8339p-1,
0x1.ec709dc3a04bep-2,
-0x1.7154764702ffbp-2,
0x1.2776c50034c48p-2,
-0x1.ec7b328ea92bcp-3,
0x1.a6225e117f92ep-3,
},
/* Algorithm:

	x = 2^k z
	m64_log2(x) = k + m64_log2(c) + m64_log2(z/c)
	m64_log2(z/c) = poly(z/c - 1)

where z is in [1.6p-1; 1.6p0] which is split into N subintervals and z falls
into the ith one, then table entries are computed as

	tab[i].invc = 1/c
	tab[i].logc = (double)m64_log2(c)
	tab2[i].chi = (double)c
	tab2[i].clo = (double)(c - (double)c)

where c is near the center of the subinterval and is chosen by trying +-2^29
floating point invc candidates around 1/center and selecting one for which

	1) the rounding error in 0x1.8p10 + logc is 0,
	2) the rounding error in z - chi - clo is < 0x1p-64 and
	3) the rounding error in (double)m64_log2(c) is minimized (< 0x1p-68).

Note: 1) ensures that k + logc can be computed without rounding error, 2)
ensures that z/c - 1 can be computed as (z - chi - clo)*invc with close to a
single rounding error when there is no fast fma for z*invc - 1, 3) ensures
that logc + poly(z/c - 1) has small error, however near x == 1 when
|m64_log2(x)| < 0x1p-4, this is not enough so that is special cased.  */
.tab = {
{0x1.724286bb1acf8p+0, -0x1.1095feecdb000p-1},
{0x1.6e1f766d2cca1p+0, -0x1.08494bd76d000p-1},
{0x1.6a13d0e30d48ap+0, -0x1.00143aee8f800p-1},
{0x1.661ec32d06c85p+0, -0x1.efec5360b4000p-2},
{0x1.623fa951198f8p+0, -0x1.dfdd91ab7e000p-2},
{0x1.5e75ba4cf026cp+0, -0x1.cffae0cc79000p-2},
{0x1.5ac055a214fb8p+0, -0x1.c043811fda000p-2},
{0x1.571ed0f166e1ep+0, -0x1.b0b67323ae000p-2},
{0x1.53909590bf835p+0, -0x1.a152f5a2db000p-2},
{0x1.5014fed61adddp+0, -0x1.9217f5af86000p-2},
{0x1.4cab88e487bd0p+0, -0x1.8304db0719000p-2},
{0x1.49539b4334feep+0, -0x1.74189f9a9e000p-2},
{0x1.460cbdfafd569p+0, -0x1.6552bb5199000p-2},
{0x1.42d664ee4b953p+0, -0x1.56b23a29b1000p-2},
{0x1.3fb01111dd8a6p+0, -0x1.483650f5fa000p-2},
{0x1.3c995b70c5836p+0, -0x1.39de937f6a000p-2},
{0x1.3991c4ab6fd4ap+0, -0x1.2baa1538d6000p-2},
{0x1.3698e0ce099b5p+0, -0x1.1d98340ca4000p-2},
{0x1.33ae48213e7b2p+0, -0x1.0fa853a40e000p-2},
{0x1.30d191985bdb1p+0, -0x1.01d9c32e73000p-2},
{0x1.2e025cab271d7p+0, -0x1.e857da2fa6000p-3},
{0x1.2b404cf13cd82p+0, -0x1.cd3c8633d8000p-3},
{0x1.288b02c7ccb50p+0, -0x1.b26034c14a000p-3},
{0x1.25e2263944de5p+0, -0x1.97c1c2f4fe000p-3},
{0x1.234563d8615b1p+0, -0x1.7d6023f800000p-3},
{0x1.20b46e33eaf38p+0, -0x1.633a71a05e000p-3},
{0x1.1e2eefdcda3ddp+0, -0x1.494f5e9570000p-3},
{0x1.1bb4a580b3930p+0, -0x1.2f9e424e0a000p-3},
{0x1.19453847f2200p+0, -0x1.162595afdc000p-3},
{0x1.16e06c0d5d73cp+0, -0x1.f9c9a75bd8000p-4},
{0x1.1485f47b7e4c2p+0, -0x1.c7b575bf9c000p-4},
{0x1.12358ad0085d1p+0, -0x1.960c60ff48000p-4},
{0x1.0fef00f532227p+0, -0x1.64ce247b60000p-4},
{0x1.0db2077d03a8fp+0, -0x1.33f78b2014000p-4},
{0x1.0b7e6d65980d9p+0, -0x1.0387d1a42c000p-4},
{0x1.0953efe7b408dp+0, -0x1.a6f9208b50000p-5},
{0x1.07325cac53b83p+0, -0x1.47a954f770000p-5},
{0x1.05197e40d1b5cp+0, -0x1.d23a8c50c0000p-6},
{0x1.03091c1208ea2p+0, -0x1.16a2629780000p-6},
{0x1.0101025b37e21p+0, -0x1.720f8d8e80000p-8},
{0x1.fc07ef9caa76bp-1, 0x1.6fe53b1500000p-7},
{0x1.f4465d3f6f184p-1, 0x1.11ccce10f8000p-5},
{0x1.ecc079f84107fp-1, 0x1.c4dfc8c8b8000p-5},
{0x1.e573a99975ae8p-1, 0x1.3aa321e574000p-4},
{0x1.de5d6f0bd3de6p-1, 0x1.918a0d08b8000p-4},
{0x1.d77b681ff38b3p-1, 0x1.e72e9da044000p-4},
{0x1.d0cb5724de943p-1, 0x1.1dcd2507f6000p-3},
{0x1.ca4b2dc0e7563p-1, 0x1.476ab03dea000p-3},
{0x1.c3f8ee8d6cb51p-1, 0x1.7074377e22000p-3},
{0x1.bdd2b4f020c4cp-1, 0x1.98ede8ba94000p-3},
{0x1.b7d6c006015cap-1, 0x1.c0db86ad2e000p-3},
{0x1.b20366e2e338fp-1, 0x1.e840aafcee000p-3},
{0x1.ac57026295039p-1, 0x1.0790ab4678000p-2},
{0x1.a6d01bc2731ddp-1, 0x1.1ac056801c000p-2},
{0x1.a16d3bc3ff18bp-1, 0x1.2db11d4fee000p-2},
{0x1.9c2d14967feadp-1, 0x1.406464ec58000p-2},
{0x1.970e4f47c9902p-1, 0x1.52dbe093af000p-2},
{0x1.920fb3982bcf2p-1, 0x1.651902050d000p-2},
{0x1.8d30187f759f1p-1, 0x1.771d2cdeaf000p-2},
{0x1.886e5ebb9f66dp-1, 0x1.88e9c857d9000p-2},
{0x1.83c97b658b994p-1, 0x1.9a80155e16000p-2},
{0x1.7f405ffc61022p-1, 0x1.abe186ed3d000p-2},
{0x1.7ad22181415cap-1, 0x1.bd0f2aea0e000p-2},
{0x1.767dcf99eff8cp-1, 0x1.ce0a43dbf4000p-2},
},
#if !__FP_FAST_FMA
.tab2 = {
{0x1.6200012b90a8ep-1, 0x1.904ab0644b605p-55},
{0x1.66000045734a6p-1, 0x1.1ff9bea62f7a9p-57},
{0x1.69fffc325f2c5p-1, 0x1.27ecfcb3c90bap-55},
{0x1.6e00038b95a04p-1, 0x1.8ff8856739326p-55},
{0x1.71fffe09994e3p-1, 0x1.afd40275f82b1p-55},
{0x1.7600015590e1p-1, -0x1.2fd75b4238341p-56},
{0x1.7a00012655bd5p-1, 0x1.808e67c242b76p-56},
{0x1.7e0003259e9a6p-1, -0x1.208e426f622b7p-57},
{0x1.81fffedb4b2d2p-1, -0x1.402461ea5c92fp-55},
{0x1.860002dfafcc3p-1, 0x1.df7f4a2f29a1fp-57},
{0x1.89ffff78c6b5p-1, -0x1.e0453094995fdp-55},
{0x1.8e00039671566p-1, -0x1.a04f3bec77b45p-55},
{0x1.91fffe2bf1745p-1, -0x1.7fa34400e203cp-56},
{0x1.95fffcc5c9fd1p-1, -0x1.6ff8005a0695dp-56},
{0x1.9a0003bba4767p-1, 0x1.0f8c4c4ec7e03p-56},
{0x1.9dfffe7b92da5p-1, 0x1.e7fd9478c4602p-55},
{0x1.a1fffd72efdafp-1, -0x1.a0c554dcdae7ep-57},
{0x1.a5fffde04ff95p-1, 0x1.67da98ce9b26bp-55},
{0x1.a9fffca5e8d2bp-1, -0x1.284c9b54c13dep-55},
{0x1.adfffddad03eap-1, 0x1.812c8ea602e3cp-58},
{0x1.b1ffff10d3d4dp-1, -0x1.efaddad27789cp-55},
{0x1.b5fffce21165ap-1, 0x1.3cb1719c61237p-58},
{0x1.b9fffd950e674p-1, 0x1.3f7d94194cep-56},
{0x1.be000139ca8afp-1, 0x1.50ac4215d9bcp-56},
{0x1.c20005b46df99p-1, 0x1.beea653e9c1c9p-57},
{0x1.c600040b9f7aep-1, -0x1.c079f274a70d6p-56},
{0x1.ca0006255fd8ap-1, -0x1.a0b4076e84c1fp-56},
{0x1.cdfffd94c095dp-1, 0x1.8f933f99ab5d7p-55},
{0x1.d1ffff975d6cfp-1, -0x1.82c08665fe1bep-58},
{0x1.d5fffa2561c93p-1, -0x1.b04289bd295f3p-56},
{0x1.d9fff9d228b0cp-1, 0x1.70251340fa236p-55},
{0x1.de00065bc7e16p-1, -0x1.5011e16a4d80cp-56},
{0x1.e200002f64791p-1, 0x1.9802f09ef62ep-55},
{0x1.e600057d7a6d8p-1, -0x1.e0b75580cf7fap-56},
{0x1.ea00027edc00cp-1, -0x1.c848309459811p-55},
{0x1.ee0006cf5cb7cp-1, -0x1.f8027951576f4p-55},
{0x1.f2000782b7dccp-1, -0x1.f81d97274538fp-55},
{0x1.f6000260c450ap-1, -0x1.071002727ffdcp-59},
{0x1.f9fffe88cd533p-1, -0x1.81bdce1fda8bp-58},
{0x1.fdfffd50f8689p-1, 0x1.7f91acb918e6ep-55},
{0x1.0200004292367p+0, 0x1.b7ff365324681p-54},
{0x1.05fffe3e3d668p+0, 0x1.6fa08ddae957bp-55},
{0x1.0a0000a85a757p+0, -0x1.7e2de80d3fb91p-58},
{0x1.0e0001a5f3fccp+0, -0x1.1823305c5f014p-54},
{0x1.11ffff8afbaf5p+0, -0x1.bfabb6680bac2p-55},
{0x1.15fffe54d91adp+0, -0x1.d7f121737e7efp-54},
{0x1.1a00011ac36e1p+0, 0x1.c000a0516f5ffp-54},
{0x1.1e00019c84248p+0, -0x1.082fbe4da5dap-54},
{0x1.220000ffe5e6ep+0, -0x1.8fdd04c9cfb43p-55},
{0x1.26000269fd891p+0, 0x1.cfe2a7994d182p-55},
{0x1.2a00029a6e6dap+0, -0x1.00273715e8bc5p-56},
{0x1.2dfffe0293e39p+0, 0x1.b7c39dab2a6f9p-54},
{0x1.31ffff7dcf082p+0, 0x1.df1336edc5254p-56},
{0x1.35ffff05a8b6p+0, -0x1.e03564ccd31ebp-54},
{0x1.3a0002e0eaeccp+0, 0x1.5f0e74bd3a477p-56},
{0x1.3e000043bb236p+0, 0x1.c7dcb149d8833p-54},
{0x1.4200002d187ffp+0, 0x1.e08afcf2d3d28p-56},
{0x1.460000d387cb1p+0, 0x1.20837856599a6p-55},
{0x1.4a00004569f89p+0, -0x1.9fa5c904fbcd2p-55},
{0x1.4e000043543f3p+0, -0x1.81125ed175329p-56},
{0x1.51fffcc027f0fp+0, 0x1.883d8847754dcp-54},
{0x1.55ffffd87b36fp+0, -0x1.709e731d02807p-55},
{0x1.59ffff21df7bap+0, 0x1.7f79f68727b02p-55},
{0x1.5dfffebfc3481p+0, -0x1.180902e30e93ep-54},
},
#endif
};
#undef N

/* ---- musl src/math/log2.c ---- */
/*
 * Double-precision m64_log2(x) function.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */


#define T m64_log2_data.tab
#define T2 m64_log2_data.tab2
#define B m64_log2_data.poly1
#define A m64_log2_data.poly
#define InvLn2hi m64_log2_data.invln2hi
#define InvLn2lo m64_log2_data.invln2lo
#define N (1 << LOG2_TABLE_BITS)
#define OFF 0x3fe6000000000000

/* Top 16 bits of a double.  */
static inline uint32_t m64_top16(double x)
{
	return asuint64(x) >> 48;
}

static double m64_log2_(double x);
double m64_log2(double x)
{
    return m64_log2_(x);
}
static double m64_log2_(double x)
{
	double z, r, r2, r4, y, invc, logc, kd, hi, lo, t1, t2, t3, p;
	uint64_t ix, iz, tmp;
	uint32_t top;
	int k, i;

	ix = asuint64(x);
	top = m64_top16(x);
#define LO asuint64(1.0 - 0x1.5b51p-5)
#define HI asuint64(1.0 + 0x1.6ab2p-5)
	if (predict_false(ix - LO < HI - LO)) {
		/* Handle close to 1.0 inputs separately.  */
		/* Fix sign of zero with downward rounding when x==1.  */
		if (WANT_ROUNDING && predict_false(ix == asuint64(1.0)))
			return 0;
		r = x - 1.0;
#if __FP_FAST_FMA
		hi = r * InvLn2hi;
		lo = r * InvLn2lo + __builtin_fma(r, InvLn2hi, -hi);
#else
		double rhi, rlo;
		rhi = asdouble(asuint64(r) & -1ULL << 32);
		rlo = r - rhi;
		hi = rhi * InvLn2hi;
		lo = rlo * InvLn2hi + r * InvLn2lo;
#endif
		r2 = r * r; /* rounding error: 0x1p-62.  */
		r4 = r2 * r2;
		/* Worst-case error is less than 0.54 ULP (0.55 ULP without fma).  */
		p = r2 * (B[0] + r * B[1]);
		y = hi + p;
		lo += hi - y + p;
		lo += r4 * (B[2] + r * B[3] + r2 * (B[4] + r * B[5]) +
			    r4 * (B[6] + r * B[7] + r2 * (B[8] + r * B[9])));
		y += lo;
		return eval_as_double(y);
	}
	if (predict_false(top - 0x0010 >= 0x7ff0 - 0x0010)) {
		/* x < 0x1p-1022 or inf or nan.  */
		if (ix * 2 == 0)
			return __math_divzero(1);
		if (ix == asuint64(INFINITY)) /* log(inf) == inf.  */
			return x;
		if ((top & 0x8000) || (top & 0x7ff0) == 0x7ff0)
			return __math_invalid(x);
		/* x is subnormal, normalize it.  */
		ix = asuint64(x * 0x1p52);
		ix -= 52ULL << 52;
	}

	/* x = 2^k z; where z is in range [OFF,2*OFF) and exact.
	   The range is split into N subintervals.
	   The ith subinterval contains z and c is near its center.  */
	tmp = ix - OFF;
	i = (tmp >> (52 - LOG2_TABLE_BITS)) % N;
	k = (int64_t)tmp >> 52; /* arithmetic shift */
	iz = ix - (tmp & 0xfffULL << 52);
	invc = T[i].invc;
	logc = T[i].logc;
	z = asdouble(iz);
	kd = (double)k;

	/* m64_log2(x) = m64_log2(z/c) + m64_log2(c) + k.  */
	/* r ~= z/c - 1, |r| < 1/(2*N).  */
#if __FP_FAST_FMA
	/* rounding error: 0x1p-55/N.  */
	r = __builtin_fma(z, invc, -1.0);
	t1 = r * InvLn2hi;
	t2 = r * InvLn2lo + __builtin_fma(r, InvLn2hi, -t1);
#else
	double rhi, rlo;
	/* rounding error: 0x1p-55/N + 0x1p-65.  */
	r = (z - T2[i].chi - T2[i].clo) * invc;
	rhi = asdouble(asuint64(r) & -1ULL << 32);
	rlo = r - rhi;
	t1 = rhi * InvLn2hi;
	t2 = rlo * InvLn2hi + r * InvLn2lo;
#endif

	/* hi + lo = r/ln2 + m64_log2(c) + k.  */
	t3 = kd + logc;
	hi = t3 + t1;
	lo = t3 - hi + t1 + t2;

	/* m64_log2(r+1) = r/ln2 + r^2*poly(r).  */
	/* Evaluation is optimized assuming superscalar pipelined execution.  */
	r2 = r * r; /* rounding error: 0x1p-54/N^2.  */
	r4 = r2 * r2;
	/* Worst-case error if |y| > 0x1p-4: 0.547 ULP (0.550 ULP without fma).
	   ~ 0.5 + 2/N/ln2 + abs-poly-error*0x1p56 ULP (+ 0.003 ULP without fma).  */
	p = A[0] + r * A[1] + r2 * (A[2] + r * A[3]) + r4 * (A[4] + r * A[5]);
	y = lo + r2 * p + hi;
	return eval_as_double(y);
}
#undef T
#undef T2
#undef B
#undef A
#undef InvLn2hi
#undef InvLn2lo
#undef N
#undef OFF
#undef LO
#undef HI


/* ---- pow des Modells: 2^(e*log2 b) wie bisher (fpu.h), Sonderfälle nach C99 ---- */
static double m64_pow_(double b, double e);
double m64_pow(double b, double e)
{
    return m64_pow_(b, e);
}
static double m64_pow_(double b, double e)
{
	if (b > 0)
		return m64_exp2(e * m64_log2(b));
	if (e == 0)
		return 1.0;
	if (b != b || e != e)
		return b + e;
	if (b == 0)
		return e > 0 ? 0.0 : 1.0 / 0.0;
	if (__builtin_floor(e) != e)
		return __math_invalid(b);
	double r = m64_exp2(e * m64_log2(-b));
	return e - 2.0 * __builtin_trunc(e * 0.5) != 0 ? -r : r;   /* (OpenScreamer: no fmod -- the 68060 has it not) */
}


/* Prüfsumme der Zahlentabellen (ohne Verschiebungen beim Laden): Ladeausreißer-Suche (Programm beim ersten Start nach
 * dem Hochladen teilweise veraltet geladen?) */
static uint32_t tab_crc(uint32_t h, const void *p, uint32_t n)
{
    const uint8_t *b = (const uint8_t *)p;
    for (uint32_t i = 0; i < n; i++)
        h = (h ^ b[i]) * 16777619u;
    return h;
}
uint32_t m64_tables_crc(void)
{
    uint32_t h = 2166136261u;
    h = tab_crc(h, ipio2, sizeof ipio2);
    h = tab_crc(h, PIo2, sizeof PIo2);
    h = tab_crc(h, T, sizeof T);
    h = tab_crc(h, atanhi, sizeof atanhi);
    h = tab_crc(h, atanlo, sizeof atanlo);
    h = tab_crc(h, aT, sizeof aT);
    h = tab_crc(h, &m64_exp_data, sizeof m64_exp_data);
    h = tab_crc(h, &m64_log2_data, sizeof m64_log2_data);
    return h;
}
