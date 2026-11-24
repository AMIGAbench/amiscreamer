; span_68k.s - THE ROW RASTERISER of the Amiga's renderer (OpenScreamer, port/amiga/render/).
; "Zeilen-Rasterer (Treuestufe C)": raster_span_poly and its macros, the 68040/68060 form (-DCPU060).  The C reference with the
; same arithmetic is span.c (span_poly_c); tools/qemu_test.sh compares the two byte for byte.
; vasmm68k_mot -quiet -no-opt -m68060 -DCPU060=1 -Fhunk (Amiga) / -Felf (m68k Linux, qemu)
	include	"m64.i"

; -DCPU060 (68040/68060-Bau): dieselben Kerne ohne AMMX/TEX8/64-Bit-mul/div. K68 = 68k-Ersatz der AMMX-Makros
; (Emulatorbau TEX8EMU bzw. CPU060); TEX8R, Kehrwertprodukte und Speicherroutinen haben eigene 060-Fassungen.
	ifd	CPU060
	machine	68060
K68	set	1
	else
	machine	68080
	endif
	ifd	TEX8EMU
K68	set	1
	endif
BSWAP		macro					; \1 = Dn: Bytefolge umkehren (Little Endian <-> Wert)
	ifd	MOVEX
	movex.l	\1,\1					; 68080 (vprobe --movex: 1,2 statt 3,2 Takte)
	else
	ror.w	#8,\1
	swap	\1
	ror.w	#8,\1
	endif
	endm
	section	code,code

; Abschnittsmessung des Polygonwegs (nur Messbau: VASM_EXTRA=-DPMKON): PMK n addiert die Takte seit dem letzten Punkt
; (Taktzähler im User-Modus) zu pm_sum[n] und zählt pm_cnt[n]; Ausgabe "poly:" in prof.c. Ohne PMKON leer.
PMK	macro
	ifd	PMKON
	movem.l	d0-d1,-(sp)
	dc.w	$4e7a,$0809			; movec ccc,d0 (Takte)
	move.l	d0,d1
	sub.l	pm_last,d1
	move.l	d0,pm_last
	add.l	d1,pm_sum+4*\1
	addq.l	#1,pm_cnt+4*\1
	movem.l	(sp)+,d0-d1
	endif
	endm
PMA	macro					; Messbau: Takt und Pipe-Zähler vor der Pixelschleife merken
	ifd	PMKON
	move.l	d0,-(sp)
	dc.w	$4e7a,$0809
	move.l	d0,pm_t0
	move.l	(sp)+,d0
	endif
	endm
PMB	macro					; Messbau: Takte/Befehle der Pixelschleife der Art \1 aufsummieren (nach PMA)
	ifd	PMKON
	tst.l	pm_t0
	beq	pmb\@
	move.l	d0,-(sp)
	dc.w	$4e7a,$0809
	sub.l	pm_t0,d0
	add.l	d0,pm_pc+4*\1
	clr.l	pm_t0
	move.l	(sp)+,d0
pmb\@:
	endif
	endm
PMZ	macro					; Messbau: Zeile der Art \1 mit n = d6 + 1 Pixeln zählen
	ifd	PMKON
	addq.l	#1,pm_rw+4*\1
	move.l	d6,-(sp)
	addq.l	#1,d6
	add.l	d6,pm_px+4*\1
	move.l	(sp)+,d6
	endif
	endm
PMK0	macro					; Bezugspunkt setzen
	ifd	PMKON
	movem.l	d0-d1,-(sp)
	dc.w	$4e7a,$0809
	move.l	d0,pm_last
	movem.l	(sp)+,d0-d1
	endif
	endm

; ---------------------------------------------------------------- K4 / K4K: schlanke Spaltenvorbereitung für TEX8
; Statt über die Original-Register (e, st, u, cu) direkt:
;   P = (UB-UA)*T, Q = (VB-VA)*T (TEX: UA, VA vorher & ~15)
;   Au = UA << 8, Av = VA << 8, DU = P >> 7 (+1 wenn W = L-1), DV = (Q >> 7) & ~$ff     (je modulo 2^24)
;   W = ((VA & $ffff) + (L-1) * ((Q >> 15) & $ffff)) >> 16; W weder 0 noch L-1 -> Originalschleife.
; tex8.256 (a2,(a6,a5)),d7: Au = a5, Av = a6, Ziel d7 (nur Low-Byte wird ersetzt). Zielzeile per muls (Abstand 640).
; Register: a0 Satz, a1 colbase, a2 Textur, a3 T, a4 Ziel, a5 Au, a6 Av; d0 L/Zähler, d2 DU/P, d3 DV/Q, d4 UA, d5 VA

	ifd	K68
TEX8B	macro
	movem.l	d1-d2,-(sp)
	move.l	a6,d1
	swap	d1
	and.l	#$ff,d1
	lsl.l	#8,d1
	move.l	a5,d2
	swap	d2
	and.l	#$ff,d2
	or.l	d2,d1
	move.b	(a2,d1.l),d7
	movem.l	(sp)+,d1-d2
	endm
	else
TEX8B	macro
	dc.w	$fe32,$573e,$e850		; tex8.256 (a2,(a6,a5)),d7
	endm
	endif

; gemeinsamer Teil nach den Grenzprüfungen: d0 = L, d1 = a; erwartet d2..d5 = UB VB UA VA (ggf. maskiert)
; Ergebnis: Sprung nach \1 bei gemischtem Übertrag, sonst a5/a6/d2/d3 = Au/Av/DU/DV, a4 = Ziel
SLIM	macro
	muls.l	#640,d1
	lea	(a1,d1.l),a4			; Ziel
	move.l	(a3,d0.l*4),d6			; T
	sub.l	d4,d2
	sub.l	d5,d3
	muls.l	d6,d2				; P
	muls.l	d6,d3				; Q
	move.l	d3,d1
	add.l	d1,d1
	swap	d1				; (Q >> 15) & $ffff im Low-Word
	move.l	d0,d6
	subq.l	#1,d6
	mulu.w	d1,d6				; (L-1) * s
	moveq	#0,d1
	move.w	d5,d1
	add.l	d1,d6
	clr.w	d6
	swap	d6				; W
	beq	.w0\@
	addq.l	#1,d6
	cmp.l	d0,d6
	bne	\1
	moveq	#1,d6
	bra	.w\@
.w0\@:	moveq	#0,d6
.w\@:	asr.l	#7,d2
	add.l	d6,d2				; DU
	asr.l	#7,d3
	clr.b	d3				; DV
	lsl.l	#8,d4
	movea.l	d4,a5				; Au
	lsl.l	#8,d5
	movea.l	d5,a6				; Av
	endm

; Originalschleife für gemischte Überträge: aus P (d2), Q (d3), UA (d4), VA (d5) die Original-Register bilden
ORIG	macro
	move.l	d2,d6
	rol.l	#8,d6
	rol.l	#1,d6				; a
	move.b	d6,d7				; cu
	move.l	d3,d2
	add.l	d2,d2
	swap	d2				; d (Low-Word)
	move.w	d2,d6
	move.l	d6,d2				; st = a.hi | d.lo
	move.l	d4,d3
	lsl.l	#8,d3
	swap	d3
	move.w	d5,d3				; e
	lsr.w	#8,d4				; u
	endm



; ---------------------------------------------------------------- Zeilen-Rasterer (Treuestufe C), 68080 -- NEUFASSUNG
; void raster_span_poly(const SpanCtx *c): gleiche Rechnung wie span_poly_c/span_row in span.c (C-Referenz,
; Prüfwerte --span 1), kind 0 TEX/ENV, 1 KEY, 2 FLAT, 3 ohne Pixel (Messung), 4 SMG, 5 Schatten.
; Voraussetzungen wie bisher (prüft der Aufrufer): Textur >= 64 KB ab Frame, Zielpuffer fasst vrows Zeilen,
; Ecken im Bild (|dx| < 32768).
; SpanCtx: 0 P (SV x,y,u,v je 16 Byte), 4 np, 8 kind, 12 tp, 16 base (buf+origin), 20 pitch, 24 xmax, 28 vrows,
;          32 rcp (65536/w, 1024 Einträge), 36 color, 40 smg, 44 remap, 48 ramk
;
; Umbau gegenüber der alten Fassung (080-Regeln: 1 Datencache-Zugriff je Takt für alle Pipes, mul/div/AMMX nur ANTON):
;  - Segmente statt Zeilenprüfungen: n = min(lend, rend, ybot, vrows) - y einmal je Kantenwechsel, Zeilenende per
;    cmpa.l S_AEND(sp),a0 (kein Y/YBOT/LEND/REND/GRD/VROWS-Vergleich und kein addq.l #1,Z_Y(a3)-RMW je Zeile).
;    Zeilen mit y < 0 werden ohne Kopf in einem Schritt übersprungen (k * Schritt, modulo 2^32 = k Additionen).
;  - je Art eine eigene Zeilenschleife (Makro ZROW), keine Art-Verteilung je Zeile.
;  - du/dv mit 64-Bit-muls.l direkt aus der Kehrwerttabelle (bits 16..47 = mulsh16 bitgleich) statt 2x MULSH16
;    (4 Multiplikationen + 14 ALU-Befehle).
;  - kein Speicher-RMW: RU/RV laden-addieren-speichern ohne Rücklesen in derselben Zeile.
;  - Lokale über sp, a3 frei für dv (adda.l a3,a6), d4 frei als Packregister.
;  - TEX-Kern: zwei unabhängige Texelketten d6/d7 (swap-Packung, Bytes 1/3 bleiben 0) statt tex8->lsl->tex8-Kette.
;  - KEY-Kern: zwei Texel je Durchlauf in d6/d7.

; \1 = (\1 * \2) >> 16 (Bits 16..47 des 64-Bit-Produkts; wie mulsh16 in span.c, dort \2 in 0..65536), \3 Hilfsregister
; (nur noch in den Kantenwechseln)
MULSH16	macro
	MULS64	\2,\3,\1
	swap	\1
	swap	\3
	move.w	\1,\3
	move.l	\3,\1
	endm

; tex8.256 (a2,(a6,a5)),d\1 (\1 = Registernummer 0..7; Ersatz für Emulatoren nur für \1 = 3..7)
	ifd	CPU060
TEX8R	macro					; 68060: Index (v >> 16 & $ff) << 8 | (u >> 16 & $ff), Hilfsregister d2/d3
	move.l	a6,d2				; (in ZROW/ZROWF um die Pixel gesichert: S_SV2/S_SV3). Vorspannung (SV23):
	move.l	a5,d3				; a6 = v + 2^23, a2 = Textur + 32768 -> Wortindex (v' >> 8).w mit u im
	lsr.l	#8,d2				; unteren Byte = idx ^ $8000, vorzeichenerweitert idx - 32768: a2 + idx,
	swap	d3				; ohne and.l
	move.b	d3,d2
	move.b	(a2,d2.w),d\1
	endm
IDX060	macro					; \1 = Wortindex des aktuellen Texels (wie TEX8R), u/v weiter; \2 Hilfsregister
	move.l	a6,\1
	move.l	a5,\2
	lsr.l	#8,\1
	swap	\2
	adda.l	a1,a5
	adda.l	a3,a6
	move.b	\2,\1
	endm
	else
	ifd	TEX8EMU
TEX8R	macro
	movem.l	d1-d2,-(sp)
	move.l	a6,d1
	swap	d1
	and.l	#$ff,d1
	lsl.l	#8,d1
	move.l	a5,d2
	swap	d2
	and.l	#$ff,d2
	or.l	d2,d1
	move.b	(a2,d1.l),d\1
	movem.l	(sp)+,d1-d2
	endm
	else
TEX8R	macro
	dc.w	$fe32,$503e+(\1<<8),$e850
	endm
	endif
	endif

; KEY mit STOREM3 (Bytemodus: schreibt nur Bytes <> 0). Nach je 4 Texeln in zwei Ketten (d6 = . p0 . p2,
; d7 = . p1 . p3 im unteren Langwort) packt KPK sie in die Bytes 0..3 von e21 (\1 = 0) bzw. e22 (\1 = 1); KST
; fügt beide zu p0..p7 zusammen und schreibt sie maskiert nach (a4). Hohe E-Register: AmigaOS sichert AMMX nicht,
; andere Programme benutzen eher e0.. (schlimmstenfalls 8 falsche Pixel für ein Bild).
	ifd	K68
KPK	macro					; Ersatz: Puffer zk_buf + 4 * (\1 - 1)
	move.l	a0,-(sp)
	move.l	d6,-(sp)
	lea	zk_buf+4*\1-4,a0
	swap	d6
	move.b	d6,(a0)				; p0
	swap	d6
	move.b	d6,2(a0)			; p2
	swap	d7
	move.b	d7,1(a0)			; p1
	swap	d7
	move.b	d7,3(a0)			; p3
	move.l	(sp)+,d6
	move.l	(sp)+,a0
	endm
KST	macro
	move.l	a0,-(sp)
	move.l	d4,-(sp)
	lea	zk_buf,a0
	moveq	#7,d4
zkl\@:	tst.b	(a0)
	beq	zkn\@
	move.b	(a0),(a4)
zkn\@:	addq.l	#1,a0
	addq.l	#1,a4
	dbra	d4,zkl\@
	subq.l	#8,a4
	move.l	(sp)+,d4
	move.l	(sp)+,a0
	endm
KSTP	macro
	KST
	addq.l	#8,a4
	endm
KSTA	macro					; Ersatz: 8 Bytes zk_buf -> (a4)
	move.l	zk_buf,(a4)
	move.l	zk_buf+4,4(a4)
	endm
KSTAP	macro
	move.l	zk_buf,(a4)+
	move.l	zk_buf+4,(a4)+
	endm
ZKMASK	macro					; Ersatz: die ersten m = d4 Bytes von zk_buf, nur die <> 0
	move.l	a0,-(sp)
	move.l	d4,-(sp)
	lea	zk_buf,a0
	subq.l	#1,d4
zkk\@:	tst.b	(a0)
	beq	zkj\@
	move.b	(a0),(a4)
zkj\@:	addq.l	#1,a0
	addq.l	#1,a4
	dbra	d4,zkk\@
	move.l	(sp)+,d4
	suba.l	d4,a4
	move.l	(sp)+,a0
	endm
KSTM	macro					; Ersatz: Byte i nach (a4)+i, wenn Bit 7-i von d6 gesetzt
	move.l	a0,-(sp)
	move.l	d4,-(sp)
	lea	zk_buf,a0
	moveq	#7,d4
zkm\@:	btst	d4,d6
	beq	zkn\@
	move.b	(a0),(a4)
zkn\@:	addq.l	#1,a0
	addq.l	#1,a4
	dbra	d4,zkm\@
	subq.l	#8,a4
	move.l	(sp)+,d4
	move.l	(sp)+,a0
	endm
	else
KPK	macro
	vperm	#$5D7F5D7F,d6,d7,e2\1
	endm
KSTA	macro					; 8 Texel p0..p7 -> (a4), unausgerichtet erlaubt
	vperm	#$012389AB,e21,e22,e23
	store	e23,(a4)
	endm
KSTAP	macro
	vperm	#$012389AB,e21,e22,e23
	store	e23,(a4)+
	endm
KSTM	macro					; nur die Bytes, deren Maskenbit in d6 (Bit 7 = Byte 0) gesetzt ist
	vperm	#$012389AB,e21,e22,e23
	storem	e23,d6,(a4)
	endm
KST	macro
	vperm	#$012389AB,e21,e22,e23
	storem3	e23,d1,(a4)			; d1 = Modus 1 (vasm-Schreibweise für #1)
	endm
KSTP	macro
	vperm	#$012389AB,e21,e22,e23
	storem3	e23,d1,(a4)+
	endm
ZKMASK	macro					; KEY-Rest: p0..p7, nur die ersten m = d4 Bytes, davon nur die <> 0
	vperm	#$012389AB,e21,e22,e23
	load	(zk_msk,d4.l*8),e20
	pand	e20,e23,e23
	storem3	e23,d1,(a4)
	endm
	endif

; Zeilenzustand in E-Registern (Bank-Prefix, auf der V1200 geprüft: move.l Dn<->En, add.l En,Dn). Im Emulatorbau
; (qemu/FS-UAE kennen keinen Bank-Prefix) Stapellokale S_E\1. EL n,Dx  EA n,Dx  ES Dx,n.
; VORGABE Stapellokale: mit E-Registern (-DEREG=1) zeigt die V1200 Pixelbrei (2026-10-14, Ursache offen: move.l Dn,En
; mit Bank 2 ungeprüft oder E-Register durch fremden AMMX-Code überschrieben); nur zum Nachprüfen.
	ifnd	EREG
EMUE	equ	1
	endif
	ifd	K68
	ifnd	EMUE
EMUE	equ	1
	endif
	endif
	ifd	EMUE
; 080 build: e12 / e13 (b.u - a.u, b.v - a.v: read and written every row) in e16 / e17 (bank 3, like the kernels'
; e21..e23; only move.l Dn<->En, the form checked on the V1200), the others on the stack
EL	macro
	ifnd	CPU060
	ifeq	(\1)-12
	move.l	e16,\2
	mexit
	endif
	ifeq	(\1)-13
	move.l	e17,\2
	mexit
	endif
	endif
	move.l	S_E\1(sp),\2
	endm
EA	macro
	add.l	S_E\1(sp),\2
	endm
ES	macro
	ifnd	CPU060
	ifeq	(\2)-12
	move.l	\1,e16
	mexit
	endif
	ifeq	(\2)-13
	move.l	\1,e17
	mexit
	endif
	endif
	move.l	\1,S_E\2(sp)
	endm
	else
EL	macro
	move.l	e\1,\2
	endm
EA	macro
	add.l	e\1,\2
	endm
ES	macro
	move.l	\1,e\2
	endm
	endif

; Lokale (sp)
S_LDX	equ	0
S_LDU	equ	4
S_LDV	equ	8
S_RDX	equ	12
S_RDU	equ	16
S_RDV	equ	20
S_RU	equ	24
S_RV	equ	28
S_LI	equ	32
S_RI	equ	36
S_LEND	equ	40
S_REND	equ	44
S_Y	equ	48				; y am Segmentanfang, im Segment: y nach dem Segment
S_YLIM	equ	52				; min(ybot, vrows): Ende der sichtbaren Zeilen des Polygons
S_GRD	equ	56
S_P	equ	60
S_NP	equ	64
S_KJMP	equ	68				; Zeilenschleife der Art
S_PITCH	equ	72
S_XMAX	equ	76
S_VROWS	equ	80
S_RCP	equ	84
S_COLOR	equ	88				; Farbe in allen 4 Bytes
S_SMG	equ	92
S_REMAP	equ	96
S_RAMK	equ	100
S_AEND	equ	104				; Zeilenanfang nach der letzten Segmentzeile
S_TMP	equ	108
S_GDU	equ	112				; konstanter Gradient du/dx, dv/dx (schlanke Zeilen)
S_GDV	equ	116
	ifd	EMUE				; Stapelbetrieb: e8..e11 sind nur Kopien -> gleich die Originale
S_E8	equ	S_LDX
S_E9	equ	S_LDU
S_E10	equ	S_LDV
S_E11	equ	S_RDX
	else
S_E8	equ	120				; (ungenutzt mit E-Registern)
S_E9	equ	124
S_E10	equ	128
S_E11	equ	132
	endif
S_SV2	equ	120				; CPU060: d2/d3 (uL/vL) während der Pixel (TEX8R-Hilfsregister); 120..135 sonst frei
S_SV3	equ	124
S_E12	equ	136
S_E13	equ	140
S_E14	equ	144
S_E15	equ	148
S_COV	equ	152				; Abdeckung (Art 8): Zeile y bei +y*10 {int16 c0, c1}, c1 < c0 = leer
S_NBASE	equ	156				; -base (Zeilenindex = (a0 - base) >> 6 = y * 10)
S_RCPR	equ	160				; Zeilen-Kehrwerte (65536/w) << 16 = S_RCP + 4096
S_KIND	equ	164				; Art (Einstieg: SpanCtx bzw. raster_poly080 direkt)
S_XRET	equ	168				; Ausgang: 0 = C-Aufruf (Register laden), 1 = raster_poly080 (fc_done)
S_PLAST	equ	172				; &P[np-1] (linke Kette: Umlauf), S_LI/S_RI sind Zeiger auf P[i]
S_PEND	equ	176				; &P[np] (rechte Kette: Umlauf)
S_PVAL	equ	180				; 1 = S_PTOP/S_PYMIN/S_PYMAX aus dem SV-Aufbau (raster_poly080), 0 = zt_l rechnet
S_PTOP	equ	184				; &P[oberste] + 8
S_PYMIN	equ	188
S_PYMAX	equ	192
S_NOCL	equ	196				; 1 = Polygon waagerecht ganz im Bild (minx >= 0, maxx <= xmax): Zeilen ohne Zuschnitt
S_OC2	equ	200				; the late occluders' cut (OCC): a right piece still to draw, its start - xl (0: none)
S_OCN	equ	204				; its n-1
S_OCA	equ	208				; the row's a4 / u / v / du / dv at xl
S_OCU	equ	212
S_OCV	equ	216
S_ODU	equ	220
S_ODV	equ	224
S_OCC	equ	228				; 0, or the cut variants' tables (rk_rowc - rk_row): this polygon may be cut
S_OBJI	equ	232				; the painter's list: the object's number (OCC: cut where a later object covers)
SLOC	equ	236
SARG	equ	SLOC+48

; ---------------------------------------------------------------- Pixel je Art; Eingang d6 = n-1 (>= 0), a4 Ziel,
; a5/a6 u/v (16.16), a1 du, a3 dv; frei d4/d5/d7 (d6 nach Gebrauch); Ausgang: weiter zu zr\1_nx (fällt durch)

; TEX: Kopf bis Langwortgrenze bytweise, dann 4 Pixel je move.l aus zwei Ketten, Rest bytweise
	ifd	CPU060
; TEX (060): ein Pixel je Durchlauf, nicht entrollt (innerste Schleife ohne Entrollung, (a4)+). Der Index des
; nächsten Texels wird hinter dem Speichern gerechnet (ein Pixel voraus), so liegen zwei Befehle zwischen dem letzten
; Schreiben von d4 und seinem Gebrauch als Index; 8 Befehle in 4 Paaren + dbra je Pixel.  (Der Schritt nach dem
; letzten Pixel rechnet einen Index zu viel: a5/a6 werden je Zeile neu gesetzt.)
ZPIX0	macro
	IDX060	d4,d5
	cnop	0,8
zq0l\@:	move.b	(a2,d4.w),(a4)+
	move.l	a6,d4
	move.l	a5,d5
	lsr.l	#8,d4
	swap	d5
	adda.l	a1,a5
	move.b	d5,d4
	adda.l	a3,a6
	dbra	d6,zq0l\@
	endm
; KEY (060): ein Pixel je Durchlauf; Texel 0 = durchsichtig: das Ziel wird gelesen und unverändert zurückgeschrieben
; (dieselbe Zeile, die geschrieben wird: im Cache), so bleibt es bei (a4)+ ohne addq
ZPIX1	macro
	IDX060	d4,d5
	cnop	0,8
zq1l\@:	move.b	(a2,d4.w),d7
	move.l	a6,d4
	move.l	a5,d5
	lsr.l	#8,d4
	swap	d5
	adda.l	a1,a5
	move.b	d5,d4
	adda.l	a3,a6
	tst.b	d7
	bne.s	zq1s\@
	move.b	(a4),d7
zq1s\@:	move.b	d7,(a4)+
	dbra	d6,zq1l\@
	endm
; TEX (060, SCREAMER_TEXU, nur Zeilen ohne Zuschnitt): u getauscht in d5 (frac << 16 | int), Schritt a1 = frac(du) << 16,
; d7.w = int(du); add.l setzt X = Übertrag aus dem Nachkomma-Teil, addx.w führt den Ganzteil nach (zr91_m). Eine Kette,
; ein Pixel je Durchlauf.  Der Index des nächsten Texels wird hinter dem Laden gerechnet (ein Pixel voraus): ein Index
; aus einem Rechenbefehl sofort als Adressindex kostet auf dem 080 2 Takte (68080_Erkenntnisse 2.2), so liegen fünf
; Befehle dazwischen.  (Nach dem letzten Pixel ein Index zu viel: a6/d5 werden je Zeile neu gesetzt.)
TEXU	macro
	move.l	a6,d4
	adda.l	a3,a6
	lsr.l	#8,d4				; (vor add.l: lsr setzt X)
	move.b	d5,d4
	add.l	a1,d5
	addx.w	d7,d5
	endm
; Laden und Speichern getrennt (ein Speicherzugriff je Paar; move.b (mem),(mem)+ belegt zwei Takte am Speicherport):
; Paare Laden|move.l, adda|lsr, move.b|add.l, Speichern|addx, dbra.  V1200 (tools/vbench, 300 px): 5,2 Takte je Pixel
; gegen 8,2 (Index sofort benutzt, ein Speicher-zu-Speicher-Befehl) und 7,2 (nur Index voraus).  d2 frei (SV23).
ZPIX9	macro
	TEXU
	cnop	0,8
zq9l\@:	move.b	(a2,d4.w),d2
	move.l	a6,d4
	adda.l	a3,a6
	lsr.l	#8,d4				; (vor add.l: lsr setzt X)
	move.b	d5,d4
	add.l	a1,d5
	move.b	d2,(a4)+
	addx.w	d7,d5
	dbra	d6,zq9l\@
	endm
; KEY (060, nur Zeilen ohne Zuschnitt): u getauscht wie TEXU, Index ein Pixel voraus; Texel 0 = durchsichtig: nicht
; geschrieben, das Ziel nur weitergezählt (addq statt (a4)+ -- gemessen: einen Speicherzugriff je durchsichtigem Pixel
; weniger; V1200 tools/vbench, Läufe von 8 durchsichtigen Texeln, 300 px: 6,2 Takte je Pixel gegen 8,4 mit Lesen und
; Zurückschreiben des Ziels).  d2 frei (SV23).
ZPIX11	macro
	TEXU
	cnop	0,8
zqbl\@:	move.b	(a2,d4.w),d2
	TEXU
	tst.b	d2
	beq.s	zqbs\@
	move.b	d2,(a4)
zqbs\@:	addq.l	#1,a4
	dbra	d6,zqbl\@
	endm
	else
ZPIX0	macro
	addq.l	#1,d6				; n
	move.l	a4,d5
	neg.l	d5
	moveq	#3,d4
	and.l	d4,d5				; h = (-a4) & 3
	beq	zq0al\@
	cmp.l	d6,d5
	bls	zq0h1\@
	move.l	d6,d5
zq0h1\@:	sub.l	d5,d6
	subq.l	#1,d5
zq0hl\@:	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	move.b	d7,(a4)+
	dbra	d5,zq0hl\@
zq0al\@:	moveq	#3,d5
	and.l	d6,d5
	swap	d5				; Rest t im oberen Wort von d5
	lsr.l	#2,d6				; q Langwörter
	beq	zq0tl\@
	subq.l	#1,d6
	move.w	d6,d5				; d5 = t << 16 | q-1
	moveq	#0,d6				; Ketten: Bytes 3 und 1 bleiben immer 0
	moveq	#0,d7
zq0q\@:	TEX8R	6				; d6 = 0 a 0 p0
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7				; d7 = 0 b 0 p1
	adda.l	a1,a5
	adda.l	a3,a6
	swap	d6				; 0 p0 0 a
	swap	d7				; 0 p1 0 b
	TEX8R	6				; 0 p0 0 p2
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7				; 0 p1 0 p3
	adda.l	a1,a5
	adda.l	a3,a6
	move.l	d6,d4
	lsl.l	#8,d4				; p0 0 p2 0
	or.l	d7,d4				; p0 p1 p2 p3
	move.l	d4,(a4)+
	dbra	d5,zq0q\@
zq0tl\@:	swap	d5				; t
	subq.w	#1,d5
	bmi	\1
zq0tt\@:	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	move.b	d7,(a4)+
	dbra	d5,zq0tt\@
	endm

; KEY: 2 Texel je Durchlauf (d6/d7 unabhängig), 0 = durchsichtig
ZPIX1	macro
	addq.l	#1,d6
	lsr.l	#1,d6				; Paare, C = ungerade
	bcc	zq1ev\@
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	tst.b	d7
	beq	zq1o\@
	move.b	d7,(a4)
zq1o\@:	addq.l	#1,a4
zq1ev\@:	move.l	d6,d5
	subq.l	#1,d5
	bmi	\1
zq1kl\@:	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	tst.b	d6
	beq	zq1k1\@
	move.b	d6,(a4)
zq1k1\@:	tst.b	d7
	beq	zq1k2\@
	move.b	d7,1(a4)
zq1k2\@:	addq.l	#2,a4
	dbra	d5,zq1kl\@
	endm
	endif

	ifnd	K68
; FLAT (68080, Art 10 = FLAT nach Gerätetest raster_sm8): Farbe 8-fach in e23, 64-Bit-store je 8 Pixel (unausgerichtet
; erlaubt), Rest per storem (Maske: oberste r Bits, Bit 7 = Byte 0)
ZPIX10	macro
	addq.l	#1,d6
	move.l	S_COLOR(sp),d7
	vperm	#$4567CDEF,d7,d7,e23
	move.l	d6,d5
	lsr.l	#3,d5
	beq	zq2r\@
	subq.l	#1,d5
zq2l\@:	store	e23,(a4)+
	dbra	d5,zq2l\@
zq2r\@:	moveq	#7,d5
	and.l	d5,d6
	beq	zq2x\@
	move.l	#$ff00,d5
	lsr.l	d6,d5
	storem	e23,d5,(a4)
zq2x\@:
	endm
	endif
; FLAT: Bytes bis zur Langwortgrenze, Langwörter, Restbytes
ZPIX2	macro
	addq.l	#1,d6
	move.l	S_COLOR(sp),d7
	move.l	a4,d5
	neg.l	d5
	moveq	#3,d4
	and.l	d4,d5
	cmp.l	d6,d5
	bls	zq21\@
	move.l	d6,d5
zq21\@:	sub.l	d5,d6
	bra	zq2hd\@
zq2hl\@:	move.b	d7,(a4)+
zq2hd\@:	dbra	d5,zq2hl\@
	move.l	d6,d5
	lsr.l	#2,d5
	bra	zq2qd\@
zq2ql\@:	move.l	d7,(a4)+
zq2qd\@:	dbra	d5,zq2ql\@
	and.l	d4,d6
	bra	zq2td\@
zq2tl\@:	move.b	d7,(a4)+
zq2td\@:	dbra	d6,zq2tl\@
	endm

; Messung: keine Pixel
ZPIX3	macro
	endm

	ifd	CPU060
; SMG (060): dst = smg[texel << 8 | dst], ein Pixel je Durchlauf, (a4)+, nicht entrollt.  Als Kette über drei Pixel:
; im Durchlauf i das SMG-Byte von Pixel i (Index aus dem Durchlauf davor) gelesen und gespeichert, Texel und Ziel von
; Pixel i+1 gelesen (Texelindex aus dem Durchlauf davor), der Texelindex von Pixel i+2 gerechnet -- kein Index aus einem
; Rechenbefehl sofort als Adressindex (080: +2 Takte, 68080_Erkenntnisse 2.2).  Der letzte Durchlauf liest Texel und
; Ziel eines Pixels mehr: das Ziel ist das ausgelassene Endpixel der Zeile (halb offen), das Texel liegt in der Textur
; (Wortindex), u/v werden je Zeile neu gesetzt.
ZPIX4	macro
	subq.l	#1,d6				; halb offen (span_row: durchscheinend ohne Endpixel, Lichtkegel)
	bmi	\1
	movem.l	d0/a0,-(sp)
	move.l	S_RAMK+8(sp),a0
	moveq	#0,d4
	IDX060	d2,d3				; Pixel 0: Texelindex
	move.b	(a2,d2.w),d4			; Texel 0
	move.b	(a4),d7				; Ziel 0
	IDX060	d2,d3				; Texelindex 1
	lsl.w	#8,d4
	move.b	d7,d4				; SMG-Index 0
	cnop	0,8
zq4l\@:	move.b	(a0,d4.l),d5			; SMG-Byte von Pixel i
	move.l	a6,d0
	move.b	(a2,d2.w),d4			; Texel i+1
	move.l	a5,d3
	move.b	d5,(a4)+			; Pixel i
	lsr.l	#8,d0
	move.b	(a4),d7				; Ziel i+1
	swap	d3
	lsl.w	#8,d4
	adda.l	a1,a5
	move.b	d7,d4				; SMG-Index i+1
	adda.l	a3,a6
	move.b	d3,d0
	move.l	d0,d2				; Texelindex i+2
	dbra	d6,zq4l\@
	movem.l	(sp)+,d0/a0
	endm
	else
; SMG (68080): dst = smg[texel << 8 | dst] read from zsm_t, the table transposed and turned by 32 KB (zsm_chk:
; zsm_t[(d << 8 | t) ^ $8000] = smg[t << 8 | d]): with a0 = zsm_t + 32768 the index is (a0,dN.w) with the
; destination byte in bits 8..15 and the texel -- TEX8 replaces only the low byte -- below it.  Four pixels a pass:
; one long read of the 4 destination bytes, four copies of it (each already holding its byte in bits 8..15:
; swap / lsr.l #8 / as it is / lsl.w #8), the four texels into their low bytes, four independent lookups, two
; pairs packed, one long write (unaligned: exact on the 080).  a0/d0 borrowed.
ZPIX4	macro
	subq.l	#1,d6				; halb offen (span_row: durchscheinend ohne Endpixel, Lichtkegel)
	bmi	\1
	movem.l	d0/a0,-(sp)
	lea	zsm_t+32768,a0
	addq.l	#1,d6				; n
	moveq	#3,d0
	and.l	d6,d0				; n & 3 einzeln
	lsr.l	#2,d6
	subq.l	#1,d0
	bmi	zq4e\@
zq4s\@:	move.b	(a4),d4
	lsl.w	#8,d4				; destination in bits 8..15
	TEX8R	4				; texel below it
	adda.l	a1,a5
	adda.l	a3,a6
	move.b	(a0,d4.w),(a4)+
	dbra	d0,zq4s\@
zq4e\@:	move.l	d6,d0
	subq.l	#1,d0
	bmi	zq4x\@
zq4l\@:	move.l	(a4),d6				; b0 b1 b2 b3 (b0 the first pixel)
	move.l	d6,d4
	move.l	d6,d5
	move.l	d6,d7
	swap	d4				; low word b0 b1
	lsr.l	#8,d5				; low word b1 b2
	lsl.w	#8,d7				; low word b3 00  (d6: b2 b3)
	TEX8R	4
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	5
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	move.b	(a0,d4.w),d4			; r0
	move.b	(a0,d6.w),d6			; r2
	lsl.w	#8,d4
	lsl.w	#8,d6
	move.b	(a0,d5.w),d4			; r0 r1
	move.b	(a0,d7.w),d6			; r2 r3
	swap	d4
	move.w	d6,d4				; r0 r1 r2 r3
	move.l	d4,(a4)+
	dbra	d0,zq4l\@
zq4x\@:	movem.l	(sp)+,d0/a0
	endm
	endif

; Schatten: dst = remap[dst]
	ifd	CPU060
ZPIX5	macro
	subq.l	#1,d6				; halb offen wie ZPIX4
	bmi	\1
	move.l	a0,-(sp)
	move.l	S_REMAP+4(sp),a0
	moveq	#0,d5
zq5l\@:	move.b	(a4),d5
	move.b	(a0,d5.l),(a4)+
	dbra	d6,zq5l\@
	move.l	(sp)+,a0
	endm
	else
; Schatten (68080): vier Pixel je Durchlauf wie ZPIX4 -- ein Langwort der 4 Zielbytes gelesen (unausgerichtet: auf dem
; 080 genau), die vier Bytes in eigene Register, vier unabhängige Nachschläge, zusammengesetzt, ein Langwort geschrieben
; (vorher je Pixel Laden -> sofort Index: 080 +4 Takte, und ein Speicher-zu-Speicher-Befehl); n & 3 einzeln.  a0/d0 geliehen.
ZPIX5	macro
	subq.l	#1,d6				; halb offen wie ZPIX4
	bmi	\1
	movem.l	d0/a0,-(sp)
	move.l	S_REMAP+8(sp),a0
	addq.l	#1,d6				; n
	moveq	#3,d0
	and.l	d6,d0				; n & 3 einzeln
	lsr.l	#2,d6
	moveq	#0,d5
	subq.l	#1,d0
	bmi.s	zq5e\@
zq5s\@:	move.b	(a4),d5
	move.b	(a0,d5.l),(a4)+
	dbra	d0,zq5s\@
zq5e\@:	subq.l	#1,d6
	bmi.s	zq5x\@
zq5l\@:	move.l	(a4),d7				; b0 b1 b2 b3 (b0 das erste Pixel)
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d0
	move.b	d7,d4				; b3
	lsr.l	#8,d7
	move.b	d7,d5				; b2
	lsr.l	#8,d7
	move.b	d7,d0				; b1
	lsr.l	#8,d7				; b0
	move.b	(a0,d4.l),d4			; r3
	move.b	(a0,d5.l),d5			; r2
	move.b	(a0,d0.l),d0			; r1
	move.b	(a0,d7.l),d7			; r0
	lsl.l	#8,d7
	move.b	d0,d7				; r0 r1
	lsl.l	#8,d7
	move.b	d5,d7				; r0 r1 r2
	lsl.l	#8,d7
	move.b	d4,d7				; r0 r1 r2 r3
	move.l	d7,(a4)+
	dbra	d6,zq5l\@
zq5x\@:	movem.l	(sp)+,d0/a0
	endm
	endif

Z6B	macro					; 8 Texel -> e21/e22 (KEY-Kern)
	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	swap	d6
	swap	d7
	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	KPK	1				; e21 = p0..p3
	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	swap	d6
	swap	d7
	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	KPK	2				; e22 = p4..p7
	endm

; KEY mit STOREM3 (raster_sm3 <> 0, Gerätetest beim Start): 8 Texel je Durchlauf aus zwei Ketten, ein maskierter
; 8-Byte-Store statt 8 x tst/beq/move.b; Rest (n & 7) wie ZPIX1 bytweise
ZPIX6	macro
	addq.l	#1,d6				; n
	moveq	#7,d5
	and.l	d6,d5
	swap	d5				; Rest im oberen Wort
	lsr.l	#3,d6				; Achtergruppen
	beq	zq6tl\@
	subq.l	#1,d6
	move.w	d6,d5
zq6q\@:	Z6B					; Store mit (a4)+ statt addq
	KSTP
	dbra	d5,zq6q\@
zq6tl\@:	swap	d5				; Rest m = 1..7: ein halber (m <= 4) oder voller Block wie ZPIX7, die Bytes ab m
	tst.w	d5				; per pand mit der Maske zk_msk[m] auf 0, dann storem3 (nur Bytes <> 0): dieselben
	beq	\1				; Bytes wie die Leiter subq/beq je Texel, ohne ihre Sprünge
	moveq	#7,d4
	and.l	d5,d4				; m
	cmp.w	#4,d5
	bhi	zq6f\@
	TEX8H	1				; p0..p3 (e22 bleibt, was es war: die Maske nimmt p4..p7 weg)
	bra	zq6m\@
zq6f\@:	TEX8G
zq6m\@:	ZKMASK
	bra	\1
	endm

; TEX mit AMMX (raster_sm8 <> 0, Gerätetest beim Start): 8 Texel je Gruppe aus zwei Ketten, ein 64-Bit-store
; (unausgerichtet), der Rest (n & 7) als eine maskierte Gruppe (storem) -> keine Byte-Schleifen für Kopf/Schwanz
TEX8G	macro					; 8 Texel -> e21/e22 (bzw. zk_buf)
	TEX8H	1
	TEX8H	2
	endm
TEX8H	macro					; 4 Texel -> e2\1 (\1 = 1: p0..p3, 2: p4..p7)
	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	swap	d6
	swap	d7
	TEX8R	6
	adda.l	a1,a5
	adda.l	a3,a6
	TEX8R	7
	adda.l	a1,a5
	adda.l	a3,a6
	KPK	\1
	endm
ZPIX7	macro
	addq.l	#1,d6				; n
	moveq	#7,d5
	and.l	d6,d5
	move.l	#$ff00,d4			; die Restmaske schon hier (d4 in der Schleife frei): Bits 7..8-m = die
	lsr.l	d5,d4				; ersten m = n & 7 Bytes (Maskenbyte 0: kein Rest, <= $f0: m <= 4)
	lsr.l	#3,d6
	beq	zq7t\@
	subq.l	#1,d6
	move.l	d6,d5
zq7q\@:	TEX8G					; Store mit (a4)+ statt addq (V1200: −0,60 ms; einfache 1-Pixel-Schleife +0,76 ms)
	KSTAP
	dbra	d5,zq7q\@
zq7t\@:	tst.b	d4
	beq	\1
; Rest m = 1..7: ein voller 8er-Block (TEX8 liest nur innerhalb der Textur), gespeichert werden per Maske nur die
; ersten m Bytes (storem) -> gleiche Bytes ohne dbra-Leiter (vorher ~90 Takte je Zeile für Rest und Sprünge)
	cmp.b	#$f0,d4				; Rest 1..4: halber Block (4 Texel, e22 ungenutzt; B: -0,45 ms)
	bhi	zq7f\@
	TEX8H	1
	move.l	d4,d6
	KSTM
	bra	\1
zq7f\@:	TEX8G
	move.l	d4,d6
	KSTM
	endm

; Art 8 (Abdeckungsdurchlauf): Zeilenspanne xl..xr in die Abdeckung der Zeile eintragen,
; ein Intervall je Zeile: Vereinigung bei Überlappung/Berührung, sonst das längere behalten (unvollständig ist
; erlaubt: es verschenkt nur Verdeckung). Keine Pixel.
ZPIX8	macro
	ifd	OCCSTAT
	addq.l	#1,oc_crow
	endif
	move.l	a0,d4
	add.l	S_NBASE(sp),d4
	lsr.l	#6,d4				; y * 10
	add.l	S_COV(sp),d4
	movea.l	d4,a5
	move.l	a4,d5
	sub.l	a0,d5				; xl
	move.l	d5,d7
	add.l	d6,d7				; xr
	move.w	(a5),d4				; c0
	ext.l	d4
	move.w	2(a5),d6			; c1
	ext.l	d6
	cmp.l	d4,d6
	blt	zq8n\@				; leer
	move.l	d4,a6
	subq.l	#1,a6
	cmpa.l	d7,a6				; c0 - 1 > xr -> getrennt
	bgt	zq8s\@
	move.l	d6,a6
	addq.l	#1,a6
	cmpa.l	d5,a6				; c1 + 1 < xl -> getrennt
	blt	zq8s\@
	cmp.l	d4,d5				; vereinigen
	bge	zq8a\@
	move.l	d5,d4
zq8a\@:	cmp.l	d6,d7
	ble	zq8b\@
	move.l	d7,d6
zq8b\@:	move.w	d4,(a5)
	move.w	d6,2(a5)
	bra	\1
zq8s\@:	sub.l	d4,d6				; getrennt: längeres behalten
	move.l	d7,a6
	suba.l	d5,a6
	cmpa.l	d6,a6
	ble	\1
zq8n\@:	move.w	d5,(a5)
	move.w	d7,2(a5)
	move.w	S_OBJI+2(sp),OC_SIZE(a5)	; (the late occluders: its object; a union keeps the first's)
	endm

; 68060 (CPU060): Kehrwertprodukte ohne 64-Bit-muls, bitgleich zu den Einbefehlsformen des 080:
; RDUV: d4 = b.u - a.u, d7 = b.v - a.v, d5 = r (<= 21845) -> d6 = du = (d4 * r) >> 16, d5 = dv (zerstört d4/d7)
RDUV	macro					; r < 2^15: muls.w/mulu.w auf die Worthälften (ext/and entfallen)
	move.l	d4,d6
	swap	d6
	muls.w	d5,d6				; (d >> 16) * r
	mulu.w	d5,d4				; (d & $ffff) * r
	clr.w	d4
	swap	d4
	add.l	d4,d6
	move.l	d7,d4
	swap	d4
	muls.w	d5,d4
	mulu.w	d5,d7
	clr.w	d7
	swap	d7
	add.l	d4,d7
	move.l	d7,d5
	endm
; RDUVM: wie RDUV, Differenzen aus S_E12/S_E13 (= d4/d7 auf den Wegen zr_row und Kantenschritt; nicht nach zr_swp):
; 13 statt 16 Befehle, u und v unabhängig (zerstört d4/d7)
RDUVM	macro
	move.l	d5,d6
	muls.w	S_E12(sp),d6			; (d >> 16) * r (oberes Wort, Big Endian vorn)
	move.l	d5,d4
	mulu.w	S_E12+2(sp),d4			; (d & $ffff) * r
	move.l	d5,d7
	muls.w	S_E13(sp),d7
	mulu.w	S_E13+2(sp),d5
	clr.w	d4
	swap	d4
	add.l	d4,d6
	clr.w	d5
	swap	d5
	add.l	d7,d5
	endm
; RMW \1,\2: \2 = (\1 * d5) >> 16 (Kanten: r = d5 <= 65535, |\1| < 2^29; r = 65536 (dy = 1) prüft der Aufrufer:
; Ergebnis = \1), zerstört \1
RMW	macro
	move.l	\1,\2
	swap	\2
	ext.l	\2
	muls.l	d5,\2
	mulu.w	d5,\1
	clr.w	\1
	swap	\1
	add.l	\1,\2
	endm
SV23	macro					; CPU060: d2/d3 frei für TEX8R (\1 = Art; TEX/KEY brauchen d2/d3 nicht), Vorspannung
	ifd	CPU060				; v für den Wortindex (a2 + 32768 einmal je Aufruf ab rk_ok, zurück in z_exit)
	ifeq	((\1)-9)*((\1)-11)
	movea.l	d2,a5				; Arten 9/11 (u getauscht in d5): nur d2 gebraucht, in a5 (bis zr_nx frei)
	else
	ifne	(\1)*((\1)-1)
	move.l	d2,S_SV2(sp)
	move.l	d3,S_SV3(sp)
	endif
	endif
	adda.l	#$800000,a6			; v wird je Zeile neu aus d3 geladen
	endif
	endm
LD23	macro
	ifd	CPU060
	ifeq	((\1)-9)*((\1)-11)
	move.l	a5,d2
	else
	ifne	(\1)*((\1)-1)
	move.l	S_SV2(sp),d2
	move.l	S_SV3(sp),d3
	endif
	endif
	endif
	endm
RK_OCC	equ	108				; rk_rowc - rk_row (S_OCC)
OC_SIZE	equ	16384
RCPT	macro					; Kehrwerttabelle der Zeilen nach a1 (080: (65536/w) << 16, 060: 65536/w)
	ifd	CPU060
	move.l	S_RCP(sp),a1
	else
	move.l	S_RCPR(sp),a1
	endif
	endm

; ---------------------------------------------------------------- (OpenScreamer) THE LATE OCCLUDERS' CUT
; pt_draw_list notes, before it paints, which pixels of every row the TEX and FLAT polygons of the last objects
; (raster_occk; of them only polygons of 2 x area >= raster_occa: the small ones cost more rows than they cover) will
; paint: one interval {c0, c1} a row (oc_cov, by the cover pass, kind 8 / ZPIX8: exactly the rows' xl..xr; disjoint
; pieces keep the longer one) and the number of the first object in it (oc_tag).  Each polygon of an object before
; that is drawn with the row loops' cut variants (ZROW k,n,c / ZROWF k,c): the part of a row inside the interval is
; not drawn -- a later object paints it over with opaque pixels, so the picture stays the same to the bit.  A row
; whose start is cut goes on with u += du k, v += dv k (as zr_cl at x < 0, modulo 2^32: k steps); one with a middle
; part cut is drawn in two pieces; SMG / SHADOW rows are half open (their last pixel not drawn: \3 = 1).
; OCC \1 = where a row wholly covered goes (_nx), \2 = the pixels (_k).  In: a4 = the first pixel (xl >= 0), d6 = n-1
; (>= 0, xl + n-1 <= xmax), a5/a6 u/v at xl, a1/a3 du/dv, a0 the row; d4/d5/d7 free (the pixel kernels' own).
; V1200 (080, 640x400, the standard scene): painting -0.9 ms; qemu: ~44000 pixels a picture not painted.
OCC	macro
	ifd	OCCSTAT
	addq.l	#1,oc_trow
	endif
	move.l	a0,d7
	add.l	S_NBASE(sp),d7
	lsr.l	#6,d7				; the row's entry (as ZPIX8: (a0 - base) >> 6)
	move.l	(oc_cov,d7.l),d5		; c0 << 16 | c1 (none: $7fff8000)
	move.l	a4,d4
	sub.l	a0,d4				; L = xl
	ifne	\3
	subq.l	#1,d6				; (SMG, SHADOW: half open, the last pixel not drawn -- R = L + n-2)
	bmi	\1
	endif
	cmp.w	d4,d5				; c1 < L: nothing of the row covered (the usual)
	blt	.k\@
	move.w	(oc_cov+OC_SIZE,d7.l),d7	; the first object whose polygons cover it: this one before it?
	cmp.w	S_OBJI+2(sp),d7
	ble	.k\@
	move.l	d5,d7
	swap	d5
	sub.w	d4,d5				; c0 - L
	bgt	.r\@
	sub.w	d4,d7				; c0 <= L <= c1
	cmp.w	d6,d7
	bge	.a\@				; c1 >= R: the whole row covered
	addq.w	#1,d7
	ext.l	d7				; k = c1 + 1 - L <= R - L: the start cut
	ifd	OCCSTAT
	add.l	d7,oc_spx
	endif
	sub.l	d7,d6
	adda.l	d7,a4
	move.l	a1,d5
	muls.l	d7,d5
	adda.l	d5,a5
	move.l	a3,d5
	muls.l	d7,d5
	adda.l	d5,a6
	bra	.k\@
.a\@:
	ifd	OCCSTAT
	addq.l	#1,oc_srow
	addq.l	#1,d6
	add.l	d6,oc_spx
	endif
	bra	\1
.r\@:	cmp.w	d6,d5				; c0 > R: the cover right of the row
	bgt	.k\@
	sub.w	d4,d7				; c1 - L
	cmp.w	d6,d7
	bge	.c\@				; c1 >= R: the end cut
	addq.w	#1,d7				; c1 < R: a middle part cut; the right piece after the left one
	ext.l	d7				; k2 = c1 + 1 - L
	move.l	d6,d4
	sub.l	d7,d4
	ifne	\3
	addq.l	#1,d4
	endif
	move.l	d4,S_OCN(sp)
	move.l	d7,S_OC2(sp)
	move.l	a4,S_OCA(sp)
	move.l	a5,S_OCU(sp)
	move.l	a6,S_OCV(sp)
	move.l	a1,S_ODU(sp)
	move.l	a3,S_ODV(sp)
	ext.l	d5
	ifd	OCCSTAT
	move.l	d7,d4
	sub.l	d5,d4
	add.l	d4,oc_spx
	endif
	bra.s	.e\@
.c\@:	ext.l	d5
	ifd	OCCSTAT
	move.l	d6,d4
	sub.l	d5,d4
	addq.l	#1,d4
	add.l	d4,oc_spx
	endif
.e\@:	subq.l	#1,d5
	move.l	d5,d6				; R = c0 - 1 (>= L)
.k\@:
	ifne	\3
	addq.l	#1,d6				; (back to the kernel's count)
	endif
	endm
; OCP2 \1: the right piece of a row cut in the middle (S_OC2 = its start - xl), then the pixels at \1 (_k)
OCP2	macro
	move.l	S_OC2(sp),d7
	clr.l	S_OC2(sp)
	move.l	S_OCN(sp),d6
	move.l	S_OCA(sp),a4
	adda.l	d7,a4
	move.l	S_ODU(sp),a1
	move.l	a1,d5
	muls.l	d7,d5
	add.l	S_OCU(sp),d5
	movea.l	d5,a5
	move.l	S_ODV(sp),a3
	move.l	a3,d5
	muls.l	d7,d5
	add.l	S_OCV(sp),d5
	movea.l	d5,a6
	bra	\1
	endm

; ---------------------------------------------------------------- Zeilenschleife der Art \1 für ein Segment
; dauerhaft: d0 xL, d1 xR (16.16), d2 uL, d3 vL, a0 Zeilenanfang, a2 Textur; Kantenschritte in e8..e15 (EL/EA/ES)
; Kehrwerte: S_RCP = 65536/w (Kanten), S_RCPR = S_RCP + 4096 = (65536/w) << 16 (kurzes Format (a1,d5*4)) (Zeilen, w >= 3; span.c g_span_rcp)
ZROW	macro
	cnop	0,32				; jede Zeilenschleife an einer 32-Byte-Grenze (hinter dem bra der vorigen, nie
						; ausgeführt): ihre Lage hängt nicht von der Größe der Arten davor ab (V1200: eine
						; längere Art-4-Schleife verschob die Zeilen der Arten 9/11 -> +2 ms Malen)
zr\1\2\3_seg:					; Segmentanfang: Zeilenzustand in E-Register (e8 LDX, e9 LDU, e10 LDV, e11 RDX,
	move.l	S_RV(sp),d7			; e12/e13 = rechte - linke Kante u/v, e14/e15 = deren Schritt); d7/d4 bleiben
	sub.l	d3,d7				; als b.v - a.v / b.u - a.u stehen
	ES	d7,13
	move.l	S_RDU(sp),d4
	sub.l	S_LDU(sp),d4
	ES	d4,14
	move.l	S_RDV(sp),d4
	sub.l	S_LDV(sp),d4
	ES	d4,15
	ifnd	EMUE
	move.l	S_LDX(sp),d4
	ES	d4,8
	move.l	S_LDU(sp),d4
	ES	d4,9
	move.l	S_LDV(sp),d4
	ES	d4,10
	move.l	S_RDX(sp),d4
	ES	d4,11
	endif
	move.l	S_RU(sp),d4			; b.u - a.u (je Zeile in d4/d7 aus dem Zeilenschritt weitergereicht)
	sub.l	d2,d4
	ES	d4,12
	RCPT
zr\1\2\3_row:					; d4/d7 = e12/e13, a1 = Kehrwerttabelle
	move.l	d0,d6
	move.l	d1,d5
	cmp.l	d1,d0				; L.x > R.x -> getauscht
	bgt	zr\1\2\3_swp
	swap	d6
	ext.l	d6				; xl (= asr 16)
	swap	d5
	ext.l	d5				; xr
	movea.l	d2,a5				; u
	movea.l	d3,a6				; v
	if	\2
zr\1\2\3_c:	movea.l	d5,a3				; ohne Zuschnitt: n-1 = w = xr - xl, in der Adresseinheit gebildet (xr/xl
	suba.l	d6,a3				; aus ext.l lange davor; ein frisches sub.l -> movea kostete 080 +2..3 Takte)
	sub.l	d6,d5				; w (für die Bereichsprüfung)
	lea	(a0,d6.l),a4			; Ziel vor Zuschnitt (xl = a4 - a0)
	else
zr\1\2\3_c:	lea	(a0,d6.l),a4			; Ziel vor Zuschnitt (xl = a4 - a0)
	movea.l	d5,a3				; xr
	sub.l	d6,d5				; w
	endif
	subq.l	#3,d5				; w - 3 in 0..1020 = Tabelle, sonst selten (w <= 2, w >= 1024)
	cmp.l	#1020,d5
	bhi	zr\1\2\3_wx
	ifd	CPU060
	move.l	12(a1,d5.l*4),d5		; r = 65536 / w
	RDUVM
	else
	if	\2
	move.l	(a1,a3.l*4),d5			; ohne Zuschnitt: a3 = w (kein Index frisch aus subq/cmp: 080 +2 Takte);
	muls.l	d5,d6:d4			; derselbe Eintrag wie 12(a1,(w-3)*4), einmal gelesen
	muls.l	d5,d5:d7
	else
	muls.l	12(a1,d5.l*4),d6:d4		; (b.u-a.u) * (r << 16): oberes Langwort = (d * r) >> 16 = du
	muls.l	12(a1,d5.l*4),d5:d7		; dv
	endif
	endif
	ifeq	((\1)-9)*((\1)-11)
zr\1\2\3_m:	move.l	d6,d7				; du -> d7.w = int(du), a1 = frac(du) << 16
	swap	d7
	move.l	d7,d4
	clr.w	d4
	movea.l	d4,a1
	move.l	a3,d6				; xr
	movea.l	d5,a3				; dv
	move.l	a5,d5				; u getauscht: frac << 16 | int
	swap	d5
	else
zr\1\2\3_m:	movea.l	d6,a1				; du
	move.l	a3,d6				; xr
	movea.l	d5,a3				; dv
	endif
	ifd	PMKON
	tst.l	raster_zuv			; Messbau: Texturschritte 0 (alle Texel aus dem Cache)
	beq	zrz\@
	suba.l	a1,a1
	suba.l	a3,a3
zrz\@:
	endif
	if	\2
zr\1\2\3_s:					; ohne Zuschnitt (S_NOCL): xl >= 0, xr <= xmax; d6 = n-1 = w (zr_c/zr_m)
	ifd	NOCLCHK				; Prüfbau (qemu): Annahme verletzt -> Abbruch
	cmpa.l	a0,a4
	bcs	zrk\@
	move.l	d6,-(sp)
	add.l	a4,d6
	sub.l	a0,d6				; xr
	cmp.l	S_XMAX+4(sp),d6
	movem.l	(sp)+,d6
	ble	zrk2\@
zrk\@:	illegal
zrk2\@:
	endif
	else
zr\1\2\3_s:	cmpa.l	a0,a4
	bcs	zr\1\2\3_cl				; xl < 0
zr\1\2\3_s2:
	cmp.l	S_XMAX(sp),d6
	ble	zr\1\2\3_s3
	move.l	S_XMAX(sp),d6
zr\1\2\3_s3:
	add.l	a0,d6
	sub.l	a4,d6				; n-1 = xr - xl
	bmi	zr\1\2\3_nx
	endif
	ifnb	\3
	ifeq	((\1)-4)*((\1)-5)
	OCC	zr\1\2\3_nx,zr\1\2\3_k,1		; (the cut variant: the part a later occluder paints over)
	else
	OCC	zr\1\2\3_nx,zr\1\2\3_k,0
	endif
	endif
zr\1\2\3_k:
	SV23	\1
	PMZ	\1
	PMA
	ZPIX\1	zr\1\2\3_px
zr\1\2\3_px:
	LD23	\1
	ifnb	\3
	tst.l	S_OC2(sp)			; a right piece still to draw
	bne	zr\1\2\3_p2
	endif
zr\1\2\3_nx:					; Kantenschritt; Speicherbefehle mit Registerbefehlen des nächsten Zeilenanfangs
	PMB	\1				; verschränkt (je Paar ein Speicherzugriff, der Partner läuft in Pipe 2);
	EL	12,d4				; e12 / e13 und die Zeilenlänge zuerst: kein Geladenes sofort benutzt, a0
	EL	13,d7				; viele Paare vor dem cmpa
	adda.l	S_PITCH(sp),a0
	EA	8,d0
	EA	11,d1
	EA	14,d4
	move.l	d0,d6
	EA	15,d7
	move.l	d1,d5
	EA	9,d2
	swap	d6
	EA	10,d3
	swap	d5
	ES	d4,12
	ext.l	d6				; xl
	ES	d7,13
	ext.l	d5				; xr
	RCPT
	movea.l	d2,a5
	cmpa.l	S_AEND(sp),a0
	movea.l	d3,a6
	beq	zr\1\2\3_se
	cmp.l	d1,d0
	ble	zr\1\2\3_c
	bra	zr\1\2\3_swp
zr\1\2\3_se:	add.l	d2,d4				; Segmentende: RU/RV = linke Kante + Differenz
	move.l	d4,S_RU(sp)
	add.l	d3,d7
	move.l	d7,S_RV(sp)
	bra	z_seg
; seltene Wege
	ifnb	\3
zr\1\2\3_p2:	OCP2	zr\1\2\3_k
	endif
zr\1\2\3_swp:					; a = R, b = L
	move.l	d1,d6
	move.l	d0,d5
	swap	d6
	ext.l	d6
	swap	d5
	ext.l	d5
	neg.l	d4				; b.u - a.u = uL - RU (d4/d7 = e12/e13)
	neg.l	d7
	movea.l	d2,a5
	suba.l	d4,a5				; RU = uL + Differenz
	movea.l	d3,a6
	suba.l	d7,a6
	ifd	CPU060
zr\1\2\3_cs:	lea	(a0,d6.l),a4			; wie zr_c, aber d4/d7 negiert (nicht in S_E12/S_E13) -> RDUV mit Registern
	if	\2
	sub.l	d6,d5
	movea.l	d5,a3
	else
	movea.l	d5,a3
	sub.l	d6,d5
	endif
	subq.l	#3,d5
	cmp.l	#1020,d5
	bhi	zr\1\2\3_wx
	move.l	12(a1,d5.l*4),d5
	RDUV
	bra	zr\1\2\3_m
	else
	bra	zr\1\2\3_c
	endif
zr\1\2\3_wx:	addq.l	#3,d5				; w außerhalb 3..1023
	ble	zr\1\2\3_w0
	cmp.l	#1023,d5
	bhi	zr\1\2\3_wb
	bra	zr\1\2\3_w12
zr\1\2\3_w0:
	ifnd	CPU060				; one pixel (w = 0 without the cut: the tips of most polygons): its texel straight
	if	\2				; (ZPIX7/ZPIX6 would make a masked block of it)
	ifeq	((\1)-6)*((\1)-7)
	TEX8R	4
	ifeq	(\1)-6
	tst.b	d4				; KEY: colour 0 is not drawn
	beq	zr\1\2\3_nx
	endif
	move.b	d4,(a4)
	bra	zr\1\2\3_nx
	endif
	endif
	endif
	suba.l	a1,a1				; w <= 0: du = dv = 0
	move.l	a3,d6
	suba.l	a3,a3
	ifeq	((\1)-9)*((\1)-11)
	moveq	#0,d7
	move.l	a5,d5
	swap	d5
	endif
	bra	zr\1\2\3_s
zr\1\2\3_wb:	move.l	#65536,d6			; w >= 1024: r = (65536 / w) << 16
	divs.l	d5,d6
	ifd	CPU060
	move.l	d6,d5
	RDUV
	else
	swap	d6
	clr.w	d6
	move.l	d6,S_TMP(sp)
	muls.l	S_TMP(sp),d6:d4
	muls.l	S_TMP(sp),d5:d7
	endif
	bra	zr\1\2\3_m
zr\1\2\3_w12:	cmp.l	#1,d5				; w = 1: du = b.u - a.u; w = 2: die Hälfte
	beq	zr\1\2\3_w1
	asr.l	#1,d4
	asr.l	#1,d7
zr\1\2\3_w1:	move.l	d4,d6
	move.l	d7,d5
	bra	zr\1\2\3_m
	ifeq	\2
zr\1\2\3_cl:	move.l	a0,d4				; -xl
	sub.l	a4,d4
	move.l	a1,d5
	muls.l	d4,d5
	adda.l	d5,a5				; u += du * -xl
	move.l	a3,d5
	muls.l	d4,d5
	adda.l	d5,a6				; v += dv * -xl
	movea.l	a0,a4
	bra	zr\1\2\3_s2
		endif
endm

; ---------------------------------------------------------------- schlanke Zeilenschleife (konstanter Gradient)
; du/dv je Polygon fest (S_GDU/S_GDV: Dreiecke aus der Ebene, FLAT/SHADOW 0) -> je Zeile kein muls/Kehrwert, keine
; rechte u/v-Kette. Einstieg zf\1_seg je Segment (a1/a3 = du/dv laden), Rücksprung in den Segmentkopf.
ZROWF	macro
zf\1\2_seg:
	movea.l	S_GDU(sp),a1
	movea.l	S_GDV(sp),a3
zf\1\2_row:
	move.l	d0,d6
	move.l	d1,d5
	cmp.l	d1,d0
	bgt	zf\1\2_swp
	swap	d6
	ext.l	d6				; xl
	swap	d5
	ext.l	d5				; xr
	ifeq	(\1)*((\1)-1)*((\1)-4)*((\1)-6)*((\1)-7)
	movea.l	d2,a5				; (u / v: only the kinds with a texture -- FLAT, SHADOW, none, the cover
	movea.l	d3,a6				; read neither, and z_newl takes d2 / d3 afresh from the corners)
	endif
zf\1\2_c:	tst.l	d6
	bmi	zf\1\2_cl
zf\1\2_s2:	cmp.l	S_XMAX(sp),d5
	ble	zf\1\2_s3
	move.l	S_XMAX(sp),d5
zf\1\2_s3:	lea	(a0,d6.l),a4
	sub.l	d6,d5				; n-1
	bmi	zf\1\2_nx
	move.l	d5,d6
	ifnb	\2
	ifeq	((\1)-4)*((\1)-5)
	OCC	zf\1\2_nx,zf\1\2_k,1
	else
	OCC	zf\1\2_nx,zf\1\2_k,0
	endif
	endif
zf\1\2_k:
	SV23	\1
	PMZ	\1
	PMA
	ZPIX\1	zf\1\2_px
zf\1\2_px:
	LD23	\1
	ifnb	\2
	tst.l	S_OC2(sp)
	bne	zf\1\2_p2
	endif
zf\1\2_nx:	PMB	\1
	add.l	S_LDX(sp),d0
	ifeq	(\1)*((\1)-1)*((\1)-4)*((\1)-6)*((\1)-7)
	add.l	S_LDU(sp),d2
	add.l	S_LDV(sp),d3
	endif
	add.l	S_RDX(sp),d1
	adda.l	S_PITCH(sp),a0
	cmpa.l	S_AEND(sp),a0
	bne	zf\1\2_row
	bra	z_seg
	ifnb	\2
zf\1\2_p2:	OCP2	zf\1\2_k
	endif
zf\1\2_swp:					; L.x > R.x: linkes Pixel auf der rechten Kante
	swap	d6
	ext.l	d6				; xL
	swap	d5
	ext.l	d5				; xR
	move.l	d6,d7
	sub.l	d5,d7				; k = xL - xR
	move.l	a1,d4
	muls.l	d7,d4
	neg.l	d4
	add.l	d2,d4
	movea.l	d4,a5				; u = uL - du * k
	move.l	a3,d4
	muls.l	d7,d4
	neg.l	d4
	add.l	d3,d4
	movea.l	d4,a6
	exg	d5,d6
	bra	zf\1\2_c
zf\1\2_cl:	move.l	d6,d7				; xl < 0
	neg.l	d7
	move.l	a1,d4
	muls.l	d7,d4
	adda.l	d4,a5
	move.l	a3,d4
	muls.l	d7,d4
	adda.l	d4,a6
	moveq	#0,d6
	bra	zf\1\2_s2
	endm

	xdef	_raster_span_poly
	xdef	raster_span_poly
_raster_span_poly:
raster_span_poly:
	movem.l	d2-d7/a2-a6,-(sp)
	lea	-SLOC(sp),sp
	PMK0					; (Messbau: Bezugspunkt -- sonst zählte Abschnitt 3 die Zeit seit dem letzten Aufruf)
	clr.l	S_XRET(sp)
	clr.l	S_PVAL(sp)
	clr.l	S_NOCL(sp)
	clr.l	S_OCC(sp)
	move.l	SARG(sp),a0
	move.l	(a0),S_P(sp)
	move.l	4(a0),S_NP(sp)
	move.l	8(a0),d7			; kind
	move.l	d7,S_KIND(sp)
	move.l	12(a0),a2			; Textur
	move.l	20(a0),S_PITCH(sp)
	move.l	24(a0),S_XMAX(sp)
	move.l	28(a0),S_VROWS(sp)
	move.l	32(a0),S_RCP(sp)
	move.l	32(a0),d0
	add.l	#4096,d0
	move.l	d0,S_RCPR(sp)
	cmp.l	#2,d7				; Farbe nur für FLAT (ZPIX2)
	bne	rsp_nc
	moveq	#0,d6
	move.b	39(a0),d6			; Farbe (Low-Byte) in alle 4 Bytes
	move.l	d6,d5
	lsl.l	#8,d5
	or.l	d5,d6
	move.l	d6,d5
	swap	d5
	or.l	d5,d6
	move.l	d6,S_COLOR(sp)
rsp_nc:
	move.l	40(a0),S_SMG(sp)
	move.l	44(a0),S_REMAP(sp)
	move.l	48(a0),S_RAMK(sp)
	move.l	52(a0),S_COV(sp)
	ifnd	CPU060
	cmp.l	#4,d7				; SMG (68080): the transposed table up to date (zsm_chk)
	bne.s	rsp_ns
	move.l	48(a0),d0
	bsr	zsm_chk
rsp_ns:
	endif
	move.l	16(a0),a4			; base
	move.l	a4,d6
	neg.l	d6
	move.l	d6,S_NBASE(sp)
	move.l	S_KIND(sp),d7
; rsp_d: Einstieg aus raster_poly080 (Rahmen dort direkt gefüllt, d7 = Art, a2 = Textur, a4 = base)
rsp_d:
	; Zeilenschleife der Art über Tabellen rk_row/rk_grd (Arten 0..8, andere wie 3); neu aufgebaut, wenn sich die
	; Gerätetest-Flaggen raster_sm8/raster_sm3 ändern (rk_sm)
	moveq	#0,d0
	tst.l	raster_sm8
	sne	d0
	add.l	d0,d0
	tst.l	raster_sm3
	sne	d0
	cmp.l	rk_sm,d0
	beq	rk_ok
	bsr	rk_build
rk_ok:
	ifd	CPU060
	adda.l	#$8000,a2			; Wortindex (SV23/TEX8R): a2 = Textur + 32768 für den ganzen Aufruf
	endif
	PMK	3
	lea	zf3_seg(pc),a1
	clr.l	S_GDU(sp)
	clr.l	S_GDV(sp)
	cmp.l	#8,d7
	bhi	zg_set0
	lea	rk_row,a1
	tst.l	S_NOCL(sp)
	beq	zg_rc
	lea	rk_rown,a1			; Zeilen ohne Zuschnitt
zg_rc:	adda.l	S_OCC(sp),a1			; (the cut variants: rk_rowc / rk_rownc)
	move.l	(a1,d7.l*4),a1
	move.l	a1,S_KJMP(sp)
	; schlanke Zeilen: FLAT/ohne Pixel/SHADOW immer (Tabelle rk_row); TEX/KEY/SMG bei Dreiecken mit Ebenengradient
	cmp.l	#3,S_NP(sp)			; fast nie 3 Ecken (Zusatzzeile): zuerst prüfen
	bne	zg_no
	lea	rk_grd,a1
	adda.l	S_OCC(sp),a1
	move.l	(a1,d7.l*4),d0
	beq	zg_no
	tst.l	raster_cgrad
	beq	zg_no
	cmp.l	#3,S_NP(sp)
	bne	zg_no
	move.l	S_P(sp),a1			; P: x 0, y 4, u 8, v 12 (16 Byte je Ecke)
	move.l	16(a1),d0
	sub.l	(a1),d0				; x1 - x0
	move.l	36(a1),d1
	sub.l	4(a1),d1			; y2 - y0
	move.l	32(a1),d2
	sub.l	(a1),d2				; x2 - x0
	move.l	20(a1),d3
	sub.l	4(a1),d3			; y1 - y0
	muls.l	d1,d0
	muls.l	d3,d2
	sub.l	d2,d0				; den
	beq	zg_no
	move.l	24(a1),d4
	sub.l	8(a1),d4			; u1 - u0
	MULS64	d1,d5,d4
	move.l	40(a1),d6
	sub.l	8(a1),d6			; u2 - u0
	MULS64	d3,d2,d6
	sub.l	d6,d4
	subx.l	d2,d5
	DIVS64	d0,d5,d4			; du/dx
	bvs	zg_no
	move.l	d4,S_GDU(sp)
	move.l	28(a1),d4
	sub.l	12(a1),d4			; v1 - v0
	MULS64	d1,d5,d4
	move.l	44(a1),d6
	sub.l	12(a1),d6
	MULS64	d3,d2,d6
	sub.l	d6,d4
	subx.l	d2,d5
	DIVS64	d0,d5,d4
	bvs	zg_no
	move.l	d4,S_GDV(sp)
	lea	rk_grd,a1
	adda.l	S_OCC(sp),a1
	move.l	(a1,d7.l*4),a1
zg_set:	move.l	a1,S_KJMP(sp)
	bra	zg_no
zg_set0:	move.l	a1,S_KJMP(sp)
zg_no:
	; oberste Ecke, unterste Zeile (aus raster_poly080 schon beim SV-Aufbau bestimmt)
	move.l	S_NP(sp),d6
	tst.l	S_PVAL(sp)
	beq	zt_s
	move.l	S_PTOP(sp),d0
	subq.l	#8,d0
	move.l	S_PYMIN(sp),d1
	move.l	S_PYMAX(sp),d2
	bra	zt_d2
zt_s:	move.l	S_P(sp),a1
	moveq	#0,d0
	move.l	4(a1),d1
	move.l	d1,d2
	moveq	#1,d3
	lea	16(a1),a5
zt_l:	cmp.l	d6,d3
	bge	zt_d
	move.l	4(a5),d4
	cmp.l	d1,d4
	bge	zt_1
	move.l	d4,d1
	move.l	d3,d0
zt_1:	cmp.l	d2,d4
	ble	zt_2
	move.l	d4,d2
zt_2:	lea	16(a5),a5
	addq.l	#1,d3
	bra	zt_l
zt_d:	lsl.l	#4,d0
	add.l	S_P(sp),d0			; &P[oberste]
zt_d2:	move.l	d0,S_LI(sp)
	move.l	d0,S_RI(sp)
	move.l	d6,d0
	lsl.l	#4,d0
	add.l	S_P(sp),d0
	move.l	d0,S_PEND(sp)
	sub.l	#16,d0
	move.l	d0,S_PLAST(sp)
	move.l	d1,S_Y(sp)
	move.l	d1,S_LEND(sp)
	move.l	d1,S_REND(sp)
	cmp.l	S_VROWS(sp),d2			; ylim = min(ybot, vrows)
	ble	zt_yl
	move.l	S_VROWS(sp),d2
zt_yl:	move.l	d2,S_YLIM(sp)
	lsl.l	#2,d6
	move.l	d6,S_GRD(sp)
	move.l	d1,d4
	muls.w	S_PITCH+2(sp),d4		; (|y| < 2^15, Zeilenlänge < 2^15: muls.w genau wie muls.l)
	lea	(a4,d4.l),a0			; Zeilenanfang der obersten Zeile
	moveq	#0,d0				; L, R wie memset 0 (Kantenschritte S_LDX..S_RV setzt z_newl/z_newr vor jeder Zeile
	moveq	#0,d1				; und vor z_skip)
	moveq	#0,d2
	moveq	#0,d3
	PMK	7				; Spannenkopf (Gradient, oberste Ecke, Rahmen) fertig

; ---------------------------------------------------------------- Segmentkopf: Kanten weiterschalten, Zeilenzahl
z_seg:	PMK	5				; (Messbau: 5 = Zeilen eines Segments bzw. Kopf, 6 = Segmentkopf mit Kanten)
	move.l	S_Y(sp),d4
z_seg2:	movea.l	S_LEND(sp),a3			; the whole head: y in d4, lend in a3, rend in a4 (z_newl / z_newr keep them;
	movea.l	S_REND(sp),a4			; S_LEND / S_REND written only where they change)
	cmp.l	S_YLIM(sp),d4			; unterste Zeile erreicht bzw. ab hier unsichtbar (span_row schreibt nichts)
	bge	z_exit
	cmp.l	a3,d4
	bge	z_newl
z_l9:	cmp.l	a4,d4
	bge	z_newr
z_r9:	tst.l	S_GRD(sp)
	ble	z_exit
	movea.l	S_KJMP(sp),a1			; (the row loop's address early: read only by the jmp below)
	move.l	a3,d5				; n = min(lend, rend, ylim) - y >= 1 (y < 0: z_skip überspringt k = min(n, -y)
	move.l	S_YLIM(sp),d7			; Zeilen; mit ylim statt ybot gleich, da vrows >= 0)
	cmp.l	a4,d5
	ble.s	z_sg1
	move.l	a4,d5
z_sg1:	cmp.l	d7,d5
	ble.s	z_sg2
	move.l	d7,d5
z_sg2:	sub.l	d4,d5
	tst.l	d4
	bmi	z_skip
	add.l	d5,d4
	muls.w	S_PITCH+2(sp),d5		; (Zeilen <= 1024, Zeilenlänge <= 640: beide < 2^15, muls.w genau wie muls.l)
	move.l	d4,S_Y(sp)			; y nach dem Segment (hinter dem muls: nicht davon abhängig)
	add.l	a0,d5
	move.l	d5,S_AEND(sp)
	PMK	6
	jmp	(a1)
z_skip:	move.l	d4,d6				; y < 0: k = min(n, -y) Zeilen nur weiterschalten
	neg.l	d6
	cmp.l	d5,d6
	ble	z_sk1
	move.l	d5,d6
z_sk1:	add.l	d6,d4
	move.l	d4,S_Y(sp)
	move.l	S_LDX(sp),d7
	muls.l	d6,d7
	add.l	d7,d0
	move.l	S_LDU(sp),d7
	muls.l	d6,d7
	add.l	d7,d2
	move.l	S_LDV(sp),d7
	muls.l	d6,d7
	add.l	d7,d3
	move.l	S_RDX(sp),d7
	muls.l	d6,d7
	add.l	d7,d1
	move.l	S_RDU(sp),d7
	muls.l	d6,d7
	add.l	d7,S_RU(sp)
	move.l	S_RDV(sp),d7
	muls.l	d6,d7
	add.l	d7,S_RV(sp)
	move.l	S_PITCH(sp),d7
	muls.l	d6,d7
	adda.l	d7,a0
	bra	z_seg2

z_exit:	PMK	4
	ifd	CPU060
	suba.l	#$8000,a2
	endif
	tst.l	S_XRET(sp)			; bedingter Sprung statt jmp (An): wird vorhergesagt
	bne	fc_done				; Einstieg aus raster_poly080 (S-Rahmen ist Teil seines Rahmens)
	lea	SLOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; linke Kette: while (lend <= y && guard-- > 0) { nx = li-1; if (P[nx].y > P[li].y) Kante L; li = nx }
; d4 = y, a3 = lend, a4 = rend (kept: y in a1 while d4 is needed); setzt d0/d2/d3, a3 / S_LEND und S_LDX/LDU/LDV
z_newl:	subq.l	#1,S_GRD(sp)			; Wächter: vorher <= 0 -> jetzt < 0
	bmi	z_l9
	move.l	S_LI(sp),a5			; P[li]
	lea	-16(a5),a6			; P[nx], nx = li - 1 (Umlauf)
	cmpa.l	S_P(sp),a6
	bhs	z_nl1
	move.l	S_PLAST(sp),a6
z_nl1:	move.l	a6,S_LI(sp)
	move.l	S_RCP(sp),a1			; (early: a1 is only this edge's until z_r9)
	move.l	4(a6),d5
	move.l	4(a5),d7			; a.y once (d7 free in the segment head)
	cmp.l	d7,d5
	ble	z_nl8
	move.l	d5,S_LEND(sp)
	movea.l	d5,a3
	sub.l	d7,d5				; dy
	move.l	(a5),d0				; a.x once (between dy and its use as an index)
	move.l	(a6),d6
	cmp.l	#1023,d5
	bgt	z_nlb
	move.l	(a1,d5.l*4),d5			; r
z_nlr:	movea.l	d4,a1				; y (the table is read)
	ifnd	CPU060
	move.l	d5,d4
	lsl.l	#8,d4
	lsl.l	#6,d4				; r << 14: (4d * (r << 14)) >> 32 = (d * r) >> 16 (MULSH16), |d| < 2^29
	endif
	sub.l	d0,d6
	swap	d0
	clr.w	d0				; xL = a.x << 16
	move.l	8(a5),d2			; uL
	move.l	12(a5),d3			; vL
	muls.l	d5,d6
	move.l	d6,S_LDX(sp)
	move.l	8(a6),d6
	sub.l	d2,d6
	lsl.l	#2,d6
	ifd	CPU060
	asr.l	#2,d6				; d wie 4d im 080-Weg (modulo 2^32)
	move.l	12(a6),d4
	sub.l	d3,d4
	lsl.l	#2,d4
	asr.l	#2,d4
	cmp.l	#65536,d5			; dy = 1: (d * 65536) >> 16 = d
	beq	z_nl1y
	RMW	d6,d7
	move.l	d7,S_LDU(sp)
	RMW	d4,d6
	move.l	d6,S_LDV(sp)
	bra	z_nly
z_nl1y:	move.l	d6,S_LDU(sp)
	move.l	d4,S_LDV(sp)
	else
	muls.l	d4,d7:d6
	move.l	d7,S_LDU(sp)
	move.l	12(a6),d6
	sub.l	d3,d6
	lsl.l	#2,d6
	muls.l	d4,d7:d6
	move.l	d7,S_LDV(sp)
	endif
z_nly:	move.l	a1,d4				; y
z_nl8:	cmp.l	a3,d4
	bge	z_newl
	bra	z_l9
z_nlb:	move.l	#65536,d7
	divs.l	d5,d7
	move.l	d7,d5
	bra	z_nlr

; rechte Kette: nx = ri+1; setzt d1, a4 / S_REND, S_RU/RV, S_RDX/RDU/RDV
z_newr:	subq.l	#1,S_GRD(sp)
	bmi	z_r9
	move.l	S_RI(sp),a5
	lea	16(a5),a6
	cmpa.l	S_PEND(sp),a6
	blo	z_nr1
	move.l	S_P(sp),a6
z_nr1:	move.l	a6,S_RI(sp)
	move.l	S_RCP(sp),a1
	move.l	4(a6),d5
	move.l	4(a5),d7			; a.y once
	cmp.l	d7,d5
	ble	z_nr8
	move.l	d5,S_REND(sp)
	movea.l	d5,a4
	sub.l	d7,d5
	move.l	(a5),d1				; a.x once
	move.l	(a6),d6
	cmp.l	#1023,d5
	bgt	z_nrb
	move.l	(a1,d5.l*4),d5
z_nrr:	movea.l	d4,a1				; y
	ifnd	CPU060
	move.l	d5,d4
	lsl.l	#8,d4
	lsl.l	#6,d4				; r << 14
	endif
	sub.l	d1,d6
	swap	d1
	clr.w	d1				; xR
	move.l	8(a5),S_RU(sp)
	move.l	12(a5),S_RV(sp)
	muls.l	d5,d6
	move.l	d6,S_RDX(sp)
	move.l	8(a6),d6
	sub.l	8(a5),d6
	lsl.l	#2,d6
	ifd	CPU060
	asr.l	#2,d6				; d wie 4d im 080-Weg (modulo 2^32)
	move.l	12(a6),d4
	sub.l	12(a5),d4
	lsl.l	#2,d4
	asr.l	#2,d4
	cmp.l	#65536,d5			; dy = 1: (d * 65536) >> 16 = d
	beq	z_nr1y
	RMW	d6,d7
	move.l	d7,S_RDU(sp)
	RMW	d4,d6
	move.l	d6,S_RDV(sp)
	bra	z_nry
z_nr1y:	move.l	d6,S_RDU(sp)
	move.l	d4,S_RDV(sp)
	else
	muls.l	d4,d7:d6
	move.l	d7,S_RDU(sp)
	move.l	12(a6),d6
	sub.l	12(a5),d6
	lsl.l	#2,d6
	muls.l	d4,d7:d6
	move.l	d7,S_RDV(sp)
	endif
z_nry:	move.l	a1,d4				; y
z_nr8:	cmp.l	a4,d4
	bge	z_newr
	bra	z_r9
z_nrb:	move.l	#65536,d7
	divs.l	d5,d7
	move.l	d7,d5
	bra	z_nrr
; rk_build: Tabellen der Zeilenschleifen je Art (d0 = Flaggen sm8 * 2 + sm3, als Bytes $ff), a1 frei
rk_build:
	move.l	d0,rk_sm
	lea	rk_row,a1
	lea	zr00_seg(pc),a5
	ifnd	CPU060				; 060: keine AMMX-Zeilenkerne (raster_sm3 gilt dort nur für die HUD-Kerne)
	tst.l	raster_sm8
	beq	rk_b0
	lea	zr70_seg(pc),a5
	endif
rk_b0:	move.l	a5,(a1)+			; 0 TEX
	lea	zr10_seg(pc),a5
	ifnd	CPU060				; 060: keine AMMX-Zeilenkerne (raster_sm3 gilt dort nur für die HUD-Kerne)
	tst.l	raster_sm3
	beq	rk_b1
	lea	zr60_seg(pc),a5
	endif
rk_b1:	move.l	a5,(a1)+			; 1 KEY
	lea	zf2_seg(pc),a5
	ifnd	K68				; 68080: FLAT mit store/storem nach Gerätetest
	tst.l	raster_sm8
	beq	rk_bf
	lea	zf10_seg(pc),a5
	endif
rk_bf:	move.l	a5,(a1)+			; 2 FLAT
	lea	zf3_seg(pc),a5
	move.l	a5,(a1)+			; 3 ohne Pixel
	lea	zr40_seg(pc),a5
	move.l	a5,(a1)+			; 4 SMG
	lea	zf5_seg(pc),a5
	move.l	a5,(a1)+			; 5 SHADOW
	lea	zf3_seg(pc),a5
	move.l	a5,(a1)+			; 6 wie 3
	move.l	a5,(a1)+			; 7 wie 3
	lea	zf8_seg(pc),a5
	move.l	a5,(a1)+			; 8 Abdeckung
	lea	rk_grd,a1			; Ebenengradient (Dreiecke): 0 = nie
	lea	zf0_seg(pc),a5
	ifnd	CPU060				; 060: keine AMMX-Zeilenkerne (raster_sm3 gilt dort nur für die HUD-Kerne)
	tst.l	raster_sm8
	beq	rk_b2
	lea	zf7_seg(pc),a5
	endif
rk_b2:	move.l	a5,(a1)+			; 0
	lea	zf1_seg(pc),a5
	ifnd	CPU060				; 060: keine AMMX-Zeilenkerne (raster_sm3 gilt dort nur für die HUD-Kerne)
	tst.l	raster_sm3
	beq	rk_b3
	lea	zf6_seg(pc),a5
	endif
rk_b3:	move.l	a5,(a1)+			; 1
	clr.l	(a1)+				; 2
	clr.l	(a1)+				; 3
	lea	zf4_seg(pc),a5
	move.l	a5,(a1)+			; 4
	clr.l	(a1)+				; 5..8
	clr.l	(a1)+
	clr.l	(a1)+
	clr.l	(a1)+
	lea	rk_row,a5			; ohne Zuschnitt: wie rk_row, TEX/KEY/SMG mit den Varianten zr*1
	lea	rk_rown,a1
	moveq	#8,d1
rk_bn:	move.l	(a5)+,(a1)+
	dbra	d1,rk_bn
	lea	rk_rown,a1
	lea	zr01_seg(pc),a5
	ifnd	CPU060				; 060: keine AMMX-Zeilenkerne (raster_sm3 gilt dort nur für die HUD-Kerne)
	tst.l	raster_sm8
	beq	rk_b4
	lea	zr71_seg(pc),a5
	endif
	ifd	CPU060
	tst.l	raster_texu
	beq	rk_b4
	lea	zr91_seg(pc),a5			; TEX mit u getauscht (SCREAMER_TEXU)
	endif
rk_b4:	move.l	a5,(a1)				; 0
	lea	zr11_seg(pc),a5
	ifd	CPU060
	tst.l	raster_texu
	beq	rk_b5
	lea	zr111_seg(pc),a5		; KEY mit u getauscht
	endif
	ifnd	CPU060				; 060: keine AMMX-Zeilenkerne (raster_sm3 gilt dort nur für die HUD-Kerne)
	tst.l	raster_sm3
	beq	rk_b5
	lea	zr61_seg(pc),a5
	endif
rk_b5:	move.l	a5,4(a1)			; 1
	lea	zr41_seg(pc),a5
	move.l	a5,16(a1)			; 4
	; the late occluders' cut variants (OCC): as the three tables above, the kinds with a cut variant replaced
	lea	rk_row,a5
	lea	rk_rowc,a1
	moveq	#3*9-1,d1
rk_bc:	move.l	(a5)+,(a1)+
	dbra	d1,rk_bc
	lea	rk_rowc,a1
	ifd	CPU060
	lea	zr00c_seg,a5
	move.l	a5,(a1)				; 0 TEX
	lea	zr10c_seg,a5
	move.l	a5,4(a1)			; 1 KEY
	lea	zf2c_seg,a5
	move.l	a5,8(a1)			; 2 FLAT
	else
	tst.l	raster_sm8			; (without the 080's kernels: the rows without the cut, as they are)
	beq	rk_c1
	lea	zr70c_seg,a5
	move.l	a5,(a1)
	ifnd	K68
	lea	zf10c_seg,a5
	move.l	a5,8(a1)
	endif
rk_c1:	tst.l	raster_sm3
	beq	rk_c2
	lea	zr60c_seg,a5
	move.l	a5,4(a1)
rk_c2:
	endif
	lea	zr40c_seg,a5
	move.l	a5,16(a1)			; 4 SMG
	lea	zf5c_seg,a5
	move.l	a5,20(a1)			; 5 SHADOW
	lea	rk_grdc,a1
	lea	zf4c_seg,a5
	move.l	a5,16(a1)			; 4 (triangles: the gradient's rows)
	lea	rk_rowc,a5			; without the clip's tests: as rk_rowc, TEX/KEY/SMG with the variants *1c
	lea	rk_rownc,a1
	moveq	#8,d1
rk_bnc:	move.l	(a5)+,(a1)+
	dbra	d1,rk_bnc
	lea	rk_rownc,a1
	ifd	CPU060
	lea	zr01c_seg,a5			; (not TEXU's 9 / 11: the plain kernels, the same pixels)
	move.l	a5,(a1)
	lea	zr11c_seg,a5
	move.l	a5,4(a1)
	else
	move.l	rk_rown,(a1)			; (the 080 without its kernels: as without the cut)
	move.l	rk_rown+4,4(a1)
	tst.l	raster_sm8
	beq	rk_c3
	lea	zr71c_seg,a5
	move.l	a5,(a1)
rk_c3:	tst.l	raster_sm3
	beq	rk_c4
	lea	zr61c_seg,a5
	move.l	a5,4(a1)
rk_c4:
	endif
	lea	zr41c_seg,a5
	move.l	a5,16(a1)			; 4
	rts

; ---------------------------------------------------------------- die sechs Zeilenschleifen
	ZROW	0,0
	ZROW	1,0
	ZROW	4,0
	ZROW	6,0
	ZROW	7,0
	ZROW	0,1
	ifd	CPU060
	ZROW	9,1
	ZROW	11,1
	endif
	ZROW	1,1
	ZROW	4,1
	ZROW	6,1
	ZROW	7,1
	ZROWF	0
	ZROWF	1
	ZROWF	2
	ZROWF	3
	ZROWF	4
	ZROWF	5
	ZROWF	6
	ZROWF	7
	ZROWF	8
	ifnd	K68
	ZROWF	10
	endif


; ---------------------------------------------------------------- (OpenScreamer) the data the kernel reads
; the switches as on the 68060, the row tables it builds itself
; ---------------------------------------------------------------- (OpenScreamer) THE PAINTER'S LIST in vasm
; void pt_draw_list(const pt_lctx *c): every polygon of the sorted objects, as main.c pt_paint's loop with span.c's
; span_draw does it (the C reference: OS_PTDRAW=0) -- area and box in one pass, the winding, the two chains, then
; straight into the row engine at rsp_d with the frame kept for the whole list (S_XRET = 1: back at fc_done).
; A polygon off the picture goes to C (c->clip = span_draw: the cut).
; pt_lctx: 0 objs, 4 nobj, 8 polys, 12 target, 16 clip, 20 base, 24 pitch, 28 w, 32 h, 36 rcp, 40 smg, 44 remap, 48 ramk
; pt_obj 16 bytes {first, count, key, order}; pt_poly 136 bytes {tex.l, n.b, kind.b, color.b, pad, 8 x span_v}
F_A	equ	SLOC				; the polygon in the chains' winding, and the cut's: 24 corners
F_B	equ	SLOC+384			; the cut's other buffer
F_P	equ	SLOC+768			; the chains: up to 2 n + 2 corners
F_CTX	equ	SLOC+1152
F_OBJ	equ	SLOC+1156
F_OBJN	equ	SLOC+1160
F_POLY	equ	SLOC+1164
F_PN	equ	SLOC+1168
F_W	equ	SLOC+1172
F_H	equ	SLOC+1176
F_N	equ	SLOC+1180
F_PH	equ	SLOC+1184			; 1: the cover pass (the last objects' TEX / FLAT polygons into oc_cov)
F_OCF	equ	SLOC+1188			; objects still to come whose polygons may be cut (< 0: none)
F_OCN	equ	SLOC+1192			; how many objects may be cut (nobj - raster_occk)
F_CY0	equ	SLOC+1196			; the cover's rows: least, largest (a superset)
F_CY1	equ	SLOC+1200
FLOC	equ	SLOC+1204

; PUTV \1: corner (a1) to P (a2)+, y + \1; the top corner (first with the least y, + 8 as zt_d2 wants it: d5), the
; least and largest y (d3, d4) noted on the way, as zt_l would find them (S_PVAL = 1: zt_l not run)
PUTV	macro
	move.l	(a1),(a2)+
	move.l	4(a1),d0
	if	\1
	addq.l	#1,d0
	endif
	move.l	d0,(a2)+
	cmp.l	d3,d0
	bge.s	.p1\@
	move.l	d0,d3
	move.l	a2,d5
.p1\@:	cmp.l	d4,d0
	ble.s	.p2\@
	move.l	d0,d4
.p2\@:	move.l	8(a1),(a2)+
	move.l	12(a1),(a2)+
	endm
	xdef	_pt_draw_list
	xdef	pt_draw_list
_pt_draw_list:
pt_draw_list:
	movem.l	d2-d7/a2-a6,-(sp)
	moveq	#0,d0				; rsp_d's test of the row tables once a list (raster_sm8 / raster_sm3 do
	tst.l	raster_sm8			; not change during one): every polygon then straight to rk_ok
	sne	d0
	add.l	d0,d0
	tst.l	raster_sm3
	sne	d0
	cmp.l	rk_sm,d0
	beq.s	dl_rk
	bsr	rk_build
dl_rk:	lea	-FLOC(sp),sp
	PMK0					; (measuring build: the list's start the reference -- section 3 of its first polygon
						; counted all the time since the last list's end before)
	move.l	raster_dlnocl,S_NOCL(sp)	; every polygon is within 0 .. w-1 here (cut, or found inside): the rows
						; without the cut's tests (TEX: TEXU) -- once a list (S_KIND: not read on this way)
	move.l	FLOC+48(sp),a0
	move.l	a0,F_CTX(sp)
	moveq	#1,d0
	move.l	d0,S_XRET(sp)
	move.l	24(a0),S_PITCH(sp)
	move.l	28(a0),d0
	move.l	d0,F_W(sp)
	subq.l	#1,d0
	move.l	d0,S_XMAX(sp)
	move.l	32(a0),d0
	move.l	d0,F_H(sp)
	move.l	d0,S_VROWS(sp)
	move.l	36(a0),d0
	move.l	d0,S_RCP(sp)
	add.l	#4096,d0
	move.l	d0,S_RCPR(sp)
	move.l	40(a0),S_SMG(sp)
	move.l	44(a0),S_REMAP(sp)
	move.l	48(a0),S_RAMK(sp)
	ifnd	CPU060
	move.l	48(a0),d0			; (68080: SMG's transposed table up to date, once a list)
	bsr	zsm_chk
	endif
	clr.l	S_COV(sp)
	move.l	20(a0),d0
	neg.l	d0
	move.l	d0,S_NBASE(sp)
	move.l	(a0),F_OBJ(sp)
	move.l	4(a0),F_OBJN(sp)
	; THE LATE OCCLUDERS (OCC): first the cover of the last raster_occk objects' TEX / FLAT polygons
	clr.l	F_PH(sp)
	clr.l	S_OCC(sp)
	clr.l	S_OC2(sp)
	clr.l	F_OCF(sp)
	moveq	#-1,d0
	move.l	d0,S_OBJI(sp)
	move.l	raster_occk,d0
	ble	dl_obj
	move.l	4(a0),d1
	cmp.l	#2,d1
	blt	dl_obj
	sub.l	d0,d1				; the objects before them (k >= nobj: all)
	bpl.s	dl_ok1
	moveq	#0,d1
	move.l	4(a0),d0
dl_ok1:
	move.l	24(a0),d2			; pitch: a multiple of 64, >= 256 (an entry a row at (row - base) >> 6)
	moveq	#63,d3
	and.l	d2,d3
	bne	dl_obj
	lsr.l	#6,d2
	cmp.l	#4,d2
	blt	dl_obj
	move.l	32(a0),d3			; h rows (as S_VROWS)
	ble	dl_obj
	move.l	d2,d4
	mulu.l	d3,d4
	cmp.l	#OC_SIZE-4,d4
	bgt	dl_obj
	move.l	4(a0),d4
	subq.l	#1,d4
	move.l	d4,F_OCN(sp)			; every object but the last may be cut (where a later one covers)
	move.l	d1,d4
	subq.l	#1,d4
	move.l	d4,S_OBJI(sp)			; (the cover pass: from nobj - k)
	lea	oc_cov,a1			; every row empty
	move.l	#$7fff8000,d4
	subq.l	#1,d3
dl_oci:	move.l	d4,(a1)
	adda.l	d2,a1
	dbra	d3,dl_oci
	move.l	#oc_cov,S_COV(sp)		; (ZPIX8's)
	move.l	#$7fffffff,F_CY0(sp)
	move.l	#$80000000,F_CY1(sp)
	lsl.l	#4,d1
	add.l	d1,F_OBJ(sp)			; the last objects
	move.l	d0,F_OBJN(sp)
	moveq	#1,d0
	move.l	d0,F_PH(sp)
dl_obj:	subq.l	#1,F_OBJN(sp)
	bmi	dl_oe
	subq.l	#1,F_OCF(sp)			; (>= 0: this object's polygons may be cut)
	addq.l	#1,S_OBJI(sp)
	move.l	F_OBJ(sp),a1
	add.l	#16,F_OBJ(sp)
	move.l	4(a1),F_PN(sp)			; count
	move.l	(a1),d1				; first
	mulu.l	#136,d1
	move.l	F_CTX(sp),a0
	add.l	8(a0),d1
	move.l	d1,F_POLY(sp)
fc_done:					; (back from the row engine: the next polygon)
dl_poly:
	subq.l	#1,F_PN(sp)
	bmi	dl_obj
	move.l	F_POLY(sp),a3
	add.l	#136,F_POLY(sp)
	tst.l	F_PH(sp)			; the cover pass: TEX and FLAT only
	beq.s	dl_p0
	move.b	5(a3),d0
	beq.s	dl_p0
	cmp.b	#2,d0
	bne	dl_poly
dl_p0:	moveq	#0,d5
	move.b	4(a3),d5			; n
	cmp.l	#3,d5
	blt	dl_poly
	cmp.l	#8,d5
	bgt	dl_poly
	move.l	d5,F_N(sp)
	lea	8(a3),a5			; V
	move.l	d5,d0
	lsl.l	#4,d0
	lea	(a5,d0.l),a6			; &V[n]
	cmp.l	#4,d5				; quads and triangles (nearly all): the quick set-up first
	beq	dl_q4
	cmp.l	#3,d5
	beq	dl_q3
dl_gen:	; the area (2x, 32 bits round as C's int) and the box, one pass: d0 minx d1 maxx d2 miny d3 maxy d4 area
	move.l	(a5),d0
	move.l	d0,d1
	move.l	4(a5),d2
	move.l	d2,d3
	moveq	#0,d4
	move.l	a5,a1
	lea	16(a5),a2
	move.l	d5,d6
	subq.l	#1,d6
dl_ar:	cmpa.l	a6,a2
	bne.s	dl_ar1
	move.l	a5,a2
dl_ar1:	move.l	(a2),d5				; a.x b.y - b.x a.y; a.x kept in a0 for the box (a0 free here), the two
	movea.l	(a1),a0				; products apart
	muls.l	4(a1),d5			; b.x a.y
	move.l	a0,d7
	muls.l	4(a2),d7			; a.x b.y
	cmpa.l	d0,a0
	bge.s	dl_ar2
	move.l	a0,d0
dl_ar2:	sub.l	d5,d7
	add.l	d7,d4
	cmpa.l	d1,a0
	ble.s	dl_ar3
	move.l	a0,d1
dl_ar3:	move.l	4(a1),d7
	cmp.l	d2,d7
	bge.s	dl_ar4
	move.l	d7,d2
dl_ar4:	cmp.l	d3,d7
	ble.s	dl_ar5
	move.l	d7,d3
dl_ar5:	lea	16(a1),a1
	lea	16(a2),a2
	dbra	d6,dl_ar
	; nothing to draw?
	tst.l	d4
	beq	dl_poly
	tst.l	F_PH(sp)			; the cover pass: only polygons of 2 x area >= raster_occa (the small ones
	beq.s	dl_ar6				; cost their rows and cover little)
	move.l	d4,d5
	bpl.s	dl_ar7
	neg.l	d5
dl_ar7:	cmp.l	raster_occa,d5
	blt	dl_poly
dl_ar6:
	tst.l	d1
	bmi	dl_poly
	cmp.l	F_W(sp),d0
	bge	dl_poly
	tst.l	d3
	bmi	dl_poly
	cmp.l	F_H(sp),d2
	bgt	dl_poly
	cmp.l	d0,d1
	beq	dl_poly
	; the box on the picture and the chains' winding already (area > 0): straight from V
	moveq	#0,d6				; d6: the sides to cut at (bit 0 x >= 0, 1 x <= w-1, 2 y >= 0, 3 y <= h)
	tst.l	d0
	bpl.s	dl_c1
	bset	#0,d6
dl_c1:	cmp.l	F_W(sp),d1
	blt.s	dl_c1b
	bset	#1,d6
dl_c1b:	tst.l	d2
	bpl.s	dl_c1c
	bset	#2,d6
dl_c1c:	cmp.l	F_H(sp),d3
	ble.s	dl_c2
	bset	#3,d6
dl_c2:	tst.l	d6
	bne.s	dl_cA
	tst.l	d4
	bgt	dl_wd
dl_cA:	move.l	d6,d7				; into F_A in the chains' winding (area > 0 as it is, else turned round)
	lea	F_A(sp),a1
	tst.l	d4
	bgt.s	dl_fw
	move.l	a6,a2
	move.l	F_N(sp),d6
	subq.l	#1,d6
dl_rv:	lea	-16(a2),a2
	move.l	(a2),(a1)+
	move.l	4(a2),(a1)+
	move.l	8(a2),(a1)+
	move.l	12(a2),(a1)+
	dbra	d6,dl_rv
	bra.s	dl_fd
dl_fw:	move.l	a5,a2
	move.l	F_N(sp),d6
	subq.l	#1,d6
dl_cp:	move.l	(a2)+,(a1)+
	move.l	(a2)+,(a1)+
	move.l	(a2)+,(a1)+
	move.l	(a2)+,(a1)+
	dbra	d6,dl_cp
dl_fd:	lea	F_A(sp),a5
	move.l	a1,a6
	tst.l	d7				; off the picture: cut (span.c span_draw's four passes: x >= 0, x <= w-1,
	beq	dl_wd				; y >= 0, y <= h)
dl_cut:	move.l	F_N(sp),d0			; only the sides the box goes past: at a side it keeps to, dc_clip gives the
	lea	F_A(sp),a2			; corners back as they are (and a cut at another side stays within the box)
	btst	#0,d7				; a2: the corners now (F_A or F_B), the next cut into the other
	beq.s	dl_k1
	moveq	#0,d1				; x
	moveq	#0,d2				; >= 0
	moveq	#0,d3
	bsr	dl_clip
	blt	dl_poly
dl_k1:	btst	#1,d7
	beq.s	dl_k2
	moveq	#0,d1
	move.l	F_W(sp),d2			; <= w - 1
	subq.l	#1,d2
	moveq	#1,d3
	bsr	dl_clip
	blt	dl_poly
dl_k2:	btst	#2,d7
	beq.s	dl_k3
	moveq	#4,d1				; y
	moveq	#0,d2				; >= 0
	moveq	#0,d3
	bsr	dl_clip
	blt	dl_poly
dl_k3:	btst	#3,d7
	beq.s	dl_k4
	moveq	#4,d1
	move.l	F_H(sp),d2			; <= h
	moveq	#1,d3
	bsr	dl_clip
	blt	dl_poly
dl_k4:	move.l	d0,F_N(sp)
	move.l	a2,a5
	move.l	d0,d1
	lsl.l	#4,d1
	lea	(a5,d1.l),a6
	move.l	(a5),d0				; minx == maxx after the cut: nothing
	move.l	d0,d1
	lea	16(a5),a1
dl_mx:	cmpa.l	a6,a1
	bhs.s	dl_mxd
	move.l	(a1),d2
	cmp.l	d0,d2
	bge.s	dl_mx1
	move.l	d2,d0
dl_mx1:	cmp.l	d1,d2
	ble.s	dl_mx2
	move.l	d2,d1
dl_mx2:	lea	16(a1),a1
	bra.s	dl_mx
dl_mxd:	cmp.l	d0,d1
	beq	dl_poly
dl_wd:	; m: the corner with the least x, of those the least y (the last of equal ones)
	move.l	a5,a4
	lea	16(a5),a1
dl_m:	cmpa.l	a6,a1
	bhs	dl_md
	move.l	(a1),d0
	cmp.l	(a4),d0
	blt.s	dl_m1
	bne.s	dl_m2
	move.l	4(a1),d0
	cmp.l	4(a4),d0
	bgt.s	dl_m2
dl_m1:	move.l	a1,a4
dl_m2:	lea	16(a1),a1
	bra.s	dl_m
; THE QUICK SET-UP of a quad / triangle (exact: what dl_ar .. dl_m give for it): every corner within 0 .. w-1,
; 0 .. h (unsigned compares: < 0 is large) and the area > 0 -- else the whole way above (dl_gen). The area as
; one product pair, (x0-x2)(y1-y3) - (x1-x3)(y0-y2) resp. (x1-x0)(y2-y0) - (x2-x0)(y1-y0): the same sum as dl_ar's
; modulo 2^32 (an identity of the ring). m: the corner with the least key x << 16 | y (both 0 .. 65535 here),
; the last of equal ones (searched from the last, taken only when less)
dl_gq:	move.l	F_N(sp),d5			; (n again: the whole way counts with it)
	bra	dl_gen
dl_q4:	move.l	S_XMAX(sp),a0
	move.l	F_H(sp),a1
	move.l	(a5),d0
	cmp.l	a0,d0
	bhi	dl_gq
	move.l	4(a5),d1
	cmp.l	a1,d1
	bhi	dl_gq
	move.l	16(a5),d2
	cmp.l	a0,d2
	bhi	dl_gq
	move.l	20(a5),d3
	cmp.l	a1,d3
	bhi	dl_gq
	move.l	32(a5),d4
	cmp.l	a0,d4
	bhi	dl_gq
	move.l	36(a5),d5
	cmp.l	a1,d5
	bhi	dl_gq
	move.l	48(a5),d6
	cmp.l	a0,d6
	bhi	dl_gq
	move.l	52(a5),d7
	cmp.l	a1,d7
	bhi	dl_gq
	sub.l	d4,d0				; x0 - x2
	sub.l	d7,d3				; y1 - y3
	sub.l	d6,d2				; x1 - x3
	sub.l	d5,d1				; y0 - y2
	muls.l	d3,d0
	muls.l	d1,d2
	sub.l	d2,d0				; 2 x area
	ble	dl_gq				; (none or turned round: the whole way)
	tst.l	F_PH(sp)			; the cover pass: only 2 x area >= raster_occa
	beq.s	dl_q4b
	cmp.l	raster_occa,d0
	blt	dl_poly
dl_q4b:	move.l	(a5),d1				; the keys
	swap	d1
	move.w	6(a5),d1
	move.l	16(a5),d2
	swap	d2
	move.w	22(a5),d2
	move.l	32(a5),d3
	swap	d3
	move.w	38(a5),d3
	move.l	48(a5),d4
	swap	d4
	move.w	54(a5),d4
	lea	48(a5),a4
	cmp.l	d4,d3
	bhs.s	dl_q42
	move.l	d3,d4
	lea	32(a5),a4
dl_q42:	cmp.l	d4,d2
	bhs.s	dl_q41
	move.l	d2,d4
	lea	16(a5),a4
dl_q41:	cmp.l	d4,d1
	bhs	dl_md
	move.l	a5,a4
	bra	dl_md
dl_q3:	move.l	S_XMAX(sp),a0
	move.l	F_H(sp),a1
	move.l	(a5),d0
	cmp.l	a0,d0
	bhi	dl_gq
	move.l	4(a5),d1
	cmp.l	a1,d1
	bhi	dl_gq
	move.l	16(a5),d2
	cmp.l	a0,d2
	bhi	dl_gq
	move.l	20(a5),d3
	cmp.l	a1,d3
	bhi	dl_gq
	move.l	32(a5),d4
	cmp.l	a0,d4
	bhi	dl_gq
	move.l	36(a5),d5
	cmp.l	a1,d5
	bhi	dl_gq
	sub.l	d0,d2				; x1 - x0
	sub.l	d1,d5				; y2 - y0
	sub.l	d0,d4				; x2 - x0
	sub.l	d1,d3				; y1 - y0
	muls.l	d5,d2
	muls.l	d3,d4
	sub.l	d4,d2				; 2 x area
	ble	dl_gq
	tst.l	F_PH(sp)
	beq.s	dl_q3b
	cmp.l	raster_occa,d2
	blt	dl_poly
dl_q3b:	move.l	(a5),d1
	swap	d1
	move.w	6(a5),d1
	move.l	16(a5),d2
	swap	d2
	move.w	22(a5),d2
	move.l	32(a5),d3
	swap	d3
	move.w	38(a5),d3
	lea	32(a5),a4
	cmp.l	d3,d2
	bhs.s	dl_q31
	move.l	d2,d3
	lea	16(a5),a4
dl_q31:	cmp.l	d3,d1
	bhs.s	dl_md
	move.l	a5,a4
dl_md:	; the upper chain from m while x does not fall (a1 = k), then the rest
	lea	F_P(sp),a2
	move.l	a4,a1
	move.l	#$7fffffff,d3			; least y, largest y (PUTV)
	move.l	#$80000000,d4
	PUTV	0
	move.l	F_N(sp),d6
	subq.l	#2,d6				; n - 1 steps
dl_up:	lea	16(a1),a0			; nk
	cmpa.l	a6,a0
	bne.s	dl_up1
	move.l	a5,a0
dl_up1:	cmpa.l	a4,a0
	beq.s	dl_upd
	move.l	(a0),d0
	cmp.l	(a1),d0
	blt.s	dl_upd
	move.l	a0,a1
	PUTV	0
	dbra	d6,dl_up
dl_upd:	moveq	#0,d7
	move.b	5(a3),d7			; kind
	cmp.l	#2,d7				; TEX KEY FLAT: the lower chain one row lower
	bhi.s	dl_noext
	move.l	F_N(sp),d6			; j = k, up to n + 1 corners
dl_ex:	PUTV	1
	cmpa.l	a4,a1
	beq.s	dl_chd
	lea	16(a1),a1
	cmpa.l	a6,a1
	bne.s	dl_ex1
	move.l	a5,a1
dl_ex1:	dbra	d6,dl_ex
	bra.s	dl_chd
dl_noext:
dl_ne:	lea	16(a1),a1
	cmpa.l	a6,a1
	bne.s	dl_ne1
	move.l	a5,a1
dl_ne1:	cmpa.l	a4,a1
	beq.s	dl_chd
	PUTV	0
	bra.s	dl_ne
dl_chd:	lea	F_P(sp),a0
	move.l	a0,S_P(sp)
	sub.l	a0,a2
	move.l	a2,d0
	lsr.l	#4,d0
	move.l	d0,S_NP(sp)
	move.l	d5,S_PTOP(sp)			; the top corner, least and largest y: noted by PUTV
	move.l	d3,S_PYMIN(sp)
	move.l	d4,S_PYMAX(sp)
	moveq	#1,d0
	move.l	d0,S_PVAL(sp)
	cmp.l	#2,d7				; FLAT: the colour in all four bytes
	bne.s	dl_nc
	moveq	#0,d6
	move.b	6(a3),d6
	move.l	d6,d5
	lsl.l	#8,d5
	or.l	d5,d6
	move.l	d6,d5
	swap	d5
	or.l	d5,d6
	move.l	d6,S_COLOR(sp)
dl_nc:	move.l	(a3),a2				; the texture
	move.l	F_CTX(sp),a0
	move.l	20(a0),a4			; base
	clr.l	S_OCC(sp)
	tst.l	F_PH(sp)
	bne.s	dl_cov
	tst.l	F_OCF(sp)			; an object before the occluders: its rows [ymin, ymax) against the cover's
	bmi	rk_ok
	cmp.l	F_CY1(sp),d3
	bgt	rk_ok
	cmp.l	F_CY0(sp),d4
	ble	rk_ok
	move.l	#RK_OCC,S_OCC(sp)		; the cut variants
	bra	rk_ok				; (rsp_d's table test: once, at the list's start)
dl_cov:	cmp.l	F_CY0(sp),d3			; the cover pass: kind 8 (ZPIX8 into oc_cov), its rows noted
	bge.s	dl_cv1
	move.l	d3,F_CY0(sp)
dl_cv1:	cmp.l	F_CY1(sp),d4
	ble.s	dl_cv2
	move.l	d4,F_CY1(sp)
dl_cv2:	moveq	#8,d7
	ifd	OCCSTAT
	addq.l	#1,oc_cpol
	endif
	bra	rk_ok
; the end of the objects: after the cover pass, all of them from the first
dl_oe:	tst.l	F_PH(sp)
	beq	dl_end
	clr.l	F_PH(sp)
	move.l	F_CTX(sp),a0
	move.l	(a0),F_OBJ(sp)
	move.l	4(a0),F_OBJN(sp)
	move.l	F_OCN(sp),F_OCF(sp)
	moveq	#-1,d0
	move.l	d0,S_OBJI(sp)
	move.l	F_CY0(sp),d0			; nothing covered: no cut
	cmp.l	F_CY1(sp),d0
	ble	dl_obj
	clr.l	F_OCF(sp)
	bra	dl_obj
; dl_clip: dc_clip from a2 (F_A or F_B) into the other, a2 = the result, d0 corners; cc as cmp.l #3,d0 (blt: < 3)
dl_clip:
	move.l	a2,a0
	lea	F_A+4(sp),a1			; (+4: this routine's return address on the stack)
	cmpa.l	a1,a2
	bne.s	dl_cl1
	lea	F_B+4(sp),a1
dl_cl1:	move.l	a1,-(sp)
	bsr	dc_clip
	move.l	(sp)+,a2
	cmp.l	#3,d0
	rts
; dc_clip: span.c clip_side as gcc compiles it.  In: a0 in, a1 out, d0 n, d1 the axis (0 x, 4 y), d2 lim,
; d3 keep_below (1: v <= lim kept, 0: v >= lim kept).  Out: d0 corners.  The crossing from the corner inside:
; the other coordinate a + (b - a) t0 / d (muls.l, divs.l), u / v a + (int)(t (b - a)) with t = t0 / d
; (fsmove.l, fsdiv.l, fsmul.l, fintrz: the difference goes into the FPU whole, as gcc's code has it)
dc_clip:
	movem.l	d1-d7/a2-a5,-(sp)
	move.l	d0,d7				; n
	moveq	#0,d6				; m
	move.l	a1,a5				; out
	move.l	a0,a2				; p
	moveq	#0,d5				; i
dc_l:	cmp.l	d7,d5
	bge	dc_d
	lea	16(a2),a3			; q
	move.l	d5,d4
	addq.l	#1,d4
	cmp.l	d7,d4
	bne.s	dc_q
	move.l	a0,a3
dc_q:	move.l	(a2,d1.l),d4			; pin, qin (bytes: $ff / 0)
	move.l	(a3,d1.l),d0
	tst.l	d3
	bne.s	dc_kb
	cmp.l	d2,d4
	sge	d4
	cmp.l	d2,d0
	sge	d0
	bra.s	dc_in
dc_kb:	cmp.l	d4,d2
	sge	d4
	cmp.l	d0,d2
	sge	d0
dc_in:	tst.b	d4
	beq.s	dc_x
	move.l	(a2),(a5)+			; p kept
	move.l	4(a2),(a5)+
	move.l	8(a2),(a5)+
	move.l	12(a2),(a5)+
	addq.l	#1,d6
dc_x:	cmp.b	d0,d4
	beq	dc_n
	move.l	a2,a4				; a = the inside one, a1 = the other
	move.l	a3,a1
	tst.b	d4
	bne.s	dc_ab
	move.l	a3,a4
	move.l	a2,a1
dc_ab:	move.l	(a4,d1.l),d4			; av
	move.l	(a1,d1.l),d0
	sub.l	d4,d0				; d = bv - av
	neg.l	d4
	add.l	d2,d4				; t0 = lim - av
	tst.l	d1
	bne.s	dc_ay
	move.l	d2,(a5)				; x = lim
	move.l	4(a1),d3			; (d3 kept on the stack: restored below)
	sub.l	4(a4),d3
	muls.l	d4,d3
	divs.l	d0,d3
	add.l	4(a4),d3
	move.l	d3,4(a5)
	bra.s	dc_uv
dc_ay:	move.l	(a1),d3				; y = lim, x = a.x + (b.x - a.x) t0 / d
	sub.l	(a4),d3
	muls.l	d4,d3
	divs.l	d0,d3
	add.l	(a4),d3
	move.l	d3,(a5)
	move.l	d2,4(a5)
dc_uv:	fsmove.l d4,fp0				; t = t0 / d
	fsdiv.l	d0,fp0
	move.l	8(a1),d3
	sub.l	8(a4),d3
	fsmove.x fp0,fp1
	fsmul.l	d3,fp1
	fintrz.x fp1,fp1
	fmove.l	fp1,d3
	add.l	8(a4),d3
	move.l	d3,8(a5)
	move.l	12(a1),d3
	sub.l	12(a4),d3
	fsmul.l	d3,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d3
	add.l	12(a4),d3
	move.l	d3,12(a5)
	lea	16(a5),a5
	addq.l	#1,d6
	move.l	8(sp),d3				; keep_below again (d1-d7 saved from 0(sp): d3 at 8)
dc_n:	lea	16(a2),a2
	addq.l	#1,d5
	bra	dc_l
dc_d:	move.l	d6,d0
	movem.l	(sp)+,d1-d7/a2-a5
	rts

dl_end:	lea	FLOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------- the row loops' cut variants (OCC)
	ifd	CPU060
	ZROW	0,0,c
	ZROW	0,1,c
	ZROW	1,0,c
	ZROW	1,1,c
	ZROWF	2,c
	else
	ZROW	7,0,c
	ZROW	7,1,c
	ZROW	6,0,c
	ZROW	6,1,c
	ifnd	K68
	ZROWF	10,c
	endif
	endif
	ZROW	4,0,c
	ZROW	4,1,c
	ZROWF	4,c
	ZROWF	5,c
	ifd	PMKON
; Messbau: pmk_get(w, k): w 0 Takte der Pixelschleifen, 1 Pixel, 2 Zeilen der Art k (0..15), 3 Takte, 4 Anzahl des
; Abschnitts k (PMK); w = -1: alles auf 0
	xdef	_pmk_get
	xdef	pmk_get
_pmk_get:
pmk_get:
	move.l	4(sp),d0
	bpl.s	pmg_r
	lea	pm_pc,a0
	move.w	#5*16-1,d0
pmg_c:	clr.l	(a0)+
	dbra	d0,pmg_c
	moveq	#0,d0
	rts
pmg_r:	lsl.l	#6,d0
	add.l	8(sp),d0
	add.l	8(sp),d0
	add.l	8(sp),d0
	add.l	8(sp),d0
	lea	pm_pc,a0
	move.l	(a0,d0.l),d0
	rts
	section	pmbss,bss
pm_pc:	ds.l	16
pm_px:	ds.l	16
pm_rw:	ds.l	16
pm_sum:	ds.l	16
pm_cnt:	ds.l	16
pm_t0:	ds.l	1
pm_last:	ds.l	1
	section	code,code
	endif
	section	data,data
	xdef	_raster_sm3
	xdef	raster_sm3
_raster_sm3:
raster_sm3:	dc.l	0
	xdef	_raster_sm8
	xdef	raster_sm8
_raster_sm8:
raster_sm8:	dc.l	0
	xdef	_raster_zuv
	xdef	raster_zuv
_raster_zuv:
raster_zuv:	dc.l	0
; 1 = triangles with one gradient (slim rows), 0 = every row as span_row (span.c: byte for byte the same as C)
	xdef	_raster_cgrad
	xdef	raster_cgrad
_raster_cgrad:
raster_cgrad:	dc.l	1
	xdef	_raster_texu
	xdef	raster_texu
_raster_texu:
raster_texu:	dc.l	1
	xdef	_raster_dlnocl
	xdef	raster_dlnocl
_raster_dlnocl:
raster_dlnocl:	dc.l	1			; (0: the painter's list with the cut's tests in every row, as before)
	ifd	K68
zk_buf:	ds.b	8
	endif
	cnop	0,8
zk_msk:	dc.l	0,0				; [m] = the first m bytes $ff (ZKMASK: the KEY row's rest)
	dc.l	$ff000000,0
	dc.l	$ffff0000,0
	dc.l	$ffffff00,0
	dc.l	$ffffffff,0
	dc.l	$ffffffff,$ff000000
	dc.l	$ffffffff,$ffff0000
	dc.l	$ffffffff,$ffffff00
rk_sm:	dc.l	-1
rk_row:	ds.l	9
rk_grd:	ds.l	9
rk_rown:	ds.l	9
rk_rowc:	ds.l	9				; (rk_row + RK_OCC: the cut variants, OCC)
rk_grdc:	ds.l	9
rk_rownc:	ds.l	9
; the late occluders (pt_draw_list): how many of the last objects cover (0: none; main.c OS_NOOCC / OS_OCCK)
	xdef	_raster_occk
	xdef	raster_occk
_raster_occk:
raster_occk:	dc.l	2
	xdef	_raster_occa
	xdef	raster_occa
_raster_occa:
raster_occa:	dc.l	1000
	xdef	_oc_spx
	xdef	oc_spx
_oc_spx:
oc_spx:	dc.l	0				; (OCCSTAT build: pixels not drawn, rows wholly skipped)
	xdef	_oc_srow
	xdef	oc_srow
_oc_srow:
oc_srow:	dc.l	0
	xdef	_oc_trow
	xdef	oc_trow
	xdef	_oc_crow
	xdef	oc_crow
	xdef	_oc_cpol
	xdef	oc_cpol

_oc_trow:
oc_trow:	dc.l	0			; (OCCSTAT: rows tested, cover rows, cover polygons)
_oc_crow:
oc_crow:	dc.l	0
_oc_cpol:
oc_cpol:	dc.l	0
	section	occbss,bss
oc_cov:	ds.b	OC_SIZE				; a row's {c0, c1} at (row - base) >> 6
oc_tag:	ds.b	OC_SIZE				; (oc_cov + OC_SIZE) the number of the first object in it (a word)
	section	data,data

	ifnd	CPU060
; SMG's table for the 68080's kernel (ZPIX4): zsm_t[(d << 8 | t) ^ $8000] = smg[t << 8 | d], made again when the
; table's address differs from the last one's (d0 = smg; all registers kept).  main.c sets raster_smgsrc = 0 when it
; fills pt_smg anew (the same address, other contents).
	section	code,code
zsm_chk:
	cmp.l	raster_smgsrc,d0
	bne.s	zsm_mk
	rts
zsm_mk:	movem.l	d1-d3/a1-a2,-(sp)
	move.l	d0,raster_smgsrc
	lea	zsm_t,a1
	moveq	#0,d1				; j >> 8
zsm_o:	move.l	d1,d2
	eori.b	#$80,d2				; d
	movea.l	d0,a2
	adda.l	d2,a2				; smg + d
	move.w	#255,d3
zsm_i:	move.b	(a2),(a1)+			; smg[t << 8 | d], t = 0..255
	lea	256(a2),a2
	dbra	d3,zsm_i
	addq.l	#1,d1
	cmp.l	#256,d1
	bne.s	zsm_o
	movem.l	(sp)+,d1-d3/a1-a2
	rts
	section	data,data
	xdef	_raster_smgsrc
	xdef	raster_smgsrc
_raster_smgsrc:
raster_smgsrc:	dc.l	0
	section	zsmbss,bss
zsm_t:	ds.b	65536
	section	data,data
	endif

; ---------------------------------------------------------------- (OpenScreamer) the 68080's AMMX for this task
; Supervisor() routine: SR bit 11 marks the task as an AMMX user, VampireSupport's task
; switch then keeps its E registers
	section	code,code
	xdef	_ammx_ctx_on
	xdef	ammx_ctx_on
_ammx_ctx_on:
ammx_ctx_on:
	ori.w	#$0800,(sp)
	rte
