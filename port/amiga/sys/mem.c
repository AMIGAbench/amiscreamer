/*
 * mem.c - the choice of mem_68k.s's copy (g_copy_kind) at start: the processor's kind, and MOVE16 only after a
 * test on this machine (the destination's old contents in the cache, every length's tail checked).
 *   OS_MOVE16=0   never MOVE16          OS_COPYTEST=1   every alignment 0..15 x 0..15, length 0..300 against bytes
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef AMIGA
#include <exec/execbase.h>
#include <proto/exec.h>
#endif

#ifdef SPAN_C_ONLY
/* (qemu's C-only build: no assembler -- the reference copy) */
int32_t g_copy_kind = 1;
void *os_copy(void *d, const void *s, uint32_t n) { uint8_t *o = d; const uint8_t *i = s; while (n--) *o++ = *i++; return d; }
#else
extern int32_t g_copy_kind;
void *os_copy(void *d, const void *s, uint32_t n);
#endif

static int copy_test(int kind)
{
    enum { N = 300 };
    static uint8_t a[N + 64], b[N + 64], c[N + 64];
    const int32_t was = g_copy_kind;
    int bad = 0;
    g_copy_kind = kind;
    /* (the source and the destination's old bytes set once for each pair of alignments; after a copy the whole of b
       is checked against what it must hold, then the copied part put back -- not three arrays filled and a byte-wise
       memcmp for each of the 27,000 copies: 3.3 s of the first race's start on the V1200) */
    (void)c;
    for (int sa = 0; sa < 16 && !bad; sa++) {
        for (int i = 0; i < N + 64; i++) a[i] = (uint8_t)(i * 37 + sa);
        for (int da = 0; da < 16 && !bad; da++) {
            for (int i = 0; i < N + 64; i++) b[i] = (uint8_t)(i * 11 + da);
            for (int n = 0; n <= N - 32 && !bad; n += n < 80 ? 1 : 7) {
                if (os_copy(b + da, a + sa, (uint32_t)n) != b + da) bad = 1;
                /* (the copy and 16 bytes either side of it -- wider than any of the copies' steps; 1.5 s before) */
                const int i1 = da + n + 16 < N + 64 ? da + n + 16 : N + 64;
                for (int i = 0; i < da && !bad; i++) if (b[i] != (uint8_t)(i * 11 + da)) bad = 1;
                for (int i = 0; i < n && !bad; i++) if (b[da + i] != a[sa + i]) bad = 1;
                for (int i = da + n; i < i1 && !bad; i++) if (b[i] != (uint8_t)(i * 11 + da)) bad = 1;
                for (int i = da; i < da + n; i++) b[i] = (uint8_t)(i * 11 + da);
            }
        }
    }
    g_copy_kind = was;
    return !bad;
}

/* MOVE16 against this machine's caches: the destination written first (in the cache), the source after */
static int move16_test(void)
{
    enum { N = 8192 };
    uint8_t *ra = malloc(N + 32), *rb = malloc(N + 32);
    if (!ra || !rb) { free(ra); free(rb); return 0; }
    uint8_t *a = (uint8_t *)(((uintptr_t)ra + 15) & ~(uintptr_t)15), *b = (uint8_t *)(((uintptr_t)rb + 15) & ~(uintptr_t)15);
    int ok = (uintptr_t)a >= 0x200000 && (uintptr_t)b >= 0x200000;
    const int32_t was = g_copy_kind;
    g_copy_kind = 2;
    for (int pass = 0; pass < 4 && ok; pass++)
        for (int k = 0; k < 4 && ok; k++) {
            const uint32_t n = N - 17u * (uint32_t)k;
            for (uint32_t i = 0; i < N; i++) b[i] = (uint8_t)(i ^ 0x5a ^ pass);          /* the old contents, cached */
            for (uint32_t i = 0; i < N; i++) a[i] = (uint8_t)(i * 13 + pass * 7 + k);    /* the fresh source */
            os_copy(b, a, n);
            for (uint32_t i = 0; i < N && ok; i++)
                if (b[i] != (i < n ? (uint8_t)(i * 13 + pass * 7 + k) : (uint8_t)(i ^ 0x5a ^ pass))) ok = 0;
        }
    g_copy_kind = was;
    free(ra); free(rb);
    return ok;
}

void os_copy_init(void)
{
    static int done;
    if (done) return;
    done = 1;
    int kind = 1;
#ifdef AMIGA
    kind = (SysBase->AttnFlags & (AFF_68040 | (1u << 7))) ? 1 : 0;      /* (bit 7: the 68060) */
#endif
    g_copy_kind = kind;
    const char *t = getenv("OS_COPYTEST");
    if (t && t[0] == '1') fprintf(stderr, "copy: test %s\n", copy_test(kind) ? "the same as bytes" : "DIFFERS");
    const char *e = getenv("OS_MOVE16");
    if (kind == 1 && !(e && e[0] == '0')) {
        const int ok = move16_test() && (!(t && t[0] == '1') || copy_test(2));
        if (ok) g_copy_kind = 2;
        fprintf(stderr, "copy: MOVE16 %s\n", ok ? "on (tested)" : "off (the test failed)");
    } else
        fprintf(stderr, "copy: %s\n", kind ? "long words, 32 bytes a pass" : "four registers, 16 bytes a pass");
}

#if defined(OS_V080) && !defined(SPAN_C_ONLY)
/* the 080 build, once the AMMX is registered and span's own test has passed (span.c): os_copy 64 bits a step, after
   copy_test (every alignment 0..15 x 0..15, lengths 0..268) against bytes */
void os_copy_ammx(void)
{
    const char *e = getenv("OS_AMMX");
    if (e && e[0] == '0') return;
    const int ok = copy_test(3);
    if (ok) g_copy_kind = 3;
    fprintf(stderr, "copy: AMMX %s\n", ok ? "on (tested)" : "OFF (the test failed)");
}
#endif
