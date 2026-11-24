/* long-double-Mathematik für den Amiga-Build (wird per -include vor jede Quelle gesetzt).
 *
 * libnix/newlib haben keine 80-Bit-libm (sinl, cosl, tanl, atanl, atan2l, powl, truncl, fabsl fehlen;
 * sqrtl ist nur deklariert). Das Spiel bildet den x87 nach (src/game/fpu.h) und braucht genau diese
 * Funktionen in Extended-Genauigkeit. Der 6888x/68040/68060 rechnet wie der x87 mit 80 Bit, die
 * transzendenten Befehle (fsin, fcos, ftan, fatan, flog2, ftwotox, fintrz auf dem 040) emuliert auf
 * 040/060 die FPSP (68040.library/68060.library). Ergebnisse können im letzten Bit vom x87 abweichen
 * (anderer Algorithmus) – docs/amiga.md "Bitgleichheit".
 *
 * Umbenennung per Makro, weil math.h sqrtl bereits als extern deklariert (eine static-inline-
 * Neudefinition gleichen Namens wäre ein Konflikt). Spielcode bleibt unverändert. */
#ifndef M68K_LIBM_H
#define M68K_LIBM_H
#if defined(__m68k__) || defined(__mc68000__)
#include <math.h>

typedef long double m68k_xf;

#define M68K_FOP1(name, insn)                                              \
    static __inline__ m68k_xf name(m68k_xf x)                              \
    {                                                                      \
        m68k_xf r;                                                         \
        __asm__ (insn "%.x %1,%0" : "=f"(r) : "f"(x));                     \
        return r;                                                          \
    }

M68K_FOP1(m68k_sinl, "fsin")
M68K_FOP1(m68k_cosl, "fcos")
M68K_FOP1(m68k_tanl, "ftan")
M68K_FOP1(m68k_atanl, "fatan")
M68K_FOP1(m68k_sqrtl, "fsqrt")
M68K_FOP1(m68k_truncl, "fintrz")
M68K_FOP1(m68k_fabsl, "fabs")
M68K_FOP1(m68k_log2l, "flog2")
M68K_FOP1(m68k_exp2l, "ftwotox")

static __inline__ int m68k_signbitl(m68k_xf x)
{
    union { m68k_xf x; unsigned short w[6]; } u;
    u.x = x;
    return (u.w[0] & 0x8000) != 0;               /* Big-Endian: Vorzeichen im ersten Wort */
}

#define M68K_PI   3.14159265358979323846264338327950288L
#define M68K_PI_2 1.57079632679489661923132169163975144L

/* atan2 wie fpatan (Quadranten, Nullen mit Vorzeichen); NaN durchreichen */
static __inline__ m68k_xf m68k_atan2l(m68k_xf y, m68k_xf x)
{
    if (x != x || y != y)
        return x + y;
    if (x == 0) {
        if (y == 0)
            return m68k_signbitl(x) ? (m68k_signbitl(y) ? -M68K_PI : M68K_PI) : y;
        return y > 0 ? M68K_PI_2 : -M68K_PI_2;
    }
    if (m68k_fabsl(x) == __builtin_infl() || m68k_fabsl(y) == __builtin_infl()) {
        m68k_xf ax = m68k_fabsl(x) == __builtin_infl() ? (x > 0 ? 1.0L : -1.0L) : 0.0L * x;
        m68k_xf ay = m68k_fabsl(y) == __builtin_infl() ? (y > 0 ? 1.0L : -1.0L) : 0.0L * y;
        if (ax != 0 && ay != 0)
            return (ay > 0 ? 1 : -1) * (ax > 0 ? M68K_PI_2 / 2 : 3 * M68K_PI_2 / 2);
        y = ay;
        x = ax;
        if (x == 0)
            return y > 0 ? M68K_PI_2 : -M68K_PI_2;
    }
    m68k_xf a = m68k_atanl(y / x);
    if (x < 0)
        a += m68k_signbitl(y) ? -M68K_PI : M68K_PI;
    return a;
}

/* pow über 2^(e*log2 b) in Extended; Sonderfälle wie C99 */
static __inline__ m68k_xf m68k_powl(m68k_xf b, m68k_xf e)
{
    if (e == 0)
        return 1.0L;
    if (b == 1)
        return 1.0L;
    if (b != b || e != e)
        return b + e;
    if (b == 0) {
        int odd = m68k_truncl(e) == e && m68k_fabsl(e) < 1e19L &&
                  ((long long)e & 1);
        if (e < 0)
            return odd && m68k_signbitl(b) ? -__builtin_infl() : __builtin_infl();
        return odd ? b : 0.0L;
    }
    if (b < 0) {
        if (m68k_truncl(e) != e)
            return __builtin_nanl("");
        int odd = m68k_fabsl(e) < 1e19L && ((long long)e & 1);
        m68k_xf r = m68k_exp2l(e * m68k_log2l(-b));
        return odd ? -r : r;
    }
    return m68k_exp2l(e * m68k_log2l(b));
}

/* Runden nach FPCR (Vorgabe: zur nächsten, gerade) wie fist nach fninit. NUR für Werte im int32-Bereich
 * (die Aufrufer im Spiel prüfen das vorher); größere Werte sättigen. */
static __inline__ long long m68k_llrintl(m68k_xf x)
{
    long r;
    __asm__ ("fmove%.l %1,%0" : "=d"(r) : "f"(x));
    return r;
}

/* lrintf / lrint: newlib's on the Amiga cut towards zero (129.99999f gave 129).  C99's are to nearest
   in the current rounding mode: the FPU's fmove.l does exactly that (FPCR 0 = nearest, set at start) */
static __inline__ long m68k_lrintf(float x) { long r; __asm__ ("fmove%.l %1,%0" : "=d"(r) : "f"(x)); return r; }
static __inline__ long m68k_lrint(double x) { long r; __asm__ ("fmove%.l %1,%0" : "=d"(r) : "f"(x)); return r; }
#define lrintf m68k_lrintf
#define lrint  m68k_lrint

#define llrintl m68k_llrintl
#define sinl   m68k_sinl
#define cosl   m68k_cosl
#define tanl   m68k_tanl
#define atanl  m68k_atanl
#define atan2l m68k_atan2l
#define powl   m68k_powl
#define sqrtl  m68k_sqrtl
#define truncl m68k_truncl
#define fabsl  m68k_fabsl
#endif
#endif

/* THE GAME'S FLOAT MATHS (amiga/sys/os_math.c, fpu64_math.c): the same code, so
   the same bits, in the qemu build, on FS-UAE and on a real 68060 / 68080; no C library calls, no FPSP traps */
#if (defined(__m68k__) || defined(__mc68000__)) && !defined(OS_MATH_NO_REDIRECT)
float os_sinf(float x); float os_cosf(float x); float os_tanf(float x); float os_atanf(float x);
float os_atan2f(float y, float x); float os_powf(float b, float e); float os_expf(float x);
float os_hypotf(float x, float y); float os_floorf(float x); float os_ceilf(float x); long os_lroundf(float x);
float os_fmodf(float x, float y);
#define sinf   os_sinf
#define cosf   os_cosf
#define tanf   os_tanf
#define atanf  os_atanf
#define atan2f os_atan2f
#define powf   os_powf
#define expf   os_expf
#define hypotf os_hypotf
#define floorf os_floorf
#define ceilf  os_ceilf
#define lroundf os_lroundf
#define fmodf  os_fmodf
/* ... and the double ones (musl's, in fpu64_math.c) */
double m64_sin(double x); double m64_cos(double x); double m64_tan(double x); double m64_atan(double x);
double m64_atan2(double y, double x); double m64_pow(double b, double e);
#define sin   m64_sin
#define cos   m64_cos
#define tan   m64_tan
#define atan  m64_atan
#define atan2 m64_atan2
#define pow   m64_pow
#endif
