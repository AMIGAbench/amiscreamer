/*
 * os_math.c - THE GAME'S FLOAT MATHS: sin, cos, tan, atan, atan2, pow,
 * exp from portable C (fpu64_math.c: musl, in double), so that the qemu build, FS-UAE and a real 68060 / 68080
 * reckon to the bit alike -- the C library's (glibc under qemu, libnix on the Amiga) differ in the last bits, and
 * cost there 5..11 us a call.  floor, ceil, lround and fmod are exact, worked out here without the library (no
 * 68060 trap: fmod is not in its FPU).  The square root stays the FPU's (fsqrt: exactly rounded everywhere).
 * m68k_libm.h turns the names over to these (the Amiga and the qemu build; the PC build keeps its libm).
 */
#include <stdint.h>
#include <string.h>
#include "fpu64_math.h"

/* to single, for certain (with -fexcess-precision=fast a cast need not round: a store to memory does) */
static float to_f(double d) { volatile float f = (float)d; return f; }
/* sine and cosine in vasm (math_68k.s sc68k: the same bits, tools/mathtest); its large arguments are the C's */
int sc68k(float x, int cosine, float *out);
float os_sinf(float x)  { float r; if (sc68k(x, 0, &r)) return r; return to_f(m64_sin((double)x)); }
float os_cosf(float x)  { float r; if (sc68k(x, 1, &r)) return r; return to_f(m64_cos((double)x)); }
int ta68k(float x, float *out);                                /* (math_68k.s) */
float os_tanf(float x)  { float r; if (ta68k(x, &r)) return r; return to_f(m64_tan((double)x)); }
int at68k(float a, float b, int two, float *out);           /* (math_68k.s: atan, atan2; its rare cases the C's) */
float os_atanf(float x) { float r; if (at68k(x, 0.0f, 0, &r)) return r; return to_f(m64_atan((double)x)); }
float os_atan2f(float y, float x) { float r; if (at68k(y, x, 1, &r)) return r; return to_f(m64_atan2((double)y, (double)x)); }
int px68k(float b, float e, float *out), ex68k(float x, float *out);   /* (math_68k.s: the whole of them) */
float os_powf(float b, float e)   { float r; px68k(b, e, &r); return r; }
float os_expf(float x)  { float r; ex68k(x, &r); return r; }
/* sqrt(x^2 + y^2) in double: the FPU's fdsqrt (in the 68060's hardware, rounded to double as IEEE wants it) */
float os_hypotf(float x, float y)
{
    const double a = x, b = y, v = a * a + b * b;
    double r;
    __asm__ ("fdsqrt%.x %1,%0" : "=f"(r) : "f"(v));
    return to_f(r);
}

static int32_t bits(float f) { int32_t b; memcpy(&b, &f, 4); return b; }

/* the whole part towards minus infinity (exact; a whole number, an infinity or NaN as it is; -0 stays -0) */
float os_floorf(float x)
{
    if (!((x < 8388608.0f) && (x > -8388608.0f)) || x == 0.0f) return x;
    const float t = (float)(int32_t)x;            /* (cut towards 0: exact below 2^23) */
    if (t == x) return x;
    return t > x ? t - 1.0f : (t == 0.0f && bits(x) < 0 ? -0.0f : t);
}
float os_ceilf(float x)
{
    if (!((x < 8388608.0f) && (x > -8388608.0f)) || x == 0.0f) return x;
    const float t = (float)(int32_t)x;
    if (t == x) return x;
    if (t < x) return t + 1.0f;
    return t == 0.0f ? -0.0f : t;                 /* (-0.3 -> -0) */
}
/* to the nearest whole number, halves away from 0 */
long os_lroundf(float x)
{
    const float a = x < 0.0f ? -x : x;
    if (!(a < 8388608.0f)) return (long)x;
    int32_t t = (int32_t)a;
    if (a - (float)t >= 0.5f) t++;                /* (a - t exact below 2^23) */
    return x < 0.0f ? -t : t;
}
/* x - n y with n = x / y cut towards 0, exactly, the sign of x (as C's fmodf): in double, exact while the quotient
   stays below 2^28 (the game's: a turn, 256 texels); else the long way, halving */
float os_fmodf(float x, float y)
{
    if (y < 0.0f) y = -y;
    if (!(y > 0.0f) || !(x - x == 0.0f) || !(y - y == 0.0f)) {
        if (y - y == 0.0f && !(x - x == 0.0f)) return (x - x) / (x - x);
        return y == 0.0f ? (x - x) / (x - x) : x;
    }
    const double dx = x, dy = y;
    double r;
    if (__builtin_fabs(dx / dy) < 268435456.0) {
        double q = __builtin_trunc(dx / dy);
        r = dx - q * dy;                          /* (q < 2^28, y 24 bits: q y exact; the difference exact) */
        if (dx >= 0.0) { if (r < 0.0) r += dy; else if (r >= dy) r -= dy; }
        else           { if (r > 0.0) r -= dy; else if (r <= -dy) r += dy; }
    } else {
        double a = __builtin_fabs(dx), m = dy;
        while (m * 2.0 <= a) m *= 2.0;
        while (m >= dy) { if (a >= m) a -= m; m *= 0.5; }
        r = dx < 0.0 ? -a : a;
    }
    if (r == 0.0) return dx < 0.0 ? -0.0f : 0.0f;
    return to_f(r);
}
