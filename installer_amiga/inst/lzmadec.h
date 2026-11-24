/* LZMA1-Decoder für den Kopf von Inno-Setup-Installern (GOG), lzmadec.c */
#ifndef LZMADEC_H
#define LZMADEC_H
#include <stddef.h>
#include <stdint.h>

/* props: 5 Byte (lc/lp/pb, Wörterbuchgröße, hier unbenutzt: ganze Ausgabe im Speicher). Endet an der Endmarke oder am
 * Ende der Eingabe. *out mit malloc (Aufrufer gibt frei). 0 = ok, < 0 Fehler. */
int lzma_decode(const uint8_t *props, const uint8_t *in, size_t inlen, uint8_t **out, size_t *outlen);
#endif
