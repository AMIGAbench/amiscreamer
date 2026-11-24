; pi_68k.s - THE TRACK'S PIECES IN WHOLE NUMBERS (main.c pi_draw; the C references pi_pre_c and pi_ford_c, the
; same arithmetic step for step; OS_PIASM=c runs both and compares).  The geometry:
; no floating point from a piece's record to its faces.
;   pi_pre68k:  the distance, the sphere against the near, far and four side planes, the place in view space,
;               the eye in the piece's frame, the turn (camera x heading, 2.14), the sort key
;   pi_ford68k: the blocks' painting order (whole-number square roots, LOD, the side's face list)
; 68020+ (muls.l 32x32->32 only: no 64-bit forms, a 68060 has none).  vasmm68k_mot -quiet -no-opt -m68060

; pi_rec (32 bytes a piece)
PR_X	equ	0
PR_Y	equ	4
PR_Z	equ	8
PR_C	equ	12
PR_S	equ	14
PR_R	equ	16
; pi_cb_t (the picture's camera and lens)
CB_CAM	equ	0
CB_CM	equ	12
CB_FX	equ	48
CB_HW	equ	52
CB_CY	equ	56
CB_CYB	equ	60
CB_FAR	equ	64
CB_LX	equ	68
CB_LT	equ	72
CB_LB	equ	76
CB_DD	equ	80
; pi_pctx
PP_REC	equ	0
PP_CB	equ	4
PP_D2	equ	8
PP_V	equ	12
PP_E	equ	24
PP_R	equ	36
PP_KEY	equ	56

	section	code,code
pi_code0:
	xref	pt_faces_68k
	xref	pt_cfaces_68k

; d0 = floor(sqrt(d0)), unsigned (d1-d2 used; fp0 kept): the FPU's root cut to a whole number, then put right with
; whole numbers until r^2 <= v < (r + 1)^2 -- the floor of the root exactly, whatever the FPU's precision (as
; pi_isqrt in main.c; before: Newton from above with a divu.l a step, ~200 cycles a root)
pi_isqrt:
	tst.l	d0
	beq.s	pq_0
	fmove.x	fp0,-(sp)
	fmove.l	d0,fp0
	tst.l	d0
	bpl.s	pq_p
	fadd.d	#4294967296.0,fp0		; (unsigned)
pq_p:	fsqrt.x	fp0,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d1
	fmove.x	(sp)+,fp0
	cmp.l	#65535,d1
	bls.s	pq_dn
	move.l	#65535,d1
pq_dn:	move.l	d1,d2				; r^2 > v: one less
	mulu.l	d1,d2
	cmp.l	d0,d2
	bls.s	pq_up
	subq.l	#1,d1
	bra.s	pq_dn
pq_up:	cmp.l	#65535,d1			; (r + 1)^2 <= v: one more
	bhs.s	pq_d
	move.l	d1,d2
	addq.l	#1,d2
	mulu.l	d2,d2
	cmp.l	d0,d2
	bhi.s	pq_d
	addq.l	#1,d1
	bra.s	pq_up
pq_d:	move.l	d1,d0
pq_0:	rts

; |\1| into \2 (data registers), then \2 >= 65536 -> \3
PABS	macro
	move.l	\1,\2
	bpl.s	.p\@
	neg.l	\2
.p\@:	cmp.l	#65536,\2
	bhs	\3
	endm

	xdef	_pi_pre68k
	xdef	pi_pre68k
; int pi_pre68k(pi_pctx *p): 0 beyond the draw distance, 1 out of the picture, 2 to be drawn
_pi_pre68k:
pi_pre68k:
	movem.l	d2-d7/a2-a3,-(sp)
	move.l	36(sp),a0			; p
	move.l	PP_REC(a0),a1
	move.l	PP_CB(a0),a2
	move.l	PR_X(a1),d5			; dx dy dz in d5 d6 d7
	sub.l	CB_CAM+0(a2),d5
	move.l	PR_Y(a1),d6
	sub.l	CB_CAM+4(a2),d6
	move.l	PR_Z(a1),d7
	sub.l	CB_CAM+8(a2),d7
	PABS	d5,d0,pp_0
	PABS	d6,d1,pp_0
	PABS	d7,d2,pp_0
	lsr.l	#2,d0				; (|d| >> 2)^2, summed: (the distance / 4)^2
	lsr.l	#2,d1
	lsr.l	#2,d2
	mulu.w	d0,d0
	mulu.w	d1,d1
	mulu.w	d2,d2
	add.l	d1,d0
	add.l	d2,d0
	move.l	CB_DD(a2),d1			; lim = (dd + r) >> 2, squared
	add.l	PR_R(a1),d1
	lsr.l	#2,d1
	mulu.l	d1,d1
	cmp.l	d1,d0
	bhi	pp_0
	move.l	d0,PP_D2(a0)
	; the place in view space: v[b] = (cm[3b] dx + cm[3b+1] dy + cm[3b+2] dz) >> 14
	lea	CB_CM(a2),a3
	lea	PP_V(a0),a1
	moveq	#14,d4
	moveq	#2,d3
pp_v:	move.l	(a3)+,d0
	muls.l	d5,d0
	move.l	(a3)+,d1
	muls.l	d6,d1
	add.l	d1,d0
	move.l	(a3)+,d1
	muls.l	d7,d1
	add.l	d1,d0
	asr.l	d4,d0
	move.l	d0,(a1)+
	dbra	d3,pp_v
	move.l	PP_REC(a0),a1
	move.l	PR_R(a1),d3			; rr
	move.l	PP_V+8(a0),d2			; vz
	move.l	d3,d0
	neg.l	d0
	cmp.l	d0,d2				; vz < -rr: behind
	blt	pp_1
	move.l	CB_FAR(a2),d1
	beq.s	pp_nf
	move.l	d2,d0
	sub.l	d3,d0
	cmp.l	d1,d0				; vz - rr > far
	bgt	pp_1
pp_nf:	move.l	PP_V(a0),d0			; |vx fx| - vz hw > rr lx
	muls.l	CB_FX(a2),d0
	bpl.s	pp_ax
	neg.l	d0
pp_ax:	move.l	d2,d1
	muls.l	CB_HW(a2),d1
	sub.l	d1,d0
	move.l	d3,d1
	muls.l	CB_LX(a2),d1
	cmp.l	d1,d0
	bgt	pp_1
	move.l	PP_V+4(a0),d4			; ay = vy fx
	muls.l	CB_FX(a2),d4
	move.l	d4,d0				; ay - vz cy > rr lt
	move.l	d2,d1
	muls.l	CB_CY(a2),d1
	sub.l	d1,d0
	move.l	d3,d1
	muls.l	CB_LT(a2),d1
	cmp.l	d1,d0
	bgt	pp_1
	move.l	d4,d0				; -ay - vz cyb > rr lb
	neg.l	d0
	move.l	d2,d1
	muls.l	CB_CYB(a2),d1
	sub.l	d1,d0
	move.l	d3,d1
	muls.l	CB_LB(a2),d1
	cmp.l	d1,d0
	bgt	pp_1
	move.l	PP_D2(a0),d0			; the key: (the distance / 4)
	bsr	pi_isqrt
	move.l	d0,PP_KEY(a0)
	; the eye in the piece's frame: E0 = -((c dx + s dy) >> 14), E1 = -dz, E2 = -((c dy - s dx) >> 14)
	move.w	PR_C(a1),d2
	ext.l	d2				; c
	move.w	PR_S(a1),d3
	ext.l	d3				; s
	moveq	#14,d4
	move.l	d2,d0
	muls.l	d5,d0
	move.l	d3,d1
	muls.l	d6,d1
	add.l	d1,d0
	asr.l	d4,d0
	neg.l	d0
	move.l	d0,PP_E(a0)
	neg.l	d7
	move.l	d7,PP_E+4(a0)
	move.l	d2,d0
	muls.l	d6,d0
	move.l	d3,d1
	muls.l	d5,d1
	sub.l	d1,d0
	asr.l	d4,d0
	neg.l	d0
	move.l	d0,PP_E+8(a0)
	; the turn: R[b] = (c m0 + s m1) >> 14, R[3+b] = m2, R[6+b] = (c m1 - s m0) >> 14 (m = camera row b)
	lea	CB_CM(a2),a3
	lea	PP_R(a0),a1
	moveq	#2,d7
pp_r:	move.w	2(a3),d5			; m0 (the low word: |m| <= 16384)
	move.w	6(a3),d6			; m1
	move.w	d5,d0
	muls.w	d2,d0
	move.w	d6,d1
	muls.w	d3,d1
	add.l	d1,d0
	asr.l	d4,d0
	move.w	d0,(a1)
	move.w	10(a3),6(a1)			; m2
	move.w	d6,d0
	muls.w	d2,d0
	move.w	d5,d1
	muls.w	d3,d1
	sub.l	d1,d0
	asr.l	d4,d0
	move.w	d0,12(a1)
	lea	12(a3),a3
	addq.l	#2,a1
	dbra	d7,pp_r
	moveq	#2,d0
	bra.s	pp_out
pp_1:	moveq	#1,d0
	bra.s	pp_out
pp_0:	moveq	#0,d0
pp_out:	movem.l	(sp)+,d2-d7/a2-a3
	rts

; int pi_ford68k(const pi_octx *c): a piece's faces in painting order (pi_ford_c)
; pi_octx: 0 blocks, 4 nb, 8 iblk (8 words a block: middle x y z, place x y z), 12 E0, 16 E1, 20 E2,
; 24 nblock_all, 28 order, 32 ford, 36 max, 40 piece (else a car's or prop's keys)
; mesh_block (132 bytes): 8 fbase, 12 fcount, 48 name, 52 order_at[17], 120 lod[3]
MB_SIZE	equ	132
OK_KEY	equ	0
OK_USE	equ	160
OK_BO	equ	320
OK_LOC	equ	480
	xdef	_pi_ford68k
	xdef	pi_ford68k
_pi_ford68k:
pi_ford68k:
	movem.l	d2-d7/a2-a6,-(sp)
	lea	-OK_LOC(sp),sp
	move.l	OK_LOC+48(sp),a6		; c
	move.l	(a6),a5				; block 0
	move.l	8(a6),a4			; iblk
	move.l	4(a6),d7			; nb
	moveq	#0,d6				; nu
	moveq	#0,d5				; i
fo_blk:	cmp.l	d7,d5
	bge	fo_sort
	move.l	(a4),d0				; |middle - E|
	sub.l	12(a6),d0
	bpl.s	fo_a0
	neg.l	d0
fo_a0:	move.l	4(a4),d1
	sub.l	16(a6),d1
	bpl.s	fo_a1
	neg.l	d1
fo_a1:	move.l	8(a4),d2
	sub.l	20(a6),d2
	bpl.s	fo_a2
	neg.l	d2
fo_a2:	move.l	d0,d3
	or.l	d1,d3
	or.l	d2,d3
	cmp.l	#32768,d3
	bhs.s	fo_far
	mulu.w	d0,d0				; all under 32768: exact
	mulu.w	d1,d1
	mulu.w	d2,d2
	add.l	d1,d0
	add.l	d2,d0
	bsr	pi_isqrt
	bra.s	fo_d
fo_far:	lsr.l	#2,d0				; (|m| >> 2), each <= 26000, squared and summed
	lsr.l	#2,d1
	lsr.l	#2,d2
	cmp.l	#26000,d0
	bhi	fo_nx
	cmp.l	#26000,d1
	bhi	fo_nx
	cmp.l	#26000,d2
	bhi	fo_nx
	mulu.w	d0,d0
	mulu.w	d1,d1
	mulu.w	d2,d2
	add.l	d1,d0
	add.l	d2,d0
	bsr	pi_isqrt
	lsl.l	#2,d0
fo_d:					; d
	tst.l	40(a6)				; a piece?
	beq.s	fo_np
	asr.l	#1,d0				; key = -(d >> 1) + (name[0] == 'Z' ? $2000 : 0)
	neg.l	d0
	cmp.b	#'Z',48(a5)
	bne.s	fo_p1
	add.l	#$2000,d0
fo_p1:	move.l	d0,d1
	moveq	#0,d2				; lv: > -6000 -> 0, > -8000 -> 1, else 2 (pi_lodt: 320x200 the half)
	cmp.l	pi_lodt,d0
	bgt.s	fo_lv
	moveq	#1,d2
	cmp.l	pi_lodt+4,d0
	bgt.s	fo_lv
	moveq	#2,d2
	bra.s	fo_lv
fo_np:	neg.l	d0				; a car or prop: lv from -d (4000 / 7000), the key with the name's exceptions
	moveq	#0,d2
	cmp.l	pi_lodt+8,d0
	bgt.s	fo_n1
	moveq	#1,d2
	cmp.l	pi_lodt+12,d0
	bgt.s	fo_n1
	moveq	#2,d2
fo_n1:	move.l	d0,d1
	move.b	48(a5),d3
	cmp.b	#'A',d3
	beq.s	fo_lv
	cmp.b	#'a',d3
	beq.s	fo_lv
	tst.b	51(a5)
	bne.s	fo_lv
	move.b	50(a5),d3
	cmp.b	#'i',d3
	bne.s	fo_n2
	sub.l	#4000,d1
	bra.s	fo_lv
fo_n2:	cmp.b	#'x',d3
	bne.s	fo_lv
	sub.l	#1000,d1
fo_lv:	move.l	120(a5,d2.l*4),d0		; drawn = lod[lv]
	bmi.s	fo_nx
	cmp.l	24(a6),d0
	bge.s	fo_nx
	move.l	d1,OK_KEY(sp,d6.l*4)
	move.l	d0,OK_USE(sp,d6.l*4)
	move.l	d6,OK_BO(sp,d6.l*4)
	addq.l	#1,d6
fo_nx:	lea	MB_SIZE(a5),a5
	lea	32(a4),a4
	addq.l	#1,d5
	bra	fo_blk
fo_sort:					; insertion: while key[bo[j-1]] > key[bo[j]] swap
	moveq	#1,d5
fo_si:	cmp.l	d6,d5
	bge.s	fo_emit
	move.l	d5,d4				; j
fo_sj:	tst.l	d4
	ble.s	fo_sn
	move.l	OK_BO-4(sp,d4.l*4),d0		; bo[j-1]
	move.l	OK_BO(sp,d4.l*4),d1		; bo[j]
	move.l	OK_KEY(sp,d0.l*4),d2
	cmp.l	OK_KEY(sp,d1.l*4),d2
	ble.s	fo_sn
	move.l	d0,OK_BO(sp,d4.l*4)
	move.l	d1,OK_BO-4(sp,d4.l*4)
	subq.l	#1,d4
	bra.s	fo_sj
fo_sn:	addq.l	#1,d5
	bra.s	fo_si
fo_emit:
	move.l	32(a6),a3			; ford
	moveq	#0,d7				; n
	move.l	36(a6),d4			; max
	moveq	#0,d5				; i
fo_ei:	cmp.l	d6,d5
	bge	fo_out
	move.l	OK_BO(sp,d5.l*4),d0
	move.l	OK_USE(sp,d0.l*4),d0		; the block drawn
	move.l	d0,d1
	lsl.l	#5,d1
	move.l	8(a6),a4
	add.l	d1,a4				; its whole numbers
	mulu.l	#MB_SIZE,d0
	move.l	(a6),a5
	add.l	d0,a5
	move.l	12(a6),d1			; the eye from the block: x y z in d1 d2 d3
	sub.l	12(a4),d1
	move.l	16(a6),d2
	sub.l	16(a4),d2
	move.l	20(a6),d3
	sub.l	20(a4),d3
	moveq	#0,d0				; row: y < 0 -> 8
	tst.l	d2
	bpl.s	fo_y
	moveq	#8,d0
fo_y:	tst.l	d1
	bmi.s	fo_xn
	tst.l	d3				; x >= 0: z >= 0 ? (z > x ? 0 : 1) : (-z <= x ? 2 : 3)
	bmi.s	fo_x2
	cmp.l	d1,d3
	bgt.s	fo_row
	addq.l	#1,d0
	bra.s	fo_row
fo_x2:	neg.l	d3
	cmp.l	d1,d3
	ble.s	fo_x3
	addq.l	#3,d0
	bra.s	fo_row
fo_x3:	addq.l	#2,d0
	bra.s	fo_row
fo_xn:	neg.l	d1				; x < 0 (-x in d1): z < 0 ? (-z > -x ? 4 : 5) : (z <= -x ? 6 : 7)
	tst.l	d3
	bpl.s	fo_x6
	neg.l	d3
	cmp.l	d1,d3
	ble.s	fo_x5
	addq.l	#4,d0
	bra.s	fo_row
fo_x5:	addq.l	#5,d0
	bra.s	fo_row
fo_x6:	cmp.l	d1,d3
	bgt.s	fo_x7
	addq.l	#6,d0
	bra.s	fo_row
fo_x7:	addq.l	#7,d0
fo_row:	move.l	52(a5,d0.l*4),d1		; from
	move.l	56(a5,d0.l*4),d2		; to
	cmp.l	d1,d2
	bne.s	fo_list
	move.l	8(a5),d1			; no list: the faces as stored
	move.l	12(a5),d2
	bra.s	fo_fe
fo_fl:	cmp.l	d4,d7
	bge.s	fo_en
	move.w	d1,(a3)+
	addq.l	#1,d1
	addq.l	#1,d7
fo_fe:	subq.l	#1,d2
	bpl.s	fo_fl
	bra.s	fo_en
fo_list:
	move.l	28(a6),a0
	lea	(a0,d1.l*2),a0
	sub.l	d1,d2				; to - from
	bra.s	fo_le
fo_ll:	cmp.l	d4,d7
	bge.s	fo_en
	move.w	(a0)+,(a3)+
	addq.l	#1,d7
fo_le:	subq.l	#1,d2
	bpl.s	fo_ll
fo_en:	addq.l	#1,d5
	bra	fo_ei
fo_out:	move.l	d7,d0
	lea	OK_LOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; int pi_near68k(const pi_nctx *c): the pieces near enough to look at, in whole numbers (main.c pi_near_c, the
; reference): (|d| >> 2)^2 summed against ((dd + r) >> 2)^2, the records side by side (16 bytes: x y z r);
; a piece whose reach is 65536 or more always listed.  pi_nctx: 0 recs, 4 n, 8 cam x, 12 y, 16 z, 20 dd, 24 list
	xdef	_pi_near68k
	xdef	pi_near68k
_pi_near68k:
pi_near68k:
	movem.l	d2-d7/a2-a4,-(sp)
	move.l	40(sp),a4			; c
	move.l	(a4),a0				; records
	move.l	24(a4),a1			; list
	move.l	4(a4),d7			; n
	move.l	20(a4),a3			; dd
	moveq	#0,d6				; o
	bra	pn_e
pn_l:	movem.l	(a0)+,d0-d3			; x y z r
	add.l	a3,d3				; lim = dd + r
	cmp.l	#65536,d3
	bhs.s	pn_take
	sub.l	8(a4),d0
	bpl.s	pn_a0
	neg.l	d0
pn_a0:	cmp.l	#65536,d0
	bhs.s	pn_nx
	sub.l	12(a4),d1
	bpl.s	pn_a1
	neg.l	d1
pn_a1:	cmp.l	#65536,d1
	bhs.s	pn_nx
	sub.l	16(a4),d2
	bpl.s	pn_a2
	neg.l	d2
pn_a2:	cmp.l	#65536,d2
	bhs.s	pn_nx
	lsr.l	#2,d0
	lsr.l	#2,d1
	lsr.l	#2,d2
	lsr.l	#2,d3
	mulu.w	d0,d0
	mulu.w	d1,d1
	mulu.w	d2,d2
	mulu.w	d3,d3
	add.l	d1,d0
	add.l	d2,d0
	cmp.l	d3,d0
	bhi.s	pn_nx
pn_take:
	move.l	d6,(a1)+
pn_nx:	addq.l	#1,d6
pn_e:	cmp.l	d7,d6
	blt	pn_l
	move.l	a1,d0
	sub.l	24(a4),d0
	asr.l	#2,d0
	movem.l	(sp)+,d2-d7/a2-a4
	rts

; void ci_block68k(const ci_obj *ob, const int32_t *io, int32_t flags, int16_t R[9], int32_t T[3], int32_t E[3]):
; a car's or prop's block (main.c ci_block, the reference): the wheel's spin and steer about its place, or the
; body's lean and drop (A, t); R = O after A (2.14), T = T0 + O t, the eye in the block's frame E = -(R^T T).
; ci_obj: 0 O[3][3], 36 T0[3], 48 wc, 52 ws, 56 sc, 60 ss, 64 bpc, 68 bps, 72 brc, 76 brs, 80 drop, 84 body, 96 pose
; io: mesh.iblk's 8 words (12 16 20: the block's place x y z); flags: the block's (0x800 the hub)
CO_T0	equ	36
CO_WC	equ	48
CO_WS	equ	52
CO_SC	equ	56
CO_SS	equ	60
CO_BPC	equ	64
CO_BPS	equ	68
CO_BRC	equ	72
CO_BRS	equ	76
CO_DROP	equ	80
CO_BODY	equ	84
CO_POSE	equ	96
CB_A	equ	0				; locals: A[3][3], t[3], M[3][3]
CB_TT	equ	36
CB_M	equ	48
CB_LOC	equ	84
	xdef	_ci_block68k
	xdef	ci_block68k
_ci_block68k:
ci_block68k:
	movem.l	d2-d7/a2-a6,-(sp)
	lea	-CB_LOC(sp),sp
	move.l	CB_LOC+48(sp),a6		; ob
	move.l	CB_LOC+52(sp),a5		; io
	move.l	CB_LOC+56(sp),d7		; flags
	move.l	CB_LOC+64(sp),a3		; T
	move.l	CB_LOC+68(sp),a2		; E
	moveq	#14,d5
	move.l	#16384,d0			; A = 1, t = 0
	moveq	#0,d1
	move.l	d0,CB_A+0(sp)
	move.l	d1,CB_A+4(sp)
	move.l	d1,CB_A+8(sp)
	move.l	d1,CB_A+12(sp)
	move.l	d0,CB_A+16(sp)
	move.l	d1,CB_A+20(sp)
	move.l	d1,CB_A+24(sp)
	move.l	d1,CB_A+28(sp)
	move.l	d0,CB_A+32(sp)
	move.l	d1,CB_TT+0(sp)
	move.l	d1,CB_TT+4(sp)
	move.l	d1,CB_TT+8(sp)
	tst.l	CO_POSE(a6)
	beq	cb_nw
	tst.l	12(a5)				; a wheel: its place's x is not 0
	beq	cb_nw
	move.l	#16384,d2			; wc ws: the hub spins
	moveq	#0,d3
	btst	#11,d7
	beq.s	cb_w1
	move.l	CO_WC(a6),d2
	move.l	CO_WS(a6),d3
cb_w1:	move.l	#16384,d4			; sc ss: a front wheel (z < 0) steers
	moveq	#0,d6
	tst.l	20(a5)
	bpl.s	cb_w2
	move.l	CO_SC(a6),d4
	move.l	CO_SS(a6),d6
cb_w2:	move.l	d4,CB_A+0(sp)			; A0 = (sc, 0, -ss)
	move.l	d6,d0
	neg.l	d0
	move.l	d0,CB_A+8(sp)
	move.l	d3,d0				; A1 = ((ws ss) >> 14, wc, (ws sc) >> 14)
	muls.l	d6,d0
	asr.l	d5,d0
	move.l	d0,CB_A+12(sp)
	move.l	d2,CB_A+16(sp)
	move.l	d3,d0
	muls.l	d4,d0
	asr.l	d5,d0
	move.l	d0,CB_A+20(sp)
	move.l	d2,d0				; A2 = ((wc ss) >> 14, -ws, (wc sc) >> 14)
	muls.l	d6,d0
	asr.l	d5,d0
	move.l	d0,CB_A+24(sp)
	move.l	d3,d0
	neg.l	d0
	move.l	d0,CB_A+28(sp)
	move.l	d2,d0
	muls.l	d4,d0
	asr.l	d5,d0
	move.l	d0,CB_A+32(sp)
	lea	CB_A(sp),a0			; t[b] = o[b] - ((o0 A0b + o1 A1b + o2 A2b) >> 14)
	lea	CB_TT(sp),a1
	moveq	#2,d6
cb_wt:	move.l	12(a5),d0
	muls.l	(a0),d0
	move.l	16(a5),d1
	muls.l	12(a0),d1
	add.l	d1,d0
	move.l	20(a5),d1
	muls.l	24(a0),d1
	add.l	d1,d0
	asr.l	d5,d0
	move.l	12(a5),d1			; o[b]
	cmp.w	#1,d6
	bne.s	cb_wo
	move.l	16(a5),d1
cb_wo:	tst.w	d6
	bne.s	cb_wp
	move.l	20(a5),d1
cb_wp:	sub.l	d0,d1
	move.l	d1,(a1)+
	addq.l	#4,a0
	dbra	d6,cb_wt
	bra	cb_mul
cb_nw:	tst.l	CO_BODY(a6)			; the body's lean and drop
	beq	cb_mul
	move.l	CO_BPC(a6),d2
	move.l	CO_BPS(a6),d3
	move.l	CO_BRC(a6),d4
	move.l	CO_BRS(a6),d6
	move.l	d4,CB_A+0(sp)			; A0 = (brc, brs, 0)
	move.l	d6,CB_A+4(sp)
	move.l	d2,d0				; A1 = (-((bpc brs) >> 14), (bpc brc) >> 14, bps)
	muls.l	d6,d0
	asr.l	d5,d0
	neg.l	d0
	move.l	d0,CB_A+12(sp)
	move.l	d2,d0
	muls.l	d4,d0
	asr.l	d5,d0
	move.l	d0,CB_A+16(sp)
	move.l	d3,CB_A+20(sp)
	move.l	d3,d0				; A2 = ((bps brs) >> 14, -((bps brc) >> 14), bpc)
	muls.l	d6,d0
	asr.l	d5,d0
	move.l	d0,CB_A+24(sp)
	move.l	d3,d0
	muls.l	d4,d0
	asr.l	d5,d0
	neg.l	d0
	move.l	d0,CB_A+28(sp)
	move.l	d2,CB_A+32(sp)
	move.l	CO_DROP(a6),d0
	neg.l	d0
	move.l	d0,CB_TT+4(sp)
cb_mul:	lea	CB_A(sp),a0			; M[a][b] = (A[a][0] O[0][b] + A[a][1] O[1][b] + A[a][2] O[2][b]) >> 14
	lea	CB_M(sp),a1
	moveq	#2,d6
cb_ma:	moveq	#0,d7				; b, in bytes
cb_mb:	move.l	(a0),d0
	muls.l	0(a6,d7.l),d0
	move.l	4(a0),d1
	muls.l	12(a6,d7.l),d1
	add.l	d1,d0
	move.l	8(a0),d1
	muls.l	24(a6,d7.l),d1
	add.l	d1,d0
	asr.l	d5,d0
	move.l	d0,(a1)+
	addq.l	#4,d7
	cmp.l	#12,d7
	bne.s	cb_mb
	lea	12(a0),a0
	dbra	d6,cb_ma
	moveq	#0,d7				; T[b] = T0[b] + ((t0 O0b + t1 O1b + t2 O2b) >> 14)
cb_tb:	move.l	CB_TT+0(sp),d0
	muls.l	0(a6,d7.l),d0
	move.l	CB_TT+4(sp),d1
	muls.l	12(a6,d7.l),d1
	add.l	d1,d0
	move.l	CB_TT+8(sp),d1
	muls.l	24(a6,d7.l),d1
	add.l	d1,d0
	asr.l	d5,d0
	add.l	CO_T0(a6,d7.l),d0
	move.l	d0,(a3,d7.l)
	addq.l	#4,d7
	cmp.l	#12,d7
	bne.s	cb_tb
	move.l	CB_LOC+60(sp),a4		; R: M's words
	lea	CB_M(sp),a1
	moveq	#8,d6
cb_r:	move.l	(a1)+,d0
	move.w	d0,(a4)+
	dbra	d6,cb_r
	lea	CB_M(sp),a1			; E[a] = -((M[a][0] T0 + M[a][1] T1 + M[a][2] T2) >> 14)
	moveq	#2,d6
cb_e:	move.l	(a1)+,d0
	muls.l	(a3),d0
	move.l	(a1)+,d1
	muls.l	4(a3),d1
	add.l	d1,d0
	move.l	(a1)+,d1
	muls.l	8(a3),d1
	add.l	d1,d0
	asr.l	d5,d0
	neg.l	d0
	move.l	d0,(a2)+
	dbra	d6,cb_e
	lea	CB_LOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; pi_pass68k(pi_sctx *c): one pass over the near pieces (main.c render_scene's loop, pi_draw and pi_faces in one):
; for each piece of the list its texture phase, the side (pass 1 only the pieces with see-through faces), pi_pre68k,
; the object's slot (pt_begin_key), the blocks' order (pi_ford68k), and the faces through the quick loop with its
; blocks projected as they come up.  Back to C (the pointers in the context): a piece not yet looked at or not
; whole (slow: draw_object), a face the quick loop leaves (face), a material to note (note), the phase (mtph).

; pi_rec (more)
PR_ZB	equ	20
PR_HAS	equ	25
PR_QK	equ	26
PR_CARP	equ	27
PR_RECS	equ	28
PR_BLK	equ	32
PR_IBLK	equ	36
PR_ORD	equ	40
PR_UV	equ	44
PR_IVERT equ	48
PR_NB	equ	52
PR_NBALL equ	54
PR_PHASE equ	56
PR_LAYER equ	60				; (a word: 0 / 1)
PR_KB	equ	62				; (a word: the sort class's keys, main.c pt_class_key)
; pi_sctx
S_LIST	equ	0
S_N	equ	4
S_RECS	equ	8
S_PASS	equ	12
S_LAYER	equ	16
S_SLOW	equ	20
S_FACE	equ	24
S_NOTE	equ	28
S_MTPH	equ	32
S_FACES	equ	36
S_GEO	equ	40
S_ANIM	equ	44
S_TEXPH	equ	48
S_ZB	equ	52
S_D2	equ	56
S_CARP	equ	60
S_GRND	equ	64
S_NPOLY	equ	68
S_NOBJ	equ	72
S_CUR	equ	76
S_OBJS	equ	80
S_STF	equ	84
S_STV	equ	88
S_STAMP	equ	92
S_O	equ	96
S_SIX	equ	100
S_SIY	equ	104
S_SOUT	equ	108
S_SV	equ	112
S_BLKAT	equ	116
S_FC	equ	120
S_G	equ	224
S_P	equ	308
S_OC	equ	368
S_MAXOBJ equ	416
; pt_fctx
FC_FORD	equ	0
FC_NFORD equ	4
FC_REC	equ	8
FC_STAMP equ	16
FC_SEE	equ	20
FC_E	equ	28
FC_UV	equ	52
FC_MT	equ	56
FC_MTST	equ	60
FC_NPOLY equ	68
FC_COUNT equ	76
FC_AT	equ	80
; geo_blk
G_V	equ	0
G_N	equ	4
G_IX	equ	8
G_IY	equ	12
G_OUT	equ	16
G_VV	equ	20
G_R	equ	24
G_T	equ	44

; PSNOTE: the piece a3's texture phase and depth bias into the context's notes (d0, a0)
PSNOTE	macro
	move.l	PR_PHASE(a3),d0			; the texture phase
	bpl.s	.p\@
	move.l	S_ANIM(a5),d0
	bra.s	.q\@
.p\@:	asr.l	#2,d0
	and.l	#$3fff,d0
.q\@:	move.l	S_TEXPH(a5),a0
	move.l	d0,(a0)
	move.l	S_ZB(a5),a0
	move.l	PR_ZB(a3),(a0)
	endm
	xdef	_pi_pass68k
	xdef	pi_pass68k
_pi_pass68k:
pi_pass68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a5			; c
	move.l	S_LIST(a5),a4
	move.l	S_N(a5),d7
	bra	ps_next
ps_loop:
	move.l	(a4)+,d6			; o
	move.l	d6,d0
	lsl.l	#6,d0
	move.l	S_RECS(a5),a3
	add.l	d0,a3				; its pi_rec
	tst.b	PR_QK(a3)
	beq	ps_slow
	move.l	S_LAYER(a5),d0			; (layer_wanted)
	cmp.l	#3,d0
	beq.s	ps_lay
	cmp.w	PR_LAYER(a3),d0
	bne	ps_next
ps_lay:	tst.l	S_PASS(a5)			; pass 1 and no see-through faces: nothing to do but the two notes below,
	beq.s	ps_ly0				; which the next piece writes over -- only the last such piece's are
	btst	#2,PR_HAS(a3)			; written (ps_pend: before a slow piece, at the end)
	bne.s	ps_ly0
	move.l	a3,ps_pend
	bra	ps_next
ps_ly0:	clr.l	ps_pend
	PSNOTE
	move.b	PR_HAS(a3),d5
	tst.l	S_PASS(a5)
	beq.s	ps_p0
	btst	#2,d5				; pass 1: only with see-through faces
	beq	ps_next
ps_p0:	move.l	a3,S_P(a5)
	pea	S_P(a5)
	bsr	pi_pre68k
	addq.l	#4,sp
	tst.l	d0
	beq	ps_next				; beyond the draw distance
	move.l	d0,d4				; 1 out of the picture, 2 to be drawn
	move.l	S_P+PP_D2(a5),d0		; g_obj_d2[o] = (float)(d2q * 16), unsigned
	lsl.l	#4,d0
	fmove.l	d0,fp0
	tst.l	d0
	bpl.s	ps_fl0
	fadd.d	#4294967296.0,fp0
ps_fl0:	move.l	S_D2(a5),a0
	fmove.s	fp0,(a0,d6.l*4)
	move.l	S_CARP(a5),a0
	move.b	PR_CARP(a3),(a0,d6.l)
	tst.w	PR_LAYER(a3)
	seq	d0
	neg.b	d0
	move.l	S_GRND(a5),a0
	move.b	d0,(a0,d6.l)
	subq.l	#1,d4
	beq	ps_next
	tst.l	S_PASS(a5)
	bne.s	ps_go
	btst	#1,d5				; pass 0: only with solid faces
	beq	ps_next
ps_go:	move.l	S_NOBJ(a5),a0			; pt_begin_key(key, 0, pass)
	move.l	(a0),d0
	move.l	S_CUR(a5),a1
	cmp.l	S_MAXOBJ(a5),d0
	blt.s	ps_bk
	moveq	#-1,d1
	move.l	d1,(a1)
	bra	ps_next
ps_bk:	move.l	d0,(a1)				; pt_cur
	addq.l	#1,(a0)
	move.l	d0,d1
	lsl.l	#4,d1
	move.l	S_OBJS(a5),a1
	add.l	d1,a1
	move.l	S_NPOLY(a5),a0
	move.l	(a0),(a1)+			; first
	clr.l	(a1)+				; count
	move.w	PR_KB(a3),d1			; key + the class's (pt_class_key)
	ext.l	d1
	add.l	S_P+PP_KEY(a5),d1
	move.l	d1,(a1)+
	add.l	d0,d0
	add.l	S_PASS(a5),d0
	move.l	d0,(a1)				; order
	cmp.l	#pt_faces_68k,S_FACES(a5)	; one block and the fused loop: its list read in place (ps_one)
	bne.s	ps_gen
	cmp.w	#1,PR_NB(a3)
	bne.s	ps_gen
	bsr	ps_one
	tst.l	d5
	bne.s	ps_fd
ps_gen:	lea	S_OC(a5),a0			; the blocks' order
	move.l	PR_BLK(a3),(a0)+
	move.w	PR_NB(a3),d0
	ext.l	d0
	move.l	d0,(a0)+
	move.l	PR_IBLK(a3),(a0)+
	move.l	S_P+PP_E(a5),(a0)+
	move.l	S_P+PP_E+4(a5),(a0)+
	move.l	S_P+PP_E+8(a5),(a0)+
	move.w	PR_NBALL(a3),d0
	ext.l	d0
	move.l	d0,(a0)+
	move.l	PR_ORD(a3),(a0)
	pea	S_OC(a5)
	bsr	pi_ford68k
	addq.l	#4,sp
	move.l	d0,d4				; nford
	move.l	S_FC+FC_FORD(a5),d5		; (the list: pi_ford_buf)
ps_fd:	move.l	d6,S_O(a5)			; the faces (pi_faces)
	addq.l	#1,S_STAMP(a5)
	move.l	S_STF(a5),a0
	add.l	d4,(a0)
	move.l	S_MTPH(a5),a0
	jsr	(a0)
	lea	S_FC(a5),a2
	move.l	d0,FC_MTST(a2)
	move.l	d4,FC_NFORD(a2)
	move.l	PR_RECS(a3),a6			; the faces' records
	move.l	a6,FC_REC(a2)
	move.l	S_STAMP(a5),FC_STAMP(a2)
	move.l	S_P+PP_E(a5),FC_E(a2)
	move.l	S_P+PP_E+4(a5),FC_E+4(a2)
	move.l	S_P+PP_E+8(a5),FC_E+8(a2)
	move.l	PR_UV(a3),FC_UV(a2)
	lea	S_P+PP_R(a5),a0			; geo: R and T
	lea	S_G+G_R(a5),a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.w	(a0)+,(a1)+
	lea	S_P+PP_V(a5),a0
	lea	S_G+G_T(a5),a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	cmp.l	#pt_faces_68k,S_FACES(a5)	; the quick loop in vasm: fused here (pz_faces, the list in d5)
	bne.s	ps_f0
	bsr	pz_faces
	bra	ps_next
ps_f0:	moveq	#0,d5				; oi
ps_fl:	cmp.l	d4,d5
	bge	ps_next
	lea	S_FC(a5),a2
	move.l	d5,FC_AT(a2)
	move.l	S_NPOLY(a5),a0
	move.l	(a0),FC_NPOLY(a2)
	clr.l	FC_COUNT(a2)
	move.l	a2,-(sp)
	move.l	S_FACES(a5),a0
	jsr	(a0)				; the quick loop: up to the first face it leaves
	addq.l	#4,sp
	move.l	d0,d5
	lea	S_FC(a5),a2
	move.l	S_NPOLY(a5),a0
	move.l	FC_NPOLY(a2),(a0)
	move.l	S_CUR(a5),a0
	move.l	(a0),d0
	lsl.l	#4,d0
	move.l	S_OBJS(a5),a0
	move.l	FC_COUNT(a2),d1
	add.l	d1,4(a0,d0.l)
	cmp.l	d4,d5
	bge	ps_next
	move.l	FC_FORD(a2),a0
	move.w	(a0,d5.l*2),d3
	ext.l	d3				; fi
	move.l	d3,d0
	mulu.w	#24,d0
	lea	(a6,d0.l),a1			; its record
	moveq	#0,d0
	move.b	19(a1),d0			; fl
	btst	#5,d0				; PTF_HARD
	bne	ps_face
	moveq	#17,d1				; PTF_VALID | PTF_CORNERS
	and.l	d0,d1
	cmp.l	#17,d1
	bne	ps_face
	and.l	#2,d0				; PTF_SEE
	cmp.l	FC_SEE(a2),d0
	bne	ps_face
	moveq	#0,d0
	move.b	23(a1),d0			; the block
	move.l	S_BLKAT(a5),a0
	move.l	S_STAMP(a5),d1
	cmp.l	(a0,d0.l*4),d1
	beq.s	ps_mt
	move.l	d1,(a0,d0.l*4)			; its corners projected
	lsl.l	#5,d0
	move.l	PR_IBLK(a3),a0
	add.l	d0,a0
	move.l	24(a0),d0			; vbase
	move.l	28(a0),d1			; vcount
	lea	S_G(a5),a1
	move.l	d1,G_N(a1)
	move.l	S_STV(a5),a0
	add.l	d1,(a0)
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	add.l	d1,d1				; vbase * 6
	add.l	PR_IVERT(a3),d1
	move.l	d1,G_V(a1)
	move.l	d0,d1
	lsl.l	#2,d1				; vbase * 4
	move.l	S_SIX(a5),a0
	add.l	d1,a0
	move.l	a0,G_IX(a1)
	move.l	S_SIY(a5),a0
	add.l	d1,a0
	move.l	a0,G_IY(a1)
	move.l	S_SOUT(a5),a0
	add.l	d0,a0
	move.l	a0,G_OUT(a1)
	move.l	d1,d0
	add.l	d1,d1
	add.l	d0,d1				; vbase * 12
	move.l	S_SV(a5),a0
	add.l	d1,a0
	move.l	a0,G_VV(a1)
	move.l	a1,-(sp)
	move.l	S_GEO(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	bra	ps_fl				; (the same face again)
ps_mt:	moveq	#0,d0
	move.w	20(a1),d0			; mi
	move.l	d0,d1
	lsl.l	#4,d1
	move.l	FC_MT(a2),a0
	move.l	12(a0,d1.l),d1
	lsr.l	#8,d1				; its stamp
	cmp.l	FC_MTST(a2),d1
	beq.s	ps_face
	move.l	d0,-(sp)
	move.l	S_NOTE(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	bra	ps_fl				; (the same face again)
ps_face:
	move.l	d3,-(sp)			; a face the quick loop leaves: C
	move.l	a5,-(sp)
	move.l	S_FACE(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	addq.l	#1,d5
	bra	ps_fl
ps_slow:
	bsr	ps_flush
	move.l	d6,-(sp)			; a piece the C way
	move.l	S_SLOW(a5),a0
	jsr	(a0)
	addq.l	#4,sp
ps_next:
	subq.l	#1,d7
	bpl	ps_loop
	bsr	ps_flush
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; pz_faces: the piece's faces through pt_faces_68k's tests, fused (the same tests in the same order): where the quick
; loop would return to ps_fl, ps_fl's work done in place -- a block not projected: projected (pf_proj), the face
; again; a HARD face: C (S_FACE); a face cut by a plane, a material not noted, no room: its material noted (S_NOTE)
; and the face again if it was not, else C.  The polygons counted straight into pt_npoly and the object's count.
; In: a5 the context (S_FC filled), a6 the faces' records, d4 nford, d5 the face list.  d0-d6 a0-a3 a6 used.
ZC_FORD	equ	0
ZC_REC	equ	8
ZC_BLK	equ	12
ZC_STAMP	equ	16
ZC_SEE	equ	20
ZC_CULL	equ	24
ZC_E	equ	28
ZC_OUT	equ	40
ZC_IX	equ	44
ZC_IY	equ	48
ZC_UV	equ	52
ZC_MT	equ	56
ZC_MTS	equ	60
ZC_BUF	equ	64
ZC_MAX	equ	72
pz_faces:
	movem.l	d6-d7/a3-a4,-(sp)
	move.l	d5,a4				; the list
	move.l	S_CUR(a5),a0			; &objs[cur].count, at (sp)
	move.l	(a0),d0
	lsl.l	#4,d0
	add.l	S_OBJS(a5),d0
	addq.l	#4,d0
	move.l	d0,-(sp)
	move.l	d4,d7				; faces left
	move.l	S_FC+ZC_OUT(a5),a3
	move.l	S_FC+ZC_SEE(a5),d6
	bra	pz_nx
pz_lp:	move.w	(a4)+,d3			; fi
	ext.l	d3
	move.l	d3,d1
	add.l	d1,d1
	add.l	d3,d1
	lsl.l	#3,d1				; x 24
	lea	(a6,d1.l),a0			; its record
	moveq	#0,d1
	move.b	19(a0),d1			; fl
	btst	#5,d1				; PTF_HARD: C
	bne	pz_c
	moveq	#17,d2				; PTF_VALID | PTF_CORNERS
	and.l	d1,d2
	cmp.b	#17,d2
	bne	pz_nx
	moveq	#2,d2				; PTF_SEE: this pass?
	and.l	d1,d2
	cmp.l	d6,d2
	bne	pz_nx
	moveq	#0,d0
	move.b	23(a0),d0			; its block projected?
	move.l	S_FC+ZC_BLK(a5),a1
	move.l	(a1,d0.l*4),d2
	cmp.l	S_FC+ZC_STAMP(a5),d2
	bne	pz_pj
	tst.l	S_FC+ZC_CULL(a5)			; turned away?
	beq.s	pz_out
	btst	#3,d1				; (PTF_NORMAL)
	beq.s	pz_out
	move.w	12(a0),d2
	ext.l	d2
	muls.l	S_FC+ZC_E+0(a5),d2
	move.w	14(a0),d0
	ext.l	d0
	muls.l	S_FC+ZC_E+4(a5),d0
	add.l	d0,d2
	move.w	16(a0),d0
	ext.l	d0
	muls.l	S_FC+ZC_E+8(a5),d0
	add.l	d0,d2
	move.l	8(a0),d0			; D - n.E < 0
	sub.l	d2,d0
	bmi	pz_nx
pz_out:						; the outcodes: all in d0, any in d4
	move.w	(a0),d2				; the four corners' indices first, each in its own register (no
	ext.l	d2				; lookup waiting on the load just before it; d3 stays the face for pz_c)
	movea.w	2(a0),a1
	movea.w	4(a0),a2
	move.w	6(a0),d5
	ext.l	d5
	move.b	(a3,d2.l),d0
	move.b	(a3,a1.l),d2
	move.b	d0,d4
	and.b	d2,d0
	or.b	d2,d4
	move.b	(a3,a2.l),d2
	and.b	d2,d0
	or.b	d2,d4
	move.b	(a3,d5.l),d2
	and.b	d2,d0
	or.b	d2,d4
	moveq	#3,d5				; all behind the eye or beyond the far plane
	and.b	d0,d5
	bne	pz_nx
	btst	#0,d4
	bne.s	pz_o2
	moveq	#$3c,d5				; ... or all off one side
	and.b	d0,d5
	bne	pz_nx
pz_o2:	moveq	#3,d5				; cut by a plane
	and.b	d4,d5
	bne	pz_rt
	moveq	#0,d2				; the material noted?
	move.w	20(a0),d2
	lsl.l	#4,d2
	move.l	S_FC+ZC_MT(a5),a1
	add.l	d2,a1
	move.l	12(a1),d2
	lsr.l	#8,d2
	cmp.l	S_FC+ZC_MTS(a5),d2
	bne	pz_rt
	move.l	S_NPOLY(a5),a2			; room?
	move.l	(a2),d2
	cmp.l	S_FC+ZC_MAX(a5),d2
	bge	pz_rt
	addq.l	#1,(a2)				; pt_npoly, the object's count
	move.l	(sp),a2
	addq.l	#1,(a2)
	move.l	d2,d0				; the polygon: buf + 136 n
	lsl.l	#7,d0
	lsl.l	#3,d2
	add.l	d0,d2
	move.l	S_FC+ZC_BUF(a5),a2
	add.l	d2,a2
	moveq	#0,d5
	move.b	18(a0),d5			; corners
	move.b	d5,4(a2)
	btst	#2,d1				; PTF_FLAT
	beq.s	pz_tx
	clr.l	(a2)
	move.b	#2,5(a2)			; SPAN_FLAT
	move.b	22(a0),6(a2)
	bra.s	pz_cn
pz_tx:	move.l	(a1),(a2)
	move.b	15(a1),5(a2)
	clr.b	6(a2)
pz_cn:	move.l	4(a1),d4			; su8
	move.l	8(a1),d0			; sv8
	addq.l	#8,a2
	move.l	S_FC+ZC_IX(a5),a1
	move.l	S_FC+ZC_IY(a5),a3
	move.l	S_FC+ZC_UV(a5),a6
	move.w	(a0)+,d2			; (each corner's index read a pass ahead: the last read is the record's
	ext.l	d2				; next word, still inside it)
pz_cc:	move.l	(a1,d2.l*4),(a2)+
	move.l	(a3,d2.l*4),(a2)+
	move.w	(a6,d2.l*4),d3			; u and v side by side
	move.w	2(a6,d2.l*4),d1
	move.w	(a0)+,d2
	ext.l	d2
	ext.l	d3
	ext.l	d1
	muls.l	d4,d3
	muls.l	d0,d1
	move.l	d3,(a2)+
	move.l	d1,(a2)+
	subq.l	#1,d5
	bne.s	pz_cc
	move.l	S_FC+ZC_OUT(a5),a3
	move.l	S_FC+ZC_REC(a5),a6
pz_nx:	subq.l	#1,d7
	bpl	pz_lp
	addq.l	#4,sp
	movem.l	(sp)+,d6-d7/a3-a4
	rts
pz_pj:	bsr	pf_proj				; a block not projected: projected (d0), then the face again
pz_ag:	subq.l	#2,a4
	addq.l	#1,d7
	bra.s	pz_nx
pz_rt:	moveq	#0,d0				; cut, not noted, no room: noted first (and the face again), else C
	move.w	20(a0),d0			; mi
	move.l	d0,d1
	lsl.l	#4,d1
	move.l	S_FC+ZC_MT(a5),a1
	move.l	12(a1,d1.l),d1
	lsr.l	#8,d1
	cmp.l	S_FC+ZC_MTS(a5),d1
	beq.s	pz_c
	move.l	d0,-(sp)
	move.l	S_NOTE(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	bra.s	pz_ag
pz_c:	move.l	d3,-(sp)			; a face for C (pf68k / pi_face_c)
	move.l	a5,-(sp)
	move.l	S_FACE(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	bra	pz_nx

; ps_one: pi_ford68k for a piece of one block (a3 its pi_rec, the eye in S_P): its face list read where it is.
; The LOD from the squared distance: with nu = 1 the key is not used, and key > L (key = Z - (d >> 1), Z = $2000
; for a 'Z' block) is (d >> 1) < K = Z - L, i.e. d < 2K; near d = isqrt(q): q < (2K)^2; far d = isqrt(q) << 2:
; isqrt(q) < ceil(K / 2), q < ceil(K / 2)^2 -- exactly pi_ford's choice without the roots.
; Out: d4 nford, d5 the list; d5 = 0: a row without a list, pi_ford68k makes it.  d0-d5 a0-a1 used.
ps_one:	move.l	PR_IBLK(a3),a0			; |middle - E|
	move.l	(a0),d0
	sub.l	S_P+PP_E(a5),d0
	bpl.s	po_a0
	neg.l	d0
po_a0:	move.l	4(a0),d1
	sub.l	S_P+PP_E+4(a5),d1
	bpl.s	po_a1
	neg.l	d1
po_a1:	move.l	8(a0),d2
	sub.l	S_P+PP_E+8(a5),d2
	bpl.s	po_a2
	neg.l	d2
po_a2:	move.l	d0,d3
	or.l	d1,d3
	or.l	d2,d3
	moveq	#0,d4				; near
	cmp.l	#32768,d3
	blo.s	po_q
	lsr.l	#2,d0				; far: (|m| >> 2), each <= 26000
	lsr.l	#2,d1
	lsr.l	#2,d2
	cmp.l	#26000,d0
	bhi	po_0
	cmp.l	#26000,d1
	bhi	po_0
	cmp.l	#26000,d2
	bhi	po_0
	moveq	#1,d4
po_q:	mulu.w	d0,d0				; q
	mulu.w	d1,d1
	mulu.w	d2,d2
	add.l	d1,d0
	add.l	d2,d0
	move.l	PR_BLK(a3),a1			; block 0
	moveq	#0,d5				; Z
	cmp.b	#'Z',48(a1)
	bne.s	po_z
	move.l	#$2000,d5
po_z:	moveq	#0,d3				; lv
	move.l	d5,d1
	sub.l	pi_lodt,d1
	bsr	po_t
	bne.s	po_lv
	moveq	#1,d3
	move.l	d5,d1
	sub.l	pi_lodt+4,d1
	bsr	po_t
	bne.s	po_lv
	moveq	#2,d3
po_lv:	move.l	120(a1,d3.l*4),d0		; drawn = lod[lv]
	bmi	po_0
	move.w	PR_NBALL(a3),d1
	ext.l	d1
	cmp.l	d1,d0
	bge	po_0
	move.l	d0,d1
	lsl.l	#5,d1
	move.l	PR_IBLK(a3),a0
	add.l	d1,a0				; its whole numbers
	mulu.l	#MB_SIZE,d0
	move.l	PR_BLK(a3),a1
	add.l	d0,a1
	move.l	S_P+PP_E(a5),d1			; the eye from the block: x y z in d1 d2 d3
	sub.l	12(a0),d1
	move.l	S_P+PP_E+4(a5),d2
	sub.l	16(a0),d2
	move.l	S_P+PP_E+8(a5),d3
	sub.l	20(a0),d3
	moveq	#0,d0				; row: y < 0 -> 8
	tst.l	d2
	bpl.s	po_y
	moveq	#8,d0
po_y:	tst.l	d1
	bmi.s	po_xn
	tst.l	d3				; x >= 0: z >= 0 ? (z > x ? 0 : 1) : (-z <= x ? 2 : 3)
	bmi.s	po_x2
	cmp.l	d1,d3
	bgt.s	po_row
	addq.l	#1,d0
	bra.s	po_row
po_x2:	neg.l	d3
	cmp.l	d1,d3
	ble.s	po_x3
	addq.l	#3,d0
	bra.s	po_row
po_x3:	addq.l	#2,d0
	bra.s	po_row
po_xn:	neg.l	d1				; x < 0 (-x in d1): z < 0 ? (-z > -x ? 4 : 5) : (z <= -x ? 6 : 7)
	tst.l	d3
	bpl.s	po_x6
	neg.l	d3
	cmp.l	d1,d3
	ble.s	po_x5
	addq.l	#4,d0
	bra.s	po_row
po_x5:	addq.l	#5,d0
	bra.s	po_row
po_x6:	cmp.l	d1,d3
	bgt.s	po_x7
	addq.l	#6,d0
	bra.s	po_row
po_x7:	addq.l	#7,d0
po_row:	move.l	52(a1,d0.l*4),d1		; from
	move.l	56(a1,d0.l*4),d4		; to
	cmp.l	d1,d4
	beq.s	po_g				; no list: pi_ford68k
	sub.l	d1,d4				; to - from, at most max, not below 0
	bpl.s	po_p
	moveq	#0,d4
po_p:	cmp.l	S_OC+36(a5),d4
	ble.s	po_m
	move.l	S_OC+36(a5),d4
po_m:	move.l	PR_ORD(a3),d5
	add.l	d1,d5
	add.l	d1,d5
	rts
po_0:	moveq	#0,d4				; nothing drawn
	move.l	S_FC+FC_FORD(a5),d5
	rts
po_g:	moveq	#0,d5
	rts
; ne: key > L, for K = Z - L in d1, q in d0, far in d4 (d1 used)
po_t:	tst.l	d1
	ble.s	po_f
	tst.l	d4
	bne.s	po_tf
	add.l	d1,d1				; near: q < (2K)^2
	cmp.l	#65536,d1
	bhs.s	po_tt
	mulu.w	d1,d1
	cmp.l	d1,d0
	blo.s	po_tt
po_f:	cmp.l	d1,d1				; (eq)
	rts
po_tf:	addq.l	#1,d1				; far: q < ceil(K / 2)^2
	lsr.l	#1,d1
	cmp.l	#65536,d1
	bhs.s	po_tt
	mulu.w	d1,d1
	cmp.l	d1,d0
	bhs.s	po_f
po_tt:	moveq	#1,d1				; (ne)
	rts

ps_flush:					; a skipped piece's notes, if they are the last written (a3, d0, a0 kept)
	move.l	ps_pend,d0
	beq.s	ps_fx
	movem.l	d0/a0/a3,-(sp)
	move.l	d0,a3
	clr.l	ps_pend
	PSNOTE
	movem.l	(sp)+,d0/a0/a3
ps_fx:	rts

; ---------------------------------------------------------------------------------------------------------------
; int ci_mface68k(ci_mctx *m): a car's reflecting face whose corners are all in its own block (main.c ci_faces,
; its block turned and projected, its material noted): the outcodes' tests, then the polygon with each corner's
; reflection (ci_ref: the corner normal turned, the eye's line reflected, along the camera's right and up).
; 1 done (drawn or not to be drawn), 0 a plane cuts it (the C way).
M_F	equ	0
M_IX	equ	4
M_IY	equ	8
M_VV	equ	12
M_OUT	equ	16
M_R	equ	20
M_VN	equ	24
M_EU	equ	28
M_EV	equ	32
M_MT	equ	36
M_CR	equ	40
M_SR	equ	44
M_BUF	equ	48
M_NPOLY	equ	52
M_MAXP	equ	56
M_CNT	equ	60
; locals
MF_NV	equ	0
MF_SU	equ	12
MF_SV	equ	16
MF_LOC	equ	20

	xdef	_ci_mface68k
	xdef	ci_mface68k
_ci_mface68k:
ci_mface68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a5			; m
	lea	-MF_LOC(sp),sp
	move.l	M_F(a5),a4			; the face's record
	moveq	#0,d7
	move.b	18(a4),d7			; nc
	move.l	M_OUT(a5),a0
	moveq	#$3f,d2				; all
	moveq	#0,d3				; any
	move.l	a4,a1
	move.l	d7,d1
	subq.l	#1,d1
mf_o:	move.w	(a1)+,d0
	ext.l	d0
	move.b	(a0,d0.l),d4
	and.b	d4,d2
	or.b	d4,d3
	dbra	d1,mf_o
	moveq	#3,d0
	and.l	d2,d0
	bne	mf_1				; all behind one plane
	btst	#0,d3
	bne.s	mf_a
	moveq	#$3c,d0
	and.l	d2,d0
	bne	mf_1				; all off one side
mf_a:	moveq	#3,d0
	and.l	d3,d0
	bne	mf_0				; cut by the near / far plane: C
	move.l	M_NPOLY(a5),a0			; the polygon's slot (pt_face)
	move.l	(a0),d0
	cmp.l	M_MAXP(a5),d0
	bge	mf_1
	addq.l	#1,(a0)
	move.l	M_CNT(a5),a0
	addq.l	#1,(a0)
	mulu.l	#136,d0
	move.l	M_BUF(a5),a3
	add.l	d0,a3
	moveq	#0,d0
	move.w	20(a4),d0			; mi
	lsl.l	#4,d0
	move.l	M_MT(a5),a0
	add.l	d0,a0				; its pt_mt
	move.l	4(a0),d0
	asr.l	#8,d0
	move.l	d0,MF_SU(sp)
	move.l	8(a0),d0
	asr.l	#8,d0
	move.l	d0,MF_SV(sp)
	move.b	d7,4(a3)			; n
	btst	#2,19(a4)			; PTF_FLAT
	beq.s	mf_t
	clr.l	(a3)
	move.b	#2,5(a3)			; SPAN_FLAT
	move.b	22(a4),6(a3)			; its colour
	bra.s	mf_k
mf_t:	move.l	(a0),(a3)			; tex
	move.b	15(a0),5(a3)			; kind
	clr.b	6(a3)
mf_k:	addq.l	#8,a3				; the corners
	move.l	a4,a2				; f->v
	move.l	M_R(a5),a6
mf_c:	move.w	(a2)+,d0
	ext.l	d0				; vi
	move.l	M_IX(a5),a0
	move.l	(a0,d0.l*4),(a3)+		; x
	move.l	M_IY(a5),a0
	move.l	(a0,d0.l*4),(a3)+		; y
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	add.l	d1,d1				; vi * 6
	move.l	M_VN(a5),a1
	add.l	d1,a1				; its normal
	add.l	d1,d1				; vi * 12
	move.l	M_VV(a5),a0
	add.l	d1,a0				; its place in view space
	move.w	(a1),d4				; the normal turned: nv[b] = (n . R column b) >> 14
	move.w	2(a1),d5
	move.w	4(a1),d6
	lea	MF_NV(sp),a1
	moveq	#2,d3
mf_n:	move.w	(a6,d3.l*2),d0
	muls.w	d4,d0
	move.w	6(a6,d3.l*2),d1
	muls.w	d5,d1
	add.l	d1,d0
	move.w	12(a6,d3.l*2),d1
	muls.w	d6,d1
	add.l	d1,d0
	asr.l	#8,d0
	asr.l	#6,d0
	move.l	d0,(a1,d3.l*4)
	dbra	d3,mf_n
	movem.l	(a0),d4-d6			; v: x y z
	move.l	d4,d0				; m = |x| | |y| | |z|
	bpl.s	mf_m1
	neg.l	d0
mf_m1:	move.l	d5,d1
	bpl.s	mf_m2
	neg.l	d1
mf_m2:	or.l	d1,d0
	move.l	d6,d1
	bpl.s	mf_m3
	neg.l	d1
mf_m3:	or.l	d1,d0
	cmp.l	#16384,d0
	blo.s	mf_s0
	bfffo	d0{0:32},d1			; sh = the top bit's place - 13
	moveq	#18,d3
	sub.l	d1,d3
	asr.l	d3,d4
	asr.l	d3,d5
	asr.l	d3,d6
mf_s0:	move.l	d4,d0				; el = sqrt(x^2 + y^2 + z^2), at least 1
	muls.l	d4,d0
	move.l	d5,d1
	muls.l	d5,d1
	add.l	d1,d0
	move.l	d6,d1
	muls.l	d6,d1
	add.l	d1,d0
	bsr	pi_isqrt
	tst.l	d0
	bgt.s	mf_e
	moveq	#1,d0
mf_e:	moveq	#14,d1				; e = (x y z << 14) / el
	lsl.l	d1,d4
	lsl.l	d1,d5
	lsl.l	d1,d6
	divs.l	d0,d4
	divs.l	d0,d5
	divs.l	d0,d6
	move.l	MF_NV(sp),d1			; d2 = 2 ((e . nv) >> 14)
	muls.l	d4,d1
	move.l	MF_NV+4(sp),d2
	muls.l	d5,d2
	add.l	d2,d1
	move.l	MF_NV+8(sp),d2
	muls.l	d6,d2
	add.l	d2,d1
	moveq	#14,d0
	asr.l	d0,d1
	add.l	d1,d1
	move.l	MF_NV(sp),d2			; rx = ((d2 nv0) >> 14) - e0
	muls.l	d1,d2
	asr.l	d0,d2
	sub.l	d4,d2
	move.l	MF_NV+4(sp),d3			; ry = ((d2 nv1) >> 14) - e1
	muls.l	d1,d3
	asr.l	d0,d3
	sub.l	d5,d3
	move.l	d2,d4				; u: 127 + 127 ((rx cr - ry sr) >> 14), 16.16
	muls.l	M_CR(a5),d4
	move.l	d3,d5
	muls.l	M_SR(a5),d5
	sub.l	d5,d4
	asr.l	d0,d4
	muls.l	#127,d4
	lsl.l	#2,d4
	add.l	#127*65536,d4
	sub.l	M_EU(a5),d4			; (- the slide) >> 8, x su
	asr.l	#8,d4
	muls.l	MF_SU(sp),d4
	move.l	d4,(a3)+
	move.l	d3,d4				; v: 127 + 127 ((ry cr + rx sr) >> 14)
	muls.l	M_CR(a5),d4
	move.l	d2,d5
	muls.l	M_SR(a5),d5
	add.l	d5,d4
	asr.l	d0,d4
	muls.l	#127,d4
	lsl.l	#2,d4
	add.l	#127*65536,d4
	sub.l	M_EV(a5),d4
	asr.l	#8,d4
	muls.l	MF_SV(sp),d4
	move.l	d4,(a3)+
	subq.l	#1,d7
	bne	mf_c
mf_1:	moveq	#1,d0
	bra.s	mf_out
mf_0:	moveq	#0,d0
mf_out:	lea	MF_LOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; ci_faces68k(ci_fctx *c): a car's or prop's faces (main.c ci_faces' loop, step for step): the quick loop
; (pt_cfaces), each block's turn (ci_block68k) when one of its faces first comes up, the whole-number cull, the
; block's corners projected, the material noted, a reflecting face in its own block through ci_mface68k; the rest
; in C (slow: ci_face_c).
C_G	equ	104
C_OB	equ	188
C_IBLK	equ	192
C_IVERT	equ	196
C_R	equ	200
C_T	equ	204
C_E	equ	208
C_TURN	equ	212
C_PROJ	equ	216
C_CFACES equ	220
C_GEO	equ	224
C_NOTE	equ	228
C_SLOW	equ	232
C_NPOLY	equ	236
C_COUNT	equ	240
C_STV	equ	244
C_CULL	equ	248
C_MC	equ	252
C_BLK	equ	256
C_SIX	equ	260
C_SIY	equ	264
C_SOUT	equ	268
C_SVV	equ	272
C_VN	equ	288

	xdef	_ci_faces68k
	xdef	ci_faces68k
_ci_faces68k:
ci_faces68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a5			; c (its pt_fctx first)
	move.l	FC_NFORD(a5),d4
	move.l	FC_REC(a5),a6
	move.l	FC_STAMP(a5),d6
	moveq	#0,d5				; oi
cf_fl:	cmp.l	#pt_cfaces_68k,C_CFACES(a5)	; the quick loop in vasm: fused (cz_fl)
	beq	cz_fl
	cmp.l	d4,d5
	bge	cf_out
	move.l	d5,FC_AT(a5)
	move.l	C_NPOLY(a5),a0
	move.l	(a0),FC_NPOLY(a5)
	clr.l	FC_COUNT(a5)
	move.l	a5,-(sp)
	move.l	C_CFACES(a5),a0
	jsr	(a0)				; the quick loop
	addq.l	#4,sp
	move.l	d0,d5
	move.l	C_NPOLY(a5),a0
	move.l	FC_NPOLY(a5),(a0)
	move.l	C_COUNT(a5),a0
	move.l	FC_COUNT(a5),d0
	add.l	d0,(a0)
	cmp.l	d4,d5
	bge	cf_out
cf_hd:	move.l	FC_FORD(a5),a0			; (cz: where the quick loop returns)
	move.w	(a0,d5.l*2),d3
	ext.l	d3				; fi
	move.l	d3,d0
	mulu.w	#24,d0
	lea	(a6,d0.l),a4			; its record
	moveq	#0,d7
	move.b	19(a4),d7			; fl
	btst	#0,d7				; PTF_VALID
	beq	cf_nx
	btst	#4,d7				; PTF_CORNERS
	beq	cf_nx
	moveq	#2,d0
	and.l	d7,d0
	cmp.l	FC_SEE(a5),d0
	bne	cf_nx
	moveq	#0,d2
	move.b	23(a4),d2			; bi
	move.l	C_TURN(a5),a0
	cmp.l	(a0,d2.l*4),d6
	beq.s	cf_tu
	move.l	d6,(a0,d2.l*4)			; the block's turn
	move.l	d2,d0				; E, T, R of block bi
	mulu.w	#12,d0
	move.l	C_E(a5),a0
	add.l	d0,a0
	move.l	a0,-(sp)
	move.l	C_T(a5),a0
	add.l	d0,a0
	move.l	a0,-(sp)
	move.l	d2,d0
	mulu.w	#18,d0
	move.l	C_R(a5),a0
	add.l	d0,a0
	move.l	a0,-(sp)
	move.l	d2,d0				; the block's flags
	mulu.w	#132,d0
	move.l	C_BLK(a5),a0
	move.l	16(a0,d0.l),-(sp)
	move.l	d2,d0
	lsl.l	#5,d0
	move.l	C_IBLK(a5),a0
	add.l	d0,a0
	move.l	a0,-(sp)			; io
	move.l	C_OB(a5),-(sp)
	bsr	ci_block68k
	lea	24(sp),sp
	bra	cf_fl				; (the same face again)
cf_tu:	tst.l	C_CULL(a5)			; the cull: D - n . E < 0
	beq.s	cf_cu
	btst	#3,d7				; PTF_NORMAL
	beq.s	cf_cu
	move.l	d2,d0
	mulu.w	#12,d0
	move.l	C_E(a5),a0
	add.l	d0,a0
	move.w	12(a4),d0
	ext.l	d0
	muls.l	(a0)+,d0
	move.w	14(a4),d1
	ext.l	d1
	muls.l	(a0)+,d1
	add.l	d1,d0
	move.w	16(a4),d1
	ext.l	d1
	muls.l	(a0),d1
	add.l	d1,d0
	move.l	8(a4),d1
	sub.l	d0,d1
	bmi	cf_nx
cf_cu:	btst	#6,d7				; PTF_INBLK
	beq	cf_mt
	move.l	C_PROJ(a5),a0
	cmp.l	(a0,d2.l*4),d6
	beq	cf_mt
	move.l	d6,(a0,d2.l*4)			; the block's corners projected (ci_proj)
	lea	C_G(a5),a1
	move.l	d2,d0				; R, T into geo
	mulu.w	#18,d0
	move.l	C_R(a5),a0
	add.l	d0,a0
	move.l	(a0)+,G_R(a1)
	move.l	(a0)+,G_R+4(a1)
	move.l	(a0)+,G_R+8(a1)
	move.l	(a0)+,G_R+12(a1)
	move.w	(a0),G_R+16(a1)
	move.l	d2,d0
	mulu.w	#12,d0
	move.l	C_T(a5),a0
	add.l	d0,a0
	move.l	(a0)+,G_T(a1)
	move.l	(a0)+,G_T+4(a1)
	move.l	(a0),G_T+8(a1)
	move.l	d2,d0
	lsl.l	#5,d0
	move.l	C_IBLK(a5),a0
	move.l	24(a0,d0.l),d0			; vbase
	move.l	C_IBLK(a5),a0
	move.l	d2,d1
	lsl.l	#5,d1
	move.l	28(a0,d1.l),d1			; vcount
	move.l	d1,G_N(a1)
	move.l	C_STV(a5),a0
	add.l	d1,(a0)
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	add.l	d1,d1				; vbase * 6
	add.l	C_IVERT(a5),d1
	move.l	d1,G_V(a1)
	move.l	d0,d1
	lsl.l	#2,d1
	move.l	C_SIX(a5),a0
	add.l	d1,a0
	move.l	a0,G_IX(a1)
	move.l	C_SIY(a5),a0
	add.l	d1,a0
	move.l	a0,G_IY(a1)
	move.l	C_SOUT(a5),a0
	add.l	d0,a0
	move.l	a0,G_OUT(a1)
	move.l	d1,d0
	add.l	d1,d1
	add.l	d0,d1				; vbase * 12
	move.l	C_SVV(a5),a0
	add.l	d1,a0
	move.l	a0,G_VV(a1)
	move.l	a1,-(sp)
	move.l	C_GEO(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	btst	#7,d7				; PTF_MIRROR: on with it
	beq	cf_fl				; (else the same face again)
cf_mt:	moveq	#0,d0
	move.w	20(a4),d0			; mi
	move.l	d0,d1
	lsl.l	#4,d1
	move.l	FC_MT(a5),a0
	move.l	12(a0,d1.l),d1
	lsr.l	#8,d1
	cmp.l	FC_MTST(a5),d1
	beq.s	cf_mi
	move.l	d0,-(sp)
	move.l	C_NOTE(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	btst	#7,d7
	bne.s	cf_mi
	btst	#6,d7
	bne	cf_fl				; (the same face again)
cf_mi:	move.l	d7,d0				; a reflecting face in its own block: ci_mface68k
	and.l	#$c0,d0
	cmp.l	#$c0,d0
	bne.s	cf_sl
	tst.l	C_VN(a5)
	beq.s	cf_sl
	move.l	C_MC(a5),a0
	move.l	a4,M_F(a0)
	move.l	d2,d0
	mulu.w	#18,d0
	add.l	C_R(a5),d0
	move.l	d0,M_R(a0)
	move.l	a0,-(sp)
	bsr	ci_mface68k
	addq.l	#4,sp
	tst.l	d0
	bne.s	cf_nx
cf_sl:	move.l	d3,-(sp)			; the rest: C
	move.l	a5,-(sp)
	move.l	C_SLOW(a5),a0
	jsr	(a0)
	addq.l	#8,sp
cf_nx:	addq.l	#1,d5
	bra	cf_fl
cf_out:	movem.l	(sp)+,d2-d7/a2-a6
	rts

; cz_fl: pt_cfaces_68k's loop fused into ci_faces68k (the same tests in the same order; its returns go to cf_hd with
; d5 the face, d4 nford and d6 the stamp as ci_faces68k keeps them; its retries come back here).  a5 the context
; (its pt_fctx first), a6 the faces' records; d3 the face, d7 its block; the polygons counted straight into pt_npoly
; and the object's count
ZC_NFORD equ	4
ZC_NPOLY equ	68
ZC_QBAT	equ	84
ZC_QEYE	equ	88
ZC_FNORM equ	92
ZC_FVERT equ	96
ZC_IEYE	equ	100
cz_fl:	move.l	ZC_FORD(a5),a4
	move.l	ZC_OUT(a5),a3
cz_lp:	cmp.l	ZC_NFORD(a5),d5
	bge	cf_out
	move.w	(a4,d5.l*2),d0			; the face
	ext.l	d0
	move.l	d0,d3				; (kept for its normal)
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	lsl.l	#3,d1
	lea	(a6,d1.l),a0
	moveq	#0,d1
	move.b	19(a0),d1			; fl
	btst	#5,d1				; PTF_HARD
	bne	cz_ret
	btst	#0,d1				; PTF_VALID
	beq	cz_nx
	moveq	#2,d2				; this pass?
	and.l	d1,d2
	cmp.l	ZC_SEE(a5),d2
	bne	cz_nx
	btst	#4,d1				; PTF_CORNERS
	beq	cz_ret
	moveq	#0,d7
	move.b	23(a0),d7			; the block
	cmp.l	#32,d7
	bhs	cz_ret
	move.l	ZC_QBAT(a5),a1			; its turn made?
	move.l	(a1,d7.l*4),d2
	cmp.l	ZC_STAMP(a5),d2
	bne	cz_ret
	tst.l	ZC_CULL(a5)
	beq	cz_out
	tst.l	ZC_IEYE(a5)			; the eye in whole numbers (ci_draw): D - n.E < 0
	beq.s	cz_fcull
	btst	#3,d1				; (PTF_NORMAL)
	beq	cz_out
	move.l	d7,d0				; the eye in the block: 12 bytes a block
	add.l	d0,d0
	add.l	d7,d0
	lsl.l	#2,d0
	move.l	ZC_QEYE(a5),a1
	add.l	d0,a1
	move.w	12(a0),d2
	ext.l	d2
	muls.l	(a1),d2
	move.w	14(a0),d0
	ext.l	d0
	muls.l	4(a1),d0
	add.l	d0,d2
	move.w	16(a0),d0
	ext.l	d0
	muls.l	8(a1),d0
	add.l	d0,d2
	move.l	8(a0),d0
	sub.l	d2,d0
	bmi	cz_nx
	bra	cz_out
cz_fcull:
	move.l	d3,d2				; the normal: 12 bytes a face
	add.l	d2,d2
	add.l	d3,d2
	lsl.l	#2,d2
	move.l	ZC_FNORM(a5),a4			; (a4: the normal for the sums; the face list again after)
	add.l	d2,a4
	move.l	(a4),d0				; all three 0 (+-0) -> no cull
	or.l	4(a4),d0
	or.l	8(a4),d0
	add.l	d0,d0
	beq.s	cz_fc0
	move.w	(a0),d2				; the first corner: 12 bytes
	ext.l	d2
	move.l	d2,d0
	add.l	d0,d0
	add.l	d2,d0
	lsl.l	#2,d0
	move.l	ZC_FVERT(a5),a2
	add.l	d0,a2
	move.l	d7,d0				; the eye in the block: 12 bytes a block
	add.l	d0,d0
	add.l	d7,d0
	lsl.l	#2,d0
	move.l	ZC_QEYE(a5),a1
	add.l	d0,a1
	fsmove.s (a2),fp1			; x and y side by side (each its own chain, the same steps and the same
	fsmove.s 4(a2),fp0			; order of the sums: the same bits); z after, in fp1 (fp2 is the
	fssub.s	(a1),fp1			; caller's and not saved: fmovem.x loses bits on the 080)
	fssub.s	4(a1),fp0
	fsmul.s	(a4),fp1
	fsmul.s	4(a4),fp0
	fsadd.x	fp1,fp0
	fsmove.s 8(a2),fp1
	fssub.s	8(a1),fp1
	fsmul.s	8(a4),fp1
	fsadd.x	fp1,fp0
	move.l	ZC_FORD(a5),a4
	ftst.x	fp0
	fbnlt	cz_out
	bra	cz_nx				; turned away
cz_fc0:	move.l	ZC_FORD(a5),a4
cz_out:	btst	#7,d1				; PTF_MIRROR, not PTF_INBLK: C
	bne	cz_ret
	btst	#6,d1
	beq	cz_ret
	move.l	ZC_BLK(a5),a1			; its corners projected?
	move.l	(a1,d7.l*4),d2
	cmp.l	ZC_STAMP(a5),d2
	bne	cz_ret
	move.w	(a0),d2				; the outcodes: all in d0, any in d4; the four corners' indices
	ext.l	d2				; first, each in its own register (d7 a1 a2 free here: cf_hd makes
	movea.w	2(a0),a1			; them afresh)
	movea.w	4(a0),a2
	move.w	6(a0),d7
	ext.l	d7
	move.b	(a3,d2.l),d0
	move.b	(a3,a1.l),d6
	move.b	d0,d4
	and.b	d6,d0
	or.b	d6,d4
	move.b	(a3,a2.l),d6
	and.b	d6,d0
	or.b	d6,d4
	move.b	(a3,d7.l),d6
	and.b	d6,d0
	or.b	d6,d4
	moveq	#3,d6
	and.b	d0,d6
	bne	cz_nx
	btst	#0,d4
	bne.s	cz_o2
	moveq	#$3c,d6
	and.b	d0,d6
	bne	cz_nx
cz_o2:	moveq	#3,d6
	and.b	d4,d6
	bne	cz_ret
	moveq	#0,d2				; the material noted?
	move.w	20(a0),d2
	lsl.l	#4,d2
	move.l	ZC_MT(a5),a1
	add.l	d2,a1
	move.l	12(a1),d2
	lsr.l	#8,d2
	cmp.l	ZC_MTS(a5),d2
	bne	cz_ret
	move.l	C_NPOLY(a5),a2			; room?
	move.l	(a2),d2
	cmp.l	ZC_MAX(a5),d2
	bge	cz_ret
	addq.l	#1,(a2)				; pt_npoly, the object's count
	move.l	C_COUNT(a5),a2
	addq.l	#1,(a2)
	move.l	d2,d0				; the polygon: buf + 136 n
	lsl.l	#7,d0
	lsl.l	#3,d2
	add.l	d0,d2
	move.l	ZC_BUF(a5),a2
	add.l	d2,a2
	moveq	#0,d7
	move.b	18(a0),d7			; corners
	move.b	d7,4(a2)
	btst	#2,d1
	beq.s	cz_tex
	clr.l	(a2)
	move.b	#2,5(a2)
	move.b	22(a0),6(a2)
	bra.s	cz_corn
cz_tex:	move.l	(a1),(a2)
	move.b	15(a1),5(a2)
	clr.b	6(a2)
cz_corn:
	move.l	4(a1),d4			; su8
	move.l	8(a1),d6			; sv8
	addq.l	#8,a2
	move.w	(a0)+,d2			; (each corner's index read a pass ahead: the last read is the record's
	ext.l	d2				; next word, still inside it)
cz_c:	move.l	ZC_IX(a5),a1
	move.l	(a1,d2.l*4),(a2)+
	move.l	ZC_IY(a5),a1
	move.l	(a1,d2.l*4),(a2)+
	move.l	ZC_UV(a5),a1
	lea	(a1,d2.l*4),a1
	move.w	(a0)+,d2
	ext.l	d2
	move.w	(a1)+,d0
	ext.l	d0
	muls.l	d4,d0
	move.l	d0,(a2)+
	move.w	(a1),d0
	ext.l	d0
	muls.l	d6,d0
	move.l	d0,(a2)+
	subq.l	#1,d7
	bne.s	cz_c
cz_nx:	addq.l	#1,d5
	bra	cz_lp
cz_ret:	move.l	ZC_NFORD(a5),d4			; back to ci_faces68k's work on face d5
	move.l	ZC_STAMP(a5),d6
	bra	cf_hd

; ---------------------------------------------------------------------------------------------------------------
; void cd68k(const cd_ctx *x): main.c ci_draw past its tests (OS_PIASM=0: the C) -- the object's place in whole
; units, its heading's sines from the table, its radius, pi_pre68k, the d2 / carpet / ground notes, its slot, the
; blocks' order, and its turn O = camera x heading x tilt with the wheels', steer's and body's sines; then its faces
; (ci_faces, C)
CD_SO	equ	0
CD_MM	equ	4
CD_RECS	equ	8
CD_ID	equ	12
CD_PASS	equ	16
CD_CB	equ	20
CD_SIN	equ	24
CD_D2	equ	28
CD_CARP	equ	32
CD_GRND	equ	36
CD_ND2	equ	40
CD_GNOW	equ	44
CD_NPOLY equ	48
CD_NOBJ	equ	52
CD_CUR	equ	56
CD_OBJS	equ	60
CD_MAXOBJ equ	64
CD_FORD	equ	68
CD_MAXF	equ	72
CD_BLK	equ	76
CD_NB	equ	80
CD_NBALL equ	84
CD_IBLK	equ	88
CD_ORDER equ	92
CD_NFACE equ	96
CD_CARPV equ	100
CD_SEE	equ	104
CD_FACES equ	108
CD_CFC	equ	112
CD_STAMP equ	116
CD_STF	equ	120
CD_MTPH	equ	124
CD_VN	equ	128
CD_UV	equ	132
CD_IVERT equ	136
CD_CF68	equ	140
CD_TAKE	equ	144				; main.c see_take (or 0): pass 1 out of pass 0
; locals: pi_rec 0 (64), pi_pctx 64 (60), pi_octx 124 (44), ci_obj 168 (100)
DL_R	equ	0
DL_P	equ	64
DL_OC	equ	124
DL_OB	equ	168
DL_SZ	equ	268
; ci_obj
OB_T0	equ	36
OB_WC	equ	48
OB_BODY	equ	84
OB_EU	equ	88
OB_EV	equ	92
OB_POSE	equ	96

	xdef	_cd68k
	xdef	cd68k
_cd68k:
cd68k:
	movem.l	d2-d7/a2-a6,-(sp)
	lea	-DL_SZ(sp),sp
	move.l	DL_SZ+44+4(sp),a5
	cmp.l	#1,CD_PASS(a5)			; pass 1: the object's polygons made in pass 0 (see_take: 1 = done)
	bne.s	cd_go
	tst.l	CD_SEE(a5)			; no see-through faces: nothing in pass 1 (the notes below would only be
	beq	cd_x				; written again as pass 0 wrote them)
	move.l	CD_TAKE(a5),d0
	beq.s	cd_go
	move.l	CD_ID(a5),-(sp)
	move.l	d0,a0
	jsr	(a0)
	addq.l	#4,sp
	tst.l	d0
	bne	cd_x
cd_go:	move.l	CD_SO(a5),a4
	move.l	CD_SIN(a5),a3
	lea	DL_R(sp),a2			; the record: x y z rounded
	fmove.s	24(a4),fp0
	fmove.l	fp0,PR_X(a2)
	fmove.s	28(a4),fp0
	fmove.l	fp0,PR_Y(a2)
	fmove.s	32(a4),fp0
	fmove.l	fp0,PR_Z(a2)
	fmove.s	36(a4),fp0			; the heading's cos / sin
	bsr	cd_sc
	move.w	d0,PR_C(a2)
	move.w	d1,PR_S(a2)
	fmove.s	48(a4),fp0			; r = ceil(radius) + 64
	fintrz.x fp0,fp1
	fcmp.x	fp0,fp1
	fbge	cd_c1
	fadd.s	K_ONEF(pc),fp1
cd_c1:	fmove.l	fp1,d0
	add.l	#64,d0
	move.l	d0,PR_R(a2)
	lea	DL_P(sp),a0			; pi_pre68k
	move.l	a2,PP_REC(a0)
	move.l	CD_CB(a5),PP_CB(a0)
	move.l	a0,-(sp)
	bsr	pi_pre68k
	addq.l	#4,sp
	move.l	d0,d7				; k
	beq	cd_x
	move.l	CD_ID(a5),d6			; the notes for the depth test
	bmi.s	cd_n1
	cmp.l	CD_ND2(a5),d6
	bge.s	cd_n1
	move.l	DL_P+PP_D2(sp),d0
	lsl.l	#4,d0
	fmove.l	d0,fp0
	tst.l	d0
	bpl.s	cd_n0
	fadd.d	#4294967296.0,fp0
cd_n0:	move.l	CD_D2(a5),a0
	fmove.s	fp0,(a0,d6.l*4)
	move.l	CD_CARP(a5),a0
	move.b	CD_CARPV+3(a5),(a0,d6.l)
	move.l	CD_GRND(a5),a0
	move.b	CD_GNOW+3(a5),(a0,d6.l)
cd_n1:	cmp.l	#1,d7
	beq	cd_x
	cmp.l	#1,CD_PASS(a5)			; pass 1: only with see-through faces
	bne.s	cd_n2
	tst.l	CD_SEE(a5)
	beq	cd_x
cd_n2:	move.l	CD_NOBJ(a5),a0			; pt_begin_key(key, 1, pass)
	move.l	(a0),d0
	move.l	CD_CUR(a5),a1
	cmp.l	CD_MAXOBJ(a5),d0
	blt.s	cd_bk
	moveq	#-1,d1
	move.l	d1,(a1)
	bra	cd_x
cd_bk:	move.l	d0,(a1)
	addq.l	#1,(a0)
	move.l	d0,d1
	lsl.l	#4,d1
	move.l	CD_OBJS(a5),a1
	add.l	d1,a1
	move.l	CD_NPOLY(a5),a0
	move.l	(a0),(a1)+
	clr.l	(a1)+
	move.l	DL_P+PP_KEY(sp),d1
	sub.l	#$320,d1
	move.l	d1,(a1)+
	add.l	d0,d0
	add.l	CD_PASS(a5),d0
	move.l	d0,(a1)
	tst.l	CD_ORDER(a5)			; the blocks' order
	beq.s	cd_o2
	lea	DL_OC(sp),a0
	move.l	CD_BLK(a5),(a0)+
	move.l	CD_NB(a5),(a0)+
	move.l	CD_IBLK(a5),(a0)+
	move.l	DL_P+PP_E(sp),(a0)+
	move.l	DL_P+PP_E+4(sp),(a0)+
	move.l	DL_P+PP_E+8(sp),(a0)+
	move.l	CD_NBALL(a5),(a0)+
	move.l	CD_ORDER(a5),(a0)+
	move.l	CD_FORD(a5),(a0)+
	move.l	CD_MAXF(a5),(a0)+
	clr.l	(a0)
	pea	DL_OC(sp)
	bsr	pi_ford68k
	addq.l	#4,sp
	move.l	d0,d5				; nford
	bra.s	cd_ob
cd_o2:	moveq	#0,d5				; (no lists: the faces in order)
	move.l	CD_FORD(a5),a0
cd_o3:	cmp.l	CD_NFACE(a5),d5
	bge.s	cd_ob
	cmp.l	CD_MAXF(a5),d5
	bge.s	cd_ob
	move.w	d5,(a0)+
	addq.l	#1,d5
	bra.s	cd_o3
cd_ob:	lea	DL_OB(sp),a2			; O = the turn (pi_pre's R)
	lea	DL_P+PP_R(sp),a0
	moveq	#8,d1
cd_o4:	move.w	(a0)+,d0
	ext.l	d0
	move.l	d0,(a2)+
	dbra	d1,cd_o4
	lea	DL_OB(sp),a2
	fmove.s	40(a4),fp0			; tilted?
	ftst.x	fp0
	fbne	cd_t
	fmove.s	44(a4),fp0
	ftst.x	fp0
	fbeq	cd_t9
cd_t:	move.l	#16384,d2			; cp sp cr sr
	moveq	#0,d3
	move.l	#16384,d4
	moveq	#0,d6
	fmove.s	40(a4),fp0
	ftst.x	fp0
	fbeq	cd_t1
	bsr	cd_sc
	move.l	d0,d2
	move.l	d1,d3
cd_t1:	fmove.s	44(a4),fp0
	ftst.x	fp0
	fbeq	cd_t2
	bsr	cd_sc
	move.l	d0,d4
	move.l	d1,d6
cd_t2:	lea	-36(sp),sp			; Tl, then O = Tl applied to O
	move.l	d4,(sp)				; Tl[0] = cr, sr, 0
	move.l	d6,4(sp)
	clr.l	8(sp)
	move.l	d2,d0				; Tl[1] = -((cp sr) >> 14), (cp cr) >> 14, -sp
	muls.l	d6,d0
	asr.l	#8,d0
	asr.l	#6,d0
	neg.l	d0
	move.l	d0,12(sp)
	move.l	d2,d0
	muls.l	d4,d0
	asr.l	#8,d0
	asr.l	#6,d0
	move.l	d0,16(sp)
	move.l	d3,d0
	neg.l	d0
	move.l	d0,20(sp)
	move.l	d3,d0				; Tl[2] = -((sp sr) >> 14), (sp cr) >> 14, cp
	muls.l	d6,d0
	asr.l	#8,d0
	asr.l	#6,d0
	neg.l	d0
	move.l	d0,24(sp)
	move.l	d3,d0
	muls.l	d4,d0
	asr.l	#8,d0
	asr.l	#6,d0
	move.l	d0,28(sp)
	move.l	d2,32(sp)
	lea	-36(sp),sp			; Y = O
	lea	DL_OB+72(sp),a0
	move.l	sp,a1
	moveq	#8,d1
cd_t3:	move.l	(a0)+,(a1)+
	dbra	d1,cd_t3
	lea	DL_OB+72(sp),a2			; out[a][b] = (Tl[a][0] Y[0][b] + Tl[a][1] Y[1][b] + Tl[a][2] Y[2][b]) >> 14
	moveq	#0,d2				; a
cd_ta:	moveq	#0,d3				; b
cd_tb:	move.l	d2,d0
	mulu.l	#12,d0
	lea	36(sp,d0.l),a0			; Tl[a]
	lea	(sp,d3.l*4),a1			; Y[0][b]
	move.l	(a0),d0
	muls.l	(a1),d0
	move.l	4(a0),d1
	muls.l	12(a1),d1
	add.l	d1,d0
	move.l	8(a0),d1
	muls.l	24(a1),d1
	add.l	d1,d0
	asr.l	#8,d0
	asr.l	#6,d0
	move.l	d0,(a2)+
	addq.l	#1,d3
	cmp.l	#3,d3
	blt.s	cd_tb
	addq.l	#1,d2
	cmp.l	#3,d2
	blt.s	cd_ta
	lea	72(sp),sp
	lea	DL_OB(sp),a2
cd_t9:	move.l	DL_P+PP_V(sp),OB_T0(a2)		; T0 = v
	move.l	DL_P+PP_V+4(sp),OB_T0+4(a2)
	move.l	DL_P+PP_V+8(sp),OB_T0+8(a2)
	move.l	#16384,d0			; wc ws sc ss bpc bps brc brs drop body eu ev
	lea	OB_WC(a2),a0
	moveq	#3,d1
cd_d1:	move.l	d0,(a0)+
	clr.l	(a0)+
	dbra	d1,cd_d1
	clr.l	(a0)+
	clr.l	(a0)+
	clr.l	(a0)+
	clr.l	(a0)+
	move.l	4(a4),d0			; the pose
	sne	d1
	extb.l	d1
	neg.l	d1
	move.l	d1,OB_POSE(a2)
	tst.l	d0
	beq	cd_f
	move.l	d0,a6
	fmove.s	(a6),fp0			; the wheels' spin, the steer
	bsr	cd_sc
	move.l	d0,OB_WC(a2)
	move.l	d1,OB_WC+4(a2)
	fmove.s	4(a6),fp0
	bsr	cd_sc
	move.l	d0,OB_WC+8(a2)
	move.l	d1,OB_WC+12(a2)
	moveq	#0,d2				; body: any of pitch, roll, drop
	fmove.s	8(a6),fp0
	ftst.x	fp0
	fbne	cd_b1
	fmove.s	12(a6),fp0
	ftst.x	fp0
	fbne	cd_b1
	fmove.s	16(a6),fp0
	ftst.x	fp0
	fbeq	cd_b2
cd_b1:	moveq	#1,d2
cd_b2:	move.l	d2,OB_BODY(a2)
	beq.s	cd_b3
	fmove.s	8(a6),fp0
	bsr	cd_sc
	move.l	d0,OB_WC+16(a2)
	move.l	d1,OB_WC+20(a2)
	fmove.s	12(a6),fp0
	bsr	cd_sc
	move.l	d0,OB_WC+24(a2)
	move.l	d1,OB_WC+28(a2)
	fmove.s	16(a6),fp0
	fmove.l	fp0,OB_WC+32(a2)		; drop
cd_b3:	fsmove.s 24(a6),fp0			; eu = lrintf(env_u 65536), ev = lrintf(env_scroll 65536)
	fsmul.s	K_65536F(pc),fp0
	fmove.l	fp0,OB_EU(a2)
	fsmove.s 20(a6),fp0
	fsmul.s	K_65536F(pc),fp0
	fmove.l	fp0,OB_EV(a2)
cd_f:	move.l	CD_STAMP(a5),a0			; ci_faces: the object's stamp, the count, the phase
	addq.l	#1,(a0)
	move.l	(a0),d4
	move.l	CD_STF(a5),a0
	add.l	d5,(a0)
	move.l	CD_MTPH(a5),a0
	jsr	(a0)
	move.l	CD_CFC(a5),a1			; the context's per-object parts (ci_faces_frame the rest)
	move.l	CD_FORD(a5),(a1)		; fc: ford nford rec stamp see uv mt_stamp
	move.l	d5,4(a1)
	move.l	CD_RECS(a5),8(a1)
	move.l	d4,16(a1)
	moveq	#0,d1
	cmp.l	#1,CD_PASS(a5)
	bne.s	cd_f1
	moveq	#2,d1
cd_f1:	move.l	d1,20(a1)
	move.l	CD_UV(a5),52(a1)
	move.l	d0,60(a1)
	lea	DL_OB(sp),a0			; ob iblk ivert count blk mm pass id vn
	move.l	a0,188(a1)
	move.l	CD_IBLK(a5),192(a1)
	move.l	CD_IVERT(a5),196(a1)
	move.l	CD_CUR(a5),a0
	move.l	(a0),d0
	lsl.l	#4,d0
	add.l	CD_OBJS(a5),d0
	addq.l	#4,d0				; &objs[cur].count
	move.l	d0,240(a1)
	move.l	CD_BLK(a5),256(a1)
	move.l	CD_MM(a5),276(a1)
	move.l	CD_PASS(a5),280(a1)
	move.l	CD_ID(a5),284(a1)
	move.l	CD_VN(a5),288(a1)
	move.l	252(a1),a0			; mc: vn eu ev count
	move.l	CD_VN(a5),24(a0)
	move.l	DL_OB+OB_EU(sp),28(a0)
	move.l	DL_OB+OB_EV(sp),32(a0)
	move.l	d0,60(a0)
	move.l	a1,-(sp)
	move.l	CD_CF68(a5),a0
	jsr	(a0)
	addq.l	#4,sp
cd_x:	lea	DL_SZ(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts
; fp0 an angle (radians): d0 = cos, d1 = sin from the table (2.14): i = lrintf(a 8192 / 2 pi)
cd_sc:	fsmul.s	K_8192PI(pc),fp0
	fmove.l	fp0,d1
	move.l	d1,d0
	add.l	#2048,d0
	and.l	#8191,d0
	and.l	#8191,d1
	move.w	(a3,d0.l*2),d0
	ext.l	d0
	move.w	(a3,d1.l*2),d1
	ext.l	d1
	rts

; int cdt68k(cd_ctx *k, const cdt_ext *e, const scene_object *so, int id, int pass): main.c ci_draw's own part --
; whether the whole-number way takes this object (0: the floating way), the object's notes (texture phase, depth
; bias, the reflections' picture), the context's fields of this object, then cd68k (1).  2: a table of the mesh is
; not made yet (ci_ok, the face records of these materials, the corners' normals): the C makes it.
CE_ENVMAT	equ	0
CE_MATGEN	equ	4
CE_CLOCK	equ	8
CE_GNOW		equ	12
CE_TEXPH	equ	16
CE_ZBIAS	equ	20
CE_SPRITE	equ	24
CE_OVER		equ	28
CE_ENVPH	equ	32
CE_MAXV		equ	36
CE_MAXP		equ	40
SO_POSE		equ	4
SO_MAT		equ	8
SO_ZBIAS	equ	12
SO_OVER		equ	16
SO_SPRITE	equ	20
SO_PHASE	equ	72
MM_UV		equ	24
MM_CARPET	equ	50
MM_NVERT	equ	78
MM_NFACE	equ	82
MM_NBLOCK	equ	86
MM_VNORMAL	equ	90
MM_BLOCK	equ	94
MM_ORDER	equ	5374
MM_NBALL	equ	5378
MM_IVERT	equ	5390
MM_IVERTOK	equ	5394
MM_INORM	equ	5398
MM_PTREC	equ	5406
MM_PTGEN	equ	5410
MM_PTSEE	equ	5414
MM_IBLK		equ	6546
MM_IVNORM	equ	6550
MM_CIOK		equ	6554
	xdef	_cdt68k
	xdef	cdt68k
_cdt68k:
cdt68k:
	movem.l	a2-a4,-(sp)
	movem.l	12+4(sp),a2-a4			; a2 k, a3 e, a4 so
	move.l	(a4),d0				; the mesh
	beq	cdt_0
	move.l	d0,a1
	tst.l	SO_SPRITE(a4)
	bne	cdt_0
	tst.l	SO_MAT(a4)
	bne	cdt_0
	tst.l	SO_OVER(a4)
	bne	cdt_0
	tst.l	MM_IVERTOK(a1)
	beq	cdt_0
	tst.l	MM_INORM(a1)
	beq	cdt_0
	move.l	MM_NVERT(a1),d0
	cmp.l	CE_MAXV(a3),d0
	bgt	cdt_0
	moveq	#32,d0
	cmp.l	MM_NBLOCK(a1),d0
	blt	cdt_0
	move.l	SO_POSE(a4),d1
	beq.s	cdt_p
	move.l	d1,a0
	tst.l	32(a0)				; per_wheel
	bne	cdt_0
cdt_p:	move.l	CE_ENVMAT(a3),a0
	tst.l	(a0)
	bpl	cdt_0
	fmove.s	K_1E9(pc),fp1			; a sane place and size
	fabs.s	24(a4),fp0
	fcmp.x	fp1,fp0
	fbnlt	cdt_0
	fabs.s	28(a4),fp0
	fcmp.x	fp1,fp0
	fbnlt	cdt_0
	fabs.s	32(a4),fp0
	fcmp.x	fp1,fp0
	fbnlt	cdt_0
	fmove.s	48(a4),fp0
	fcmp.s	K_30000(pc),fp0
	fbnlt	cdt_0
	move.l	MM_CIOK(a1),d0			; the tables
	beq	cdt_2
	cmp.l	#1,d0
	bne	cdt_0
	move.l	MM_PTREC(a1),d0
	beq	cdt_2
	move.l	CE_MATGEN(a3),a0
	move.l	MM_PTGEN(a1),d0
	cmp.l	(a0),d0
	bne	cdt_2
	tst.l	MM_IVNORM(a1)
	bne.s	cdt_v
	tst.l	MM_VNORMAL(a1)
	bne	cdt_2
cdt_v:	move.l	SO_PHASE(a4),d0			; the object's notes
	bpl.s	cdt_ph
	move.l	CE_CLOCK(a3),a0
	move.l	(a0),d0
	bra.s	cdt_ph1
cdt_ph:	asr.l	#2,d0
cdt_ph1: and.l	#$3fff,d0
	move.l	CE_TEXPH(a3),a0
	move.l	d0,(a0)
	move.l	SO_ZBIAS(a4),d0
	fmove.s	SO_ZBIAS(a4),fp0
	fcmp.s	K_ZEROF(pc),fp0
	fbgt	cdt_zb
	move.l	#$3f800000,d0
cdt_zb:	move.l	CE_ZBIAS(a3),a0
	move.l	d0,(a0)
	move.l	CE_SPRITE(a3),a0
	clr.l	(a0)
	move.l	CE_OVER(a3),a0
	clr.l	(a0)
	moveq	#0,d0
	move.l	SO_POSE(a4),d1
	beq.s	cdt_e
	move.l	d1,a0
	move.l	28(a0),d0			; env
cdt_e:	move.l	CE_ENVPH(a3),a0
	move.l	d0,(a0)
	move.l	a4,CD_SO(a2)			; the context's fields of this object
	move.l	a1,CD_MM(a2)
	move.l	MM_PTREC(a1),CD_RECS(a2)
	move.l	12+16(sp),CD_ID(a2)
	move.l	12+20(sp),CD_PASS(a2)
	move.l	CE_GNOW(a3),a0
	move.l	(a0),CD_GNOW(a2)
	lea	MM_BLOCK(a1),a0
	move.l	a0,CD_BLK(a2)
	move.l	MM_NBLOCK(a1),d0
	cmp.l	CE_MAXP(a3),d0
	blt.s	cdt_nb
	move.l	CE_MAXP(a3),d0
cdt_nb:	move.l	d0,CD_NB(a2)
	move.l	MM_NBALL(a1),CD_NBALL(a2)
	move.l	MM_IBLK(a1),CD_IBLK(a2)
	move.l	MM_ORDER(a1),CD_ORDER(a2)
	move.l	MM_NFACE(a1),CD_NFACE(a2)
	move.l	MM_CARPET(a1),CD_CARPV(a2)
	move.l	MM_PTSEE(a1),CD_SEE(a2)
	move.l	MM_IVNORM(a1),CD_VN(a2)
	move.l	MM_UV(a1),CD_UV(a2)
	move.l	MM_IVERT(a1),CD_IVERT(a2)
	move.l	a2,-(sp)
	bsr	cd68k
	addq.l	#4,sp
	moveq	#1,d0
	movem.l	(sp)+,a2-a4
	rts
cdt_0:	moveq	#0,d0
	movem.l	(sp)+,a2-a4
	rts
cdt_2:	moveq	#2,d0
	movem.l	(sp)+,a2-a4
	rts

; void car68k(const cl_ctx *c): render_scene's loop over the cars, props and moving scenery -- cdt68k for each but
; the hidden one (the player's car from inside); those it does not take (0 / 2) through the C's draw_object
CL_CARS		equ	0
CL_N		equ	4
CL_HIDE		equ	8
CL_ID0		equ	12
CL_PASS		equ	16
CL_CAM		equ	20
CL_K		equ	24
CL_E		equ	28
CL_SLOW		equ	32
	xdef	_car68k
	xdef	car68k
_car68k:
car68k:
	movem.l	d2-d3/a2/a5,-(sp)
	move.l	16+4(sp),a5
	move.l	CL_CARS(a5),a2
	moveq	#0,d2
cl_l:	cmp.l	CL_N(a5),d2
	bge.s	cl_x
	cmp.l	CL_HIDE(a5),a2
	beq.s	cl_n
	move.l	CL_ID0(a5),d3
	add.l	d2,d3
	move.l	CL_PASS(a5),-(sp)
	move.l	d3,-(sp)
	move.l	a2,-(sp)
	move.l	CL_E(a5),-(sp)
	move.l	CL_K(a5),-(sp)
	bsr	cdt68k
	lea	20(sp),sp
	cmp.l	#1,d0
	beq.s	cl_n
	move.l	CL_CAM(a5),-(sp)
	move.l	CL_PASS(a5),-(sp)
	move.l	d3,-(sp)
	move.l	a2,-(sp)
	move.l	CL_SLOW(a5),a0
	jsr	(a0)
	lea	16(sp),sp
cl_n:	addq.l	#1,d2
	lea	76(a2),a2
	bra.s	cl_l
cl_x:	movem.l	(sp)+,d2-d3/a2/a5
	rts

	cnop	0,4
K_ONEF:	dc.l	$3f800000
K_ZEROF: dc.l	$00000000
K_1E9:	dc.l	$4e6e6b28			; 1e9f
K_30000: dc.l	$46ea6000
K_65536F: dc.l	$47800000
K_8192PI: dc.l	$44a2f983			; 8192.0f / 6.28318531f

; ---------------------------------------------------------------------------------------------------------------
; void pf68k(pi_sctx *c, int fi): main.c pi_face_c -- a piece's face the quick loop leaves: its material (noted if
; not; a flat colour or not drawn), the pass, its corners, its block projected, the whole-number cull, the corners'
; outcodes; uncut its polygon (pt_face: C), cut by a plane the floating way (draw_poly_view)
S_CULLX	equ	412
XS_OBJS	equ	420
XS_MAT	equ	424
XS_NMAT	equ	428
XS_FLAT	equ	432
XS_FACEW	equ	436
XS_POLY	equ	440
XS_SEEIN equ	444
FC_CULL	equ	24
ME_NC	equ	4
ME_IDX	equ	8
ME_MAT	equ	16
ME_COL	equ	20
ME_UV	equ	24
ME_IVERT equ	5390
ME_INORM equ	5398
ME_FBLK	equ	5402
; locals: 0 poly pointer, 4 vtx[4] (80)
FL_P	equ	0
FL_V	equ	4
FL_LOC	equ	84

	xdef	_pf68k
	xdef	pf68k
_pf68k:
pf68k:
	movem.l	d2-d7/a2-a6,-(sp)
	lea	-FL_LOC(sp),sp
	move.l	FL_LOC+44+4(sp),a5		; c
	move.l	FL_LOC+44+8(sp),d7		; fi
	move.l	S_O(a5),d0			; mm
	mulu.l	#76,d0
	move.l	XS_OBJS(a5),a0
	move.l	(a0,d0.l),a4
	move.l	ME_NC(a4),a0			; nc
	moveq	#0,d6
	move.b	(a0,d7.l),d6
	cmp.l	#3,d6
	blt	pf_x
	move.l	ME_MAT(a4),a0			; mi = material / 16 (C's division)
	move.l	(a0,d7.l*4),d0
	divsl.l	#16,d0:d0
	tst.l	d0
	bmi	pf_x
	cmp.l	XS_NMAT(a5),d0
	bge	pf_x
	move.l	d0,d5				; mi
	lsl.l	#4,d0				; noted?
	move.l	S_FC+FC_MT(a5),a0
	move.l	12(a0,d0.l),d1
	lsr.l	#8,d1
	cmp.l	S_FC+FC_MTST(a5),d1
	beq.s	pf_1
	move.l	d5,-(sp)
	move.l	S_NOTE(a5),a0
	jsr	(a0)
	addq.l	#4,sp
pf_1:	move.l	d5,d0				; mat
	mulu.l	#1048,d0
	move.l	XS_MAT(a5),a3
	add.l	d0,a3
	move.l	XS_FLAT(a5),a6			; g_flat_colour = -1
	moveq	#-1,d0
	move.l	d0,(a6)
	tst.l	16(a3)				; untextured: a flat colour, or not drawn
	bne.s	pf_2
	cmp.l	#128,(a3)
	bne	pf_x
	move.l	ME_COL(a4),a0
	move.w	(a0,d7.l*2),d0
	and.l	#255,d0
	move.l	d0,(a6)
pf_2:	tst.l	XS_SEEIN(a5)			; see_inline: every face in pass 0, none in pass 1
	beq.s	pf_2s
	tst.l	S_PASS(a5)
	bne	pf_xf
	bra.s	pf_2c
pf_2s:	moveq	#0,d0				; (type == 224) == (pass == 1)?
	cmp.l	#224,(a3)
	seq	d0
	moveq	#0,d1
	cmp.l	#1,S_PASS(a5)
	seq	d1
	cmp.b	d0,d1
	bne	pf_xf
pf_2c:
	move.l	ME_IDX(a4),a2			; its corners
	move.l	d7,d0
	lsl.l	#4,d0
	add.l	d0,a2
	tst.l	(a2)
	bmi	pf_xf
	tst.l	4(a2)
	bmi	pf_xf
	tst.l	8(a2)
	bmi	pf_xf
	cmp.l	#3,d6
	ble.s	pf_3
	tst.l	12(a2)
	bmi	pf_xf
pf_3:	move.l	ME_FBLK(a4),a0			; its block projected
	moveq	#0,d0
	move.b	(a0,d7.l),d0
	move.l	S_BLKAT(a5),a0
	move.l	S_STAMP(a5),d1
	cmp.l	(a0,d0.l*4),d1
	beq.s	pf_4
	bsr	pf_proj
pf_4:	tst.l	S_CULLX(a5)			; the cull: (l0 - E) . n < 0
	beq.s	pf_5
	move.l	ME_INORM(a4),a0
	move.l	d7,d0
	mulu.l	#6,d0
	add.l	d0,a0				; n
	move.w	(a0),d1
	or.w	2(a0),d1
	or.w	4(a0),d1
	beq.s	pf_5
	move.l	(a2),d0				; l0
	mulu.l	#6,d0
	move.l	ME_IVERT(a4),a1
	add.l	d0,a1
	move.w	(a1),d0
	ext.l	d0
	sub.l	S_FC+FC_E(a5),d0
	move.w	(a0),d1
	ext.l	d1
	muls.l	d1,d0
	move.w	2(a1),d2
	ext.l	d2
	sub.l	S_FC+FC_E+4(a5),d2
	move.w	2(a0),d1
	ext.l	d1
	muls.l	d1,d2
	add.l	d2,d0
	move.w	4(a1),d2
	ext.l	d2
	sub.l	S_FC+FC_E+8(a5),d2
	move.w	4(a0),d1
	ext.l	d1
	muls.l	d1,d2
	add.l	d2,d0
	bmi	pf_xf
pf_5:	moveq	#$3f,d2				; all, any
	moveq	#0,d3
	move.l	S_SOUT(a5),a0
	move.l	d6,d1
	subq.l	#1,d1
	move.l	a2,a1
pf_o:	move.l	(a1)+,d0
	move.b	(a0,d0.l),d0
	and.b	d0,d2
	or.b	d0,d3
	dbra	d1,pf_o
	moveq	#3,d0
	and.l	d2,d0
	bne	pf_xf
	btst	#0,d3
	bne.s	pf_6
	moveq	#$3c,d0
	and.l	d2,d0
	bne	pf_xf
pf_6:	move.l	4(a3),d4			; su8, sv8
	lsl.l	#8,d4
	move.l	8(a3),d5
	lsl.l	#8,d5
	moveq	#3,d0
	and.l	d3,d0
	bne	pf_cut
	pea	FL_P(sp)			; uncut: its polygon
	move.l	d6,-(sp)
	move.l	a3,-(sp)
	move.l	XS_FACEW(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	move.l	FL_P(sp),d0
	beq	pf_xf
	move.l	d0,a1
	lea	8(a1),a1			; its corners: x y u v
	move.l	d6,d1
	subq.l	#1,d1
pf_c:	move.l	(a2)+,d0			; vi
	move.l	S_SIX(a5),a0
	move.l	(a0,d0.l*4),(a1)+
	move.l	S_SIY(a5),a0
	move.l	(a0,d0.l*4),(a1)+
	move.l	S_FC+FC_UV(a5),a0
	move.w	(a0,d0.l*4),d2
	ext.l	d2
	muls.l	d4,d2
	move.l	d2,(a1)+
	move.w	2(a0,d0.l*4),d2
	ext.l	d2
	muls.l	d5,d2
	move.l	d2,(a1)+
	dbra	d1,pf_c
	bra	pf_xf
pf_cut:	lea	FL_V(sp),a1			; cut by a plane: the corners as floats, draw_poly_view
	move.l	d6,d1
	subq.l	#1,d1
	move.l	a2,a6				; (a6 no longer &flat: reloaded below)
pf_v:	move.l	(a6)+,d0			; vi
	move.l	d0,d2
	mulu.l	#12,d2
	move.l	S_SV(a5),a0
	add.l	d2,a0
	fmove.l	(a0)+,fp0
	fmove.s	fp0,(a1)+
	fmove.l	(a0)+,fp0
	fmove.s	fp0,(a1)+
	fmove.l	(a0),fp0
	fmove.s	fp0,(a1)+
	move.l	S_FC+FC_UV(a5),a0
	move.w	(a0,d0.l*4),d2
	ext.l	d2
	muls.l	d4,d2
	fsmove.l d2,fp0
	fsmul.s	K_I65536(pc),fp0
	fmove.s	fp0,(a1)+
	move.w	2(a0,d0.l*4),d2
	ext.l	d2
	muls.l	d5,d2
	fsmove.l d2,fp0
	fsmul.s	K_I65536(pc),fp0
	fmove.s	fp0,(a1)+
	dbra	d1,pf_v
	move.l	S_O(a5),-(sp)			; draw_poly_view(in, nc, mat, id)
	move.l	a3,-(sp)
	move.l	d6,-(sp)
	pea	FL_V+12(sp)
	move.l	XS_POLY(a5),a0
	jsr	(a0)
	lea	16(sp),sp
pf_xf:	move.l	XS_FLAT(a5),a0			; g_flat_colour = -1
	moveq	#-1,d0
	move.l	d0,(a0)
pf_x:	lea	FL_LOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts
; the block d0 projected (pi_proj): through the piece's iblk words 6, 7
pf_proj:
	movem.l	d2-d7/a2-a4,-(sp)
	move.l	S_BLKAT(a5),a0
	move.l	S_STAMP(a5),(a0,d0.l*4)
	move.l	S_O(a5),d1
	lsl.l	#6,d1
	move.l	S_RECS(a5),a3
	add.l	d1,a3				; the pi_rec
	lsl.l	#5,d0
	move.l	PR_IBLK(a3),a0
	add.l	d0,a0
	move.l	24(a0),d0			; vbase
	move.l	28(a0),d1			; vcount
	lea	S_G(a5),a1
	move.l	d1,G_N(a1)
	move.l	S_STV(a5),a0
	add.l	d1,(a0)
	move.l	d0,d1
	add.l	d1,d1
	add.l	d0,d1
	add.l	d1,d1
	add.l	PR_IVERT(a3),d1
	move.l	d1,G_V(a1)
	move.l	d0,d1
	lsl.l	#2,d1
	move.l	S_SIX(a5),a0
	add.l	d1,a0
	move.l	a0,G_IX(a1)
	move.l	S_SIY(a5),a0
	add.l	d1,a0
	move.l	a0,G_IY(a1)
	move.l	S_SOUT(a5),a0
	add.l	d0,a0
	move.l	a0,G_OUT(a1)
	move.l	d1,d0
	add.l	d1,d1
	add.l	d0,d1
	move.l	S_SV(a5),a0
	add.l	d1,a0
	move.l	a0,G_VV(a1)
	move.l	a1,-(sp)
	move.l	S_GEO(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	movem.l	(sp)+,d2-d7/a2-a4
	rts

	cnop	0,4
K_I65536: dc.l	$37800000			; 1.0f / 65536.0f

; (the 68080: this file's code padded to a fixed size, so that the code linked after it -- game_68k.s and the C --
; keeps its place in the instruction cache when this file changes: measured on the V1200, a shift of a few hundred
; bytes there cost the pieces' pass ~0.3 ms; at this size and at 4 KB less it did not)
PI_HOT	equ	$2c0c
	ifd	V080
	dcb.b	PI_HOT-(*-pi_code0),0
	endc

; the LOD thresholds (pieces' key -6000 / -8000, the rest's -d -4000 / -7000; main.c lod_thresholds: at 320x200
; the half -- an object at d is as big as at 2d in 640x400)
	section	data,data
	xdef	_pi_lodt
	xdef	pi_lodt
	cnop	0,4
_pi_lodt:
pi_lodt:	dc.l	-6000,-8000,-4000,-7000

	section	bss,bss
ps_pend:	ds.l	1				; pi_pass68k: the last skipped piece of pass 1 whose notes are not written yet
