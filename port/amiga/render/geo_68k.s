; geo_68k.s - THE PAINTER'S CORNERS in assembler (geo.h; the C reference is geo.c geo_block_c, the same
; arithmetic step for step: the machine's test compares the two).  A block's corners turned (2.14, muls.w),
; shifted, tested against the picture's sides and planes, and projected through the lens's table (rcp[z]:
; one muls.l a coordinate, no division); a corner deeper than the table or more than 16384
; columns / rows off the middle by two divs.l, rounded down, as before.
; 68020+ (muls.l 32x32->32 and divs.l 32/32 only: no 64-bit forms, a 68060 has none).
; vasmm68k_mot -quiet -no-opt -m68060 -Fhunk / -Felf

G_V	equ	0
G_N	equ	4
G_IX	equ	8
G_IY	equ	12
G_OUT	equ	16
G_VV	equ	20
G_R	equ	24
G_T	equ	44
G_FX	equ	56
G_HW	equ	60
G_CY	equ	64
G_CYB	equ	68
G_FAR	equ	72
G_RCP	equ	76
G_NRCP	equ	80

	section	code,code
	xdef	_geo_block_68k
	xdef	geo_block_68k
; void geo_block_68k(const geo_blk *g)
_geo_block_68k:
geo_block_68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a0			; g
	move.l	G_V(a0),a1
	move.l	G_N(a0),d0
	ble	gb_done
	move.l	G_NRCP(a0),d1			; locals: (sp) the corners left (unused), 4 the picture's width (2 hw), 8 its
	beq.s	gb_n0				; rows, 12 nrcp - 24 (0 without a table: every z past it) -- the z test as one
	sub.l	#24,d1				; unsigned compare
gb_n0:	move.l	d1,-(sp)
	move.l	G_CY(a0),d1
	add.l	G_CYB(a0),d1
	move.l	d1,-(sp)
	move.l	G_HW(a0),d1
	add.l	d1,d1
	move.l	d1,-(sp)
	move.l	d0,-(sp)			; (a6 holds the table)
	move.l	d0,d5				; the count in d5's high word (n - 1 .. 0), 14 in its low word: asr.l d5
	subq.l	#1,d5				; shifts by 14 (the count mod 64)
	swap	d5
	move.w	#14,d5
	move.l	G_RCP(a0),a6
	move.l	G_IX(a0),a2
	move.l	G_IY(a0),a3
	move.l	G_OUT(a0),a4
	move.l	G_VV(a0),a5
gb_loop:
	move.w	(a1)+,d1			; lx
	move.w	(a1)+,d2			; ly
	move.w	(a1)+,d3			; lz
	; x = (lx R0 + ly R3 + lz R6) >> 14 + T0, y with R1 R4 R7, z with R2 R5 R8: the nine products so scheduled that
	; no add.l waits on the muls.w right before it (the sums mod 2^32 do not depend on their order); d1 / d2 / d3
	; hold z's products once they are no longer needed as factors
	move.w	d1,d0
	muls.w	G_R+0(a0),d0			; lx R0
	move.w	d1,d6
	muls.w	G_R+2(a0),d6			; lx R1
	muls.w	G_R+4(a0),d1			; lx R2 (z's sum in d1)
	move.w	d2,d4
	muls.w	G_R+6(a0),d4			; ly R3
	move.w	d2,d7
	muls.w	G_R+8(a0),d7			; ly R4
	add.l	d4,d0
	muls.w	G_R+10(a0),d2			; ly R5
	add.l	d7,d6
	move.w	d3,d4
	muls.w	G_R+12(a0),d4			; lz R6
	add.l	d2,d1
	move.w	d3,d7
	muls.w	G_R+14(a0),d7			; lz R7
	add.l	d4,d0
	muls.w	G_R+16(a0),d3			; lz R8
	add.l	d7,d6
	asr.l	d5,d0
	add.l	d3,d1
	asr.l	d5,d6
	add.l	G_T+0(a0),d0
	asr.l	d5,d1
	add.l	G_T+4(a0),d6
	move.l	d1,d7
	move.l	d0,(a5)+
	add.l	G_T+8(a0),d7
	move.l	d6,(a5)+
	move.l	d7,(a5)+
	; THE QUICK WAY: the far plane's bit; behind the near plane only marked; the table with muls.l's V as the
	; test; the sides from the column and row
	moveq	#0,d1
	move.l	G_FAR(a0),d2
	beq.s	gq_f
	cmp.l	d2,d7
	blt.s	gq_f
	moveq	#2,d1
gq_f:	move.l	d7,d2				; 24 <= z < nrcp as one unsigned test of z - 24 (rare: gq_r)
	sub.l	#24,d2
	cmp.l	12(sp),d2
	bhs	gq_r
gq_z:	move.l	(a6,d7.l*4),d3			; t
	move.l	d0,d2
	move.l	d6,d4				; (between the load and its muls)
	muls.l	d3,d2				; x t
	bvs	gb_slow
	muls.l	d3,d4				; y t
	bvs	gb_slow
	add.l	#$8000,d2
	swap	d2
	ext.l	d2
	add.l	G_HW(a0),d2			; the column
	move.l	d2,(a2)+
	move.l	#$8000,d3
	sub.l	d4,d3
	swap	d3
	ext.l	d3
	add.l	G_CY(a0),d3			; the row
	move.l	d3,(a3)+
	cmp.l	4(sp),d2			; 0 <= column <= 2 hw: one unsigned compare (off it: gq_sx)
	bhi.s	gq_sx
gq_x2:	cmp.l	8(sp),d3			; the row likewise (gq_sy)
	bhi.s	gq_sy
gq_y2:	move.b	d1,(a4)+
	sub.l	#$10000,d5			; (gb_next)
	bpl	gb_loop
	bra	gb_end
gq_sx:	tst.l	d2
	bpl.s	gq_x1
	addq.b	#8,d1
	bra.s	gq_x2
gq_x1:	addq.b	#4,d1
	bra.s	gq_x2
gq_sy:	tst.l	d3
	bpl.s	gq_y1
	or.b	#16,d1
	bra.s	gq_y2
gq_y1:	or.b	#32,d1
	bra.s	gq_y2
gq_r:	tst.l	d2				; z < 24: behind, no place on the picture; else past the table: gb_slow
	bpl.s	gb_slow
	addq.b	#1,d1
	move.b	d1,(a4)+
	addq.l	#4,a2
	addq.l	#4,a3
	bra	gb_next
gb_slow:					; the outcode in d1 (as before: exact); d5 (count, 14) kept on the stack
	move.l	d5,-(sp)
	moveq	#0,d1
	moveq	#24,d2
	cmp.l	d2,d7
	bge.s	gb_near
	moveq	#1,d1
gb_near:
	move.l	G_FAR(a0),d2
	beq.s	gb_far
	cmp.l	d2,d7
	blt.s	gb_far
	or.b	#2,d1
gb_far:
	move.l	d0,d2
	muls.l	G_FX(a0),d2			; xf
	move.l	d7,d3
	muls.l	G_HW(a0),d3			; zx
	cmp.l	d3,d2
	ble.s	gb_x1
	or.b	#4,d1
	bra.s	gb_x2
gb_x1:	move.l	d2,d4
	neg.l	d4
	cmp.l	d3,d4
	ble.s	gb_x2
	or.b	#8,d1
gb_x2:	move.l	d6,d4
	muls.l	G_FX(a0),d4			; yf (kept in d4)
	move.l	d7,d3
	muls.l	G_CY(a0),d3
	cmp.l	d3,d4
	ble.s	gb_y1
	or.b	#16,d1
	bra.s	gb_y2
gb_y1:	move.l	d7,d3
	muls.l	G_CYB(a0),d3
	move.l	d4,d5
	neg.l	d5
	cmp.l	d3,d5
	ble.s	gb_y2
	or.b	#32,d1
gb_y2:	move.b	d1,(a4)+
	btst	#0,d1
	beq.s	gb_proj
	addq.l	#4,a2				; (behind the eye: no place on the picture)
	addq.l	#4,a3
	bra	gb_snext
gb_proj:
	cmp.l	G_NRCP(a0),d7			; z within the table (unsigned: z >= 24 here)
	bhs	gb_div
	move.l	d7,d3
	moveq	#14,d5
	lsl.l	d5,d3				; z << 14
	move.l	d2,d5
	bpl.s	gb_ax
	neg.l	d5
gb_ax:	cmp.l	d3,d5				; |xf| < z << 14
	bhs	gb_div
	move.l	d4,d5
	bpl.s	gb_ay
	neg.l	d5
gb_ay:	cmp.l	d3,d5				; |yf| < z << 14
	bhs	gb_div
	move.l	(a6,d7.l*4),d3			; t = rcp[z]
	move.l	d0,d2
	muls.l	d3,d2				; x t
	add.l	#$8000,d2
	swap	d2
	ext.l	d2				; >> 16
	add.l	G_HW(a0),d2
	move.l	d2,(a2)+
	muls.l	d6,d3				; y t
	move.l	#$8000,d2
	sub.l	d3,d2
	swap	d2
	ext.l	d2
	add.l	G_CY(a0),d2
	move.l	d2,(a3)+
	bra	gb_snext
gb_div:
	move.l	d7,d3
	add.l	d3,d3				; d2 = 2z (> 0)
	; column: floor((2 xf + z) / 2z) + hw   (xf in d2)
	add.l	d2,d2
	add.l	d7,d2
	bmi.s	gb_cn
	divs.l	d3,d2
	bra.s	gb_cs
gb_cn:	neg.l	d2
	add.l	d3,d2
	subq.l	#1,d2
	divs.l	d3,d2
	neg.l	d2
gb_cs:	add.l	G_HW(a0),d2
	move.l	d2,(a2)+
	; row: floor((z - 2 yf) / 2z) + cy   (yf in d4)
	move.l	d7,d2
	add.l	d4,d4
	sub.l	d4,d2
	bmi.s	gb_rn
	divs.l	d3,d2
	bra.s	gb_rs
gb_rn:	neg.l	d2
	add.l	d3,d2
	subq.l	#1,d2
	divs.l	d3,d2
	neg.l	d2
gb_rs:	add.l	G_CY(a0),d2
	move.l	d2,(a3)+
gb_snext:
	move.l	(sp)+,d5
gb_next:
	sub.l	#$10000,d5
	bpl	gb_loop
gb_end:	lea	16(sp),sp
gb_done:
	movem.l	(sp)+,d2-d7/a2-a6
	rts
