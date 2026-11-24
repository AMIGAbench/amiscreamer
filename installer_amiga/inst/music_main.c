/* screamer_music (Linux/PC): CD-Musik von Screamer nach trackNN.raw wie screamer_inst auf dem Amiga (gleicher Kern
 * inst_core.c / inst_gog.c, gleiche Ausgabe). Aufgerufen von installer_amiga/amiscreamer_music.sh.
 *   screamer_music wav <trackNN.wav> <trackNN.raw>     gerippte CD-Spur (44,1 kHz, 16 Bit, Stereo)
 *   screamer_music gog <setup_screamer_*.exe> <ziel>   alle Spuren aus dem GOG-Installationsprogramm
 * cc -O2 -o screamer_music music_main.c inst_core.c inst_gog.c lzmadec.c md5.c -lz -lm */
#include "inst_core.h"
#include "inst_gog.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static int wout(void *ctx, const uint8_t *p, size_t n) { return fwrite(p, 1, n, (FILE *)ctx) != n; }

static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

/* WAV als Strom: "data"-Abschnitt suchen, dann blockweise an mus_feed */
static int cmd_wav(const char *in, const char *out)
{
    FILE *f = fopen(in, "rb");
    if (!f) {
        fprintf(stderr, "Cannot read %s\n", in);
        return 1;
    }
    uint8_t h[12], c[8];
    if (fread(h, 1, 12, f) != 12 || memcmp(h, "RIFF", 4) || memcmp(h + 8, "WAVE", 4)) {
        fprintf(stderr, "%s is no WAV file\n", in);
        fclose(f);
        return 1;
    }
    uint32_t len = 0;
    int fmt_ok = 0;
    for (;;) {
        if (fread(c, 1, 8, f) != 8) {
            fprintf(stderr, "%s: no audio data\n", in);
            fclose(f);
            return 1;
        }
        len = le32(c + 4);
        if (!memcmp(c, "fmt ", 4) && len >= 16) {
            uint8_t fm[16];
            if (fread(fm, 1, 16, f) != 16)
                break;
            /* PCM, 2 Kanäle, 44100 Hz, 16 Bit */
            fmt_ok = fm[0] == 1 && fm[2] == 2 && le32(fm + 4) == 44100 && fm[14] == 16;
            fseek(f, (long)(len - 16 + (len & 1)), SEEK_CUR);
        } else if (!memcmp(c, "data", 4))
            break;
        else
            fseek(f, (long)(len + (len & 1)), SEEK_CUR);
    }
    if (!fmt_ok) {
        fprintf(stderr, "%s: expected 44.1 kHz, 16 bit, stereo (CD audio)\n", in);
        fclose(f);
        return 1;
    }
    FILE *o = fopen(out, "wb");
    if (!o) {
        fprintf(stderr, "Cannot write %s\n", out);
        fclose(f);
        return 1;
    }
    MusConv *m = mus_begin(len / 4, wout, o);
    static uint8_t buf[4 * 16384];
    uint32_t left = len / 4 * 4;
    int err = !m;
    while (!err && left) {
        size_t n = left < sizeof buf ? left : sizeof buf;
        if (fread(buf, 1, n, f) != n) {          /* kürzer als angegeben: Rest ist Stille (mus_end) */
            break;
        }
        err = mus_feed(m, buf, n / 4);
        left -= (uint32_t)n;
    }
    if (m)
        err |= mus_end(m);
    err |= fclose(o) != 0;
    fclose(f);
    if (err) {
        fprintf(stderr, "Write error %s\n", out);
        remove(out);
    }
    return err;
}

static int cb_mkdir(void *ctx, const char *p)
{
    (void)ctx;
    return mkdir(p, 0755) && errno != EEXIST;
}
static int cb_track(void *ctx, int t, int pct, uint32_t sec)
{
    static int last = -1;
    (void)ctx;
    if (pct > 100) {
        printf("\rTrack %02d: done (%02u:%02u)\n", t, (unsigned)(sec / 75 / 60), (unsigned)(sec / 75 % 60));
        last = -1;
    } else if (pct / 5 != last) {
        last = pct / 5;
        printf("\rTrack %02d: %3d %%", t, pct);
    }
    fflush(stdout);
    return 0;
}

static int cmd_gog(const char *exe, const char *dir)
{
    char err[128];
    GogSetup *g = gog_open(exe, err, sizeof err);
    if (!g) {
        fprintf(stderr, "Cannot use the GOG installer: %s\n", err);
        return 1;
    }
    cb_mkdir(NULL, dir);
    GogCb cb = {NULL, cb_track, cb_mkdir, NULL};
    int n = 0, rc = gog_music(g, dir, &cb, &n);
    gog_close(g);
    static const char *const msg[] = {"", "aborted", "read error", "installer damaged (checksum)",
                                      "write error", "no music in the installer"};
    if (rc)
        fprintf(stderr, "\nError: %s\n", msg[rc > 0 && rc < 6 ? rc : 2]);
    return rc != 0;
}

int main(int argc, char **argv)
{
    if (argc == 4 && !strcmp(argv[1], "wav"))
        return cmd_wav(argv[2], argv[3]);
    if (argc == 4 && !strcmp(argv[1], "gog"))
        return cmd_gog(argv[2], argv[3]);
    fprintf(stderr, "Usage: screamer_music wav <trackNN.wav> <trackNN.raw> | gog <setup.exe> <dir>\n");
    return 2;
}
