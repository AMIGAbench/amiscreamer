/*
 * snd_load.c - the Amiga's sound: what port/src/sound.c loads (the .RAW samples, the SOUND_FX lists of SFXSBASE.DTR
 * and MAPnDAT.DTR) into snd_tab of amiga/sys/snd_68k.s, which plays them (the mixer, Paula, the music).
 * OS_NOSOUND: no device.  OS_SNDWAV=<file> (the qemu test): no device, the mix (amiga/sys/mixer_68k.s at 15625 Hz,
 * 8 bit) goes into a WAV file, advanced by snd_render.
 */
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "../src/sound.h"
#include "../src/port.h"

typedef struct {
    uint8_t *data;
    int32_t  len;
    float    volume;                 /* 0..1 */
    int32_t  loop, loop_start, loop_len;
    char     name[16];
} snd_sample;
_Static_assert(sizeof(snd_sample) == 40, "snd_68k.s SM_SIZE");

extern snd_sample snd_tab[SND_MAX];
extern int32_t    snd_n;
extern uint32_t   snd_rate;
int  snd_dev_open(void);
void snd_halt(void);
void snd_set_dir(const char *dir);
void mx_init(uint32_t rate);
void amiga_audio_close(void);
int  mx_render_l(int8_t *left, int8_t *right, uint32_t n);

static char  g_dir[512];
static int   g_open;
static FILE *g_wav;
static long  g_wav_frames;

extern uint32_t snd_played, mus_played;
int snd_music_on(void);
static void snd_report(void)
{
    printf("sound: %lu buffers played, music %lu blocks\n", (unsigned long)snd_played, (unsigned long)mus_played);
    amiga_audio_close();
}

static uint8_t *load_raw(const char *name, int32_t *len)
{
    char file[700], up[32];
    int i = 0;
    for (; name[i] && i < 31; i++) up[i] = (char)toupper((unsigned char)name[i]);
    up[i] = 0;
    snprintf(file, sizeof file, "%s/%s.RAW", g_dir, up);
    FILE *f = fopen(file, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *d = malloc((size_t)(n > 0 ? n : 1));
    if (n <= 0 || fread(d, 1, (size_t)n, f) != (size_t)n) { free(d); fclose(f); return NULL; }
    fclose(f);
    *len = (int32_t)n;
    return d;
}

int snd_add(const char *name, float volume, int loop, int loop_start, int loop_len)
{
    if (snd_n >= SND_MAX) return -1;
    snd_sample *s = &snd_tab[snd_n];
    memset(s, 0, sizeof *s);
    snprintf(s->name, sizeof s->name, "%s", name);
    s->data = load_raw(name, &s->len);
    s->volume = volume;
    s->loop = loop;
    s->loop_start = loop_start;
    s->loop_len = loop_len;
    if (!s->data) (fprintf)(stderr, "sound: no sample %s\n", name);
    return snd_n++;
}

int snd_find(const char *name)
{
    for (int i = 0; i < snd_n; i++)
        if (!strcasecmp(snd_tab[i].name, name)) return i;
    return -1;
}

int snd_add_list(const char *list_file)
{
    int first = snd_n;
    FILE *f = fopen(list_file, "r");
    if (!f) return first;
    char line[256];
    int in = 0;
    while (fgets(line, sizeof line, f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (!in) { if (!strncmp(p, "SOUND_FX", 8)) in = 1; continue; }
        if (!strncmp(p, "END_LIST", 8)) break;
        char name[32];
        unsigned vol = 0;
        int loop = 0, ls = 0, ll = 0;
        if (sscanf(p, "s%31s x%x d%d d%d d%d", name, &vol, &loop, &ls, &ll) == 5)
            snd_add(name, (float)(vol & 0xffff) / 32767.0f, loop, ls, ll);
    }
    fclose(f);
    return first;
}

#if defined(AMIGA) && !defined(AMIGA_NULL)
extern long snd_ahi_on;                         /* (snd_68k.s) */
static int snd_ahi_running(void) { return snd_ahi_on != 0; }
/* the music's drawer: OS_MUSICDIR (--music: as given when it has a volume or is there from the current
   directory, else under the data), else <data>/MUSIC */
/* a drawer and a name joined as AmigaDOS wants them: no '/' after a volume ("PROGDIR:" + "MUSIC" = "PROGDIR:MUSIC";
   "PROGDIR:/MUSIC" would be the drawer ABOVE) -- the music is opened by snd_68k.s with dos Open, not through the
   C library's fopen that amiga_path.c mends */
static void dir_join(char *out, size_t n, const char *dir, const char *name)
{
    const size_t l = strlen(dir);
    snprintf(out, n, "%s%s%s", dir, l && (dir[l - 1] == ':' || dir[l - 1] == '/') ? "" : "/", name);
}
static const char *music_dir(void)
{
    static char dir[700];
    const char *m = getenv("OS_MUSICDIR");
    if (m && *m) {
        FILE *t = NULL;
        char probe[760];
        snprintf(probe, sizeof probe, "%s/track02.raw", m);
        if (strchr(m, ':') || (t = fopen(probe, "rb")) != NULL) { if (t) fclose(t); snprintf(dir, sizeof dir, "%s", m); return dir; }
        dir_join(dir, sizeof dir, os_data_dir(), m);
        return dir;
    }
    dir_join(dir, sizeof dir, os_data_dir(), "MUSIC");
    return dir;
}
#endif

int snd_init(const char *sound_dir, const char *list_file)
{
    snd_halt();                                 /* (no voice may play a sample the part before let go) */
    snprintf(g_dir, sizeof g_dir, "%s", sound_dir);
    snd_n = 0;
    snd_add_list(list_file);
    if (getenv("OS_NOSOUND")) return snd_n;
    if (getenv("OS_SNDWAV")) {
        if (!g_wav && (g_wav = fopen(getenv("OS_SNDWAV"), "wb"))) {
            uint8_t hdr[44] = { 0 };
            fwrite(hdr, 1, 44, g_wav);
            mx_init(snd_rate);
        }
        return snd_n;
    }
#if defined(AMIGA) && !defined(AMIGA_NULL)
    if (!g_open) {
        /* SCREAMER_SND (the launcher's SOUND=, oldargs.c): paula (the default), ahi, off */
        const char *how = getenv("SCREAMER_SND");
        if (how && !strcasecmp(how, "off")) { printf("sound: off (SCREAMER_SND=off)\n"); return snd_n; }
        extern void *snd_ahi_open, *snd_ahi_close;          /* (snd_68k.s: AHI's functions when it is wanted) */
        extern void *ahi_open(void);
        extern void ahi_close(void);
        const int ahi = how && !strcasecmp(how, "ahi");
        snd_ahi_open = ahi ? (void *)ahi_open : NULL;
        snd_ahi_close = ahi ? (void *)ahi_close : NULL;
        snd_set_dir(music_dir());
        g_open = snd_dev_open() == 0;
        if (g_open) {
            atexit(snd_report);                 /* (the processes ended before the program's code goes) */
            if (ahi && snd_ahi_running())
                printf("sound: music: %s/trackNN.raw in the AHI stream\n", music_dir());
            else
                printf("sound: Paula, %lu Hz, 3 x 512 samples; music: %s/trackNN.raw on channels 2/3%s\n",
                       (unsigned long)snd_rate, music_dir(), snd_music_on() ? "" : " -- no music (audio.device)");
        }
        if (!g_open) (fprintf)(stderr, "sound: audio.device (channels 0/1) not there -- no sound\n");
    }
#endif
    return snd_n;
}

/* the test: the mix advanced by `seconds` into the WAV file (8 bit unsigned, stereo, snd_rate) */
void snd_render(float seconds)
{
    if (!g_wav) return;
    static int8_t l[1024], r[1024];
    static uint8_t out[2048];
    static float carry;
    float want = seconds * (float)snd_rate + carry;
    int frames = (int)want & ~7;
    carry = want - (float)frames;
    while (frames > 0) {
        int n = frames > 1024 ? 1024 : frames;
        mx_render_l(l, r, (uint32_t)n);
        for (int i = 0; i < n; i++) { out[2 * i] = (uint8_t)(l[i] + 128); out[2 * i + 1] = (uint8_t)(r[i] + 128); }
        fwrite(out, 2, (size_t)n, g_wav);
        g_wav_frames += n;
        frames -= n;
    }
}

static void put32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }

void snd_close(void)
{
    snd_halt();
    /* the song stops with the part, as the game's menu_unload (0x2a1b0) and race unload (0x156a8) cd_stop and the PC's
       closed device: no music over the loading picture, none while the menu or the next race is set up */
    snd_music(NULL, 0);
    if (g_wav) {
        uint8_t h[44];
        const uint32_t bytes = (uint32_t)g_wav_frames * 2;
        memcpy(h, "RIFF", 4); put32(h + 4, 36 + bytes); memcpy(h + 8, "WAVEfmt ", 8); put32(h + 16, 16);
        h[20] = 1; h[21] = 0; h[22] = 2; h[23] = 0; put32(h + 24, snd_rate); put32(h + 28, snd_rate * 2);
        h[32] = 2; h[33] = 0; h[34] = 8; h[35] = 0; memcpy(h + 36, "data", 4); put32(h + 40, bytes);
        fseek(g_wav, 0, SEEK_SET);
        fwrite(h, 1, 44, g_wav);
        fclose(g_wav);
        g_wav = NULL;
    }
}

int snd_open(void) { return g_open || g_wav; }
