; pt_68k.s - THE PAINTER'S QUICK FACE LOOP in assembler (ptf.h; the C reference is main.c pt_faces_c, the
; same tests in the same order).  For the faces of a list from c->at: dropped when not drawn in this pass,
; turned away (whole-number normal against the eye) or off the picture; kept as a polygon when all its
; corners are on it; back to C (the index returned) for a block not projected yet, a face a plane cuts, a
; material not noted, or no room.  68020+ (muls.l 32x32->32 only).
; vasmm68k_mot -quiet -no-opt -m68060 -Fhunk / -Felf

C_FORD	equ	0
C_NFORD	equ	4
C_REC	equ	8
C_BLK	equ	12
C_STAMP	equ	16
C_SEE	equ	20
C_CULL	equ	24
C_E	equ	28
C_OUT	equ	40
C_IX	equ	44
C_IY	equ	48
C_UV	equ	52
C_MT	equ	56
C_MTS	equ	60
C_BUF	equ	64
C_NPOLY	equ	68
C_MAX	equ	72
C_COUNT	equ	76
C_AT	equ	80

	xref	pi_lodt				; (pi_68k.s: the LOD thresholds)
	section	code,code
	xdef	_pt_faces_68k
	xdef	pt_faces_68k
; int pt_faces_68k(pt_fctx *c)
_pt_faces_68k:
pt_faces_68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a6			; c
	move.l	C_AT(a6),d7			; i
	move.l	C_FORD(a6),a5
	move.l	C_REC(a6),a4
	move.l	C_OUT(a6),a3
pf_loop:
	cmp.l	C_NFORD(a6),d7
	bge	pf_ret
	move.w	(a5,d7.l*2),d0			; the face
	ext.l	d0
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1				; x 24
	lea	(a4,d1.l),a0			; its record
	moveq	#0,d1
	move.b	19(a0),d1			; fl
	btst	#5,d1				; PTF_HARD: the C loop's
	bne	pf_ret
	moveq	#17,d2				; PTF_VALID | PTF_CORNERS
	and.l	d1,d2
	cmp.b	#17,d2
	bne	pf_next
	moveq	#2,d2				; PTF_SEE: this pass?
	and.l	d1,d2
	cmp.l	C_SEE(a6),d2
	bne	pf_next
	moveq	#0,d2
	move.b	23(a0),d2			; its block projected?
	move.l	C_BLK(a6),a1
	move.l	(a1,d2.l*4),d2
	cmp.l	C_STAMP(a6),d2
	bne	pf_ret
	tst.l	C_CULL(a6)			; turned away?
	beq.s	pf_out
	btst	#3,d1				; (PTF_NORMAL)
	beq.s	pf_out
	move.w	12(a0),d2
	ext.l	d2
	muls.l	C_E+0(a6),d2
	move.w	14(a0),d3
	ext.l	d3
	muls.l	C_E+4(a6),d3
	add.l	d3,d2
	move.w	16(a0),d3
	ext.l	d3
	muls.l	C_E+8(a6),d3
	add.l	d3,d2
	move.l	8(a0),d3			; D - n.E < 0
	sub.l	d2,d3
	bmi	pf_next
pf_out:						; the outcodes: all in d3, any in d4
	move.w	(a0),d2
	ext.l	d2
	move.b	(a3,d2.l),d3
	move.b	d3,d4
	move.w	2(a0),d2
	ext.l	d2
	move.b	(a3,d2.l),d5
	and.b	d5,d3
	or.b	d5,d4
	move.w	4(a0),d2
	ext.l	d2
	move.b	(a3,d2.l),d5
	and.b	d5,d3
	or.b	d5,d4
	move.w	6(a0),d2
	ext.l	d2
	move.b	(a3,d2.l),d5
	and.b	d5,d3
	or.b	d5,d4
	moveq	#3,d5				; all behind the eye or beyond the far plane
	and.b	d3,d5
	bne	pf_next
	btst	#0,d4
	bne.s	pf_o2
	moveq	#$3c,d5				; ... or all off one side
	and.b	d3,d5
	bne	pf_next
pf_o2:	moveq	#3,d5				; cut by a plane: C
	and.b	d4,d5
	bne	pf_ret
	moveq	#0,d2				; the material noted?
	move.w	20(a0),d2
	lsl.l	#4,d2
	move.l	C_MT(a6),a1
	add.l	d2,a1
	move.l	12(a1),d2
	lsr.l	#8,d2
	cmp.l	C_MTS(a6),d2
	bne	pf_ret
	move.l	C_NPOLY(a6),d2			; room?
	cmp.l	C_MAX(a6),d2
	bge	pf_ret
	move.l	d2,d3				; the polygon: buf + 136 n
	lsl.l	#7,d3
	lsl.l	#3,d2
	add.l	d3,d2
	move.l	C_BUF(a6),a2
	add.l	d2,a2
	moveq	#0,d5
	move.b	18(a0),d5			; corners
	move.b	d5,4(a2)
	btst	#2,d1				; PTF_FLAT
	beq.s	pf_tex
	clr.l	(a2)
	move.b	#2,5(a2)			; SPAN_FLAT
	move.b	22(a0),6(a2)
	bra.s	pf_corn
pf_tex:	move.l	(a1),(a2)
	move.b	15(a1),5(a2)
	clr.b	6(a2)
pf_corn:
	move.l	4(a1),d4			; su8
	move.l	8(a1),d6			; sv8
	addq.l	#8,a2
	move.l	C_IX(a6),a1			; the tables once a polygon (a3 / a5, out and ford, put back after)
	move.l	C_IY(a6),a3
	move.l	C_UV(a6),a5
pf_c:	move.w	(a0)+,d2
	ext.l	d2
	move.l	(a1,d2.l*4),(a2)+
	move.l	(a3,d2.l*4),(a2)+
	move.w	(a5,d2.l*4),d3			; u and v side by side (d1 free here)
	move.w	2(a5,d2.l*4),d1
	ext.l	d3
	ext.l	d1
	muls.l	d4,d3
	muls.l	d6,d1
	move.l	d3,(a2)+
	move.l	d1,(a2)+
	subq.l	#1,d5
	bne.s	pf_c
	move.l	C_OUT(a6),a3
	move.l	C_FORD(a6),a5
	addq.l	#1,C_NPOLY(a6)
	addq.l	#1,C_COUNT(a6)
pf_next:
	addq.l	#1,d7
	bra	pf_loop
pf_ret:
	move.l	d7,d0
	movem.l	(sp)+,d2-d7/a2-a6
	rts

C_QBAT	equ	84
C_QEYE	equ	88
C_FNORM	equ	92
C_FVERT	equ	96
C_IEYE	equ	100

	xdef	_pt_cfaces_68k
	xdef	pt_cfaces_68k
; int pt_cfaces_68k(pt_fctx *c): a car's or prop's faces (main.c pt_cfaces_c): the block's turn made, the floating
; cull in gcc's single-precision order ((x + y) + z < 0, fsub/fsmul/fsadd), then as pt_faces_68k
_pt_cfaces_68k:
pt_cfaces_68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a6			; c
	move.l	C_AT(a6),d7
	move.l	C_FORD(a6),a5
	move.l	C_REC(a6),a4
	move.l	C_OUT(a6),a3
cf_loop:
	cmp.l	C_NFORD(a6),d7
	bge	cf_ret
	move.w	(a5,d7.l*2),d0			; the face
	ext.l	d0
	move.l	d0,d6				; (kept for its normal)
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1
	lea	(a4,d1.l),a0
	moveq	#0,d1
	move.b	19(a0),d1			; fl
	btst	#5,d1				; PTF_HARD
	bne	cf_ret
	btst	#0,d1				; PTF_VALID
	beq	cf_next
	moveq	#2,d2				; this pass?
	and.l	d1,d2
	cmp.l	C_SEE(a6),d2
	bne	cf_next
	btst	#4,d1				; PTF_CORNERS
	beq	cf_ret
	moveq	#0,d5
	move.b	23(a0),d5			; the block
	cmp.l	#32,d5
	bhs	cf_ret
	move.l	C_QBAT(a6),a1			; its turn made?
	move.l	(a1,d5.l*4),d2
	cmp.l	C_STAMP(a6),d2
	bne	cf_ret
	tst.l	C_CULL(a6)
	beq	cf_out
	tst.l	C_IEYE(a6)			; the eye in whole numbers (ci_draw): D - n.E < 0
	beq.s	cf_fcull
	btst	#3,d1				; (PTF_NORMAL)
	beq	cf_out
	move.l	d5,d3				; the eye in the block: 12 bytes a block
	add.l	d3,d3
	add.l	d5,d3
	lsl.l	#2,d3
	move.l	C_QEYE(a6),a1
	add.l	d3,a1
	move.w	12(a0),d2
	ext.l	d2
	muls.l	(a1),d2
	move.w	14(a0),d3
	ext.l	d3
	muls.l	4(a1),d3
	add.l	d3,d2
	move.w	16(a0),d3
	ext.l	d3
	muls.l	8(a1),d3
	add.l	d3,d2
	move.l	8(a0),d3
	sub.l	d2,d3
	bmi	cf_next
	bra	cf_out
cf_fcull:
	move.l	d6,d2				; the normal: 12 bytes a face
	add.l	d2,d2
	add.l	d6,d2
	lsl.l	#2,d2
	move.l	C_FNORM(a6),a1
	add.l	d2,a1
	move.l	(a1),d3				; all three 0 (+-0) -> no cull
	or.l	4(a1),d3
	or.l	8(a1),d3
	add.l	d3,d3
	beq.s	cf_out
	move.w	(a0),d2				; the first corner: 12 bytes
	ext.l	d2
	move.l	d2,d3
	add.l	d3,d3
	add.l	d2,d3
	lsl.l	#2,d3
	move.l	C_FVERT(a6),a2
	add.l	d3,a2
	move.l	d5,d3				; the eye in the block: 12 bytes a block
	add.l	d3,d3
	add.l	d5,d3
	lsl.l	#2,d3
	move.l	C_QEYE(a6),a1
	add.l	d3,a1
	move.l	C_FNORM(a6),d3			; (the normal again)
	move.l	d6,d4
	add.l	d4,d4
	add.l	d6,d4
	lsl.l	#2,d4
	add.l	d4,d3
	exg	d3,a3				; a3 = the normal for the sums (the outcodes' base kept in d3)
	fsmove.s (a2),fp1
	fssub.s	(a1),fp1
	fsmul.s	(a3),fp1
	fsmove.s 4(a2),fp0
	fssub.s	4(a1),fp0
	fsmul.s	4(a3),fp0
	fsadd.x	fp1,fp0
	fsmove.s 8(a2),fp1
	fssub.s	8(a1),fp1
	fsmul.s	8(a3),fp1
	fsadd.x	fp1,fp0
	exg	d3,a3
	ftst.x	fp0
	fbnlt	cf_out
	bra	cf_next				; turned away
cf_out:	btst	#7,d1				; PTF_MIRROR, not PTF_INBLK: C
	bne	cf_ret
	btst	#6,d1
	beq	cf_ret
	move.l	C_BLK(a6),a1			; its corners projected?
	move.l	(a1,d5.l*4),d2
	cmp.l	C_STAMP(a6),d2
	bne	cf_ret
	move.w	(a0),d2				; the outcodes
	ext.l	d2
	move.b	(a3,d2.l),d3
	move.b	d3,d4
	move.w	2(a0),d2
	ext.l	d2
	move.b	(a3,d2.l),d5
	and.b	d5,d3
	or.b	d5,d4
	move.w	4(a0),d2
	ext.l	d2
	move.b	(a3,d2.l),d5
	and.b	d5,d3
	or.b	d5,d4
	move.w	6(a0),d2
	ext.l	d2
	move.b	(a3,d2.l),d5
	and.b	d5,d3
	or.b	d5,d4
	moveq	#3,d5
	and.b	d3,d5
	bne	cf_next
	btst	#0,d4
	bne.s	cf_o2
	moveq	#$3c,d5
	and.b	d3,d5
	bne	cf_next
cf_o2:	moveq	#3,d5
	and.b	d4,d5
	bne	cf_ret
	moveq	#0,d2				; the material noted?
	move.w	20(a0),d2
	lsl.l	#4,d2
	move.l	C_MT(a6),a1
	add.l	d2,a1
	move.l	12(a1),d2
	lsr.l	#8,d2
	cmp.l	C_MTS(a6),d2
	bne	cf_ret
	move.l	C_NPOLY(a6),d2			; room?
	cmp.l	C_MAX(a6),d2
	bge	cf_ret
	move.l	d2,d3
	lsl.l	#7,d3
	lsl.l	#3,d2
	add.l	d3,d2
	move.l	C_BUF(a6),a2
	add.l	d2,a2
	moveq	#0,d5
	move.b	18(a0),d5
	move.b	d5,4(a2)
	btst	#2,d1
	beq.s	cf_tex
	clr.l	(a2)
	move.b	#2,5(a2)
	move.b	22(a0),6(a2)
	bra.s	cf_corn
cf_tex:	move.l	(a1),(a2)
	move.b	15(a1),5(a2)
	clr.b	6(a2)
cf_corn:
	move.l	4(a1),d4
	move.l	8(a1),d6
	addq.l	#8,a2
cf_c:	move.w	(a0)+,d2
	ext.l	d2
	move.l	C_IX(a6),a1
	move.l	(a1,d2.l*4),(a2)+
	move.l	C_IY(a6),a1
	move.l	(a1,d2.l*4),(a2)+
	move.l	C_UV(a6),a1
	lea	(a1,d2.l*4),a1
	move.w	(a1)+,d3
	ext.l	d3
	muls.l	d4,d3
	move.l	d3,(a2)+
	move.w	(a1),d3
	ext.l	d3
	muls.l	d6,d3
	move.l	d3,(a2)+
	subq.l	#1,d5
	bne.s	cf_c
	addq.l	#1,C_NPOLY(a6)
	addq.l	#1,C_COUNT(a6)
cf_next:
	addq.l	#1,d7
	bra	cf_loop
cf_ret:	move.l	d7,d0
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; int pt_ford68k(const pt_octx *c): THE PAINTING ORDER of an object's faces (main.c draw_object_'s pt_ford, the C
; reference): each block's distance from the eye in gcc's single-precision order ((ox + cx) - ex, ((mx^2 + my^2) +
; mz^2), fssqrt, cut to whole), the key and the coarser form (0x8b2fc / 0x8b1d4), a stable insertion sort (the
; furthest first), then each block's list for the side the eye is on copied (or its faces as stored).
; pt_octx: 0 blocks, 4 nb, 8 piece, 12 ex, 16 ey, 20 ez (floats), 24 nblock_all, 28 order, 32 ford, 36 max
; mesh_block (132 bytes): 8 fbase, 12 fcount, 24 ox, 28 oy, 32 oz, 36 cx, 40 cy, 44 cz, 48 name, 52 order_at[17], 120 lod[3]
MB_SIZE	equ	132
OK_KEY	equ	0
OK_USE	equ	160
OK_BO	equ	320
OK_LOC	equ	480
	xdef	_pt_ford68k
	xdef	pt_ford68k
_pt_ford68k:
pt_ford68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp3,-(sp)
	lea	-OK_LOC(sp),sp
	move.l	OK_LOC+24+48(sp),a6		; c
	move.l	(a6),a5				; block 0
	move.l	4(a6),d7			; nb
	moveq	#0,d6				; nu
	moveq	#0,d5				; i
po_blk:	cmp.l	d7,d5
	bge	po_sort
	fsmove.s 24(a5),fp0			; mx = (ox + cx) - ex
	fsadd.l	36(a5),fp0
	fssub.s	12(a6),fp0
	fsmove.s 28(a5),fp1
	fsadd.l	40(a5),fp1
	fssub.s	16(a6),fp1
	fsmove.s 32(a5),fp2
	fsadd.l	44(a5),fp2
	fssub.s	20(a6),fp2
	fsmul.x	fp0,fp0
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fsmul.x	fp2,fp2
	fsadd.x	fp2,fp0
	fssqrt.x fp0,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d0				; d
	tst.l	8(a6)
	beq.s	po_np
	asr.l	#1,d0				; a piece: -(d >> 1) + (name[0] == 'Z' ? $2000 : 0)
	neg.l	d0
	cmp.b	#'Z',48(a5)
	bne.s	po_p1
	add.l	#$2000,d0
po_p1:	move.l	d0,d1				; key
	moveq	#0,d2				; lv: > -6000 -> 0, > -8000 -> 1, else 2
	cmp.l	pi_lodt,d0
	bgt.s	po_lv
	moveq	#1,d2
	cmp.l	pi_lodt+4,d0
	bgt.s	po_lv
	moveq	#2,d2
	bra.s	po_lv
po_np:	neg.l	d0				; the rest: lv from -d (4000 / 7000), the key with the name's exceptions
	moveq	#0,d2
	cmp.l	pi_lodt+8,d0
	bgt.s	po_n1
	moveq	#1,d2
	cmp.l	pi_lodt+12,d0
	bgt.s	po_n1
	moveq	#2,d2
po_n1:	move.l	d0,d1
	move.b	48(a5),d3
	cmp.b	#'A',d3
	beq.s	po_lv
	cmp.b	#'a',d3
	beq.s	po_lv
	tst.b	51(a5)
	bne.s	po_lv
	move.b	50(a5),d3
	cmp.b	#'i',d3
	bne.s	po_n2
	sub.l	#4000,d1
	bra.s	po_lv
po_n2:	cmp.b	#'x',d3
	bne.s	po_lv
	sub.l	#1000,d1
po_lv:	move.l	120(a5,d2.l*4),d0		; drawn = lod[lv]
	bmi.s	po_nx
	cmp.l	24(a6),d0
	bge.s	po_nx
	move.l	d1,OK_KEY(sp,d6.l*4)
	move.l	d0,OK_USE(sp,d6.l*4)
	move.l	d6,OK_BO(sp,d6.l*4)
	addq.l	#1,d6
po_nx:	lea	MB_SIZE(a5),a5
	addq.l	#1,d5
	bra	po_blk
po_sort:					; insertion: while key[bo[j-1]] > key[bo[j]] swap
	moveq	#1,d5
po_si:	cmp.l	d6,d5
	bge.s	po_emit
	move.l	d5,d4				; j
po_sj:	tst.l	d4
	ble.s	po_sn
	move.l	OK_BO-4(sp,d4.l*4),d0		; bo[j-1]
	move.l	OK_BO(sp,d4.l*4),d1		; bo[j]
	move.l	OK_KEY(sp,d0.l*4),d2
	cmp.l	OK_KEY(sp,d1.l*4),d2
	ble.s	po_sn
	move.l	d0,OK_BO(sp,d4.l*4)
	move.l	d1,OK_BO-4(sp,d4.l*4)
	subq.l	#1,d4
	bra.s	po_sj
po_sn:	addq.l	#1,d5
	bra.s	po_si
po_emit:
	move.l	32(a6),a3			; ford
	moveq	#0,d7				; n
	move.l	36(a6),d4			; max
	moveq	#0,d5				; i
po_ei:	cmp.l	d6,d5
	bge	po_out
	move.l	OK_BO(sp,d5.l*4),d0
	move.l	OK_USE(sp,d0.l*4),d0		; the block drawn
	mulu.l	#MB_SIZE,d0
	move.l	(a6),a5
	add.l	d0,a5
	fsmove.s 12(a6),fp0			; the eye from the block: x, y, z
	fssub.s	24(a5),fp0
	fsmove.s 16(a6),fp1
	fssub.s	28(a5),fp1
	fsmove.s 20(a6),fp2
	fssub.s	32(a5),fp2
	moveq	#0,d0				; row: y < 0 -> 8
	ftst.x	fp1
	fbnlt	po_y
	moveq	#8,d0
po_y:	ftst.x	fp0
	fbnge	po_xn
	ftst.x	fp2				; x >= 0: z >= 0 ? (z > x ? 0 : 1) : (-z <= x ? 2 : 3)
	fbnge	po_x2
	fcmp.x	fp0,fp2
	fbgt	po_row
	addq.l	#1,d0
	bra.s	po_row
po_x2:	fneg.x	fp2,fp3
	fcmp.x	fp0,fp3
	fble	po_x3
	addq.l	#3,d0
	bra.s	po_row
po_x3:	addq.l	#2,d0
	bra.s	po_row
po_xn:	fneg.x	fp0,fp1				; x < 0 (-x in fp1): z < 0 ? (-z > -x ? 4 : 5) : (z <= -x ? 6 : 7)
	ftst.x	fp2
	fbnlt	po_x6
	fneg.x	fp2,fp3
	fcmp.x	fp1,fp3
	fbngt	po_x5
	addq.l	#4,d0
	bra.s	po_row
po_x5:	addq.l	#5,d0
	bra.s	po_row
po_x6:	fcmp.x	fp1,fp2
	fbnle	po_x7
	addq.l	#6,d0
	bra.s	po_row
po_x7:	addq.l	#7,d0
po_row:	move.l	52(a5,d0.l*4),d1		; from
	move.l	56(a5,d0.l*4),d2		; to
	cmp.l	d1,d2
	bne.s	po_list
	move.l	8(a5),d1			; no list: the faces as stored
	move.l	12(a5),d2
	bra.s	po_fe
po_fl:	cmp.l	d4,d7
	bge.s	po_en
	move.w	d1,(a3)+
	addq.l	#1,d1
	addq.l	#1,d7
po_fe:	subq.l	#1,d2
	bpl.s	po_fl
	bra.s	po_en
po_list:
	move.l	28(a6),a0
	lea	(a0,d1.l*2),a0
	sub.l	d1,d2				; to - from
	bra.s	po_le
po_ll:	cmp.l	d4,d7
	bge.s	po_en
	move.w	(a0)+,(a3)+
	addq.l	#1,d7
po_le:	subq.l	#1,d2
	bpl.s	po_ll
po_en:	addq.l	#1,d5
	bra	po_ei
po_out:	move.l	d7,d0
	lea	OK_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp3
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; int pt_near68k(const pt_nctx *c): the pieces near enough to look at (main.c render_scene's test, gcc's order:
; ((dx^2 + dy^2) + dz^2) > ((r + drawdist)^2) * 1.001f -> not), their numbers in order into c->list.
; pt_nctx: 0 near_at (x y z r floats, 16 bytes a piece), 4 n, 8 cam x, 12 y, 16 z, 20 drawdist, 24 list
	xdef	_pt_near68k
	xdef	pt_near68k
_pt_near68k:
pt_near68k:
	movem.l	d2-d3/a2,-(sp)
	fmovem.x fp2-fp3,-(sp)
	move.l	12+24+4(sp),a2			; c
	move.l	(a2),a0				; near_at
	move.l	24(a2),a1			; list
	move.l	4(a2),d2			; n
	moveq	#0,d0				; o
	moveq	#0,d1				; found
	bra.s	pn_e
pn_l:	fsmove.s (a0)+,fp0			; dx
	fssub.s	8(a2),fp0
	fsmove.s (a0)+,fp3			; dy
	fssub.s	12(a2),fp3
	fsmove.s (a0)+,fp2			; dz
	fssub.s	16(a2),fp2
	fsmove.s (a0)+,fp1			; lim = r + drawdist
	fsadd.s	20(a2),fp1
	fsmul.x	fp0,fp0
	fsmul.x	fp3,fp3
	fsadd.x	fp3,fp0
	fsmul.x	fp2,fp2
	fsadd.x	fp2,fp0
	fsmul.x	fp1,fp1
	fsmul.s	pn_k(pc),fp1			; 1.001f (its bits)
	fcmp.x	fp1,fp0
	fbgt	pn_n
	move.l	d0,(a1)+
	addq.l	#1,d1
pn_n:	addq.l	#1,d0
pn_e:	cmp.l	d2,d0
	blt.s	pn_l
	move.l	d1,d0
	fmovem.x (sp)+,fp2-fp3
	movem.l	(sp)+,d2-d3/a2
	rts
	cnop	0,4
pn_k:	dc.l	$3f8020c5

; int pt_pro68k(pt_pctx *c): an object's first tests (main.c draw_object_'s prologue, the C reference): the phases,
; the distance (((dx^2 + dy^2) + dz^2) > (drawdist + r)^2 -> 0), the pass, the notes by id, its middle in view space
; (to_view), behind the eye / beyond the far plane / off the side (sqrtf(x^2 + y^2) - r > (z + r) 1.7f) -> 0;
; 1: drawn on (dx dy dz, the middle in view space in c->out), 2: the C prologue (has[id] not known yet).
; pt_pctx: 0 so, 4 id, 8 pass, 12 sorted, 16 cam, 20 &drawdist, 24 has, 28 hasn, 32 d2, 36 d2n, 40 carpet, 44 ground,
; 48 &ground_now, 52 &g_cam, 56 &vc, 60 &vs, 64 &vcp, 68 &vsp, 72 &vcr, 76 &vsr, 80 &far_z, 84 &eye_h, 88 &ground_vy,
; 92 &obj_eye_h, 96 &tex_phase, 100 &anim_clock, 104 &zbias, 108 &sprite, 112 &over, 116 &env_phase, 120 out[6]
; scene_object: 0 m, 4 pose, 12 zbias, 16 over, 20 sprite, 24 x, 28 y, 32 z, 48 radius, 72 phase; car_pose 28 env;
; mesh 50 carpet
	xdef	_pt_pro68k
	xdef	pt_pro68k
_pt_pro68k:
pt_pro68k:
	movem.l	d2-d3/a2-a3,-(sp)
	fmovem.x fp2-fp4,-(sp)
	move.l	16+36+4(sp),a0			; c
	move.l	(a0),a1				; so
	move.l	16(a0),a2			; cam
	move.l	72(a1),d0			; the textures' phase
	bpl.s	pp_ph
	move.l	100(a0),a3
	move.l	(a3),d0
	and.l	#$3fff,d0
	bra.s	pp_ph2
pp_ph:	asr.l	#2,d0
	and.l	#$3fff,d0
pp_ph2:	move.l	96(a0),a3
	move.l	d0,(a3)
	move.l	104(a0),a3			; zbias: > 0 ? it : 1
	fmove.s	12(a1),fp0
	ftst.x	fp0
	fbgt	pp_zb
	fmove.s	pp_one(pc),fp0
pp_zb:	fmove.s	fp0,(a3)
	move.l	108(a0),a3
	move.l	20(a1),(a3)			; sprite
	move.l	112(a0),a3
	move.l	16(a1),(a3)			; over
	moveq	#0,d0				; env phase
	move.l	4(a1),d1
	beq.s	pp_env
	move.l	d1,a3
	move.l	28(a3),d0
pp_env:	move.l	116(a0),a3
	move.l	d0,(a3)
	fsmove.s 24(a1),fp0			; dx dy dz
	fssub.s	(a2),fp0
	fsmove.s 28(a1),fp1
	fssub.s	4(a2),fp1
	fsmove.s 32(a1),fp2
	fssub.s	8(a2),fp2
	fmove.s	fp0,120(a0)
	fmove.s	fp1,124(a0)
	fmove.s	fp2,128(a0)
	fsmul.x	fp0,fp0				; d2 = (dx^2 + dy^2) + dz^2
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fsmul.x	fp2,fp2
	fsadd.x	fp2,fp0
	move.l	20(a0),a3			; lim = drawdist + r
	fsmove.s (a3),fp1
	fsadd.s	48(a1),fp1
	fsmul.x	fp1,fp1
	fcmp.x	fp1,fp0
	fbgt	pp_out0
	tst.l	12(a0)				; sorted: the pass's faces known?
	beq.s	pp_d2
	move.l	4(a0),d1
	move.l	24(a0),a3
	moveq	#0,d2
	move.b	(a3,d1.l),d2
	beq	pp_out2				; (not known yet: the C prologue)
	moveq	#2,d3
	cmp.l	#1,8(a0)
	bne.s	pp_s1
	moveq	#4,d3
pp_s1:	and.l	d2,d3
	bne.s	pp_d2
	cmp.l	#1,8(a0)
	beq	pp_out0
pp_d2:	move.l	4(a0),d1			; the notes by id
	bmi.s	pp_tv
	cmp.l	36(a0),d1
	bge.s	pp_tv
	move.l	32(a0),a3
	fmove.s	fp0,(a3,d1.l*4)
	moveq	#0,d2				; carpet: mm && mm->carpet
	move.l	(a1),d3
	beq.s	pp_cp
	move.l	d3,a3
	tst.l	50(a3)
	beq.s	pp_cp
	moveq	#1,d2
pp_cp:	move.l	40(a0),a3
	move.b	d2,(a3,d1.l)
	move.l	48(a0),a3
	move.l	(a3),d2
	move.l	44(a0),a3
	move.b	d2,(a3,d1.l)
pp_tv:	move.l	52(a0),a3			; to_view(so's x y z): d = w - g_cam
	fsmove.s 24(a1),fp0
	fssub.s	(a3),fp0
	fsmove.s 28(a1),fp1
	fssub.s	4(a3),fp1
	fsmove.s 32(a1),fp2
	fssub.s	8(a3),fp2
	move.l	56(a0),a3			; fx = vc dx + vs dy
	fsmove.s (a3),fp3
	fsmul.x	fp0,fp3
	move.l	60(a0),a3
	fsmove.s (a3),fp4
	fsmul.x	fp1,fp4
	fsadd.x	fp4,fp3				; fp3 = fx
	fsmove.s (a3),fp4			; x = vs dx - vc dy
	fsmul.x	fp0,fp4
	move.l	56(a0),a3
	fsmove.s (a3),fp0
	fsmul.x	fp1,fp0
	fssub.x	fp0,fp4				; fp4 = x
	move.l	64(a0),a3			; y = vcp dz - vsp fx
	fsmove.s (a3),fp0
	fsmul.x	fp2,fp0
	move.l	68(a0),a3
	fsmove.s (a3),fp1
	fsmul.x	fp3,fp1
	fssub.x	fp1,fp0				; fp0 = y
	move.l	72(a0),a2			; (a2: &vcr, a3: &vsr)
	move.l	76(a0),a3
	fsmove.s (a2),fp1			; ox = x vcr + y vsr
	fsmul.x	fp4,fp1
	fmove.x	fp0,-(sp)
	fsmul.s	(a3),fp0
	fsadd.x	fp0,fp1
	fmove.s	fp1,132(a0)
	fmove.x	(sp)+,fp0
	fsmove.s (a2),fp1			; oy = y vcr - x vsr
	fsmul.x	fp0,fp1
	fsmove.s (a3),fp0
	fsmul.x	fp4,fp0
	fssub.x	fp0,fp1
	fmove.s	fp1,136(a0)
	move.l	68(a0),a3			; oz = vsp dz + vcp fx
	fsmove.s (a3),fp0
	fsmul.x	fp2,fp0
	move.l	64(a0),a3
	fsmove.s (a3),fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,140(a0)
	move.l	16(a0),a2			; (cam again)
	fsmove.s 48(a1),fp1			; behind: z < -r
	fneg.x	fp1
	fcmp.x	fp1,fp0
	fblt	pp_out0
	move.l	80(a0),a3			; beyond the far plane: far > 0 && z - r > far
	fsmove.s (a3),fp1
	ftst.x	fp1
	fbngt	pp_gv
	fsmove.x fp0,fp2
	fssub.s	48(a1),fp2
	fcmp.x	fp1,fp2
	fbgt	pp_out0
pp_gv:	move.l	88(a0),a3			; ground_vy = vc.y
	move.l	136(a0),(a3)
	tst.l	16(a1)				; over: eye_h = min(cam.z - so.z, g_eye_h), at least 60
	beq.s	pp_side
	fsmove.s 8(a2),fp1
	fssub.s	32(a1),fp1
	move.l	84(a0),a3
	fsmove.s (a3),fp2
	fcmp.x	fp2,fp1
	fblt	pp_e1
	fmove.x	fp2,fp1
pp_e1:	fcmp.s	pp_k60(pc),fp1
	fbnlt	pp_e2
	fmove.s	pp_k60(pc),fp1
pp_e2:	move.l	92(a0),a3
	fmove.s	fp1,(a3)
pp_side:					; off the side: sqrtf(x^2 + y^2) - r > (z + r) 1.7f
	fsmove.s 132(a0),fp1
	fsmul.x	fp1,fp1
	fsmove.s 136(a0),fp2
	fsmul.x	fp2,fp2
	fsadd.x	fp2,fp1
	fssqrt.x fp1,fp1
	fssub.s	48(a1),fp1
	fsmove.x fp0,fp2
	fsadd.s	48(a1),fp2
	fsmul.s	pp_k17(pc),fp2
	fcmp.x	fp2,fp1
	fbgt	pp_out0
	tst.l	12(a0)				; sorted, pass 0 and no solid face: nothing
	beq.s	pp_out1
	tst.l	8(a0)
	bne.s	pp_out1
	move.l	4(a0),d1
	move.l	24(a0),a3
	btst	#1,(a3,d1.l)
	beq.s	pp_out0
pp_out1:
	moveq	#1,d0
	bra.s	pp_ret
pp_out2:
	moveq	#2,d0
	bra.s	pp_ret
pp_out0:
	moveq	#0,d0
pp_ret:	fmovem.x (sp)+,fp2-fp4
	movem.l	(sp)+,d2-d3/a2-a3
	rts
	cnop	0,4
pp_one:	dc.l	$3f800000			; 1.0f
pp_k60:	dc.l	$42700000			; 60.0f
pp_k17:	dc.l	$3fd9999a			; 1.7f
