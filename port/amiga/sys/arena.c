/*
 * arena.c - THE PORT'S MEMORY: malloc,
 * calloc, realloc and free of the whole program (-Wl,--wrap) out of one field in Fast RAM.
 *
 *  - the field: AllocAbs at a fixed address first ($0C000000, NAT_WRK: its place in the data cache
 *    does not depend on where AmigaOS loads the program), else AllocVec(MEMF_FAST); never Chip RAM;
 *  - every block 16-byte aligned (a head of 4 bytes before it: size | used), first fit from a roving pointer, free
 *    neighbours merged when looked at;
 *  - two parts: big blocks (>= 64 KB: containers, textures, pictures) in front, small ones behind -- in one field the
 *    many small ones cut up the gaps of freed big ones (black faces in the second race);
 *  - a block that fits in neither part, or a pointer from outside the field (newlib's own), goes to AllocVec /
 *    the real free.
 * Off the Amiga (qemu's test build) the field is mmap'd (outside the statics, as the Amiga's): the same code runs there.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifdef __amigaos__
#include <exec/memory.h>
#include <proto/exec.h>
#endif

void *__real_malloc(size_t n);
void *__real_calloc(size_t n, size_t e);
void *__real_realloc(void *p, size_t n);
void __real_free(void *p);

#ifndef ARENA_MB
#define ARENA_MB 64                 /* the containers in memory (OS_MEMFILES), textures, meshes: about 30 MB in a race */
#endif
#define ARENA_SMALL_MB 12           /* the part for blocks under ARENA_BIG, at the field's end */
#define ARENA_BIG (64u << 10)
#define ARENA_PAD 4096
#ifndef ARENA_REL
#define ARENA_REL 0                 /* (AmigaOS) the field's place against the statics, modulo 128 KB (Makefile ARENAREL) */
#endif
#define ARENA_STACK (1u << 20)      /* (AmigaOS) the program's stack at the field's start (amiga_stack_main) */

typedef struct { uint32_t *base, *end, *rover; } Arena;   /* heads: size in bytes (head included, x16), bit 0 = used */
static Arena s_ar[2];               /* 0 big, 1 small */
static uint8_t *s_mem;
static uint32_t s_size;
static int s_fixed, s_tried, s_gone;      /* s_gone: given back at the end (s_mem kept for the range test) */
uint32_t g_arena_used, g_arena_peak, g_arena_fail, g_arena_outside;
static uint8_t *s_stack;                  /* (AmigaOS) the stack's low end in the field, NULL: none */
static uint32_t s_rel;                    /* the field's start - the statics' (os_all.o's .bss), modulo 128 KB */
static void **s_out;                      /* the blocks outside the field (outside_alloc), a list */
static int s_out_gone;                    /* 1: arena_release has freed them -- a free() after it does nothing */

#ifdef __amigaos__
#define NAT_WRK 0x0c000000u
static void arena_release(void) __attribute__((destructor));
static void arena_release(void)
{
    /* (nothing more from the field after this: newlib's own clean-up never frees our blocks) */
    while (s_out) { void **raw = s_out; s_out = raw[0]; FreeVec(raw); }   /* (the outside blocks) */
    s_out_gone = 1;
    if (!s_mem || s_gone) return;
    s_gone = 1;                               /* free() of its blocks after this: nothing */
    if (s_fixed) FreeMem(s_mem, s_size); else FreeVec(s_mem);
}
#else
#include <sys/mman.h>                      /* (qemu: the field outside the program's statics, as the Amiga's -- else
                                              os_state_save would go through it, the containers loaded at the start) */
#endif

static void arena_part(Arena *a, uintptr_t from, uintptr_t to)
{
    uintptr_t b = (from + 15) & ~(uintptr_t)15;
    a->base = (uint32_t *)(b + 12);           /* the data 16-aligned: the head 4 bytes before it */
    a->end = (uint32_t *)((to & ~(uintptr_t)15) - 4);
    a->base[0] = (uint32_t)((uintptr_t)a->end - (uintptr_t)a->base) & ~15u;
    a->rover = a->base;
}

static int arena_init(void)
{
    if (s_tried) return s_mem != NULL;
    s_tried = 1;
#ifdef __amigaos__
    /* every size at the fixed address first (the V1200's Fast RAM ends at $10000000: 64 MB at $0C000000 does not fit,
       48 does), only then anywhere -- before, the first size's AllocVec ended the search and the field moved with
       whatever AmigaOS had free (V1200: the picture at $0B7B7AA0, $0B81F3F0, ... from build to build) */
    /* several fixed places, all on 16 MB bounds -- the same place in the 32 KB data cache for every one of them; another
       program's (or a crashed run's) blocks in one of them no longer send the field to wherever AmigaOS has room */
    static const uint32_t at[] = { NAT_WRK, 0x0d000000u, 0x0b000000u, 0x0a000000u, 0x0e000000u, 0x09000000u };
    /* the place within those: the same against the statics (the BSS hunk, where LoadSeg puts it) every run and every
       build, modulo 128 KB -- a fixed address alone left the statics' hot lines (pt_smg, the painter's tables) against
       the field's (textures, pictures, the stack) wherever the BSS hunk fell: painting +-1..3 ms from build to build.
       The stack at the field's start (ARENA_STACK, amiga_stack_main), so it is fixed against both */
    extern char __start_osbss[];
    const uint32_t off = ((uint32_t)(uintptr_t)__start_osbss + ARENA_REL) & 0x1fff0u;
    for (uint32_t mb = ARENA_MB; mb >= 16 && !s_mem; mb -= 16)
        for (unsigned k = 0; k < sizeof at / sizeof at[0] && !s_mem; k++) {
            s_size = (mb << 20) + ARENA_PAD + 64 + ARENA_STACK;
            uint8_t *p = AllocAbs(s_size, (APTR)(at[k] + off));
            if (p == (uint8_t *)(at[k] + off) && (TypeOfMem(p) & MEMF_FAST)) { s_mem = p; s_fixed = 1; break; }
            if (p) FreeMem(p, s_size);
        }
    for (uint32_t mb = ARENA_MB; mb >= 16 && !s_mem; mb -= 16) {
        s_size = (mb << 20) + ARENA_PAD + 64 + ARENA_STACK;
        s_mem = AllocVec(s_size, MEMF_FAST);
    }
    if (!s_mem) { (fprintf)(stderr, "memory: no field in Fast RAM -- AllocVec(MEMF_FAST) a block\n"); return 0; }
    s_stack = s_fixed ? s_mem + 64 : NULL;         /* (only at the fixed place: elsewhere libnix's stack is as good) */
    s_rel = (uint32_t)((uintptr_t)s_mem - (uintptr_t)__start_osbss) & 0x1ffffu;
#else
    s_size = (ARENA_MB << 20) + ARENA_PAD + 64;
    s_mem = mmap(NULL, s_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (s_mem == MAP_FAILED) { s_mem = NULL; (fprintf)(stderr, "memory: no field\n"); return 0; }
#endif
#ifdef __amigaos__
    const uint32_t stk = ARENA_STACK;
#else
    const uint32_t stk = 0;
#endif
    const uint32_t mb = (s_size - ARENA_PAD - 64 - stk) >> 20;
    const uintptr_t b = (uintptr_t)s_mem + stk + ARENA_PAD, split = b + ((mb - (mb > 24 ? ARENA_SMALL_MB : mb / 4)) << 20);
    arena_part(&s_ar[0], b, split);
    arena_part(&s_ar[1], split, (uintptr_t)s_mem + s_size);
    fprintf(stderr, "memory: a field of %lu MB in Fast RAM at %p%s\n", (unsigned long)mb, (void *)s_mem,
            s_fixed ? " (fixed)" : "");
    return 1;
}

/* (for the log once it is open: amiga_video.c) */
void arena_where(char *out, int n)
{
#ifdef __amigaos__
    extern char __start_osbss[], __start_osdata[];
    char sp_;
    snprintf(out, (size_t)n, "a field of %lu MB at %p%s, the statics' +%lu KB (modulo 128), stack %s (%p), data hunk %p, BSS %p",
             (unsigned long)(s_mem ? (s_size - ARENA_PAD - 64 - ARENA_STACK) >> 20 : 0),
             (void *)s_mem, s_fixed ? " (fixed)" : " (NOT at the fixed address)", (unsigned long)s_rel >> 10,
             s_stack && &sp_ >= (char *)s_stack && &sp_ < (char *)s_stack + ARENA_STACK ? "in the field" : "libnix's",
             (void *)&sp_, (void *)__start_osdata, (void *)__start_osbss);
#else
    snprintf(out, (size_t)n, "a field of %lu MB at %p%s", (unsigned long)(s_mem ? (s_size - ARENA_PAD - 64) >> 20 : 0),
             (void *)s_mem, s_fixed ? " (fixed)" : " (NOT at the fixed address)");
#endif
}

#ifdef __amigaos__
/* THE STACK IN THE FIELD: main (main.c) runs itself once more on ARENA_STACK at the field's start (win_68k.s
   amiga_stack_run: exec's StackSwap there and back), its place in the data cache then fixed against the statics and
   the field (libnix's __stack block lay wherever AmigaOS had room: the stack is the painter's and
   the geometry's most read data).  1: done, *ret main's result; 0: not here (none, or already on it) -- go on. */
extern int amiga_stack_run(void *lower, void *upper, int (*fn)(int, char **), int argc, char **argv);
extern void amiga_stack_exit(int rc) __attribute__((noreturn));
static int s_stack_on;                    /* 1 while main runs on it, 2 after */
int amiga_stack_main(int (*fn)(int, char **), int argc, char **argv, int *ret)
{
    if (s_stack_on || !arena_init() || !s_stack) return 0;
    s_stack_on = 1;
    *ret = amiga_stack_run(s_stack, s_stack + ARENA_STACK, fn, argc, argv);
    s_stack_on = 2;
    return 1;
}
/* exit() on it: first back onto libnix's stack (amiga_stack_run returns rc to main, main returns it), then the real
   exit -- its clean-up (arena_release) frees the field, the stack with it */
void __real_exit(int rc) __attribute__((noreturn));
void __wrap_exit(int rc)
{
    char here;
    if (s_stack_on == 1 && &here >= (char *)s_stack && &here < (char *)s_stack + ARENA_STACK) amiga_stack_exit(rc);
    __real_exit(rc);
}
#endif

static int in_field(const void *v)
{
    return s_mem && (const uint8_t *)v >= s_mem && (const uint8_t *)v < s_mem + s_size;
}

static void *arena_take(Arena *a, uint32_t need)
{
    for (int pass = 0; pass < 2; pass++) {
        uint32_t *p = pass ? a->base : a->rover, *stop = pass ? a->rover : a->end;
        while (p < stop && (uint32_t)((uintptr_t)a->end - (uintptr_t)p) >= 16) {
            uint32_t sz = p[0] & ~15u;
            if (!sz) break;
            if (!(p[0] & 1)) {
                uint32_t *q = (uint32_t *)((uint8_t *)p + sz);       /* free neighbours merged */
                while (q < a->end && !(q[0] & 1) && (q[0] & ~15u)) {
                    sz += q[0] & ~15u;
                    q = (uint32_t *)((uint8_t *)p + sz);
                }
                p[0] = sz;
                if (p < a->rover && q > a->rover) a->rover = p;
                if (sz >= need) {
                    if (sz - need >= 32) {                         /* the rest a free block */
                        uint32_t *r = (uint32_t *)((uint8_t *)p + need);
                        r[0] = sz - need;
                        sz = need;
                    }
                    p[0] = sz | 1;
                    a->rover = (uint32_t *)((uint8_t *)p + sz);
                    return p + 1;
                }
            }
            p = (uint32_t *)((uint8_t *)p + sz);
        }
    }
    return NULL;
}

/* outside the field (it is full, or there is none): a block of its own in Fast RAM, 16-aligned; the word before it
   0 (not "used": free knows it is not the field's), the one before that the AllocVec's address */
/* (the outside blocks in a list -- the raw block's first two long words, before the aligned data: AllocVec memory
   is not given back at the program's end, so arena_release frees what is left; before, every run on the V1200 left
   about a megabyte behind) */
static void out_link(void **raw) { raw[0] = s_out; raw[1] = NULL; if (s_out) s_out[1] = raw; s_out = raw; }
static void out_unlink(void **raw)
{
    if (raw[1]) ((void **)raw[1])[0] = raw[0]; else s_out = raw[0];
    if (raw[0]) ((void **)raw[0])[1] = raw[1];
}
static void *outside_alloc(size_t n)
{
#ifdef __amigaos__
    uint8_t *raw = AllocVec(n + 32, MEMF_FAST);
    if (!raw) raw = AllocVec(n + 32, MEMF_ANY);
#else
    uint8_t *raw = __real_malloc(n + 32);
#endif
    if (!raw) return NULL;
    out_link((void **)raw);
    uint8_t *v = (uint8_t *)(((uintptr_t)raw + 8 + 15) & ~(uintptr_t)15);
    ((void **)v)[-2] = raw;
    ((uint32_t *)v)[-1] = (uint32_t)n << 4 | 2;                   /* (bit 1: outside, the size above) */
    g_arena_outside++;
    return v;
}

static void *arena_alloc(size_t n)
{
    void *p = NULL;
    if (!s_gone && arena_init() && n <= s_size) {
        const uint32_t need = (uint32_t)((n + 4 + 15) & ~(size_t)15);
        const int k = n < ARENA_BIG;
        if (!(p = arena_take(&s_ar[k], need))) p = arena_take(&s_ar[!k], need);
    }
    if (p) {
        g_arena_used += ((uint32_t *)p)[-1] & ~15u;
        if (g_arena_used > g_arena_peak) g_arena_peak = g_arena_used;
        return p;
    }
    g_arena_fail++;
    return outside_alloc(n);
}

static size_t block_size(const void *v)
{
    const uint32_t h = ((const uint32_t *)v)[-1];
    return in_field(v) ? (h & ~15u) - 4 : h >> 4;
}

void *__wrap_malloc(size_t n) { return arena_alloc(n ? n : 1); }

void __wrap_free(void *v)
{
    if (!v) return;
    if (in_field(v)) {
        if (s_gone) return;
        if (((uint32_t *)v)[-1] & 1) {
            g_arena_used -= ((uint32_t *)v)[-1] & ~15u;
            ((uint32_t *)v)[-1] &= ~1u;
        }
        return;
    }
    if ((((uint32_t *)v)[-1] & 15) == 2) {                       /* one of outside_alloc's */
        if (s_out_gone) return;
        out_unlink((void **)((void **)v)[-2]);
#ifdef __amigaos__
        FreeVec(((void **)v)[-2]);
#else
        __real_free(((void **)v)[-2]);
#endif
        return;
    }
    __real_free(v);                                               /* newlib's own */
}

void *__wrap_calloc(size_t a, size_t b)
{
    const size_t n = a * b;
    void *v = arena_alloc(n ? n : 1);
    if (v) memset(v, 0, n);
    return v;
}

void *__wrap_realloc(void *v, size_t n)
{
    if (!v) return arena_alloc(n ? n : 1);
    if (!in_field(v) && (((uint32_t *)v)[-1] & 15) != 2) return __real_realloc(v, n);
    const size_t have = block_size(v);
    if (n <= have) return v;
    void *w = arena_alloc(n);
    if (w) { memcpy(w, v, have); __wrap_free(v); }
    return w;
}

/* a block aligned to `align` (a power of two, >= 16) out of the field */
void *arena_alloc_aligned(size_t n, uint32_t align)
{
    uint8_t *v = arena_alloc(n + align);
    return v ? (void *)(((uintptr_t)v + align - 1) & ~(uintptr_t)(align - 1)) : NULL;
}
