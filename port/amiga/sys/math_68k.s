; math_68k.s - THE GAME'S SINE AND COSINE in vasm: musl's sin / cos in double as amiga/sys/fpu64_math.c has them
; (m64_sin, m64_cos, __sin, __cos, __rem_pio2), each operation rounded to double (fd*) in gcc's order, so the
; same bits as the C (tools/mathtest: every float compared).  The large arguments (|x| >= 2^20 pi/2, Payne-Hanek)
; and Inf / NaN are the C's still: then 0 is returned and the caller asks m64_sin / m64_cos.
;
; int sc68k(float x, int cosine, float *out): 1 = *out = (float)sin(x) or (float)cos(x)
; frame: -16 x (double), -32 y[0], -24 y[1]

	section	code,code

	xdef	_sc68k
	xdef	sc68k
_sc68k:
sc68k:
	link	a6,#-32
	fmovem.x fp2-fp6,-(sp)
	movem.l	d2-d5,-(sp)
	fmove.s	8(a6),fp0
	fmove.d	fp0,-16(a6)			; x, exact
	move.l	-16(a6),d3			; its high word, with the sign
	move.l	d3,d1
	bclr	#31,d1				; ix
	tst.l	12(a6)
	bne.s	.cos
	cmp.l	#$3fe921fb,d1			; sin: |x| ~< pi/4
	bhi.s	.sred
	cmp.l	#$3e500000,d1
	blo	.done				; |x| < 2^-26: x
	bsr	ksin0
	bra	.done
.sred:	cmp.l	#$7ff00000,d1
	bhs	.slow
	bsr	rp68k
	cmp.l	#$80000000,d0
	beq	.slow				; (large)
	lea	-32(a6),a0
	and.l	#3,d0
	beq.s	.s0
	cmp.l	#2,d0
	blo.s	.s1
	beq.s	.s2
	bsr	kcos
	fneg.x	fp0
	bra	.done
.s0:	bsr	ksin1
	bra	.done
.s1:	bsr	kcos
	bra	.done
.s2:	bsr	ksin1
	fneg.x	fp0
	bra	.done
.cos:	cmp.l	#$3fe921fb,d1			; cos: |x| ~< pi/4
	bhi.s	.cred
	cmp.l	#$3e46a09e,d1
	bhs.s	.ck
	fmove.d	KD_ONE(pc),fp0			; |x| < 2^-27 sqrt 2: 1
	bra.s	.done
.ck:	lea	-32(a6),a0			; kcos(x, 0)
	move.l	-16(a6),(a0)
	move.l	-12(a6),4(a0)
	clr.l	8(a0)
	clr.l	12(a0)
	bsr	kcos
	bra.s	.done
.cred:	cmp.l	#$7ff00000,d1
	bhs.s	.slow
	bsr	rp68k
	cmp.l	#$80000000,d0
	beq.s	.slow
	lea	-32(a6),a0
	and.l	#3,d0
	beq.s	.c0
	cmp.l	#2,d0
	blo.s	.c1
	beq.s	.c2
	bsr	ksin1
	bra.s	.done
.c0:	bsr	kcos
	bra.s	.done
.c1:	bsr	ksin1
	fneg.x	fp0
	bra.s	.done
.c2:	bsr	kcos
	fneg.x	fp0
.done:	move.l	16(a6),a0
	fsmove.x fp0,fp0			; (float) of the double, as gcc's: to 24 bits, then stored
	fmove.s	fp0,(a0)
	moveq	#1,d0
	bra.s	.x
.slow:	moveq	#0,d0
.x:	movem.l	(sp)+,d2-d5
	fmovem.x (sp)+,fp2-fp6
	unlk	a6
	rts

; __sin(x, 0, 0) of x at -16(a6) -> fp0
ksin0:
	fdmove.d -16(a6),fp0
	fdmul.x	fp0,fp0				; z
	fdmove.x fp0,fp2
	fdmul.x	fp0,fp2
	fdmul.x	fp0,fp2				; z w
	fdmove.x fp0,fp4
	fdmul.d	KD_S6(pc),fp4
	fdsub.d	KD_S5A(pc),fp4
	fdmul.x	fp4,fp2
	fdmove.x fp0,fp4
	fdmul.d	KD_S4(pc),fp4
	fdsub.d	KD_S3A(pc),fp4
	fdmul.x	fp0,fp4
	fdadd.d	KD_S2(pc),fp4
	fdadd.x	fp4,fp2				; r
	fdmul.x	fp0,fp2
	fdsub.d	KD_S1A(pc),fp2			; S1 + z r
	fdmul.d	-16(a6),fp0			; v = z x
	fdmul.x	fp2,fp0
	fdadd.d	-16(a6),fp0
	rts

; __sin(y0, y1, 1) of a0 -> fp0
ksin1:
	fdmove.d 8(a0),fp3			; y
	fdmove.d (a0),fp0			; x
	fdmove.x fp0,fp5
	fdmul.x	fp0,fp5				; z
	fdmove.x fp0,fp1
	fdmul.x	fp5,fp1				; v
	fdmove.x fp3,fp2
	fdmul.d	KD_HALF(pc),fp2			; 0.5 y
	fdmove.x fp5,fp4
	fdmul.x	fp5,fp4
	fdmul.x	fp5,fp4				; z w
	fdmove.x fp5,fp6
	fdmul.d	KD_S6(pc),fp6
	fdsub.d	KD_S5A(pc),fp6
	fdmul.x	fp6,fp4
	fdmove.x fp5,fp6
	fdmul.d	KD_S4(pc),fp6
	fdsub.d	KD_S3A(pc),fp6
	fdmul.x	fp5,fp6
	fdadd.d	KD_S2(pc),fp6
	fdadd.x	fp6,fp4				; r
	fdmul.x	fp1,fp4				; v r
	fdsub.x	fp4,fp2
	fdmul.x	fp5,fp2
	fdsub.x	fp3,fp2
	fdmul.d	KD_S1A(pc),fp1			; - v S1
	fdadd.x	fp1,fp2
	fdsub.x	fp2,fp0
	rts

; __cos(y0, y1) of a0 -> fp0
kcos:
	fdmove.d (a0),fp4			; x
	fdmove.x fp4,fp1
	fdmul.x	fp4,fp1				; z
	fdmove.x fp1,fp6
	fdmul.x	fp1,fp6				; w
	fdmove.x fp1,fp3
	fdmul.d	KD_HALF(pc),fp3			; hz
	fmove.d	KD_ONE(pc),fp0
	fdsub.x	fp3,fp0				; w = 1 - hz
	fdmove.x fp1,fp2
	fdmul.d	KD_C6(pc),fp2
	fdadd.d	KD_C5(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	KD_C4A(pc),fp2
	fdmul.x	fp6,fp6
	fdmul.x	fp6,fp2
	fdmove.x fp1,fp6
	fdmul.d	KD_C3(pc),fp6
	fdsub.d	KD_C2A(pc),fp6
	fdmul.x	fp1,fp6
	fdadd.d	KD_C1(pc),fp6
	fdmul.x	fp1,fp6
	fdadd.x	fp6,fp2				; r
	fdmul.x	fp1,fp2				; z r
	fdmul.d	8(a0),fp4			; x y
	fdsub.x	fp4,fp2
	fmove.d	KD_ONE(pc),fp4
	fdsub.x	fp0,fp4
	fdsub.x	fp3,fp4				; (1 - w) - hz
	fdadd.x	fp4,fp2
	fdadd.x	fp2,fp0
	rts

; __rem_pio2(x at -16(a6), d3 its high word, d1 ix) -> y at -32(a6), d0 = n; d0 < 0 (not -1..-4: $80000000) =
; large, the C's
RP_SMALL macro					; \1 the multiple of pio2_1, \2 of pio2_1t, \3 n
	tst.l	d3
	bmi.s	.n\@
	fdsub.d	\1(pc),fp0
	fdmove.x fp0,fp1
	fdsub.d	\2(pc),fp1
	fmove.d	fp1,(a0)
	fdsub.x	fp1,fp0
	fdsub.d	\2(pc),fp0
	fmove.d	fp0,8(a0)
	moveq	#\3,d0
	rts
.n\@:	fdadd.d	\1(pc),fp0
	fdmove.x fp0,fp1
	fdadd.d	\2(pc),fp1
	fmove.d	fp1,(a0)
	fdsub.x	fp1,fp0
	fdadd.d	\2(pc),fp0
	fmove.d	fp0,8(a0)
	moveq	#-\3,d0
	rts
	endm
rp68k:
	lea	-32(a6),a0
	cmp.l	#$400f6a7a,d1			; |x| ~<= 5pi/4
	bhi	.r1
	move.l	d3,d0
	and.l	#$fffff,d0
	cmp.l	#$921fb,d0
	beq	.med
	fdmove.d -16(a6),fp0
	cmp.l	#$4002d97c,d1
	bhi	.r2
	RP_SMALL KD_P1,KD_P1T,1
.r2:	RP_SMALL KD_P1X2,KD_P1TX2,2
.r1:	cmp.l	#$401c463b,d1			; |x| ~<= 9pi/4
	bhi	.r5
	cmp.l	#$4015fdbc,d1
	bhi	.r4
	cmp.l	#$4012d97c,d1
	beq	.med
	fdmove.d -16(a6),fp0
	RP_SMALL KD_P1X3,KD_P1TX3,3
.r4:	cmp.l	#$401921fb,d1
	beq	.med
	fdmove.d -16(a6),fp0
	RP_SMALL KD_P1X4,KD_P1TX4,4
.r5:	cmp.l	#$413921fb,d1			; medium: |x| ~< 2^20 pi/2
	blo	.med
	move.l	#$80000000,d0
	rts
.med:	fdmove.d -16(a6),fp2
	fdmul.d	KD_INVPIO2(pc),fp2
	fdadd.d	KD_TOINT(pc),fp2
	fdsub.d	KD_TOINT(pc),fp2		; fn
	fintrz.x fp2,fp0
	fmove.l	fp0,d0				; n
	bsr	.rw
	fcmp.d	KD_MPIO4(pc),fp3
	fblt	.dec
	fcmp.d	KD_PIO4(pc),fp3
	fbgt	.inc
.m2:	fmove.d	fp3,(a0)			; y0 = r - w
	move.l	d1,d4
	moveq	#20,d2
	lsr.l	d2,d4				; ex
	move.l	(a0),d5
	lsr.l	d2,d5
	and.l	#$7ff,d5			; ey
	move.l	d4,d2
	sub.l	d5,d2
	cmp.l	#16,d2
	ble	.y1
	fdmove.x fp2,fp1			; the second round
	fdmul.d	KD_P2(pc),fp1
	fdmove.x fp0,fp4
	fdsub.x	fp1,fp4				; r = t - w
	fdsub.x	fp4,fp0
	fdsub.x	fp1,fp0				; (t - r) - w
	fdmove.x fp2,fp1
	fdmul.d	KD_P2T(pc),fp1
	fdsub.x	fp0,fp1				; w
	fdmove.x fp4,fp0
	fdsub.x	fp1,fp0
	fmove.d	fp0,(a0)			; y0
	move.l	(a0),d5
	moveq	#20,d2
	lsr.l	d2,d5
	and.l	#$7ff,d5
	move.l	d4,d2
	sub.l	d5,d2
	cmp.l	#49,d2
	ble	.y2
	fdmove.x fp2,fp1			; the third round
	fdmul.d	KD_P3(pc),fp1
	fdmove.x fp4,fp0
	fdsub.x	fp1,fp0				; r
	fdsub.x	fp0,fp4
	fdsub.x	fp1,fp4
	fdmul.d	KD_P3T(pc),fp2
	fdmove.x fp2,fp1
	fdsub.x	fp4,fp1				; w
	fdmove.x fp0,fp2
	fdsub.x	fp1,fp2
	fmove.d	fp2,(a0)			; y0
	bra	.y1
.y2:	fdmove.x fp4,fp0			; (r of the second round)
.y1:	fdsub.d	(a0),fp0			; y1 = (r - y0) - w
	fdsub.x	fp1,fp0
	fmove.d	fp0,8(a0)
	rts
.dec:	subq.l	#1,d0
	fdsub.d	KD_ONE(pc),fp2
	bsr	.rw
	bra	.m2
.inc:	addq.l	#1,d0
	fdadd.d	KD_ONE(pc),fp2
	bsr	.rw
	bra	.m2
.rw:	fdmove.x fp2,fp1			; fp0 = r = x - fn pio2_1, fp1 = w = fn pio2_1t, fp3 = r - w (double)
	fdmul.d	KD_P1(pc),fp1
	fdmove.d -16(a6),fp0
	fdsub.x	fp1,fp0
	fdmove.x fp2,fp1
	fdmul.d	KD_P1T(pc),fp1
	fdmove.x fp0,fp3
	fdsub.x	fp1,fp3
	rts

	cnop	0,4
KD_ONE:		dc.l	$3ff00000,$00000000
KD_HALF:	dc.l	$3fe00000,$00000000
KD_S1A:		dc.l	$3fc55555,$55555549
KD_S2:		dc.l	$3f811111,$1110f8a6
KD_S3A:		dc.l	$3f2a01a0,$19c161d5
KD_S4:		dc.l	$3ec71de3,$57b1fe7d
KD_S5A:		dc.l	$3e5ae5e6,$8a2b9ceb
KD_S6:		dc.l	$3de5d93a,$5acfd57c
KD_C1:		dc.l	$3fa55555,$5555554c
KD_C2A:		dc.l	$3f56c16c,$16c15177
KD_C3:		dc.l	$3efa01a0,$19cb1590
KD_C4A:		dc.l	$3e927e4f,$809c52ad
KD_C5:		dc.l	$3e21ee9e,$bdb4b1c4
KD_C6:		dc.l	$bda8fae9,$be8838d4
KD_P1:		dc.l	$3ff921fb,$54400000
KD_P1T:		dc.l	$3dd0b461,$1a626331
KD_P1X2:	dc.l	$400921fb,$54400000
KD_P1TX2:	dc.l	$3de0b461,$1a626331
KD_P1X3:	dc.l	$4012d97c,$7f300000
KD_P1TX3:	dc.l	$3de90e91,$a79394ca
KD_P1X4:	dc.l	$401921fb,$54400000
KD_P1TX4:	dc.l	$3df0b461,$1a626331
KD_INVPIO2:	dc.l	$3fe45f30,$6dc9c883
KD_TOINT:	dc.l	$43380000,$00000000
KD_MPIO4:	dc.l	$bfe921fb,$54442d18
KD_PIO4:	dc.l	$3fe921fb,$54442d18
KD_P2:		dc.l	$3dd0b461,$1a600000
KD_P2T:		dc.l	$3ba3198a,$2e037073
KD_P3:		dc.l	$3ba3198a,$2e000000
KD_P3T:		dc.l	$397b839a,$252049c1

; int at68k(float a, float b, int two, float *out): two = 0: *out = (float)atan(a), 1: (float)atan2(a, b) -- musl's
; as fpu64_math.c (m64_atan_, m64_atan2_), every operation rounded to double in gcc's order.  0: a case the C
; answers (a zero, Inf / NaN, x = 1 exactly, |y / x| beyond 2^64 either way, |x| >= 2^66).
; frame: -8 x (double)
	section	code,code
	xdef	_at68k
	xdef	at68k
_at68k:
at68k:
	link	a6,#-8
	fmovem.x fp2,-(sp)
	movem.l	d2-d3,-(sp)
	tst.l	16(a6)
	bne	.two
	fmove.s	8(a6),fp0
	fmove.d	fp0,-8(a6)
	bsr	atan_
	tst.l	d0
	beq	.slow
	bra	.done
.two:	fmove.s	12(a6),fp0			; x
	fmove.d	fp0,-8(a6)
	move.l	-8(a6),d2			; ix with the sign
	move.l	d2,d0
	and.l	#$7ff00000,d0
	cmp.l	#$7ff00000,d0
	beq	.slow
	cmp.l	#$3ff00000,d2			; x = 1.0 (a float's low word is 0 when it is)
	bne	.t1
	tst.l	-4(a6)
	beq	.slow
.t1:	fmove.s	8(a6),fp1			; y
	fmove.d	fp1,-(sp)
	move.l	(sp)+,d3			; iy with the sign
	addq.l	#4,sp
	move.l	d3,d0
	and.l	#$7ff00000,d0
	cmp.l	#$7ff00000,d0
	beq	.slow
	move.l	d3,d1				; m = 2 sign(x) + sign(y)
	moveq	#31,d0
	lsr.l	d0,d1
	move.l	d2,d0
	rol.l	#2,d0
	and.l	#2,d0
	or.l	d0,d1
	bclr	#31,d2
	bclr	#31,d3
	fmove.s	8(a6),fp0
	fbeq	.slow				; y = 0
	fmove.s	12(a6),fp0
	fbeq	.slow				; x = 0
	move.l	d2,d0
	add.l	#64<<20,d0
	cmp.l	d3,d0
	blo	.slow				; |y / x| > 2^64
	btst	#1,d1
	beq	.t2
	move.l	d3,d0
	add.l	#64<<20,d0
	cmp.l	d2,d0
	blo	.slow				; |y / x| < 2^-64, x < 0
.t2:	move.l	d1,-(sp)
	fdmove.s 8(a6),fp0
	fddiv.s	12(a6),fp0			; y / x
	fabs.x	fp0
	fmove.d	fp0,-8(a6)
	bsr	atan_
	move.l	(sp)+,d1
	tst.l	d0
	beq	.slow
	and.l	#3,d1
	beq	.done
	cmp.l	#2,d1
	blo	.m1
	beq	.m2
	fdsub.d	KD_PILO(pc),fp0			; (z - pi_lo) - pi
	fdsub.d	KD_PI(pc),fp0
	bra	.done
.m1:	fneg.x	fp0
	bra	.done
.m2:	fdsub.d	KD_PILO(pc),fp0			; pi - (z - pi_lo)
	fmove.d	KD_PI(pc),fp1
	fdsub.x	fp0,fp1
	fmove.x	fp1,fp0
.done:	move.l	20(a6),a0
	fsmove.x fp0,fp0
	fmove.s	fp0,(a0)
	moveq	#1,d0
	bra	.x
.slow:	moveq	#0,d0
.x:	movem.l	(sp)+,d2-d3
	fmovem.x (sp)+,fp2
	unlk	a6
	rts

; atan of the double at -8(a6) -> fp0, d0 = 1; d0 = 0: |x| >= 2^66 or NaN (the C's)
atan_:
	move.l	-8(a6),d3
	move.l	d3,d1				; sign
	moveq	#31,d0
	lsr.l	d0,d1
	bclr	#31,d3				; ix
	cmp.l	#$44100000,d3
	bhs	.no
	cmp.l	#$3fdc0000,d3			; |x| < 0.4375
	bhs	.red
	fdmove.d -8(a6),fp0
	cmp.l	#$3e400000,d3
	blo	.yes				; |x| < 2^-27: x
	moveq	#-1,d2
	bra	.poly
.red:	fdabs.d	-8(a6),fp0
	cmp.l	#$3ff30000,d3
	bhs	.r23
	fdmove.x fp0,fp2
	cmp.l	#$3fe5ffff,d3
	bhi	.r1
	fdadd.x	fp0,fp2				; (2x - 1) / (2 + x)
	fdsub.d	KD_ONE(pc),fp2
	fdadd.d	KD_TWO(pc),fp0
	fddiv.x	fp0,fp2
	moveq	#0,d2
	bra	.st
.r1:	fdsub.d	KD_ONE(pc),fp2			; (x - 1) / (x + 1)
	fdadd.d	KD_ONE(pc),fp0
	fddiv.x	fp0,fp2
	moveq	#1,d2
	bra	.st
.r23:	cmp.l	#$40037fff,d3
	bhi	.r3
	fdmove.x fp0,fp2			; (x - 1.5) / (1 + 1.5 x)
	fdsub.d	KD_1P5(pc),fp2
	fdmul.d	KD_1P5(pc),fp0
	fdadd.d	KD_ONE(pc),fp0
	fddiv.x	fp0,fp2
	moveq	#2,d2
	bra	.st
.r3:	fmove.d	KD_MONE(pc),fp2			; -1 / x
	fddiv.x	fp0,fp2
	moveq	#3,d2
.st:	fmove.d	fp2,-8(a6)
.poly:	fdmove.d -8(a6),fp2
	fdmul.x	fp2,fp2				; z
	fdmove.x fp2,fp1
	fdmul.x	fp2,fp1				; w
	fdmove.x fp1,fp0
	fdmul.d	KD_AT10(pc),fp0
	fdadd.d	KD_AT8(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	KD_AT6(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	KD_AT4(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	KD_AT2(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	KD_AT0(pc),fp0
	fdmul.x	fp2,fp0				; s1
	fdmove.x fp1,fp2
	fdmul.d	KD_AT9(pc),fp2
	fdsub.d	KD_AT7A(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	KD_AT5A(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	KD_AT3A(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	KD_AT1A(pc),fp2
	fdmul.x	fp1,fp2				; s2
	fdadd.x	fp2,fp0
	fdmove.d -8(a6),fp1
	fdmul.x	fp0,fp1				; x (s1 + s2)
	tst.l	d2
	bpl	.hi
	fdmove.d -8(a6),fp0
	fdsub.x	fp1,fp0
	bra	.yes
.hi:	lea	KD_ATLO(pc),a0
	fdsub.d	(a0,d2.l*8),fp1
	fdsub.d	-8(a6),fp1
	lea	KD_ATHI(pc),a0
	fdmove.d (a0,d2.l*8),fp0
	fdsub.x	fp1,fp0
	tst.l	d1
	beq	.yes
	fneg.x	fp0
.yes:	moveq	#1,d0
	rts
.no:	moveq	#0,d0
	rts

	cnop	0,4
KD_TWO:		dc.l	$40000000,$00000000
KD_MONE:	dc.l	$bff00000,$00000000
KD_1P5:		dc.l	$3ff80000,$00000000
KD_PI:		dc.l	$400921fb,$54442d18
KD_PILO:	dc.l	$3ca1a626,$33145c07
KD_ATHI:	dc.l	$3fddac67,$0561bb4f,$3fe921fb,$54442d18,$3fef730b,$d281f69b,$3ff921fb,$54442d18
KD_ATLO:	dc.l	$3c7a2b7f,$222f65e2,$3c81a626,$33145c07,$3c700788,$7af0cbbd,$3c91a626,$33145c07
KD_AT0:		dc.l	$3fd55555,$5555550d
KD_AT1A:	dc.l	$3fc99999,$9998ebc4
KD_AT2:		dc.l	$3fc24924,$920083ff
KD_AT3A:	dc.l	$3fbc71c6,$fe231671
KD_AT4:		dc.l	$3fb745cd,$c54c206e
KD_AT5A:	dc.l	$3fb3b0f2,$af749a6d
KD_AT6:		dc.l	$3fb10d66,$a0d03d51
KD_AT7A:	dc.l	$3fadde2d,$52defd9a
KD_AT8:		dc.l	$3fa97b4b,$24760deb
KD_AT9:		dc.l	$bfa2b444,$2c6a6c2f
KD_AT10:	dc.l	$3f90ad3a,$e322da11

; int ta68k(float x, float *out): *out = (float)tan(x), musl's as fpu64_math.c (m64_tan_, __tan); 0: |x| beyond the
; medium reduction or Inf / NaN (the C's).  frame as sc68k's: -16 x, -32 y[0], -24 y[1]
	section	code,code
	xdef	_ta68k
	xdef	ta68k
_ta68k:
ta68k:
	link	a6,#-32
	fmovem.x fp2-fp6,-(sp)
	movem.l	d2-d5,-(sp)
	fmove.s	8(a6),fp0
	fmove.d	fp0,-16(a6)
	move.l	-16(a6),d3
	move.l	d3,d1
	bclr	#31,d1
	lea	-32(a6),a0
	cmp.l	#$3fe921fb,d1
	bhi.s	.red
	cmp.l	#$3e400000,d1
	blo.s	.done				; |x| < 2^-27: x
	move.l	-16(a6),(a0)			; __tan(x, 0, 0)
	move.l	-12(a6),4(a0)
	clr.l	8(a0)
	clr.l	12(a0)
	moveq	#0,d4
	bsr	ktan
	bra.s	.done
.red:	cmp.l	#$7ff00000,d1
	bhs.s	.slow
	bsr	rp68k
	cmp.l	#$80000000,d0
	beq.s	.slow
	moveq	#1,d4
	and.l	d0,d4				; odd
	lea	-32(a6),a0
	bsr	ktan
.done:	move.l	12(a6),a0
	fsmove.x fp0,fp0
	fmove.s	fp0,(a0)
	moveq	#1,d0
	bra.s	.x
.slow:	moveq	#0,d0
.x:	movem.l	(sp)+,d2-d5
	fmovem.x (sp)+,fp2-fp6
	unlk	a6
	rts

; __tan(x at (a0), y at 8(a0), d4 odd) -> fp0; (a0) is changed
ktan:
	fdmove.d 8(a0),fp4			; y
	move.l	(a0),d1
	move.l	d1,d2
	bclr	#31,d2
	moveq	#0,d3				; sign (of a big x)
	cmp.l	#$3fe59427,d2			; |x| >= 0.6744: the other way
	bls.s	.p
	tst.l	d1
	bpl.s	.b1
	moveq	#1,d3
	fdneg.d	(a0),fp0
	fmove.d	fp0,(a0)
	fdneg.x	fp4,fp4
.b1:	fmove.d	KD_PIO4(pc),fp0
	fdsub.d	(a0),fp0
	fmove.d	KD_PIO4LO(pc),fp1
	fdsub.x	fp4,fp1
	fdadd.x	fp0,fp1
	fmove.d	fp1,(a0)
	fmove.d	KD_ZERO(pc),fp4
.p:	fdmove.d (a0),fp3
	fdmul.x	fp3,fp3				; z
	fdmove.x fp3,fp5
	fdmul.x	fp3,fp5				; w
	fdmove.d (a0),fp1
	fdmul.x	fp3,fp1				; s
	fdmove.x fp5,fp0
	fdmul.d	KD_T12(pc),fp0
	fdadd.d	KD_T10(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	KD_T8(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	KD_T6(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	KD_T4(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	KD_T2(pc),fp0
	fdmul.x	fp3,fp0				; v
	fdmove.x fp5,fp2
	fdmul.d	KD_T11(pc),fp2
	fdadd.d	KD_T9(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	KD_T7(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	KD_T5(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	KD_T3(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	KD_T1(pc),fp2			; r
	fdadd.x	fp2,fp0
	fdmul.x	fp1,fp0				; s (r + v)
	fdmove.x fp0,fp2
	fdadd.x	fp4,fp2
	fdmul.x	fp3,fp2
	fdadd.x	fp4,fp2				; y + z (s (r + v) + y)
	fdmul.d	KD_T0(pc),fp1
	fdmove.x fp1,fp0
	fdadd.x	fp2,fp0				; r
	fdmove.d (a0),fp1
	fdadd.x	fp0,fp1
	fmove.d	fp1,-(sp)			; w (double)
	fdmove.d (sp)+,fp1
	cmp.l	#$3fe59427,d2
	bhi.s	.big
	tst.l	d4
	bne.s	.odd
	fmove.x	fp1,fp0				; w
	rts
.big:	moveq	#1,d0				; s = 1 - 2 odd
	sub.l	d4,d0
	sub.l	d4,d0
	fdmove.l d0,fp2
	fdmove.x fp1,fp4
	fdmul.x	fp1,fp4				; w w
	fdadd.x	fp2,fp1				; w + s
	fddiv.x	fp1,fp4
	fdsub.x	fp4,fp0				; r - w w / (w + s)
	fdadd.d	(a0),fp0
	fdadd.x	fp0,fp0
	fdsub.x	fp0,fp2				; v
	fmove.x	fp2,fp0
	tst.l	d3
	beq.s	.r
	fneg.x	fp0
.r:	rts
.odd:	fmove.d	fp1,-(sp)			; -1 / (x + r), worked out accurately
	clr.l	4(sp)
	fdmove.d (sp)+,fp4			; w0: w, its low word 0
	fmove.d	KD_MONE(pc),fp2
	fddiv.x	fp1,fp2				; a
	fmove.d	fp2,-(sp)
	fdmove.d (sp),fp1			; (a, as a double)
	clr.l	4(sp)
	fdmove.d (sp)+,fp2			; a0
	fmove.x	fp4,fp5
	fdsub.d	(a0),fp4			; w0 - x
	fdsub.x	fp4,fp0				; v = r - (w0 - x)
	fdmul.x	fp2,fp0				; a0 v
	fmove.x	fp2,fp4
	fdmul.x	fp5,fp4				; a0 w0
	fdadd.d	KD_ONE(pc),fp4
	fdadd.x	fp4,fp0
	fdmul.x	fp1,fp0
	fdadd.x	fp2,fp0				; a0 + a (1 + a0 w0 + a0 v)
	rts

	cnop	0,4
KD_ZERO:	dc.l	$00000000,$00000000
KD_PIO4LO:	dc.l	$3c81a626,$33145c07
KD_T0:		dc.l	$3fd55555,$55555563
KD_T1:		dc.l	$3fc11111,$1110fe7a
KD_T2:		dc.l	$3faba1ba,$1bb341fe
KD_T3:		dc.l	$3f9664f4,$8406d637
KD_T4:		dc.l	$3f8226e3,$e96e8493
KD_T5:		dc.l	$3f6d6d22,$c9560328
KD_T6:		dc.l	$3f57dbc8,$fee08315
KD_T7:		dc.l	$3f4344d8,$f2f26501
KD_T8:		dc.l	$3f3026f7,$1a8d1068
KD_T9:		dc.l	$3f147e88,$a03792a6
KD_T10:		dc.l	$3f12b80f,$32f0a7e9
KD_T11:		dc.l	$bef375cb,$db605373
KD_T12:		dc.l	$3efb2a70,$74bf7ad4


; ---------------------------------------------------------------- all of fpu64_math.c (musl's double maths):
; gcc's code of it put into vasm's syntax (tools/mit2mot/mit2mot.py) -- the same instructions in the
; same order, so the same bits -- with its tables; floor / trunc as fintrz (exact).  The hand-written quick ways
; above (sc68k, at68k, ta68k) go first; this is their rare cases' and the rest's.
; int px68k(float b, float e, float *out): (float)pow(b, e)     int ex68k(float x, float *out): (float)exp(x)
	section	code,code
	xdef	_px68k
	xdef	px68k
_px68k:
px68k:
	fmove.s	8(sp),fp0
	fmove.d	fp0,-(sp)
	fmove.s	4+8(sp),fp0
	fmove.d	fp0,-(sp)
	bsr	m64_pow
	lea	16(sp),sp
	move.l	12(sp),a0
	fsmove.x fp0,fp0
	fmove.s	fp0,(a0)
	moveq	#1,d0
	rts
	xdef	_ex68k
	xdef	ex68k
_ex68k:
ex68k:
	fdmove.s 4(sp),fp0
	fdmul.d	KX_LOG2E(pc),fp0
	fmove.d	fp0,-(sp)
	bsr	mx_exp2_
	addq.l	#8,sp
	move.l	8(sp),a0
	fsmove.x fp0,fp0
	fmove.s	fp0,(a0)
	moveq	#1,d0
	rts
mx_trunc:
	fdmove.d 4(sp),fp0
	fintrz.x fp0,fp0
	rts
mx_floor:
	fdmove.d 4(sp),fp0
	fintrz.x fp0,fp1
	fcmp.x	fp0,fp1
	fble	.ok
	fdsub.d	KD_ONE(pc),fp1
.ok:	fmove.x	fp1,fp0
	rts
	cnop	0,4
KX_LOG2E:	dc.l	$3ff71547,$652b82fe
mx_scalbn:
	fdmove.d	4(sp),fp0
	move.l	12(sp),d0
	cmp.l	#1023,d0
	ble	mxf_L2
	fdmul.d	mxf_K0(pc),fp0
	cmp.l	#2046,d0
	ble	mxf_L3
	fdmul.d	mxf_K0(pc),fp0
	add.l	#-2046,d0
	cmp.l	#1023,d0
	bgt	mxf_L10
mxf_L7:
	add.l	#1023,d0
mxf_L3:
	move.l	d0,d1
	smi	d0
	extb.l	d0
	moveq	#20,d0
	lsl.l	d0,d1
	move.l	d1,d0
	clr.l	d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp1
	fdmul.x	fp1,fp0
	rts
mxf_L2:
	cmp.l	#-1022,d0
	bge	mxf_L7
	fdmul.d	mxf_K1(pc),fp0
	move.l	d0,d1
	add.l	#969,d1
	cmp.l	#-1022,d1
	bge	mxf_L11
	fdmul.d	mxf_K1(pc),fp0
	add.l	#1938,d0
	cmp.l	#-1022,d0
	bge	mxf_L7
	move.l	#-1022,d0
	add.l	#1023,d0
	bra	mxf_L3
mxf_L10:
	move.l	#1023,d0
	add.l	#1023,d0
	bra	mxf_L3
mxf_L11:
	add.l	#1992,d0
	move.l	d0,d1
	smi	d0
	extb.l	d0
	moveq	#20,d0
	lsl.l	d0,d1
	move.l	d1,d0
	clr.l	d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp1
	fdmul.x	fp1,fp0
	rts
mx_kcos:
	fmovem.x	fp2/fp3/fp4/fp6,-(sp)
	fdmove.d	52(sp),fp4
	fdmove.x	fp4,fp1
	fdmul.x	fp4,fp1
	fdmove.x	fp1,fp6
	fdmul.x	fp1,fp6
	fdmove.x	fp1,fp3
	fdmul.d	mxf_K2(pc),fp3
	fmove.d	mxf_K3(pc),fp0
	fdsub.x	fp3,fp0
	fdmove.x	fp1,fp2
	fdmul.d	mxf_K4(pc),fp2
	fdadd.d	mxf_K5(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	mxf_K6(pc),fp2
	fdmul.x	fp6,fp6
	fdmul.x	fp6,fp2
	fdmove.x	fp1,fp6
	fdmul.d	mxf_K7(pc),fp6
	fdsub.d	mxf_K8(pc),fp6
	fdmul.x	fp1,fp6
	fdadd.d	mxf_K9(pc),fp6
	fdmul.x	fp1,fp6
	fdadd.x	fp6,fp2
	fdmul.x	fp1,fp2
	fdmul.d	60(sp),fp4
	fdsub.x	fp4,fp2
	fmove.d	mxf_K3(pc),fp4
	fdsub.x	fp0,fp4
	fdsub.x	fp3,fp4
	fdadd.x	fp4,fp2
	fdadd.x	fp2,fp0
	fmovem.x	(sp)+,fp2/fp3/fp4/fp6
	rts
mx_ktan:
	fmovem.x	fp2/fp3/fp4/fp5,-(sp)
	movem.l	d2/d3/d4,-(sp)
	fdmove.d	72(sp),fp4
	move.l	64(sp),d1
	move.l	d1,d2
	bclr	#31,d2
	cmp.l	#1072010279,d2
	bls	mxf_L15
	move.l	d1,d3
	add.l	d3,d3
	subx.l	d3,d3
	neg.l	d3
	tst.l	d1
	bge	mxf_L16
	fdneg.d	64(sp),fp0
	fmove.d	fp0,64(sp)
	fdneg.x	fp4,fp4
mxf_L16:
	fmove.d	mxf_K10(pc),fp0
	fdsub.d	64(sp),fp0
	fmove.d	mxf_K11(pc),fp1
	fdsub.x	fp4,fp1
	fdadd.x	fp0,fp1
	fmove.d	fp1,64(sp)
	fmove.d	mxf_K12(pc),fp4
mxf_L15:
	fdmove.d	64(sp),fp3
	fdmul.x	fp3,fp3
	fdmove.x	fp3,fp5
	fdmul.x	fp3,fp5
	fdmove.d	64(sp),fp1
	fdmul.x	fp3,fp1
	fdmove.x	fp5,fp0
	fdmul.d	mxf_K13(pc),fp0
	fdadd.d	mxf_K14(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	mxf_K15(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	mxf_K16(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	mxf_K17(pc),fp0
	fdmul.x	fp5,fp0
	fdadd.d	mxf_K18(pc),fp0
	fdmul.x	fp3,fp0
	fdmove.x	fp5,fp2
	fdmul.d	mxf_K19(pc),fp2
	fdadd.d	mxf_K20(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	mxf_K21(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	mxf_K22(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	mxf_K23(pc),fp2
	fdmul.x	fp5,fp2
	fdadd.d	mxf_K24(pc),fp2
	fdadd.x	fp2,fp0
	fdmul.x	fp1,fp0
	fdmove.x	fp0,fp2
	fdadd.x	fp4,fp2
	fdmul.x	fp3,fp2
	fdadd.x	fp4,fp2
	fdmul.d	mxf_K25(pc),fp1
	fdmove.x	fp1,fp0
	fdadd.x	fp2,fp0
	fdmove.d	64(sp),fp1
	fdadd.x	fp0,fp1
	fmove.d	fp1,-(sp)
	move.l	(sp)+,d0
	move.l	(sp)+,d1
	cmp.l	#1072010279,d2
	bhi	mxf_L30
	tst.l	80(sp)
	beq	mxf_L14
	move.l	d0,d2
	clr.l	d3
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp4
	fmove.d	mxf_K26(pc),fp2
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp1
	fddiv.x	fp1,fp2
	fmove.d	fp2,-(sp)
	move.l	(sp)+,d0
	move.l	(sp)+,d1
	move.l	d0,a0
	lea	0.w,a1
	move.l	a1,-(sp)
	move.l	a0,-(sp)
	fdmove.d	(sp)+,fp2
	fdsub.d	64(sp),fp4
	fdsub.x	fp4,fp0
	fdmul.x	fp2,fp0
	move.l	a1,-(sp)
	move.l	a0,-(sp)
	fdmove.d	(sp)+,fp4
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp1
	fdmul.x	fp1,fp4
	fdadd.d	mxf_K3(pc),fp4
	fdadd.x	fp4,fp0
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp1
	fdmul.x	fp1,fp0
	fdadd.x	fp2,fp0
	fmove.d	fp0,-(sp)
	move.l	(sp)+,d0
	move.l	(sp)+,d1
mxf_L14:
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	movem.l	(sp)+,d2/d3/d4
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5
	rts
mxf_L30:
	move.l	80(sp),d4
	add.l	d4,d4
	moveq	#1,d2
	sub.l	d4,d2
	fdmove.l	d2,fp2
	fdmove.x	fp1,fp4
	fdmul.x	fp1,fp4
	fdadd.x	fp2,fp1
	fddiv.x	fp1,fp4
	fdsub.x	fp4,fp0
	fdadd.d	64(sp),fp0
	fdadd.x	fp0,fp0
	fdsub.x	fp0,fp2
	fmove.d	fp2,-(sp)
	move.l	(sp)+,d0
	move.l	(sp)+,d1
	tst.l	d3
	beq	mxf_L14
	bchg	#31,d0
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	movem.l	(sp)+,d2/d3/d4
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5
	rts
mx_atan_:
	subq.l	#8,sp
	fmovem.x	fp2,-(sp)
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	move.l	32(sp),d3
	move.l	32(sp),d1
	add.l	d1,d1
	subx.l	d1,d1
	neg.l	d1
	move.l	d3,d0
	bclr	#31,d0
	cmp.l	#1141899263,d0
	bls	mxf_L32
	fdmove.d	32(sp),fp0
	fcmp.x	fp0,fp0
	fbun	mxf_L33
	tst.l	d1
	beq	mxf_L41
	fmove.d	mxf_K27(pc),fp0
mxf_L31:
	move.l	(sp)+,d2
	move.l	(sp)+,d3
	fmovem.x	(sp)+,fp2
	addq.l	#8,sp
	rts
mxf_L32:
	cmp.l	#1071382527,d0
	bhi	mxf_L35
	cmp.l	#1044381695,d0
	bls	mxf_L48
	moveq	#-1,d0
mxf_L36:
	fdmove.d	32(sp),fp2
	fdmul.x	fp2,fp2
	fdmove.x	fp2,fp1
	fdmul.x	fp2,fp1
	fdmove.x	fp1,fp0
	fdmul.d	mxf_K28(pc),fp0
	fdadd.d	mxf_K29(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	mxf_K30(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	mxf_K31(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	mxf_K32(pc),fp0
	fdmul.x	fp1,fp0
	fdadd.d	mxf_K33(pc),fp0
	fdmul.x	fp2,fp0
	fdmove.x	fp1,fp2
	fdmul.d	mxf_K34(pc),fp2
	fdsub.d	mxf_K35(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	mxf_K36(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	mxf_K37(pc),fp2
	fdmul.x	fp1,fp2
	fdsub.d	mxf_K38(pc),fp2
	fdmul.x	fp1,fp2
	fdadd.x	fp2,fp0
	fdmove.d	32(sp),fp1
	fdmul.x	fp0,fp1
	moveq	#-1,d2
	cmp.l	d0,d2
	beq	mxf_L49
	fdsub.d	(mx_atanlo,d0.l*8),fp1
	fdsub.d	32(sp),fp1
	fdmove.d	(mx_atanhi,d0.l*8),fp0
	fdsub.x	fp1,fp0
	tst.l	d1
	beq	mxf_L31
	fdneg.x	fp0,fp0
	move.l	(sp)+,d2
	move.l	(sp)+,d3
	fmovem.x	(sp)+,fp2
	addq.l	#8,sp
	rts
mxf_L35:
	fdabs.d	32(sp),fp0
	cmp.l	#1072889855,d0
	bhi	mxf_L37
	fdmove.x	fp0,fp2
	cmp.l	#1072037887,d0
	bhi	mxf_L38
	fdadd.x	fp0,fp2
	fdsub.d	mxf_K3(pc),fp2
	fdadd.d	mxf_K39(pc),fp0
	fddiv.x	fp0,fp2
	fmove.d	fp2,32(sp)
	clr.l	d0
	bra	mxf_L36
mxf_L41:
	fmove.d	mxf_K40(pc),fp0
	move.l	(sp)+,d2
	move.l	(sp)+,d3
	fmovem.x	(sp)+,fp2
	addq.l	#8,sp
	rts
mxf_L37:
	cmp.l	#1073971199,d0
	bhi	mxf_L39
	fdmove.x	fp0,fp2
	fdsub.d	mxf_K41(pc),fp2
	fdmul.d	mxf_K41(pc),fp0
	fdadd.d	mxf_K3(pc),fp0
	fddiv.x	fp0,fp2
	fmove.d	fp2,32(sp)
	moveq	#2,d0
	bra	mxf_L36
mxf_L48:
	move.l	d3,d0
	and.l	#2146435072,d0
	bne	mxf_L33
	fsmove.d	32(sp),fp0
	fmove.d	fp0,20(sp)
	move.l	20(sp),d0
	move.l	24(sp),d1
mxf_L33:
	fdmove.d	32(sp),fp0
	move.l	(sp)+,d2
	move.l	(sp)+,d3
	fmovem.x	(sp)+,fp2
	addq.l	#8,sp
	rts
mxf_L49:
	fdmove.d	32(sp),fp0
	fdsub.x	fp1,fp0
	move.l	(sp)+,d2
	move.l	(sp)+,d3
	fmovem.x	(sp)+,fp2
	addq.l	#8,sp
	rts
mxf_L39:
	fmove.d	mxf_K26(pc),fp1
	fddiv.x	fp0,fp1
	fmove.d	fp1,32(sp)
	moveq	#3,d0
	bra	mxf_L36
mxf_L38:
	fdsub.d	mxf_K3(pc),fp2
	fdadd.d	mxf_K3(pc),fp0
	fddiv.x	fp0,fp2
	fmove.d	fp2,32(sp)
	moveq	#1,d0
	bra	mxf_L36
mx_exp2_:
	lea	(-32,sp),sp
	fmovem.x	fp2/fp4,-(sp)
	movem.l	d2/d3/d4/d5/d6/d7,-(sp)
	move.l	84(sp),d0
	move.l	88(sp),d1
	move.l	d0,d2
	move.l	d1,d3
	moveq	#20,d3
	lsr.l	d3,d2
	and.l	#2047,d2
	move.l	d2,a0
	lea	(-969,a0),a0
	moveq	#62,d3
	cmp.l	a0,d3
	bcs	mxf_L69
mxf_L51:
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	fdadd.d	mxf_K42(pc),fp0
	fmove.d	fp0,-(sp)
	move.l	(sp)+,d6
	move.l	(sp)+,d7
	fdsub.d	mxf_K42(pc),fp0
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp2
	fdsub.x	fp0,fp2
	clr.l	d4
	clr.l	d5
	moveq	#127,d5
	and.l	d7,d5
	add.l	d5,d5
	addx.l	d4,d4
	lea	mx_exp_data,a0
	move.l	d6,d0
	move.l	d7,d1
	moveq	#13,d0
	lsl.l	d0,d1
	move.l	d1,d0
	clr.l	d1
	move.l	120(a0,d5.l*8),d6
	add.l	124(a0,d5.l*8),d1
	addx.l	d6,d0
	fdmove.x	fp2,fp1
	fdmul.x	fp2,fp1
	fdmove.x	fp2,fp0
	fdmul.d	mxf_K43(pc),fp0
	fdadd.d	112(a0,d5.l*8),fp0
	fdmove.x	fp2,fp4
	fdmul.d	mxf_K44(pc),fp4
	fdadd.d	mxf_K45(pc),fp4
	fdmul.x	fp1,fp4
	fdadd.x	fp4,fp0
	fdmul.d	mxf_K46(pc),fp2
	fdadd.d	mxf_K47(pc),fp2
	fdmul.x	fp1,fp1
	fdmul.x	fp1,fp2
	fdadd.x	fp2,fp0
	tst.l	d2
	beq	mxf_L70
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp2
	fdmul.x	fp2,fp0
	fdadd.x	fp2,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mxf_L69:
	tst.l	a0
	blt	mxf_L55
	cmp.l	#1032,d2
	bls	mxf_L54
	move.l	#-1048576,d6
	clr.l	d7
	sub.l	d1,d7
	subx.l	d0,d6
	beq	mxf_L62
	cmp.l	#2047,d2
	beq	mxf_L55
	tst.l	d0
	bge	mxf_L71
	move.l	#-1064252417,d6
	moveq	#-1,d7
	sub.l	d1,d7
	subx.l	d0,d6
	bcc	mxf_L54
	move.l	#268435456,56(sp)
	clr.l	60(sp)
	fdmove.d	56(sp),fp0
	fdmul.d	mxf_K48(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mxf_L70:
	clr.l	d4
	clr.l	d5
	move.l	d7,d5
	and.l	#-2147483648,d5
	move.l	d4,d7
	or.l	d5,d7
	beq	mxf_L72
	move.l	#1071644672,d3
	add.l	#0,d1
	addx.l	d3,d0
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp2
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp1
	fdmul.x	fp0,fp1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	fdadd.x	fp1,fp0
	fcmp.d	mxf_K3(pc),fp0
	fblt	mxf_L59
	fdmul.d	mxf_K49(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mxf_L54:
	move.l	d0,d4
	move.l	d1,d5
	add.l	d5,d5
	addx.l	d4,d4
	move.l	#-2129002496,d6
	clr.l	d7
	sub.l	d5,d7
	subx.l	d4,d6
	bcc	mxf_L51
	clr.l	d2
	bra	mxf_L51
mxf_L59:
	fdsub.x	fp0,fp2
	fdadd.x	fp1,fp2
	fdmove.x	fp0,fp4
	fdadd.d	mxf_K3(pc),fp4
	fmove.d	mxf_K3(pc),fp1
	fdsub.x	fp4,fp1
	fdadd.x	fp1,fp0
	fdadd.x	fp2,fp0
	fdadd.x	fp4,fp0
	fdsub.d	mxf_K3(pc),fp0
	ftst.x	fp0
	fbeq	mxf_L63
	fdmul.d	mxf_K49(pc),fp0
	move.l	#1048576,64(sp)
	clr.l	68(sp)
	fdmove.d	64(sp),fp2
	fdmul.d	mxf_K49(pc),fp2
	fmove.d	fp2,72(sp)
	move.l	72(sp),d0
	move.l	76(sp),d1
mxf_L73:
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mxf_L55:
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	fdadd.d	mxf_K3(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mxf_L72:
	move.l	#-1048576,d2
	add.l	#0,d1
	addx.l	d2,d0
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp2
	fdmul.x	fp2,fp0
	fdadd.x	fp2,fp0
	fdadd.x	fp0,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mxf_L63:
	fmove.d	mxf_K12(pc),fp0
	move.l	#1048576,64(sp)
	clr.l	68(sp)
	fdmove.d	64(sp),fp2
	fdmul.d	mxf_K49(pc),fp2
	fmove.d	fp2,72(sp)
	move.l	72(sp),d0
	move.l	76(sp),d1
	bra	mxf_L73
mxf_L71:
	move.l	#1879048192,48(sp)
	clr.l	52(sp)
	fdmove.d	48(sp),fp0
	fdmul.d	mxf_K50(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mxf_L62:
	fmove.d	mxf_K12(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7
	fmovem.x	(sp)+,fp2/fp4
	lea	(32,sp),sp
	rts
mx_log2_:
	lea	(-16,sp),sp
	fmovem.x	fp2/fp3/fp4/fp5/fp6/fp7,-(sp)
	movem.l	d2/d3/d4/d5/d6/d7/a2/a3,-(sp)
	move.l	124(sp),a2
	move.l	128(sp),a3
	move.l	a2,d4
	move.l	a3,d5
	move.l	a2,d7
	clr.w	d7
	swap	d7
	move.l	#-1072604335,d2
	clr.l	d3
	add.l	d5,d3
	addx.l	d4,d2
	move.l	#135337,d0
	moveq	#-1,d1
	sub.l	d3,d1
	subx.l	d2,d0
	bcc	mxf_L85
	move.w	#-16,a0
	add.l	d7,a0
	cmp.w	#32735,a0
	bhi	mxf_L86
	move.l	#-1072037888,d2
	clr.l	d3
	add.l	d5,d3
	addx.l	d4,d2
	move.l	d2,d0
	move.l	d3,d1
	moveq	#14,d1
	lsr.l	d1,d0
	move.l	d0,d1
	moveq	#63,d6
	and.l	d6,d1
	move.l	d2,d6
	and.l	#-1048576,d6
	clr.l	d7
	sub.l	d7,d5
	subx.l	d6,d4
	lea	mx_log2_data,a0
	moveq	#73,d0
	add.l	d1,d0
	lsl.l	#4,d0
	move.l	d5,-(sp)
	move.l	d4,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.d	(a0,d0.l),fp0
	move.l	d1,d0
	lsl.l	#4,d0
	add.l	d0,a0
	fdsub.d	1176(a0),fp0
	move.l	d0,d1
	fdmul.d	(mx_log2_data+144,d1.l),fp0
	fmove.d	fp0,104(sp)
	move.l	104(sp),d0
	clr.l	d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp7
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp4
	fdmul.d	mxf_K51(pc),fp4
	moveq	#20,d3
	asr.l	d3,d2
	move.l	d2,d3
	smi	d2
	ext.w	d2
	fdmove.d	152(a0),fp5
	fdadd.l	d3,fp5
	fdmove.x	fp4,fp3
	fdadd.x	fp5,fp3
	fdmove.x	fp0,fp2
	fdmul.x	fp0,fp2
	fdmul.d	mxf_K52(pc),fp0
	fdsub.d	mxf_K53(pc),fp0
	fdmul.x	fp2,fp0
	fdmove.d	104(sp),fp6
	fdmul.d	mxf_K54(pc),fp6
	fdsub.d	mxf_K55(pc),fp6
	fdadd.x	fp6,fp0
	fdmove.d	104(sp),fp1
	fdmul.d	mxf_K56(pc),fp1
	fdsub.d	mxf_K57(pc),fp1
	fdmove.x	fp2,fp6
	fdmul.x	fp2,fp6
	fdmul.x	fp6,fp1
	fdadd.x	fp1,fp0
	fdmul.x	fp2,fp0
	fdmove.d	104(sp),fp2
	fdsub.x	fp7,fp2
	fdmul.d	mxf_K51(pc),fp2
	fdmove.d	104(sp),fp1
	fdmul.d	mxf_K58(pc),fp1
	fdadd.x	fp1,fp2
	fdsub.x	fp3,fp5
	fdadd.x	fp4,fp5
	fdadd.x	fp5,fp2
	fdadd.x	fp2,fp0
	fdadd.x	fp3,fp0
mxf_L74:
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5/fp6/fp7
	lea	(16,sp),sp
	rts
mxf_L86:
	move.l	a2,d2
	move.l	a3,d3
	add.l	d3,d3
	addx.l	d2,d2
	move.l	d2,d0
	or.l	d3,d0
	beq	mxf_L87
	move.l	#2146435072,d0
	clr.l	d1
	sub.l	d5,d1
	subx.l	d4,d0
	beq	mxf_L82
	move.l	d7,d2
	and.l	#32768,d2
	move.l	a3,-(sp)
	move.l	a2,-(sp)
	fdmove.d	(sp)+,fp0
	tst.l	d2
	bne	mxf_L79
	move.l	d7,d2
	and.l	#32752,d2
	cmp.l	#32752,d2
	beq	mxf_L79
	fdmul.d	mxf_K59(pc),fp0
	fmove.d	fp0,-(sp)
	move.l	(sp)+,d4
	move.l	(sp)+,d5
	move.l	#-54525952,d0
	add.l	#0,d5
	addx.l	d0,d4
	move.l	#-1072037888,d2
	clr.l	d3
	add.l	d5,d3
	addx.l	d4,d2
	move.l	d2,d0
	move.l	d3,d1
	moveq	#14,d1
	lsr.l	d1,d0
	move.l	d0,d1
	moveq	#63,d6
	and.l	d6,d1
	move.l	d2,d6
	and.l	#-1048576,d6
	clr.l	d7
	sub.l	d7,d5
	subx.l	d6,d4
	lea	mx_log2_data,a0
	moveq	#73,d0
	add.l	d1,d0
	lsl.l	#4,d0
	move.l	d5,-(sp)
	move.l	d4,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.d	(a0,d0.l),fp0
	move.l	d1,d0
	lsl.l	#4,d0
	add.l	d0,a0
	fdsub.d	1176(a0),fp0
	move.l	d0,d1
	fdmul.d	(mx_log2_data+144,d1.l),fp0
	fmove.d	fp0,104(sp)
	move.l	104(sp),d0
	clr.l	d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp7
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp4
	fdmul.d	mxf_K51(pc),fp4
	moveq	#20,d3
	asr.l	d3,d2
	move.l	d2,d3
	smi	d2
	ext.w	d2
	fdmove.d	152(a0),fp5
	fdadd.l	d3,fp5
	fdmove.x	fp4,fp3
	fdadd.x	fp5,fp3
	fdmove.x	fp0,fp2
	fdmul.x	fp0,fp2
	fdmul.d	mxf_K52(pc),fp0
	fdsub.d	mxf_K53(pc),fp0
	fdmul.x	fp2,fp0
	fdmove.d	104(sp),fp6
	fdmul.d	mxf_K54(pc),fp6
	fdsub.d	mxf_K55(pc),fp6
	fdadd.x	fp6,fp0
	fdmove.d	104(sp),fp1
	fdmul.d	mxf_K56(pc),fp1
	fdsub.d	mxf_K57(pc),fp1
	fdmove.x	fp2,fp6
	fdmul.x	fp2,fp6
	fdmul.x	fp6,fp1
	fdadd.x	fp1,fp0
	fdmul.x	fp2,fp0
	fdmove.d	104(sp),fp2
	fdsub.x	fp7,fp2
	fdmul.d	mxf_K51(pc),fp2
	fdmove.d	104(sp),fp1
	fdmul.d	mxf_K58(pc),fp1
	fdadd.x	fp1,fp2
	fdsub.x	fp3,fp5
	fdadd.x	fp4,fp5
	fdadd.x	fp5,fp2
	fdadd.x	fp2,fp0
	fdadd.x	fp3,fp0
	bra	mxf_L74
mxf_L85:
	move.l	#1072693248,d0
	clr.l	d1
	sub.l	d5,d1
	subx.l	d4,d0
	beq	mxf_L81
	move.l	a3,-(sp)
	move.l	a2,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.d	mxf_K3(pc),fp0
	fmove.d	fp0,104(sp)
	move.l	104(sp),d0
	clr.l	d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp4
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	fdmul.d	mxf_K51(pc),fp0
	fdmove.d	104(sp),fp2
	fdsub.x	fp4,fp2
	fdmul.d	mxf_K51(pc),fp2
	fdmove.d	104(sp),fp1
	fdmul.d	mxf_K58(pc),fp1
	fdadd.x	fp1,fp2
	fdmove.d	104(sp),fp6
	fdmul.x	fp6,fp6
	fdmove.x	fp6,fp4
	fdmul.x	fp6,fp4
	fdmove.d	104(sp),fp1
	fdmul.d	mxf_K60(pc),fp1
	fdsub.d	mxf_K61(pc),fp1
	fdmove.x	fp1,fp5
	fdmul.x	fp6,fp5
	fdmove.x	fp0,fp1
	fdadd.x	fp5,fp1
	fdmove.x	fp0,fp3
	fdsub.x	fp1,fp3
	fdadd.x	fp5,fp3
	fdadd.x	fp2,fp3
	fdmove.d	104(sp),fp0
	fdmul.d	mxf_K62(pc),fp0
	fdsub.d	mxf_K63(pc),fp0
	fdmul.x	fp6,fp0
	fdmove.d	104(sp),fp2
	fdmul.d	mxf_K64(pc),fp2
	fdsub.d	mxf_K65(pc),fp2
	fdadd.x	fp2,fp0
	fdmul.x	fp4,fp0
	fdmove.d	104(sp),fp2
	fdmul.d	mxf_K66(pc),fp2
	fdsub.d	mxf_K67(pc),fp2
	fdmove.x	fp2,fp5
	fdmul.x	fp6,fp5
	fdmove.d	104(sp),fp2
	fdmul.d	mxf_K68(pc),fp2
	fdsub.d	mxf_K69(pc),fp2
	fdadd.x	fp5,fp2
	fdadd.x	fp2,fp0
	fdmul.x	fp4,fp0
	fdadd.x	fp3,fp0
	fdadd.x	fp1,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5/fp6/fp7
	lea	(16,sp),sp
	rts
mxf_L82:
	move.l	a3,-(sp)
	move.l	a2,-(sp)
	fdmove.d	(sp)+,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5/fp6/fp7
	lea	(16,sp),sp
	rts
mxf_L87:
	move.l	#-1074790400,112(sp)
	clr.l	116(sp)
	fdmove.d	112(sp),fp0
	fddiv.d	mxf_K12(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5/fp6/fp7
	lea	(16,sp),sp
	rts
mxf_L79:
	move.l	a3,-(sp)
	move.l	a2,-(sp)
	fdmove.d	(sp)+,fp1
	fdsub.x	fp1,fp0
	fddiv.x	fp0,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5/fp6/fp7
	lea	(16,sp),sp
	rts
mxf_L81:
	fmove.d	mxf_K12(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	fmovem.x	(sp)+,fp2/fp3/fp4/fp5/fp6/fp7
	lea	(16,sp),sp
	rts
mx_rpl:
	lea	(-580,sp),sp
	fmovem.x	fp2,-(sp)
	movem.l	d2/d3/d4/d5/d6/d7/a2/a3/a4/a5/a6,-(sp)
	move.l	640(sp),a3
	move.l	652(sp),d1
	subq.l	#1,d1
	move.l	648(sp),d0
	subq.l	#3,d0
	moveq	#24,d3
	divs.l	d3,d0
	move.l	d0,d5
	addq.l	#1,d5
	move.l	d5,56(sp)
	moveq	#-24,d6
	muls.l	d5,d6
	add.l	648(sp),d6
	sub.l	d1,d0
	lea	(156,sp),a1
	move.l	d0,d2
	lsl.l	#2,d2
	move.l	d2,a0
	add.l	#mx_ipio2,a0
	move.l	652(sp),d2
	addq.l	#4,d2
	move.l	d2,d3
	add.l	d0,d3
mxf_L92:
	tst.l	d0
	blt	mxf_L185
mxf_L89:
	fdmove.l	(a0),fp0
	fmove.d	fp0,(a1)
	addq.l	#1,d0
	cmp.l	d0,d3
	beq	mxf_L91
	addq.l	#8,a1
	addq.l	#4,a0
	tst.l	d0
	bge	mxf_L89
mxf_L185:
	clr.l	(a1)+
	clr.l	(a1)+
	addq.l	#1,d0
	addq.l	#4,a0
	bra	mxf_L92
mxf_L91:
	lea	(476,sp),a4
	move.l	d1,d0
	move.l	d1,d3
	lsl.l	#3,d3
	moveq	#99,d1
	not.b	d1
	add.l	sp,d1
	add.l	d3,d1
	lea	8(a3,d3.l),a2
mxf_L94:
	move.l	d1,a1
	move.l	a3,a0
	fmove.d	mxf_K12(pc),fp0
mxf_L93:
	fdmove.d	(a0)+,fp1
	fdmul.d	(a1),fp1
	fdadd.x	fp1,fp0
	subq.l	#8,a1
	cmp.l	a2,a0
	bne	mxf_L93
	fmove.d	fp0,(a4)+
	addq.l	#8,d1
	addq.l	#1,d0
	cmp.l	d2,d0
	bne	mxf_L94
	moveq	#4,d3
	moveq	#24,d4
	sub.l	d6,d4
	moveq	#23,d0
	sub.l	d6,d0
	move.l	d0,72(sp)
	lea	(92,sp),a0
	move.l	a0,64(sp)
mxf_L95:
	fdmove.d	476(sp,d3.l*8),fp0
	move.l	d3,d2
	move.l	d3,d0
	lsl.l	#3,d0
	move.l	d0,a5
	lea	(476,sp),a1
	add.l	d0,a1
	lea	(76,sp),a0
	move.l	d3,d0
mxf_L96:
	fdmove.x	fp0,fp2
	fdmul.d	mxf_K70(pc),fp2
	fintrz.x	fp2,fp2
	fmove.l	fp2,d1
	fmove.d	mxf_K71(pc),fp1
	fdmul.l	d1,fp1
	fdsub.x	fp1,fp0
	fintrz.x	fp0,fp0
	fmove.l	fp0,(a0)+
	subq.l	#1,d0
	fdmove.d	-(a1),fp0
	fdadd.l	d1,fp0
	tst.l	d0
	bne	mxf_L96
	move.l	d6,-(sp)
	fmove.d	fp0,-(sp)
	bsr	mx_scalbn
	lea	(12,sp),sp
	fdmove.x	fp0,fp2
	fdmul.d	mxf_K72(pc),fp0
	fmove.d	fp0,-(sp)
	bsr	mx_floor
	addq.l	#8,sp
	fdmul.d	mxf_K73(pc),fp0
	fdsub.x	fp0,fp2
	fintrz.x	fp2,fp0
	fmove.l	fp0,d7
	fdsub.l	d7,fp2
	tst.l	d6
	ble	mxf_L97
	move.l	d3,a0
	subq.l	#1,a0
	move.l	76(sp,a0.l*4),d0
	move.l	d0,d1
	asr.l	d4,d1
	add.l	d1,d7
	lsl.l	d4,d1
	sub.l	d1,d0
	move.l	d0,76(sp,a0.l*4)
	move.l	72(sp),d1
	asr.l	d1,d0
	tst.l	d0
	bgt	mxf_L186
mxf_L100:
	ftst.x	fp2
	fbne	mxf_L114
mxf_L190:
	moveq	#4,d1
	cmp.l	d3,d1
	beq	mxf_L115
	move.l	d3,d1
	lsl.l	#2,d1
	lea	(76,sp),a0
	add.l	d1,a0
	clr.l	d1
mxf_L116:
	or.l	-(a0),d1
	cmp.l	64(sp),a0
	bne	mxf_L116
	tst.l	d1
	bne	mxf_L117
mxf_L115:
	tst.l	88(sp)
	bne	mxf_L187
	tst.l	84(sp)
	bne	mxf_L145
	tst.l	80(sp)
	bne	mxf_L146
	moveq	#4,d1
	move.l	d3,d0
	addq.l	#1,d0
	add.l	d1,d3
mxf_L119:
	move.l	56(sp),d1
	add.l	d2,d1
	lsl.l	#2,d1
	move.l	d1,a4
	add.l	#mx_ipio2,a4
	add.l	652(sp),d2
	lsl.l	#3,d2
	lea	(156,sp),a6
	add.l	d2,a6
	lea	484(sp,a5.l),a5
mxf_L122:
	fdmove.l	(a4)+,fp0
	fmove.d	fp0,(a6)
	move.l	a6,a1
	addq.l	#8,a6
	move.l	a3,a0
	fmove.d	mxf_K12(pc),fp0
mxf_L121:
	fdmove.d	(a0)+,fp1
	fdmul.d	(a1),fp1
	fdadd.x	fp1,fp0
	subq.l	#8,a1
	cmp.l	a0,a2
	bne	mxf_L121
	fmove.d	fp0,(a5)+
	addq.l	#1,d0
	cmp.l	d0,d3
	blt	mxf_L95
	fdmove.l	(a4)+,fp0
	fmove.d	fp0,(a6)
	move.l	a6,a1
	addq.l	#8,a6
	move.l	a3,a0
	fmove.d	mxf_K12(pc),fp0
	bra	mxf_L121
mxf_L186:
	addq.l	#1,d7
	move.l	d3,d1
	lsl.l	#2,d1
	lea	(76,sp),a1
	add.l	d1,a1
	lea	(76,sp),a0
mxf_L178:
	move.l	(a0)+,d1
	beq	mxf_L103
	move.l	#16777216,d5
	sub.l	d1,d5
	move.l	d5,-4(a0)
	cmp.l	a1,a0
	beq	mxf_L104
mxf_L188:
	move.l	(a0),d1
	move.l	#16777215,d5
	sub.l	d1,d5
	move.l	d5,(a0)+
	cmp.l	a1,a0
	bne	mxf_L188
mxf_L104:
	tst.l	d6
	ble	mxf_L189
	moveq	#1,d1
	moveq	#1,d5
	cmp.l	d6,d5
	beq	mxf_L111
mxf_L191:
	moveq	#2,d5
	cmp.l	d6,d5
	bne	mxf_L110
	and.l	#4194303,72(sp,d3.l*4)
mxf_L110:
	moveq	#2,d5
	cmp.l	d0,d5
	bne	mxf_L100
mxf_L192:
	fmove.d	mxf_K3(pc),fp0
	fdsub.x	fp2,fp0
	fdmove.x	fp0,fp2
	tst.l	d1
	beq	mxf_L100
	move.l	#1023,d1
	add.l	d6,d1
	smi	d0
	extb.l	d0
	moveq	#20,d0
	lsl.l	d0,d1
	move.l	d1,d0
	clr.l	d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp1
	fdsub.x	fp1,fp2
	moveq	#2,d0
mxf_L194:
	ftst.x	fp2
	fbeq	mxf_L190
mxf_L114:
	move.l	d6,d1
	neg.l	d1
	move.l	d1,-(sp)
	fmove.d	fp2,-(sp)
	move.l	d0,72(sp)
	bsr	mx_scalbn
	lea	(12,sp),sp
	move.l	60(sp),d0
	fcmp.d	mxf_K71(pc),fp0
	fbnge	mxf_L176
	fdmove.x	fp0,fp2
	fdmul.d	mxf_K70(pc),fp2
	fintrz.x	fp2,fp2
	fmove.l	fp2,d1
	fmove.d	mxf_K71(pc),fp1
	fdmul.l	d1,fp1
	fdsub.x	fp1,fp0
	fintrz.x	fp0,fp0
	fmove.l	fp0,76(sp,d3.l*4)
	addq.l	#1,d3
	move.l	d1,76(sp,d3.l*4)
	move.l	#1047,d5
	add.l	d6,d5
	smi	d4
	extb.l	d4
	move.l	d4,d1
	move.l	d5,d2
	moveq	#20,d1
	lsl.l	d1,d2
	move.l	d2,d1
	clr.l	d2
	move.l	d1,64(sp)
	move.l	d2,68(sp)
mxf_L128:
	move.l	d3,d4
	addq.l	#1,d4
	move.l	d4,d1
	lsl.l	#2,d1
	lea	(76,sp),a1
	add.l	d1,a1
	lsl.l	#3,d4
	lea	(476,sp),a0
	add.l	d4,a0
	move.l	d3,d1
mxf_L131:
	fdmove.d	64(sp),fp2
	fdmul.l	-(a1),fp2
	fmove.d	fp2,-(a0)
	fdmove.d	64(sp),fp0
	fdmul.d	mxf_K70(pc),fp0
	fmove.d	fp0,64(sp)
	dbra	d1,mxf_L131
	clr.w	d1
	subq.l	#1,d1
	bcc	mxf_L131
	move.l	sp,d5
	add.l	#316,d5
	lea	468(sp,d4.l),a2
	move.l	d5,a3
	clr.l	d2
	lea	mx_PIo2,a1
	move.l	a2,a0
	clr.l	d1
	fmove.d	mxf_K12(pc),fp0
mxf_L134:
	fdmove.d	(a1)+,fp1
	fdmul.d	(a0)+,fp1
	fdadd.x	fp1,fp0
	addq.l	#1,d1
	moveq	#5,d6
	cmp.l	d1,d6
	beq	mxf_L133
	cmp.l	d1,d2
	bge	mxf_L134
mxf_L133:
	fmove.d	fp0,(a3)+
	move.l	d2,d1
	addq.l	#1,d1
	subq.l	#8,a2
	cmp.l	d3,d2
	beq	mxf_L135
	move.l	d1,d2
	lea	mx_PIo2,a1
	move.l	a2,a0
	clr.l	d1
	fmove.d	mxf_K12(pc),fp0
	bra	mxf_L134
mxf_L117:
	subq.l	#1,d3
	move.w	#-24,a1
	add.l	d6,a1
	tst.l	76(sp,d3.l*4)
	bne	mxf_L123
	move.l	d2,d1
	add.l	#1073741822,d1
	lsl.l	#2,d1
	lea	(76,sp),a0
	add.l	d1,a0
mxf_L124:
	subq.l	#1,d3
	move.l	a1,d1
	lea	(-24,a1),a1
	subq.l	#4,a0
	tst.l	4(a0)
	beq	mxf_L124
	cmp.w	#-1022,a1
	bge	mxf_L147
	move.l	d1,a1
	lea	(945,a1),a1
	fmove.d	mxf_K1(pc),fp0
mxf_L129:
	tst.l	d3
	blt	mxf_L148
	move.l	#1023,d5
	add.l	a1,d5
	smi	d4
	extb.l	d4
	moveq	#20,d4
	lsl.l	d4,d5
	move.l	d5,d4
	clr.l	d5
	move.l	d5,-(sp)
	move.l	d4,-(sp)
	fdmove.d	(sp)+,fp1
	fdmul.x	fp0,fp1
	fmove.d	fp1,64(sp)
	move.l	d3,d4
	addq.l	#1,d4
	move.l	d4,d1
	lsl.l	#2,d1
	lea	(76,sp),a1
	add.l	d1,a1
	lsl.l	#3,d4
	lea	(476,sp),a0
	add.l	d4,a0
	move.l	d3,d1
	bra	mxf_L131
mxf_L103:
	cmp.l	a1,a0
	bne	mxf_L178
	tst.l	d6
	ble	mxf_L110
	moveq	#1,d5
	cmp.l	d6,d5
	bne	mxf_L191
mxf_L111:
	and.l	#8388607,72(sp,d3.l*4)
	moveq	#2,d5
	cmp.l	d0,d5
	bne	mxf_L100
	bra	mxf_L192
mxf_L97:
	tst.l	d6
	bne	mxf_L99
	move.l	72(sp,d3.l*4),d0
	moveq	#23,d5
	asr.l	d5,d0
	tst.l	d0
	ble	mxf_L100
	bra	mxf_L186
mxf_L99:
	fcmp.d	mxf_K2(pc),fp2
	fbge	mxf_L193
	clr.l	d0
	bra	mxf_L100
mxf_L187:
	addq.l	#1,d3
	move.l	d3,d0
	move.l	56(sp),d1
	add.l	d2,d1
	lsl.l	#2,d1
	move.l	d1,a4
	add.l	#mx_ipio2,a4
	add.l	652(sp),d2
	lsl.l	#3,d2
	lea	(156,sp),a6
	add.l	d2,a6
	lea	484(sp,a5.l),a5
	bra	mxf_L122
mxf_L145:
	moveq	#2,d1
	move.l	d3,d0
	addq.l	#1,d0
	add.l	d1,d3
	bra	mxf_L119
mxf_L146:
	moveq	#3,d1
	move.l	d3,d0
	addq.l	#1,d0
	add.l	d1,d3
	bra	mxf_L119
mxf_L193:
	addq.l	#1,d7
	moveq	#2,d0
	move.l	d3,d1
	lsl.l	#2,d1
	lea	(76,sp),a1
	add.l	d1,a1
	lea	(76,sp),a0
	bra	mxf_L178
mxf_L189:
	moveq	#2,d1
	cmp.l	d0,d1
	bne	mxf_L100
	fmove.d	mxf_K3(pc),fp0
	fdsub.x	fp2,fp0
	fdmove.x	fp0,fp2
	move.l	#1023,d1
	add.l	d6,d1
	smi	d0
	extb.l	d0
	moveq	#20,d0
	lsl.l	d0,d1
	move.l	d1,d0
	clr.l	d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp1
	fdsub.x	fp1,fp2
	moveq	#2,d0
	bra	mxf_L194
mxf_L176:
	fintrz.x	fp0,fp0
	fmove.l	fp0,76(sp,d3.l*4)
	move.l	#1023,d5
	add.l	d6,d5
	smi	d4
	extb.l	d4
	move.l	d4,d1
	move.l	d5,d2
	moveq	#20,d1
	lsl.l	d1,d2
	move.l	d2,d1
	clr.l	d2
	move.l	d1,64(sp)
	move.l	d2,68(sp)
	bra	mxf_L128
mxf_L135:
	move.l	d5,a0
	add.l	d4,a0
	fmove.d	mxf_K12(pc),fp0
mxf_L136:
	fdadd.d	-(a0),fp0
	cmp.l	d5,a0
	bne	mxf_L136
mxf_L130:
	fdmove.d	316(sp),fp1
	fdsub.x	fp0,fp1
	tst.l	d0
	beq	mxf_L137
	fdneg.x	fp0,fp2
	move.l	644(sp),a0
	fmove.d	fp2,(a0)
	tst.l	d3
	ble	mxf_L138
	lea	(324,sp),a0
	moveq	#1,d1
mxf_L139:
	fdadd.d	(a0)+,fp1
	addq.l	#1,d1
	cmp.l	d1,d3
	bge	mxf_L139
	tst.l	d0
	beq	mxf_L140
mxf_L138:
	fdneg.x	fp1,fp1
mxf_L140:
	move.l	644(sp),a0
	fmove.d	fp1,8(a0)
	moveq	#7,d0
	and.l	d7,d0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3/a4/a5/a6
	fmovem.x	(sp)+,fp2
	lea	(580,sp),sp
	rts
mxf_L137:
	move.l	644(sp),a0
	fmove.d	fp0,(a0)
	tst.l	d3
	ble	mxf_L140
	lea	(324,sp),a0
	moveq	#1,d1
	bra	mxf_L139
mxf_L123:
	cmp.w	#-1022,a1
	bge	mxf_L142
	move.l	#1968,d5
	add.l	d6,d5
	smi	d4
	extb.l	d4
	moveq	#20,d4
	lsl.l	d4,d5
	move.l	d5,d4
	clr.l	d5
	move.l	d5,-(sp)
	move.l	d4,-(sp)
	fdmove.d	(sp)+,fp0
	fdmul.d	mxf_K1(pc),fp0
	fmove.d	fp0,64(sp)
	move.l	d3,d4
	addq.l	#1,d4
	move.l	d4,d1
	lsl.l	#2,d1
	lea	(76,sp),a1
	add.l	d1,a1
	lsl.l	#3,d4
	lea	(476,sp),a0
	add.l	d4,a0
	move.l	d3,d1
	bra	mxf_L131
mxf_L148:
	fmove.d	mxf_K12(pc),fp0
	bra	mxf_L130
mxf_L147:
	fmove.d	mxf_K3(pc),fp0
	bra	mxf_L129
mxf_L142:
	move.l	#999,d5
	add.l	d6,d5
	smi	d4
	extb.l	d4
	move.l	d4,d1
	move.l	d5,d2
	moveq	#20,d1
	lsl.l	d1,d2
	move.l	d2,d1
	clr.l	d2
	move.l	d1,64(sp)
	move.l	d2,68(sp)
	bra	mxf_L128
mx_rem_pio2:
	link.w	a6,#-40
	fmovem.x	fp2/fp3/fp4,-(sp)
	movem.l	d2/d3/d4/d5/d6/d7/a2,-(sp)
	move.l	8(a6),d2
	move.l	12(a6),d3
	move.l	16(a6),a2
	move.l	d2,d7
	move.l	d2,d0
	move.l	d3,d1
	add.l	d0,d0
	clr.l	d0
	clr.l	d1
	addx.l	d1,d1
	move.l	d1,d6
	move.l	d2,d5
	move.l	d5,d1
	bclr	#31,d1
	cmp.l	#1074752122,d1
	bhi	mxf_L196
	move.l	d5,d0
	and.l	#1048575,d0
	cmp.l	#598523,d0
	beq	mxf_L197
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	cmp.l	#1073928572,d1
	bhi	mxf_L198
	tst.l	d6
	bne	mxf_L199
	fdsub.d	mxf_K74(pc),fp0
	fdmove.x	fp0,fp1
	fdsub.d	mxf_K75(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdsub.d	mxf_K75(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#1,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L196:
	cmp.l	#1075594811,d1
	bhi	mxf_L202
	cmp.l	#1075183036,d1
	bhi	mxf_L203
	cmp.l	#1074977148,d1
	beq	mxf_L197
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	tst.l	d6
	bne	mxf_L204
	fdsub.d	mxf_K76(pc),fp0
	fdmove.x	fp0,fp1
	fdsub.d	mxf_K77(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdsub.d	mxf_K77(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#3,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L202:
	cmp.l	#1094263290,d1
	bls	mxf_L197
	cmp.l	#2146435071,d1
	bhi	mxf_L235
	and.l	#1048575,d7
	move.l	d7,d2
	or.l	#1096810496,d2
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	fintrz.x	fp0,fp2
	fmove.l	fp2,d0
	fdmove.l	d0,fp1
	fmove.d	fp1,-24(a6)
	fdsub.x	fp1,fp0
	fdmul.d	mxf_K71(pc),fp0
	fintrz.x	fp0,fp2
	fmove.l	fp2,d0
	fdmove.l	d0,fp1
	fmove.d	fp1,-16(a6)
	fdsub.x	fp1,fp0
	fdmul.d	mxf_K71(pc),fp0
	fmove.d	fp0,-8(a6)
	ftst.x	fp0
	fbne	mxf_L218
	tst.l	d0
	bne	mxf_L219
	moveq	#1,d0
mxf_L213:
	move.l	d0,-(sp)
	moveq	#20,d0
	lsr.l	d0,d1
	move.l	d1,a0
	pea	-1046(a0)
	pea	-40(a6)
	pea	-24(a6)
	bsr	mx_rpl
	lea	(16,sp),sp
	tst.l	d6
	bne	mxf_L236
	fdmove.d	-40(a6),fp2
	fmove.d	fp2,(a2)
	move.l	-32(a6),d1
	move.l	-28(a6),d2
	move.l	d1,8(a2)
	move.l	d2,12(a2)
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L198:
	tst.l	d6
	bne	mxf_L201
	fdsub.d	mxf_K78(pc),fp0
	fdmove.x	fp0,fp1
	fdsub.d	mxf_K79(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdsub.d	mxf_K79(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#2,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L203:
	cmp.l	#1075388923,d1
	beq	mxf_L197
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	tst.l	d6
	bne	mxf_L205
	fdsub.d	mxf_K80(pc),fp0
	fdmove.x	fp0,fp1
	fdsub.d	mxf_K81(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdsub.d	mxf_K81(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#4,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L197:
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp2
	fdmul.d	mxf_K82(pc),fp2
	fdadd.d	mxf_K83(pc),fp2
	fdsub.d	mxf_K83(pc),fp2
	fintrz.x	fp2,fp0
	fmove.l	fp0,d0
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K74(pc),fp1
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.x	fp1,fp0
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K75(pc),fp1
	fdmove.x	fp0,fp3
	fdsub.x	fp1,fp3
	fmove.d	fp3,-(sp)
	move.l	(sp)+,d4
	move.l	(sp)+,d5
	fcmp.d	mxf_K84(pc),fp3
	fblt	mxf_L237
	move.l	d5,-(sp)
	move.l	d4,-(sp)
	fdmove.d	(sp)+,fp3
	fcmp.d	mxf_K10(pc),fp3
	fbgt	mxf_L238
mxf_L209:
	moveq	#20,d2
	lsr.l	d2,d1
	move.l	d4,d2
	move.l	d5,d3
	moveq	#20,d3
	lsr.l	d3,d2
	and.l	#2047,d2
	move.l	d1,a0
	sub.l	d2,a0
	moveq	#16,d2
	cmp.l	a0,d2
	bge	mxf_L211
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K85(pc),fp1
	fdmove.x	fp0,fp4
	fdsub.x	fp1,fp4
	fdsub.x	fp4,fp0
	fdsub.x	fp1,fp0
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K86(pc),fp1
	fdsub.x	fp0,fp1
	fdmove.x	fp4,fp0
	fdsub.x	fp1,fp0
	fmove.d	fp0,-(sp)
	move.l	(sp)+,d4
	move.l	(sp)+,d5
	move.l	d4,d2
	move.l	d5,d3
	moveq	#20,d3
	lsr.l	d3,d2
	and.l	#2047,d2
	sub.l	d2,d1
	moveq	#49,d2
	cmp.l	d1,d2
	bge	mxf_L217
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K87(pc),fp1
	fdmove.x	fp4,fp0
	fdsub.x	fp1,fp0
	fdsub.x	fp0,fp4
	fdsub.x	fp1,fp4
	fdmul.d	mxf_K88(pc),fp2
	fdmove.x	fp2,fp1
	fdsub.x	fp4,fp1
	fdmove.x	fp0,fp2
	fdsub.x	fp1,fp2
	fmove.d	fp2,-(sp)
	move.l	(sp)+,d4
	move.l	(sp)+,d5
mxf_L211:
	move.l	d4,(a2)
	move.l	d5,4(a2)
	move.l	d5,-(sp)
	move.l	d4,-(sp)
	fdmove.d	(sp)+,fp3
	fdsub.x	fp3,fp0
	fdsub.x	fp1,fp0
	fmove.d	fp0,8(a2)
mxf_L239:
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L235:
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.x	fp0,fp0
	fmove.d	fp0,8(a2)
	fmove.d	fp0,(a2)
	clr.l	d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L217:
	fdmove.x	fp4,fp0
	move.l	d4,(a2)
	move.l	d5,4(a2)
	move.l	d5,-(sp)
	move.l	d4,-(sp)
	fdmove.d	(sp)+,fp3
	fdsub.x	fp3,fp0
	fdsub.x	fp1,fp0
	fmove.d	fp0,8(a2)
	bra	mxf_L239
mxf_L219:
	moveq	#2,d0
	bra	mxf_L213
mxf_L238:
	addq.l	#1,d0
	fdadd.d	mxf_K3(pc),fp2
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K74(pc),fp1
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.x	fp1,fp0
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K75(pc),fp1
	fdmove.x	fp0,fp3
	fdsub.x	fp1,fp3
	fmove.d	fp3,-(sp)
	move.l	(sp)+,d4
	move.l	(sp)+,d5
	bra	mxf_L209
mxf_L236:
	fdneg.d	-40(a6),fp0
	fmove.d	fp0,(a2)
	fdneg.d	-32(a6),fp1
	fmove.d	fp1,8(a2)
	neg.l	d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L218:
	moveq	#3,d0
	bra	mxf_L213
mxf_L237:
	subq.l	#1,d0
	fdsub.d	mxf_K3(pc),fp2
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K74(pc),fp1
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.x	fp1,fp0
	fdmove.x	fp2,fp1
	fdmul.d	mxf_K75(pc),fp1
	fdmove.x	fp0,fp3
	fdsub.x	fp1,fp3
	fmove.d	fp3,-(sp)
	move.l	(sp)+,d4
	move.l	(sp)+,d5
	bra	mxf_L209
mxf_L201:
	fdadd.d	mxf_K78(pc),fp0
	fdmove.x	fp0,fp1
	fdadd.d	mxf_K79(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdadd.d	mxf_K79(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#-2,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L199:
	fdadd.d	mxf_K74(pc),fp0
	fdmove.x	fp0,fp1
	fdadd.d	mxf_K75(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdadd.d	mxf_K75(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#-1,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L205:
	fdadd.d	mxf_K80(pc),fp0
	fdmove.x	fp0,fp1
	fdadd.d	mxf_K81(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdadd.d	mxf_K81(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#-4,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
mxf_L204:
	fdadd.d	mxf_K76(pc),fp0
	fdmove.x	fp0,fp1
	fdadd.d	mxf_K77(pc),fp1
	fmove.d	fp1,(a2)
	fdsub.x	fp1,fp0
	fdadd.d	mxf_K77(pc),fp0
	fmove.d	fp0,8(a2)
	moveq	#-3,d0
	movem.l	-104(a6),d2/d3/d4/d5/d6/d7/a2
	fmovem.x	-76(a6),fp2/fp3/fp4
	unlk	a6
	rts
	xdef	_m64_sin
	xdef	m64_sin
_m64_sin:
m64_sin:
	link.w	a6,#-16
	fmovem.x	fp2/fp3/fp4/fp5/fp6,-(sp)
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	move.l	8(a6),d3
	move.l	d3,d0
	bclr	#31,d0
	cmp.l	#1072243195,d0
	bhi	mxf_L241
	cmp.l	#1045430271,d0
	bhi	mxf_L242
	move.l	d3,d0
	and.l	#2146435072,d0
	fdmove.d	8(a6),fp0
	tst.l	d0
	bne	mxf_L243
	fdmul.d	mxf_K89(pc),fp0
	fmove.d	fp0,-16(a6)
	move.l	-16(a6),d0
	move.l	-12(a6),d1
	fdmove.d	8(a6),fp0
mxf_L240:
	move.l	-84(a6),d2
	move.l	-80(a6),d3
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L241:
	cmp.l	#2146435071,d0
	bls	mxf_L246
	fdmove.d	8(a6),fp0
	fdsub.x	fp0,fp0
	move.l	-84(a6),d2
	move.l	-80(a6),d3
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L242:
	fdmove.d	8(a6),fp0
	fdmul.x	fp0,fp0
	fdmove.x	fp0,fp2
	fdmul.x	fp0,fp2
	fdmul.x	fp0,fp2
	fdmove.x	fp0,fp4
	fdmul.d	mxf_K90(pc),fp4
	fdsub.d	mxf_K91(pc),fp4
	fdmul.x	fp4,fp2
	fdmove.x	fp0,fp4
	fdmul.d	mxf_K92(pc),fp4
	fdsub.d	mxf_K93(pc),fp4
	fdmul.x	fp0,fp4
	fdadd.d	mxf_K94(pc),fp4
	fdadd.x	fp4,fp2
	fdmul.x	fp0,fp2
	fdsub.d	mxf_K95(pc),fp2
	fdmul.d	8(a6),fp0
	fdmul.x	fp2,fp0
	fdadd.d	8(a6),fp0
	move.l	-84(a6),d2
	move.l	-80(a6),d3
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L246:
	pea	-16(a6)
	move.l	12(a6),-(sp)
	move.l	8(a6),-(sp)
	bsr	mx_rem_pio2
	moveq	#3,d1
	and.l	d1,d0
	lea	(12,sp),sp
	moveq	#1,d1
	cmp.l	d0,d1
	beq	mxf_L247
	moveq	#2,d1
	cmp.l	d0,d1
	beq	mxf_L248
	tst.l	d0
	beq	mxf_L252
	move.l	-4(a6),-(sp)
	move.l	-8(a6),-(sp)
	move.l	-12(a6),-(sp)
	move.l	-16(a6),-(sp)
	bsr	mx_kcos
	lea	(16,sp),sp
	fdneg.x	fp0,fp0
	move.l	-84(a6),d2
	move.l	-80(a6),d3
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L243:
	fdadd.d	mxf_K96(pc),fp0
	fmove.d	fp0,-16(a6)
	move.l	-16(a6),d0
	move.l	-12(a6),d1
	fdmove.d	8(a6),fp0
	bra	mxf_L240
mxf_L252:
	fdmove.d	-8(a6),fp3
	fdmove.d	-16(a6),fp0
	fdmove.x	fp0,fp5
	fdmul.x	fp0,fp5
	fdmove.x	fp0,fp1
	fdmul.x	fp5,fp1
	fdmove.x	fp3,fp2
	fdmul.d	mxf_K2(pc),fp2
	fdmove.x	fp5,fp4
	fdmul.x	fp5,fp4
	fdmul.x	fp5,fp4
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K90(pc),fp6
	fdsub.d	mxf_K91(pc),fp6
	fdmul.x	fp6,fp4
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K92(pc),fp6
	fdsub.d	mxf_K93(pc),fp6
	fdmul.x	fp5,fp6
	fdadd.d	mxf_K94(pc),fp6
	fdadd.x	fp6,fp4
	fdmul.x	fp1,fp4
	fdsub.x	fp4,fp2
	fdmul.x	fp5,fp2
	fdsub.x	fp3,fp2
	fdmul.d	mxf_K95(pc),fp1
	fdadd.x	fp1,fp2
	fdsub.x	fp2,fp0
	move.l	-84(a6),d2
	move.l	-80(a6),d3
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L248:
	fdmove.d	-8(a6),fp4
	fdmove.d	-16(a6),fp0
	fdmove.x	fp0,fp5
	fdmul.x	fp0,fp5
	fdmove.x	fp0,fp1
	fdmul.x	fp5,fp1
	fdmove.x	fp4,fp2
	fdmul.d	mxf_K2(pc),fp2
	fdmove.x	fp5,fp3
	fdmul.x	fp5,fp3
	fdmul.x	fp5,fp3
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K90(pc),fp6
	fdsub.d	mxf_K91(pc),fp6
	fdmul.x	fp6,fp3
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K92(pc),fp6
	fdsub.d	mxf_K93(pc),fp6
	fdmul.x	fp5,fp6
	fdadd.d	mxf_K94(pc),fp6
	fdadd.x	fp6,fp3
	fdmul.x	fp1,fp3
	fdsub.x	fp3,fp2
	fdmul.x	fp5,fp2
	fdsub.x	fp4,fp2
	fdmul.d	mxf_K95(pc),fp1
	fdadd.x	fp1,fp2
	fdsub.x	fp2,fp0
	fdneg.x	fp0,fp0
	move.l	-84(a6),d2
	move.l	-80(a6),d3
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L247:
	move.l	-4(a6),-(sp)
	move.l	-8(a6),-(sp)
	move.l	-12(a6),-(sp)
	move.l	-16(a6),-(sp)
	bsr	mx_kcos
	lea	(16,sp),sp
	move.l	-84(a6),d2
	move.l	-80(a6),d3
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
	xdef	_m64_cos
	xdef	m64_cos
_m64_cos:
m64_cos:
	link.w	a6,#-16
	fmovem.x	fp2/fp3/fp4/fp5/fp6,-(sp)
	move.l	8(a6),d1
	move.l	d1,d0
	bclr	#31,d0
	cmp.l	#1072243195,d0
	bhi	mxf_L254
	cmp.l	#1044816029,d0
	bhi	mxf_L255
	fdmove.d	8(a6),fp0
	fdadd.d	mxf_K96(pc),fp0
	fmove.d	fp0,-16(a6)
	move.l	-16(a6),d0
	move.l	-12(a6),d1
	fmove.d	mxf_K3(pc),fp0
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L254:
	cmp.l	#2146435071,d0
	bls	mxf_L257
	fdmove.d	8(a6),fp0
	fdsub.x	fp0,fp0
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L255:
	clr.l	-(sp)
	clr.l	-(sp)
	move.l	12(a6),-(sp)
	move.l	8(a6),-(sp)
	bsr	mx_kcos
	lea	(16,sp),sp
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L257:
	pea	-16(a6)
	move.l	12(a6),-(sp)
	move.l	8(a6),-(sp)
	bsr	mx_rem_pio2
	moveq	#3,d1
	and.l	d1,d0
	lea	(12,sp),sp
	moveq	#1,d1
	cmp.l	d0,d1
	beq	mxf_L258
	moveq	#2,d1
	cmp.l	d0,d1
	beq	mxf_L259
	tst.l	d0
	beq	mxf_L263
	fdmove.d	-8(a6),fp3
	fdmove.d	-16(a6),fp0
	fdmove.x	fp0,fp5
	fdmul.x	fp0,fp5
	fdmove.x	fp0,fp1
	fdmul.x	fp5,fp1
	fdmove.x	fp3,fp2
	fdmul.d	mxf_K2(pc),fp2
	fdmove.x	fp5,fp4
	fdmul.x	fp5,fp4
	fdmul.x	fp5,fp4
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K90(pc),fp6
	fdsub.d	mxf_K91(pc),fp6
	fdmul.x	fp6,fp4
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K92(pc),fp6
	fdsub.d	mxf_K93(pc),fp6
	fdmul.x	fp5,fp6
	fdadd.d	mxf_K94(pc),fp6
	fdadd.x	fp6,fp4
	fdmul.x	fp1,fp4
	fdsub.x	fp4,fp2
	fdmul.x	fp5,fp2
	fdsub.x	fp3,fp2
	fdmul.d	mxf_K95(pc),fp1
	fdadd.x	fp1,fp2
	fdsub.x	fp2,fp0
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L259:
	move.l	-4(a6),-(sp)
	move.l	-8(a6),-(sp)
	move.l	-12(a6),-(sp)
	move.l	-16(a6),-(sp)
	bsr	mx_kcos
	lea	(16,sp),sp
	fdneg.x	fp0,fp0
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L263:
	move.l	-4(a6),-(sp)
	move.l	-8(a6),-(sp)
	move.l	-12(a6),-(sp)
	move.l	-16(a6),-(sp)
	bsr	mx_kcos
	lea	(16,sp),sp
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
mxf_L258:
	fdmove.d	-8(a6),fp3
	fdmove.d	-16(a6),fp0
	fdmove.x	fp0,fp5
	fdmul.x	fp0,fp5
	fdmove.x	fp0,fp1
	fdmul.x	fp5,fp1
	fdmove.x	fp3,fp2
	fdmul.d	mxf_K2(pc),fp2
	fdmove.x	fp5,fp4
	fdmul.x	fp5,fp4
	fdmul.x	fp5,fp4
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K90(pc),fp6
	fdsub.d	mxf_K91(pc),fp6
	fdmul.x	fp6,fp4
	fdmove.x	fp5,fp6
	fdmul.d	mxf_K92(pc),fp6
	fdsub.d	mxf_K93(pc),fp6
	fdmul.x	fp5,fp6
	fdadd.d	mxf_K94(pc),fp6
	fdadd.x	fp6,fp4
	fdmul.x	fp1,fp4
	fdsub.x	fp4,fp2
	fdmul.x	fp5,fp2
	fdsub.x	fp3,fp2
	fdmul.d	mxf_K95(pc),fp1
	fdadd.x	fp1,fp2
	fdsub.x	fp2,fp0
	fdneg.x	fp0,fp0
	fmovem.x	-76(a6),fp2/fp3/fp4/fp5/fp6
	unlk	a6
	rts
	xdef	_m64_tan
	xdef	m64_tan
_m64_tan:
m64_tan:
	link.w	a6,#-16
	movem.l	d2/d4/d5,-(sp)
	move.l	8(a6),d0
	move.l	12(a6),d1
	move.l	d0,d5
	move.l	d5,d2
	bclr	#31,d2
	cmp.l	#1072243195,d2
	bhi	mxf_L265
	cmp.l	#1044381695,d2
	bhi	mxf_L266
	move.l	d5,d2
	and.l	#2146435072,d2
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	tst.l	d2
	bne	mxf_L267
	fdmul.d	mxf_K89(pc),fp0
	fmove.d	fp0,-16(a6)
	move.l	-16(a6),a0
	move.l	-12(a6),a1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
mxf_L264:
	movem.l	-28(a6),d2/d4/d5
	unlk	a6
	rts
mxf_L265:
	cmp.l	#2146435071,d2
	bls	mxf_L270
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	fdsub.x	fp0,fp0
	movem.l	-28(a6),d2/d4/d5
	unlk	a6
	rts
mxf_L266:
	clr.l	-(sp)
	clr.l	-(sp)
	clr.l	-(sp)
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	bsr	mx_ktan
	lea	(20,sp),sp
	movem.l	-28(a6),d2/d4/d5
	unlk	a6
	rts
mxf_L270:
	pea	-16(a6)
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	bsr	mx_rem_pio2
	moveq	#1,d1
	and.l	d0,d1
	move.l	d1,-(sp)
	move.l	-4(a6),-(sp)
	move.l	-8(a6),-(sp)
	move.l	-12(a6),-(sp)
	move.l	-16(a6),-(sp)
	bsr	mx_ktan
	lea	(32,sp),sp
	movem.l	-28(a6),d2/d4/d5
	unlk	a6
	rts
mxf_L267:
	fdadd.d	mxf_K96(pc),fp0
	fmove.d	fp0,-16(a6)
	move.l	-16(a6),a0
	move.l	-12(a6),a1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	bra	mxf_L264
	xdef	_m64_atan
	xdef	m64_atan
_m64_atan:
m64_atan:
	bra	mx_atan_
	xdef	_m64_atan2
	xdef	m64_atan2
_m64_atan2:
m64_atan2:
	movem.l	d2/d3/d4/d5/d6/d7/a2/a3,-(sp)
	move.l	36(sp),d0
	move.l	40(sp),d1
	move.l	44(sp),a0
	move.l	48(sp),a1
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	fdmove.d	(sp)+,fp0
	move.l	a1,-(sp)
	move.l	a0,-(sp)
	fdmove.d	(sp)+,fp1
	fcmp.x	fp1,fp0
	fbun	mxf_L311
	move.l	a0,d2
	add.l	#-1072693248,d2
	move.l	a1,d3
	or.l	d3,d2
	beq	mxf_L312
	move.l	a0,d2
	moveq	#30,d3
	lsr.l	d3,d2
	moveq	#2,d3
	and.l	d3,d2
	move.l	d0,d6
	add.l	d6,d6
	subx.l	d6,d6
	neg.l	d6
	or.l	d6,d2
	move.l	d0,d6
	bclr	#31,d6
	move.l	d1,d3
	or.l	d6,d3
	bne	mxf_L279
	moveq	#2,d3
	cmp.l	d2,d3
	beq	mxf_L290
	subq.l	#3,d2
	beq	mxf_L291
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L279:
	move.l	a0,d4
	bclr	#31,d4
	move.l	a1,d3
	or.l	d4,d3
	beq	mxf_L283
	cmp.l	#2146435072,d4
	beq	mxf_L313
	move.l	d4,d3
	add.l	#67108864,d3
	cmp.l	d6,d3
	bcs	mxf_L283
	cmp.l	#2146435072,d6
	beq	mxf_L283
	moveq	#2,d3
	and.l	d2,d3
	beq	mxf_L285
	add.l	#67108864,d6
	cmp.l	d4,d6
	bcc	mxf_L286
	moveq	#2,d0
	fmove.d	mxf_K12(pc),fp0
	cmp.l	d2,d0
	beq	mxf_L287
mxf_L288:
	fdsub.d	mxf_K97(pc),fp0
	fdsub.d	mxf_K98(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L291:
	fmove.d	mxf_K99(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L313:
	subq.l	#1,d2
	cmp.l	#2146435072,d6
	beq	mxf_L314
	moveq	#2,d3
	cmp.l	d2,d3
	bcc	mxf_L315
	fmove.d	mxf_K12(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L283:
	btst	#0,d2
	beq	mxf_L295
	fmove.d	mxf_K27(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L312:
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	bra	mx_atan_
mxf_L290:
	fmove.d	mxf_K98(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L311:
	fdadd.x	fp1,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L295:
	fmove.d	mxf_K40(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L286:
	fddiv.x	fp1,fp0
	fdabs.x	fp0,fp0
	fmove.d	fp0,-(sp)
	bsr	mx_atan_
	addq.l	#8,sp
	subq.l	#2,d2
	bne	mxf_L288
mxf_L287:
	fdmove.x	fp0,fp1
	fdsub.d	mxf_K97(pc),fp1
	fmove.d	mxf_K98(pc),fp0
	fdsub.x	fp1,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L315:
	fdmove.d	(mx_sw93,d2.l*8),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L285:
	fddiv.x	fp1,fp0
	fdabs.x	fp0,fp0
	fmove.d	fp0,-(sp)
	bsr	mx_atan_
	addq.l	#8,sp
	moveq	#1,d0
	cmp.l	d2,d0
	bne	mxf_L316
	fdneg.x	fp0,fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L314:
	moveq	#2,d0
	cmp.l	d2,d0
	bcs	mxf_L293
	fdmove.d	(mx_sw92,d2.l*8),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L316:
	moveq	#2,d3
	cmp.l	d2,d3
	beq	mxf_L287
	tst.l	d2
	bne	mxf_L288
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
mxf_L293:
	fmove.d	mxf_K10(pc),fp0
	movem.l	(sp)+,d2/d3/d4/d5/d6/d7/a2/a3
	rts
	xdef	_m64_exp2
	xdef	m64_exp2
_m64_exp2:
m64_exp2:
	bra	mx_exp2_
	xdef	_m64_log2
	xdef	m64_log2
_m64_log2:
m64_log2:
	bra	mx_log2_
	xdef	_m64_pow
	xdef	m64_pow
_m64_pow:
m64_pow:
	fmovem.x	fp2/fp4,-(sp)
	fdmove.d	28(sp),fp2
	fdmove.d	36(sp),fp4
	ftst.x	fp2
	fbgt	mxf_L335
	ftst.x	fp4
	fbeq	mxf_L329
	fcmp.x	fp2,fp2
	fbne	mxf_L325
	fcmp.x	fp4,fp4
	fbne	mxf_L325
	ftst.x	fp2
	fbeq	mxf_L336
	fmove.d	fp4,-(sp)
	bsr	mx_floor
	addq.l	#8,sp
	fcmp.x	fp0,fp4
	fbeq	mxf_L328
	fdsub.x	fp2,fp2
	fddiv.x	fp2,fp2
mxf_L321:
	fdmove.x	fp2,fp0
	fmovem.x	(sp)+,fp2/fp4
	rts
mxf_L329:
	fmove.d	mxf_K3(pc),fp2
	fdmove.x	fp2,fp0
	fmovem.x	(sp)+,fp2/fp4
	rts
mxf_L325:
	fdadd.x	fp4,fp2
	fdmove.x	fp2,fp0
	fmovem.x	(sp)+,fp2/fp4
	rts
mxf_L335:
	fmove.d	fp2,-(sp)
	bsr	mx_log2_
	addq.l	#8,sp
	fdmul.x	fp0,fp4
	fmove.d	fp4,28(sp)
	fmovem.x	(sp)+,fp2/fp4
	bra	mx_exp2_
mxf_L336:
	ftst.x	fp4
	fbngt	mxf_L337
	fmove.d	mxf_K12(pc),fp2
	fdmove.x	fp2,fp0
	fmovem.x	(sp)+,fp2/fp4
	rts
mxf_L328:
	fdneg.x	fp2,fp2
	fmove.d	fp2,-(sp)
	bsr	mx_log2_
	fdmul.x	fp4,fp0
	fmove.d	fp0,-(sp)
	bsr	mx_exp2_
	fdmove.x	fp0,fp2
	fdmove.x	fp4,fp0
	fdmul.d	mxf_K2(pc),fp0
	fmove.d	fp0,-(sp)
	bsr	mx_trunc
	fdadd.x	fp0,fp0
	fdsub.x	fp0,fp4
	lea	(24,sp),sp
	ftst.x	fp4
	fbeq	mxf_L321
	fdneg.x	fp2,fp2
	fdmove.x	fp2,fp0
	fmovem.x	(sp)+,fp2/fp4
	rts
mxf_L337:
	fmove.d	mxf_K3(pc),fp2
	fddiv.d	mxf_K12(pc),fp2
	fdmove.x	fp2,fp0
	fmovem.x	(sp)+,fp2/fp4
	rts
	xdef	_m64_tables_crc
	xdef	m64_tables_crc
_m64_tables_crc:
m64_tables_crc:
	lea	mx_ipio2,a0
	lea	mx_ipio2+2760,a1
	move.l	#-2128831035,d0
mxf_L339:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L339
	lea	mx_PIo2,a0
	lea	mx_PIo2+64,a1
mxf_L340:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L340
	lea	mx_T,a0
	lea	mx_T+104,a1
mxf_L341:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L341
	lea	mx_atanhi,a0
	lea	mx_atanhi+32,a1
mxf_L342:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L342
	lea	mx_atanlo,a0
	lea	mx_atanlo+32,a1
mxf_L343:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L343
	lea	mx_aT,a0
	lea	mx_aT+88,a1
mxf_L344:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L344
	lea	mx_exp_data,a0
	lea	mx_exp_data+2160,a1
mxf_L345:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L345
	lea	mx_log2_data,a0
	lea	mx_log2_data+2192,a1
mxf_L346:
	clr.l	d1
	move.b	(a0)+,d1
	eor.l	d1,d0
	muls.l	#16777619,d0
	cmp.l	a1,a0
	bne	mxf_L346
	rts
	cnop	0,4
mxf_K0:	dc.l	$7fe00000,$00000000
mxf_K1:	dc.l	$03600000,$00000000
mxf_K2:	dc.l	$3fe00000,$00000000
mxf_K3:	dc.l	$3ff00000,$00000000
mxf_K4:	dc.l	$bda8fae9,$be8838d4
mxf_K5:	dc.l	$3e21ee9e,$bdb4b1c4
mxf_K6:	dc.l	$3e927e4f,$809c52ad
mxf_K7:	dc.l	$3efa01a0,$19cb1590
mxf_K8:	dc.l	$3f56c16c,$16c15177
mxf_K9:	dc.l	$3fa55555,$5555554c
mxf_K10:	dc.l	$3fe921fb,$54442d18
mxf_K11:	dc.l	$3c81a626,$33145c07
mxf_K12:	dc.l	$00000000,$00000000
mxf_K13:	dc.l	$3efb2a70,$74bf7ad4
mxf_K14:	dc.l	$3f12b80f,$32f0a7e9
mxf_K15:	dc.l	$3f3026f7,$1a8d1068
mxf_K16:	dc.l	$3f57dbc8,$fee08315
mxf_K17:	dc.l	$3f8226e3,$e96e8493
mxf_K18:	dc.l	$3faba1ba,$1bb341fe
mxf_K19:	dc.l	$bef375cb,$db605373
mxf_K20:	dc.l	$3f147e88,$a03792a6
mxf_K21:	dc.l	$3f4344d8,$f2f26501
mxf_K22:	dc.l	$3f6d6d22,$c9560328
mxf_K23:	dc.l	$3f9664f4,$8406d637
mxf_K24:	dc.l	$3fc11111,$1110fe7a
mxf_K25:	dc.l	$3fd55555,$55555563
mxf_K26:	dc.l	$bff00000,$00000000
mxf_K27:	dc.l	$bff921fb,$54442d18
mxf_K28:	dc.l	$3f90ad3a,$e322da11
mxf_K29:	dc.l	$3fa97b4b,$24760deb
mxf_K30:	dc.l	$3fb10d66,$a0d03d51
mxf_K31:	dc.l	$3fb745cd,$c54c206e
mxf_K32:	dc.l	$3fc24924,$920083ff
mxf_K33:	dc.l	$3fd55555,$5555550d
mxf_K34:	dc.l	$bfa2b444,$2c6a6c2f
mxf_K35:	dc.l	$3fadde2d,$52defd9a
mxf_K36:	dc.l	$3fb3b0f2,$af749a6d
mxf_K37:	dc.l	$3fbc71c6,$fe231671
mxf_K38:	dc.l	$3fc99999,$9998ebc4
mxf_K39:	dc.l	$40000000,$00000000
mxf_K40:	dc.l	$3ff921fb,$54442d18
mxf_K41:	dc.l	$3ff80000,$00000000
mxf_K42:	dc.l	$42c80000,$00000000
mxf_K43:	dc.l	$3fe62e42,$fefa39ef
mxf_K44:	dc.l	$3fac6b08,$d70cf4b5
mxf_K45:	dc.l	$3fcebfbd,$ff82c424
mxf_K46:	dc.l	$3f55d7e0,$9b4e3a84
mxf_K47:	dc.l	$3f83b2ab,$d24650cc
mxf_K48:	dc.l	$10000000,$00000000
mxf_K49:	dc.l	$00100000,$00000000
mxf_K50:	dc.l	$70000000,$00000000
mxf_K51:	dc.l	$3ff71547,$65200000
mxf_K52:	dc.l	$3fd2776c,$50034c48
mxf_K53:	dc.l	$3fd71547,$64702ffb
mxf_K54:	dc.l	$3fdec709,$dc3a04be
mxf_K55:	dc.l	$3fe71547,$652b8339
mxf_K56:	dc.l	$3fca6225,$e117f92e
mxf_K57:	dc.l	$3fcec7b3,$28ea92bc
mxf_K58:	dc.l	$3de705fc,$2eefa200
mxf_K59:	dc.l	$43300000,$00000000
mxf_K60:	dc.l	$3fdec709,$dc3a03f7
mxf_K61:	dc.l	$3fe71547,$652b82fe
mxf_K62:	dc.l	$3fc0b32f,$285aee66
mxf_K63:	dc.l	$3fc289e4,$a72c383c
mxf_K64:	dc.l	$3fc484d1,$54f01b4a
mxf_K65:	dc.l	$3fc7153f,$bc64a79b
mxf_K66:	dc.l	$3fca6176,$1ec4e736
mxf_K67:	dc.l	$3fcec709,$dd768fe5
mxf_K68:	dc.l	$3fd2776c,$50f05be4
mxf_K69:	dc.l	$3fd71547,$652b7c3f
mxf_K70:	dc.l	$3e700000,$00000000
mxf_K71:	dc.l	$41700000,$00000000
mxf_K72:	dc.l	$3fc00000,$00000000
mxf_K73:	dc.l	$40200000,$00000000
mxf_K74:	dc.l	$3ff921fb,$54400000
mxf_K75:	dc.l	$3dd0b461,$1a626331
mxf_K76:	dc.l	$4012d97c,$7f300000
mxf_K77:	dc.l	$3de90e91,$a79394ca
mxf_K78:	dc.l	$400921fb,$54400000
mxf_K79:	dc.l	$3de0b461,$1a626331
mxf_K80:	dc.l	$401921fb,$54400000
mxf_K81:	dc.l	$3df0b461,$1a626331
mxf_K82:	dc.l	$3fe45f30,$6dc9c883
mxf_K83:	dc.l	$43380000,$00000000
mxf_K84:	dc.l	$bfe921fb,$54442d18
mxf_K85:	dc.l	$3dd0b461,$1a600000
mxf_K86:	dc.l	$3ba3198a,$2e037073
mxf_K87:	dc.l	$3ba3198a,$2e000000
mxf_K88:	dc.l	$397b839a,$252049c1
mxf_K89:	dc.l	$38700000,$00000000
mxf_K90:	dc.l	$3de5d93a,$5acfd57c
mxf_K91:	dc.l	$3e5ae5e6,$8a2b9ceb
mxf_K92:	dc.l	$3ec71de3,$57b1fe7d
mxf_K93:	dc.l	$3f2a01a0,$19c161d5
mxf_K94:	dc.l	$3f811111,$1110f8a6
mxf_K95:	dc.l	$3fc55555,$55555549
mxf_K96:	dc.l	$47700000,$00000000
mxf_K97:	dc.l	$3ca1a626,$33145c07
mxf_K98:	dc.l	$400921fb,$54442d18
mxf_K99:	dc.l	$c00921fb,$54442d18
	section	data,data
	cnop	0,4
mx_sw93:
	dc.l	-2147483648
	dc.l	0
	dc.l	1074340347
	dc.l	1413754136
	dc.l	-1073143301
	dc.l	1413754136
mx_sw92:
	dc.l	-1075240453
	dc.l	1413754136
	dc.l	1073928572
	dc.l	2134057426
	dc.l	-1073555076
	dc.l	2134057426
mx_log2_data:
	dc.l	1073157447
	dc.l	1696595968
	dc.l	1038550524
	dc.l	787456512
	dc.l	-1075374777
	dc.l	1697350457
	dc.l	1071564553
	dc.l	-600177474
	dc.l	-1076423353
	dc.l	1685073915
	dc.l	1070757740
	dc.l	1342393416
	dc.l	-1076967501
	dc.l	686461628
	dc.l	1070228005
	dc.l	-518522578
	dc.l	-1075374777
	dc.l	1697350398
	dc.l	1071564553
	dc.l	-600177673
	dc.l	-1076423353
	dc.l	1697348671
	dc.l	1070757740
	dc.l	1357929444
	dc.l	-1076967671
	dc.l	-579432475
	dc.l	1070227830
	dc.l	516220726
	dc.l	-1077471937
	dc.l	-1134254181
	dc.l	1069843665
	dc.l	1425021770
	dc.l	-1077769756
	dc.l	-1490274244
	dc.l	1069593391
	dc.l	677047910
	dc.l	1073161256
	dc.l	1806806264
	dc.l	-1075771041
	dc.l	-288509952
	dc.l	1073144311
	dc.l	1725090977
	dc.l	-1075805036
	dc.l	-1116286976
	dc.l	1073127741
	dc.l	238081162
	dc.l	-1075838653
	dc.l	-1360463872
	dc.l	1073111532
	dc.l	852520069
	dc.l	-1075904827
	dc.l	906706944
	dc.l	1073095674
	dc.l	-1794008840
	dc.l	-1075970599
	dc.l	448258048
	dc.l	1073080155
	dc.l	-1529937300
	dc.l	-1076035666
	dc.l	214405120
	dc.l	1073064965
	dc.l	1512132536
	dc.l	-1076100040
	dc.l	301834240
	dc.l	1073050093
	dc.l	253128222
	dc.l	-1076163737
	dc.l	842719232
	dc.l	1073035529
	dc.l	1493956661
	dc.l	-1076226769
	dc.l	1512943616
	dc.l	1073021263
	dc.l	-312365603
	dc.l	-1076289153
	dc.l	1526226944
	dc.l	1073007288
	dc.l	-1907852336
	dc.l	-1076350899
	dc.l	-1334734848
	dc.l	1072993593
	dc.l	-1271705618
	dc.l	-1076412023
	dc.l	-106307584
	dc.l	1072980171
	dc.l	-542124695
	dc.l	-1076472533
	dc.l	-1256615936
	dc.l	1072967014
	dc.l	1323612499
	dc.l	-1076532445
	dc.l	-1566896128
	dc.l	1072954113
	dc.l	287168678
	dc.l	-1076591771
	dc.l	257925120
	dc.l	1072941461
	dc.l	-1223927754
	dc.l	-1076650519
	dc.l	938909696
	dc.l	1072929052
	dc.l	1253506378
	dc.l	-1076708703
	dc.l	1401774080
	dc.l	1072916878
	dc.l	216046005
	dc.l	-1076766333
	dc.l	1086996480
	dc.l	1072904932
	dc.l	-2112624718
	dc.l	-1076823419
	dc.l	977330176
	dc.l	1072893209
	dc.l	428195249
	dc.l	-1076879972
	dc.l	854011904
	dc.l	1072881701
	dc.l	-894275113
	dc.l	-1076984451
	dc.l	-1560649728
	dc.l	1072870404
	dc.l	-820785790
	dc.l	-1077095480
	dc.l	1664974848
	dc.l	1072859312
	dc.l	746376016
	dc.l	-1077205501
	dc.l	1276420096
	dc.l	1072848418
	dc.l	1670663653
	dc.l	-1077314532
	dc.l	793763840
	dc.l	1072837718
	dc.l	1032197553
	dc.l	-1077422590
	dc.l	1065353216
	dc.l	1072827206
	dc.l	-482431176
	dc.l	-1077529689
	dc.l	436592640
	dc.l	1072816878
	dc.l	-36854819
	dc.l	-1077635851
	dc.l	-380174336
	dc.l	1072806730
	dc.l	1477130544
	dc.l	-1077741084
	dc.l	618700800
	dc.l	1072796755
	dc.l	-2072043008
	dc.l	-1077845415
	dc.l	1526579200
	dc.l	1072786950
	dc.l	-1059727556
	dc.l	-1077961574
	dc.l	1975353344
	dc.l	1072777311
	dc.l	1203233986
	dc.l	-1078166697
	dc.l	1543094272
	dc.l	1072767832
	dc.l	-1392474671
	dc.l	-1078370106
	dc.l	267681792
	dc.l	1072758512
	dc.l	257106471
	dc.l	-1078571806
	dc.l	1203109888
	dc.l	1072749344
	dc.l	2010135183
	dc.l	-1078771848
	dc.l	-1308540928
	dc.l	1072740326
	dc.l	-698777383
	dc.l	-1078970243
	dc.l	440582144
	dc.l	1072731454
	dc.l	-25476979
	dc.l	-1079349358
	dc.l	146079744
	dc.l	1072722725
	dc.l	-893043837
	dc.l	-1079739755
	dc.l	1333198848
	dc.l	1072714135
	dc.l	-468903076
	dc.l	-1080220760
	dc.l	-989069312
	dc.l	1072705681
	dc.l	-1054830942
	dc.l	-1080989146
	dc.l	695730176
	dc.l	1072697360
	dc.l	632520225
	dc.l	-1082711816
	dc.l	-655884288
	dc.l	1072676990
	dc.l	-104159381
	dc.l	1065811539
	dc.l	-1320157184
	dc.l	1072645221
	dc.l	-738791036
	dc.l	1067523276
	dc.l	-519077888
	dc.l	1072614407
	dc.l	-1618734977
	dc.l	1068256764
	dc.l	-1937014784
	dc.l	1072584506
	dc.l	-1718134040
	dc.l	1068739122
	dc.l	509034496
	dc.l	1072555478
	dc.l	-256033306
	dc.l	1069095072
	dc.l	-796164096
	dc.l	1072527286
	dc.l	-2113980237
	dc.l	1069445865
	dc.l	-637255680
	dc.l	1072499893
	dc.l	1917708611
	dc.l	1069669586
	dc.l	1350524928
	dc.l	1072473266
	dc.l	-603032221
	dc.l	1069840043
	dc.l	64921600
	dc.l	1072447374
	dc.l	-388576431
	dc.l	1070008131
	dc.l	2011308032
	dc.l	1072422187
	dc.l	1325534284
	dc.l	1070173918
	dc.l	-1951842304
	dc.l	1072397676
	dc.l	6297034
	dc.l	1070337464
	dc.l	1792204800
	dc.l	1072373814
	dc.l	1848521615
	dc.l	1070498826
	dc.l	-1345396736
	dc.l	1072350576
	dc.l	640241721
	dc.l	1070627082
	dc.l	-1268285440
	dc.l	1072327937
	dc.l	-1138282019
	dc.l	1070705669
	dc.l	1744945152
	dc.l	1072305875
	dc.l	-1136660085
	dc.l	1070783249
	dc.l	-721494016
	dc.l	1072284369
	dc.l	1231552173
	dc.l	1070859846
	dc.l	1321566208
	dc.l	1072263396
	dc.l	-193160958
	dc.l	1070935486
	dc.l	154857472
	dc.l	1072242939
	dc.l	964869362
	dc.l	1071010192
	dc.l	542167040
	dc.l	1072222977
	dc.l	-2013832719
	dc.l	1071083986
	dc.l	-840241152
	dc.l	1072203493
	dc.l	-340134291
	dc.l	1071156892
	dc.l	-2055368704
	dc.l	1072184471
	dc.l	-1235699308
	dc.l	1071228929
	dc.l	1440833536
	dc.l	1072165893
	dc.l	-3796958
	dc.l	1071300120
	dc.l	1859375104
	dc.l	1072147746
	dc.l	403969482
	dc.l	1071370482
	dc.l	-1365188608
	dc.l	1072130012
	dc.l	-107020404
	dc.l	1071440036
	dc.l	1035943936
	dc.l	1072046080
	dc.l	314116750
	dc.l	1015612587
	dc.l	105166341
	dc.l	1072062464
	dc.l	72823974
	dc.l	1013055387
	dc.l	-362612823
	dc.l	1072078847
	dc.l	-1020923195
	dc.l	1015185103
	dc.l	-885223238
	dc.l	1072095232
	dc.l	951671300
	dc.l	1015611272
	dc.l	1450414886
	dc.l	1072111615
	dc.l	-526805789
	dc.l	1015741760
	dc.l	660570801
	dc.l	1072128000
	dc.l	358157840
	dc.l	-1133314699
	dc.l	-1272741055
	dc.l	1072144384
	dc.l	308632533
	dc.l	1014499558
	dc.l	2082745206
	dc.l	1072160768
	dc.l	844753318
	dc.l	-1134425884
	dc.l	653664951
	dc.l	1072177151
	dc.l	-306924846
	dc.l	-1132199354
	dc.l	514181423
	dc.l	1072193536
	dc.l	771423427
	dc.l	1013839860
	dc.l	-1561159137
	dc.l	1072209919
	dc.l	-141792432
	dc.l	-1131543469
	dc.l	155817469
	dc.l	1072226304
	dc.l	963056998
	dc.l	-1131805453
	dc.l	-1094223035
	dc.l	1072242687
	dc.l	-490793147
	dc.l	-1132987852
	dc.l	1074667580
	dc.l	1072259071
	dc.l	-866345007
	dc.l	-1133052032
	dc.l	94398813
	dc.l	1072275456
	dc.l	1002063719
	dc.l	1014036676
	dc.l	-991134205
	dc.l	1072291839
	dc.l	-407294555
	dc.l	1015971801
	dc.l	1200375298
	dc.l	1072308223
	dc.l	-684786257
	dc.l	-1133900715
	dc.l	1305325182
	dc.l	1072324607
	dc.l	-570097771
	dc.l	1015446953
	dc.l	-1930841493
	dc.l	1072340991
	dc.l	-899773141
	dc.l	-1132297015
	dc.l	-1253305378
	dc.l	1072357375
	dc.l	-575863830
	dc.l	1012404936
	dc.l	-362795460
	dc.l	1072373759
	dc.l	-250790579
	dc.l	-1131480355
	dc.l	-1389922148
	dc.l	1072390143
	dc.l	-836692390
	dc.l	1012124439
	dc.l	432411191
	dc.l	1072406527
	dc.l	-649009548
	dc.l	1014233049
	dc.l	1100271104
	dc.l	1072422912
	dc.l	329033903
	dc.l	1014303428
	dc.l	559782848
	dc.l	1072439296
	dc.l	1531371417
	dc.l	1013706406
	dc.l	1407828425
	dc.l	1072455680
	dc.l	1085929390
	dc.l	-1132722273
	dc.l	659189974
	dc.l	1072472064
	dc.l	1649802634
	dc.l	-1132852416
	dc.l	1994935327
	dc.l	1072488447
	dc.l	-649328291
	dc.l	1015609651
	dc.l	-107301417
	dc.l	1072504831
	dc.l	-109717809
	dc.l	-1135072248
	dc.l	1717559742
	dc.l	1072521215
	dc.l	-1571414893
	dc.l	-1132788696
	dc.l	-1680697869
	dc.l	1072537599
	dc.l	-1658680564
	dc.l	1015480913
	dc.l	873439798
	dc.l	1072553984
	dc.l	1706851862
	dc.l	-1133182690
	dc.l	379901964
	dc.l	1072570368
	dc.l	49694609
	dc.l	1015644207
	dc.l	166683360
	dc.l	1072586752
	dc.l	1473750744
	dc.l	-1132590219
	dc.l	1477244922
	dc.l	1072603136
	dc.l	669892620
	dc.l	-1131641725
	dc.l	155555857
	dc.l	1072619520
	dc.l	1828047740
	dc.l	-1131446233
	dc.l	-1793755404
	dc.l	1072635904
	dc.l	2016116172
	dc.l	-1131445799
	dc.l	1920226191
	dc.l	1072652288
	dc.l	638338314
	dc.l	-1136627456
	dc.l	656932828
	dc.l	1072668671
	dc.l	-393423565
	dc.l	-1135076388
	dc.l	-503469904
	dc.l	1072685055
	dc.l	-720402807
	dc.l	1015544090
	dc.l	-879653266
	dc.l	1072701440
	dc.l	69804903
	dc.l	1016823795
	dc.l	1697793665
	dc.l	1072717823
	dc.l	-471607704
	dc.l	1015478792
	dc.l	-575761029
	dc.l	1072734208
	dc.l	176531287
	dc.l	-1135090978
	dc.l	-2133591151
	dc.l	1072750592
	dc.l	442449868
	dc.l	-1131314637
	dc.l	96858132
	dc.l	1072766975
	dc.l	-122701067
	dc.l	-1131676997
	dc.l	1719712450
	dc.l	1072783359
	dc.l	-447901267
	dc.l	-1130529006
	dc.l	389539823
	dc.l	1072799744
	dc.l	296498913
	dc.l	1016856586
	dc.l	85390847
	dc.l	1072816128
	dc.l	432554568
	dc.l	-1131379973
	dc.l	-455451232
	dc.l	1072832512
	dc.l	268328558
	dc.l	-1131872816
	dc.l	1285356355
	dc.l	1072848896
	dc.l	648009873
	dc.l	1015873066
	dc.l	2039796098
	dc.l	1072865280
	dc.l	698803930
	dc.l	-1133510029
	dc.l	1902021573
	dc.l	1072881663
	dc.l	-534168007
	dc.l	1016822841
	dc.l	-625826055
	dc.l	1072898047
	dc.l	-136515454
	dc.l	1014886707
	dc.l	1859932756
	dc.l	1072914431
	dc.l	-262501536
	dc.l	-1130495146
	dc.l	1288516075
	dc.l	1072930816
	dc.l	772714188
	dc.l	1014362343
	dc.l	1272161399
	dc.l	1072947200
	dc.l	71021110
	dc.l	1016888779
	dc.l	345868339
	dc.l	1072963584
	dc.l	47286271
	dc.l	1014892719
	dc.l	-819118808
	dc.l	1072979968
	dc.l	221805745
	dc.l	1015154743
	dc.l	-2056939098
	dc.l	1072996352
	dc.l	72785801
	dc.l	-1131808164
	dc.l	-1873822510
	dc.l	1073012736
	dc.l	70599667
	dc.l	-1132981979
	dc.l	-317238487
	dc.l	1073029119
	dc.l	-872251633
	dc.l	1016628184
	dc.l	-2072554276
	dc.l	1073045503
	dc.l	-41438353
	dc.l	-1132000793
	dc.l	835725319
	dc.l	1073061887
	dc.l	-232917062
	dc.l	1015543711
	dc.l	1752333058
	dc.l	1073078271
	dc.l	-335793023
	dc.l	-1131315056
	dc.l	774957374
mx_exp_data:
	dc.l	1080497479
	dc.l	1697350398
	dc.l	1127743488
	dc.l	0
	dc.l	-1082773950
	dc.l	-17170432
	dc.l	-1123223654
	dc.l	-1130480838
	dc.l	1071644671
	dc.l	-579
	dc.l	1069897045
	dc.l	1431655484
	dc.l	1067799893
	dc.l	-820565103
	dc.l	1065423121
	dc.l	1738854423
	dc.l	1120403456
	dc.l	0
	dc.l	1072049730
	dc.l	-17155601
	dc.l	1070514109
	dc.l	-8207324
	dc.l	1068264200
	dc.l	-687016779
	dc.l	1065595563
	dc.l	-767143732
	dc.l	1062590432
	dc.l	-1689372028
	dc.l	0
	dc.l	0
	dc.l	1072693248
	dc.l	0
	dc.l	1016806223
	dc.l	445169518
	dc.l	1072690749
	dc.l	-1443155147
	dc.l	-1133420525
	dc.l	-1663509411
	dc.l	1072688282
	dc.l	1048019041
	dc.l	-1131389318
	dc.l	277309137
	dc.l	1072685845
	dc.l	-395411579
	dc.l	1015861842
	dc.l	896005651
	dc.l	1072683440
	dc.l	-753564300
	dc.l	-1131688320
	dc.l	603557626
	dc.l	1072681067
	dc.l	702412510
	dc.l	1012987726
	dc.l	1642514529
	dc.l	1072678725
	dc.l	410360776
	dc.l	1016112100
	dc.l	1530123161
	dc.l	1072676414
	dc.l	-892931197
	dc.l	1016568486
	dc.l	1568897901
	dc.l	1072674136
	dc.l	1828292879
	dc.l	1015985434
	dc.l	-1828851716
	dc.l	1072671890
	dc.l	728909815
	dc.l	1010744893
	dc.l	1882168529
	dc.l	1072669676
	dc.l	852742562
	dc.l	-1133903052
	dc.l	-1987023349
	dc.l	1072667494
	dc.l	-1342254309
	dc.l	-1131063726
	dc.l	707771662
	dc.l	1072665345
	dc.l	-804103343
	dc.l	-1135574801
	dc.l	-1940985259
	dc.l	1072663229
	dc.l	-1066651188
	dc.l	-1131296477
	dc.l	-1177160682
	dc.l	1072661146
	dc.l	-1364644384
	dc.l	1015075811
	dc.l	-379824721
	dc.l	1072659096
	dc.l	-928674223
	dc.l	-1132455147
	dc.l	-358247608
	dc.l	1072657080
	dc.l	1014845819
	dc.l	-1131470864
	dc.l	1440625213
	dc.l	1072655097
	dc.l	948735466
	dc.l	1015777676
	dc.l	1058231231
	dc.l	1072653147
	dc.l	-344994955
	dc.l	-1130964580
	dc.l	1980885798
	dc.l	1072651232
	dc.l	-2080088876
	dc.l	1016786167
	dc.l	1044000608
	dc.l	1072649351
	dc.l	828946858
	dc.l	-1131419774
	dc.l	-880396131
	dc.l	1072647504
	dc.l	586995997
	dc.l	1015705409
	dc.l	1151779725
	dc.l	1072645691
	dc.l	-2006807338
	dc.l	1015052805
	dc.l	-1327233923
	dc.l	1072643913
	dc.l	-1854022506
	dc.l	1016499965
	dc.l	-475486060
	dc.l	1072642170
	dc.l	1853186616
	dc.l	1015504408
	dc.l	-227260291
	dc.l	1072640462
	dc.l	1337108031
	dc.l	1015039787
	dc.l	-1742739470
	dc.l	1072638789
	dc.l	1709341917
	dc.l	-1130973061
	dc.l	1064372318
	dc.l	1072637151
	dc.l	-504011903
	dc.l	1015216097
	dc.l	1829350193
	dc.l	1072635549
	dc.l	-182460703
	dc.l	-1136844389
	dc.l	443531258
	dc.l	1072633983
	dc.l	-790963824
	dc.l	1015756674
	dc.l	1913391796
	dc.l	1072632453
	dc.l	-1495006453
	dc.l	1013847186
	dc.l	-1982936177
	dc.l	1072630959
	dc.l	-1455542442
	dc.l	1015238005
	dc.l	1303423926
	dc.l	1072629502
	dc.l	171030293
	dc.l	1015431681
	dc.l	-492014516
	dc.l	1072628080
	dc.l	-62072783
	dc.l	1016061241
	dc.l	1574172746
	dc.l	1072626696
	dc.l	-1302063361
	dc.l	-1132027008
	dc.l	999185156
	dc.l	1072625349
	dc.l	1603444721
	dc.l	-1131263251
	dc.l	-867479448
	dc.l	1072624039
	dc.l	926591435
	dc.l	-1130821640
	dc.l	458304910
	dc.l	1072622766
	dc.l	1829099622
	dc.l	-1133391384
	dc.l	1049900754
	dc.l	1072621531
	dc.l	887463927
	dc.l	-1130817255
	dc.l	-1278338283
	dc.l	1072620333
	dc.l	-1022121755
	dc.l	1015390024
	dc.l	-1490400147
	dc.l	1072619174
	dc.l	1276261410
	dc.l	-1131212192
	dc.l	2049468810
	dc.l	1072618053
	dc.l	78413852
	dc.l	-1135040625
	dc.l	1209502043
	dc.l	1072616970
	dc.l	569847338
	dc.l	-1132712805
	dc.l	1732876827
	dc.l	1072615925
	dc.l	-649025385
	dc.l	1011049453
	dc.l	1623370769
	dc.l	1072614920
	dc.l	1617004845
	dc.l	1016489481
	dc.l	990274799
	dc.l	1072613953
	dc.l	-316866473
	dc.l	1013894369
	dc.l	-626982023
	dc.l	1072613026
	dc.l	-1245627184
	dc.l	1016332174
	dc.l	1057952304
	dc.l	1072612138
	dc.l	-254290978
	dc.l	1014403278
	dc.l	-1149587536
	dc.l	1072611290
	dc.l	-717870553
	dc.l	1016274365
	dc.l	-346759049
	dc.l	1072610482
	dc.l	-1711416051
	dc.l	-1131441100
	dc.l	7447438
	dc.l	1072609714
	dc.l	1990012071
	dc.l	-1131946292
	dc.l	-594304183
	dc.l	1072608986
	dc.l	-1563466174
	dc.l	-1132929338
	dc.l	-1123076001
	dc.l	1072608299
	dc.l	1453150082
	dc.l	-1132064186
	dc.l	-327459594
	dc.l	1072607652
	dc.l	-899837425
	dc.l	1016280325
	dc.l	419288974
	dc.l	1072607047
	dc.l	917841882
	dc.l	1014732983
	dc.l	797612805
	dc.l	1072606482
	dc.l	-728250371
	dc.l	1016095713
	dc.l	-501459959
	dc.l	1072605959
	dc.l	-582462423
	dc.l	1010091909
	dc.l	1343866602
	dc.l	1072605478
	dc.l	-1973860681
	dc.l	1016345318
	dc.l	728023093
	dc.l	1072605039
	dc.l	363667784
	dc.l	-1131617206
	dc.l	1637447327
	dc.l	1072604641
	dc.l	-1183392759
	dc.l	-1131662395
	dc.l	1005538728
	dc.l	1072604286
	dc.l	-1338354299
	dc.l	-1132178568
	dc.l	-1993610834
	dc.l	1072603974
	dc.l	885834528
	dc.l	-1131163939
	dc.l	2018924632
	dc.l	1072603704
	dc.l	-2108349915
	dc.l	1012338858
	dc.l	-2139219612
	dc.l	1072603477
	dc.l	-733173389
	dc.l	-1131170833
	dc.l	-1084349912
	dc.l	1072603294
	dc.l	1719614413
	dc.l	-1133899091
	dc.l	-2026587774
	dc.l	1072603154
	dc.l	1963711167
	dc.l	-1134336017
	dc.l	-1200772626
	dc.l	1072603058
	dc.l	1013258799
	dc.l	-1132405699
	dc.l	1424001105
	dc.l	1072603005
	dc.l	-112094076
	dc.l	-1132978332
	dc.l	2119843535
	dc.l	1072602997
	dc.l	-387162252
	dc.l	-1132007862
	dc.l	-1064600144
	dc.l	1072603034
	dc.l	1218806132
	dc.l	-1132062414
	dc.l	508946058
	dc.l	1072603115
	dc.l	1447192521
	dc.l	1016110283
	dc.l	1577702611
	dc.l	1072603241
	dc.l	1339972927
	dc.l	-1132776740
	dc.l	-1186093795
	dc.l	1072603412
	dc.l	1944781191
	dc.l	1016392957
	dc.l	1416085611
	dc.l	1072603629
	dc.l	19972402
	dc.l	1013312481
	dc.l	-1412010923
	dc.l	1072603891
	dc.l	919555682
	dc.l	-1131896379
	dc.l	800313154
	dc.l	1072604199
	dc.l	1413356050
	dc.l	-1131189834
	dc.l	-247777484
	dc.l	1072604553
	dc.l	-1723019757
	dc.l	-1132437884
	dc.l	974782238
	dc.l	1072604954
	dc.l	1176749997
	dc.l	-1131097008
	dc.l	-663595154
	dc.l	1072605401
	dc.l	-1690004755
	dc.l	1016114535
	dc.l	1527679488
	dc.l	1072605895
	dc.l	-645241191
	dc.l	1015920431
	dc.l	-1041175884
	dc.l	1072606437
	dc.l	1110089947
	dc.l	-1134184864
	dc.l	-1664751617
	dc.l	1072607026
	dc.l	380978316
	dc.l	1014756995
	dc.l	1509121860
	dc.l	1072607662
	dc.l	-1726646474
	dc.l	-1131214561
	dc.l	-1491190397
	dc.l	1072608347
	dc.l	194117574
	dc.l	-1134712392
	dc.l	-1955848663
	dc.l	1072609079
	dc.l	-1328691739
	dc.l	-1133763591
	dc.l	2089859417
	dc.l	1072609860
	dc.l	-876064241
	dc.l	-1131265213
	dc.l	586480042
	dc.l	1072610690
	dc.l	-1612820912
	dc.l	-1132082580
	dc.l	-681144757
	dc.l	1072611569
	dc.l	1892288442
	dc.l	1014083580
	dc.l	730975783
	dc.l	1072612497
	dc.l	-2103185264
	dc.l	1013830197
	dc.l	-519408709
	dc.l	1072613475
	dc.l	434316067
	dc.l	-1131952892
	dc.l	576856675
	dc.l	1072614502
	dc.l	2069751141
	dc.l	1015749766
	dc.l	-471715371
	dc.l	1072615579
	dc.l	-330683085
	dc.l	-1131299887
	dc.l	-742606059
	dc.l	1072616707
	dc.l	-1304550051
	dc.l	1016122417
	dc.l	-1662111278
	dc.l	1072617886
	dc.l	321958744
	dc.l	1015310724
	dc.l	1853053619
	dc.l	1072619115
	dc.l	1434058175
	dc.l	-1132273715
	dc.l	-1752261196
	dc.l	1072620395
	dc.l	-1076628614
	dc.l	1015814775
	dc.l	-1832176761
	dc.l	1072621727
	dc.l	-1722100819
	dc.l	-1131381873
	dc.l	1255266810
	dc.l	1072623111
	dc.l	697153126
	dc.l	-1135229991
	dc.l	1457303226
	dc.l	1072624546
	dc.l	-1202776581
	dc.l	-1131371506
	dc.l	1034352192
	dc.l	1072626034
	dc.l	-1914349254
	dc.l	-1133979916
	dc.l	950899508
	dc.l	1072627574
	dc.l	-218407353
	dc.l	-1131286814
	dc.l	1800964661
	dc.l	1072629168
	dc.l	815859274
	dc.l	1014300631
	dc.l	174054861
	dc.l	1072630814
	dc.l	-1874083374
	dc.l	-1131299333
	dc.l	-91055956
	dc.l	1072632514
	dc.l	1540824585
	dc.l	1014197934
	dc.l	816778419
	dc.l	1072634267
	dc.l	-578465124
	dc.l	1015997234
	dc.l	1553989012
	dc.l	1072636075
	dc.l	1610600570
	dc.l	1015341199
	dc.l	-787916372
	dc.l	1072637937
	dc.l	777507147
	dc.l	1013173679
	dc.l	944642663
	dc.l	1072639853
	dc.l	-1811486795
	dc.l	1013410604
	dc.l	1821514088
	dc.l	1072641824
	dc.l	-588279703
	dc.l	-1132426728
	dc.l	-2083736110
	dc.l	1072643851
	dc.l	1432208378
	dc.l	-1131434659
	dc.l	1073740399
	dc.l	1072645933
	dc.l	1242007932
	dc.l	-1131410002
	dc.l	947235145
	dc.l	1072648071
	dc.l	135105010
	dc.l	1014276997
	dc.l	-1505949785
	dc.l	1072650264
	dc.l	-587488121
	dc.l	-1132293730
	dc.l	541073935
	dc.l	1072652515
	dc.l	382305176
	dc.l	1015962192
	dc.l	-708734292
	dc.l	1072654822
	dc.l	64696965
	dc.l	1015298649
	dc.l	-1409193141
	dc.l	1072657185
	dc.l	-217992096
	dc.l	-1132276447
	dc.l	129252895
	dc.l	1072659607
	dc.l	863738719
	dc.l	-1131861319
	dc.l	994512329
	dc.l	1072662086
	dc.l	351641897
	dc.l	1014281732
	dc.l	1614448851
	dc.l	1072664622
	dc.l	-410304522
	dc.l	1015268844
	dc.l	1369272945
	dc.l	1072667217
	dc.l	-70824829
	dc.l	-1131415790
	dc.l	-1881959952
	dc.l	1072669871
	dc.l	-1566273318
	dc.l	-1131565416
	dc.l	-500992899
	dc.l	1072672584
	dc.l	764307441
	dc.l	1015989180
	dc.l	1101668360
	dc.l	1072675355
	dc.l	-295609817
	dc.l	1015294868
	dc.l	-1012274382
	dc.l	1072678187
	dc.l	929806999
	dc.l	1015702697
	dc.l	835814894
	dc.l	1072681078
	dc.l	1533953344
	dc.l	-1131530310
	dc.l	-465837075
	dc.l	1072684029
	dc.l	-1382236652
	dc.l	1014466875
	dc.l	1301400989
	dc.l	1072687041
	dc.l	-2120314664
	dc.l	1012073921
	dc.l	1096862857
	dc.l	1072690114
	dc.l	730821105
mx_aT:
	dc.l	1070945621
	dc.l	1431655693
	dc.l	-1077306983
	dc.l	-1718031420
	dc.l	1069697316
	dc.l	-1845459969
	dc.l	-1078169146
	dc.l	-31254927
	dc.l	1068975565
	dc.l	-984866706
	dc.l	-1078742798
	dc.l	-1351312787
	dc.l	1068567910
	dc.l	-1596965551
	dc.l	-1079124435
	dc.l	1390345626
	dc.l	1068071755
	dc.l	611716587
	dc.l	-1079856060
	dc.l	745172015
	dc.l	1066446138
	dc.l	-484255215
mx_atanlo:
	dc.l	1014639487
	dc.l	573531618
	dc.l	1015129638
	dc.l	856972295
	dc.l	1013974920
	dc.l	2062601149
	dc.l	1016178214
	dc.l	856972295
mx_atanhi:
	dc.l	1071492199
	dc.l	90291023
	dc.l	1072243195
	dc.l	1413754136
	dc.l	1072657163
	dc.l	-763234661
	dc.l	1073291771
	dc.l	1413754136
mx_T:
	dc.l	1070945621
	dc.l	1431655779
	dc.l	1069617425
	dc.l	286326394
	dc.l	1068212666
	dc.l	464732670
	dc.l	1066820852
	dc.l	-2079926729
	dc.l	1065494243
	dc.l	-378633069
	dc.l	1064135970
	dc.l	-917109976
	dc.l	1062722504
	dc.l	-18840811
	dc.l	1061373144
	dc.l	-218995455
	dc.l	1060120311
	dc.l	445452392
	dc.l	1058307720
	dc.l	-1606970714
	dc.l	1058191375
	dc.l	854632425
	dc.l	-1091340853
	dc.l	-614444173
	dc.l	1056647792
	dc.l	1958705876
mx_PIo2:
	dc.l	1073291771
	dc.l	1073741824
	dc.l	1047807021
	dc.l	0
	dc.l	1022903960
	dc.l	-2147483648
	dc.l	997772369
	dc.l	1610612736
	dc.l	972036995
	dc.l	-2147483648
	dc.l	947528992
	dc.l	1073741824
	dc.l	920879650
	dc.l	-2147483648
	dc.l	896135965
	dc.l	0
mx_ipio2:
	dc.l	10680707
	dc.l	7228996
	dc.l	1387004
	dc.l	2578385
	dc.l	16069853
	dc.l	12639074
	dc.l	9804092
	dc.l	4427841
	dc.l	16666979
	dc.l	11263675
	dc.l	12935607
	dc.l	2387514
	dc.l	4345298
	dc.l	14681673
	dc.l	3074569
	dc.l	13734428
	dc.l	16653803
	dc.l	1880361
	dc.l	10960616
	dc.l	8533493
	dc.l	3062596
	dc.l	8710556
	dc.l	7349940
	dc.l	6258241
	dc.l	3772886
	dc.l	3769171
	dc.l	3798172
	dc.l	8675211
	dc.l	12450088
	dc.l	3874808
	dc.l	9961438
	dc.l	366607
	dc.l	15675153
	dc.l	9132554
	dc.l	7151469
	dc.l	3571407
	dc.l	2607881
	dc.l	12013382
	dc.l	4155038
	dc.l	6285869
	dc.l	7677882
	dc.l	13102053
	dc.l	15825725
	dc.l	473591
	dc.l	9065106
	dc.l	15363067
	dc.l	6271263
	dc.l	9264392
	dc.l	5636912
	dc.l	4652155
	dc.l	7056368
	dc.l	13614112
	dc.l	10155062
	dc.l	1944035
	dc.l	9527646
	dc.l	15080200
	dc.l	6658437
	dc.l	6231200
	dc.l	6832269
	dc.l	16767104
	dc.l	5075751
	dc.l	3212806
	dc.l	1398474
	dc.l	7579849
	dc.l	6349435
	dc.l	12618859
	dc.l	4703257
	dc.l	12806093
	dc.l	14477321
	dc.l	2786137
	dc.l	12875403
	dc.l	9837734
	dc.l	14528324
	dc.l	13719321
	dc.l	343717
	dc.l	16713477
	dc.l	4161075
	dc.l	15217346
	dc.l	14569368
	dc.l	3308987
	dc.l	12795174
	dc.l	15690526
	dc.l	6224031
	dc.l	3809077
	dc.l	13300351
	dc.l	1935345
	dc.l	2199676
	dc.l	8135786
	dc.l	16412373
	dc.l	7810352
	dc.l	4406037
	dc.l	12981429
	dc.l	10295747
	dc.l	12764333
	dc.l	4279596
	dc.l	6094860
	dc.l	4619654
	dc.l	2978275
	dc.l	10143387
	dc.l	25139
	dc.l	8180404
	dc.l	9938868
	dc.l	13980983
	dc.l	16137943
	dc.l	1577123
	dc.l	16545357
	dc.l	2792804
	dc.l	11261808
	dc.l	16284771
	dc.l	5746810
	dc.l	15144215
	dc.l	5654976
	dc.l	14276155
	dc.l	3703975
	dc.l	13312804
	dc.l	7834326
	dc.l	2315354
	dc.l	12132096
	dc.l	1772273
	dc.l	14667289
	dc.l	16724383
	dc.l	6954598
	dc.l	6379417
	dc.l	4717484
	dc.l	14188414
	dc.l	12018978
	dc.l	9037874
	dc.l	6340582
	dc.l	13485295
	dc.l	603756
	dc.l	13909853
	dc.l	14147094
	dc.l	14564184
	dc.l	9608158
	dc.l	2630354
	dc.l	15238696
	dc.l	5069026
	dc.l	3328710
	dc.l	1499912
	dc.l	13336032
	dc.l	5292055
	dc.l	10952179
	dc.l	6021144
	dc.l	3412782
	dc.l	6427267
	dc.l	84099
	dc.l	6000373
	dc.l	8368301
	dc.l	15919390
	dc.l	4409928
	dc.l	13854480
	dc.l	14212522
	dc.l	4349870
	dc.l	13525354
	dc.l	10758154
	dc.l	11835859
	dc.l	15902214
	dc.l	8353628
	dc.l	8635043
	dc.l	8928353
	dc.l	7893898
	dc.l	5934255
	dc.l	12441455
	dc.l	6530605
	dc.l	13352948
	dc.l	15696269
	dc.l	6799654
	dc.l	4573781
	dc.l	3594698
	dc.l	13805608
	dc.l	9265602
	dc.l	7850258
	dc.l	1320452
	dc.l	10176018
	dc.l	12868036
	dc.l	4507080
	dc.l	9548365
	dc.l	15931136
	dc.l	11355092
	dc.l	15026473
	dc.l	1103357
	dc.l	16563712
	dc.l	13407262
	dc.l	15650416
	dc.l	16072211
	dc.l	8450540
	dc.l	12838835
	dc.l	2685127
	dc.l	9700755
	dc.l	4092353
	dc.l	11733294
	dc.l	15942923
	dc.l	10228360
	dc.l	8069291
	dc.l	10466606
	dc.l	12751431
	dc.l	3093115
	dc.l	7165196
	dc.l	9480050
	dc.l	2090859
	dc.l	9882417
	dc.l	4855417
	dc.l	14842177
	dc.l	9035764
	dc.l	9934056
	dc.l	8709858
	dc.l	9908633
	dc.l	7073160
	dc.l	3563359
	dc.l	982459
	dc.l	11835976
	dc.l	7119975
	dc.l	4354673
	dc.l	3300749
	dc.l	12064159
	dc.l	648636
	dc.l	2437517
	dc.l	3765495
	dc.l	1836336
	dc.l	68621
	dc.l	6817867
	dc.l	5828140
	dc.l	9480775
	dc.l	190324
	dc.l	2414269
	dc.l	10911223
	dc.l	7489646
	dc.l	15668895
	dc.l	10917006
	dc.l	16159156
	dc.l	5329873
	dc.l	15862479
	dc.l	3381280
	dc.l	8276981
	dc.l	6841266
	dc.l	6242013
	dc.l	220480
	dc.l	8358277
	dc.l	2708053
	dc.l	12608567
	dc.l	1103981
	dc.l	3295282
	dc.l	7687259
	dc.l	13922638
	dc.l	7230533
	dc.l	12650763
	dc.l	6944042
	dc.l	13985300
	dc.l	10290983
	dc.l	5243997
	dc.l	14367668
	dc.l	12941034
	dc.l	1571207
	dc.l	8219465
	dc.l	12199709
	dc.l	2714006
	dc.l	11324614
	dc.l	5510317
	dc.l	7004816
	dc.l	9034120
	dc.l	5272108
	dc.l	12493828
	dc.l	9701239
	dc.l	7352563
	dc.l	2620416
	dc.l	11039210
	dc.l	4833894
	dc.l	4055140
	dc.l	8641943
	dc.l	9912227
	dc.l	16618563
	dc.l	9209357
	dc.l	14565681
	dc.l	10303890
	dc.l	9203933
	dc.l	15185687
	dc.l	3923720
	dc.l	2832149
	dc.l	10518620
	dc.l	9666650
	dc.l	9572624
	dc.l	14215183
	dc.l	11501676
	dc.l	4980699
	dc.l	1019960
	dc.l	7739481
	dc.l	1418594
	dc.l	12307297
	dc.l	12159431
	dc.l	12402704
	dc.l	324306
	dc.l	2585929
	dc.l	16168683
	dc.l	12264155
	dc.l	11146250
	dc.l	3090057
	dc.l	7766884
	dc.l	3357449
	dc.l	1741838
	dc.l	11156049
	dc.l	12755741
	dc.l	11464111
	dc.l	1189468
	dc.l	5096045
	dc.l	10254893
	dc.l	9918144
	dc.l	8601347
	dc.l	16183305
	dc.l	9191467
	dc.l	10039661
	dc.l	504889
	dc.l	1384460
	dc.l	6013912
	dc.l	12882677
	dc.l	4959686
	dc.l	10865230
	dc.l	13449127
	dc.l	3582438
	dc.l	9736875
	dc.l	6832861
	dc.l	14574361
	dc.l	15699062
	dc.l	5409640
	dc.l	3660796
	dc.l	11248046
	dc.l	3216863
	dc.l	10595840
	dc.l	14351116
	dc.l	6704484
	dc.l	11994605
	dc.l	3171625
	dc.l	12539479
	dc.l	3866439
	dc.l	12188010
	dc.l	15974005
	dc.l	14652200
	dc.l	3178667
	dc.l	16157798
	dc.l	1428228
	dc.l	402170
	dc.l	1959129
	dc.l	10793789
	dc.l	9378647
	dc.l	642358
	dc.l	15286862
	dc.l	10796563
	dc.l	11871027
	dc.l	1747696
	dc.l	11035983
	dc.l	10863058
	dc.l	999179
	dc.l	13465691
	dc.l	7797027
	dc.l	297851
	dc.l	7477129
	dc.l	5482182
	dc.l	14839407
	dc.l	60399
	dc.l	5786267
	dc.l	12049092
	dc.l	12215978
	dc.l	13619062
	dc.l	1901265
	dc.l	3010993
	dc.l	12687756
	dc.l	7843267
	dc.l	14305414
	dc.l	10509815
	dc.l	16023750
	dc.l	3141804
	dc.l	10153181
	dc.l	12344383
	dc.l	7200464
	dc.l	2082704
	dc.l	11983658
	dc.l	3810723
	dc.l	10137344
	dc.l	9655213
	dc.l	284598
	dc.l	11808041
	dc.l	8290379
	dc.l	10946522
	dc.l	961142
	dc.l	10574203
	dc.l	2757142
	dc.l	2996188
	dc.l	16639482
	dc.l	16702345
	dc.l	16629385
	dc.l	7108324
	dc.l	16558342
	dc.l	7372862
	dc.l	1404549
	dc.l	16746493
	dc.l	474664
	dc.l	3368801
	dc.l	8788010
	dc.l	15383885
	dc.l	11528115
	dc.l	7237007
	dc.l	3762069
	dc.l	6012721
	dc.l	4773764
	dc.l	1498928
	dc.l	4402631
	dc.l	3498277
	dc.l	13529289
	dc.l	12110640
	dc.l	16608447
	dc.l	10616996
	dc.l	14969861
	dc.l	10542426
	dc.l	4681505
	dc.l	13767266
	dc.l	8674489
	dc.l	4809072
	dc.l	14702187
	dc.l	86681
	dc.l	3626320
	dc.l	12047646
	dc.l	12906803
	dc.l	6254099
	dc.l	14954589
	dc.l	11087493
	dc.l	12825117
	dc.l	3551905
	dc.l	10794760
	dc.l	13939178
	dc.l	2225942
	dc.l	14969231
	dc.l	7864103
	dc.l	8389388
	dc.l	2965645
	dc.l	10538319
	dc.l	10069280
	dc.l	13869747
	dc.l	679215
	dc.l	4389300
	dc.l	13359633
	dc.l	13680253
	dc.l	12704667
	dc.l	12392363
	dc.l	8495818
	dc.l	6056456
	dc.l	1529134
	dc.l	5570599
	dc.l	15733887
	dc.l	8783841
	dc.l	6556436
	dc.l	9257366
	dc.l	14597767
	dc.l	2817498
	dc.l	11937131
	dc.l	3443067
	dc.l	16708357
	dc.l	10403769
	dc.l	5204584
	dc.l	11020874
	dc.l	5948495
	dc.l	12384301
	dc.l	9984727
	dc.l	9816052
	dc.l	9260301
	dc.l	10893856
	dc.l	6248356
	dc.l	11616020
	dc.l	9779328
	dc.l	73932
	dc.l	8838513
	dc.l	11984585
	dc.l	16081087
	dc.l	1140045
	dc.l	7014145
	dc.l	11317388
	dc.l	13680818
	dc.l	4740433
	dc.l	981790
	dc.l	12808853
	dc.l	3868323
	dc.l	3489984
	dc.l	8117254
	dc.l	13387232
	dc.l	16394574
	dc.l	13159126
	dc.l	4322280
	dc.l	14574716
	dc.l	14181531
	dc.l	3260121
	dc.l	12818340
	dc.l	13916279
	dc.l	12968809
	dc.l	1301232
	dc.l	3947194
	dc.l	4593734
	dc.l	6255957
	dc.l	16104914
	dc.l	13013614
	dc.l	6106796
	dc.l	15549454
	dc.l	4341276
	dc.l	8897633
	dc.l	15334697
	dc.l	15980263
	dc.l	13270050
	dc.l	3510639
	dc.l	12967944
	dc.l	9295871
	dc.l	14838382
	dc.l	13041072
	dc.l	12650643
	dc.l	7626108
	dc.l	11709803
	dc.l	10317517
	dc.l	8090174
	dc.l	6951366
	dc.l	11128823
	dc.l	14644009
	dc.l	12241333
	dc.l	5308599
	dc.l	897762
	dc.l	2407028
	dc.l	6323685
	dc.l	9099380
	dc.l	2888973
	dc.l	792705
	dc.l	9725566
	dc.l	1452289
	dc.l	7764639
	dc.l	12516861
	dc.l	15680854
	dc.l	3571417
	dc.l	1300972
	dc.l	12171915
	dc.l	16553924
	dc.l	2598961
	dc.l	12807921
	dc.l	3589524
	dc.l	5679320
	dc.l	11905204
	dc.l	969935
	dc.l	2984210
	dc.l	3430255
	dc.l	9000492
	dc.l	14929561
	dc.l	12132566
	dc.l	11165291
	dc.l	10234430
	dc.l	13393681
	dc.l	4852733
	dc.l	16512225
	dc.l	7158670
	dc.l	2918114
	dc.l	8705257
	dc.l	11121916
	dc.l	13758191
	dc.l	13186350
	dc.l	6371631
	dc.l	4464952
	dc.l	13162779
	dc.l	720001
	dc.l	6966011
	dc.l	14162991
	dc.l	8696915
	dc.l	9214286
	dc.l	13378132
	dc.l	14439722
	dc.l	14075584
	dc.l	9836811
	dc.l	12087322
	dc.l	6591849
	dc.l	6314534
	dc.l	15618623
	dc.l	987519
	dc.l	1160692
	dc.l	16108540
	dc.l	2997300
	dc.l	15645748
	dc.l	13393384
	dc.l	6315741
	dc.l	10194535
	dc.l	15676306
	dc.l	12064713
	dc.l	10180705
	dc.l	12343265
	dc.l	13009745
	dc.l	1064664
	dc.l	4747741
	dc.l	14490669
	dc.l	10557615
	dc.l	4598817
	dc.l	14152537
	dc.l	9992921
	dc.l	12604574
	dc.l	16418383
	dc.l	16516694
	dc.l	11434469
	dc.l	3547785
	dc.l	2272568
	dc.l	14455655
	dc.l	11200597
	dc.l	3679874
	dc.l	10217418
	dc.l	10751313
	dc.l	11613081
	dc.l	972713
	dc.l	4719977
	dc.l	15774309
	dc.l	10979455
	dc.l	9915528
	dc.l	3592697
	dc.l	11768353
	dc.l	4883067
	dc.l	2215832
	dc.l	14458688
	dc.l	5588956
	dc.l	3831009
	dc.l	4385639
	dc.l	14654974
	dc.l	6280286
	dc.l	10774395
	dc.l	8039610
	dc.l	10679893
	dc.l	2328619
	dc.l	5618241
	dc.l	552537
	dc.l	8792609
	dc.l	8603449
	dc.l	15131529
	dc.l	13934309
	dc.l	4258633
	dc.l	15292159
	dc.l	13242140
	dc.l	9066949
	dc.l	2882196
	dc.l	12960211
	dc.l	13616399
	dc.l	11426523
	dc.l	8832327
	dc.l	6439813
	dc.l	3900961
	dc.l	9730348
	dc.l	8872208
	dc.l	8080426
	dc.l	1715328
	dc.l	1228611
	dc.l	9447048
	dc.l	8993912
	dc.l	14992552
	dc.l	8117221
	dc.l	12729028
	dc.l	15397926
	dc.l	9070583
	dc.l	12554765
	dc.l	2859877
	dc.l	11637565
	dc.l	752829
	dc.l	14438820
	dc.l	6544679
	dc.l	14541161
	dc.l	1676442
	dc.l	9775528
	dc.l	2674280
	dc.l	11857161
	dc.l	2137924
	dc.l	13277262
	dc.l	6521456
	dc.l	2325630
	dc.l	3324175
	dc.l	9368999
	dc.l	15160852
	dc.l	586017
	dc.l	2792885
	dc.l	5078639
	dc.l	5314981
	dc.l	11270581
	dc.l	14081922
	dc.l	6413718
	dc.l	144918
	dc.l	10435268
	dc.l	10592899
	dc.l	7204210
	dc.l	8031545
	dc.l	11122818
	dc.l	6042219
	dc.l	5973830
	dc.l	15545344
	dc.l	7798994
	dc.l	5633276
	dc.l	5069057
	dc.l	8417760
