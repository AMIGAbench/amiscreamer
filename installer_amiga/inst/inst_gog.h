/* GOG-Installationsprogramm (Inno Setup 5.6, GOG-Teile) als Installationsquelle, inst_gog.c.
 * Plattformneutral: stdio + zlib. */
#ifndef INST_GOG_H
#define INST_GOG_H
#include <stddef.h>
#include <stdint.h>

typedef struct GogSetup GogSetup;

/* Öffnen und Kopf lesen; NULL bei Fehler, Meldung in err (englisch, kurz) */
GogSetup *gog_open(const char *path, char *err, size_t errn);
void gog_close(GogSetup *g);
int gog_count(const GogSetup *g);
const char *gog_name(const GogSetup *g, int i);          /* z. B. "GFX\GRAF.DAT" */
uint64_t gog_size(const GogSetup *g, int i);             /* entpackte Größe */
int gog_find(const GogSetup *g, const char *name);       /* ohne Groß-/Kleinschreibung, '/' = '\'; -1 = fehlt */

/* Datei i als Strom: out(ctx, daten, n) != 0 bricht ab. MD5 je Teil und Datei geprüft.
 * 0 = ok, 1 = abgebrochen (out), 2 = Lesefehler, 3 = Daten beschädigt (zlib/MD5) */
typedef int (*gog_out_fn)(void *ctx, const uint8_t *p, size_t n);
int gog_read(GogSetup *g, int i, gog_out_fn out, void *ctx);

/* Rückrufe der Abläufe: Fortschritt (what = Dateiname bzw. Spurnummer, pct 0..100; != 0 bricht ab),
 * Verzeichnis anlegen (0 = ok oder vorhanden) */
typedef struct {
    int (*file)(void *ctx, const char *name, int pct);
    int (*track)(void *ctx, int track, int pct, uint32_t sectors);   /* je Block; pct 101 = fertig */
    int (*mkdir)(void *ctx, const char *path);
    void *ctx;
} GogCb;
/* Pfad zusammensetzen (AmigaDOS: kein '/' nach ':' bzw. '/') */
void gog_join(char *o, size_t n, const char *dir, const char *rel);
/* Spieldateien wie der CD-Weg nach dir (STARTH/STARTL ins Hauptverzeichnis, DATA, GFX, TABS, REPLAYS,
 * CONFIG/DEFCTRL.CFG, CONFIG/SETUP.DAT, Piktogramme CONFIG/x.ICO). 0 ok, 1 abgebrochen, 2 lesen, 3 beschädigt, 4 schreiben,
 * 5 Datei fehlt im Installationsprogramm */
int gog_install(GogSetup *g, const char *dir, const GogCb *cb);
/* CD-Musik aus SCREAM.gog (BIN, Spuren laut SCREAM.DAT) -> dir/trackNN.raw (mus_*, wie der CD-Weg). Rückgabe wie
 * gog_install; *ntracks = umgewandelte Spuren */
int gog_music(GogSetup *g, const char *dir, const GogCb *cb, int *ntracks);
#endif
