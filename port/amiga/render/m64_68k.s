; 64-Bit-Multiplikation/-Division ohne die 64-Bit-Formen von mulu.l/muls.l/divu.l/divs.l (68040/68060: Trap über die
; 68060.library bzw. FPSP-Emulation, Hunderte Takte). vasm: vasmm68k_mot -no-opt -m68060
;  - m64_muls/m64_mulu: 32 x 32 -> 64 aus vier 16-Bit-Teilprodukten
;  - m64_divs/m64_divu: 64 / 32 -> 32 Quotient + Rest (Hacker's Delight divlu2, zwei 32/32-Divisionen), Überlauf -> V
;    und Operanden unverändert (wie divs.l/divu.l)
;  - libgcc-Ersatz (C-Aufruf, Argumente auf dem Stapel, Ergebnis d0:d1): __muldi3 __udivdi3 __umoddi3 __divdi3 __moddi3
;    (nur mit -DLIBGCC: Amiga-040/060-Bau; Prüfbau unter qemu ruft die m64_*di3-Namen)
; Stapelaufrufe (alle Register bleiben erhalten), Makros dazu in m64.i:
;   m64_muls/m64_mulu: 4(sp) = x, 8(sp) = y -> 4(sp) = unteres, 8(sp) = oberes Langwort
;   m64_divs/m64_divu: 4(sp) = lo, 8(sp) = hi, 12(sp) = Teiler -> 4(sp) = Quotient, 8(sp) = Rest, 14(sp).w = CCR
	machine	68060
	section	code,code

	xdef	m64_muls
	xdef	m64_mulu
	xdef	m64_divs
	xdef	m64_divu

; d0 = x, d1 = y -> d0 = unteres, d1 = oberes Langwort von x * y (vorzeichenlos); zerstört d2-d4
umul64:	move.l	d0,d2
	move.l	d1,d3
	swap	d2				; xh
	swap	d3				; yh
	move.l	d2,d4
	mulu.w	d3,d4				; p3 = xh * yh
	mulu.w	d1,d2				; p2 = xh * yl
	mulu.w	d0,d3				; p1 = yh * xl
	mulu.w	d1,d0				; p0 = xl * yl
	moveq	#0,d1
	add.l	d3,d2				; Mitte = p1 + p2 (Übertrag = 2^48)
	addx.l	d1,d1
	swap	d1				; Übertrag << 16
	swap	d2
	move.w	d2,d1				; Übertrag << 16 | Mitte >> 16
	clr.w	d2				; Mitte << 16
	add.l	d2,d0
	addx.l	d4,d1
	rts

m64_mulu:
	movem.l	d0-d4,-(sp)
	move.l	24(sp),d0
	move.l	28(sp),d1
	bsr	umul64
	move.l	d0,24(sp)
	move.l	d1,28(sp)
	movem.l	(sp)+,d0-d4
	rts

m64_muls:
	movem.l	d0-d4,-(sp)
	move.l	24(sp),d0
	move.l	28(sp),d1
	bsr	umul64
	tst.l	24(sp)				; x < 0: oberes -= y
	bpl	mms_1
	sub.l	28(sp),d1
mms_1:	tst.l	28(sp)				; y < 0: oberes -= x
	bpl	mms_2
	sub.l	24(sp),d1
mms_2:	move.l	d0,24(sp)
	move.l	d1,28(sp)
	movem.l	(sp)+,d0-d4
	rts

; d1:d0 / d2 (vorzeichenlos, d1 < d2) -> d0 = Quotient, d1 = Rest; zerstört d2-d7/a0-a1
; Hacker's Delight divlu2: Teiler normalisieren (oberstes Bit gesetzt), zwei 16-Bit-Quotientenziffern je über eine
; 32/32-Division mit höchstens zwei Korrekturen
udiv64:	bfffo	d2{0:32},d3			; s = Anzahl führender Nullen
	movea.l	d3,a1
	lsl.l	d3,d2				; v <<= s
	lsl.l	d3,d1
	tst.l	d3
	beq	ud_s0
	moveq	#32,d4
	sub.l	d3,d4
	move.l	d0,d5
	lsr.l	d4,d5
	or.l	d5,d1				; un32 = u1 << s | u0 >> (32 - s)
ud_s0:	lsl.l	d3,d0				; un10 = u0 << s
	movea.l	d0,a0
	move.l	d2,d4
	clr.w	d4
	swap	d4				; vn1 (vn0 = unteres Wort von d2 für mulu.w)
	move.l	d1,d5
	divul.l	d4,d6:d5			; q1 = un32 / vn1, rhat = un32 % vn1
	move.l	a0,d0
	clr.w	d0
	swap	d0				; un1
ud_a1:	cmp.l	#$10000,d5
	bcc	ud_d1				; q1 >= b
	move.l	d5,d7
	mulu.w	d2,d7				; q1 * vn0
	move.l	d6,d3
	swap	d3
	clr.w	d3
	or.l	d0,d3				; rhat * b + un1
	cmp.l	d3,d7
	bls	ud_k1
ud_d1:	subq.l	#1,d5
	add.l	d4,d6				; rhat += vn1
	cmp.l	#$10000,d6
	bcs	ud_a1
ud_k1:	move.l	d1,d7
	swap	d7
	clr.w	d7
	or.l	d0,d7				; un32 * b + un1 (mod 2^32)
	move.l	d5,d3
	mulu.l	d2,d3
	sub.l	d3,d7				; un21 = un32 * b + un1 - q1 * v
	move.l	d7,d1
	divul.l	d4,d6:d7			; q0 = un21 / vn1, rhat
	move.l	a0,d0
	and.l	#$ffff,d0
	movea.l	d0,a0				; un0
ud_a2:	cmp.l	#$10000,d7
	bcc	ud_d2
	move.l	d7,d3
	mulu.w	d2,d3				; q0 * vn0
	move.l	d6,d0
	swap	d0
	clr.w	d0
	add.l	a0,d0				; rhat * b + un0
	cmp.l	d0,d3
	bls	ud_k2
ud_d2:	subq.l	#1,d7
	add.l	d4,d6
	cmp.l	#$10000,d6
	bcs	ud_a2
ud_k2:	swap	d1
	clr.w	d1
	add.l	a0,d1				; un21 * b + un0
	move.l	d7,d3
	mulu.l	d2,d3
	sub.l	d3,d1
	move.l	a1,d3
	lsr.l	d3,d1				; Rest = (un21 * b + un0 - q0 * v) >> s
	swap	d5
	clr.w	d5
	or.l	d7,d5
	move.l	d5,d0				; q1 * b + q0
	rts

m64_divu:
	movem.l	d0-d7/a0-a1,-(sp)		; 40 Byte: lo 44(sp), hi 48(sp), Teiler 52(sp)
	move.l	44(sp),d0
	move.l	48(sp),d1
	move.l	52(sp),d2
	cmp.l	d2,d1
	bcc	mdu_v				; hi >= Teiler: Quotient >= 2^32
	bsr	udiv64
	move.l	d0,44(sp)
	move.l	d1,48(sp)
	tst.l	d0
	move.w	ccr,d0
	move.w	d0,54(sp)
	movem.l	(sp)+,d0-d7/a0-a1
	rts
mdu_v:	move.w	#2,54(sp)			; V
	movem.l	(sp)+,d0-d7/a0-a1
	rts

m64_divs:
	movem.l	d0-d7/a0-a1,-(sp)
	move.l	44(sp),d0
	move.l	48(sp),d1
	move.l	52(sp),d2
	bpl	mds_1
	neg.l	d2				; |Teiler|
mds_1:	tst.l	d1
	bpl	mds_2
	neg.l	d0				; |Dividend|
	negx.l	d1
mds_2:	cmp.l	d2,d1
	bcc	mds_v
	bsr	udiv64
	move.l	48(sp),d2			; Vorzeichen Dividend -> Rest
	bpl	mds_3
	neg.l	d1
mds_3:	eor.l	d2,52(sp)			; Vorzeichen Quotient (Bit 31 von 52(sp))
	bmi	mds_n
	tst.l	d0				; positiv: < 2^31
	bmi	mds_v
	bra	mds_ok
mds_n:	cmp.l	#$80000000,d0			; negativ: <= 2^31
	bhi	mds_v
	neg.l	d0
mds_ok:	move.l	d0,44(sp)
	move.l	d1,48(sp)
	tst.l	d0
	move.w	ccr,d0
	move.w	d0,54(sp)
	movem.l	(sp)+,d0-d7/a0-a1
	rts
mds_v:	move.w	#2,54(sp)
	movem.l	(sp)+,d0-d7/a0-a1
	rts

; ---------------------------------------------------------------- libgcc-Ersatz (C-Aufrufe)
; 64-Bit-Werte auf dem Stapel: oberes Langwort zuerst; Ergebnis d0 = oberes, d1 = unteres Langwort
	xdef	_m64_muldi3
	xdef	m64_muldi3
	xdef	_m64_udivdi3
	xdef	m64_udivdi3
	xdef	_m64_umoddi3
	xdef	m64_umoddi3
	xdef	_m64_divdi3
	xdef	m64_divdi3
	xdef	_m64_moddi3
	xdef	m64_moddi3
	ifd	LIBGCC
	xdef	___muldi3
	xdef	___udivdi3
	xdef	___umoddi3
	xdef	___divdi3
	xdef	___moddi3
___muldi3:
	endif
_m64_muldi3:
m64_muldi3:					; a = 4/8(sp), b = 12/16(sp)
	movem.l	d2-d4,-(sp)
	move.l	20(sp),d0			; al
	move.l	28(sp),d1			; bl
	bsr	umul64				; d1:d0 = al * bl
	move.l	16(sp),d2			; ah
	mulu.l	28(sp),d2			; ah * bl
	add.l	d2,d1
	move.l	24(sp),d2			; bh
	mulu.l	20(sp),d2			; bh * al
	add.l	d2,d1
	exg	d0,d1
	movem.l	(sp)+,d2-d4
	rts

; d1:d0 = n, d3:d2 = d (vorzeichenlos, d != 0) -> d1:d0 = Quotient, d3:d2 = Rest; zerstört d4-d7/a0-a2
; (Hacker's Delight divDU: d < 2^32 über zwei 64/32-Schritte, sonst über die normalisierten oberen 32 Bit von d)
udiv6464:
	tst.l	d3
	bne	u66_big
	cmp.l	d2,d1
	bcs	u66_one
	move.l	d0,a2				; n.hi >= d: q1 = n.hi / d, dann (n.hi % d):n.lo / d
	move.l	d1,d0
	divul.l	d2,d1:d0			; d0 = q1, d1 = n.hi % d
	exg	d0,a2				; d0 = n.lo, a2 = q1
	bsr	udiv64				; d0 = q0, d1 = Rest
	move.l	d1,d2
	moveq	#0,d3
	move.l	a2,d1
	rts
u66_one:	bsr	udiv64
	move.l	d1,d2
	moveq	#0,d3
	moveq	#0,d1
	rts
u66_big:	movem.l	d0-d3,-(sp)			; n.lo 0(sp), n.hi 4(sp), d.lo 8(sp), d.hi 12(sp)
	bfffo	d3{0:32},d4			; s = nlz(d.hi), 0..31
	move.l	d3,d5
	lsl.l	d4,d5
	tst.l	d4
	beq	u66_b0
	moveq	#32,d6
	sub.l	d4,d6
	move.l	d2,d7
	lsr.l	d6,d7
	or.l	d7,d5				; v1 = (d << s) >> 32
u66_b0:	move.l	d4,a2
	lsr.l	#1,d1				; u1 = n >> 1
	roxr.l	#1,d0
	move.l	d5,d2
	bsr	udiv64				; d0 = q1 = u1 / v1 (u1.hi < v1, da v1 >= 2^31)
	moveq	#31,d4
	sub.l	a2,d4
	lsr.l	d4,d0				; q0 = (q1 << s) >> 31 = q1 >> (31 - s) (64-Bit-Schieben im Original)
	tst.l	d0
	beq	u66_b1
	subq.l	#1,d0
u66_b1:	move.l	d0,a2				; q0
	move.l	8(sp),d1			; d.lo
	bsr	umul64				; d1:d0 = q0 * d.lo
	move.l	12(sp),d2
	move.l	a2,d3
	mulu.l	d3,d2				; q0 * d.hi (< 2^32: q0 * d < n)
	add.l	d2,d1
	move.l	0(sp),d2
	move.l	4(sp),d3
	sub.l	d0,d2
	subx.l	d1,d3				; Rest = n - q0 * d
	move.l	a2,d0
	cmp.l	12(sp),d3			; Rest >= d -> q0 + 1, Rest -= d
	bcs	u66_b3
	bhi	u66_b2
	cmp.l	8(sp),d2
	bcs	u66_b3
u66_b2:	addq.l	#1,d0
	sub.l	8(sp),d2
	move.l	12(sp),d1
	subx.l	d1,d3
u66_b3:	moveq	#0,d1				; Quotient < 2^32
	lea	16(sp),sp
	rts

	ifd	LIBGCC
___udivdi3:
	endif
_m64_udivdi3:
m64_udivdi3:
	movem.l	d2-d7/a2,-(sp)			; 28 Byte: n = 32/36(sp), d = 40/44(sp)
	move.l	36(sp),d0
	move.l	32(sp),d1
	move.l	44(sp),d2
	move.l	40(sp),d3
	bsr	udiv6464
	exg	d0,d1				; d0 = oberes, d1 = unteres
	movem.l	(sp)+,d2-d7/a2
	rts

	ifd	LIBGCC
___umoddi3:
	endif
_m64_umoddi3:
m64_umoddi3:
	movem.l	d2-d7/a2,-(sp)
	move.l	36(sp),d0
	move.l	32(sp),d1
	move.l	44(sp),d2
	move.l	40(sp),d3
	bsr	udiv6464
	move.l	d3,d0
	move.l	d2,d1
	movem.l	(sp)+,d2-d7/a2
	rts

; Vorzeichen: Quotient negativ bei verschiedenen Vorzeichen, Rest mit dem Vorzeichen des Dividenden
	ifd	LIBGCC
___divdi3:
	endif
_m64_divdi3:
m64_divdi3:
	movem.l	d2-d7/a2-a3,-(sp)		; 32 Byte: n = 36/40(sp), d = 44/48(sp)
	bsr	sdiv_ab
	move.l	a3,d2
	tst.l	d2				; Bit 31 = Vorzeichen Quotient
	bpl	sd_q
	neg.l	d0
	negx.l	d1
sd_q:	exg	d0,d1
	movem.l	(sp)+,d2-d7/a2-a3
	rts

	ifd	LIBGCC
___moddi3:
	endif
_m64_moddi3:
m64_moddi3:
	movem.l	d2-d7/a2-a3,-(sp)
	bsr	sdiv_ab
	tst.l	36(sp)				; n.hi: Vorzeichen Dividend
	bpl	sm_r
	neg.l	d2
	negx.l	d3
sm_r:	move.l	d3,d0
	move.l	d2,d1
	movem.l	(sp)+,d2-d7/a2-a3
	rts

; Beträge von n (40/44(sp) aus Sicht des Aufrufers + 4) und d, dividieren; a3 = n.hi ^ d.hi (Vorzeichen Quotient)
sdiv_ab:	move.l	44(sp),d0			; n.lo
	move.l	40(sp),d1			; n.hi
	move.l	52(sp),d2			; d.lo
	move.l	48(sp),d3			; d.hi
	move.l	d1,d4
	eor.l	d3,d4
	movea.l	d4,a3
	tst.l	d1
	bpl	sa_1
	neg.l	d0
	negx.l	d1
sa_1:	tst.l	d3
	bpl	sa_2
	neg.l	d2
	negx.l	d3
sa_2:	bra	udiv6464
