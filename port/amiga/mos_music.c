/*
 * mos_music.c - THE MUSIC ON MORPHOS (the PowerPC build): the CD's tracks as the installer makes them,
 * MUSIC/trackNN.raw -- "SMUS", the rate, the block B, the length (big-endian longs), then blocks of B bytes left +
 * B bytes right, 8 bits signed -- read as they play, in the mixer's thread (src/sound.c, under its lock), each output
 * frame the average of the track's frames it spans.  Nothing else: no HMI/MIDI music, no other file kinds; the
 * music_* calls of src/sound.c are answered silently.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "../src/port.h"
#include "../src/sound.h"

/* (src/sound.c's HMI music: not on the Amiga) */
void music_frame(float *left, float *right) { (void)left; (void)right; }
int  music_play(const char *dir, int number) { (void)dir; (void)number; return 0; }
void music_stop(void) {}
void music_volume(float v) { (void)v; }
void music_master(float m) { (void)m; }
void fmchip_at(int frame) { (void)frame; }

#define SMUS_MAXB 16384
static FILE *g_smus;
static int g_smus_blk, g_smus_fill, g_smus_pos;
static int8_t g_smus_buf[2 * SMUS_MAXB];
static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }

static struct {
    int playing, loop, track, rate;
    int16_t buf[4096 * 2];          /* as two sides */
    int have, at;                   /* frames in buf, the next one */
    float frac, step;               /* how far into frame `at`; track frames an output frame */
    int paused;                     /* (the race's CD player: PLAY again goes on from here) */
} g_cd;
static float g_cd_volume = 1.0f;    /* the CD's own volume, 0..1 */

void cd_audio_stop(void)
{
    if (g_smus) { fclose(g_smus); g_smus = NULL; }
    memset(&g_cd, 0, sizeof g_cd);
}

/* the file of track n (OS_MUSICDIR, else <data>/MUSIC), or 0 */
int cd_audio_find(int track, char *out, size_t n)
{
    const char *m = getenv("OS_MUSICDIR");
    char d[512];
    snprintf(d, sizeof d, "%s", m && *m ? m : "");
    if (!d[0] || !strchr(d, ':')) {
        char t[512];
        snprintf(t, sizeof t, "%s/%s", os_data_dir(), d[0] ? d : "MUSIC");
        snprintf(d, sizeof d, "%s", t);
    }
    snprintf(out, n, "%s/track%02d.raw", d, track);
    FILE *f = fopen(os_path(out), "rb");
    if (!f) return 0;
    char real[600];
    fclose(f);
    snprintf(real, sizeof real, "%s", os_path(out));
    snprintf(out, n, "%s", real);
    return 1;
}

/* track n from its start, round and round if `loop`; 0 if there is no file for it */
int cd_audio_play(int track, int loop, int out_rate)
{
    char path[600];
    uint8_t h[16];
    cd_audio_stop();
    if (!cd_audio_find(track, path, sizeof path)) {
        if (getenv("OS_MUSICLOG")) printf("cd: no file for track %d\n", track);
        return 0;
    }
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    if (fread(h, 1, 16, f) != 16 || memcmp(h, "SMUS", 4) || !be32(h + 8) || be32(h + 8) > SMUS_MAXB || be32(h + 4) < 1000) {
        fclose(f);
        fprintf(stderr, "cd: %s cannot be read\n", path);
        return 0;
    }
    g_smus = f; g_smus_blk = (int)be32(h + 8); g_smus_fill = g_smus_pos = 0;
    g_cd.playing = 1; g_cd.rate = (int)be32(h + 4);
    g_cd.loop = loop; g_cd.track = track;
    g_cd.step = (float)g_cd.rate / (float)out_rate;
    if (getenv("OS_MUSICLOG")) printf("cd: track %d from %s (%d a second)%s\n", track, path, g_cd.rate, loop ? ", round and round" : "");
    return 1;
}

int cd_audio_track(void) { return g_cd.playing ? g_cd.track : 0; }
void cd_audio_pause(int on) { g_cd.paused = on != 0; }
int cd_audio_paused(void) { return g_cd.playing && g_cd.paused; }
void cd_audio_volume(float v) { g_cd_volume = v < 0.0f ? 0.0f : v > 1.0f ? 1.0f : v; }

/* more of the track into buf; 0 at its end (when not looping) */
static int cd_decode(void)
{
    for (int tries = 0; tries < 2; tries++) {
        if (g_smus_pos >= g_smus_fill) {                 /* the next block: B left, B right */
            g_smus_pos = g_smus_fill = 0;
            if (fread(g_smus_buf, 1, (size_t)(2 * g_smus_blk), g_smus) == (size_t)(2 * g_smus_blk)) g_smus_fill = g_smus_blk;
        }
        if (g_smus_pos < g_smus_fill) {
            int k = g_smus_fill - g_smus_pos;
            if (k > 4096) k = 4096;
            for (int i = 0; i < k; i++) {
                g_cd.buf[2 * i] = (int16_t)(g_smus_buf[g_smus_pos + i] * 256);
                g_cd.buf[2 * i + 1] = (int16_t)(g_smus_buf[g_smus_blk + g_smus_pos + i] * 256);
            }
            g_smus_pos += k;
            g_cd.have = k; g_cd.at = 0;
            return 1;
        }
        if (!g_cd.loop) return 0;
        fseek(g_smus, 16, SEEK_SET);                     /* the end: from the start again */
        g_smus_fill = g_smus_pos = 0;
    }
    return 0;
}

/* one output frame, added to *left / *right at `gain` (the mixer's thread) */
void cd_audio_frame(float *left, float *right, float gain)
{
    if (!g_cd.playing || g_cd.paused) return;
    float need = g_cd.step, l = 0.0f, r = 0.0f;
    while (need > 0.0f) {
        if (g_cd.at >= g_cd.have && !cd_decode()) { cd_audio_stop(); return; }
        float part = 1.0f - g_cd.frac;
        if (part > need) part = need;
        l += (float)g_cd.buf[2 * g_cd.at] * part;
        r += (float)g_cd.buf[2 * g_cd.at + 1] * part;
        need -= part;
        g_cd.frac += part;
        if (g_cd.frac >= 0.9999f) { g_cd.frac = 0.0f; g_cd.at++; }
    }
    const float k = gain * g_cd_volume / g_cd.step;
    *left += l * k;
    *right += r * k;
}
