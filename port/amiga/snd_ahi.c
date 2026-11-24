/*
 * snd_ahi.c - THE SOUND THROUGH AHI: the port's own
 * 16-voice mixer (mixer_68k.s mx_render_l) stays; AHI gets only its sum -- one channel, two dynamic sounds (16-bit
 * stereo) in turn, the SoundFunc hook queueing the other one.  The CD's music (MUSIC/trackNN.raw, 22050 Hz) is mixed
 * into the same stream by this process (step 22050 / the mixing rate), no Paula channels 2/3.  The sum of each
 * buffer is vasm (snd_68k.s ahi_mix68k), checked against the C below once when the process starts.
 *  - SCREAMER_SND=ahi (or the launcher's CONFIG/AMIGA.CFG SOUND=AHI, oldargs.c): snd_load.c hands ahi_open to
 *    snd_68k.s's snd_dev_open, which falls back to Paula when it fails;
 *  - SCREAMER_AHIMODE (hex; AHIMODE=) the audio mode, else AHI's default; SCREAMER_AHIFREQ (>= 8000) the rate,
 *    else 22050;
 *  - snd_music's commands (mus_cmd / mus_newfh / mus_newblk under mus_sem, CTRL_D) and the music's volume
 *    (mus_vol, 0..64) are snd_68k.s's, as for its Paula music process.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <exec/exec.h>
#include <dos/dos.h>
#include <dos/dostags.h>
#include <devices/ahi.h>
#include <utility/hooks.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/ahi.h>
#include <clib/alib_protos.h>

struct Library *AHIBase;

/* snd_68k.s / mixer_68k.s */
extern struct SignalSemaphore snd_sem, mus_sem;
extern volatile long mus_cmd, mus_newfh, mus_newblk, mus_vol;
extern uint32_t snd_rate;
void mx_init(uint32_t rate);
int mx_render_l(int8_t *l, int8_t *r, uint32_t n);
uint32_t ahi_mix68k(int16_t *out, const int8_t *l, const int8_t *r, uint32_t n, const int8_t *ml, const int8_t *mr,
                    uint32_t *pos, uint32_t fill, uint32_t step, int32_t mv);

enum { AHI_LEN = 1024, MUS_MAXB = 16384, MUS_HDR = 16 };

static ULONG g_mode = AHI_DEFAULT_ID, g_freq = 22050, g_mixfreq;
static struct Task *volatile g_task, *g_main;
static volatile BYTE g_sig = -1;
static BYTE g_ready = -1;
static volatile int g_state, g_quit;          /* 0 starting, 1 playing, 2 ended, -1 failed */
static volatile int g_q, g_dbf;
static struct AHIAudioCtrl *g_ctrl;
static int8_t *g_l, *g_r;                     /* the mixer's sum, 8 bits a side */
/* the music (the process's) */
static BPTR g_fh;
static int g_play, g_eof;
static uint32_t g_blk, g_pos, g_fill, g_step;
static int8_t *g_mb;                          /* one block: blk left + blk right */
static int g_kernel = 1;                      /* 0: the C sum (ahi_mix68k differed from it) */

static uint32_t ahi_mix_c(int16_t *out, const int8_t *l, const int8_t *r, uint32_t n, const int8_t *ml, const int8_t *mr,
                          uint32_t *pos, uint32_t fill, uint32_t step, int32_t mv)
{
    uint32_t i = 0;
    if (!n) return 0;
    if (!ml || !mv) {
        for (; i < n; i++) { out[2 * i] = (int16_t)(l[i] * 128); out[2 * i + 1] = (int16_t)(r[i] * 128); }
        return n;
    }
    uint32_t p = *pos;
    while (i < n) {
        const uint32_t k = p >> 16;
        out[2 * i] = (int16_t)((l[i] * 64 + ml[k] * mv) * 2);
        out[2 * i + 1] = (int16_t)((r[i] * 64 + mr[k] * mv) * 2);
        i++;
        p += step;
        if (p >= fill << 16) break;
    }
    *pos = p;
    return i;
}

static int kernel_check(void)
{
    static int16_t a[2 * 64], b[2 * 64];
    static int8_t l[64], r[64], m[2 * 40];
    uint32_t s = 12345u;
    for (int i = 0; i < 64; i++) { s = s * 1103515245u + 12345u; l[i] = (int8_t)(s >> 16); r[i] = (int8_t)(s >> 8); }
    for (int i = 0; i < 80; i++) { s = s * 1103515245u + 12345u; m[i] = (int8_t)(s >> 12); }
    for (int t = 0; t < 3; t++) {
        uint32_t pa = 0x1234u * t, pb = pa;
        const int32_t mv = t == 2 ? 0 : 37 + 27 * t;
        const uint32_t na = ahi_mix_c(a, l, r, 64, m, m + 40, &pa, 40, 0xa000u + 0x3000u * t, mv);
        const uint32_t nb = ahi_mix68k(b, l, r, 64, m, m + 40, &pb, 40, 0xa000u + 0x3000u * t, mv);
        if (na != nb || pa != pb || memcmp(a, b, na * 4)) return 0;
    }
    return 1;
}

static ULONG soundfunc(struct Hook *h, struct AHIAudioCtrl *a, struct AHISoundMessage *m)
{
    (void)h; (void)m;
    AHI_SetSound(0, (UWORD)g_dbf, 0, 0, a, AHISF_NONE);    /* the other buffer behind the one just started */
    g_q = g_dbf;
    g_dbf ^= 1;
    Signal((struct Task *)g_task, 1UL << g_sig);
    return 0;
}

static void read_block(void)
{
    g_fill = 0;
    if (!g_play || g_eof) return;
    LONG n = Read(g_fh, g_mb, (LONG)(2 * g_blk));
    if (n < (LONG)(2 * g_blk)) {                       /* the end: from the top again (as the Paula music) */
        Seek(g_fh, MUS_HDR, OFFSET_BEGINNING);
        if (n <= 0) n = Read(g_fh, g_mb, (LONG)(2 * g_blk));
    }
    if (n <= 0) { g_eof = 1; return; }
    if (n < (LONG)(2 * g_blk)) memset(g_mb + n, 0, 2 * g_blk - (uint32_t)n);
    g_fill = g_blk;
}

static void command(void)                            /* snd_music's (snd_68k.s), CTRL_D */
{
    ObtainSemaphore(&mus_sem);
    const long cmd = mus_cmd, blk = mus_newblk;
    const BPTR fh = (BPTR)mus_newfh;
    mus_cmd = 0; mus_newfh = 0;
    ReleaseSemaphore(&mus_sem);
    if (!cmd) { if (fh) Close(fh); return; }
    if (g_fh) Close(g_fh);
    g_fh = 0; g_play = 0; g_fill = 0;
    if (cmd == 1 && fh) {
        g_fh = fh; g_blk = (uint32_t)blk; g_eof = 0; g_pos = 0; g_play = 1;
        read_block();
    }
}

static void fill(int16_t *out)
{
    ObtainSemaphore(&snd_sem);
    mx_render_l(g_l, g_r, AHI_LEN);
    ReleaseSemaphore(&snd_sem);
    const int32_t mv = g_play ? (int32_t)mus_vol : 0;
    uint32_t done = 0;
    while (done < AHI_LEN) {
        const int m = mv && g_fill;
        const uint32_t k = (g_kernel ? ahi_mix68k : ahi_mix_c)(out + 2 * done, g_l + done, g_r + done, AHI_LEN - done,
                                                               m ? g_mb : NULL, m ? g_mb + g_blk : NULL, &g_pos, g_fill,
                                                               g_step, m ? mv : 0);
        done += k;
        if (m && g_pos >= g_fill << 16) {               /* the block played: the next one */
            g_pos -= g_fill << 16;
            read_block();
            if (!g_fill) g_pos = 0;
        }
    }
    if (g_play && g_eof && !g_fill) { Close(g_fh); g_fh = 0; g_play = 0; }
}

static void proc(void)
{
    struct MsgPort *mp = CreateMsgPort();
    struct AHIRequest *io = mp ? (struct AHIRequest *)CreateIORequest(mp, sizeof(struct AHIRequest)) : NULL;
    int16_t *buf[2] = { NULL, NULL };
    static struct Hook hook;
    int dev_open = 0, ok = 0;
    ULONG mixfreq = 0;
    g_task = FindTask(NULL);
    g_sig = AllocSignal(-1);
    if (!io || g_sig < 0) goto out;
    io->ahir_Version = 4;
    if (OpenDevice((CONST_STRPTR)AHINAME, AHI_NO_UNIT, (struct IORequest *)io, 0)) goto out;
    dev_open = 1;
    AHIBase = (struct Library *)io->ahir_Std.io_Device;
    for (int b = 0; b < 2; b++) if (!(buf[b] = AllocVec(AHI_LEN * 4, MEMF_PUBLIC | MEMF_CLEAR))) goto out;
    if (!(g_l = AllocVec(2 * AHI_LEN, MEMF_ANY)) || !(g_mb = AllocVec(2 * MUS_MAXB, MEMF_ANY))) goto out;
    g_r = g_l + AHI_LEN;
    memset(&hook, 0, sizeof hook);
    hook.h_Entry = (void *)HookEntry;
    hook.h_SubEntry = (void *)soundfunc;
    g_dbf = 1;
    g_ctrl = AHI_AllocAudio(AHIA_AudioID, g_mode, AHIA_MixFreq, g_freq, AHIA_Channels, 1, AHIA_Sounds, 2,
                            AHIA_SoundFunc, (ULONG)&hook, TAG_DONE);
    if (!g_ctrl) goto out;
    AHI_ControlAudio(g_ctrl, AHIC_MixFreq_Query, (ULONG)&mixfreq, TAG_DONE);
    if (!mixfreq) mixfreq = g_freq;
    for (int b = 0; b < 2; b++) {
        struct AHISampleInfo si = { AHIST_S16S, buf[b], AHI_LEN };
        if (AHI_LoadSound((UWORD)b, AHIST_DYNAMICSAMPLE, &si, g_ctrl)) goto out;
    }
    g_mixfreq = mixfreq;
    snd_rate = mixfreq;                                 /* (the game's pitches: the mixer's rate) */
    ObtainSemaphore(&snd_sem);
    mx_init(mixfreq);
    ReleaseSemaphore(&snd_sem);
    g_step = (22050u << 16) / (uint32_t)mixfreq;
    g_kernel = kernel_check();
    ok = 1;
    fill(buf[0]);
    fill(buf[1]);
    if (AHI_ControlAudio(g_ctrl, AHIC_Play, TRUE, TAG_DONE)) { ok = 0; goto out; }
    AHI_Play(g_ctrl, AHIP_BeginChannel, 0, AHIP_Freq, mixfreq, AHIP_Vol, 0x10000, AHIP_Pan, 0x8000,
             AHIP_Sound, 0, AHIP_Offset, 0, AHIP_Length, 0, AHIP_EndChannel, 0, TAG_DONE);
    g_state = 1;
    Signal(g_main, 1UL << g_ready);
    while (!g_quit) {
        const ULONG sig = Wait((1UL << g_sig) | SIGBREAKF_CTRL_C | SIGBREAKF_CTRL_D);
        if (g_quit) break;
        if (sig & SIGBREAKF_CTRL_D) command();
        if (sig & (1UL << g_sig)) fill(buf[g_q]);
    }
out:
    if (g_ctrl) { AHI_ControlAudio(g_ctrl, AHIC_Play, FALSE, TAG_DONE); AHI_FreeAudio(g_ctrl); g_ctrl = NULL; }
    if (g_fh) Close(g_fh);
    g_fh = 0; g_play = 0;
    if (dev_open) CloseDevice((struct IORequest *)io);
    if (io) DeleteIORequest((struct IORequest *)io);
    if (mp) DeleteMsgPort(mp);
    for (int b = 0; b < 2; b++) if (buf[b]) FreeVec(buf[b]);
    if (g_l) FreeVec(g_l);
    if (g_mb) FreeVec(g_mb);
    g_l = g_r = NULL; g_mb = NULL;
    if (g_sig >= 0) FreeSignal(g_sig);
    g_sig = -1;
    Forbid();                                           /* (the code stays until the process is gone) */
    g_state = ok ? 2 : -1;
    Signal(g_main, 1UL << g_ready);
}

/* snd_68k.s snd_dev_open: the process started -> it (the music's commands go there too), or NULL (then Paula) */
void *ahi_open(void)
{
    const char *m = getenv("SCREAMER_AHIMODE");
    if (m && *m) g_mode = strtoul(m, NULL, 16);
    const char *f = getenv("SCREAMER_AHIFREQ");
    if (f && atoi(f) >= 8000) g_freq = (ULONG)atoi(f);
    g_main = FindTask(NULL);
    g_ready = AllocSignal(-1);
    if (g_ready < 0) return NULL;
    SetSignal(0, 1UL << g_ready);
    g_quit = 0; g_state = 0;
    struct Task *t = (struct Task *)CreateNewProcTags(NP_Entry, (ULONG)proc, NP_Name, (ULONG)"AmiScreamer AHI",
                                                      NP_Priority, 21, NP_StackSize, 16384, TAG_DONE);
    if (!t) { FreeSignal(g_ready); g_ready = -1; return NULL; }
    while (!g_state) Wait(1UL << g_ready);
    if (g_state < 0) {
        (fprintf)(stderr, "sound: AHI (mode %08lx, %lu Hz) not there -- Paula\n", (unsigned long)g_mode, (unsigned long)g_freq);
        FreeSignal(g_ready); g_ready = -1;
        return NULL;
    }
    printf("sound: AHI, mode %08lx, %lu Hz, 2 x %d pairs, the music in the same stream%s\n", (unsigned long)g_mode,
           (unsigned long)g_mixfreq, AHI_LEN, g_kernel ? "" : " (the sum in C: the vasm one differed)");
    return (void *)g_task;
}

void ahi_close(void)
{
    if (!g_task || g_state != 1) return;
    g_quit = 1;
    Signal((struct Task *)g_task, SIGBREAKF_CTRL_C);
    while (g_state == 1) Wait(1UL << g_ready);
    g_task = NULL;
    if (g_ready >= 0) { FreeSignal(g_ready); g_ready = -1; }
}
