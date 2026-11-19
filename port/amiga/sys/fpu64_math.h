/* Transzendente Funktionen des 64-Bit-FPU-Modells in portablem C (fpu64_math.c, aus musl) */
#ifndef FPU64_MATH_H
#define FPU64_MATH_H
double m64_sin(double x);
double m64_cos(double x);
double m64_tan(double x);
double m64_atan(double x);
double m64_atan2(double y, double x);
double m64_exp2(double x);
double m64_log2(double x);
double m64_pow(double b, double e);    /* 2^(e*log2 b), Sonderfälle nach C99 */
#endif
