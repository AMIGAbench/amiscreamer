; Installer (screamer_inst): Tiefpass der CD-Musik für beide Kanäle (inst_core.c fir2, gleiche Rechnung).
; void fir2_68k(const WORD *x, const WORD *h, LONG *acc)   (Stapel: x, h, acc)
;   x[0..62] Fenster Kanal 0 (halbierte Werte), Kanal 1 bei x + 1024 Byte; h[0..31] Q16
;   acc[c] = sum_k (WORD)(x[k] + x[62 - k]) * h[k] + x[31] * h[31]
; Ganz ausgerollt, feste Versätze: je Paar und Kanal move/add/muls/add.
	section	text,code

R	equ	1024				; Abstand der Kanäle im Ring (2 * RING Wörter)

	xdef	_fir2_68k
_fir2_68k:
	movem.l	d2-d4,-(sp)
	move.l	16(sp),a0			; x
	move.l	20(sp),a1			; h
	moveq	#0,d0
	moveq	#0,d3
K	set	0
	rept	31
	move.w	K*2(a1),d4
	move.w	K*2(a0),d1
	move.w	R+K*2(a0),d2
	add.w	(62-K)*2(a0),d1
	add.w	R+(62-K)*2(a0),d2
	muls.w	d4,d1
	muls.w	d4,d2
	add.l	d1,d0
	add.l	d2,d3
K	set	K+1
	endr
	move.w	62(a1),d4			; Mitte
	move.w	62(a0),d1
	move.w	R+62(a0),d2
	muls.w	d4,d1
	muls.w	d4,d2
	add.l	d1,d0
	add.l	d2,d3
	move.l	24(sp),a0
	move.l	d0,(a0)+
	move.l	d3,(a0)
	movem.l	(sp)+,d2-d4
	rts
