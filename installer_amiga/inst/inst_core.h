/* Installer-Kern (plattformneutral): Archiv, Titellogo für den Starter, Konfigurationsdateien (wie Setup/DOS-
 * Installation), CD-Musik -> trackNN.raw als Strom. */
#ifndef SCREAMER_INST_CORE_H
#define SCREAMER_INST_CORE_H
#include <stddef.h>
#include <stdint.h>

/* Eintrag aus einem Archiv (*.DAT) entpacken; NULL = fehlt/Fehler, *n = Größe; Freigabe mit free */
uint8_t *arc_load(const uint8_t *arc, size_t arcn, const char *name, size_t *n);

/* Titellogo des Starters (installer_amiga/launcher/launcher.c LogoBlock): Größe */
enum { LOGO_MAXW = 44, LOGO_MAXH = 320, LOGO_MAXC = 64,
       LOGO_BLOCK = 8 + 12 + 3 * LOGO_MAXC + LOGO_MAXW * LOGO_MAXH + 8 };
/* Logo aus GRAF.DAT (MENUL.SPR Sprites 15/14, MENU1L.PCX) in einen Block (Big Endian, tag "SCRLOGO1"); 0 = ok */
int logo_build(const uint8_t *graf, size_t grafn, uint8_t blk[LOGO_BLOCK]);

/* CONFIG/SETUP.CFG (144 Byte, Vorgaben wie die ausgelieferte Datei bzw. src/setup/setup.c) */
void setup_cfg(uint8_t out[0x90]);
/* SCREAMER.CFG wie die DOS-Installation (Pfade, die der Port auf das Datenverzeichnis abbildet) */
extern const char screamer_cfg[];

/* CD-Musik: 44,1 kHz, 16 Bit, Stereo (Little Endian wie CD-DA) -> SMUS-Strom (Kopf, Blöcke L/R zu 4096 Byte).
 * mus_begin mit der Zahl der Eingangs-Abtastpaare (aus dem Inhaltsverzeichnis), dann mus_feed beliebig oft, am Ende
 * mus_end. Ausgabe über die Rückruffunktion (Bytes in Reihenfolge der Datei). */
typedef int (*mus_out_fn)(void *ctx, const uint8_t *p, size_t n);
typedef struct MusConv MusConv;
MusConv *mus_begin(uint32_t nin, mus_out_fn out, void *ctx);
int mus_feed(MusConv *m, const uint8_t *pcm, size_t pairs);
int mus_end(MusConv *m);                    /* schreibt den Rest, gibt frei; 0 = ok */
void mus_abort(MusConv *m);                 /* Abbruch: nur freigeben (mus_end rechnete die ganze Spur zu Ende) */
#endif
