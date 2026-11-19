/*
 * mos_audio.c - THE SOUND ON MORPHOS (the PowerPC build): SDL's audio calls that port/src/sound.c makes (the PC's
 * mixer in C: the effects; the CD's tracks MUSIC/trackNN.raw, amiga/mos_music.c), answered with
 * AHI -- one channel, two dynamic 16-bit stereo sounds in turn (the SoundFunc hook queues the other one), the game's
 * callback filling the one just played; SDL_LockAudio = a semaphore round it.  As snd_ahi.c of the 68k builds, whose
 * mixer is vasm.  SCREAMER_AHIMODE / the launcher's AHIMODE: the audio mode, else AHI's default.
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
#include <SDL.h>

struct Library *AHIBase;
static SDL_AudioSpec g_spec;
static struct SignalSemaphore g_sem;
static struct Task *volatile g_task, *g_main;
static volatile BYTE g_sig = -1;
static BYTE g_ready = -1;
static volatile int g_state, g_quit, g_paused = 1, g_q, g_dbf;
static struct AHIAudioCtrl *g_ctrl;
static ULONG g_mode = AHI_DEFAULT_ID;

static ULONG soundfunc(void)
{
    struct AHIAudioCtrl *a = (struct AHIAudioCtrl *)REG_A2;
    AHI_SetSound(0, (UWORD)g_dbf, 0, 0, a, AHISF_NONE);    /* the other buffer behind the one just started */
    g_q = g_dbf;
    g_dbf ^= 1;
    Signal((struct Task *)g_task, 1UL << g_sig);
    return 0;
}
static const struct EmulLibEntry g_gate = { TRAP_LIB, 0, (void (*)(void))soundfunc };

static void fill(int16_t *buf, int bytes)
{
    if (g_paused) { memset(buf, 0, (size_t)bytes); return; }
    ObtainSemaphore(&g_sem);
    g_spec.callback(g_spec.userdata, (Uint8 *)buf, bytes);
    ReleaseSemaphore(&g_sem);
}

static void proc(void)
{
    struct MsgPort *mp = CreateMsgPort();
    struct AHIRequest *io = mp ? (struct AHIRequest *)CreateIORequest(mp, sizeof(struct AHIRequest)) : NULL;
    int16_t *buf[2] = { NULL, NULL };
    static struct Hook hook;
    int dev_open = 0, ok = 0;
    const int frames = g_spec.samples, bytes = frames * 4;
    g_task = FindTask(NULL);
    g_sig = AllocSignal(-1);
    if (!io || g_sig < 0) goto out;
    io->ahir_Version = 4;
    if (OpenDevice((CONST_STRPTR)AHINAME, AHI_NO_UNIT, (struct IORequest *)io, 0)) goto out;
    dev_open = 1;
    AHIBase = (struct Library *)io->ahir_Std.io_Device;
    for (int b = 0; b < 2; b++) if (!(buf[b] = AllocVec((ULONG)bytes, MEMF_PUBLIC | MEMF_CLEAR))) goto out;
    memset(&hook, 0, sizeof hook);
    hook.h_Entry = (HOOKFUNC)&g_gate;
    g_dbf = 1;
    g_ctrl = AHI_AllocAudio(AHIA_AudioID, g_mode, AHIA_MixFreq, (ULONG)g_spec.freq, AHIA_Channels, 1, AHIA_Sounds, 2,
                            AHIA_SoundFunc, (ULONG)&hook, TAG_DONE);
    if (!g_ctrl) goto out;
    for (int b = 0; b < 2; b++) {
        struct AHISampleInfo si = { AHIST_S16S, buf[b], (ULONG)frames };
        if (AHI_LoadSound((UWORD)b, AHIST_DYNAMICSAMPLE, &si, g_ctrl)) goto out;
    }
    ok = 1;
    fill(buf[0], bytes);
    fill(buf[1], bytes);
    if (AHI_ControlAudio(g_ctrl, AHIC_Play, TRUE, TAG_DONE)) { ok = 0; goto out; }
    AHI_Play(g_ctrl, AHIP_BeginChannel, 0, AHIP_Freq, (ULONG)g_spec.freq, AHIP_Vol, 0x10000, AHIP_Pan, 0x8000,
             AHIP_Sound, 0, AHIP_Offset, 0, AHIP_Length, 0, AHIP_EndChannel, 0, TAG_DONE);
    g_state = 1;
    Signal(g_main, 1UL << g_ready);
    while (!g_quit) {
        const ULONG sig = Wait((1UL << g_sig) | SIGBREAKF_CTRL_C);
        if (g_quit) break;
        if (sig & (1UL << g_sig)) fill(buf[g_q], bytes);
    }
out:
    if (g_ctrl) { AHI_ControlAudio(g_ctrl, AHIC_Play, FALSE, TAG_DONE); AHI_FreeAudio(g_ctrl); g_ctrl = NULL; }
    if (dev_open) CloseDevice((struct IORequest *)io);
    if (io) DeleteIORequest((struct IORequest *)io);
    if (mp) DeleteMsgPort(mp);
    for (int b = 0; b < 2; b++) if (buf[b]) FreeVec(buf[b]);
    if (g_sig >= 0) FreeSignal(g_sig);
    g_sig = -1;
    Forbid();
    g_state = ok ? 2 : -1;
    Signal(g_main, 1UL << g_ready);
}

int SDL_OpenAudio(SDL_AudioSpec *want, SDL_AudioSpec *have)
{
    if (g_state == 1 || !want || !want->callback) return -1;
    const char *how = getenv("SCREAMER_SND");
    if (how && !strcmp(how, "off")) return -1;
    const char *m = getenv("SCREAMER_AHIMODE");
    if (m && *m) g_mode = strtoul(m, NULL, 16);
    g_spec = *want;
    g_spec.format = AUDIO_S16SYS; g_spec.channels = 2;
    if (g_spec.samples < 256) g_spec.samples = 1024;
    g_spec.size = (Uint32)g_spec.samples * 4;
    if (have) *have = g_spec;
    InitSemaphore(&g_sem);
    g_main = FindTask(NULL);
    g_ready = AllocSignal(-1);
    if (g_ready < 0) return -1;
    SetSignal(0, 1UL << g_ready);
    g_quit = 0; g_state = 0; g_paused = 1;
    struct Task *t = (struct Task *)CreateNewProcTags(NP_Entry, (ULONG)proc, NP_Name, (ULONG)"AmiScreamer AHI",
                                                      NP_Priority, 21, NP_StackSize, 65536, NP_CodeType, CODETYPE_PPC, TAG_DONE);
    if (!t) { FreeSignal(g_ready); g_ready = -1; return -1; }
    while (!g_state) Wait(1UL << g_ready);
    if (g_state < 0) {
        (fprintf)(stderr, "sound: AHI (mode %08lx, %d Hz) not there -- no sound\n", (unsigned long)g_mode, g_spec.freq);
        FreeSignal(g_ready); g_ready = -1;
        return -1;
    }
    printf("sound: AHI, mode %08lx, %d Hz, 2 x %d pairs (the C mixer)\n", (unsigned long)g_mode, g_spec.freq, g_spec.samples);
    return 0;
}
void SDL_PauseAudio(int on) { g_paused = on; }
void SDL_LockAudio(void) { if (g_state == 1) ObtainSemaphore(&g_sem); }
void SDL_UnlockAudio(void) { if (g_state == 1) ReleaseSemaphore(&g_sem); }
void SDL_CloseAudio(void)
{
    if (g_state != 1) return;
    g_quit = 1;
    Signal((struct Task *)g_task, SIGBREAKF_CTRL_C);
    while (g_state == 1) Wait(1UL << g_ready);
    if (g_ready >= 0) { FreeSignal(g_ready); g_ready = -1; }
}
