; game_68k.s - THE RACE'S LOGIC in vasm (C references in main.c; OS_TUASM=0 etc.).  Floating sums as gcc compiles
; the C: every operation rounded to single (fsadd/fssub/fsmul), the same operands; two-term sums only (their order
; is exact either way).  vasmm68k_mot -quiet -no-opt -m68060

	section	code,code
	ifd	V080
	xref	raster_sm8
	endif

; int tu68k(const tu_ctx *c): main.c track_under -- the face of the track under (x, y): the nine cells round the
; point, each cell's drivable pieces in stored order, a piece looked at when the point is in its circle, the point
; turned into its frame and moved up to `tries` times by `step` until a face of its ground list holds it (in the
; face's box, all edges' cross products of one sign); with want_height its height and normal.
; tu_ctx: 0 x, 4 y (floats), 8 want_height, 12 out (float *), 16 scene objects, 20 cell_first, 24 cell_obj,
;         28 cos, 32 sin (floats a piece), 36 tries, 40 step (float), 44 boxes on, 48 &g_under_obj, 52 g_under_n,
;         56 offsetof(mesh, coll_kbox): the boxes as whole numbers that compare as the floats (no FPU for them)
; scene_object (76 bytes): 0 m, 24 x, 28 y, 32 z.  mesh: 0 vert (12 bytes), 4 ncorner (bytes), 8 idx (16 bytes a
; face), 12 normal (12 bytes), 54 bound_r, 58 bound_cx, 62 bound_cz, 66 ncoll, 70 coll (words), 74 coll_box (16)
TU_X	equ	0
TU_Y	equ	4
TU_WANT	equ	8
TU_OUT	equ	12
TU_OBJ	equ	16
TU_CF	equ	20
TU_CO	equ	24
TU_COS	equ	28
TU_SIN	equ	32
TU_TRY	equ	36
TU_STEP	equ	40
TU_BOX	equ	44
TU_UOBJ	equ	48
TU_UN	equ	52
TU_KB	equ	56
TU_C9F	equ	60				; the nine cells' pieces as one list a cell (0: not made), main.c under_index9:
TU_C9O	equ	64				; first (65537), the pieces -- in the same order, less those whose circle the cell misses
L_CX	equ	0
L_CY	equ	4
L_CI	equ	8
L_AT	equ	12
L_END	equ	16
L_NC	equ	20
L_NX	equ	24
L_NY	equ	28
L_NZ	equ	32
L_KX	equ	36
L_KZ	equ	40
L_KB	equ	44
L_CO	equ	48				; the list L_AT .. L_END index
L_LOC	equ	52

	xdef	_tu68k
	xdef	tu68k
_tu68k:
tu68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-L_LOC(sp),sp
	move.l	L_LOC+72+48(sp),a6
	fintrz.s TU_X(a6),fp0			; the cell: ((int)x + $100000) >> 13
	fmove.l	fp0,d0
	add.l	#$100000,d0
	asr.l	#8,d0
	asr.l	#5,d0
	move.l	d0,L_CX(sp)
	fintrz.s TU_Y(a6),fp0
	fmove.l	fp0,d0
	add.l	#$100000,d0
	asr.l	#8,d0
	asr.l	#5,d0
	move.l	d0,L_CY(sp)
	clr.l	L_CI(sp)
	move.l	TU_C9F(a6),d1			; the nine cells' list of the point's cell (the cell inside the grid)
	beq.s	tu_cell
	cmp.l	#255,d0
	bhi.s	tu_cell
	move.l	L_CX(sp),d2
	cmp.l	#255,d2
	bhi.s	tu_cell
	lsl.l	#8,d0
	add.l	d2,d0
	move.l	d1,a0
	move.l	(a0,d0.l*4),L_AT(sp)
	move.l	4(a0,d0.l*4),L_END(sp)
	move.l	TU_C9O(a6),L_CO(sp)
	moveq	#8,d0				; (the last cell: when the list ends, the end)
	move.l	d0,L_CI(sp)
	bra.s	tu_obj
tu_cell:
	move.l	L_CI(sp),d0
	cmp.l	#9,d0
	bge	tu_none
	lea	tu_tab(pc),a0
	move.b	(a0,d0.l*2),d1
	ext.w	d1
	ext.l	d1
	move.b	1(a0,d0.l*2),d2
	ext.w	d2
	ext.l	d2
	add.l	L_CX(sp),d1			; kx
	add.l	L_CY(sp),d2			; ky
	cmp.l	#255,d1
	bhi	tu_ncell			; (unsigned: < 0 too)
	cmp.l	#255,d2
	bhi	tu_ncell
	lsl.l	#8,d2
	add.l	d1,d2
	move.l	TU_CF(a6),a0
	move.l	(a0,d2.l*4),L_AT(sp)
	move.l	4(a0,d2.l*4),L_END(sp)
	move.l	TU_CO(a6),L_CO(sp)
tu_obj:	move.l	L_AT(sp),d0
	cmp.l	L_END(sp),d0
	bge	tu_ncell
	addq.l	#1,L_AT(sp)
	move.l	L_CO(sp),a0
	move.l	(a0,d0.l*4),d7			; o
	move.l	d7,d0
	mulu.l	#76,d0
	move.l	TU_OBJ(a6),a5
	add.l	d0,a5				; so
	move.l	(a5),a4				; mm
	fsmove.s TU_X(a6),fp6			; dx, dy
	fssub.s	24(a5),fp6
	fsmove.s TU_Y(a6),fp7
	fssub.s	28(a5),fp7
	fsmove.x fp6,fp0			; in the piece's circle?  bx^2 + by^2 > r^2 -> not
	fssub.s	58(a4),fp0
	fsmove.x fp7,fp1
	fssub.s	62(a4),fp1
	fsmul.x	fp0,fp0
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fsmove.s 54(a4),fp1
	fsmul.x	fp1,fp1
	fcmp.x	fp1,fp0
	fbgt	tu_obj
	move.l	TU_COS(a6),a0
	fsmove.s (a0,d7.l*4),fp4		; c
	move.l	TU_SIN(a6),a0
	fsmove.s (a0,d7.l*4),fp5		; sn
	fsmove.x fp6,fp2			; lx = dx c + dy sn
	fsmul.x	fp4,fp2
	fsmove.x fp7,fp0
	fsmul.x	fp5,fp0
	fsadd.x	fp0,fp2
	fsmove.x fp7,fp3			; lz = -dx sn + dy c
	fsmul.x	fp4,fp3
	fsmove.x fp6,fp0
	fsmul.x	fp5,fp0
	fssub.x	fp0,fp3
	move.l	TU_KB(a6),d0
	move.l	(a4,d0.l),L_KB(sp)		; the boxes' whole numbers (0: the floats)
	move.l	TU_TRY(a6),d4
tu_try:	subq.l	#1,d4
	bmi	tu_obj
	fmove.s	fp2,d0				; lx, lz as such whole numbers: the bits, a negative one 0x80000000 - bits
	tst.l	d0
	bpl.s	tu_k1
	bclr	#31,d0
	neg.l	d0
tu_k1:	move.l	d0,L_KX(sp)
	fmove.s	fp3,d0
	tst.l	d0
	bpl.s	tu_k2
	bclr	#31,d0
	neg.l	d0
tu_k2:	move.l	d0,L_KZ(sp)
	move.l	66(a4),d5			; ncoll
	moveq	#0,d6				; k
tu_face:
	cmp.l	d5,d6
	bge	tu_step
	tst.l	TU_BOX(a6)			; the boxes as whole numbers (the usual case): a quick scan from k with the
	beq.s	tu_sf				; list and the boxes stepped by pointers, KX / KZ in registers, to the next
	move.l	L_KB(sp),d1			; face inside its box (then the edges as before: tu_nb)
	beq.s	tu_sf
	move.l	70(a4),a3
	lea	(a3,d6.l*2),a3
	move.l	d6,d0
	lsl.l	#4,d0
	move.l	d1,a0
	add.l	d0,a0
	move.l	L_KX(sp),d1
	move.l	L_KZ(sp),d2
tu_fq:	move.w	(a3)+,d3
	ext.l	d3
	bmi.s	tu_fqn
	cmp.l	(a0),d1
	blt.s	tu_fqn
	cmp.l	4(a0),d1
	bgt.s	tu_fqn
	cmp.l	8(a0),d2
	blt.s	tu_fqn
	cmp.l	12(a0),d2
	ble	tu_nb
tu_fqn:	lea	16(a0),a0
	addq.l	#1,d6
	cmp.l	d5,d6
	blt.s	tu_fq
	bra	tu_step
tu_sf:	move.l	70(a4),a3
	move.w	(a3,d6.l*2),d3			; f
	ext.l	d3
	bmi	tu_fn
	tst.l	TU_BOX(a6)			; outside the face's box: on none of it
	beq	tu_nb
	move.l	d6,d0
	lsl.l	#4,d0
	move.l	L_KB(sp),d1
	beq.s	tu_fb
	move.l	d1,a0
	add.l	d0,a0
	move.l	L_KX(sp),d1
	cmp.l	(a0),d1
	blt	tu_fn
	cmp.l	4(a0),d1
	bgt	tu_fn
	move.l	L_KZ(sp),d1
	cmp.l	8(a0),d1
	blt	tu_fn
	cmp.l	12(a0),d1
	bgt	tu_fn
	bra.s	tu_nb
tu_fb:	move.l	74(a4),a2
	lea	(a2,d0.l),a0
	fcmp.s	(a0),fp2
	fblt	tu_fn
	fcmp.s	4(a0),fp2
	fbgt	tu_fn
	fcmp.s	8(a0),fp3
	fblt	tu_fn
	fcmp.s	12(a0),fp3
	fbgt	tu_fn
tu_nb:	move.l	4(a4),a0			; the edges: d1 bit 0 a positive cross product, bit 1 a negative one
	moveq	#0,d0
	move.b	(a0,d3.l),d0
	move.l	d0,L_NC(sp)
	move.l	8(a4),a1
	move.l	d3,d0
	lsl.l	#4,d0
	add.l	d0,a1				; idx[f]
	move.l	(a4),a0				; vert
	moveq	#0,d1
	moveq	#0,d0				; j
tu_ej:	cmp.l	L_NC(sp),d0
	bge	tu_ed
	move.l	(a1,d0.l*4),d2			; a = vert[idx[j]]
	bmi	tu_fn
	mulu.l	#12,d2
	lea	(a0,d2.l),a2
	move.l	d0,d2				; b = vert[idx[j + 1 < nc ? j + 1 : 0]]
	addq.l	#1,d2
	cmp.l	L_NC(sp),d2
	blt.s	tu_e1
	moveq	#0,d2
tu_e1:	move.l	(a1,d2.l*4),d2
	bmi	tu_fn
	mulu.l	#12,d2
	lea	(a0,d2.l),a3
	fsmove.s (a3),fp0			; cr = (b.x - a.x)(lz - a.z) - (b.z - a.z)(lx - a.x)
	fssub.s	(a2),fp0
	fsmove.x fp3,fp1
	fssub.s	8(a2),fp1
	fsmul.x	fp1,fp0
	fsmove.s 8(a3),fp1
	fssub.s	8(a2),fp1
	fsmove.x fp2,fp6
	fssub.s	(a2),fp6
	fsmul.x	fp6,fp1
	fssub.x	fp1,fp0
	ftst.x	fp0
	fbgt	tu_ep
	fblt	tu_en
	bra.s	tu_ex
tu_ep:	bset	#0,d1
	bra.s	tu_ex
tu_en:	bset	#1,d1
tu_ex:	addq.l	#1,d0
	bra	tu_ej
tu_ed:	cmp.b	#3,d1				; both signs: not on it
	beq	tu_fn
	move.l	TU_UOBJ(a6),a0			; on this face
	move.l	d7,(a0)
	tst.l	TU_WANT(a6)
	beq	tu_yes
	move.l	12(a4),a0			; the normal x 16384, rounded (lroundf: half away from 0)
	move.l	d3,d0
	mulu.l	#12,d0
	add.l	d0,a0
	fsmove.s (a0),fp0
	bsr	tu_lr
	move.l	d0,L_NX(sp)
	fsmove.s 4(a0),fp0
	bsr	tu_lr
	move.l	d0,L_NY(sp)
	fsmove.s 8(a0),fp0
	bsr	tu_lr
	move.l	d0,L_NZ(sp)
	tst.l	L_NY(sp)
	beq	tu_fn				; standing on edge: the next face
	move.l	8(a4),a1			; v0
	move.l	d3,d0
	lsl.l	#4,d0
	move.l	(a1,d0.l),d0
	mulu.l	#12,d0
	move.l	(a4),a0
	add.l	d0,a0
	fintrz.x fp2,fp0			; num = ((int)lx - (int)v0.x) nx + ((int)lz - (int)v0.z) nz
	fmove.l	fp0,d0
	fintrz.s (a0),fp0
	fmove.l	fp0,d1
	sub.l	d1,d0
	muls.l	L_NX(sp),d0
	fintrz.x fp3,fp0
	fmove.l	fp0,d1
	fintrz.s 8(a0),fp0
	fmove.l	fp0,d2
	sub.l	d2,d1
	muls.l	L_NZ(sp),d1
	add.l	d1,d0
	neg.l	d0				; -num / ny (towards 0)
	divs.l	L_NY(sp),d0
	fsmove.l d0,fp1				; out = (so.z + v0.y) + (float)
	fsmove.s 32(a5),fp0
	fsadd.s	4(a0),fp0
	fsadd.x	fp1,fp0
	move.l	TU_OUT(a6),a0
	fmove.s	fp0,(a0)
	move.l	TU_UN(a6),a0			; the normal in world axes: nx c - nz sn, nx sn + nz c, ny
	fsmove.l L_NX(sp),fp0
	fsmul.x	fp4,fp0
	fsmove.l L_NZ(sp),fp1
	fsmul.x	fp5,fp1
	fssub.x	fp1,fp0
	fmove.s	fp0,(a0)
	fsmove.l L_NX(sp),fp0
	fsmul.x	fp5,fp0
	fsmove.l L_NZ(sp),fp1
	fsmul.x	fp4,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,4(a0)
	fsmove.l L_NY(sp),fp0
	fmove.s	fp0,8(a0)
tu_yes:	moveq	#1,d0
	bra.s	tu_ret
tu_fn:	addq.l	#1,d6
	bra	tu_face
tu_step:
	fsadd.s	TU_STEP(a6),fp2			; tries++, lx += step, lz += step
	fsadd.s	TU_STEP(a6),fp3
	bra	tu_try
tu_ncell:
	addq.l	#1,L_CI(sp)
	bra	tu_cell
tu_none:
	moveq	#0,d0
tu_ret:	lea	L_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; fp0 (a float) x 16384, rounded half away from 0 (lroundf), in d0: the sum with 1/2 in extended precision is exact
tu_lr:	fsmul.s	tu_k16(pc),fp0
	ftst.x	fp0
	fblt	tu_lrn
	fadd.s	tu_kh(pc),fp0
	bra.s	tu_lrt
tu_lrn:	fsub.s	tu_kh(pc),fp0
tu_lrt:	fintrz.x fp0,fp0
	fmove.l	fp0,d0
	rts

	cnop	0,4
tu_k16:	dc.l	$46800000			; 16384.0f
tu_kh:	dc.l	$3f000000			; 0.5f
tu_tab:	dc.b	0,0, 1,0, -1,0, 0,1, 0,-1, 1,1, -1,-1, 1,-1, -1,1

; ---------------------------------------------------------------------------------------------------------------
; void opp68k(const oc_ctx *c): main.c opponents_step (opponents_step_c is the reference, OS_OPPASM=c compares them
; to the bit): for each opponent the lap ahead, its markers and speed, the way along its curve, the push from a
; collision, the lean in a bend, the push dying away, then its place (opp_place: the curve, the heading, the ground
; under it and the tilt, off the road, the crash and its tumbling or spin, the object), and the running order.
; Every float operation as gcc compiles the C (one rounding to single each); atan2f, sinf/cosf, track_under and
; the wheels / shadow through the context's C functions.
O_NODE	equ	0
O_HALF	equ	4
O_U	equ	8
O_SPEED	equ	12
O_OFFX	equ	16
O_OFFY	equ	20
O_AGE	equ	24
O_SHOVE	equ	28
O_SHX	equ	32
O_SHY	equ	36
O_SPIN	equ	40
O_CRASH	equ	44
O_BNC	equ	48
O_VY	equ	52
O_UP	equ	56
O_TIP	equ	60
O_TURN	equ	64
O_LEAN	equ	68
O_TIPR	equ	72
O_TURNR	equ	76
O_LEANR	equ	80
O_PREVS	equ	84
O_PREVY	equ	88
O_BODY	equ	92
O_X	equ	96
O_Y	equ	100
O_Z	equ	104
O_YAW	equ	108
O_PITCH	equ	112
O_ROLL	equ	116
O_MARK	equ	120
O_MKC	equ	124
O_MKL	equ	128
O_SEEN	equ	132
O_PROG	equ	196
O_RANK	equ	200
O_OBJ	equ	204
O_SIZE	equ	208
OC_OPP	equ	0
OC_N	equ	4
OC_SPEC	equ	8
OC_SPL	equ	12
OC_GO	equ	16
OC_RANK	equ	20
OC_LAPS	equ	24
OC_PROG	equ	28
OC_LAPPED equ	32
OC_NMARK equ	36
OC_MARK	equ	40
OC_D4F	equ	44
OC_D4C	equ	48
OC_D60	equ	52
OC_D79	equ	56
OC_D97	equ	60
OC_POSE	equ	64
OC_UN	equ	68
OC_ATAN2 equ	72
OC_SINCOS equ	76
OC_UNDER equ	80
OC_TAIL	equ	84
OC_LIV	equ	88
OC_CLOCK equ	92
; locals (a6)
OL_A	equ	0
OL_B	equ	8
OL_C	equ	16
OL_DER	equ	24
OL_POS	equ	32
OL_Z	equ	40
OL_S	equ	44
OL_CO	equ	48
OL_LEFT	equ	52
OL_GUARD equ	56
OL_AHEAD equ	60
OL_LOC	equ	64

	xdef	_opp68k
	xdef	opp68k
_opp68k:
opp68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-OL_LOC(sp),sp
	move.l	sp,a6
	move.l	OL_LOC+72+48(sp),a5
	moveq	#0,d7				; k
op_k:	cmp.l	OC_N(a5),d7
	bge	op_order
	move.l	d7,d0
	mulu.l	#O_SIZE,d0
	move.l	OC_OPP(a5),a4
	add.l	d0,a4				; o
	move.l	d7,d0
	mulu.l	#20,d0
	move.l	OC_SPEC(a5),a3
	add.l	d0,a3				; its spec
	move.l	d7,d0
	mulu.l	#5384,d0
	move.l	OC_SPL(a5),a2
	add.l	d0,a2				; its curve
	move.l	OC_RANK(a5),a0			; the player ahead (by the running order)
	moveq	#0,d0
	move.l	(a0),d1
	cmp.l	O_RANK(a4),d1
	bge.s	op_na
	moveq	#1,d0
op_na:	move.l	d0,OL_AHEAD(a6)
	tst.l	d7				; a whole lap ahead of one
	bne.s	op_lp0
	move.l	OC_LAPPED(a5),a0
	clr.l	(a0)
op_lp0:	move.l	O_MKL(a4),d0
	move.l	OC_LAPS(a5),d1
	cmp.l	d1,d0
	bge.s	op_lp2
	move.l	d0,d2
	muls.l	#100,d2
	fsmove.l d2,fp1
	fsmove.s O_PROG(a4),fp0
	fssub.x	fp1,fp0
	move.l	d1,d2
	muls.l	#100,d2
	fsmove.l d2,fp2
	fsmove.s OC_PROG(a5),fp1
	fssub.x	fp2,fp1
	fcmp.x	fp1,fp0
	fblt	op_lp1
op_lp2:	sub.l	d0,d1
	cmp.l	#1,d1
	ble.s	op_lp3
op_lp1:	move.l	OC_LAPPED(a5),a0
	move.l	#1,(a0)
op_lp3:	tst.l	OC_GO(a5)			; the speed
	beq	op_move
	bsr	op_markers
	fsmove.s K_ONE(pc),fp2			; pace
	move.l	OC_NMARK(a5),d0
	beq.s	op_p1
	move.l	O_MARK(a4),d0
	mulu.l	#28,d0
	move.l	OC_MARK(a5),a0
	fsmove.s 8(a0,d0.l),fp2
op_p1:	fsmove.s (a3),fp0			; target = (max_spd + (ahead ? skill : 0)) x pace
	tst.l	OL_AHEAD(a6)
	beq.s	op_p2
	fsadd.s	12(a3),fp0
	bra.s	op_p3
op_p2:	fsadd.s	K_ZERO(pc),fp0
op_p3:	fsmul.x	fp2,fp0
	fsmove.s O_SPEED(a4),fp1
	fcmp.x	fp0,fp1
	fbge	op_p5
	fsmove.s 4(a3),fp2			; speed += accel dt, not past the target
	fsmul.s	g_dt_smooth,fp2
	fsadd.x	fp2,fp1
	fcmp.x	fp0,fp1
	fble	op_p7
	fsmove.x fp0,fp1
	bra.s	op_p7
op_p5:	fcmp.x	fp0,fp1
	fble	op_p7
	fsmove.s 8(a3),fp2			; speed -= brakes dt, not past the target
	fsmul.s	g_dt_smooth,fp2
	fssub.x	fp2,fp1
	fcmp.x	fp0,fp1
	fbge	op_p7
	fsmove.x fp0,fp1
op_p7:	fmove.s	fp1,O_SPEED(a4)
op_move:					; that far along the curve
	fsmove.s O_SPEED(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fmove.s	fp0,OL_LEFT(a6)
	clr.l	OL_GUARD(a6)
op_mv:	cmp.l	#8,OL_GUARD(a6)
	bge	op_shove
	fsmove.s OL_LEFT(a6),fp0
	ftst.x	fp0
	fble	op_shove
	bsr	op_piece
	bsr	op_curve
	fsmove.s OL_DER(a6),fp0			; len = sqrt(der0^2 + der1^2), at least 1
	fsmul.x	fp0,fp0
	fsmove.s OL_DER+4(a6),fp1
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fcmp.s	K_ONE(pc),fp0
	fbge	op_m1
	fsmove.s K_ONE(pc),fp0
op_m1:	fsmove.s OL_LEFT(a6),fp1		; du = left / len
	fsdiv.x	fp0,fp1
	fsmove.s O_U(a4),fp2
	fsadd.x	fp1,fp2
	fcmp.s	K_ONE(pc),fp2
	fbge	op_m2
	fmove.s	fp2,O_U(a4)			; within this piece
	bra	op_shove
op_m2:	fsmove.s K_ONE(pc),fp2			; left -= (1 - u) len; the next piece
	fssub.s	O_U(a4),fp2
	fsmul.x	fp0,fp2
	fsmove.s OL_LEFT(a6),fp1
	fssub.x	fp2,fp1
	fmove.s	fp1,OL_LEFT(a6)
	clr.l	O_U(a4)
	tst.l	O_HALF(a4)
	bne.s	op_m3
	move.l	#1,O_HALF(a4)
	bra.s	op_m4
op_m3:	clr.l	O_HALF(a4)
	move.l	O_NODE(a4),d0
	mulu.l	#56,d0
	move.l	8+16(a2,d0.l),d1		; node[4]: the next
	bmi.s	op_m5
	cmp.l	(a2),d1
	blt.s	op_m6
op_m5:	moveq	#0,d1
op_m6:	move.l	d1,O_NODE(a4)
op_m4:	addq.l	#1,OL_GUARD(a6)
	bra	op_mv
op_shove:					; the push from a collision
	fsmove.s O_SHOVE(a4),fp0
	ftst.x	fp0
	fble	op_lean
	fsmove.s O_SHX(a4),fp1
	fsmul.x	fp0,fp1
	fsmul.s	g_dt_smooth,fp1
	fsadd.s	O_OFFX(a4),fp1
	fmove.s	fp1,O_OFFX(a4)
	fsmove.s O_SHY(a4),fp1
	fsmul.x	fp0,fp1
	fsmul.s	g_dt_smooth,fp1
	fsadd.s	O_OFFY(a4),fp1
	fmove.s	fp1,O_OFFY(a4)
	fsmul.s	OC_D79(a5),fp0
	fcmp.s	K_TEN(pc),fp0
	fbge	op_sh1
	fsmove.s K_ZERO(pc),fp0
op_sh1:	fmove.s	fp0,O_SHOVE(a4)
	clr.l	O_AGE(a4)
op_lean:					; in a bend: the nose in, the body leaning
	fsmove.s O_SPEED(a4),fp2
	fsmul.s	16(a3),fp2			; v = speed x sband
	fsmove.s O_YAW(a4),fp0
	fssub.s	O_PREVY(a4),fp0
	bsr	op_wrap
	fsmove.x fp2,fp1
	fsmul.x	fp2,fp1
	fsmul.x	fp0,fp1
	fsmul.s	K_5030(pc),fp1
	fcmp.s	K_TWO(pc),fp1
	fble	op_l1
	fsmove.s K_TWO(pc),fp1
op_l1:	fcmp.s	K_MTWO(pc),fp1
	fbge	op_l2
	fsmove.s K_MTWO(pc),fp1
op_l2:	tst.l	OC_GO(a5)
	bne.s	op_l3
	fsmove.s K_ZERO(pc),fp1
op_l3:	move.l	O_YAW(a4),O_PREVY(a4)
	fsmove.x fp1,fp2			; spin = (spin - v/2) d4f + v/2
	fsmul.s	K_HALF(pc),fp2
	fsmove.s O_SPIN(a4),fp0
	fssub.x	fp2,fp0
	fsmul.s	OC_D4F(a5),fp0
	fsadd.x	fp2,fp0
	fmove.s	fp0,O_SPIN(a4)
	fsmove.x fp1,fp2			; body = (body - v 0.02) d4c + v 0.02
	fsmul.s	K_002(pc),fp2
	fsmove.s O_BODY(a4),fp0
	fssub.x	fp2,fp0
	fsmul.s	OC_D4C(a5),fp0
	fsadd.x	fp2,fp0
	fmove.s	fp0,O_BODY(a4)
	move.l	d7,d0
	mulu.l	#84,d0
	move.l	OC_POSE(a5),a0
	add.l	d0,a0
	move.l	O_BODY(a4),12(a0)		; body_roll
	move.l	O_BODY(a4),8(a0)		; body_pitch
	fsmove.s O_OFFX(a4),fp0			; the push dies away, three seconds on
	ftst.x	fp0
	fbne	op_ag1
	fsmove.s O_OFFY(a4),fp0
	ftst.x	fp0
	fbeq	op_place
op_ag1:	fsmove.s O_AGE(a4),fp0
	fsadd.s	g_dt_smooth,fp0
	fmove.s	fp0,O_AGE(a4)
	fcmp.s	K_THREE(pc),fp0
	fblt	op_place
	fsmove.s OC_D60(a5),fp2
	fsmove.s O_OFFX(a4),fp0
	fsmul.x	fp2,fp0
	fmove.s	fp0,O_OFFX(a4)
	fsmove.s O_OFFY(a4),fp1
	fsmul.x	fp2,fp1
	fmove.s	fp1,O_OFFY(a4)
	fsabs.x	fp0,fp0
	fcmp.s	K_ONE(pc),fp0
	fbge	op_place
	fsabs.x	fp1,fp1
	fcmp.s	K_ONE(pc),fp1
	fbge	op_place
	clr.l	O_OFFX(a4)
	clr.l	O_OFFY(a4)
op_place:					; opp_place
	bsr	op_piece
	bsr	op_curve
	fsmove.s OL_POS(a6),fp0
	fsadd.s	O_OFFX(a4),fp0
	fmove.s	fp0,O_X(a4)
	fsmove.s OL_POS+4(a6),fp0
	fsadd.s	O_OFFY(a4),fp0
	fmove.s	fp0,O_Y(a4)
	pea	O_YAW(a4)			; yaw = atan2f(der0, -der1)
	move.l	OL_DER+4(a6),d0
	bchg	#31,d0
	move.l	d0,-(sp)
	move.l	OL_DER(a6),-(sp)
	move.l	OC_ATAN2(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	tst.l	O_OBJ(a4)
	beq	op_next
	pea	OL_Z(a6)			; the ground under it
	move.l	#1,-(sp)
	move.l	O_Y(a4),-(sp)
	move.l	O_X(a4),-(sp)
	move.l	OC_UNDER(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	tst.l	d0
	beq.s	op_ot
	move.l	OL_Z(a6),O_Z(a4)
	bsr	op_tilt
op_ot:	fsmove.s O_SPEED(a4),fp0		; off the road at more than 3000: stopped dead
	fcmp.s	K_3000(pc),fp0
	fble	op_cr
	clr.l	-(sp)
	clr.l	-(sp)
	move.l	O_Y(a4),-(sp)
	move.l	O_X(a4),-(sp)
	move.l	OC_UNDER(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	tst.l	d0
	bne.s	op_cr
	clr.l	O_SPEED(a4)
op_cr:	tst.l	O_CRASH(a4)			; more than 5000 lost: it crashes
	bne	op_cr9
	fsmove.s O_PREVS(a4),fp0
	fssub.s	O_SPEED(a4),fp0
	fcmp.s	K_5000(pc),fp0
	fble	op_cr9
	fintrz.s O_X(a4),fp0
	fmove.l	fp0,d0
	fintrz.s O_Y(a4),fp0
	fmove.l	fp0,d1
	add.l	d1,d0
	asr.l	#2,d0
	btst	#0,d0
	beq.s	op_cr1
	move.l	#4,O_CRASH(a4)			; spins
	clr.l	O_TURN(a4)
	move.l	K_24(pc),O_TURNR(a4)
	bra.s	op_cr9
op_cr1:	move.l	#1,O_CRASH(a4)			; tumbles
	clr.l	O_BNC(a4)
	move.l	K_3000(pc),O_VY(a4)
	clr.l	O_UP(a4)
	clr.l	O_TIP(a4)
	clr.l	O_TURN(a4)
	clr.l	O_LEAN(a4)
	move.l	K_12(pc),O_TIPR(a4)
	move.l	K_12(pc),O_TURNR(a4)
	clr.l	O_LEANR(a4)
op_cr9:	move.l	O_SPEED(a4),O_PREVS(a4)
	move.l	O_CRASH(a4),d0
	cmp.l	#1,d0
	bne	op_c4
	fsmove.s OC_D97(a5),fp2			; tumbling
	fsmove.s O_VY(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	O_UP(a4),fp0
	fmove.s	fp0,O_UP(a4)
	fsmove.s O_VY(a4),fp0
	fssub.s	g_dt6000,fp0
	fmove.s	fp0,O_VY(a4)
	fsmove.s O_TIPR(a4),fp0
	fsmul.x	fp2,fp0
	fmove.s	fp0,O_TIPR(a4)
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	O_TIP(a4),fp0
	fmove.s	fp0,O_TIP(a4)
	fsmove.s O_TURNR(a4),fp0
	fsmul.x	fp2,fp0
	fmove.s	fp0,O_TURNR(a4)
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	O_TURN(a4),fp0
	fmove.s	fp0,O_TURN(a4)
	fsmove.s O_LEANR(a4),fp0
	fsmul.x	fp2,fp0
	fmove.s	fp0,O_LEANR(a4)
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	O_LEAN(a4),fp0
	fmove.s	fp0,O_LEAN(a4)
	fsmove.s O_UP(a4),fp0
	ftst.x	fp0
	fbgt	op_obj
	addq.l	#1,O_BNC(a4)			; a bounce
	clr.l	O_UP(a4)
	fsmove.s O_VY(a4),fp0
	fsneg.x	fp0
	fsmul.s	K_04(pc),fp0
	fmove.s	fp0,O_VY(a4)
	clr.l	O_TIP(a4)
	clr.l	O_TURN(a4)
	clr.l	O_LEAN(a4)
	move.l	K_06(pc),d0
	btst	#0,O_BNC+3(a4)
	beq.s	op_c1
	bset	#31,d0
op_c1:	move.l	d0,O_LEANR(a4)
	move.l	K_M1(pc),O_TIPR(a4)
	clr.l	O_TURNR(a4)
	cmp.l	#3,O_BNC(a4)
	ble	op_obj
	clr.l	O_CRASH(a4)
	clr.l	O_TIP(a4)
	clr.l	O_LEAN(a4)
	bra	op_obj
op_c4:	cmp.l	#4,d0
	bne	op_obj
	fsmove.s O_TURNR(a4),fp0		; spinning round
	fsmul.s	OC_D97(a5),fp0
	fmove.s	fp0,O_TURNR(a4)
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	O_TURN(a4),fp0
	fmove.s	fp0,O_TURN(a4)
	fcmp.s	K_4PI(pc),fp0
	fbge	op_c41
	fsmove.s O_TURNR(a4),fp0
	fcmp.s	K_005(pc),fp0
	fbge	op_obj
op_c41:	clr.l	O_TURN(a4)
	clr.l	O_CRASH(a4)
op_obj:	move.l	O_OBJ(a4),a1			; the object
	move.l	O_X(a4),24(a1)
	move.l	O_Y(a4),28(a1)
	fsmove.s O_Z(a4),fp0
	cmp.l	#1,O_CRASH(a4)
	bne.s	op_o1
	fsadd.s	O_UP(a4),fp0
	bra.s	op_o2
op_o1:	fsadd.s	K_ZERO(pc),fp0
op_o2:	fmove.s	fp0,32(a1)
	fsmove.s O_YAW(a4),fp0
	fsadd.s	O_SPIN(a4),fp0
	tst.l	O_CRASH(a4)
	beq.s	op_o3
	fsadd.s	O_TURN(a4),fp0
	bra.s	op_o4
op_o3:	fsadd.s	K_ZERO(pc),fp0
op_o4:	fmove.s	fp0,36(a1)
	fsmove.s O_PITCH(a4),fp0
	fsneg.x	fp0
	cmp.l	#1,O_CRASH(a4)
	bne.s	op_o5
	fsadd.s	O_TIP(a4),fp0
	bra.s	op_o6
op_o5:	fsadd.s	K_ZERO(pc),fp0
op_o6:	fmove.s	fp0,40(a1)
	fsmove.s O_ROLL(a4),fp0
	fsneg.x	fp0
	cmp.l	#1,O_CRASH(a4)
	bne.s	op_o7
	fsadd.s	O_LEAN(a4),fp0
	bra.s	op_o8
op_o7:	fsadd.s	K_ZERO(pc),fp0
op_o8:	fmove.s	fp0,44(a1)
	move.l	OC_LIV(a5),a0			; its pictures
	move.l	(a0,d7.l*4),d0
	or.l	#$4000,d0
	fsmove.s O_SPEED(a4),fp0
	fcmp.s	K_4000(pc),fp0
	fbgt	op_o9
	or.l	#$2000,d0
op_o9:	move.l	d0,72(a1)
	moveq	#0,d1				; the reflections by the marker's kind
	move.l	OC_NMARK(a5),d2
	beq.s	op_e1
	move.l	O_MARK(a4),d0
	divsl.l	d2,d3:d0
	add.l	d2,d3
	move.l	d3,d0
	divsl.l	d2,d3:d0
	mulu.l	#28,d3
	move.l	OC_MARK(a5),a0
	move.l	20(a0,d3.l),d1
op_e1:	moveq	#0,d0
	tst.l	d1
	beq.s	op_e3
	move.l	#$ff00,d0
	cmp.l	#1,d1
	bne.s	op_e3
	move.l	#$8000,d0
op_e3:	move.l	d7,d1
	mulu.l	#84,d1
	move.l	OC_POSE(a5),a0
	move.l	d0,28(a0,d1.l)
	move.l	d7,-(sp)			; the wheels, the shadow
	move.l	OC_TAIL(a5),a0
	jsr	(a0)
	addq.l	#4,sp
op_next:
	addq.l	#1,d7
	bra	op_k
op_order:					; the running order: one exchange with the player
	tst.l	OC_GO(a5)
	beq.s	op_done
	tst.l	OC_CLOCK(a5)
	beq.s	op_done
	moveq	#0,d7
oo_l:	cmp.l	OC_N(a5),d7
	bge.s	op_done
	move.l	d7,d0
	mulu.l	#O_SIZE,d0
	move.l	OC_OPP(a5),a4
	add.l	d0,a4
	move.l	OC_RANK(a5),a0
	fsmove.s OC_PROG(a5),fp0
	fssub.s	O_PROG(a4),fp0
	move.l	O_RANK(a4),d0
	sub.l	(a0),d0
	fsmove.l d0,fp1
	fsmul.x	fp1,fp0
	ftst.x	fp0
	fbge	oo_n
	move.l	O_RANK(a4),d0
	move.l	(a0),O_RANK(a4)
	move.l	d0,(a0)
	bra.s	op_done
oo_n:	addq.l	#1,d7
	bra.s	oo_l
op_done:
	lea	OL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; A B C of the opponent's piece of curve (opp_piece): a2 the curve, a4 the opponent
op_piece:
	move.l	O_NODE(a4),d0
	mulu.l	#56,d0
	lea	8(a2,d0.l),a0			; n
	move.l	16(a0),d1			; n[4]
	bmi.s	opc1
	cmp.l	(a2),d1
	blt.s	opc2
opc1:	moveq	#0,d1
opc2:	mulu.l	#56,d1
	lea	8(a2,d1.l),a1			; m
	tst.l	O_HALF(a4)
	bne.s	opc3
	fsmove.l 20(a0),fp0
	fmove.s	fp0,OL_A(a6)
	fsmove.l 24(a0),fp0
	fmove.s	fp0,OL_A+4(a6)
	fsmove.l 32(a0),fp0
	fmove.s	fp0,OL_B(a6)
	fsmove.l 36(a0),fp0
	fmove.s	fp0,OL_B+4(a6)
	fsmove.l 20(a1),fp0
	fmove.s	fp0,OL_C(a6)
	fsmove.l 24(a1),fp0
	fmove.s	fp0,OL_C+4(a6)
	rts
opc3:	fsmove.l 32(a0),fp0
	fmove.s	fp0,OL_A(a6)
	fsmove.l 36(a0),fp0
	fmove.s	fp0,OL_A+4(a6)
	fsmove.l 20(a1),fp0
	fmove.s	fp0,OL_B(a6)
	fsmove.l 24(a1),fp0
	fmove.s	fp0,OL_B+4(a6)
	fsmove.l 32(a1),fp0
	fmove.s	fp0,OL_C(a6)
	fsmove.l 36(a1),fp0
	fmove.s	fp0,OL_C+4(a6)
	rts

; the curve at u (opp_curve): pos and der from A B C (fp2-fp7 used)
op_curve:
	fsmove.s K_ONE(pc),fp7			; 1 - u
	fssub.s	O_U(a4),fp7
	fsmove.s O_U(a4),fp6			; u
	fsmove.x fp7,fp2			; w0 = (1 - u)^2 / 2
	fsmul.x	fp7,fp2
	fsmul.s	K_HALF(pc),fp2
	fsmove.x fp6,fp4			; w2 = u^2 / 2
	fsmul.x	fp6,fp4
	fsmul.s	K_HALF(pc),fp4
	fsmove.s K_ONE(pc),fp3			; w1 = 1 - w0 - w2
	fssub.x	fp2,fp3
	fssub.x	fp4,fp3
	moveq	#0,d0
ocv_k:	fsmove.s OL_A(a6,d0.l),fp0		; pos = A w0 + B w1 + C w2
	fsmul.x	fp2,fp0
	fsmove.s OL_B(a6,d0.l),fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fsmove.s OL_C(a6,d0.l),fp1
	fsmul.x	fp4,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,OL_POS(a6,d0.l)
	fsmove.s OL_B(a6,d0.l),fp0		; der = (1 - u)(B - A) + u (C - B)
	fssub.s	OL_A(a6,d0.l),fp0
	fsmul.x	fp7,fp0
	fsmove.s OL_C(a6,d0.l),fp1
	fssub.s	OL_B(a6,d0.l),fp1
	fsmul.x	fp6,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,OL_DER(a6,d0.l)
	addq.l	#4,d0
	cmp.l	#8,d0
	blt.s	ocv_k
	rts

; fp0 into -pi..pi (wrap_pi)
op_wrap:
ow_1:	fcmp.s	K_PI(pc),fp0
	fble	ow_2
	fssub.s	K_2PI(pc),fp0
	bra.s	ow_1
ow_2:	fcmp.s	K_MPI(pc),fp0
	fbge	ow_3
	fsadd.s	K_2PI(pc),fp0
	bra.s	ow_2
ow_3:	rts

; the tilt on the face found (slope_tilt): g_under_n, the heading
op_tilt:
	move.l	OC_UN(a5),a0
	fsmove.s (a0),fp2			; nx ny nz
	fsmove.s 4(a0),fp3
	fsmove.s 8(a0),fp4
	fsmove.x fp2,fp0			; len
	fsmul.x	fp2,fp0
	fsmove.x fp3,fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fsmove.x fp4,fp1
	fsmul.x	fp4,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	ftst.x	fp4
	fbge	ot_1
	fsneg.x	fp0
ot_1:	ftst.x	fp0
	fbeq	ot_2
	fsdiv.x	fp0,fp2
	fsdiv.x	fp0,fp3
ot_2:	pea	OL_CO(a6)			; sinf, cosf of the heading
	pea	OL_S(a6)
	move.l	O_YAW(a4),-(sp)
	move.l	OC_SINCOS(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	fsmove.s OL_S(a6),fp4			; fx
	fsmove.s OL_CO(a6),fp5
	fsneg.x	fp5				; fy
	fsmove.x fp2,fp0			; pitch = -1.117 (nx fx + ny fy)
	fsmul.x	fp4,fp0
	fsmove.x fp3,fp1
	fsmul.x	fp5,fp1
	fsadd.x	fp1,fp0
	fsmul.s	K_M1117(pc),fp0
	fmove.s	fp0,O_PITCH(a4)
	fsmove.x fp5,fp0			; roll = 1.117 (nx -fy + ny fx)
	fsneg.x	fp0
	fsmul.x	fp2,fp0
	fsmove.x fp3,fp1
	fsmul.x	fp4,fp1
	fsadd.x	fp1,fp0
	fsmul.s	K_1117(pc),fp0
	fmove.s	fp0,O_ROLL(a4)
	rts

; the opponent's markers (opp_markers), then its progress (marker_progress)
op_markers:
	move.l	OC_NMARK(a5),d2
	beq	om_p0
	moveq	#-1,d3				; d
om_l:	cmp.l	#1,d3
	bgt	om_pr
	move.l	O_MARK(a4),d0			; i = ((at + d) % n + n) % n
	add.l	d3,d0
	divsl.l	d2,d1:d0
	add.l	d2,d1
	move.l	d1,d0
	divsl.l	d2,d1:d0
	move.l	d1,d4
	mulu.l	#28,d1
	move.l	OC_MARK(a5),a0
	add.l	d1,a0				; m
	fsmove.s O_X(a4),fp0
	fssub.s	12(a0),fp0			; dx
	fsmove.s O_Y(a4),fp1
	fssub.s	16(a0),fp1			; dy
	fsmove.s (a0),fp2			; radius
	fsabs.x	fp0,fp3
	fcmp.x	fp2,fp3
	fbge	om_n
	fsabs.x	fp1,fp3
	fcmp.x	fp2,fp3
	fbge	om_n
	fsmul.x	fp0,fp0
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fcmp.x	fp2,fp0
	fbgt	om_n
	move.l	d4,O_MARK(a4)
	lea	O_SEEN(a4),a1
	tst.l	d4
	beq.s	om_c2
	tst.b	-1(a1,d4.l)
	beq.s	om_c3
om_c2:	tst.b	(a1,d4.l)
	bne.s	om_c3
	move.b	#1,(a1,d4.l)			; passed
	addq.l	#1,O_MKC(a4)
	bra.s	om_n
om_c3:	tst.l	d4				; the line with all passed: a lap
	bne.s	om_n
	cmp.l	O_MKC(a4),d2
	bne.s	om_n
	lea	1(a1),a0
	moveq	#62,d0
om_z:	clr.b	(a0)+
	dbra	d0,om_z
	move.l	#1,O_MKC(a4)
	addq.l	#1,O_MKL(a4)
om_n:	addq.l	#1,d3
	bra	om_l
om_pr:	move.l	O_MARK(a4),d4			; marker_progress(at, laps, x, y)
	move.l	d4,d0
	mulu.l	#28,d0
	move.l	OC_MARK(a5),a0
	add.l	d0,a0				; a
	move.l	d4,d0
	addq.l	#1,d0
	divsl.l	d2,d1:d0
	mulu.l	#28,d1
	move.l	OC_MARK(a5),a1
	add.l	d1,a1				; b
	fsmove.s 12(a1),fp0			; span
	fssub.s	12(a0),fp0
	fsmul.x	fp0,fp0
	fsmove.s 16(a1),fp1
	fssub.s	16(a0),fp1
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fsmul.s	K_005(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d5
	fsmove.s O_X(a4),fp0			; gone
	fssub.s	12(a0),fp0
	fsmul.x	fp0,fp0
	fsmove.s O_Y(a4),fp1
	fssub.s	16(a0),fp1
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fsmul.s	K_005(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d6
	tst.l	d5
	beq.s	om_q0
	fsmove.l d6,fp0
	fsmove.l d5,fp1
	fsdiv.x	fp1,fp0
	bra.s	om_q1
om_q0:	fsmove.s K_ZERO(pc),fp0
om_q1:	fsmove.l d4,fp1
	fsadd.x	fp1,fp0
	move.l	O_MKL(a4),d0
	muls.l	#100,d0
	fsmove.l d0,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,O_PROG(a4)
	rts
om_p0:	clr.l	O_PROG(a4)
	rts

; ---------------------------------------------------------------------------------------------------------------
; void pc68k(const pc_ctx *c): main.c player_contact (player_contact_c the reference, OS_PCASM=c compares them): the
; four wheels turned by the heading and the drift and stood on the ground (track_under), the grass and its jolts,
; the same four turned by the heading alone for the chase camera, then the car's height, nose and lean.
PC_CAR	equ	0
PC_MM	equ	4
PC_CONT	equ	8
PC_OBJ	equ	12
PC_UOBJ	equ	16
PC_SC	equ	20
PC_ATAN	equ	24
PC_UNDER equ	28
PC_COS	equ	32
; car_state
CS_X	equ	68
CS_Y	equ	72
CS_Z	equ	76
CS_YAW	equ	80
CS_PITCH equ	84
CS_ROLL	equ	88
CS_DRIFT equ	156
CS_ROUGH equ	188
CS_GRASS equ	200
; g_contact: 0 ready, 4 h[4], 20 ground, 24 hc[4], 40 cam_pitch, 44 cam_roll
; locals (a6)
PL_LX	equ	0
PL_LZ	equ	16
PL_CR	equ	32
PL_CP	equ	36
PL_CS	equ	40
PL_SN	equ	44
PL_J	equ	48
PL_H	equ	64
PL_T	equ	68
PL_WX	equ	72
PL_WY	equ	76
PL_TR	equ	80
PL_AF	equ	84
PL_AR	equ	88
PL_S	equ	92
PL_C	equ	96
PL_LOC	equ	100

	xdef	_pc68k
	xdef	pc68k
_pc68k:
pc68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-PL_LOC(sp),sp
	move.l	sp,a6
	move.l	PL_LOC+72+48(sp),a5
	move.l	PC_CAR(a5),a4
	move.l	PC_MM(a5),a3
	move.l	PC_CONT(a5),a2
	fsmove.s 40(a3),fp0			; tr: the track's half, else 226
	ftst.x	fp0
	fbgt	pc_1
	fsmove.s K_226(pc),fp0
pc_1:	fmove.s	fp0,PL_TR(a6)
	move.l	32(a3),PL_AF(a6)
	move.l	36(a3),PL_AR(a6)
	move.l	PL_TR(a6),d0			; lx = tr tr -tr -tr, lz = -af ar -af ar
	move.l	d0,PL_LX(a6)
	move.l	d0,PL_LX+4(a6)
	bchg	#31,d0
	move.l	d0,PL_LX+8(a6)
	move.l	d0,PL_LX+12(a6)
	move.l	PL_AF(a6),d0
	bchg	#31,d0
	move.l	d0,PL_LZ(a6)
	move.l	d0,PL_LZ+8(a6)
	move.l	PL_AR(a6),PL_LZ+4(a6)
	move.l	PL_AR(a6),PL_LZ+12(a6)
	pea	PL_T(a6)			; cr = |cos roll|, cp = |cos pitch|
	move.l	CS_ROLL(a4),-(sp)
	move.l	PC_COS(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	move.l	PL_T(a6),d0
	bclr	#31,d0
	move.l	d0,PL_CR(a6)
	pea	PL_T(a6)
	move.l	CS_PITCH(a4),-(sp)
	move.l	PC_COS(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	move.l	PL_T(a6),d0
	bclr	#31,d0
	move.l	d0,PL_CP(a6)
	fsmove.s CS_YAW(a4),fp0			; cs, sn of yaw + drift
	fsadd.s	CS_DRIFT(a4),fp0
	fmove.s	fp0,PL_T(a6)
	pea	PL_C(a6)
	pea	PL_S(a6)
	move.l	PL_T(a6),-(sp)
	move.l	PC_SC(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	move.l	PL_C(a6),PL_CS(a6)
	move.l	PL_S(a6),PL_SN(a6)
	tst.l	(a2)				; the first time: the wheels at the car's height
	bne.s	pc_2
	move.l	CS_Z(a4),d0
	move.l	d0,4(a2)
	move.l	d0,8(a2)
	move.l	d0,12(a2)
	move.l	d0,16(a2)
pc_2:	clr.l	CS_ROUGH(a4)
	moveq	#0,d7				; n
pc_l:	cmp.l	#4,d7
	bge	pc_cam
	fsmove.s PL_LX(a6,d7.l*4),fp2		; x = lx cr, z = lz cp
	fsmul.s	PL_CR(a6),fp2
	fsmove.s PL_LZ(a6,d7.l*4),fp3
	fsmul.s	PL_CP(a6),fp3
	fsmove.s CS_X(a4),fp0			; wx = c.x + x cs - z sn
	fsmove.x fp2,fp1
	fsmul.s	PL_CS(a6),fp1
	fsadd.x	fp1,fp0
	fsmove.x fp3,fp1
	fsmul.s	PL_SN(a6),fp1
	fssub.x	fp1,fp0
	fmove.s	fp0,PL_WX(a6)
	fsmove.s CS_Y(a4),fp0			; wy = c.y + x sn + z cs
	fsmove.x fp2,fp1
	fsmul.s	PL_SN(a6),fp1
	fsadd.x	fp1,fp0
	fsmove.x fp3,fp1
	fsmul.s	PL_CS(a6),fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,PL_WY(a6)
	pea	PL_H(a6)
	move.l	#1,-(sp)
	move.l	PL_WY(a6),-(sp)
	move.l	PL_WX(a6),-(sp)
	move.l	PC_UNDER(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	tst.l	d0
	beq.s	pc_j				; over nothing: the wheel keeps its height
	move.l	PL_H(a6),4(a2,d7.l*4)
	move.l	PC_UOBJ(a5),a0			; grass: the piece's surface 'e'
	move.l	(a0),d0
	mulu.l	#76,d0
	move.l	PC_OBJ(a5),a0
	move.l	(a0,d0.l),a0
	moveq	#0,d1
	cmp.b	#'e',48(a0)
	bne.s	pc_g
	moveq	#1,d1
pc_g:	move.l	d1,CS_GRASS(a4,d7.l*4)
	beq.s	pc_j
	btst	#0,d7
	bne.s	pc_j
	move.l	#1,CS_ROUGH(a4)
pc_j:	move.l	4(a2,d7.l*4),PL_J(a6,d7.l*4)	; jolted
	tst.l	CS_GRASS(a4,d7.l*4)
	beq.s	pc_n
	fintrz.s PL_WX(a6),fp0			; spot = (int)wx + (int)wy: +-(spot & 15)
	fmove.l	fp0,d0
	fintrz.s PL_WY(a6),fp0
	fmove.l	fp0,d1
	add.l	d1,d0
	moveq	#15,d1
	and.l	d0,d1
	btst	#1,d0
	beq.s	pc_g2
	neg.l	d1
pc_g2:	fsmove.l d1,fp0
	fsadd.s	PL_J(a6,d7.l*4),fp0
	fmove.s	fp0,PL_J(a6,d7.l*4)
pc_n:	addq.l	#1,d7
	bra	pc_l
pc_cam:	pea	PL_C(a6)			; the camera's: turned by the heading alone, no jolts
	pea	PL_S(a6)
	move.l	CS_YAW(a4),-(sp)
	move.l	PC_SC(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	moveq	#0,d7
pcc_l:	cmp.l	#4,d7
	bge	pcc_e
	fsmove.s PL_LX(a6,d7.l*4),fp2
	fsmul.s	PL_CR(a6),fp2
	fsmove.s PL_LZ(a6,d7.l*4),fp3
	fsmul.s	PL_CP(a6),fp3
	tst.l	(a2)
	bne.s	pcc_1
	move.l	CS_Z(a4),24(a2,d7.l*4)
pcc_1:	fsmove.s CS_X(a4),fp0
	fsmove.x fp2,fp1
	fsmul.s	PL_C(a6),fp1
	fsadd.x	fp1,fp0
	fsmove.x fp3,fp1
	fsmul.s	PL_S(a6),fp1
	fssub.x	fp1,fp0
	fmove.s	fp0,PL_WX(a6)
	fsmove.s CS_Y(a4),fp0
	fsmove.x fp2,fp1
	fsmul.s	PL_S(a6),fp1
	fsadd.x	fp1,fp0
	fsmove.x fp3,fp1
	fsmul.s	PL_C(a6),fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,PL_WY(a6)
	pea	PL_H(a6)
	move.l	#1,-(sp)
	move.l	PL_WY(a6),-(sp)
	move.l	PL_WX(a6),-(sp)
	move.l	PC_UNDER(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	tst.l	d0
	beq.s	pcc_n
	move.l	PL_H(a6),24(a2,d7.l*4)
pcc_n:	addq.l	#1,d7
	bra	pcc_l
pcc_e:	fsmove.s 32(a2),fp0			; cam_pitch = atan((hc2 - hc3) / (af + ar))
	fssub.s	36(a2),fp0
	bsr	pc_daf
	pea	40(a2)
	bsr	pc_at
	fsmove.s 32(a2),fp0			; cam_roll = atan((hc2 - hc0) / (2 tr))
	fssub.s	24(a2),fp0
	bsr	pc_dtr
	pea	44(a2)
	bsr	pc_at
	move.l	#1,(a2)
	fsmove.s 4(a2),fp0			; ground = (h0 + h1 + h2 + h3) / 4
	fsadd.s	8(a2),fp0
	fsadd.s	12(a2),fp0
	fsadd.s	16(a2),fp0
	fsmul.s	K_QTR(pc),fp0
	fmove.s	fp0,20(a2)
	fsmove.s PL_J(a6),fp0			; z: the jolted ones
	fsadd.s	PL_J+4(a6),fp0
	fsadd.s	PL_J+8(a6),fp0
	fsadd.s	PL_J+12(a6),fp0
	fsmul.s	K_QTR(pc),fp0
	fmove.s	fp0,CS_Z(a4)
	fsmove.s PL_J+8(a6),fp0			; pitch = atan((j2 - j3) / (af + ar))
	fssub.s	PL_J+12(a6),fp0
	bsr	pc_daf
	pea	CS_PITCH(a4)
	bsr	pc_at
	fsmove.s PL_J+8(a6),fp0			; roll = atan((j2 - j0) / (2 tr))
	fssub.s	PL_J(a6),fp0
	bsr	pc_dtr
	pea	CS_ROLL(a4)
	bsr	pc_at
	lea	PL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts
pc_daf:	fsmove.s PL_AF(a6),fp1			; fp0 / (af + ar)
	fsadd.s	PL_AR(a6),fp1
	fsdiv.x	fp1,fp0
	rts
pc_dtr:	fsmove.s K_TWO(pc),fp1			; fp0 / (2 tr)
	fsmul.s	PL_TR(a6),fp1
	fsdiv.x	fp1,fp0
	rts
; atanf(fp0) into the float the caller pushed (4(sp)); pops it
pc_at:	fmove.s	fp0,PL_T(a6)
	move.l	4(sp),-(sp)
	move.l	PL_T(a6),-(sp)
	move.l	PC_ATAN(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	move.l	(sp)+,a0			; the return
	addq.l	#4,sp				; the pushed address
	jmp	(a0)

; ---------------------------------------------------------------------------------------------------------------
; void cc68k(const cc_ctx *c): main.c cars_collide (cars_collide_c the reference, OS_CCASM=c compares them): every
; car two circles (car_circles); the player against each opponent (player_hits in C), the opponent's overtaking
; (its line moved over), each opponent against the ones after it.
CC_CAR	equ	0
CC_PM	equ	4
CC_OPP	equ	8
CC_N	equ	12
CC_HIT	equ	16
CC_CON	equ	20
CC_D32	equ	24
CC_SC	equ	28
CC_HITS	equ	32
CS_SPEED equ	92
; locals (a6): circles cx0 cx1 cy0 cy1 r
CL_P	equ	0
CL_O	equ	20
CL_Q	equ	40
CL_IX	equ	60
CL_IY	equ	64
CL_IYAW	equ	68
CL_IM	equ	72
CL_OUT	equ	76
CL_S	equ	80
CL_C	equ	84
CL_QX	equ	88
CL_QY	equ	92
CL_LOC	equ	96

	xdef	_cc68k
	xdef	cc68k
_cc68k:
cc68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-CL_LOC(sp),sp
	move.l	sp,a6
	move.l	CL_LOC+72+48(sp),a5
	move.l	CC_CAR(a5),a4
	move.l	CC_PM(a5),CL_IM(a6)		; the player's circles
	move.l	CS_X(a4),CL_IX(a6)
	move.l	CS_Y(a4),CL_IY(a6)
	move.l	CS_YAW(a4),CL_IYAW(a6)
	lea	CL_P(a6),a0
	move.l	a0,CL_OUT(a6)
	bsr	cc_circ
	move.l	CC_CON(a5),a0			; hitcar eases to the contact (0x32)
	fsmove.l (a0),fp1
	move.l	CC_HIT(a5),a1
	fsmove.s (a1),fp0
	fssub.x	fp1,fp0
	fsmul.s	CC_D32(a5),fp0
	fsadd.x	fp1,fp0
	fmove.s	fp0,(a1)
	clr.l	(a0)
	moveq	#0,d7				; k
cc_k:	cmp.l	CC_N(a5),d7
	bge	cc_done
	move.l	d7,d0
	mulu.l	#O_SIZE,d0
	move.l	CC_OPP(a5),a3
	add.l	d0,a3				; o
	tst.l	O_OBJ(a3)
	beq	cc_nk
	move.l	O_OBJ(a3),a0			; its circles
	move.l	(a0),CL_IM(a6)
	move.l	O_X(a3),CL_IX(a6)
	move.l	O_Y(a3),CL_IY(a6)
	move.l	O_YAW(a3),CL_IYAW(a6)
	lea	CL_O(a6),a0
	move.l	a0,CL_OUT(a6)
	bsr	cc_circ
	fsmove.s CS_X(a4),fp0			; the player and this one: within 1500, 600 up
	fssub.s	O_X(a3),fp0
	fsabs.x	fp0
	fcmp.s	K_1500(pc),fp0
	fbge	cc_ov
	fsmove.s CS_Y(a4),fp0
	fssub.s	O_Y(a3),fp0
	fsabs.x	fp0
	fcmp.s	K_1500(pc),fp0
	fbge	cc_ov
	fsmove.s CS_Z(a4),fp0
	fssub.s	O_Z(a3),fp0
	fsabs.x	fp0
	fcmp.s	K_600(pc),fp0
	fbge	cc_ov
	moveq	#0,d6				; a
cc_a:	cmp.l	#2,d6
	bge	cc_ov
	moveq	#0,d5				; b
cc_b:	cmp.l	#2,d5
	bge	cc_an
	fsmove.s CL_P(a6,d6.l*4),fp2		; dx dy
	fssub.s	CL_O(a6,d5.l*4),fp2
	fsmove.s CL_P+8(a6,d6.l*4),fp3
	fssub.s	CL_O+8(a6,d5.l*4),fp3
	bsr	cc_dist
	fsmove.s CL_P+16(a6),fp1		; pr + orad
	fsadd.s	CL_O+16(a6),fp1
	fcmp.x	fp1,fp0
	fbge	cc_bn
	fssub.x	fp0,fp1				; player_hits(o, dx / dist, dy / dist, pr + orad - dist)
	fmove.s	fp1,-(sp)
	fsdiv.x	fp0,fp3
	fmove.s	fp3,-(sp)
	fsdiv.x	fp0,fp2
	fmove.s	fp2,-(sp)
	move.l	a3,-(sp)
	move.l	CC_HITS(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	fsmove.s O_X(a3),fp0			; its circles again (x + 0, y + 0)
	fsadd.s	K_ZERO(pc),fp0
	fmove.s	fp0,CL_IX(a6)
	fsmove.s O_Y(a3),fp0
	fsadd.s	K_ZERO(pc),fp0
	fmove.s	fp0,CL_IY(a6)
	move.l	O_YAW(a3),CL_IYAW(a6)
	move.l	O_OBJ(a3),a0
	move.l	(a0),CL_IM(a6)
	lea	CL_O(a6),a0
	move.l	a0,CL_OUT(a6)
	bsr	cc_circ
	bra.s	cc_an				; (out of b)
cc_bn:	addq.l	#1,d5
	bra	cc_b
cc_an:	addq.l	#1,d6
	bra	cc_a
cc_ov:	pea	CL_C(a6)			; overtaking: three radii ahead of it
	pea	CL_S(a6)
	move.l	O_YAW(a3),-(sp)
	move.l	CC_SC(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	fsmove.s CL_S(a6),fp0			; qx = o.x + fx orad 3
	fsmul.s	CL_O+16(a6),fp0
	fsmul.s	K_THREE(pc),fp0
	fsadd.s	O_X(a3),fp0
	fmove.s	fp0,CL_QX(a6)
	fsmove.s CL_C(a6),fp0			; qy = o.y + fy orad 3
	fsneg.x	fp0
	fsmul.s	CL_O+16(a6),fp0
	fsmul.s	K_THREE(pc),fp0
	fsadd.s	O_Y(a3),fp0
	fmove.s	fp0,CL_QY(a6)
	fsmove.s CL_QX(a6),fp0
	fssub.s	CS_X(a4),fp0
	fsabs.x	fp0
	fcmp.s	K_5000(pc),fp0
	fbge	cc_oo
	fsmove.s CL_QY(a6),fp0
	fssub.s	CS_Y(a4),fp0
	fsabs.x	fp0
	fcmp.s	K_5000(pc),fp0
	fbge	cc_oo
	fsmove.s CS_SPEED(a4),fp0
	fcmp.s	O_SPEED(a3),fp0
	fbge	cc_oo
	fsmove.s CS_Z(a4),fp0
	fssub.s	O_Z(a3),fp0
	fsabs.x	fp0
	fcmp.s	K_600(pc),fp0
	fbge	cc_oo
	fsmove.s CL_O+16(a6),fp4		; thr = orad 2 + pr
	fsmul.s	K_TWO(pc),fp4
	fsadd.s	CL_P+16(a6),fp4
	moveq	#0,d6
cc_oa:	cmp.l	#2,d6
	bge	cc_oo
	fsmove.s CL_QX(a6),fp2
	fssub.s	CL_P(a6,d6.l*4),fp2
	fsmove.s CL_QY(a6),fp3
	fssub.s	CL_P+8(a6,d6.l*4),fp3
	fsmove.x fp2,fp0
	fsmul.x	fp2,fp0
	fsmove.x fp3,fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fcmp.x	fp4,fp0
	fbge	cc_on
	fsadd.s	K_ONE(pc),fp0			; its line over by just enough
	fsmove.x fp4,fp1
	fsmul.x	fp2,fp1
	fsdiv.x	fp0,fp1
	fssub.x	fp2,fp1
	fsadd.s	O_OFFX(a3),fp1
	fmove.s	fp1,O_OFFX(a3)
	fsmove.x fp4,fp1
	fsmul.x	fp3,fp1
	fsdiv.x	fp0,fp1
	fssub.x	fp3,fp1
	fsadd.s	O_OFFY(a3),fp1
	fmove.s	fp1,O_OFFY(a3)
	clr.l	O_AGE(a3)
cc_on:	addq.l	#1,d6
	bra	cc_oa
cc_oo:	move.l	d7,d4				; this one and the ones after it
	addq.l	#1,d4
cc_j:	cmp.l	CC_N(a5),d4
	bge	cc_nk
	move.l	d4,d0
	mulu.l	#O_SIZE,d0
	move.l	CC_OPP(a5),a2
	add.l	d0,a2				; q
	tst.l	O_OBJ(a2)
	beq	cc_jn
	fsmove.s O_X(a3),fp0
	fssub.s	O_X(a2),fp0
	fsabs.x	fp0
	fcmp.s	K_1500(pc),fp0
	fbge	cc_jn
	fsmove.s O_Y(a3),fp0
	fssub.s	O_Y(a2),fp0
	fsabs.x	fp0
	fcmp.s	K_1500(pc),fp0
	fbge	cc_jn
	move.l	O_OBJ(a2),a0
	move.l	(a0),CL_IM(a6)
	move.l	O_X(a2),CL_IX(a6)
	move.l	O_Y(a2),CL_IY(a6)
	move.l	O_YAW(a2),CL_IYAW(a6)
	lea	CL_Q(a6),a0
	move.l	a0,CL_OUT(a6)
	bsr	cc_circ
	moveq	#0,d6
cc_ja:	cmp.l	#2,d6
	bge	cc_jn
	moveq	#0,d5
cc_jb:	cmp.l	#2,d5
	bge	cc_jan
	fsmove.s CL_O(a6,d6.l*4),fp2
	fssub.s	CL_Q(a6,d5.l*4),fp2
	fsmove.s CL_O+8(a6,d6.l*4),fp3
	fssub.s	CL_Q+8(a6,d5.l*4),fp3
	bsr	cc_dist
	fsmove.s CL_O+16(a6),fp1		; orad + qrad
	fsadd.s	CL_Q+16(a6),fp1
	fcmp.x	fp1,fp0
	fbge	cc_jbn
	fsmove.s O_SPEED(a3),fp4		; the faster drops to the average
	fsadd.s	O_SPEED(a2),fp4
	fsmul.s	K_HALF(pc),fp4
	fsmove.s O_SPEED(a2),fp5
	fcmp.s	O_SPEED(a3),fp5
	fbgt	cc_q
	fmove.s	fp4,O_SPEED(a3)
	bra.s	cc_p
cc_q:	fmove.s	fp4,O_SPEED(a2)
cc_p:	fssub.x	fp0,fp1				; pen; the other moved over
	fsmove.x fp2,fp5
	fsdiv.x	fp0,fp5
	fsmul.x	fp1,fp5
	fsmove.s O_OFFX(a2),fp6
	fssub.x	fp5,fp6
	fmove.s	fp6,O_OFFX(a2)
	fsmove.x fp3,fp5
	fsdiv.x	fp0,fp5
	fsmul.x	fp1,fp5
	fsmove.s O_OFFY(a2),fp6
	fssub.x	fp5,fp6
	fmove.s	fp6,O_OFFY(a2)
	clr.l	O_AGE(a2)
cc_jbn:	addq.l	#1,d5
	bra	cc_jb
cc_jan:	addq.l	#1,d6
	bra	cc_ja
cc_jn:	addq.l	#1,d4
	bra	cc_j
cc_nk:	addq.l	#1,d7
	bra	cc_k
cc_done:
	lea	CL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts
; fp0 = sqrt(fp2^2 + fp3^2), at least 1
cc_dist:
	fsmove.x fp2,fp0
	fsmul.x	fp2,fp0
	fsmove.x fp3,fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fcmp.s	K_ONE(pc),fp0
	fbge	cd_1
	fsmove.s K_ONE(pc),fp0
cd_1:	rts
; car_circles: CL_IM (mesh), CL_IX CL_IY CL_IYAW -> (CL_OUT): cx0 cx1 cy0 cy1 r  (fp2-fp7 used)
cc_circ:
	move.l	CL_IM(a6),a0
	fsmove.s 32(a0),fp2			; nose = axle_front + 250
	fsadd.s	K_250(pc),fp2
	fsmove.s 36(a0),fp3			; tail = axle_rear + 150
	fsadd.s	K_150(pc),fp3
	fsmove.x fp2,fp4			; quarter = (nose + tail) / 4
	fsadd.x	fp3,fp4
	fsmul.s	K_QTR(pc),fp4
	pea	CL_C(a6)
	pea	CL_S(a6)
	move.l	CL_IYAW(a6),-(sp)
	move.l	CC_SC(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	move.l	CL_OUT(a6),a0
	fsmove.s CL_S(a6),fp5			; fx
	fsmove.s CL_C(a6),fp6
	fsneg.x	fp6				; fy
	fsmove.x fp2,fp0			; zf = nose - quarter
	fssub.x	fp4,fp0
	fsmove.x fp3,fp1			; zr = -(tail - quarter)
	fssub.x	fp4,fp1
	fsneg.x	fp1
	fsmove.x fp5,fp7
	fsmul.x	fp0,fp7
	fsadd.s	CL_IX(a6),fp7
	fmove.s	fp7,(a0)
	fsmove.x fp6,fp7
	fsmul.x	fp0,fp7
	fsadd.s	CL_IY(a6),fp7
	fmove.s	fp7,8(a0)
	fsmove.x fp5,fp7
	fsmul.x	fp1,fp7
	fsadd.s	CL_IX(a6),fp7
	fmove.s	fp7,4(a0)
	fsmove.x fp6,fp7
	fsmul.x	fp1,fp7
	fsadd.s	CL_IY(a6),fp7
	fmove.s	fp7,12(a0)
	fmove.s	fp4,16(a0)
	rts

; ---------------------------------------------------------------------------------------------------------------
; void pw68k(const pw_ctx *c): main.c player_walls (player_walls_c the reference, OS_PWASM=c compares them): the
; body's four corners on the ground or not (track_under); for those off it the nearest wall (C), the push back to
; 30 inside its line, the largest on each axis; the car moved, then the wall's answer (pw_tail, C).
PW_CAR	equ	0
PW_CORN	equ	4
PW_SC	equ	8
PW_COS	equ	12
PW_UNDER equ	16
PW_NEAR	equ	20
PW_WALLS equ	24
PW_IN	equ	28
PW_TAIL	equ	32
; locals (a6)
WL_PX	equ	0
WL_PY	equ	16
WL_S	equ	32
WL_C	equ	36
WL_CR	equ	40
WL_CP	equ	44
WL_T	equ	48
WL_IDX	equ	52
WL_MX	equ	56
WL_MY	equ	60
WL_WA	equ	64
WL_NS	equ	68
WL_NC	equ	72
WL_LOC	equ	76

	xdef	_pw68k
	xdef	pw68k
_pw68k:
pw68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-WL_LOC(sp),sp
	move.l	sp,a6
	move.l	WL_LOC+72+48(sp),a5
	move.l	PW_CAR(a5),a4
	pea	WL_C(a6)			; sin, cos of the heading
	pea	WL_S(a6)
	move.l	CS_YAW(a4),-(sp)
	move.l	PW_SC(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	pea	WL_T(a6)			; cr = |cos roll|, cp = |cos pitch|
	move.l	CS_ROLL(a4),-(sp)
	move.l	PW_COS(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	move.l	WL_T(a6),d0
	bclr	#31,d0
	move.l	d0,WL_CR(a6)
	pea	WL_T(a6)
	move.l	CS_PITCH(a4),-(sp)
	move.l	PW_COS(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	move.l	WL_T(a6),d0
	bclr	#31,d0
	move.l	d0,WL_CP(a6)
	fsmove.s WL_S(a6),fp4			; fx = s, fy = -c, rx = -c, ry = -s
	fsmove.s WL_C(a6),fp5
	fsneg.x	fp5
	fsmove.x fp5,fp6
	fsmove.s WL_S(a6),fp7
	fsneg.x	fp7
	moveq	#0,d5				; out bits
	moveq	#0,d7				; k
	move.l	PW_CORN(a5),a3
pw_l:	cmp.l	#4,d7
	bge.s	pw_e
	fsmove.s (a3,d7.l*8),fp2		; lx = corner x cr, lz = corner z cp
	fsmul.s	WL_CR(a6),fp2
	fsmove.s 4(a3,d7.l*8),fp3
	fsmul.s	WL_CP(a6),fp3
	fsmove.x fp6,fp0			; px = c.x + rx lx + fx lz
	fsmul.x	fp2,fp0
	fsadd.s	CS_X(a4),fp0
	fsmove.x fp4,fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,WL_PX(a6,d7.l*4)
	fsmove.x fp7,fp0			; py = c.y + ry lx + fy lz
	fsmul.x	fp2,fp0
	fsadd.s	CS_Y(a4),fp0
	fsmove.x fp5,fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,WL_PY(a6,d7.l*4)
	clr.l	-(sp)				; on the track?
	clr.l	-(sp)
	move.l	WL_PY(a6,d7.l*4),-(sp)
	move.l	WL_PX(a6,d7.l*4),-(sp)
	move.l	PW_UNDER(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	tst.l	d0
	bne.s	pw_n
	bset	d7,d5
pw_n:	addq.l	#1,d7
	bra.s	pw_l
pw_e:	tst.l	d5
	beq	pw_out				; all four on it
	clr.l	WL_MX(a6)
	clr.l	WL_MY(a6)
	clr.l	WL_WA(a6)
	moveq	#0,d7
pw_w:	cmp.l	#4,d7
	bge	pw_m
	btst	d7,d5
	beq	pw_wn
	pea	WL_IDX(a6)			; the nearest wall
	move.l	WL_PY(a6,d7.l*4),-(sp)
	move.l	WL_PX(a6,d7.l*4),-(sp)
	move.l	PW_NEAR(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	move.l	WL_IDX(a6),d6
	bmi	pw_wn
	move.l	d6,d0
	lsl.l	#5,d0
	move.l	PW_WALLS(a5),a3
	add.l	d0,a3				; w
	pea	WL_NC(a6)			; its normal: cos, -sin of its angle
	pea	WL_NS(a6)
	move.l	(a3),-(sp)
	move.l	PW_SC(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	fsmove.s WL_NC(a6),fp2			; nx
	fsmove.s WL_NS(a6),fp3
	fsneg.x	fp3				; ny
	fsmove.s WL_PX(a6,d7.l*4),fp0		; across = (px - w.x) nx + (py - w.y) ny
	fssub.s	4(a3),fp0
	fsmul.x	fp2,fp0
	fsmove.s WL_PY(a6,d7.l*4),fp1
	fssub.s	8(a3),fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	move.l	PW_IN(a5),a0
	fsmove.s (a0,d6.l*4),fp4		; in
	fsmul.x	fp4,fp0				; depth
	fcmp.s	K_30(pc),fp0
	fbge	pw_wn
	fsmove.s K_30(pc),fp1			; push = (30 - depth) in
	fssub.x	fp0,fp1
	fsmul.x	fp4,fp1
	fsmove.x fp1,fp5			; qx = push nx, qy = push ny
	fsmul.x	fp2,fp5
	fsmove.x fp1,fp6
	fsmul.x	fp3,fp6
	fsabs.x	fp5,fp0
	fsmove.s WL_MX(a6),fp1
	fsabs.x	fp1
	fcmp.x	fp1,fp0
	fble	pw_y
	fmove.s	fp5,WL_MX(a6)
	move.l	(a3),WL_WA(a6)
pw_y:	fsabs.x	fp6,fp0
	fsmove.s WL_MY(a6),fp1
	fsabs.x	fp1
	fcmp.x	fp1,fp0
	fble	pw_wn
	fmove.s	fp6,WL_MY(a6)
	move.l	(a3),WL_WA(a6)
pw_wn:	addq.l	#1,d7
	bra	pw_w
pw_m:	fsmove.s WL_MX(a6),fp0			; off the surface but not at a wall: nothing
	ftst.x	fp0
	fbne	pw_mv
	fsmove.s WL_MY(a6),fp0
	ftst.x	fp0
	fbeq	pw_out
pw_mv:	fsmove.s WL_MX(a6),fp0			; the car put back
	fsadd.s	CS_X(a4),fp0
	fmove.s	fp0,CS_X(a4)
	fsmove.s WL_MY(a6),fp0
	fsadd.s	CS_Y(a4),fp0
	fmove.s	fp0,CS_Y(a4)
	move.l	WL_WA(a6),-(sp)			; the wall's answer
	move.l	WL_MY(a6),-(sp)
	move.l	WL_MX(a6),-(sp)
	move.l	d5,-(sp)
	move.l	PW_TAIL(a5),a0
	jsr	(a0)
	lea	16(sp),sp
pw_out:	lea	WL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; void dr68k(const dr_ctx *x): drive.c drive_step (drive_step_c the reference, OS_DRASM=c compares them): integrate,
; engine, pedals, steering, skid -- every float operation as gcc compiles them, sinf / cosf / tanf through C.
; void dhw68k(const dr_ctx *x, float push_x, push_y, side, wall_angle): drive_hit_wall.
DR_CAR	equ	0
DR_IN	equ	4
DR_DAMP	equ	8
DR_SIN	equ	12
DR_COS	equ	16
DR_TAN	equ	20
DR_CHORD equ	24				; dr_chord(car): the turn's chord (C: its whole-number sums)
; car_state (more)
CS_MAXSPD equ	16
CS_MAXRPM equ	20
CS_GRIP	equ	24
CS_ACCEL equ	28
CS_AUTO	equ	32
CS_NSHIFT equ	36
CS_RATIO equ	40
CS_RPM	equ	96
CS_GEAR	equ	100
CS_LAUNCH equ	104
CS_WAIT	equ	108
CS_ANALOG equ	112
CS_THR	equ	116
CS_BRAKE equ	120
CS_STEER equ	124
CS_SMAX	equ	128
CS_TURN	equ	132
CS_RADIUS equ	136
CS_LOCK	equ	140
CS_SLIP	equ	144
CS_SWANT equ	148
CS_SLIDE equ	152
CS_SPIN	equ	160
CS_YAWR	equ	164
CS_SHOVE equ	168
CS_SHX	equ	172
CS_SHY	equ	176
CS_WB	equ	180
CS_SURF	equ	184
CS_SDX	equ	192
CS_SDY	equ	196
CS_KRPM	equ	216
CS_KEB	equ	220
CS_KBRAKE equ	224
CS_GSLIDE equ	232
CS_GSPIN equ	236
CS_GDEC	equ	240
CS_GLOCK equ	244
CS_LEND	equ	248				; launch_end, front_out, timeout (drive.h)
CS_FOUT	equ	252
CS_TOUT	equ	256
CS_CRASH equ	260				; crash, rear_z, chord_x, chord_y (drive.h)
CS_CHX	equ	268
CS_CHY	equ	272
; locals (a6)
DL_T	equ	0
DL_S	equ	4
DL_C	equ	8
DL_A	equ	12
DL_SLP	equ	16				; sinf(pitch): the slope (OS_ORIG_TICK's handling)
DL_LOC	equ	20

; *v = (*v - fp1) damp(i) + fp1   (\1 the field, \2 the damp's number)
APPR	macro
	fsmove.s \1(a4),fp0
	fssub.x	fp1,fp0
	fsmul.s	(\2)*4(a3),fp0
	fsadd.x	fp1,fp0
	fmove.s	fp0,\1(a4)
	endm
; fp0 = f(\2) as the C library returns it (\1 the context's pointer to sinf / tanf)
CALLR	macro
	move.l	\2,-(sp)
	move.l	\1(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	endm
; \3 = f(\2) through the context's C function at \1 (\2, \3 effective addresses)
CALLF	macro
	pea	\3
	move.l	\2,-(sp)
	move.l	\1(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	endm

	xdef	_dr68k
	xdef	dr68k
_dr68k:
dr68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-DL_LOC(sp),sp
	move.l	sp,a6
	move.l	DL_LOC+72+48(sp),a5
	move.l	DR_CAR(a5),a4
	move.l	DR_IN(a5),a2
	move.l	DR_DAMP(a5),a3
	bsr	dr_int
	bsr	dr_eng
	bsr	dr_ped
	bsr	dr_steer
	bsr	dr_skid
	tst.l	CS_LAUNCH(a4)			; the launch turns the car with the steering, once a picture, in gear
	beq.s	dr_e1
	tst.l	CS_GEAR(a4)
	beq.s	dr_e1
	fsmove.s CS_STEER(a4),fp0
	fsmul.s	K_03(pc),fp0
	fsadd.s	CS_YAW(a4),fp0
	fmove.s	fp0,CS_YAW(a4)
dr_e1:	clr.l	CS_LEND(a4)
	lea	DL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; fp0 = sqrt0(fp0): 0 below 0
dr_sq0:	ftst.x	fp0
	fbge	dq_1
	fsmove.s K_ZERO(pc),fp0
	rts
dq_1:	fssqrt.x fp0,fp0
	rts

; integrate (0x16f34, the original's): the heading into 0..2 pi first; whole-number positions, cut after each move
dr_int:	fsmove.s CS_YAW(a4),fp0
	ftst.x	fp0
	fbge	di_w1
	fsadd.s	K_2PI(pc),fp0
	fmove.s	fp0,CS_YAW(a4)
di_w1:	fcmp.s	K_2PI(pc),fp0
	fble	di_w2
	fssub.s	K_2PI(pc),fp0
	fmove.s	fp0,CS_YAW(a4)
di_w2:	tst.l	CS_LAUNCH(a4)
	bne	di_st
	tst.l	CS_CRASH(a4)
	bne	di_st
	fsmove.s CS_STEER(a4),fp0
	ftst.x	fp0
	fbne	di_ch
	CALLF	DR_COS,CS_PITCH(a4),DL_T(a6)	; straight: x += sin cp speed dt, y += cos (-cp) speed dt
	fsmove.s DL_T(a6),fp2			; cp
	CALLR	DR_SIN,CS_YAW(a4)
	fmove.s	fp0,DL_S(a6)
	CALLF	DR_COS,CS_YAW(a4),DL_C(a6)
	fsmove.s DL_S(a6),fp0
	fsmul.x	fp2,fp0
	fsmul.s	CS_SPEED(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	CS_X(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_X(a4)
	fsneg.x	fp2,fp1
	fsmove.s DL_C(a6),fp0
	fsmul.x	fp1,fp0
	fsmul.s	CS_SPEED(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	CS_Y(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_Y(a4)
	bra	di_sh
di_ch:	CALLF	DR_COS,CS_ROLL(a4),DL_T(a6)	; turning: along the chord, |cos roll| of it
	fsmove.s DL_T(a6),fp2
	fsabs.x	fp2
	fsmove.x fp2,fp0
	fsmul.s	CS_CHX(a4),fp0
	fsadd.s	CS_X(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_X(a4)
	fsmove.x fp2,fp0
	fsmul.s	CS_CHY(a4),fp0
	fsadd.s	CS_Y(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_Y(a4)
	bra	di_sh
di_st:	CALLR	DR_SIN,CS_YAW(a4)		; the launch, a crash: straight on, the slope not counted
	fmove.s	fp0,DL_S(a6)
	CALLF	DR_COS,CS_YAW(a4),DL_C(a6)
	fsmove.s DL_S(a6),fp0
	fsmul.s	CS_SPEED(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	CS_X(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_X(a4)
	fsmove.s DL_C(a6),fp0
	fsmul.s	CS_SPEED(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsmove.s CS_Y(a4),fp1
	fssub.x	fp0,fp1
	fintrz.x fp1
	fmove.s	fp1,CS_Y(a4)
di_sh:	fsmove.s CS_SHX(a4),fp0			; shoved off a wall
	fsmul.s	CS_SHOVE(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	CS_X(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_X(a4)
	fsmove.s CS_SHY(a4),fp0
	fsmul.s	CS_SHOVE(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	CS_Y(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_Y(a4)
	fsmove.s CS_YAWR(a4),fp0		; yaw_rate damped (80), into the heading
	fsmul.s	80*4(a3),fp0
	fmove.s	fp0,CS_YAWR(a4)
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	CS_YAW(a4),fp0
	fmove.s	fp0,CS_YAW(a4)
	fsmove.s CS_SHOVE(a4),fp0		; the shove damped (91), gone under 250
	fsmul.s	91*4(a3),fp0
	fsabs.x	fp0,fp1
	fcmp.s	K_250(pc),fp1
	fbge	di_1
	fsmove.s K_ZERO(pc),fp0
di_1:	fmove.s	fp0,CS_SHOVE(a4)
	CALLF	DR_COS,CS_ROLL(a4),DL_T(a6)	; k = sqrt0(|cos roll| 2)
	fsmove.s DL_T(a6),fp0
	fsabs.x	fp0
	fsmul.s	K_TWO(pc),fp0
	bsr	dr_sq0
	fsmul.s	g_dt_smooth,fp0			; running wide: (k dt) (slide sd)
	fsmove.x fp0,fp2
	fsmove.s CS_SLIDE(a4),fp0
	fsmul.s	CS_SDX(a4),fp0
	fsmul.x	fp2,fp0
	fsadd.s	CS_X(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_X(a4)
	fsmove.s CS_SLIDE(a4),fp0
	fsmul.s	CS_SDY(a4),fp0
	fsmul.x	fp2,fp0
	fsadd.s	CS_Y(a4),fp0
	fintrz.x fp0
	fmove.s	fp0,CS_Y(a4)
	rts

; the engine and gearbox (0x18da0); fp7 = M (maxrpm)
dr_eng:	fsmove.s CS_MAXRPM(a4),fp7
	tst.l	CS_TOUT(a4)			; the time up or the car finished (0x118e1d bit 6): the engine follows
	beq.s	de_0				; the pedal (j 0x3d), no gearbox, no drive
	fsmove.s CS_THR(a4),fp1
	fsmul.x	fp7,fp1
	APPR	CS_RPM,$3d
	bra	de_end
de_0:	tst.l	CS_WAIT(a4)
	beq.s	de_1
	fsmove.s CS_THR(a4),fp1			; before the green: the engine follows the pedal
	fsmul.x	fp7,fp1
	APPR	CS_RPM,$4b
	bra	de_end
de_1:	tst.l	CS_AUTO(a4)
	bne.s	de_au
	tst.l	12(a2)				; by hand
	ble.s	de_m2
	move.l	CS_GEAR(a4),d1
	cmp.l	CS_NSHIFT(a4),d1
	bge.s	de_m2
	addq.l	#1,CS_GEAR(a4)
de_m2:	tst.l	12(a2)
	bge	de_g
	tst.l	CS_GEAR(a4)
	ble	de_g
	subq.l	#1,CS_GEAR(a4)
	bra.s	de_g
de_au:	move.l	CS_GEAR(a4),d0			; automatic: up past 8500 + gear, down below 4000 - gear
	add.l	#8500,d0
	fsmove.l d0,fp1
	fsmove.s CS_RPM(a4),fp0
	fcmp.x	fp1,fp0
	fble	de_a2
	move.l	CS_GEAR(a4),d0
	cmp.l	CS_NSHIFT(a4),d0
	bge.s	de_a3
	addq.l	#1,CS_GEAR(a4)
	bra.s	de_a3
de_a2:	move.l	#4000,d0
	sub.l	CS_GEAR(a4),d0
	fsmove.l d0,fp1
	fcmp.x	fp1,fp0
	fbge	de_a3
	cmp.l	#1,CS_GEAR(a4)
	ble.s	de_a3
	subq.l	#1,CS_GEAR(a4)
de_a3:	tst.l	CS_LAUNCH(a4)
	beq.s	de_g
	move.l	#1,CS_GEAR(a4)
de_g:	tst.l	CS_GEAR(a4)
	bne.s	de_drv
	fsmove.s CS_SPEED(a4),fp0		; neutral: coasting
	fssub.s	g_dt500,fp0
	ftst.x	fp0
	fbge	de_n1
	fsmove.s K_ZERO(pc),fp0
de_n1:	fmove.s	fp0,CS_SPEED(a4)
	fsmove.s CS_THR(a4),fp1
	fsmul.x	fp7,fp1
	APPR	CS_RPM,$4b
	bra	de_end
de_drv:	CALLR	DR_SIN,CS_PITCH(a4)		; the slope: sinf(pitch) (its fp0 as it comes)
	fmove.s	fp0,DL_SLP(a6)
	move.l	CS_GEAR(a4),d0
	fsmove.s CS_RATIO(a4,d0.l*4),fp6	; ratio
	fsmul.s	K_FOUR(pc),fp0			; top = maxspd - (slope 4 + 1) 1000
	fsadd.s	K_ONE(pc),fp0
	fsmul.s	K_1000(pc),fp0
	fsmove.s CS_MAXSPD(a4),fp5
	fssub.x	fp0,fp5
	fsmove.s CS_GRIP(a4),fp0		; locked to the wheels, or spinning off the line
	fsmul.s	K_6000(pc),fp0
	fsmove.s CS_RPM(a4),fp1
	fcmp.x	fp0,fp1
	fble	de_lk
	fsmove.s CS_SPEED(a4),fp0
	fcmp.s	K_2000(pc),fp0
	fbge	de_lk
	fsmove.s (a2),fp0
	fcmp.s	K_THR(pc),fp0
	fble	de_lk
	tst.l	CS_CRASH(a4)			; (a state only over none)
	bne.s	de_lc
	move.l	#1,CS_LAUNCH(a4)
de_lc:
	fsmove.s CS_RPM(a4),fp0
	fssub.s	g_dt500,fp0
	fmove.s	fp0,CS_RPM(a4)
	bra.s	de_pl
de_lk:	fsmove.x fp6,fp0
	fsmul.s	CS_SPEED(a4),fp0
	fsmul.s	CS_KRPM(a4),fp0
	fmove.s	fp0,CS_RPM(a4)
	tst.l	CS_LAUNCH(a4)			; (state 5 -> 6: no grip work this step)
	beq.s	de_lk1
	move.l	#1,CS_LEND(a4)
de_lk1:	clr.l	CS_LAUNCH(a4)
de_pl:	fsmove.s CS_KRPM(a4),fp0		; vgear = M / (k_rpm ratio)
	fsmul.x	fp6,fp0
	fsmove.x fp7,fp4
	fsdiv.x	fp0,fp4
	cmp.l	#1,CS_NSHIFT(a4)
	bne.s	de_mu
	fsmove.s CS_ACCEL(a4),fp3		; one gear: pull = accel, curve = sqrt0(1 - speed / vgear)
	fsmove.s CS_SPEED(a4),fp0
	fsdiv.x	fp4,fp0
	fsmove.s K_ONE(pc),fp1
	fssub.x	fp0,fp1
	fsmove.x fp1,fp0
	bsr	dr_sq0
	fsmove.x fp0,fp2
	bra	de_r
de_mu:	fsmove.x fp4,fp0			; a = 2 - (vgear - speed) / (vgear / 2) - 1
	fssub.s	CS_SPEED(a4),fp0
	fsmove.x fp4,fp1
	fsmul.s	K_HALF(pc),fp1
	fsdiv.x	fp1,fp0
	fsmove.s K_TWO(pc),fp1
	fssub.x	fp0,fp1
	fssub.s	K_ONE(pc),fp1
	cmp.l	#1,CS_GEAR(a4)
	bne.s	de_m1
	ftst.x	fp1
	fbge	de_m1
	fsmove.s K_02(pc),fp1
de_m1:	fsmul.s	K_PI2B(pc),fp1			; curve = (1 + sin(a pi/2)) / 2
	fmove.s	fp1,DL_A(a6)
	CALLR	DR_SIN,DL_A(a6)
	fsadd.s	K_ONE(pc),fp0			; (sinf's fp0 as it comes)
	fsmul.s	K_HALF(pc),fp0
	fsmove.x fp0,fp2
	move.l	CS_GEAR(a4),d0			; pull = accel x the gear's
	lea	K_PULL(pc),a0
	fsmove.s CS_ACCEL(a4),fp3
	fsmul.s	(a0,d0.l*4),fp3
de_r:	fsmove.s CS_THR(a4),fp0			; rpm < throttle M: rpm += throttle pull curve dt
	fsmul.x	fp7,fp0
	fsmove.s CS_RPM(a4),fp1
	fcmp.x	fp0,fp1
	fbge	de_r2
	fsmove.s CS_THR(a4),fp0
	fsmul.x	fp3,fp0
	fsmul.x	fp2,fp0
	fsmove.s DL_SLP(a6),fp1			; - slope 100 (uphill the engine gains less)
	fsmul.s	K_100(pc),fp1
	fssub.x	fp1,fp0
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	CS_RPM(a4),fp0
	fmove.s	fp0,CS_RPM(a4)
de_r2:	fsmove.s CS_RPM(a4),fp1
	fcmp.x	fp7,fp1
	fbgt	de_ov
	fsmove.s CS_THR(a4),fp0			; engine braking
	fsmul.x	fp7,fp0
	fcmp.x	fp1,fp0
	fbge	de_sp
	fsmove.x fp1,fp0
	fsdiv.x	fp7,fp0
	bsr	dr_sq0
	fsmul.s	CS_KEB(a4),fp0
	fsmul.s	g_dt_smooth,fp0
	fsmove.s CS_RPM(a4),fp1
	fssub.x	fp0,fp1
	fmove.s	fp1,CS_RPM(a4)
	bra.s	de_cl
de_ov:	fsmove.s DL_SLP(a6),fp0			; over-revving: rpm -= (slope 100 + 4000 + (rpm - M) 2) dt
	fsmul.s	K_100(pc),fp0
	fsadd.s	K_4000(pc),fp0
	fsmove.x fp1,fp2
	fssub.x	fp7,fp2
	fsadd.x	fp2,fp2
	fsadd.x	fp2,fp0
	fsmul.s	g_dt_smooth,fp0
	fssub.x	fp0,fp1
	fmove.s	fp1,CS_RPM(a4)
de_cl:	fsmove.x fp7,fp0			; not below M throttle
	fsmul.s	CS_THR(a4),fp0
	fsmove.s CS_RPM(a4),fp1
	fcmp.x	fp0,fp1
	fbge	de_sp
	fmove.s	fp0,CS_RPM(a4)
de_sp:	fsmove.s CS_SPEED(a4),fp2		; before
	tst.l	CS_LAUNCH(a4)
	beq.s	de_s1
	fsmove.x fp2,fp0
	fsadd.s	g_dt1000,fp0
	bra.s	de_s2
de_s1:	fsmove.s CS_RPM(a4),fp0
	fsmove.s CS_KRPM(a4),fp1
	fsmul.x	fp6,fp1
	fsdiv.x	fp1,fp0
de_s2:	fcmp.x	fp5,fp0
	fble	de_s3
	fsmove.x fp5,fp0
de_s3:	fmove.s	fp0,CS_SPEED(a4)
	fsmove.s CS_GDEC(a4),fp1		; slowing faster than the tyres manage: locked
	fsmul.s	g_dt_smooth,fp1
	fsmove.x fp2,fp3
	fssub.x	fp0,fp3
	fcmp.x	fp3,fp1
	fbge	de_end
	move.l	K_ONE(pc),CS_LOCK(a4)
de_end:	fsmove.s CS_SPEED(a4),fp0		; stopped: neutral
	fcmp.s	g_dt500,fp0
	fbge	de_x
	clr.l	CS_GEAR(a4)
de_x:	rts

; the pedals (0x16094 / 0x16140)
dr_ped:	fsmove.s CS_THR(a4),fp0
	ftst.x	fp0
	fblt	dp_0
	fsmove.s CS_SWANT(a4),fp0
	ftst.x	fp0
	fbne	dp_0
	fsmove.s CS_LOCK(a4),fp0
	ftst.x	fp0
	fbne	dp_0
	tst.l	CS_SPIN(a4)
	bne.s	dp_0
	tst.l	CS_LAUNCH(a4)			; (nor in the launch, its end, a crash, the time up)
	bne.s	dp_0
	tst.l	CS_LEND(a4)
	bne.s	dp_0
	tst.l	CS_CRASH(a4)
	bne.s	dp_0
	tst.l	CS_TOUT(a4)
	bne.s	dp_0
	move.l	(a2),CS_THR(a4)
	bra.s	dp_1
dp_0:	clr.l	CS_THR(a4)
dp_1:	move.l	4(a2),d0			; the brake (the time up: 512 / 1023)
	tst.l	CS_TOUT(a4)
	beq.s	dp_1a
	move.l	K_512(pc),d0
dp_1a:	fsmove.s d0,fp0
	ftst.x	fp0
	fbgt	dp_b1
	clr.l	CS_BRAKE(a4)
	bra.s	dp_b3
dp_b1:	btst	#2,CS_ANALOG+3(a4)
	beq.s	dp_b2
	move.l	d0,CS_BRAKE(a4)
	bra.s	dp_b3
dp_b2:	fsmove.s K_ONE(pc),fp1
	APPR	CS_BRAKE,$52
dp_b3:	fsmove.s CS_DRIFT(a4),fp0		; the drift itself under 0.1, not its size
	fcmp.s	K_01(pc),fp0
	fbnlt	dp_x
	fsmove.s CS_KBRAKE(a4),fp0		; speed -= k_brake dt brake
	fsmul.s	g_dt_smooth,fp0
	fsmul.s	CS_BRAKE(a4),fp0
	fsmove.s CS_SPEED(a4),fp1
	fssub.x	fp0,fp1
	ftst.x	fp1
	fbge	dp_2
	fsmove.s K_ZERO(pc),fp1
dp_2:	fmove.s	fp1,CS_SPEED(a4)
	fsmove.s CS_BRAKE(a4),fp0		; braking that hard: locked, or on the grass a spin
	fsmul.x	fp1,fp0
	fcmp.s	CS_GLOCK(a4),fp0
	fble	dp_x
	tst.l	CS_SPIN(a4)
	bne.s	dp_x
	tst.l	CS_ROUGH(a4)
	beq.s	dp_l
	move.l	#1,CS_SPIN(a4)
	bra.s	dp_x
dp_l:	move.l	CS_BRAKE(a4),CS_LOCK(a4)
dp_x:	rts

; the steering (0x1628c); d6 = the stiffness
dr_steer:
	tst.l	CS_LAUNCH(a4)
	beq.s	ds_1
	move.l	#$58,d6
	bra.s	ds_3
ds_1:	move.l	#$55,d6
	fsmove.s CS_LOCK(a4),fp0
	ftst.x	fp0
	fbne	ds_3
	fsmove.s CS_SWANT(a4),fp0
	ftst.x	fp0
	fbne	ds_3
	tst.l	CS_SPIN(a4)
	bne.s	ds_3
	move.l	#$50,d6
ds_3:	fsmove.s CS_SPEED(a4),fp0		; steer_max = (1 - sqrt0(speed / maxspd)) 0.296706 + 0.0174533
	fsdiv.s	CS_MAXSPD(a4),fp0
	bsr	dr_sq0
	fsmove.s K_ONE(pc),fp1
	fssub.x	fp0,fp1
	fsmul.s	K_SM1(pc),fp1
	fsadd.s	K_SM2(pc),fp1
	fmove.s	fp1,CS_SMAX(a4)
	fsmove.s 8(a2),fp1			; want
	fsmul.s	CS_SMAX(a4),fp1
	btst	#1,CS_ANALOG+3(a4)
	beq.s	ds_4
	cmp.l	#$50,d6
	bne.s	ds_4
	fmove.s	fp1,CS_STEER(a4)
	bra.s	ds_5
ds_4:	fsmove.s CS_STEER(a4),fp0		; eased
	fssub.x	fp1,fp0
	fsmul.s	(a3,d6.l*4),fp0
	fsadd.x	fp1,fp0
	fmove.s	fp0,CS_STEER(a4)
ds_5:	fsmove.s CS_STEER(a4),fp0
	fsabs.x	fp0
	fcmp.s	K_1EM5(pc),fp0
	fbge	ds_6
	clr.l	CS_STEER(a4)
ds_6:	tst.l	CS_ROUGH(a4)			; the grass tugs the wheel
	beq	ds_8
	fintrz.s CS_X(a4),fp0
	fmove.l	fp0,d0
	fintrz.s CS_Y(a4),fp0
	fmove.l	fp0,d1
	add.l	d1,d0
	moveq	#$3f,d1
	and.l	d0,d1
	fsmove.l d1,fp2
	fsmul.s	K_0008(pc),fp2
	fsmove.s K_ONE(pc),fp0
	btst	#0,d0
	beq.s	ds_t
	fsmove.s K_M1(pc),fp0
ds_t:	fsmul.x	fp0,fp2				; tug
	fsmove.s CS_SPEED(a4),fp0
	fsdiv.s	CS_MAXSPD(a4),fp0
	fsmove.s K_ONE(pc),fp1
	fssub.x	fp0,fp1
	fsmove.x fp1,fp0
	bsr	dr_sq0
	fsmul.x	fp2,fp0
	fsadd.s	CS_STEER(a4),fp0
	fmove.s	fp0,CS_STEER(a4)
	fsabs.x	fp0,fp1
	fcmp.s	CS_SMAX(a4),fp1
	fble	ds_8
	move.l	CS_SMAX(a4),d0
	ftst.x	fp0
	fbge	ds_7
	bchg	#31,d0
ds_7:	move.l	d0,CS_STEER(a4)
ds_8:	fsmove.s CS_STEER(a4),fp0		; no steering towards a front corner off the track
	ftst.x	fp0
	fbngt	ds_8b
	btst	#0,CS_FOUT+3(a4)
	beq.s	ds_8c
	bra.s	ds_8z
ds_8b:	fbnlt	ds_8c
	btst	#1,CS_FOUT+3(a4)
	beq.s	ds_8c
ds_8z:	clr.l	CS_STEER(a4)
ds_8c:	tst.l	CS_CRASH(a4)			; nor in a crash
	beq.s	ds_8d
	clr.l	CS_STEER(a4)
ds_8d:	fsmove.s CS_STEER(a4),fp0
	ftst.x	fp0
	fbeq	ds_9
	move.l	CS_STEER(a4),-(sp)		; radius = wheelbase / tanf(steer) (its fp0 as it comes)
	move.l	DR_TAN(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	fsmove.s CS_WB(a4),fp1
	fsdiv.x	fp0,fp1
	fsmove.x fp1,fp0
	fmove.s	fp0,CS_RADIUS(a4)
	fsmove.s g_dt_smooth,fp1			; turn = dt speed / radius
	fsmul.s	CS_SPEED(a4),fp1
	fsdiv.x	fp0,fp1
	fmove.s	fp1,CS_TURN(a4)
	fsadd.s	CS_YAW(a4),fp1
	fmove.s	fp1,CS_YAW(a4)
	move.l	a4,-(sp)			; the chord (C)
	move.l	DR_CHORD(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	rts
ds_9:	clr.l	CS_RADIUS(a4)
	clr.l	CS_TURN(a4)
	rts

; the skid and spin (0x17d04 / 0x188a8)
dr_skid:
	tst.l	CS_SPIN(a4)
	bne	dk_sl
	tst.l	CS_LAUNCH(a4)			; (nothing of this in the launch either)
	bne	dk_sl
	tst.l	CS_LEND(a4)
	bne	dk_sl
	tst.l	CS_CRASH(a4)
	bne	dk_sl
	fsmove.s CS_LOCK(a4),fp0
	ftst.x	fp0
	fbeq	dk_g
	tst.l	CS_TOUT(a4)			; a lock counts only while there is time
	beq	dk_lk
dk_g:
	fsmove.s CS_SPEED(a4),fp2		; f = speed^2 turn 0.0001 / dt surface + the grass x the turn's sign
	fsmul.s	CS_SPEED(a4),fp2
	fsmul.s	CS_TURN(a4),fp2
	fsmul.s	K_1EM4(pc),fp2
	fsdiv.s	g_dt_smooth,fp2
	fsmul.s	CS_SURF(a4),fp2
	move.l	CS_GRASS(a4),d0
	add.l	CS_GRASS+8(a4),d0
	muls.l	#1000,d0
	move.l	CS_GRASS+4(a4),d1
	add.l	CS_GRASS+12(a4),d1
	muls.l	#600,d1
	add.l	d1,d0
	fsmove.l d0,fp0
	fsmove.s K_ONE(pc),fp1
	fsmove.s CS_TURN(a4),fp3
	ftst.x	fp3
	fbge	dk_1
	fsmove.s K_M1(pc),fp1
dk_1:	fsmul.x	fp1,fp0
	fsadd.x	fp0,fp2				; f
	fsabs.x	fp2,fp0
	fcmp.s	CS_GSLIDE(a4),fp0
	fbgt	dk_2
	clr.l	CS_SWANT(a4)			; within the grip
	clr.l	CS_SLIP(a4)
	bra	dk_an
dk_2:	fsmove.s CS_BRAKE(a4),fp0
	fsadd.s	K_HALF(pc),fp0
	fsmul.x	fp2,fp0
	fcmp.s	CS_GSPIN(a4),fp0
	fbgt	dk_sp1
	fsmove.s CS_GSLIDE(a4),fp0		; past it: f +- grip_slide
	ftst.x	fp2
	fble	dk_3
	fsneg.x	fp0
dk_3:	fsadd.x	fp0,fp2
	fsmove.x fp2,fp0			; slip = f 0.00015, at most 1.53938
	fsmul.s	K_15EM5(pc),fp0
	fsabs.x	fp0,fp1
	fcmp.s	K_SLIPM(pc),fp1
	fble	dk_4
	fsmove.s K_SLIPM(pc),fp0
	ftst.x	fp2
	fbge	dk_4
	fsneg.x	fp0
dk_4:	fmove.s	fp0,CS_SLIP(a4)
	fsmove.s CS_RADIUS(a4),fp1		; slide_want = surface 0.2 (speed^2 / radius)
	ftst.x	fp1
	fbeq	dk_5z
	fsmove.s CS_SPEED(a4),fp0
	fsmul.s	CS_SPEED(a4),fp0
	fsdiv.x	fp1,fp0
	fsmove.s CS_SURF(a4),fp1
	fsmul.s	K_02(pc),fp1
	fsmul.x	fp1,fp0
	bra.s	dk_5
dk_5z:	fsmove.s K_ZERO(pc),fp0
dk_5:	fmove.s	fp0,CS_SWANT(a4)
	fsmove.s CS_YAW(a4),fp0			; which way: (sin, -cos) of heading - 90 deg
	fssub.s	K_PI2B(pc),fp0
	fmove.s	fp0,DL_A(a6)
	CALLR	DR_SIN,DL_A(a6)
	fmove.s	fp0,CS_SDX(a4)
	CALLF	DR_COS,DL_A(a6),CS_SDY(a4)
	bchg	#7,CS_SDY(a4)
	bra	dk_an
dk_sp1:	move.l	#1,CS_SPIN(a4)
	bra	dk_an
dk_lk:	fsmove.s CS_LOCK(a4),fp0		; locked: slide straight on
	fsmul.s	98*4(a3),fp0
	fmove.s	fp0,CS_LOCK(a4)
	fsmul.s	CS_SPEED(a4),fp0
	fcmp.s	K_2000(pc),fp0
	fbge	dk_l1
	clr.l	CS_LOCK(a4)
dk_l1:	fsmove.s CS_LOCK(a4),fp1		; target: the lock's share of the speed, the turn's way, x dt x 7
	fsmul.s	CS_SPEED(a4),fp1
	fsdiv.s	CS_MAXSPD(a4),fp1
	fsmove.s CS_TURN(a4),fp0
	ftst.x	fp0
	fbge	dk_l2
	fsneg.x	fp1
dk_l2:	fsmul.s	g_dt_smooth,fp1
	fsmul.s	K_SEVEN(pc),fp1
	APPR	CS_SLIP,7
	fsmove.s CS_SLIP(a4),fp0
	fsmul.s	K_02(pc),fp0
	fsadd.s	CS_YAW(a4),fp0
	fmove.s	fp0,CS_YAW(a4)
dk_an:	CALLF	DR_COS,CS_ROLL(a4),DL_T(a6)	; drift eases to sqrt0(|cos roll| 2) slip (0x5a, through a sine near it)
	fsmove.s DL_T(a6),fp0
	fsabs.x	fp0
	fsmul.s	K_TWO(pc),fp0
	bsr	dr_sq0
	fsmul.s	CS_SLIP(a4),fp0
	fsmove.x fp0,fp2			; target
	fsmove.s CS_DRIFT(a4),fp0
	fsmove.x fp2,fp1
	fssub.x	fp0,fp1
	fsabs.x	fp1
	fcmp.s	K_PI2A(pc),fp1
	fbge	dk_li
	fssub.x	fp2,fp0
	fmove.s	fp0,DL_A(a6)
	CALLR	DR_SIN,DL_A(a6)
	fsmul.s	$5a*4(a3),fp0			; (sinf's fp0 as it comes)
	fsadd.x	fp2,fp0
	fmove.s	fp0,CS_DRIFT(a4)
	bra.s	dk_sl
dk_li:	fsmove.x fp2,fp1
	APPR	CS_DRIFT,$5a
dk_sl:	fsmove.s CS_SWANT(a4),fp1		; slide eases to slide_want (0x50), nothing under 10
	fsmove.s CS_SLIDE(a4),fp0
	fssub.x	fp1,fp0
	fsmul.s	$50*4(a3),fp0
	fsadd.x	fp1,fp0
	fcmp.s	K_TEN(pc),fp0
	fbge	dk_s0
	fsmove.s K_ZERO(pc),fp0
dk_s0:	fmove.s	fp0,CS_SLIDE(a4)
	move.l	CS_SPIN(a4),d0			; a spin: the tail round once, then settling
	cmp.l	#1,d0
	bne.s	dk_s2
	fsmove.s CS_TURN(a4),fp0
	ftst.x	fp0
	fblt	dk_s1
	move.l	#2,CS_SPIN(a4)
	fsmove.s CS_DRIFT(a4),fp0
	fssub.s	K_2PI(pc),fp0
	fmove.s	fp0,CS_DRIFT(a4)
	rts
dk_s1:	move.l	#4,CS_SPIN(a4)
	fsmove.s CS_DRIFT(a4),fp0
	fsadd.s	K_2PI(pc),fp0
	fmove.s	fp0,CS_DRIFT(a4)
	rts
dk_s2:	ble.s	dk_x
	fsmove.s CS_DRIFT(a4),fp1		; rate = (|drift| + 0.2) / pi 3 dt
	fsabs.x	fp1
	fsadd.s	K_02(pc),fp1
	fsdiv.s	K_PI(pc),fp1
	fsmul.s	K_THREE(pc),fp1
	fsmul.s	g_dt_smooth,fp1
	subq.l	#3,d0
	ble.s	dk_s3
	fsmove.s CS_DRIFT(a4),fp0
	fssub.x	fp1,fp0
	fmove.s	fp0,CS_DRIFT(a4)
	ftst.x	fp0
	fblt	dk_dn
	rts
dk_s3:	tst.l	d0
	beq.s	dk_x
	fsmove.s CS_DRIFT(a4),fp0
	fsadd.x	fp1,fp0
	fmove.s	fp0,CS_DRIFT(a4)
	ftst.x	fp0
	fbgt	dk_dn
dk_x:	rts
dk_dn:	clr.l	CS_DRIFT(a4)
	clr.l	CS_SPIN(a4)
	rts

	xdef	_dhw68k
	xdef	dhw68k
_dhw68k:
dhw68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-DL_LOC(sp),sp
	move.l	sp,a6
	lea	DL_LOC+72+48(sp),a1		; the arguments: x, push_x, push_y, side, wall_angle
	move.l	(a1)+,a5
	move.l	DR_CAR(a5),a4
	fsmove.s (a1),fp2			; push_x
	fsmove.s 4(a1),fp3			; push_y
	fsmove.s 8(a1),fp4			; side
	fsmove.s 12(a1),fp5			; wall_angle
	fsmove.x fp2,fp0			; len
	fsmul.x	fp2,fp0
	fsmove.x fp3,fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp6
	fcmp.s	K_1EM3(pc),fp6
	fblt	dh_x
	fsmove.s CS_YAW(a4),fp0			; square = |sin(yaw + wall_angle)|
	fsadd.x	fp5,fp0
	fmove.s	fp0,DL_A(a6)
	CALLR	DR_SIN,DL_A(a6)
	fsabs.x	fp0,fp7
	fsdiv.x	fp6,fp2				; shove_x, shove_y
	fmove.s	fp2,CS_SHX(a4)
	fsdiv.x	fp6,fp3
	fmove.s	fp3,CS_SHY(a4)
	fsmul.x	fp0,fp0				; shove = square^4 speed 2 + 2000, at most 5000 (as gcc: sinf's fp0 squared first)
	fsmul.x	fp7,fp0
	fsmul.x	fp7,fp0
	fsmul.s	CS_SPEED(a4),fp0
	fsmul.s	K_TWO(pc),fp0
	fsadd.s	K_2000(pc),fp0
	fcmp.s	K_5000(pc),fp0
	fble	dh_1
	fsmove.s K_5000(pc),fp0
dh_1:	fmove.s	fp0,CS_SHOVE(a4)
	fsmove.s CS_SPEED(a4),fp0		; speed -= speed 0.9 square
	fsmul.s	K_09(pc),fp0
	fsmul.x	fp7,fp0
	fsmove.s CS_SPEED(a4),fp1
	fssub.x	fp0,fp1
	ftst.x	fp1
	fbge	dh_2
	fsmove.s K_ZERO(pc),fp1
dh_2:	fmove.s	fp1,CS_SPEED(a4)
	fsmove.x fp4,fp0			; yaw_rate = side 5 square
	fsmul.s	K_FIVE(pc),fp0
	fsmul.x	fp7,fp0
	fmove.s	fp0,CS_YAWR(a4)
	clr.l	CS_LOCK(a4)
	clr.l	CS_SLIP(a4)
	clr.l	CS_SWANT(a4)
	tst.l	CS_SPIN(a4)
	bne.s	dh_x
	clr.l	CS_DRIFT(a4)
dh_x:	lea	DL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; void wheels68k(car_pose *w, float speed, float steer_part): main.c wheels_step at DRIVE_DT (wheels_step_c the
; reference, OS_WHASM=c): the reflections' slide and the wheels' turn, each wrapped as fmodf does it (exactly,
; without the 68060's missing fmod), the steer.
	xdef	_wheels68k
	xdef	wheels68k
_wheels68k:
wheels68k:
	fmovem.x fp2-fp4,-(sp)
	move.l	36+4(sp),a0			; w
	fsmove.s 36+8(sp),fp2			; speed dt
	fsmul.s	g_dt_smooth,fp2
	fsmove.s K_0002(pc),fp0			; env_scroll + speed dt (env ? 0.03 : 0.002), wrapped at 256
	tst.l	28(a0)
	beq.s	wh_1
	fsmove.s K_003(pc),fp0
wh_1:	fsmul.x	fp2,fp0
	fsadd.s	20(a0),fp0
	fsmove.s K_256(pc),fp1
	bsr	fmodr
	fmove.s	fp0,20(a0)
	fsdiv.s	K_1086(pc),fp2			; spin - speed dt / 108.6, wrapped at 6.2831853
	fsmove.s (a0),fp0
	fssub.x	fp2,fp0
	fsmove.s K_2PI(pc),fp1
	bsr	fmodr
	fmove.s	fp0,(a0)
	fsmove.s 36+12(sp),fp0			; steer = steer_part / 1.5
	fsdiv.s	K_15(pc),fp0
	fmove.s	fp0,4(a0)
	fmovem.x (sp)+,fp2-fp4
	rts

; fp0 = fmodf(fp0, fp1) (fp1 > 0, the quotient small): x - trunc(x / y) y in extended precision, which is exact,
; set right where the quotient's rounding was off by one; a zero with the sign of x (fp3 fp4 used)
fmodr:	fmove.x	fp0,fp3
	fdiv.x	fp1,fp3
	fintrz.x fp3
	fmul.x	fp1,fp3
	fmove.x	fp0,fp4
	fsub.x	fp3,fp4				; r
	ftst.x	fp0
	fblt	fm_n
	ftst.x	fp4				; x >= 0: 0 <= r < y
	fbge	fm_p1
	fadd.x	fp1,fp4
fm_p1:	fcmp.x	fp1,fp4
	fblt	fm_d
	fsub.x	fp1,fp4
	bra.s	fm_d
fm_n:	ftst.x	fp4				; x < 0: -y < r <= 0
	fble	fm_n1
	fsub.x	fp1,fp4
fm_n1:	fmove.x	fp1,fp3
	fneg.x	fp3
	fcmp.x	fp3,fp4
	fbgt	fm_d
	fadd.x	fp1,fp4
fm_d:	ftst.x	fp4
	fbne	fm_r
	fmove.x	fp0,fp4				; zero: the sign of x
	fmul.s	K_ZERO(pc),fp4
fm_r:	fmove.x	fp4,fp0
	rts

; ---------------------------------------------------------------------------------------------------------------
; void susp68k(const su_ctx *x): main.c suspension_step at DRIVE_DT (suspension_step_c the reference): each
; wheel's spring from the change of speed and the cornering, its bounce through cosf, the body's drop, roll and
; pitch through atanf -- cosf's and atanf's fp0 used as gcc uses them.
SU_W	equ	0
SU_C	equ	4
SU_MM	equ	8
SU_SUSP	equ	12
SU_PREV	equ	16
SU_D3D	equ	20
SU_D61	equ	24
SU_D71	equ	28
SU_COS	equ	32
SU_ATAN	equ	36

	xdef	_susp68k
	xdef	susp68k
_susp68k:
susp68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	move.l	72+48(sp),a5
	move.l	SU_C(a5),a4
	move.l	SU_SUSP(a5),a3
	move.l	SU_W(a5),a2
	move.l	SU_PREV(a5),a0			; a = (speed - prev) 0.00175 (50 / 30)
	fsmove.s CS_SPEED(a4),fp0
	fsmove.x fp0,fp3
	fssub.s	(a0),fp3
	fsmul.s	K_00175(pc),fp3
	fsmul.s	K_5030(pc),fp3
	fsmove.s CS_TURN(a4),fp4		; b = (turn / dt) speed speed 1.5e-9
	fsdiv.s	g_dt_smooth,fp4
	fsmul.x	fp0,fp4
	fsmul.x	fp0,fp4
	fsmul.s	K_15EM9(pc),fp4
	fmove.s	fp0,(a0)
	fsneg.x	fp3,fp6				; -a
	fsneg.x	fp4,fp5				; -b
	moveq	#0,d7				; n
su_l:	btst	#0,d7				; lng = (rear ? 3 a : -a) / (1 / 30)
	beq.s	su_1
	fsmove.x fp3,fp7
	fsmul.s	K_THREE(pc),fp7
	bra.s	su_2
su_1:	fsmove.x fp6,fp7
su_2:	fsdiv.s	g_dt_smooth,fp7			; (GAME_FRAME_T: the picture's time)
	fsmove.x fp5,fp0			; lat = (right ? b : -b) * 37
	btst	#1,d7
	beq.s	su_3
	fsmove.x fp4,fp0
su_3:	fsmul.s	K_LEAN(pc),fp0			; (main.c LEAN_FPS: the same lean at any picture rate)
	fsabs.s	4(a3),fp2			; a stronger push: from it, the phase from 0
	fsabs.x	fp0,fp1
	fcmp.x	fp1,fp2
	fbnlt	su_4
	clr.l	(a3)
	fmove.s	fp0,4(a3)
su_4:	fsmove.s 8(a3),fp2
	fsabs.x	fp2,fp1
	fsabs.x	fp7,fp0
	fcmp.x	fp0,fp1
	fbnlt	su_5
	clr.l	(a3)
	fssub.x	fp7,fp2
	fsmul.s	SU_D3D(a5),fp2
	fsadd.x	fp7,fp2
	fmove.s	fp2,8(a3)
su_5:	fsmove.s (a3),fp0			; d = (int)(cos(phase 4 pi + pi) (lat + lng)), within 18
	fsmul.s	K_4PI(pc),fp0
	fsadd.s	K_PI(pc),fp0
	fmove.s	fp0,-(sp)
	move.l	SU_COS(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	fsadd.s	4(a3),fp2
	fsmul.x	fp0,fp2
	fintrz.x fp2,fp2
	fmove.l	fp2,d0
	moveq	#-18,d1
	cmp.l	d1,d0
	bge.s	su_6
	move.l	d1,d0
su_6:	moveq	#18,d1
	cmp.l	d1,d0
	ble.s	su_7
	move.l	d1,d0
su_7:	move.l	d0,12(a3)
	fsmove.s SU_D61(a5),fp0			; lat *= damp(61), gone under 2
	fsmul.s	4(a3),fp0
	fsabs.x	fp0,fp1
	fcmp.s	K_TWO(pc),fp1
	fbnlt	su_8
	fsmove.s K_ZERO(pc),fp0
su_8:	fmove.s	fp0,4(a3)
	fsmove.s SU_D71(a5),fp0			; lng *= damp(71), gone under 2
	fsmul.s	8(a3),fp0
	fsabs.x	fp0,fp1
	fcmp.s	K_TWO(pc),fp1
	fbnlt	su_9
	fsmove.s K_ZERO(pc),fp0
su_9:	fmove.s	fp0,8(a3)
	fsmove.s (a3),fp0			; phase += dt
	fsadd.s	g_dt_smooth,fp0
	fmove.s	fp0,(a3)
	lea	16(a3),a3
	addq.l	#1,d7
	cmp.l	#4,d7
	blt	su_l
	move.l	SU_SUSP(a5),a3
	move.l	SU_MM(a5),a0
	fsmove.s 40(a0),fp2			; track = 2 track_half, else 452
	ftst.x	fp2
	fbngt	su_t1
	fsadd.x	fp2,fp2
	bra.s	su_t2
su_t1:	fsmove.s K_452(pc),fp2
su_t2:	fsmove.s 28(a0),fp3			; wb, else 935
	ftst.x	fp3
	fbgt	su_t3
	fsmove.s K_935(pc),fp3
su_t3:	move.l	12(a3),d1			; drop = (sum of the four) / 4
	move.l	28(a3),d4
	move.l	44(a3),d2
	move.l	60(a3),d3
	move.l	d1,d0
	add.l	d4,d0
	add.l	d2,d0
	add.l	d3,d0
	bpl.s	su_d1
	addq.l	#3,d0
su_d1:	asr.l	#2,d0
	fsmove.l d0,fp1
	fmove.s	fp1,16(a2)
	sub.l	d2,d1				; roll = atan((d0 - d2) / track) 4
	fsmove.l d1,fp1
	fsdiv.x	fp2,fp1
	fmove.s	fp1,-(sp)
	move.l	SU_ATAN(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	fsmul.s	K_FOUR(pc),fp0
	fmove.s	fp0,12(a2)
	sub.l	d3,d2				; pitch = atan((d2 - d3) / wb) 2
	fsmove.l d2,fp0
	fsdiv.x	fp3,fp0
	fmove.s	fp0,-(sp)
	move.l	SU_ATAN(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	fsadd.x	fp0,fp0
	fmove.s	fp0,8(a2)
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; void props68k(const pr_ctx *x): main.c props_step and props_show (props_step_c the reference, OS_PRASM=c): the
; player's two circles against each prop near it (knocked flying: the count, sound and rumble in C), a flying
; prop's way, its ground (track_under), its bounces, on its side when it stops (C); then the objects.
PR_CAR	equ	0
PR_PM	equ	4
PR_PROPS equ	8
PR_N	equ	12
PR_UNDER equ	16
PR_HIT	equ	20
PR_LIE	equ	24
; prop: 0 x y z yaw, 16 tilt[3], 52 gz, 56 dx dy v vz, 72 flying, 80 obj, 84 bytes
Q_GZ	equ	52
Q_DX	equ	56
Q_DY	equ	60
Q_V	equ	64
Q_VZ	equ	68
Q_FLY	equ	72
Q_OBJ	equ	80
; locals (a6): cc_circ's, then
PL_G	equ	96
PL_OX	equ	100
PL_OY	equ	104
PL_GR	equ	108
PL_OFF	equ	112
PL_PLOC	equ	116

	xdef	_props68k
	xdef	props68k
_props68k:
props68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-PL_PLOC(sp),sp
	move.l	sp,a6
	move.l	PL_PLOC+72+48(sp),a5
	move.l	PR_CAR(a5),a4
	move.l	PR_PM(a5),CL_IM(a6)		; the player's circles
	move.l	CS_X(a4),CL_IX(a6)
	move.l	CS_Y(a4),CL_IY(a6)
	move.l	CS_YAW(a4),CL_IYAW(a6)
	lea	CL_P(a6),a0
	move.l	a0,CL_OUT(a6)
	bsr	cc_circ
	moveq	#0,d7				; i
pp_i:	cmp.l	PR_N(a5),d7
	bge	pp_show
	move.l	d7,d0
	mulu.l	#84,d0
	move.l	PR_PROPS(a5),a3
	add.l	d0,a3				; q
	tst.l	Q_FLY(a3)
	bne	pp_fl
	fsmove.s CS_X(a4),fp0			; near the player?
	fssub.s	(a3),fp0
	fsabs.x	fp0
	fcmp.s	K_1500(pc),fp0
	fbge	pp_fl
	fsmove.s CS_Y(a4),fp0
	fssub.s	4(a3),fp0
	fsabs.x	fp0
	fcmp.s	K_1500(pc),fp0
	fbge	pp_fl
	fsmove.s CS_Z(a4),fp0
	fssub.s	8(a3),fp0
	fsabs.x	fp0
	fcmp.s	K_1500(pc),fp0
	fbge	pp_fl
	moveq	#0,d6				; k
pp_k:	cmp.l	#2,d6
	bge	pp_fl
	tst.l	Q_FLY(a3)
	bne	pp_fl
	fsmove.s CL_P(a6,d6.l*4),fp2		; sqrt(dx^2 + dy^2) - (rad + 100) >= 100: not touched
	fssub.s	(a3),fp2
	fsmove.s CL_P+8(a6,d6.l*4),fp3
	fssub.s	4(a3),fp3
	fsmul.x	fp2,fp2
	fsmul.x	fp3,fp3
	fsadd.x	fp3,fp2
	fssqrt.x fp2,fp2
	fsmove.s CL_P+16(a6),fp0
	fsadd.s	K_100(pc),fp0
	fssub.x	fp0,fp2
	fcmp.s	K_100(pc),fp2
	fbge	pp_kn
	pea	CL_C(a6)			; knocked flying along the car's heading
	pea	CL_S(a6)
	move.l	CS_YAW(a4),-(sp)
	move.l	CC_SC(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	move.l	CL_S(a6),Q_DX(a3)
	move.l	CL_C(a6),d0
	bchg	#31,d0
	move.l	d0,Q_DY(a3)
	fsmove.s CS_SPEED(a4),fp0
	fsmul.s	K_002(pc),fp0
	fmove.s	fp0,Q_VZ(a3)
	fsmove.s CS_SPEED(a4),fp0
	fsmul.s	K_14(pc),fp0
	fmove.s	fp0,Q_V(a3)
	move.l	#1,Q_FLY(a3)
	move.l	a3,-(sp)
	move.l	PR_HIT(a5),a0
	jsr	(a0)
	addq.l	#4,sp
pp_kn:	addq.l	#1,d6
	bra	pp_k
pp_fl:	tst.l	Q_FLY(a3)			; flying
	beq	pp_n
	move.l	(a3),PL_OX(a6)
	move.l	4(a3),PL_OY(a6)
	move.l	Q_GZ(a3),PL_GR(a6)
	fsmove.s Q_V(a3),fp2			; v dx dt, v dy dt
	fsmul.s	Q_DX(a3),fp2
	fsmul.s	g_dt_smooth,fp2
	fsmove.s Q_V(a3),fp3
	fsmul.s	Q_DY(a3),fp3
	fsmul.s	g_dt_smooth,fp3
	fsmove.x fp2,fp0
	fsadd.s	(a3),fp0
	fmove.s	fp0,(a3)
	fsmove.x fp3,fp0
	fsadd.s	4(a3),fp0
	fmove.s	fp0,4(a3)
	fsmul.s	K_0008B(pc),fp2			; tilt[0] -= v dx dt 0.008, tilt[2] -= v dy dt 0.0015
	fsmove.s 16(a3),fp0
	fssub.x	fp2,fp0
	fmove.s	fp0,16(a3)
	fsmul.s	K_00015(pc),fp3
	fsmove.s 24(a3),fp0
	fssub.x	fp3,fp0
	fmove.s	fp0,24(a3)
	fsmove.s Q_V(a3),fp0			; v -= dt 2000, not below 0
	fssub.s	g_dt2000,fp0
	ftst.x	fp0
	fbge	pp_v
	fsmove.s K_ZERO(pc),fp0
pp_v:	fmove.s	fp0,Q_V(a3)
	pea	PL_G(a6)			; the ground under it
	move.l	#1,-(sp)
	move.l	4(a3),-(sp)
	move.l	(a3),-(sp)
	move.l	PR_UNDER(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	clr.l	PL_OFF(a6)
	tst.l	d0
	beq.s	pp_off
	move.l	PL_G(a6),PL_GR(a6)
	bra.s	pp_z
pp_off:	move.l	#1,PL_OFF(a6)			; off the track: back, turned, 0.3 of its speed
	move.l	8(a3),PL_GR(a6)
	move.l	PL_OX(a6),(a3)
	move.l	PL_OY(a6),4(a3)
	bchg	#7,Q_DX(a3)
	bchg	#7,Q_DY(a3)
	fsmove.s Q_V(a3),fp0
	fsmul.s	K_03(pc),fp0
	fmove.s	fp0,Q_V(a3)
pp_z:	fsmove.s Q_VZ(a3),fp0			; vz -= dt 500; z += vz frames
	fssub.s	g_dt500,fp0
	fmove.s	fp0,Q_VZ(a3)
	fsmul.s	K_FRAMES(pc),fp0
	fsadd.s	8(a3),fp0
	fmove.s	fp0,8(a3)
	fcmp.s	PL_GR(a6),fp0
	fbgt	pp_gz
	move.l	PL_GR(a6),8(a3)			; down: a bounce
	fsmove.s Q_VZ(a3),fp0
	fsneg.x	fp0
	fsmul.s	K_08(pc),fp0
	fsabs.x	fp0,fp1
	fcmp.s	K_50(pc),fp1
	fbge	pp_b1
	fsmove.s K_ZERO(pc),fp0
pp_b1:	fmove.s	fp0,Q_VZ(a3)
	fsmove.s Q_V(a3),fp1
	ftst.x	fp1
	fbne	pp_gz
	ftst.x	fp0
	fbne	pp_gz
	clr.l	Q_FLY(a3)			; stopped
	tst.l	PL_OFF(a6)
	beq.s	pp_lie
	move.l	K_M20000(pc),8(a3)		; off the track: gone
	bra.s	pp_gz
pp_lie:	move.l	a3,-(sp)
	move.l	PR_LIE(a5),a0
	jsr	(a0)
	addq.l	#4,sp
pp_gz:	move.l	PL_GR(a6),Q_GZ(a3)
pp_n:	addq.l	#1,d7
	bra	pp_i
pp_show:					; props_show
	moveq	#0,d7
ps_i:	cmp.l	PR_N(a5),d7
	bge.s	pp_done
	move.l	d7,d0
	mulu.l	#84,d0
	move.l	PR_PROPS(a5),a3
	add.l	d0,a3
	move.l	Q_OBJ(a3),d0
	beq.s	ps_n
	move.l	d0,a1
	move.l	(a3),24(a1)
	move.l	4(a3),28(a1)
	move.l	8(a3),32(a1)
	fsmove.s 12(a3),fp0
	fsadd.s	20(a3),fp0
	fmove.s	fp0,36(a1)
	move.l	16(a3),40(a1)
	move.l	24(a3),44(a1)
ps_n:	addq.l	#1,d7
	bra.s	ps_i
pp_done:
	lea	PL_PLOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; void anims68k(const an_ctx *x): main.c anims_step and anim_place (anims_step_c the reference): each moving piece
; of scenery within 52000 of the player along its curve (as an opponent's), its place, height and heading.
AN_CAR	equ	0
AN_A	equ	4
AN_N	equ	8
AN_ATAN2 equ	12
; locals (a6): opp68k's, then a block as op_piece / op_curve read it (node, half, u)
AL_B	equ	64
AL_LOC	equ	80

	xdef	_anims68k
	xdef	anims68k
_anims68k:
anims68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-AL_LOC(sp),sp
	move.l	sp,a6
	move.l	AL_LOC+72+48(sp),a5
	lea	AL_B(a6),a4			; (op_piece / op_curve's opponent)
	moveq	#0,d7
an_k:	cmp.l	AN_N(a5),d7
	bge	an_done
	move.l	d7,d0
	mulu.l	#28,d0
	move.l	AN_A(a5),a3
	add.l	d0,a3				; a
	move.l	24(a3),a1			; its object
	move.l	AN_CAR(a5),a0
	fsmove.s CS_X(a0),fp0			; within 52000 of the player
	fssub.s	24(a1),fp0
	fsabs.x	fp0
	fcmp.s	K_52000(pc),fp0
	fbge	an_n
	fsmove.s CS_Y(a0),fp0
	fssub.s	28(a1),fp0
	fsabs.x	fp0
	fcmp.s	K_52000(pc),fp0
	fbge	an_n
	move.l	20(a3),a2			; its curve
	move.l	(a3),O_NODE(a4)
	move.l	4(a3),O_HALF(a4)
	move.l	12(a3),O_U(a4)
	fsmove.s 16(a3),fp0			; left = speed dt
	fsmul.s	g_dt_smooth,fp0
	fmove.s	fp0,OL_LEFT(a6)
	clr.l	OL_GUARD(a6)
an_mv:	cmp.l	#8,OL_GUARD(a6)
	bge	an_pl
	fsmove.s OL_LEFT(a6),fp0
	ftst.x	fp0
	fble	an_pl
	bsr	op_piece
	bsr	op_curve
	fsmove.s OL_DER(a6),fp0
	fsmul.x	fp0,fp0
	fsmove.s OL_DER+4(a6),fp1
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fcmp.s	K_ONE(pc),fp0
	fbge	an_m1
	fsmove.s K_ONE(pc),fp0
an_m1:	fsmove.s OL_LEFT(a6),fp1
	fsdiv.x	fp0,fp1
	fsmove.s O_U(a4),fp2
	fsadd.x	fp1,fp2
	fcmp.s	K_ONE(pc),fp2
	fbge	an_m2
	fmove.s	fp2,O_U(a4)
	bra	an_pl
an_m2:	fsmove.s K_ONE(pc),fp2
	fssub.s	O_U(a4),fp2
	fsmul.x	fp0,fp2
	fsmove.s OL_LEFT(a6),fp1
	fssub.x	fp2,fp1
	fmove.s	fp1,OL_LEFT(a6)
	clr.l	O_U(a4)
	tst.l	O_HALF(a4)
	bne.s	an_m3
	move.l	#1,O_HALF(a4)
	bra.s	an_m4
an_m3:	clr.l	O_HALF(a4)
	move.l	O_NODE(a4),d0
	mulu.l	#56,d0
	move.l	8+16(a2,d0.l),d1
	bmi.s	an_m5
	cmp.l	(a2),d1
	blt.s	an_m6
an_m5:	moveq	#0,d1
an_m6:	move.l	d1,O_NODE(a4)
an_m4:	addq.l	#1,OL_GUARD(a6)
	bra	an_mv
an_pl:	move.l	O_NODE(a4),(a3)			; anim_place
	move.l	O_HALF(a4),4(a3)
	move.l	O_U(a4),12(a3)
	bsr	op_piece
	bsr	op_curve
	move.l	24(a3),a1
	move.l	O_NODE(a4),d0
	mulu.l	#56,d0
	lea	8(a2,d0.l),a0			; n
	move.l	16(a0),d1			; nx
	bmi.s	an_p1
	cmp.l	(a2),d1
	blt.s	an_p2
an_p1:	moveq	#0,d1
an_p2:	mulu.l	#56,d1
	fsmove.l 12(a0),fp2			; z0 = n[3], z1 = next[3]
	fsmove.l 8+12(a2,d1.l),fp3
	move.l	OL_POS(a6),24(a1)
	move.l	OL_POS+4(a6),28(a1)
	fsmove.l O_HALF(a4),fp0			; z = z0 + (half + u) (z1 - z0) / 2
	fsadd.s	O_U(a4),fp0
	fssub.x	fp2,fp3
	fsmul.x	fp3,fp0
	fsmul.s	K_HALF(pc),fp0
	fsadd.x	fp2,fp0
	fmove.s	fp0,32(a1)
	fsmove.s OL_DER(a6),fp0			; heading, unless der is 0
	ftst.x	fp0
	fbne	an_y
	fsmove.s OL_DER+4(a6),fp0
	ftst.x	fp0
	fbeq	an_n
an_y:	pea	36(a1)
	move.l	OL_DER+4(a6),d0
	bchg	#31,d0
	move.l	d0,-(sp)
	move.l	OL_DER(a6),-(sp)
	move.l	AN_ATAN2(a5),a0
	jsr	(a0)
	lea	12(sp),sp
an_n:	addq.l	#1,d7
	bra	an_k
an_done:
	lea	AL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; int pt68k(const float *p, int n, float x, float y, int from): main.c path_track -- the road's sample nearest
; (x, y) among the 81 round the last one, else (further than 6000) among all of them (path_nearest)
	xdef	_pt68k
	xdef	pt68k
_pt68k:
pt68k:
	movem.l	d2-d7/a2,-(sp)
	fmovem.x fp2-fp4,-(sp)
	lea	28+36+4(sp),a1
	move.l	(a1)+,a2			; p (12 bytes a sample)
	move.l	(a1)+,d6			; n
	fsmove.s (a1)+,fp2			; x
	fsmove.s (a1)+,fp3			; y
	move.l	(a1),d7				; from
	move.l	d7,d5				; bi
	fsmove.s K_1E30(pc),fp4			; best
	moveq	#-40,d4				; k
pt_l:	cmp.l	#40,d4
	bgt.s	pt_e
	move.l	d7,d0				; i = ((from + k) % n + n) % n
	add.l	d4,d0
	divsl.l	d6,d1:d0
	add.l	d6,d1
	move.l	d1,d0
	divsl.l	d6,d1:d0
	bsr.s	pt_d
	addq.l	#1,d4
	bra.s	pt_l
pt_e:	fcmp.s	K_36E6(pc),fp4			; further than 6000: all of them
	fble	pt_x
	moveq	#0,d5
	fsmove.s K_1E30(pc),fp4
	moveq	#0,d1
pt_a:	cmp.l	d6,d1
	bge.s	pt_x
	bsr.s	pt_d
	addq.l	#1,d1
	bra.s	pt_a
pt_x:	move.l	d5,d0
	fmovem.x (sp)+,fp2-fp4
	movem.l	(sp)+,d2-d7/a2
	rts
; sample d1: d = (p.x - x)^2 + (p.y - y)^2, the least (the first of equals) in fp4 / d5
pt_d:	move.l	d1,d0
	mulu.l	#12,d0
	fsmove.s (a2,d0.l),fp0
	fssub.x	fp2,fp0
	fsmove.s 4(a2,d0.l),fp1
	fssub.x	fp3,fp1
	fsmul.x	fp0,fp0
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fcmp.x	fp4,fp0
	fbge	pd_1
	fsmove.x fp0,fp4
	move.l	d1,d5
pd_1:	rts

; ---------------------------------------------------------------------------------------------------------------
; void mk68k(const mk_ctx *x): main.c markers_step (markers_step_c the reference): the clocks and the time left,
; the special modes (C), the marker reached among the last one and its two neighbours (the line and a checkpoint:
; C), the race's progress (marker_progress)
MK_C	equ	0
MK_RACE	equ	4
MK_FIN	equ	8
MK_CLOCK equ	12
MK_TOUT	equ	16
MK_LAP	equ	20
MK_TOT	equ	24
MK_TIMER equ	28
MK_CHEAT equ	32
MK_MODE	equ	36
MK_NMARK equ	40
MK_MARK	equ	44
MK_AT	equ	48
MK_SEEN	equ	52
MK_CNT	equ	56
MK_LAPS	equ	60
MK_PROG	equ	64
MK_MODES equ	68
MK_ZERO	equ	72
MK_CHECK equ	76
MK_OVER	equ	80
CS_SURF2 equ	184

	xdef	_mk68k
	xdef	mk68k
_mk68k:
mk68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp3,-(sp)
	move.l	24+48(sp),a5
	move.l	MK_C(a5),a4
	move.l	MK_RACE(a5),a0			; the clocks, the time left
	tst.l	(a0)
	beq.s	mk_m
	move.l	MK_FIN(a5),a0
	tst.l	(a0)
	bne.s	mk_m
	move.l	MK_OVER(a5),a0			; (the race broken off: the end screen up, the clocks stand -- 0x18a14)
	tst.l	(a0)
	bne.s	mk_m
	move.l	MK_CLOCK(a5),a0
	tst.l	(a0)
	beq.s	mk_1
	move.l	MK_LAP(a5),a0
	fsmove.s (a0),fp0
	fsadd.s	g_dt_raw,fp0
	fmove.s	fp0,(a0)
	move.l	MK_TOT(a5),a0
	fsmove.s (a0),fp0
	fsadd.s	g_dt_raw,fp0
	fmove.s	fp0,(a0)
mk_1:	move.l	MK_TIMER(a5),a1
	btst	#2,MK_CHEAT+3(a5)
	bne.s	mk_2
	fsmove.s (a1),fp0
	fssub.s	g_dt_raw,fp0
	fmove.s	fp0,(a1)
mk_2:	fsmove.s (a1),fp0
	move.l	MK_TOUT(a5),a0
	clr.l	(a0)
	ftst.x	fp0
	fbge	mk_m
	move.l	#1,(a0)
	clr.l	(a1)
mk_m:	move.l	MK_RACE(a5),a0			; the special modes
	tst.l	(a0)
	beq.s	mk_3
	move.l	MK_MODE(a5),d0
	cmp.l	#$20,d0
	beq.s	mk_mo
	cmp.l	#$40,d0
	bne.s	mk_3
mk_mo:	move.l	a4,-(sp)
	move.l	MK_MODES(a5),a0
	jsr	(a0)
	addq.l	#4,sp
mk_3:	move.l	MK_NMARK(a5),d2
	beq	mk_x
	moveq	#-1,d3				; k
mk_l:	cmp.l	#1,d3
	bgt	mk_pr
	move.l	MK_AT(a5),a0			; i = ((at + k) % n + n) % n
	move.l	(a0),d0
	add.l	d3,d0
	divsl.l	d2,d1:d0
	add.l	d2,d1
	move.l	d1,d0
	divsl.l	d2,d1:d0
	move.l	d1,d4				; i
	mulu.l	#28,d1
	move.l	MK_MARK(a5),a3
	add.l	d1,a3				; m
	fsmove.s CS_X(a4),fp0			; dx dy
	fssub.s	12(a3),fp0
	fsmove.s CS_Y(a4),fp1
	fssub.s	16(a3),fp1
	fsmove.s (a3),fp2			; radius
	fsabs.x	fp0,fp3
	fcmp.x	fp2,fp3
	fbge	mk_n
	fsabs.x	fp1,fp3
	fcmp.x	fp2,fp3
	fbge	mk_n
	fsmul.x	fp0,fp0
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fcmp.x	fp2,fp0
	fbgt	mk_n
	move.l	MK_AT(a5),a0			; reached
	move.l	d4,(a0)
	move.l	4(a3),CS_SURF2(a4)		; the surface's slip
	tst.l	d4
	bne.s	mk_s
	move.l	MK_ZERO(a5),a0			; the line: C
	jsr	(a0)
	bra.s	mk_n
mk_s:	move.l	MK_SEEN(a5),a0
	tst.l	(a0,d4.l*4)
	bne.s	mk_n
	move.l	#1,(a0,d4.l*4)			; passed
	move.l	MK_CNT(a5),a0
	addq.l	#1,(a0)
	btst	#1,24+3(a3)			; a checkpoint, the clocks on, not finished: C
	beq.s	mk_n
	move.l	MK_CLOCK(a5),a0
	tst.l	(a0)
	beq.s	mk_n
	move.l	MK_FIN(a5),a0
	tst.l	(a0)
	bne.s	mk_n
	move.l	MK_CHECK(a5),a0
	jsr	(a0)
mk_n:	addq.l	#1,d3
	bra	mk_l
mk_pr:	move.l	MK_AT(a5),a0			; the progress, once the marker is passed properly
	move.l	(a0),d4
	bne.s	mk_p1
	move.l	MK_CLOCK(a5),a0
	tst.l	(a0)
	beq	mk_x
	bra.s	mk_p2
mk_p1:	move.l	MK_SEEN(a5),a0
	tst.l	(a0,d4.l*4)
	beq	mk_x
mk_p2:	move.l	d4,d0				; marker_progress(at, laps, x, y)
	mulu.l	#28,d0
	move.l	MK_MARK(a5),a0
	add.l	d0,a0				; a
	move.l	d4,d0
	addq.l	#1,d0
	divsl.l	d2,d1:d0
	mulu.l	#28,d1
	move.l	MK_MARK(a5),a1
	add.l	d1,a1				; b
	fsmove.s 12(a1),fp0			; span
	fssub.s	12(a0),fp0
	fsmul.x	fp0,fp0
	fsmove.s 16(a1),fp1
	fssub.s	16(a0),fp1
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fsmul.s	K_005(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d5
	fsmove.s CS_X(a4),fp0			; gone
	fssub.s	12(a0),fp0
	fsmul.x	fp0,fp0
	fsmove.s CS_Y(a4),fp1
	fssub.s	16(a0),fp1
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fssqrt.x fp0,fp0
	fsmul.s	K_005(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d6
	tst.l	d5
	beq.s	mk_q0
	fsmove.l d6,fp0
	fsmove.l d5,fp1
	fsdiv.x	fp1,fp0
	bra.s	mk_q1
mk_q0:	fsmove.s K_ZERO(pc),fp0
mk_q1:	fsmove.l d4,fp1
	fsadd.x	fp1,fp0
	move.l	MK_LAPS(a5),a0
	move.l	(a0),d0
	muls.l	#100,d0
	fsmove.l d0,fp1
	fsadd.x	fp1,fp0
	move.l	MK_PROG(a5),a0
	fmove.s	fp0,(a0)
mk_x:	fmovem.x (sp)+,fp2-fp3
	movem.l	(sp)+,d2-d7/a2-a6
	rts

; ---------------------------------------------------------------------------------------------------------------
; void cr68k(const cr_ctx *x): main.c crash_step at DRIVE_DT (crash_step_c the reference): thrown up and
; tumbling, each bounce (the rumble: C) lower, after the fourth the view back (C).
; g_crash: 0 on, 4 bounces, 8 view, 12 vy, 16 height, 20 pitch, 24 roll, 28 pitch_rate, 32 roll_rate
	xdef	_cr68k
	xdef	cr68k
_cr68k:
cr68k:
	movem.l	a4-a5,-(sp)
	fmovem.x fp2,-(sp)
	move.l	12+8+4(sp),a5
	move.l	(a5),a4
	tst.l	(a4)
	beq	cr_x
	fsmove.s 12(a4),fp0			; height += vy dt; vy -= dt 6000
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	16(a4),fp0
	fmove.s	fp0,16(a4)
	fsmove.s 12(a4),fp0
	fssub.s	g_dt6000,fp0
	fmove.s	fp0,12(a4)
	fsmove.s 4(a5),fp2			; damp(97)
	fsmove.s 28(a4),fp0			; pitch_rate *= d; pitch += pitch_rate dt
	fsmul.x	fp2,fp0
	fmove.s	fp0,28(a4)
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	20(a4),fp0
	fmove.s	fp0,20(a4)
	fsmove.s 32(a4),fp0			; roll the same
	fsmul.x	fp2,fp0
	fmove.s	fp0,32(a4)
	fsmul.s	g_dt_smooth,fp0
	fsadd.s	24(a4),fp0
	fmove.s	fp0,24(a4)
	fsmove.s 16(a4),fp0
	ftst.x	fp0
	fbgt	cr_x
	addq.l	#1,4(a4)			; a bounce
	move.l	8(a5),a0
	jsr	(a0)
	clr.l	16(a4)
	fsmove.s 12(a4),fp0
	fsneg.x	fp0
	fsmul.s	K_04(pc),fp0
	fmove.s	fp0,12(a4)
	clr.l	20(a4)
	clr.l	24(a4)
	move.l	K_06(pc),d0
	btst	#0,7(a4)
	beq.s	cr_1
	bset	#31,d0
cr_1:	move.l	d0,32(a4)
	move.l	K_M1(pc),28(a4)
	cmp.l	#3,4(a4)
	ble.s	cr_x
	clr.l	(a4)
	move.l	12(a5),a0
	jsr	(a0)
cr_x:	fmovem.x (sp)+,fp2
	movem.l	(sp)+,a4-a5
	rts

; ---------------------------------------------------------------------------------------------------------------
; void ps68k(const ps_ctx *x): main.c player_sync (player_sync_c the reference): the drawn car from the player's
; state, its pictures, the reflections by the marker's kind, the shadow, the crash's height and tumbling
	xdef	_ps68k
	xdef	ps68k
_ps68k:
ps68k:
	movem.l	a2-a5,-(sp)
	move.l	16+4(sp),a5
	move.l	(a5),a3				; pobj
	move.l	4(a5),a4			; the car
	move.l	CS_X(a4),24(a3)
	move.l	CS_Y(a4),28(a3)
	move.l	CS_Z(a4),32(a3)
	fsmove.s CS_YAW(a4),fp0			; yaw + drift
	fsadd.s	CS_DRIFT(a4),fp0
	fmove.s	fp0,36(a3)
	move.l	CS_PITCH(a4),d0
	bchg	#31,d0
	move.l	d0,40(a3)
	move.l	CS_ROLL(a4),d0
	bchg	#31,d0
	move.l	d0,44(a3)
	move.l	12(a5),d0			; the pictures: brake lights, slow
	fsmove.s CS_BRAKE(a4),fp0
	ftst.x	fp0
	fbne	ps_1
	or.l	#$4000,d0
ps_1:	fsmove.s CS_SPEED(a4),fp0
	fcmp.s	K_4000(pc),fp0
	fbgt	ps_2
	or.l	#$2000,d0
ps_2:	move.l	d0,72(a3)
	move.l	8(a5),a2			; the pose
	move.l	a2,4(a3)
	moveq	#0,d0
	tst.l	16(a5)
	beq.s	ps_e
	move.l	24(a5),d0
	mulu.l	#28,d0
	move.l	20(a5),a0
	move.l	20(a0,d0.l),d1			; the marker's kind
	moveq	#0,d0
	tst.l	d1
	beq.s	ps_e
	move.l	#$ff00,d0
	cmp.l	#1,d1
	bne.s	ps_e
	move.l	#$8000,d0
ps_e:	move.l	d0,28(a2)
	move.l	28(a5),d0			; the shadow follows
	beq.s	ps_c
	move.l	d0,a1
	move.l	24(a3),24(a1)
	move.l	28(a3),28(a1)
	fsmove.s 32(a3),fp0
	fsadd.s	K_FOUR(pc),fp0
	fmove.s	fp0,32(a1)
	move.l	36(a3),36(a1)
	move.l	40(a3),40(a1)
	move.l	44(a3),44(a1)
ps_c:	move.l	32(a5),a0			; crashing: thrown up and tumbling, the shadow stays
	tst.l	(a0)
	beq.s	ps_x
	fsmove.s 32(a3),fp0
	fsadd.s	16(a0),fp0
	fmove.s	fp0,32(a3)
	fsmove.s 40(a3),fp0
	fsadd.s	20(a0),fp0
	fmove.s	fp0,40(a3)
	fsmove.s 44(a3),fp0
	fsadd.s	24(a0),fp0
	fmove.s	fp0,44(a3)
	move.l	28(a5),d0
	beq.s	ps_x
	move.l	d0,a1
	move.l	CS_PITCH(a4),d0
	bchg	#31,d0
	move.l	d0,40(a1)
	move.l	CS_ROLL(a4),d0
	bchg	#31,d0
	move.l	d0,44(a1)
ps_x:	movem.l	(sp)+,a2-a5
	rts

; ---------------------------------------------------------------------------------------------------------------
; the step's cameras, needles, smoke and rumble (main.c chase_step, swoop_step + swoop_done, dash_step, smoke_step,
; rumble_step at DRIVE_DT; the _c functions their references, OS_MSASM=c), all from one context (ms_ctx)
MS_C	equ	0
MS_CHASE equ	4
MS_VIEW	equ	8
MS_CONT	equ	12
MS_D51	equ	16
MS_D0	equ	20
MS_SIN	equ	24
MS_SWOOP equ	28
MS_D90	equ	32
MS_D19	equ	36
MS_COS	equ	40
MS_NS	equ	44
MS_NR	equ	48
MS_D5A	equ	52
MS_SOK	equ	56
MS_POBJ	equ	60
MS_PUFF	equ	64
MS_SKID	equ	68
MS_CPUFF equ	72
MS_PTIM	equ	76
MS_RACE	equ	80
MS_KICK	equ	84
MS_CRASH equ	88
MS_RLOW	equ	92
MS_RHIGH equ	96

MSIN	macro					; \2 = sinf / cosf (\1 the context's pointer) of fp0, through memory
	fmove.s	fp0,-(sp)
	move.l	\1(a5),a0
	jsr	(a0)
	addq.l	#4,sp
	endm

; chase_step: the chase camera's heading, lean and pitch ease to the car's (0x51), its height (0)
	xdef	_chase68k
	xdef	chase68k
_chase68k:
chase68k:
	movem.l	a2-a5,-(sp)
	fmovem.x fp2-fp5,-(sp)
	move.l	48+16+4(sp),a5
	move.l	MS_C(a5),a4
	move.l	MS_CHASE(a5),a3
	move.l	MS_VIEW(a5),a2
	move.l	MS_CONT(a5),a1
	tst.l	(a1)
	beq.s	ch_1
	fsmove.s 40(a1),fp2			; the camera's wheel set
	fsmove.s 44(a1),fp3
	bra.s	ch_2
ch_1:	fsmove.s CS_PITCH(a4),fp2
	fsmove.s CS_ROLL(a4),fp3
ch_2:	fsmove.x fp2,fp4			; want_pitch
	fssub.s	12(a2),fp4
	tst.l	16(a3)
	bne.s	ch_3
	move.l	CS_YAW(a4),(a3)			; the first time: where it wants to be
	fmove.s	fp3,8(a3)
	fmove.s	fp4,4(a3)
	bsr	ch_h
	fmove.s	fp0,12(a3)
	move.l	#1,16(a3)
	bra.s	ch_x
ch_3:	fsmove.s MS_D51(a5),fp5
	fsmove.s (a3),fp0			; yaw
	fssub.s	CS_YAW(a4),fp0
	bsr	op_wrap
	fsmul.x	fp5,fp0
	fsadd.s	CS_YAW(a4),fp0
	fmove.s	fp0,(a3)
	fsmove.s 8(a3),fp0			; roll
	fssub.x	fp3,fp0
	bsr	op_wrap
	fsmul.x	fp5,fp0
	fsadd.x	fp3,fp0
	fmove.s	fp0,8(a3)
	fsmove.s 4(a3),fp0			; pitch
	fssub.x	fp4,fp0
	bsr	op_wrap
	fsmul.x	fp5,fp0
	fsadd.x	fp4,fp0
	fmove.s	fp0,4(a3)
	bsr.s	ch_h				; height
	fsmove.s 12(a3),fp1
	fssub.x	fp0,fp1
	fsmul.s	MS_D0(a5),fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,12(a3)
ch_x:	fmovem.x (sp)+,fp2-fp5
	movem.l	(sp)+,a2-a5
	rts
; fp0 = z + above - behind sinf(pitch)
ch_h:	fsmove.s 4(a3),fp0
	MSIN	MS_SIN
	fsmul.s	4(a2),fp0
	fsmove.s CS_Z(a4),fp1
	fsadd.s	8(a2),fp1
	fssub.x	fp0,fp1
	fsmove.x fp1,fp0
	rts

; swoop_step and swoop_done: the fly-across's offsets die away (90, 0x19); done when all are small
	xdef	_swoop68k
	xdef	swoop68k
_swoop68k:
swoop68k:
	movem.l	a4-a5,-(sp)
	fmovem.x fp2,-(sp)
	move.l	12+8+4(sp),a5
	move.l	MS_SWOOP(a5),a4
	tst.l	(a4)
	beq	sw_x
	moveq	#4,d1
sw_1:	fsmove.s (a4,d1.l),fp0			; x y z x damp(90)
	fsmul.s	MS_D90(a5),fp0
	fmove.s	fp0,(a4,d1.l)
	addq.l	#4,d1
	cmp.l	#16,d1
	blt.s	sw_1
sw_2:	fsmove.s (a4,d1.l),fp0			; yaw pitch roll x damp(0x19)
	fsmul.s	MS_D19(a5),fp0
	fmove.s	fp0,(a4,d1.l)
	addq.l	#4,d1
	cmp.l	#28,d1
	blt.s	sw_2
	fsmove.s 16(a4),fp0			; done: cos of each angle > 0.99995, each offset under dt 200
	MSIN	MS_COS
	fcmp.s	K_99995(pc),fp0
	fbngt	sw_x
	fsmove.s 20(a4),fp0
	MSIN	MS_COS
	fcmp.s	K_99995(pc),fp0
	fbngt	sw_x
	fsmove.s 24(a4),fp0
	MSIN	MS_COS
	fcmp.s	K_99995(pc),fp0
	fbngt	sw_x
	fsmove.s g_dt_smooth,fp2
	fsmul.s	K_200(pc),fp2
	moveq	#4,d1
sw_3:	fsmove.s (a4,d1.l),fp0
	fsabs.x	fp0
	fcmp.x	fp2,fp0
	fbnlt	sw_x
	addq.l	#4,d1
	cmp.l	#16,d1
	blt.s	sw_3
	clr.l	(a4)
sw_x:	fmovem.x (sp)+,fp2
	movem.l	(sp)+,a4-a5
	rts

; dash_step: the needles ease (0x5a) to the speed and the revs
	xdef	_dash68k
	xdef	dash68k
_dash68k:
dash68k:
	move.l	4(sp),a1
	move.l	MS_C(a1),a0
	fsmove.s CS_SPEED(a0),fp0		; ws = speed / maxspd 4.0840706
	fsdiv.s	CS_MAXSPD(a0),fp0
	fsmul.s	K_WS(pc),fp0
	fsmove.s K_PI(pc),fp1			; full
	move.l	MS_VIEW(a1),d0
	exg	d0,a1
	tst.l	24(a1)
	exg	d0,a1
	beq.s	da_1
	fsmove.s K_FULLC(pc),fp1
da_1:	fmove.x	fp2,-(sp)
	fsmove.s CS_RPM(a0),fp2			; wr = rpm / maxrpm full, at most full
	fsdiv.s	CS_MAXRPM(a0),fp2
	fsmul.x	fp1,fp2
	fcmp.x	fp1,fp2
	fble	da_2
	fsmove.x fp1,fp2
da_2:	move.l	MS_NS(a1),a0			; needle = w + (needle - w) k
	fsmove.s (a0),fp1
	fssub.x	fp0,fp1
	fsmul.s	MS_D5A(a1),fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,(a0)
	move.l	MS_NR(a1),a0
	fsmove.s (a0),fp1
	fssub.x	fp2,fp1
	fsmul.s	MS_D5A(a1),fp1
	fsadd.x	fp1,fp2
	fmove.s	fp2,(a0)
	fmove.x	(sp)+,fp2
	rts

; smoke_step: skidding, a pair of puffs every 0.05 s at the rear wheels, each puff carried with the car
	xdef	_smoke68k
	xdef	smoke68k
_smoke68k:
smoke68k:
	movem.l	d2-d7/a2-a5,-(sp)
	fmovem.x fp2-fp5,-(sp)
	move.l	48+40+4(sp),a5
	tst.l	MS_SOK(a5)
	beq	sm_x
	move.l	MS_POBJ(a5),d0
	beq	sm_x
	move.l	d0,a3				; pobj
	tst.l	(a3)
	beq	sm_x
	move.l	MS_C(a5),a4
	moveq	#1,d7				; skid? (0x17d14: the locked-wheel branch or a drift past 0.23; running wide does not)
	fsmove.s CS_LOCK(a4),fp0
	ftst.x	fp0
	fbeq	sm_d
	tst.l	CS_SPIN(a4)			; (the lock's branch: no spin, no state, the time not up)
	bne.s	sm_d
	tst.l	CS_CRASH(a4)
	bne.s	sm_d
	tst.l	CS_TOUT(a4)
	beq.s	sm_s
sm_d:	fsmove.s CS_DRIFT(a4),fp0
	fsabs.x	fp0
	fcmp.s	K_023(pc),fp0
	fbgt	sm_s
	tst.l	CS_LAUNCH(a4)			; the launch, in gear (0x15c1c state 5: its pedal is held at 0, 0x160a4)
	beq.s	sm_1
	tst.l	CS_GEAR(a4)
	beq.s	sm_1
	tst.l	MS_RACE(a5)
	bne.s	sm_s
sm_1:	move.l	MS_CPUFF(a5),a0
	tst.l	(a0)
	bgt.s	sm_s
	moveq	#0,d7
sm_s:	move.l	MS_SKID(a5),a0
	move.l	d7,(a0)
	move.l	MS_CPUFF(a5),a0
	tst.l	(a0)
	ble.s	sm_2
	subq.l	#1,(a0)
sm_2:	tst.l	d7
	beq	sm_mv
	move.l	MS_PTIM(a5),a0			; every 0.05 s
	fsmove.s (a0),fp0
	fcmp.s	K_005(pc),fp0
	fbge	sm_3
	fsadd.s	g_dt_smooth,fp0
	fmove.s	fp0,(a0)
	bra	sm_mv
sm_3:	clr.l	(a0)
	move.l	(a3),a2				; the mesh
	fintrz.s CS_X(a4),fp0			; lx = +-(track_half + ((int)x & 7) 51), lz = axle_rear + ((int)y & 7) 51
	fmove.l	fp0,d0
	moveq	#7,d1
	and.l	d1,d0
	mulu.l	#51,d0
	fsmove.l d0,fp2
	fsadd.s	40(a2),fp2
	fintrz.s CS_Y(a4),fp0
	fmove.l	fp0,d0
	and.l	d1,d0
	mulu.l	#51,d0
	fsmove.l d0,fp3
	fsadd.s	36(a2),fp3
	moveq	#0,d6				; side
sm_sd:	cmp.l	#2,d6
	bge.s	sm_mv
	move.l	MS_PUFF(a5),a1
	moveq	#8-1,d5
sm_f:	tst.l	(a1)				; the first free one
	bne.s	sm_fn
	tst.l	16(a1)
	beq.s	sm_fn
	move.l	#1,(a1)
	clr.l	4(a1)
	fsmove.x fp2,fp0
	tst.l	d6
	beq.s	sm_f1
	fsneg.x	fp0
sm_f1:	fmove.s	fp0,8(a1)
	fmove.s	fp3,12(a1)
	bra.s	sm_fd
sm_fn:	lea	20(a1),a1
	dbra	d5,sm_f
sm_fd:	addq.l	#1,d6
	bra.s	sm_sd
sm_mv:	fsmove.s 36(a3),fp0			; each puff with the car
	MSIN	MS_COS
	fsmove.x fp0,fp4			; cs
	fsmove.s 36(a3),fp0
	MSIN	MS_SIN
	fsmove.x fp0,fp5			; sn
	move.l	MS_PUFF(a5),a1
	moveq	#8-1,d5
sm_p:	move.l	16(a1),d0
	beq	sm_pn
	move.l	d0,a2				; its object
	tst.l	(a1)
	beq.s	sm_off
	fsmove.s g_dt_smooth,fp0			; phase += dt 1.5; at 1 gone
	fsmul.s	K_15(pc),fp0
	fsadd.s	4(a1),fp0
	fmove.s	fp0,4(a1)
	fcmp.s	K_ONE(pc),fp0
	fblt	sm_on
	clr.l	(a1)
sm_off:	move.l	K_M1E6(pc),32(a2)
	bra.s	sm_pn
sm_on:	fsmove.s 8(a1),fp0			; x = c.x + lx cs - lz sn
	fsmul.x	fp4,fp0
	fsadd.s	CS_X(a4),fp0
	fsmove.s 12(a1),fp1
	fsmul.x	fp5,fp1
	fssub.x	fp1,fp0
	fmove.s	fp0,24(a2)
	fsmove.s 8(a1),fp0			; y = c.y + lx sn + lz cs
	fsmul.x	fp5,fp0
	fsadd.s	CS_Y(a4),fp0
	fsmove.s 12(a1),fp1
	fsmul.x	fp4,fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,28(a2)
	move.l	CS_Z(a4),32(a2)
	fsmove.s 4(a1),fp0			; phase 65535
	fsmul.s	K_65535(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,72(a2)
sm_pn:	lea	20(a1),a1
	dbra	d5,sm_p
sm_x:	fmovem.x (sp)+,fp2-fp5
	movem.l	(sp)+,d2-d7/a2-a5
	rts

; rumble_step: the controller's two motors from a knock, the grass, a skid, locked wheels, a launch, a spin
	xdef	_rumble68k
	xdef	rumble68k
_rumble68k:
rumble68k:
	movem.l	d2/a4-a5,-(sp)
	fmovem.x fp2-fp4,-(sp)
	move.l	36+12+4(sp),a5
	move.l	MS_C(a5),a4
	fsmove.s K_ZERO(pc),fp2			; low
	fsmove.s K_ZERO(pc),fp3			; high
	move.l	MS_KICK(a5),a1			; a knock dies away
	fsmove.s 8(a1),fp0
	ftst.x	fp0
	fbngt	ru_1
	fssub.s	g_dt_smooth,fp0
	fmove.s	fp0,8(a1)
	bra.s	ru_2
ru_1:	fsmove.s g_dt_smooth,fp1			; dt 5
	fsmul.s	K_FIVE(pc),fp1
	fsmove.s (a1),fp0
	fssub.x	fp1,fp0
	ftst.x	fp0
	fbge	ru_1a
	fsmove.s K_ZERO(pc),fp0
ru_1a:	fmove.s	fp0,(a1)
	fsmove.s 4(a1),fp0
	fssub.x	fp1,fp0
	ftst.x	fp0
	fbge	ru_1b
	fsmove.s K_ZERO(pc),fp0
ru_1b:	fmove.s	fp0,4(a1)
ru_2:	move.l	MS_CRASH(a5),a0
	tst.l	(a0)
	bne	ru_k
	fsmove.s CS_SPEED(a4),fp4		; v = speed / 8000, at most 1
	fsdiv.s	K_8000(pc),fp4
	fcmp.s	K_ONE(pc),fp4
	fble	ru_3
	fsmove.s K_ONE(pc),fp4
ru_3:	move.l	CS_GRASS(a4),d2			; on the grass
	add.l	CS_GRASS+4(a4),d2
	add.l	CS_GRASS+8(a4),d2
	add.l	CS_GRASS+12(a4),d2
	beq.s	ru_4
	fcmp.s	K_002(pc),fp4
	fbngt	ru_4
	fintrz.s CS_X(a4),fp0			; jolt = (((int)x + (int)y) & 15) / 15
	fmove.l	fp0,d0
	fintrz.s CS_Y(a4),fp0
	fmove.l	fp0,d1
	add.l	d1,d0
	moveq	#15,d1
	and.l	d1,d0
	fsmove.l d0,fp1
	fsdiv.s	K_15F(pc),fp1
	fsmul.s	K_HALF(pc),fp1			; low += grass 0.25 v (0.3 + 0.5 jolt)
	fsadd.s	K_03(pc),fp1
	fsmove.l d2,fp0
	fsmul.s	K_QTR(pc),fp0
	fsmul.x	fp4,fp0
	fsmul.x	fp1,fp0
	fsadd.x	fp0,fp2
	fsmove.l d2,fp0				; high += grass 0.25 v 0.15
	fsmul.s	K_QTR(pc),fp0
	fsmul.x	fp4,fp0
	fsmul.s	K_015(pc),fp0
	fsadd.x	fp0,fp3
ru_4:	move.l	MS_SKID(a5),a0			; skidding
	tst.l	(a0)
	beq.s	ru_5
	tst.l	CS_LAUNCH(a4)
	bne.s	ru_5
	fsmove.s CS_SLIDE(a4),fp0
	fsdiv.s	K_3000(pc),fp0
	fcmp.s	K_ONE(pc),fp0
	fble	ru_4a
	fsmove.s K_ONE(pc),fp0
ru_4a:	fsmul.s	K_03(pc),fp0
	fsadd.s	K_QTR(pc),fp0
	fsadd.x	fp0,fp3
ru_5:	fsmove.s CS_LOCK(a4),fp0		; locked
	ftst.x	fp0
	fbeq	ru_6
	fsadd.s	K_02(pc),fp3
	fsadd.s	K_015(pc),fp2
ru_6:	tst.l	CS_LAUNCH(a4)			; a launch
	beq.s	ru_7
	fsadd.s	K_04(pc),fp3
	fsadd.s	K_015(pc),fp2
ru_7:	tst.l	CS_SPIN(a4)			; a spin
	beq.s	ru_k
	fsadd.s	K_03(pc),fp2
ru_k:	fsadd.s	(a1),fp2			; + the knock, at most 1
	fsadd.s	4(a1),fp3
	fcmp.s	K_ONE(pc),fp2
	fble	ru_8
	fsmove.s K_ONE(pc),fp2
ru_8:	fcmp.s	K_ONE(pc),fp3
	fble	ru_9
	fsmove.s K_ONE(pc),fp3
ru_9:	move.l	MS_RLOW(a5),a0
	fmove.s	fp2,(a0)
	move.l	MS_RHIGH(a5),a0
	fmove.s	fp3,(a0)
	fmovem.x (sp)+,fp2-fp4
	movem.l	(sp)+,d2/a4-a5
	rts

; ---------------------------------------------------------------------------------------------------------------
; int near68k(const void *rec, int n, int stride, float x, float y): main.c nearest_wall / nearest_dir -- the
; record whose x, y (at +4, +8) is nearest (x, y): d = (rx - x)^2 + (ry - y)^2, the first of equals; -1 none
	xdef	_near68k
	xdef	near68k
_near68k:
near68k:
	movem.l	d2-d4,-(sp)
	fmovem.x fp2-fp4,-(sp)
	lea	12+36+4(sp),a1
	move.l	(a1)+,a0			; rec
	move.l	(a1)+,d2			; n
	move.l	(a1)+,d3			; stride
	fsmove.s (a1)+,fp2			; x
	fsmove.s (a1),fp3			; y
	fsmove.s K_1E30(pc),fp4
	moveq	#-1,d0				; best
	moveq	#0,d1				; i
	bra.s	nr_n
nr_l:	fsmove.s 4(a0),fp0
	fssub.x	fp2,fp0
	fsmul.x	fp0,fp0
	fsmove.s 8(a0),fp1
	fssub.x	fp3,fp1
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fcmp.x	fp4,fp0
	fbnlt	nr_1
	fsmove.x fp0,fp4
	move.l	d1,d0
nr_1:	add.l	d3,a0
	addq.l	#1,d1
nr_n:	cmp.l	d2,d1
	blt.s	nr_l
	fmovem.x (sp)+,fp2-fp4
	movem.l	(sp)+,d2-d4
	rts

; ---------------------------------------------------------------------------------------------------------------
; void pose68k(const pz_ctx *x): mesh.c mesh_pose (mesh_pose_c the reference, OS_POSEASM=c): each part's corners
; turned and moved by the frame's 3x3 + shift (int16, 16383 = 1), its normals turned the other way round
PZ_VERT	equ	0
PZ_NORM	equ	4
PZ_PART	equ	8
PZ_NP	equ	12
PZ_F	equ	16
	xdef	_pose68k
	xdef	pose68k
_pose68k:
pose68k:
	movem.l	d2-d7/a2-a5,-(sp)
	fmovem.x fp2-fp5,-(sp)
	lea	-48(sp),sp			; the frame's twelve as floats
	move.l	48+48+40+4(sp),a5
	move.l	PZ_PART(a5),a4
	move.l	PZ_NP(a5),d7
	bra	pz_pn
pz_p:	move.l	16(a4),a0			; frame + 24 f
	move.l	PZ_F(a5),d0
	mulu.l	#24,d0
	add.l	d0,a0
	moveq	#11,d1
	move.l	sp,a1
pz_q:	fsmove.w (a0)+,fp0
	fmove.s	fp0,(a1)+
	dbra	d1,pz_q
	move.l	20(a4),a1			; the corners
	move.l	(a4),d0
	mulu.l	#12,d0
	move.l	PZ_VERT(a5),a2
	add.l	d0,a2
	move.l	4(a4),d6
	bra.s	pz_vn
pz_v:	fsmove.s (a1)+,fp2
	fsmove.s (a1)+,fp3
	fsmove.s (a1)+,fp4
	moveq	#0,d1
pz_va:	fsmove.s (sp,d1.l),fp0			; (q[a] x + q[3+a] y + q[6+a] z) k + q[9+a]
	fsmul.x	fp2,fp0
	fsmove.s 12(sp,d1.l),fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fsmove.s 24(sp,d1.l),fp1
	fsmul.x	fp4,fp1
	fsadd.x	fp1,fp0
	fsmul.s	K_16383(pc),fp0
	fsadd.s	36(sp,d1.l),fp0
	fmove.s	fp0,(a2)+
	addq.l	#4,d1
	cmp.l	#12,d1
	blt.s	pz_va
pz_vn:	subq.l	#1,d6
	bpl.s	pz_v
	move.l	24(a4),a1			; the normals: -(the same turn) k
	move.l	8(a4),d0
	mulu.l	#12,d0
	move.l	PZ_NORM(a5),a2
	add.l	d0,a2
	move.l	12(a4),d6
	bra.s	pz_nn
pz_n:	fsmove.s (a1)+,fp2
	fsmove.s (a1)+,fp3
	fsmove.s (a1)+,fp4
	moveq	#0,d1
pz_na:	fsmove.s (sp,d1.l),fp0
	fsmul.x	fp2,fp0
	fsmove.s 12(sp,d1.l),fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	fsmove.s 24(sp,d1.l),fp1
	fsmul.x	fp4,fp1
	fsadd.x	fp1,fp0
	fsneg.x	fp0
	fsmul.s	K_16383(pc),fp0
	fmove.s	fp0,(a2)+
	addq.l	#4,d1
	cmp.l	#12,d1
	blt.s	pz_na
pz_nn:	subq.l	#1,d6
	bpl.s	pz_n
	lea	28(a4),a4
pz_pn:	subq.l	#1,d7
	bpl	pz_p
	lea	48(sp),sp
	fmovem.x (sp)+,fp2-fp5
	movem.l	(sp)+,d2-d7/a2-a5
	rts

; ---------------------------------------------------------------------------------------------------------------
; void vp68k(const vp_ctx *x): main.c view_pose (view_pose_c the reference): the camera from the car (in it: the
; body's drop, pitch and lean) or behind it at the chase's heading, pitch, lean and height
	xdef	_vp68k
	xdef	vp68k
_vp68k:
vp68k:
	movem.l	a2-a5,-(sp)
	fmovem.x fp2,-(sp)
	move.l	12+16+4(sp),a5
	move.l	(a5),a3				; cam
	move.l	4(a5),a4			; the car
	move.l	8(a5),a2			; the view
	move.l	28(a5),a1			; &g_hide
	clr.l	(a1)
	tst.l	16(a2)
	beq.s	vp_ch
	move.l	12(a5),a0			; in the car
	move.l	CS_X(a4),(a3)
	move.l	CS_Y(a4),4(a3)
	fsmove.s CS_Z(a4),fp0			; z = c.z + camera_hi + drop
	fsadd.s	20(a5),fp0
	fsadd.s	16(a0),fp0
	fmove.s	fp0,8(a3)
	fsmove.s CS_YAW(a4),fp0			; yaw = yaw + drift - pi/2
	fsadd.s	CS_DRIFT(a4),fp0
	fssub.s	K_PI2B(pc),fp0
	fmove.s	fp0,12(a3)
	fsmove.s 8(a0),fp0			; pitch = c.pitch + body_pitch 0.5
	fsmul.s	K_HALF(pc),fp0
	fsadd.s	CS_PITCH(a4),fp0
	fmove.s	fp0,16(a3)
	fsmove.s 12(a0),fp0			; roll = c.roll - body_roll 0.75
	fsmul.s	K_075(pc),fp0
	fsmove.s CS_ROLL(a4),fp1
	fssub.x	fp0,fp1
	fmove.s	fp1,20(a3)
	move.l	24(a5),(a1)			; the car hidden
	bra	vp_x
vp_ch:	move.l	16(a5),a1			; behind it
	fsmove.s 4(a1),fp0			; cp = cosf(pitch)
	MSIN	36
	fsmove.x fp0,fp2
	fsmul.s	4(a2),fp2			; cp behind
	fsmove.s (a1),fp0			; x = c.x - cp behind sinf(yaw)
	MSIN	32
	fsmul.x	fp2,fp0
	fsmove.s CS_X(a4),fp1
	fssub.x	fp0,fp1
	fmove.s	fp1,(a3)
	move.l	16(a5),a1
	fsmove.s (a1),fp0			; y = c.y + cp behind cosf(yaw)
	MSIN	36
	fsmul.x	fp2,fp0
	fsadd.s	CS_Y(a4),fp0
	fmove.s	fp0,4(a3)
	move.l	16(a5),a1
	move.l	12(a1),8(a3)			; z = the chase's height
	fsmove.s (a1),fp0			; yaw - pi/2
	fssub.s	K_PI2B(pc),fp0
	fmove.s	fp0,12(a3)
	move.l	4(a1),16(a3)
	move.l	8(a1),20(a3)
vp_x:	fmovem.x (sp)+,fp2
	movem.l	(sp)+,a2-a5
	rts

; ---------------------------------------------------------------------------------------------------------------
; void ph68k(const ph_ctx *x, opponent *o, float nx, ny, pen): main.c player_hits (player_hits_c the reference):
; the contact, the crash's sound (C), off the road the player is put back, else ahead of it the opponent is shoved
; and knocked round and the player bounces off, behind it the opponent loses speed; the opponent pushed aside
	xdef	_ph68k
	xdef	ph68k
_ph68k:
ph68k:
	movem.l	d2/a3-a5,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	72+16+4(sp),a1
	move.l	(a1)+,a5			; x
	move.l	(a1)+,a3			; o
	fsmove.s (a1)+,fp6			; nx
	fsmove.s (a1)+,fp7			; ny
	fsmove.s (a1),fp0			; pen
	move.l	(a5),a4				; the car
	fsmove.x fp6,fp4			; px, py
	fsmul.x	fp0,fp4
	fsmove.x fp7,fp5
	fsmul.x	fp0,fp5
	move.l	4(a5),a0			; contact
	move.l	#1,(a0)
	move.l	28(a5),a0			; the sound (C)
	jsr	(a0)
	fsmove.s O_X(a3),fp0			; on the road at o - p?
	fssub.x	fp4,fp0
	fsmove.s O_Y(a3),fp1
	fssub.x	fp5,fp1
	clr.l	-(sp)
	clr.l	-(sp)
	fmove.s	fp1,-(sp)
	fmove.s	fp0,-(sp)
	move.l	16(a5),a0
	jsr	(a0)
	lea	16(sp),sp
	tst.l	d0
	bne.s	ph_on
	fsmove.s CS_X(a4),fp0			; no: the player put back
	fsadd.x	fp4,fp0
	fmove.s	fp0,CS_X(a4)
	fsmove.s CS_Y(a4),fp0
	fsadd.x	fp5,fp0
	fmove.s	fp0,CS_Y(a4)
	bra	ph_x
ph_on:	fsmove.s CS_YAW(a4),fp0			; fx = sin yaw, fy = -cos yaw
	MSIN	20
	fsmove.x fp0,fp2
	fsmove.s CS_YAW(a4),fp0
	MSIN	24
	fsneg.x	fp0,fp3
	fsmove.s O_X(a3),fp0			; ahead = (o.x - c.x) fx + (o.y - c.y) fy
	fssub.s	CS_X(a4),fp0
	fsmul.x	fp2,fp0
	fsmove.s O_Y(a3),fp1
	fssub.s	CS_Y(a4),fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp1,fp0
	ftst.x	fp0
	fblt	ph_bh
	fsmove.s O_YAW(a3),fp0			; its forward (sin, -cos), its right (-cos, -sin)
	MSIN	20
	fsmove.x fp0,fp2			; s
	fsmove.s O_YAW(a3),fp0
	MSIN	24
	fsmove.x fp0,fp3			; c
	fsmove.s CS_X(a4),fp0			; rel
	fssub.s	O_X(a3),fp0
	fsmove.s CS_Y(a4),fp1
	fssub.s	O_Y(a3),fp1
	moveq	#0,d2				; bit 0 left, bit 1 behind
	fsmove.x fp3,fp4			; rel_x orx + rel_y ory < 0: left
	fsneg.x	fp4
	fsmul.x	fp0,fp4
	fsmove.x fp2,fp5
	fsneg.x	fp5
	fsmul.x	fp1,fp5
	fsadd.x	fp5,fp4
	ftst.x	fp4
	fbnlt	ph_1
	bset	#0,d2
ph_1:	fsmove.x fp2,fp4			; rel_x ofx + rel_y ofy < 0: behind
	fsmul.x	fp0,fp4
	fsmove.x fp3,fp5
	fsneg.x	fp5
	fsmul.x	fp1,fp5
	fsadd.x	fp5,fp4
	ftst.x	fp4
	fbnlt	ph_2
	bset	#1,d2
ph_2:	fsmove.s CS_SPEED(a4),fp0		; o.shove = speed / 2
	fsmul.s	K_HALF(pc),fp0
	fmove.s	fp0,O_SHOVE(a3)
	fsmove.s CS_SPEED(a4),fp0		; turn = speed 0.0001, at most pi/2
	fsmul.s	K_1EM4(pc),fp0
	fcmp.s	K_PI2B(pc),fp0
	fble	ph_3
	fsmove.s K_PI2B(pc),fp0
ph_3:	btst	#0,d2				; spin = (behind ? 1 : -1)(left ? 1 : -1) turn
	sne	d0
	btst	#1,d2
	sne	d1
	cmp.b	d0,d1
	beq.s	ph_4
	fsneg.x	fp0
ph_4:	fmove.s	fp0,O_SPIN(a3)
	fsmove.s CS_SPEED(a4),fp0		; the player: shove, its way, the nose
	fsmul.s	K_021(pc),fp0
	fmove.s	fp0,CS_SHOVE(a4)
	fmove.s	fp6,CS_SHX(a4)
	fmove.s	fp7,CS_SHY(a4)
	fsmove.s K_2EM4(pc),fp0
	btst	#0,d2
	bne.s	ph_5
	fsneg.x	fp0
ph_5:	fsmul.s	CS_SPEED(a4),fp0
	fmove.s	fp0,CS_YAWR(a4)
	fsmove.s CS_SPEED(a4),fp0
	fsmul.s	12(a5),fp0
	fmove.s	fp0,CS_SPEED(a4)
	move.l	8(a5),a0
	addq.l	#1,(a0)
	bra.s	ph_o
ph_bh:	fsmove.s O_SPEED(a3),fp0		; behind it: it loses speed
	fsmul.s	K_07(pc),fp0
	fmove.s	fp0,O_SPEED(a3)
ph_o:	fsmove.x fp6,fp0			; it is pushed aside
	fsneg.x	fp0
	fmove.s	fp0,O_SHX(a3)
	fsmove.x fp7,fp0
	fsneg.x	fp0
	fmove.s	fp0,O_SHY(a3)
	fsmove.x fp6,fp4			; (px, py again: fp4 fp5 were used)
	fsmul.s	(72+16+4+16)(sp),fp4
	fsmove.x fp7,fp5
	fsmul.s	(72+16+4+16)(sp),fp5
	fsmove.s O_OFFX(a3),fp0
	fssub.x	fp4,fp0
	fmove.s	fp0,O_OFFX(a3)
	fsmove.s O_OFFY(a3),fp0
	fssub.x	fp5,fp0
	fmove.s	fp0,O_OFFY(a3)
	clr.l	O_AGE(a3)
ph_x:	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2/a3-a5
	rts

; ---------------------------------------------------------------------------------------------------------------
; void sky68k(const sk_ctx *x): main.c sky_paint for a backdrop a power of two wide (sky_paint_c the reference,
; OS_SKYASM=c): the backdrop's column and row a straight-line function of the screen's, worked out at each row's
; start in floats (as gcc does it, floor exact by fintrz) and stepped along it in 16.16; level rows a copy round
; the end, tilted ones in stretches of one backdrop row; below the backdrop the ground's colour
SK_FB	equ	0
SK_FBW	equ	4
SK_VH	equ	8
SK_CY	equ	12
SK_GS	equ	16
SK_SY	equ	20
SK_W	equ	24
SK_H	equ	28
SK_PK	equ	32
SK_GND	equ	36
SK_YAW	equ	40
SK_PITCH equ	44
SK_ROLL	equ	48
SK_FOC	equ	52
SK_SIN	equ	56
SK_COS	equ	60
SK_MCPY	equ	64
SK_DBL	equ	68				; main.c sky_doubled: each byte twice (or 0)
SK_DST	equ	72
SK_PAD	equ	76				; main.c sky_padded (or 0), rows above and ground below
SK_PADA	equ	80
SK_PADN	equ	84
; locals
KL_DU	equ	0
KL_DV	equ	4
KL_SX	equ	8
KL_SY	equ	12
KL_W	equ	16
KL_MASK	equ	20
KL_GND4	equ	24
KL_T	equ	28
KL_Y	equ	32
KL_FU	equ	36
KL_UI	equ	40				; sr = 0: the rows' ui, worked out once (KL_UOK = 1)
KL_UOK	equ	44
KL_LOC	equ	48

; fp0 = floor(fp0), exactly (fp1 used)
FLOOR	macro
	fintrz.x fp0,fp1
	fcmp.x	fp0,fp1
	fble	.f\@
	fsub.s	K_ONE(pc),fp1
.f\@:	fmove.x	fp1,fp0
	endm

	xdef	_sky68k
	xdef	sky68k
_sky68k:
sky68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-KL_LOC(sp),sp
	move.l	KL_LOC+72+48(sp),a5
	fsmove.s SK_ROLL(a5),fp0		; cr, sr
	MSIN	SK_COS
	fsmove.x fp0,fp2
	fsmove.s SK_ROLL(a5),fp0
	MSIN	SK_SIN
	fsmove.x fp0,fp3
	fsmove.l SK_W(a5),fp0			; w, sx, sy as floats
	fmove.s	fp0,KL_W(sp)
	fsmove.l SK_GS(a5),fp0
	fmove.s	fp0,KL_SX(sp)
	fsmove.l SK_SY(a5),fp0
	fmove.s	fp0,KL_SY(sp)
	fsmove.s SK_YAW(a5),fp0			; heading = (yaw + pi/2) 1024 / pi
	fsadd.s	K_PI2B(pc),fp0
	fsmul.s	K_1024PI(pc),fp0
	fsmove.s K_2047(pc),fp7			; off = (2047 - heading) / 2, less whole turns of w
	fssub.x	fp0,fp7
	fsmul.s	K_HALF(pc),fp7
	fsmove.x fp7,fp0
	fsdiv.s	KL_W(sp),fp0
	FLOOR
	fsmul.s	KL_W(sp),fp0
	fssub.x	fp0,fp7
	fsmove.s SK_PITCH(a5),fp0		; top = cy / sy + (22 - h) + focal_y / sy sin(pitch)
	MSIN	SK_SIN
	fsmove.s SK_FOC(a5),fp1
	fsdiv.s	KL_SY(sp),fp1
	fsmul.x	fp0,fp1
	fsmove.s SK_CY(a5),fp5			; (cy / sy)
	fsdiv.s	KL_SY(sp),fp5
	fsmove.s K_22(pc),fp0
	fsmove.l SK_H(a5),fp6
	fssub.x	fp6,fp0
	fsmove.x fp5,fp6
	fsadd.x	fp0,fp6
	fsadd.x	fp1,fp6				; top
	fsmove.x fp2,fp0			; du = (int)(cr / sx 65536), dv = (int)(-sr / sx 65536)
	fsdiv.s	KL_SX(sp),fp0
	fsmul.s	K_65536(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,KL_DU(sp)
	fsmove.x fp3,fp0
	fsneg.x	fp0
	fsdiv.s	KL_SX(sp),fp0
	fsmul.s	K_65536(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,KL_DV(sp)
	move.l	SK_FBW(a5),d6
	move.l	d6,d0				; ax = -FB_W 0.5 / sx
	neg.l	d0
	fsmove.l d0,fp4
	fsmul.s	K_HALF(pc),fp4
	fsdiv.s	KL_SX(sp),fp4
	fsmove.l d6,fp0				; off + FB_W 0.5 / sx
	fsmul.s	K_HALF(pc),fp0
	fsdiv.s	KL_SX(sp),fp0
	fsadd.x	fp0,fp7
	move.l	SK_W(a5),d0
	subq.l	#1,d0
	move.l	d0,KL_MASK(sp)
	moveq	#0,d0				; the ground's colour four times
	move.b	SK_GND+3(a5),d0
	mulu.l	#$01010101,d0
	move.l	d0,KL_GND4(sp)
	move.l	SK_PK(a5),a3
	move.l	SK_FB(a5),a4			; the row
	clr.l	KL_Y(sp)			; y
	clr.l	KL_UOK(sp)
sk_y:	move.l	KL_Y(sp),d7
	cmp.l	SK_VH(a5),d7
	bge	sk_x
	fsmove.l d7,fp1				; ay = (cy - y) / sy
	fsmove.s SK_CY(a5),fp0
	fssub.x	fp1,fp0
	fsdiv.s	KL_SY(sp),fp0
	fmove.s	fp0,KL_T(sp)
	tst.l	KL_UOK(sp)			; sr = 0: ax cr - ay 0 is ax cr in every row, so ui is the first row's, and
	beq.s	sk_uc				; uy = ax 0 + ay cr is ay cr (adding +-0 changes no rounded value)
	move.l	KL_UI(sp),d3
	fsmove.s KL_T(sp),fp1
	fsmul.x	fp2,fp1
	bra	sk_vi
sk_uc:	fsmove.x fp4,fp0			; fu = off + FB_W/2/sx + (ax cr - ay sr), less whole turns of w
	fsmul.x	fp2,fp0
	fsmove.s KL_T(sp),fp1
	fsmul.x	fp3,fp1
	fssub.x	fp1,fp0
	fsadd.x	fp7,fp0
	fmove.s	fp0,KL_FU(sp)
	fsdiv.s	KL_W(sp),fp0
	FLOOR
	fsmul.s	KL_W(sp),fp0
	fsmove.s KL_FU(sp),fp1
	fssub.x	fp0,fp1
	fsmul.s	K_65536(pc),fp1			; ui = (int)(fu 65536)
	fintrz.x fp1,fp1
	fmove.l	fp1,d3
	ftst.x	fp3
	fbne	sk_us
	move.l	d3,KL_UI(sp)
	moveq	#1,d0
	move.l	d0,KL_UOK(sp)
sk_us:	fsmove.s KL_T(sp),fp0			; uy = ax sr + ay cr
	fsmul.x	fp2,fp0
	fsmove.x fp4,fp1
	fsmul.x	fp3,fp1
	fsadd.x	fp0,fp1
sk_vi:	fsmove.x fp5,fp0			; vi = (int)floor((cy / sy - uy - top) 65536)
	fssub.x	fp1,fp0
	fssub.x	fp6,fp0
	fsmul.s	K_65536(pc),fp0
	FLOOR
	fmove.l	fp0,d2
	move.l	KL_DU(sp),d5
	move.l	KL_DV(sp),d4
	move.l	a4,a1				; the row
	tst.l	d4
	bne	sk_t
	move.l	d2,d0				; level: one backdrop row, or ground
	swap	d0
	ext.l	d0
	cmp.l	SK_H(a5),d0
	blt.s	sk_u1
	ftst.x	fp2				; cr > 0: vi grows with y, so every row from here is ground: no more sums
	fbngt	sk_g0
sk_ga:	bsr	sk_gnd_row
	add.l	d6,a4
	move.l	a4,a1
	addq.l	#1,KL_Y(sp)
	move.l	KL_Y(sp),d7
	cmp.l	SK_VH(a5),d7
	blt.s	sk_ga
	bra	sk_x
sk_g0:	bsr	sk_gnd_row
	bra	sk_n
sk_u1:	tst.l	d0
	bpl.s	sk_u2
	moveq	#0,d0
sk_u2:	cmp.l	#32768,d5			; half a byte a pixel (high resolution, level): one copy out of the
	bne.s	sk_u2n				; doubled rows, from (ui >> 15) & (2w - 1) (main.c sky_doubled)
	move.l	SK_DBL(a5),d1
	beq.s	sk_u2n
	mulu.l	SK_DST(a5),d0
	add.l	d0,d1
	move.l	d3,d0
	moveq	#15,d4
	asr.l	d4,d0
	move.l	KL_MASK(sp),d4
	add.l	d4,d4
	addq.l	#1,d4
	and.l	d4,d0
	add.l	d0,d1
	ifd	V080
	tst.l	raster_sm8			; the 080 (AMMX tested: span.c): the row 64 bits at a time, unaligned
	beq.s	sk_cpj				; source allowed (FB_W a multiple of 8), no call
	move.l	d1,a0
	move.l	d6,d0
	lsr.l	#3,d0
	subq.l	#1,d0
sk_cpl:	load	(a0)+,e0
	store	e0,(a1)+
	dbra	d0,sk_cpl
	bra	sk_n
sk_cpj:
	endif
	move.l	d6,-(sp)
	move.l	d1,-(sp)
	move.l	a1,-(sp)
	move.l	SK_MCPY(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	bra	sk_n
sk_u2n:	mulu.l	SK_W(a5),d0
	lea	(a3,d0.l),a2			; src
	cmp.l	#65536,d5
	bne.s	sk_u5
	move.l	d3,d0				; one to one: a copy, round the end
	swap	d0
	and.l	KL_MASK(sp),d0			; px
	move.l	SK_W(a5),d4
	sub.l	d0,d4				; first = min(w - px, FB_W)
	cmp.l	d6,d4
	ble.s	sk_u3
	move.l	d6,d4
sk_u3:	move.l	d4,-(sp)
	pea	(a2,d0.l)
	move.l	a1,-(sp)
	move.l	SK_MCPY(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	move.l	d4,d2				; x
sk_u4:	cmp.l	d6,d2
	bge	sk_n
	move.l	d6,d1				; min(FB_W - x, w)
	sub.l	d2,d1
	cmp.l	SK_W(a5),d1
	ble.s	sk_u4b
	move.l	SK_W(a5),d1
sk_u4b:	move.l	d1,-(sp)
	move.l	a2,-(sp)
	pea	(a4,d2.l)
	move.l	SK_MCPY(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	add.l	SK_W(a5),d2
	bra.s	sk_u4
sk_u5:	move.l	d6,d1				; stepped: src[(ui >> 16) & mask]
	subq.l	#1,d1
	move.l	KL_MASK(sp),d4
sk_u6:	move.l	d3,d0
	swap	d0
	and.l	d4,d0
	move.b	(a2,d0.l),(a1)+
	add.l	d5,d3
	dbra	d1,sk_u6
	bra	sk_n
sk_t:	move.l	SK_PAD(a5),d0			; tilted: with the padded table every pixel as one texel, when the
	beq	sk_t0				; row's v stays within it (the stretches below find the same rows)
	move.l	d6,d0
	subq.l	#1,d0
	muls.l	d4,d0
	add.l	d2,d0				; v at the row's end
	swap	d0
	ext.l	d0				; (>> 16, rounded down)
	move.l	d2,d1
	swap	d1
	ext.l	d1
	cmp.l	d0,d1				; d1 = lowest row, d0 = highest
	ble.s	sk_p1
	exg	d0,d1
sk_p1:	cmp.l	SK_H(a5),d1
	blt.s	sk_p2
	bsr	sk_gnd_row			; all of it ground
	bra	sk_n
sk_p2:	add.l	SK_PADA(a5),d1
	bmi	sk_t0				; above the table
	add.l	SK_PADA(a5),d0
	cmp.l	SK_PADN(a5),d0
	bge	sk_t0				; below it
	movem.l	d2-d7,-(sp)
	move.l	SK_PAD(a5),a2
	move.l	SK_PADA(a5),d0
	swap	d0
	clr.w	d0
	add.l	d0,d2				; V' = v + PADA << 16 (>= 0 over the whole row)
	move.l	d6,d7
	subq.l	#1,d7
	move.l	d2,d0				; the first texel's index: (V' >> 16) << 9 | (u >> 16) & 511
	move.l	d3,d1
	lsr.l	#7,d0
	swap	d1
	and.l	#-512,d0
	and.l	#511,d1
	add.l	d4,d2
	or.l	d1,d0
	add.l	d5,d3
sk_pl:	move.b	(a2,d0.l),d6			; a pixel's texel; the next one's index worked out behind it
	move.l	d2,d0
	move.l	d3,d1
	lsr.l	#7,d0
	swap	d1
	and.l	#-512,d0
	and.l	#511,d1
	add.l	d4,d2
	or.l	d1,d0
	add.l	d5,d3
	move.b	d6,(a1)+
	dbra	d7,sk_pl
	movem.l	(sp)+,d2-d7
	bra	sk_n
sk_t0:	moveq	#0,d1				; tilted: stretches of one backdrop row; d1 = x
sk_t1:	cmp.l	d6,d1
	bge	sk_n
	move.l	d2,d0				; v
	swap	d0
	ext.l	d0
	move.l	d2,d7				; frac = vi & 0xffff
	and.l	#$ffff,d7
	tst.l	d4
	bmi.s	sk_t2
	neg.l	d7				; k = (65536 - frac + dv - 1) / dv
	add.l	#65535,d7
	add.l	d4,d7
	divu.l	d4,d7
	bra.s	sk_t3
sk_t2:	move.l	d4,KL_T(sp)			; k = frac / -dv + 1
	neg.l	KL_T(sp)
	divu.l	KL_T(sp),d7
	addq.l	#1,d7
sk_t3:	move.l	d6,KL_T(sp)			; at most FB_W - x, at least 1
	sub.l	d1,KL_T(sp)
	cmp.l	KL_T(sp),d7
	ble.s	sk_t4
	move.l	KL_T(sp),d7
sk_t4:	cmp.l	#1,d7
	bge.s	sk_t5
	moveq	#1,d7
sk_t5:	move.l	d7,a0				; (k)
	subq.l	#1,d7
	cmp.l	SK_H(a5),d0
	blt.s	sk_t6
	move.b	SK_GND+3(a5),d0			; ground
sk_tg:	move.b	d0,(a1)+
	dbra	d7,sk_tg
	bra.s	sk_t8
sk_t6:	tst.l	d0
	bpl.s	sk_t6a
	moveq	#0,d0
sk_t6a:	mulu.l	SK_W(a5),d0
	lea	(a3,d0.l),a2
	move.l	d3,a6				; u_
	cmp.l	#24,d7				; a long stretch (k >= 25): u swapped (frac << 16 | int) with add.l/addx.w,
	blo.s	sk_t7				; the index a pixel ahead, load and store apart (as span_68k.s TEXU: no
	movem.l	d1-d6,-(sp)			; ALU result straight into an address); same index ((u >> 16) & mask)
	move.l	KL_MASK+24(sp),d6
	move.l	d3,d1
	swap	d1				; R = frac << 16 | int
	move.l	d5,d2
	swap	d2
	move.w	d2,d4				; I = du >> 16
	clr.w	d2				; F = (du & $ffff) << 16
	move.w	d1,d0
	and.w	d6,d0
	add.l	d2,d1
	addx.w	d4,d1
sk_tf:	move.b	(a2,d0.w),d3
	move.w	d1,d0
	add.l	d2,d1
	and.w	d6,d0				; (and: X unchanged)
	addx.w	d4,d1
	move.b	d3,(a1)+
	dbra	d7,sk_tf
	movem.l	(sp)+,d1-d6
	bra.s	sk_t8
sk_t7:	move.l	a6,d0
	swap	d0
	and.l	KL_MASK(sp),d0
	move.b	(a2,d0.l),(a1)+
	add.l	d5,a6
	dbra	d7,sk_t7
sk_t8:	move.l	a0,d7				; x += k; ui += du k; vi += dv k
	add.l	d7,d1
	move.l	d7,d0
	muls.l	d5,d0
	add.l	d0,d3
	move.l	d7,d0
	muls.l	d4,d0
	add.l	d0,d2
	bra	sk_t1
sk_n:	addq.l	#1,KL_Y(sp)
	add.l	d6,a4
	bra	sk_y
sk_x:	lea	KL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts
sk_gnd_row:					; a1: FB_W bytes of the ground's colour
	move.l	d6,d1
	lsr.l	#2,d1
	subq.l	#1,d1
	move.l	KL_GND4+4(sp),d0
sk_g1:	move.l	d0,(a1)+
	dbra	d1,sk_g1
	rts

; ---------------------------------------------------------------------------------------------------------------
; void radar68k(const rd_ctx *x): main.c hud_radar's walls and dots (rad_walls_c the reference, OS_RADASM=c): each
; wall within 70000 turned into the radar's frame (x right, y down, s = zoom / 32768), its ends cut down (floor,
; exactly) and joined (hud_line68k); each opponent a dot (hud_sprite_px, C)
RD_W	equ	0
RD_NW	equ	4
RD_CX	equ	8
RD_CY	equ	12
RD_YAW	equ	16
RD_ZS	equ	20
RD_GS	equ	24
RD_SIN	equ	28
RD_COS	equ	32
RD_LINE	equ	36
RD_FB	equ	40
RD_PITCH equ	44
RD_CLIP	equ	48
RD_OY	equ	64
RD_OPP	equ	68
RD_NOPP	equ	72
RD_DOT	equ	76
RD_GF	equ	80				; the walls' grid (main.c rad_grid; 0: every wall): first a cell, the walls' numbers,
RD_GI	equ	84				; the grid's width and the cells to visit kx0..kx1, ky0..ky1 (a row's cells one run)
RD_GW	equ	88
RD_KX0	equ	92
RD_KX1	equ	96
RD_KY0	equ	100
RD_KY1	equ	104
; locals: a hud_line (48 bytes), then 48 s, 52 x0 base (40 gs), 56 y0 base (160 gs)
RL_S	equ	48
RL_BX	equ	52
RL_BY	equ	56
RL_LOC	equ	60

; RDPT \1: a wall's end (fp4, fp5 = its dx, dy) to the line's x at \1(sp) and y at \1+4(sp) -- the two sums side by
; side (the FPU's latency covered), each exactly as before: (dx cs + dy sn) s and (dy cs - dx sn) s, floored
RDPT	macro
	fsmove.x fp4,fp0
	fsmove.x fp5,fp6
	fsmul.x	fp2,fp0				; dx cs
	fsmul.x	fp2,fp6				; dy cs
	fsmove.x fp5,fp1
	fsmove.x fp4,fp7
	fsmul.x	fp3,fp1				; dy sn
	fsmul.x	fp3,fp7				; dx sn
	fsadd.x	fp1,fp0
	fssub.x	fp7,fp6
	fsmul.s	RL_S(sp),fp0
	fsmul.s	RL_S(sp),fp6
	fintrz.x fp0,fp1			; floor (FLOOR, twice)
	fintrz.x fp6,fp7
	fcmp.x	fp0,fp1
	fble	.a\@
	fsub.s	K_ONE(pc),fp1
.a\@:	fcmp.x	fp6,fp7
	fble	.b\@
	fsub.s	K_ONE(pc),fp7
.b\@:	fmove.l	fp1,d0
	fmove.l	fp7,d1
	move.l	RL_BX(sp),d2
	sub.l	d0,d2
	move.l	d2,\1(sp)
	add.l	RL_BY(sp),d1
	move.l	d1,\1+4(sp)
	endm
	xdef	_radar68k
	xdef	radar68k
_radar68k:
radar68k:
	movem.l	d2-d7/a2-a6,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-RL_LOC(sp),sp
	move.l	RL_LOC+72+48(sp),a5
	fsmove.l RD_ZS(a5),fp0			; s = (float)(zoom g_s) / 32768
	fsdiv.s	K_32768(pc),fp0
	fmove.s	fp0,RL_S(sp)
	fsmove.s RD_YAW(a5),fp0			; cs, sn
	MSIN	RD_COS
	fsmove.x fp0,fp2
	fsmove.s RD_YAW(a5),fp0
	MSIN	RD_SIN
	fsmove.x fp0,fp3
	move.l	RD_GS(a5),d0
	move.l	d0,d1
	mulu.l	#40,d0
	move.l	d0,RL_BX(sp)
	mulu.l	#160,d1
	move.l	d1,RL_BY(sp)
	move.l	RD_FB(a5),(sp)			; the line's fixed parts
	move.l	RD_PITCH(a5),4(sp)
	move.l	#255,24(sp)
	move.l	RD_CLIP(a5),28(sp)
	move.l	RD_CLIP+4(a5),32(sp)
	move.l	RD_CLIP+8(a5),36(sp)
	move.l	RD_CLIP+12(a5),40(sp)
	move.l	RD_OY(a5),44(sp)
	move.l	RD_GF(a5),d0
	bne	rg_go
	move.l	RD_W(a5),a4
	move.l	RD_NW(a5),d7
	bra	rd_wn
rd_w:	fsmove.s 12(a4),fp4			; ax ay bx by
	fssub.s	RD_CX(a5),fp4
	fsmove.s 16(a4),fp5
	fssub.s	RD_CY(a5),fp5
	fsabs.x	fp4,fp0
	fcmp.s	K_70000(pc),fp0
	fbgt	rd_wx
	fsabs.x	fp5,fp0
	fcmp.s	K_70000(pc),fp0
	fbgt	rd_wx
	RDPT	8				; x0 = 40 gs - floor((ax cs + ay sn) s), y0 = 160 gs + floor((ay cs - ax sn) s)
	fsmove.s 20(a4),fp4			; the other end into fp4 / fp5 (the same sums as before into fp6 / fp7)
	fssub.s	RD_CX(a5),fp4
	fsmove.s 24(a4),fp5
	fssub.s	RD_CY(a5),fp5
	RDPT	16				; x1, y1
	move.l	sp,-(sp)
	move.l	RD_LINE(a5),a0
	jsr	(a0)
	addq.l	#4,sp
rd_wx:	tst.l	RD_GF(a5)
	bne.s	rg_nx
	lea	32(a4),a4
rd_wn:	subq.l	#1,d7
	bpl	rd_w
	bra.s	rd_wd
rg_go:	move.l	d0,a2				; the grid: d3 the row, d6 .. d4 its run of walls
	move.l	RD_GI(a5),a3
	move.l	RD_KY0(a5),d3
	bra.s	rg_y
rg_nx:	addq.l	#1,d6
rg_e:	cmp.l	d4,d6
	bge.s	rg_ny
	move.l	(a3,d6.l*4),d0			; the wall's number: 32 bytes a wall
	lsl.l	#5,d0
	move.l	RD_W(a5),a4
	add.l	d0,a4
	bra	rd_w
rg_ny:	addq.l	#1,d3
rg_y:	cmp.l	RD_KY1(a5),d3
	bgt.s	rd_wd
	move.l	d3,d0
	mulu.l	RD_GW(a5),d0
	move.l	d0,d1
	add.l	RD_KX0(a5),d0
	add.l	RD_KX1(a5),d1
	move.l	(a2,d0.l*4),d6
	move.l	4(a2,d1.l*4),d4
	bra.s	rg_e
rd_wd:
	move.l	RD_OPP(a5),a4			; the opponents' dots
	move.l	RD_NOPP(a5),d7
	fsmove.l RD_GS(a5),fp6			; (float)g_s
	bra	rd_on
rd_o:	fsmove.s O_X(a4),fp4			; dx dy
	fssub.s	RD_CX(a5),fp4
	fsmove.s O_Y(a4),fp5
	fssub.s	RD_CY(a5),fp5
	move.l	#5,-(sp)
	fsmove.x fp5,fp0			; y = (int)(159 gs + (dy cs - dx sn) s)
	fsmul.x	fp2,fp0
	fsmove.x fp4,fp1
	fsmul.x	fp3,fp1
	fssub.x	fp1,fp0
	fsmul.s	RL_S+4(sp),fp0
	fsmove.s K_159(pc),fp1
	fsmul.x	fp6,fp1
	fsadd.x	fp1,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,-(sp)
	fsmove.x fp5,fp0			; x = (int)(39 gs - (dy sn + dx cs) s)
	fsmul.x	fp3,fp0
	fsmove.x fp4,fp1
	fsmul.x	fp2,fp1
	fsadd.x	fp1,fp0
	fsmul.s	RL_S+8(sp),fp0
	fsmove.s K_39(pc),fp1
	fsmul.x	fp6,fp1
	fssub.x	fp0,fp1
	fintrz.x fp1,fp1
	fmove.l	fp1,-(sp)
	move.l	RD_DOT(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	lea	O_SIZE(a4),a4
rd_on:	subq.l	#1,d7
	bpl	rd_o
	lea	RL_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a6
	rts
; d0 = (int)floor(fp0 s)  (the caller's locals at 4(sp))
rd_fl:	fsmul.s	RL_S+4(sp),fp0
	FLOOR
	fmove.l	fp0,d0
	rts

; ---------------------------------------------------------------------------------------------------------------
; char *fmt68k(char *out, int v, int width): v as printf's "%0<width>d" (a minus sign counts in the width), no
; 0 at the end; returns where it stopped
	xdef	_fmt68k
	xdef	fmt68k
_fmt68k:
fmt68k:
	move.l	4(sp),a0
	move.l	8(sp),d0
	move.l	12(sp),d1
fmt_do:	movem.l	d2-d4,-(sp)			; (a0 out, d0 v, d1 width; out: a0 past the last)
	lea	-12(sp),sp			; the digits, last first
	move.l	sp,a1
	moveq	#0,d4				; the sign
	tst.l	d0
	bpl.s	ft_1
	moveq	#1,d4
	neg.l	d0
ft_1:	moveq	#0,d3				; n
ft_2:	divul.l	#10,d2:d0
	add.b	#'0',d2
	move.b	d2,(a1)+
	addq.l	#1,d3
	tst.l	d0
	bne.s	ft_2
	tst.l	d4
	beq.s	ft_3
	move.b	#'-',(a0)+
ft_3:	sub.l	d3,d1				; zeros = width - n - sign
	sub.l	d4,d1
	bra.s	ft_5
ft_4:	move.b	#'0',(a0)+
ft_5:	subq.l	#1,d1
	bpl.s	ft_4
ft_6:	move.b	-(a1),(a0)+
	subq.l	#1,d3
	bne.s	ft_6
	lea	12(sp),sp
	movem.l	(sp)+,d2-d4
	move.l	a0,d0
	rts

; void clk68k(char *out, float t): main.c hud_clock -- "%02d:%02d:%02d" of the whole seconds / 60, % 60 and the
; hundredths (t - whole) 100, each cut towards 0
	xdef	_clk68k
	xdef	clk68k
_clk68k:
clk68k:
	movem.l	d2-d3,-(sp)
	move.l	8+4(sp),a0
	fsmove.s 8+8(sp),fp0
	fintrz.x fp0,fp1			; whole
	fmove.l	fp1,d2
	fsmove.l d2,fp1				; hund = (int)((t - (float)whole) 100)
	fssub.x	fp1,fp0
	fsmul.s	K_100(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d3
	move.l	d2,d0				; whole / 60, whole % 60
	divsl.l	#60,d1:d0
	move.l	d1,d2
	moveq	#2,d1
	bsr	fmt_do
	move.l	d0,a0
	move.b	#':',(a0)+
	move.l	d2,d0
	moveq	#2,d1
	bsr	fmt_do
	move.l	d0,a0
	move.b	#':',(a0)+
	move.l	d3,d0
	moveq	#2,d1
	bsr	fmt_do
	move.l	d0,a0
	clr.b	(a0)
	movem.l	(sp)+,d2-d3
	rts

; ---------------------------------------------------------------------------------------------------------------
; int text68k(const tx_ctx *c, int x, int y, const char *str, int font, int colour, int draw): main.c hud_text where
; the letters are drawn whole (hud_text_c the reference, OS_TEXTASM=c): the font's letters along the line (control
; bytes 1 fixed pitch, 2 proportional, 3 no gap, 4 the gap), each cut to the clip and put by the blit (hud_block),
; colour x 16 added to its shades; returns the width in the layout's pixels
TX_FONT	equ	0
TX_NF	equ	4
TX_S	equ	8
TX_SP	equ	12
TX_NOSP	equ	16
TX_SH	equ	20
TX_OY	equ	24
TX_CLIP	equ	28
TX_FB	equ	44
TX_FBW	equ	48
TX_BLIT	equ	52
TX_U	equ	56			; the gaps' and the cell's unit (main.c hud_text_u)
; locals: a hud_blit (28), then 28 cell, 32 fixed, 36 gap, 40 x0
XL_CELL	equ	28
XL_FIX	equ	32
XL_GAP	equ	36
XL_X0	equ	40
XL_LOC	equ	44

	xdef	_text68k
	xdef	text68k
_text68k:
text68k:
	movem.l	d2-d7/a2-a5,-(sp)
	lea	-XL_LOC(sp),sp
	lea	XL_LOC+40+4(sp),a0
	move.l	(a0)+,a5			; c
	move.l	(a0)+,d6			; x
	move.l	(a0)+,d7			; y
	move.l	(a0)+,a4			; str
	move.l	(a0)+,d0			; font
	move.l	(a0)+,d5			; colour
	move.l	(a0),d4				; draw
	moveq	#0,d1
	tst.l	d0
	bmi	tx_ret0
	cmp.l	TX_NF(a5),d0
	bge	tx_ret0
	mulu.l	#28,d0
	move.l	TX_FONT(a5),a3
	add.l	d0,a3				; ft
	move.l	TX_S(a5),d3			; s_
	muls.l	d3,d6				; x *= s_, y *= s_
	muls.l	d3,d7
	add.l	TX_OY(a5),d7			; (y + oy, as the blit wants it)
	move.l	TX_U(a5),d3			; from here on: u, the gaps' unit (s_ again at the end)
	move.l	TX_SP(a5),d0			; cell = widest + (space ? space s_ : 2 s_)
	cmp.l	TX_NOSP(a5),d0
	bne.s	tx_c1
	moveq	#2,d0
tx_c1:	muls.l	d3,d0
	add.l	20(a3),d0
	move.l	d0,XL_CELL(sp)
	clr.l	XL_FIX(sp)
	move.l	d3,XL_GAP(sp)
	move.l	d6,XL_X0(sp)
	lsl.l	#4,d5				; colour 16
tx_l:	moveq	#0,d0
	move.b	(a4)+,d0
	beq	tx_e
	sub.l	8(a3),d0			; ch - first
	bmi.s	tx_ctl
	cmp.l	12(a3),d0
	blt.s	tx_ch
tx_ctl:	add.l	8(a3),d0			; a control byte
	cmp.l	#1,d0
	bne.s	tx_k2
	move.l	#1,XL_FIX(sp)
	bra.s	tx_l
tx_k2:	cmp.l	#2,d0
	bne.s	tx_k3
	clr.l	XL_FIX(sp)
	bra.s	tx_l
tx_k3:	cmp.l	#3,d0
	bne.s	tx_k4
	clr.l	XL_GAP(sp)
	bra.s	tx_l
tx_k4:	cmp.l	#4,d0
	bne.s	tx_l
	move.l	d3,XL_GAP(sp)
	bra.s	tx_l
tx_ch:	move.l	16(a3),a0			; w = glyph[ch][0]
	move.l	(a0,d0.l*8),d2
	move.l	d6,d1				; gx = x + (space ? 0 : gap) + (fixed ? (cell - (w + s_)) / 2 : 0)
	move.l	TX_SP(a5),a0
	cmp.l	TX_NOSP(a5),a0
	bne.s	tx_g1
	add.l	XL_GAP(sp),d1
tx_g1:	tst.l	XL_FIX(sp)
	beq.s	tx_g2
	move.l	XL_CELL(sp),a0
	sub.l	d2,a0
	sub.l	d3,a0
	move.l	a0,-(sp)
	move.l	(sp)+,a1
	exg	a1,d0
	divsl.l	#2,d0:d0
	exg	a1,d0
	add.l	a1,d1
tx_g2:	tst.l	d4
	beq.s	tx_adv
	move.l	24(a3),a0			; the letter: font_sh + sh[ch]
	move.l	(a0,d0.l*4),a0
	add.l	TX_SH(a5),a0
	bsr	tx_block
tx_adv:	tst.l	XL_FIX(sp)			; x += fixed ? cell : space ? w + space s_ : w + s_ + gap
	beq.s	tx_a1
	add.l	XL_CELL(sp),d6
	bra	tx_l
tx_a1:	move.l	TX_SP(a5),d0
	cmp.l	TX_NOSP(a5),d0
	beq.s	tx_a2
	muls.l	d3,d0
	add.l	d2,d0
	add.l	d0,d6
	bra	tx_l
tx_a2:	add.l	d2,d6
	add.l	d3,d6
	add.l	XL_GAP(sp),d6
	bra	tx_l
tx_e:	move.l	d6,d0				; (x - x0 + s_ - 1) / s_
	move.l	TX_S(a5),d3
	sub.l	XL_X0(sp),d0
	add.l	d3,d0
	subq.l	#1,d0
	divsl.l	d3,d0:d0
	bra.s	tx_ret
tx_ret0: moveq	#0,d0
tx_ret:	lea	XL_LOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a5
	rts
; hud_block(gx = d1, y = d7, src = a0, spitch = w = d2, h = rows, add = d5): cut to the clip, blit
tx_block:
	movem.l	d0-d7/a0-a1,-(sp)
	lea	40+4(sp),a1			; (the caller's locals: the hud_blit at 0)
	moveq	#0,d3				; c0
	move.l	d2,d4				; c1 = w
	moveq	#0,d6				; r0
	move.l	4(a3),a2			; r1 = rows
	move.l	TX_CLIP(a5),d0			; x + c0 < clip x0: c0 = clip x0 - x
	sub.l	d1,d0
	ble.s	tb_1
	move.l	d0,d3
tb_1:	move.l	TX_CLIP+4(a5),d0		; x + c1 > clip x1: c1 = clip x1 - x
	sub.l	d1,d0
	cmp.l	d4,d0
	bge.s	tb_2
	move.l	d0,d4
tb_2:	move.l	TX_CLIP+8(a5),d0		; y + r0 < clip y0
	sub.l	d7,d0
	ble.s	tb_3
	move.l	d0,d6
tb_3:	move.l	TX_CLIP+12(a5),d0		; y + r1 > clip y1
	sub.l	d7,d0
	cmp.l	a2,d0
	bge.s	tb_4
	move.l	d0,a2
tb_4:	cmp.l	d4,d3
	bge.s	tb_x
	cmp.l	a2,d6
	bge.s	tb_x
	move.l	d7,d0				; dst = fb + (y + r0) fbw + x + c0
	add.l	d6,d0
	muls.l	TX_FBW(a5),d0
	add.l	d1,d0
	add.l	d3,d0
	add.l	TX_FB(a5),d0
	move.l	d0,(a1)
	move.l	TX_FBW(a5),4(a1)
	move.l	d6,d0				; src + r0 spitch + c0
	muls.l	d2,d0
	add.l	d3,d0
	add.l	a0,d0
	move.l	d0,8(a1)
	move.l	d2,12(a1)
	sub.l	d3,d4				; w = c1 - c0, h = r1 - r0
	move.l	d4,16(a1)
	move.l	a2,d0
	sub.l	d6,d0
	move.l	d0,20(a1)
	move.l	d5,24(a1)
	move.l	a1,-(sp)
	move.l	TX_BLIT(a5),a0
	jsr	(a0)
	addq.l	#4,sp
tb_x:	movem.l	(sp)+,d0-d7/a0-a1
	rts

; ---------------------------------------------------------------------------------------------------------------
; void pkc68k(uint8_t *to, const int16_t *pic, const int *run, int n): main.c pkc_draw's runs -- each run (picture
; offset, screen offset, length) copied, the low byte of each word
	xdef	_pkc68k
	xdef	pkc68k
_pkc68k:
pkc68k:
	movem.l	d2-d3/a2,-(sp)
	movem.l	12+4(sp),d2/a2			; to, pic
	move.l	12+12(sp),a0			; run
	move.l	12+16(sp),d3			; n
	bra.s	pk_n
pk_r:	move.l	(a0)+,d0			; picture offset (words)
	lea	(a2,d0.l*2),a1
	move.l	(a0)+,d0			; screen offset
	move.l	d2,-(sp)
	add.l	d0,(sp)
	move.l	(a0)+,d1			; length
	move.l	a0,-(sp)
	move.l	4(sp),a0			; at
	bra.s	pk_c2
pk_c:	move.w	(a1)+,d0
	move.b	d0,(a0)+
pk_c2:	dbra	d1,pk_c
	move.l	(sp)+,a0
	addq.l	#4,sp
pk_n:	subq.l	#1,d3
	bpl.s	pk_r
	movem.l	(sp)+,d2-d3/a2
	rts


; void pkcb68k(uint8_t *to, const uint8_t *bytes, const int *run, int n): as pkc68k, the runs' pixels out of one
; stream of bytes (main.c pkc_draw makes it with the runs): read in order, long words where a run has four or more
	xdef	_pkcb68k
	xdef	pkcb68k
_pkcb68k:
pkcb68k:
	movem.l	d2-d3/a2,-(sp)
	movem.l	12+4(sp),d2/a1			; to, bytes
	move.l	12+12(sp),a2			; run
	move.l	12+16(sp),d3			; n
	bra.s	pb_n
pb_r:	addq.l	#4,a2				; (the picture's offset: not needed)
	move.l	(a2)+,a0
	adda.l	d2,a0				; at
	move.l	(a2)+,d1			; length
	move.l	d1,d0
	lsr.l	#2,d0
	beq.s	pb_b
	subq.l	#1,d0
pb_l:	move.l	(a1)+,(a0)+
	dbra	d0,pb_l
	and.l	#3,d1
pb_b:	subq.l	#1,d1
	bmi.s	pb_n
pb_c:	move.b	(a1)+,(a0)+
	dbra	d1,pb_c
pb_n:	subq.l	#1,d3
	bpl.s	pb_r
	movem.l	(sp)+,d2-d3/a2
	rts

; ---------------------------------------------------------------------------------------------------------------
; void blk68k(const bl_ctx *c, int x, int y, const uint8_t *src, int spitch, int w, int h, int add): main.c
; hud_block -- a block of pixels (0 see-through) cut to the clip and put by the blit
	xdef	_blk68k
	xdef	blk68k
_blk68k:
blk68k:
	movem.l	d2-d7/a2-a3,-(sp)
	lea	-28(sp),sp			; a hud_blit
	lea	28+32+4(sp),a0
	move.l	(a0)+,a3			; c: 0 clip[4], 16 fb, 20 fbw, 24 blit
	move.l	(a0)+,d1			; x
	move.l	(a0)+,d7			; y
	move.l	(a0)+,a1			; src
	move.l	(a0)+,d2			; spitch
	move.l	(a0)+,d4			; c1 = w
	move.l	(a0)+,a2			; r1 = h
	move.l	(a0),d5				; add
	moveq	#0,d3				; c0
	moveq	#0,d6				; r0
	move.l	(a3),d0
	sub.l	d1,d0
	ble.s	bk_1
	move.l	d0,d3
bk_1:	move.l	4(a3),d0
	sub.l	d1,d0
	cmp.l	d4,d0
	bge.s	bk_2
	move.l	d0,d4
bk_2:	move.l	8(a3),d0
	sub.l	d7,d0
	ble.s	bk_3
	move.l	d0,d6
bk_3:	move.l	12(a3),d0
	sub.l	d7,d0
	cmp.l	a2,d0
	bge.s	bk_4
	move.l	d0,a2
bk_4:	cmp.l	d4,d3
	bge.s	bk_x
	cmp.l	a2,d6
	bge.s	bk_x
	move.l	d7,d0				; dst = fb + (y + r0) fbw + x + c0
	add.l	d6,d0
	muls.l	20(a3),d0
	add.l	d1,d0
	add.l	d3,d0
	add.l	16(a3),d0
	move.l	d0,(sp)
	move.l	20(a3),4(sp)
	move.l	d6,d0				; src + r0 spitch + c0
	muls.l	d2,d0
	add.l	d3,d0
	add.l	a1,d0
	move.l	d0,8(sp)
	move.l	d2,12(sp)
	sub.l	d3,d4
	move.l	d4,16(sp)
	move.l	a2,d0
	sub.l	d6,d0
	move.l	d0,20(sp)
	move.l	d5,24(sp)
	move.l	sp,-(sp)
	move.l	24(a3),a0
	jsr	(a0)
	addq.l	#4,sp
bk_x:	lea	28(sp),sp
	movem.l	(sp)+,d2-d7/a2-a3
	rts

; ---------------------------------------------------------------------------------------------------------------
; void dline68k(const nd_ctx *c, int x0, int y0, int x1, int y1, int col): main.c dash_line -- point i of
; n = max(|dx|, |dy|) at x0 + dx i / n (C's division), in the wide picture only the even rows (halved), + oy, inside
; the picture.  nd_ctx: 0 fb, 4 fbw, 8 fbh, 12 yd, 16 oy, 20 gs, 24 sin, 28 cos
	xdef	_dline68k
	xdef	dline68k
_dline68k:
dline68k:
	movem.l	d2-d4/a3,-(sp)
	lea	16+4(sp),a0
	move.l	(a0)+,a3
	movem.l	(a0),d0-d4			; x0 y0 x1 y1 col
	bsr.s	dl_core
	movem.l	(sp)+,d2-d4/a3
	rts
; d0 x0, d1 y0, d2 x1, d3 y1, d4 col, a3 the context (d0-d3 changed).  Point i of n = max(|dx|, |dy|) at
; x0 + dx i / n (C's division, towards 0): as magnitudes stepped -- acc += |dx|, past n at most once a step (|dx| <= n)
; -> one on in dx's direction; no muls.l / divsl.l a point (as hud_line68k)
dl_core:
	movem.l	d4-d7/a1-a2/a4-a5,-(sp)		; ((sp): the saved d4, its low byte the colour)
	sub.l	d0,d2				; dx, dy
	sub.l	d1,d3
	move.w	#1,a4				; sx, sy
	tst.l	d2
	bpl.s	dc_1
	neg.l	d2
	subq.l	#2,a4
dc_1:	move.w	#1,a5
	tst.l	d3
	bpl.s	dc_2
	neg.l	d3
	subq.l	#2,a5
dc_2:	move.l	d2,d5				; n = max(|dx|, |dy|)
	cmp.l	d3,d5
	bge.s	dc_3
	move.l	d3,d5
dc_3:	move.l	d5,d6				; n + 1 points
	suba.l	a1,a1				; acc x, acc y
	suba.l	a2,a2
dc_l:	move.l	d1,d4
	cmp.l	#2,12(a3)			; the wide picture: the even rows, halved
	bne.s	dc_q
	btst	#0,d4
	bne.s	dc_s
	asr.l	#1,d4
dc_q:	add.l	16(a3),d4			; + oy
	tst.l	d0
	bmi.s	dc_s
	cmp.l	4(a3),d0
	bge.s	dc_s
	tst.l	d4
	bmi.s	dc_s
	cmp.l	8(a3),d4
	bge.s	dc_s
	muls.l	4(a3),d4
	add.l	d0,d4
	move.l	(a3),a0
	move.b	3(sp),(a0,d4.l)			; (the colour: the saved d4's low byte)
dc_s:	subq.l	#1,d6
	bmi.s	dc_x
	adda.l	d2,a1				; x on?
	cmpa.l	d5,a1
	blt.s	dc_y
	suba.l	d5,a1
	add.l	a4,d0
dc_y:	adda.l	d3,a2				; y on?
	cmpa.l	d5,a2
	blt.s	dc_l
	suba.l	d5,a2
	add.l	a5,d1
	bra.s	dc_l
dc_x:	movem.l	(sp)+,d4-d7/a1-a2/a4-a5
	rts

; void needle68k(const nd_ctx *c, int px, int py, int len, float angle, int colour): main.c dash_needle -- the
; needle from (px, py) at angle - 2, len long, and two lines one pixel either side of its foot to its tip
	xdef	_needle68k
	xdef	needle68k
_needle68k:
needle68k:
	movem.l	d2-d7/a3/a5,-(sp)
	fmovem.x fp2-fp5,-(sp)
	lea	48+32+4(sp),a0
	move.l	(a0)+,a3
	move.l	a3,a5				; (MSIN reads the context through a5)
	move.l	(a0)+,d5			; px
	move.l	(a0)+,d6			; py
	move.l	(a0)+,d7			; len
	fsmove.s (a0)+,fp2			; angle
	move.l	(a0),d4				; colour
	fssub.s	K_TWO(pc),fp2			; a = angle - 2
	move.l	20(a3),d0			; px py len x g_s
	muls.l	d0,d5
	muls.l	d0,d6
	muls.l	d0,d7
	fsmove.l d5,fp4				; (float)px, (float)py
	fsmove.l d6,fp5
	fsmove.x fp2,fp0			; tx = (int)(px + len sin a)
	MSIN	24
	fsmove.l d7,fp1
	fsmul.x	fp1,fp0
	fsadd.x	fp4,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d2
	fsmove.x fp2,fp0			; ty = (int)(py - len cos a)
	MSIN	28
	fsmove.l d7,fp1
	fsmul.x	fp1,fp0
	fsmove.x fp5,fp1
	fssub.x	fp0,fp1
	fintrz.x fp1,fp1
	fmove.l	fp1,d3
	move.l	d2,d7				; (tx, ty kept)
	move.l	d3,-(sp)
	move.l	d5,d0				; the needle
	move.l	d6,d1
	bsr	dl_core
	move.l	d7,d2
	move.l	(sp),d3
	fsadd.s	K_PI2B(pc),fp2			; b = a + pi/2
	fsmove.x fp2,fp0			; sin b, cos b
	MSIN	24
	fsmove.x fp0,fp3
	fsmove.x fp2,fp0
	MSIN	28
	fsmove.x fp0,fp2
	fsmove.x fp4,fp0			; ((int)(px + sin b), (int)(py - cos b)) to the tip
	fsadd.x	fp3,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d0
	fsmove.x fp5,fp0
	fssub.x	fp2,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d1
	bsr	dl_core
	move.l	d7,d2
	move.l	(sp),d3
	fsmove.x fp4,fp0			; ((int)(px - sin b), (int)(py + cos b)) to the tip
	fssub.x	fp3,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d0
	fsmove.x fp5,fp0
	fsadd.x	fp2,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d1
	bsr	dl_core
	addq.l	#4,sp
	fmovem.x (sp)+,fp2-fp5
	movem.l	(sp)+,d2-d7/a3/a5
	rts

; ---------------------------------------------------------------------------------------------------------------
; void pal68k(uint32_t *out, const uint32_t *src, uint32_t to, float to_k, float fade): main.c show_palette_c --
; each colour towards `to` by to_k (if > 0), then towards black by fade (if < 1), each channel cut to whole
	xdef	_pal68k
	xdef	pal68k
_pal68k:
pal68k:
	movem.l	d2-d5/a2,-(sp)
	fmovem.x fp2-fp5,-(sp)
	lea	48+20+4(sp),a0
	move.l	(a0)+,a1			; out
	move.l	(a0)+,a2			; src
	move.l	(a0)+,d5			; to
	fsmove.s (a0)+,fp4			; to_k
	fsmove.s (a0),fp5			; fade
	move.w	#255,d4
pl_l:	move.l	(a2)+,d0
	or.l	#$ff000000,d0
	ftst.x	fp4
	fbngt	pl_f
	moveq	#16,d2				; each channel: c + (t - c) k
	bsr.s	pl_to
	moveq	#8,d2
	bsr.s	pl_to
	moveq	#0,d2
	bsr.s	pl_to
pl_f:	fcmp.s	K_ONE(pc),fp5
	fbnlt	pl_o
	moveq	#16,d2				; each channel: c fade
	bsr.s	pl_fd
	moveq	#8,d2
	bsr.s	pl_fd
	moveq	#0,d2
	bsr.s	pl_fd
pl_o:	move.l	d0,(a1)+
	dbra	d4,pl_l
	fmovem.x (sp)+,fp2-fp5
	movem.l	(sp)+,d2-d5/a2
	rts
; channel at bit d2 of d0: (uint32)((float)c + ((float)t - (float)c) k)
pl_to:	move.l	d0,d1
	lsr.l	d2,d1
	and.l	#255,d1
	fsmove.l d1,fp2				; c
	move.l	d5,d1
	lsr.l	d2,d1
	and.l	#255,d1
	fsmove.l d1,fp3				; t
	fssub.x	fp2,fp3
	fsmul.x	fp4,fp3
	fsadd.x	fp3,fp2
	bra.s	pl_put
; channel at bit d2 of d0: (uint32)((float)c fade)
pl_fd:	move.l	d0,d1
	lsr.l	d2,d1
	and.l	#255,d1
	fsmove.l d1,fp2
	fsmul.x	fp5,fp2
pl_put:	fintrz.x fp2,fp2
	fmove.l	fp2,d1
	move.l	#255,d3				; the channel replaced
	lsl.l	d2,d3
	not.l	d3
	and.l	d3,d0
	lsl.l	d2,d1
	or.l	d1,d0
	rts

; ---------------------------------------------------------------------------------------------------------------
; void dpv68k(const dv_ctx *c, const vtx *in, int n, const material *m): main.c draw_poly_view (Screamer 1: no
; fade) -- the polygon cut at the near plane (24) and, with a far plane, at it; then pt_add_view: each corner
; projected (x = FB_W / 2 + x fx / z, y = cy - y fy / z), rounded as pt_px, u v x 65536 cut; the polygon from pt_face
; (C).  vtx: x y z u v (20 bytes).  dv_ctx: 0 far_z, 4 fbw, 8 fx, 12 fy, 16 cy, 20 face
DV_OUT	equ	0
DV_CUT	equ	200
DV_P	equ	440
DV_LOC	equ	444

; cut the polygon (a0, d0 corners) by the plane z = fp7 into (a1): d1 = 0 keep z >= it (near), 1 keep z < it
; (far); d0 = the corners kept
dv_clip:
	movem.l	d2-d4/a2-a3,-(sp)
	move.l	d0,d2				; n
	moveq	#0,d3				; k
	moveq	#0,d4				; out n
	bra	dvc_n
dvc_k:	move.l	d3,d0				; p, q
	mulu.l	#20,d0
	lea	(a0,d0.l),a2
	move.l	d3,d0
	addq.l	#1,d0
	cmp.l	d2,d0
	blt.s	dvc_k1
	moveq	#0,d0
dvc_k1:	mulu.l	#20,d0
	lea	(a0,d0.l),a3
	bsr.s	dvc_in				; pin
	move.l	d0,-(sp)
	exg	a2,a3
	bsr.s	dvc_in				; qin
	exg	a2,a3
	move.l	(sp)+,d1			; (pin)
	tst.l	d1
	beq.s	dvc_k2
	move.l	(a2),(a1)+			; keep p
	move.l	4(a2),(a1)+
	move.l	8(a2),(a1)+
	move.l	12(a2),(a1)+
	move.l	16(a2),(a1)+
	addq.l	#1,d4
dvc_k2:	cmp.l	d0,d1
	beq.s	dvc_k3
	fsmove.x fp7,fp1			; t = (plane - p.z) / (q.z - p.z)
	fssub.s	8(a2),fp1
	fsmove.s 8(a3),fp0
	fssub.s	8(a2),fp0
	fsdiv.x	fp0,fp1
	moveq	#0,d0				; x y (z the plane) u v: p + (q - p) t
	bsr.s	dvc_l
	moveq	#4,d0
	bsr.s	dvc_l
	fmove.s	fp7,(a1)+
	moveq	#12,d0
	bsr.s	dvc_l
	moveq	#16,d0
	bsr.s	dvc_l
	addq.l	#1,d4
dvc_k3:	addq.l	#1,d3
dvc_n:	cmp.l	d2,d3
	blt	dvc_k
	move.l	d4,d0
	movem.l	(sp)+,d2-d4/a2-a3
	rts
dvc_in:	fsmove.s 8(a2),fp0			; d0 = z on the kept side (d1 the side, in the caller's d1... see dv_side)
	moveq	#0,d0
	fcmp.x	fp7,fp0
	tst.l	dv_side
	bne.s	dvc_in1
	fblt	dvc_in0				; near: z >= plane
	moveq	#1,d0
dvc_in0:	rts
dvc_in1:	fbnlt	dvc_in2				; far: z < plane
	moveq	#1,d0
dvc_in2:	rts
dvc_l:	fsmove.s (a3,d0.l),fp0
	fssub.s	(a2,d0.l),fp0
	fsmul.x	fp1,fp0
	fsadd.s	(a2,d0.l),fp0
	fmove.s	fp0,(a1)+
	rts

	xdef	_dpv68k
	xdef	dpv68k
_dpv68k:
dpv68k:
	movem.l	d2-d7/a2-a5,-(sp)
	fmovem.x fp2-fp7,-(sp)
	lea	-DV_LOC(sp),sp
	lea	DV_LOC+72+40+4(sp),a0
	move.l	(a0)+,a5			; c
	move.l	(a0)+,a4			; in
	move.l	(a0)+,d0			; n
	move.l	(a0),a3				; m
	move.l	a4,a0				; the near plane
	lea	DV_OUT(sp),a1
	fsmove.s K_24(pc),fp7
	clr.l	dv_side
	bsr	dv_clip
	move.l	d0,d7				; no
	lea	DV_OUT(sp),a2
	fsmove.s (a5),fp7			; the far plane, if any, with three corners
	ftst.x	fp7
	fbngt	dv_pr
	cmp.l	#3,d7
	blt.s	dv_pr
	move.l	d7,d0
	lea	DV_OUT(sp),a0
	lea	DV_CUT(sp),a1
	move.l	#1,dv_side
	bsr	dv_clip
	move.l	d0,d7
	lea	DV_CUT(sp),a2
dv_pr:	cmp.l	#8,d7				; pt_add_view: at most 8
	ble.s	dv_p1
	moveq	#8,d7
dv_p1:	pea	DV_P(sp)			; the polygon (pt_face)
	move.l	d7,-(sp)
	move.l	a3,-(sp)
	move.l	20(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	move.l	DV_P(sp),d0
	beq	dv_x
	move.l	d0,a1
	lea	8(a1),a1			; its corners: x y u v
	fsmove.l 4(a5),fp2			; FB_W / 2
	fsmul.s	K_HALF(pc),fp2
	move.l	d7,d6
	bra.s	dv_cn
dv_c:	fsmove.s K_ONE(pc),fp3			; iz = 1 / z
	fsdiv.s	8(a2),fp3
	fsmove.s (a2),fp0			; x = FB_W/2 + x fx iz
	fsmul.s	8(a5),fp0
	fsmul.x	fp3,fp0
	fsadd.x	fp2,fp0
	bsr.s	dv_px
	move.l	d0,(a1)+
	fsmove.s 4(a2),fp0			; y = cy - y fy iz
	fsmul.s	12(a5),fp0
	fsmul.x	fp3,fp0
	fsmove.s 16(a5),fp1
	fssub.x	fp0,fp1
	fsmove.x fp1,fp0
	bsr.s	dv_px
	move.l	d0,(a1)+
	fsmove.s 12(a2),fp0			; u v x 65536, cut
	fsmul.s	K_65536(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,(a1)+
	fsmove.s 16(a2),fp0
	fsmul.s	K_65536(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,(a1)+
	lea	20(a2),a2
dv_cn:	subq.l	#1,d6
	bpl.s	dv_c
dv_x:	lea	DV_LOC(sp),sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a5
	rts
; d0 = pt_px(fp0) = (int)(f + 16384.5) - 16384
dv_px:	fsadd.s	K_16384H(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,d0
	sub.l	#16384,d0
	rts

	section	data,data
dv_side: dc.l	0
	section	code,code

; ---------------------------------------------------------------- the sound glue (main.c sound_step_c, sound_world_c)
; sd68k(const sd_ctx *x) = sound_step, sw68k(x, lx, ly, over) = sound_world; the commentary (comment, comment_hold /
; repeat / once / pick / step) inside.  The game's sound calls go through x->f (sd_fns), so that the compare mode can
; hand back C's.  a5 = the context (MSIN), a4 = the state (sd_state), a3 = the player's car.
SD_ENGINE	equ	0
SD_SKID		equ	4
SD_TURN		equ	8
SD_TIMER	equ	116
SD_QUEUE	equ	224
SD_NQ		equ	320
SD_VH		equ	324
SD_VCLK		equ	328
SD_STAGE	equ	332
SD_OVER		equ	336
SD_LEAD		equ	340
SD_TRACK0	equ	344
SD_ASND		equ	348
SD_OSND		equ	380
SD_ADIST	equ	416
SD_ODIST	equ	448
SD_EAR		equ	484
SD_YAW		equ	492
SD_CUT		equ	496
SD_DOP		equ	500
SD_EAROK	equ	504
SX_SD		equ	0
SX_PC		equ	4
SX_F		equ	8
SX_NEAR		equ	12
SX_SIN		equ	16
SX_COS		equ	20
SX_HYP		equ	24
SX_MARK		equ	28
SX_ANIM		equ	32
SX_OPP		equ	36
SX_EVS		equ	40
SX_FIN		equ	44
SX_GOVER	equ	48
SX_NMARK	equ	52
SX_MARKAT	equ	56
SX_SKID		equ	60
SX_CRASH	equ	64
SX_CLOCK	equ	68
SX_RACEON	equ	72
SX_MODE		equ	76
SX_AWON		equ	80
SX_RANK		equ	84
SX_TIMER	equ	88
SX_NPROP	equ	92
SX_PHIT		equ	96
SX_NGATE	equ	100
SX_GDONE	equ	104
SX_CLKON	equ	108
SX_NOPP		equ	112
SX_LAPPED	equ	116
SX_HITCAR	equ	120
SX_INTRO	equ	124
SX_NANIM	equ	128
SX_NOSPEECH	equ	132
SX_NOOPP	equ	136
SF_PLAY		equ	0
SF_STOP		equ	4
SF_PLAYING	equ	8
SF_PITCH	equ	12
SF_SWAP		equ	16
SF_VOL		equ	20
SF_PAN		equ	24
SF_RENDER	equ	28
SDF	macro					; a sound call (its arguments pushed)
	move.l	SX_F(a5),a0
	move.l	\1(a0),a0
	jsr	(a0)
	endm

; comment(d0 ev, d1 mode, a0 delay's bits): queued unless it is there; keeps d2-d7/a2-a6
sd_comment:
	cmp.l	#26,d0
	bhi.s	.x
	cmp.l	#8,SD_NQ(a4)
	bge.s	.x
	tst.l	SX_NOSPEECH(a5)
	bne.s	.x
	move.l	d2,-(sp)
	move.l	SD_NQ(a4),d2
	lea	SD_QUEUE(a4),a1
	bra.s	.t
.l:	cmp.l	(a1),d0
	beq.s	.y
	lea	12(a1),a1
.t:	subq.l	#1,d2
	bpl.s	.l
	move.l	d0,(a1)+
	move.l	d1,(a1)+
	move.l	a0,(a1)
	addq.l	#1,SD_NQ(a4)
.y:	move.l	(sp)+,d2
.x:	rts

; comment_hold(d0 cond, d1 ev, fp1 t) -> d0 = 1 when said; keeps d2-d7/a2-a6, fp1-fp7
sd_hold:
	lea	SD_TIMER(a4,d1.l*4),a1
	tst.l	d0
	bne.s	.c
	clr.l	(a1)
	moveq	#0,d0
	rts
.c:	fmove.s	(a1),fp0
	fblt	.no
	fsadd.s	g_dt_smooth,fp0
	fmove.s	fp0,(a1)
	fcmp.x	fp1,fp0
	fblt	.no
	move.l	d1,d0
	moveq	#3,d1
	move.l	K_07(pc),a0
	move.l	a1,-(sp)
	bsr	sd_comment
	move.l	(sp)+,a1
	move.l	#$bf800000,(a1)
	moveq	#1,d0
	rts
.no:	moveq	#0,d0
	rts

; comment_repeat(d0 cond, d1 ev, fp1 t)
sd_repeat:
	lea	SD_TIMER(a4,d1.l*4),a1
	tst.l	d0
	bne.s	.c
	clr.l	(a1)
	rts
.c:	fmove.s	(a1),fp0
	fsadd.s	g_dt_smooth,fp0
	fmove.s	fp0,(a1)
	fcmp.x	fp1,fp0
	fbnge	.x
	move.l	d1,d0
	moveq	#3,d1
	move.l	K_07(pc),a0
	move.l	a1,-(sp)
	bsr	sd_comment
	move.l	(sp)+,a1
	clr.l	(a1)
.x:	rts

; comment_once(d0 ev, d1 mode)
sd_once:
	lea	SD_TIMER(a4,d0.l*4),a1
	cmp.l	#$bf800000,(a1)
	beq.s	.x
	move.l	K_07(pc),a0
	move.l	a1,-(sp)
	bsr	sd_comment
	move.l	(sp)+,a1
	move.l	#$bf800000,(a1)
.x:	rts

; the queue's first let go (memmove of the rest, --nqueue)
sd_pop:
	subq.l	#1,SD_NQ(a4)
	move.l	SD_NQ(a4),d0
	lea	SD_QUEUE(a4),a0
	mulu.l	#3,d0
	bra.s	.t
.l:	move.l	12(a0),(a0)+
.t:	dbf	d0,.l
	rts

; sound_pan(fp0 x, fp1 y) -> fp0; keeps fp2-fp7
sd_pan:
	fmovem.x fp2-fp4,-(sp)
	fmove.x	fp0,fp2
	fssub.s	SD_EAR(a4),fp2
	fmove.x	fp1,fp4
	fssub.s	SD_EAR+4(a4),fp4
	fmove.x	fp2,fp1
	fsmul.x	fp2,fp1
	fmove.x	fp4,fp0
	fsmul.x	fp4,fp0
	fsadd.x	fp0,fp1
	fssqrt.x fp1,fp3
	fcmp.s	K_ONE(pc),fp3
	fblt	.zero
	fmove.s	SD_YAW(a4),fp0
	MSIN	SX_SIN
	fsmul.x	fp0,fp2
	fmove.s	SD_YAW(a4),fp0
	MSIN	SX_COS
	fsmul.x	fp0,fp4
	fmove.x	fp2,fp0
	fssub.x	fp4,fp0
	fsdiv.x	fp3,fp0
	ftst.x	fp0
	fblt	.neg
	fssqrt.x fp0,fp0
	bra.s	.x
.neg:	fsneg.x	fp0,fp1
	fssqrt.x fp1,fp0
	fsneg.x	fp0,fp0
	bra.s	.x
.zero:	fmove.s	K_ZERO(pc),fp0
.x:	fmovem.x (sp)+,fp2-fp4
	rts

; sound_from: a3 = &handle, a1 = &last, d3 = the sample (-1 none), fp5 x, fp6 y (scale 1); uses d6, fp2
sd_from:
	move.l	a1,d6
	fmove.x	fp5,fp2
	fssub.s	SD_EAR(a4),fp2
	fmove.x	fp6,fp0
	fssub.s	SD_EAR+4(a4),fp0
	fsmul.x	fp2,fp2
	fsmul.x	fp0,fp0
	fsadd.x	fp0,fp2
	fssqrt.x fp2,fp2
	move.l	d6,a0
	tst.l	SD_CUT(a4)
	beq.s	.c
	fmove.s	fp2,(a0)
.c:	fcmp.s	K_40000(pc),fp2
	fbge	.far
	tst.l	d3
	bmi	.far
	move.l	(a3),-(sp)
	SDF	SF_PLAYING
	addq.l	#4,sp
	tst.l	d0
	bne.s	.on
	move.l	d3,-(sp)
	SDF	SF_PLAY
	addq.l	#4,sp
	move.l	d0,(a3)
	move.l	d6,a0
	fmove.s	fp2,(a0)
.on:	fmove.s	K_40000(pc),fp0
	fssub.x	fp2,fp0
	fsdiv.s	K_40000(pc),fp0
	fsmul.x	fp0,fp0
	fmove.s	fp0,-(sp)
	move.l	(a3),-(sp)
	SDF	SF_VOL
	addq.l	#8,sp
	fmove.x	fp5,fp0
	fmove.x	fp6,fp1
	bsr	sd_pan
	fmove.s	fp0,-(sp)
	move.l	(a3),-(sp)
	SDF	SF_PAN
	addq.l	#8,sp
	move.l	d6,a0
	fmove.s	(a0),fp0
	fssub.x	fp2,fp0
	fsmul.s	SD_DOP(a4),fp0
	fsmul.s	K_NINE(pc),fp0
	fsadd.s	K_65536(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,-(sp)
	move.l	(a3),-(sp)
	SDF	SF_PITCH
	addq.l	#8,sp
	bra.s	.x
.far:	move.l	(a3),d0
	moveq	#-1,d1
	cmp.l	d1,d0
	beq.s	.x
	move.l	d0,-(sp)
	SDF	SF_STOP
	addq.l	#4,sp
	move.l	d0,(a3)
.x:	move.l	d6,a0
	fmove.s	fp2,(a0)
	rts

	xdef	_sw68k
	xdef	sw68k
_sw68k:
sw68k:
	link	a6,#-48				; -48 the cars' distances, -12 the three heard
	movem.l	d2-d7/a2-a5,-(sp)
	fmovem.x fp2-fp7,-(sp)
	move.l	8(a6),a5
	move.l	SX_SD(a5),a4
	fmove.s	12(a6),fp3			; lx
	fmove.s	16(a6),fp4			; ly
	move.l	20(a6),d5			; over
	moveq	#1,d7				; a cut: no listener before, or it jumped
	tst.l	SD_EAROK(a4)
	beq.s	.cut
	fmove.x	fp4,fp0
	fssub.s	SD_EAR+4(a4),fp0
	fmove.s	fp0,-(sp)
	fmove.x	fp3,fp1
	fssub.s	SD_EAR(a4),fp1
	fmove.s	fp1,-(sp)
	move.l	SX_HYP(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	fcmp.s	K_1000(pc),fp0
	fbgt	.cut
	moveq	#0,d7
.cut:	move.l	d7,SD_CUT(a4)
	fmove.s	fp3,SD_EAR(a4)
	fmove.s	fp4,SD_EAR+4(a4)
	move.l	#1,SD_EAROK(a4)
	; the moving scenery
	moveq	#0,d4
	move.l	SX_ANIM(a5),a2
.al:	cmp.l	SX_NANIM(a5),d4
	bge.s	.opp
	move.l	24(a2),a0
	fmove.s	24(a0),fp5
	fmove.s	28(a0),fp6
	move.l	8(a2),d3
	bmi.s	.a1
	add.l	SD_TRACK0(a4),d3
	bra.s	.a2
.a1:	moveq	#-1,d3
.a2:	lea	SD_ASND(a4,d4.l*4),a3
	lea	SD_ADIST(a4,d4.l*4),a1
	bsr	sd_from
	addq.l	#1,d4
	lea	28(a2),a2
	bra.s	.al
	; the opponents' engines: the three nearest within 35000
.opp:	moveq	#-1,d0
	move.l	d0,-12(a6)
	move.l	d0,-8(a6)
	move.l	d0,-4(a6)
	moveq	#0,d2
	move.l	SX_OPP(a5),a2
.ol:	cmp.l	SX_NOPP(a5),d2
	bge	.o2
	fmove.s	100(a2),fp0
	fssub.x	fp4,fp0
	fmove.s	fp0,-(sp)
	fmove.s	96(a2),fp1
	fssub.x	fp3,fp1
	fmove.s	fp1,-(sp)
	move.l	SX_HYP(a5),a0
	jsr	(a0)
	addq.l	#8,sp
	fmove.s	fp0,-48(a6,d2.l*4)
	fmove.s	-48(a6,d2.l*4),fp2
	tst.l	d5
	bne.s	.on
	fcmp.s	K_35000(pc),fp2
	fbge	.on
	tst.l	SX_NOOPP(a5)
	bne.s	.on
	lea	-12(a6),a0
	moveq	#0,d0
.ij:	move.l	(a0,d0.l*4),d1
	bmi.s	.ins
	fcmp.s	-48(a6,d1.l*4),fp2
	fblt	.ins
	addq.l	#1,d0
	cmp.l	#3,d0
	blt.s	.ij
	bra.s	.on
.ins:	moveq	#2,d1
.sh:	cmp.l	d0,d1
	ble.s	.put
	move.l	-4(a0,d1.l*4),(a0,d1.l*4)
	subq.l	#1,d1
	bra.s	.sh
.put:	move.l	d2,(a0,d0.l*4)
.on:	addq.l	#1,d2
	lea	208(a2),a2
	bra	.ol
.o2:	moveq	#0,d2
	move.l	SX_OPP(a5),a2
.pl:	cmp.l	SX_NOPP(a5),d2
	bge	.done
	lea	SD_OSND(a4,d2.l*4),a3
	cmp.l	-12(a6),d2
	beq.s	.heard
	cmp.l	-8(a6),d2
	beq.s	.heard
	cmp.l	-4(a6),d2
	beq.s	.heard
	move.l	(a3),d0
	moveq	#-1,d1
	cmp.l	d1,d0
	beq.s	.nh
	move.l	d0,-(sp)
	SDF	SF_STOP
	addq.l	#4,sp
	move.l	d0,(a3)
.nh:	move.l	-48(a6,d2.l*4),SD_ODIST(a4,d2.l*4)
	bra	.next
.heard:	move.l	(a3),-(sp)
	SDF	SF_PLAYING
	addq.l	#4,sp
	tst.l	d0
	bne.s	.h1
	pea	2.w
	SDF	SF_PLAY
	addq.l	#4,sp
	move.l	d0,(a3)
	move.l	-48(a6,d2.l*4),SD_ODIST(a4,d2.l*4)
.h1:	tst.l	SD_CUT(a4)
	beq.s	.h2
	move.l	-48(a6,d2.l*4),SD_ODIST(a4,d2.l*4)
.h2:	fmove.s	-48(a6,d2.l*4),fp2
	fmove.s	K_35000(pc),fp0
	fssub.x	fp2,fp0
	fsdiv.s	K_35000(pc),fp0
	fsmul.x	fp0,fp0
	fsmul.s	K_VOPP(pc),fp0
	fmove.s	fp0,-(sp)
	move.l	(a3),-(sp)
	SDF	SF_VOL
	addq.l	#8,sp
	fmove.s	96(a2),fp0
	fmove.s	100(a2),fp1
	bsr	sd_pan
	fmove.s	fp0,-(sp)
	move.l	(a3),-(sp)
	SDF	SF_PAN
	addq.l	#8,sp
	move.l	SX_RACEON(a5),d0
	or.l	SX_INTRO(a5),d0
	beq.s	.grid
	fmove.s	12(a2),fp1
	bra.s	.note
.grid:	fmove.s	K_HALF(pc),fp0			; on the grid: sin(k x 0.5 x clock) x 15000
	fsmul.l	d2,fp0
	fsmul.s	SX_CLOCK(a5),fp0
	MSIN	SX_SIN
	fmove.x	fp0,fp1
	fsmul.s	K_15000(pc),fp1
.note:	fmove.s	SD_ODIST(a4,d2.l*4),fp0
	fssub.x	fp2,fp0
	fsmul.s	K_NINE(pc),fp0
	fsmul.s	SD_DOP(a4),fp0
	fsmul.s	K_2P4(pc),fp1
	fsadd.s	K_13568(pc),fp1
	fsadd.x	fp1,fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,-(sp)
	move.l	(a3),-(sp)
	SDF	SF_PITCH
	addq.l	#8,sp
	move.l	-48(a6,d2.l*4),SD_ODIST(a4,d2.l*4)
.next:	addq.l	#1,d2
	lea	208(a2),a2
	bra	.pl
.done:	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a5
	unlk	a6
	rts

	xdef	_sd68k
	xdef	sd68k
_sd68k:
sd68k:
	link	a6,#-4				; -4 the road's angle
	movem.l	d2-d7/a2-a5,-(sp)
	fmovem.x fp2-fp7,-(sp)
	move.l	8(a6),a5
	move.l	SX_SD(a5),a4
	move.l	SX_PC(a5),a3
	moveq	#0,d3				; over
	move.l	SX_FIN(a5),d0
	or.l	SX_GOVER(a5),d0
	beq	.run
	moveq	#1,d3
	tst.l	SD_OVER(a4)
	bne	.cstep
	move.l	#1,SD_OVER(a4)			; the end: the engine and the skid stopped, the result said
	move.l	SD_ENGINE(a4),-(sp)
	SDF	SF_STOP
	addq.l	#4,sp
	move.l	d0,SD_ENGINE(a4)
	move.l	SD_SKID(a4),-(sp)
	SDF	SF_STOP
	addq.l	#4,sp
	move.l	d0,SD_SKID(a4)
	clr.l	SD_NQ(a4)
	moveq	#25,d0
	tst.l	SX_GOVER(a5)
	bne.s	.osay
	cmp.l	#4,SX_MODE(a5)
	bne.s	.o2
	moveq	#12,d0
	tst.l	SX_AWON(a5)
	beq.s	.osay
	moveq	#11,d0
	bra.s	.osay
.o2:	moveq	#12,d0
	cmp.l	#1,SX_RANK(a5)
	bne.s	.osay
	moveq	#11,d0
.osay:	moveq	#3,d1
	sub.l	a0,a0
	bsr	sd_comment
	bra	.cstep
.run:	moveq	#3,d0				; the engine: in a tunnel the other sample
	tst.l	SX_NMARK(a5)
	beq.s	.k
	move.l	SX_MARKAT(a5),d1
	mulu.l	#28,d1
	move.l	SX_MARK(a5),a0
	cmp.l	#1,20(a0,d1.l)
	bne.s	.k
	moveq	#7,d0
.k:	move.l	d0,-(sp)
	move.l	SD_ENGINE(a4),-(sp)
	SDF	SF_SWAP
	addq.l	#8,sp
	fmove.s	96(a3),fp0
	fsmul.s	K_FOURTEEN(pc),fp0
	fsadd.s	K_32768(pc),fp0
	fintrz.x fp0,fp0
	fmove.l	fp0,-(sp)
	move.l	SD_ENGINE(a4),-(sp)
	SDF	SF_PITCH
	addq.l	#8,sp
	tst.l	SX_SKID(a5)
	beq.s	.ns
	tst.l	SX_CRASH(a5)
	bne.s	.ns
	move.l	SD_SKID(a4),-(sp)
	SDF	SF_PLAYING
	addq.l	#4,sp
	tst.l	d0
	bne.s	.stg
	clr.l	-(sp)
	SDF	SF_PLAY
	addq.l	#4,sp
	move.l	d0,SD_SKID(a4)
	bra.s	.stg
.ns:	move.l	SD_SKID(a4),d0
	moveq	#-1,d1
	cmp.l	d1,d0
	beq.s	.stg
	move.l	d0,-(sp)
	SDF	SF_STOP
	addq.l	#4,sp
	move.l	d0,SD_SKID(a4)
.stg:	fintrz.s SX_CLOCK(a5),fp0		; the countdown: one event a state of the lights
	fmove.l	fp0,d1
	move.l	d1,d0
	bpl.s	.s1
	addq.l	#1,d0
.s1:	asr.l	#1,d0
	cmp.l	SD_STAGE(a4),d0
	beq.s	.race
	moveq	#7,d2
	cmp.l	d1,d2
	blt.s	.race
	move.l	d0,SD_STAGE(a4)
	moveq	#0,d1
	sub.l	a0,a0
	bsr	sd_comment
.race:	tst.l	SX_RACEON(a5)
	beq	.cstep
	; what the commentator notices (0x2425c)
	pea	-4(a6)
	move.l	72(a3),-(sp)
	move.l	68(a3),-(sp)
	move.l	SX_NEAR(a5),a0
	jsr	(a0)
	lea	12(sp),sp
	fmove.s	K_THREE(pc),fp2
	tst.l	d0
	beq.s	.w3
	fmove.s	-4(a6),fp1
	fsadd.s	K_PI(pc),fp1
	fmove.s	80(a3),fp2
	fssub.x	fp1,fp2
.w1:	fcmp.s	K_PI(pc),fp2
	fbngt	.w2
	fssub.s	K_2PI(pc),fp2
	bra.s	.w1
.w2:	fcmp.s	K_MPI(pc),fp2
	fbnlt	.w4
	fsadd.s	K_2PI(pc),fp2
	bra.s	.w2
.w4:	fsabs.x	fp2,fp2
.w3:	moveq	#0,d4				; the wrong way
	fcmp.s	K_PI4(pc),fp2
	fbnlt	.ww
	moveq	#1,d4
.ww:	move.l	d4,d0
	moveq	#16,d1
	fmove.s	K_FIVE(pc),fp1
	bsr	sd_repeat
	moveq	#0,d0				; standing
	fmove.s	92(a3),fp0
	fcmp.s	K_1000(pc),fp0
	fbnlt	.sp
	moveq	#1,d0
.sp:	moveq	#17,d1
	fmove.s	K_EIGHT(pc),fp1
	bsr	sd_repeat
	move.l	SX_MODE(a5),d0			; hurry
	cmp.l	#1,d0
	beq.s	.m14
	cmp.l	#4,d0
	bne.s	.m14x
.m14:	fmove.s	SX_TIMER(a5),fp0
	fcmp.s	K_FIVE(pc),fp0
	fbnle	.m14x
	moveq	#22,d0
	moveq	#3,d1
	bsr	sd_once
.m14x:	cmp.l	#1,SX_MODE(a5)			; in the lead
	bne.s	.l1
	moveq	#0,d0
	cmp.l	#1,SX_RANK(a5)
	bne.s	.r1
	moveq	#1,d0
.r1:	moveq	#21,d1
	fmove.s	K_FIVE(pc),fp1
	bsr	sd_hold
	tst.l	d0
	beq.s	.l1
	move.l	#1,SD_LEAD(a4)
.l1:	moveq	#0,d0				; the lead lost
	tst.l	SD_LEAD(a4)
	beq.s	.l2
	cmp.l	#2,SX_RANK(a5)
	blt.s	.l2
	moveq	#1,d0
.l2:	moveq	#24,d1
	fmove.s	K_FIVE(pc),fp1
	bsr	sd_hold
	tst.l	d0
	beq.s	.l3
	clr.l	SD_LEAD(a4)
.l3:	cmp.l	#32,SX_MODE(a5)			; cones: all of them
	bne.s	.c1
	move.l	SX_NPROP(a5),d0
	cmp.l	SX_PHIT(a5),d0
	bne.s	.c1
	moveq	#26,d0
	moveq	#3,d1
	bsr	sd_once
.c1:	cmp.l	#64,SX_MODE(a5)			; slalom: every gate, nothing hit
	bne.s	.c2
	move.l	SX_NGATE(a5),d0
	cmp.l	SX_GDONE(a5),d0
	bne.s	.c2
	tst.l	SX_PHIT(a5)
	bne.s	.c2
	moveq	#26,d0
	moveq	#3,d1
	bsr	sd_once
.c2:	cmp.l	#32,SX_MODE(a5)			; cones: the clock on
	bne.s	.c3
	tst.l	SX_CLKON(a5)
	beq.s	.c3
	moveq	#19,d0
	moveq	#3,d1
	bsr	sd_once
.c3:	tst.l	d4				; a bend
	bne.s	.b1
	moveq	#0,d0
	tst.l	SX_NMARK(a5)
	beq.s	.b0
	move.l	SX_MARKAT(a5),d1
	mulu.l	#28,d1
	move.l	SX_MARK(a5),a0
	btst	#2,27(a0,d1.l)
	beq.s	.b0
	moveq	#1,d0
.b0:	moveq	#20,d1
	fmove.s	K_ZERO(pc),fp1
	bsr	sd_hold
.b1:	fintrz.s 148(a3),fp0			; a skid
	fmove.l	fp0,d0
	fmove.s	24(a3),fp1
	fsmul.s	K_29(pc),fp1
	moveq	#10,d1
	bsr	sd_hold
	move.l	SX_NOPP(a5),d1			; last
	moveq	#2,d0
	cmp.l	d0,d1
	bge.s	.n2
	move.l	d0,d1
.n2:	moveq	#0,d0
	cmp.l	SX_RANK(a5),d1
	bge.s	.n3
	moveq	#1,d0
.n3:	moveq	#13,d1
	fmove.s	K_EIGHT(pc),fp1
	bsr	sd_hold
	cmp.l	#1,SX_MODE(a5)			; lapped one
	bne.s	.lp
	move.l	SX_LAPPED(a5),d0
	moveq	#23,d1
	fmove.s	K_TWO(pc),fp1
	bsr	sd_hold
.lp:	moveq	#0,d0				; touching a car
	fmove.s	SX_HITCAR(a5),fp0
	fcmp.s	K_08(pc),fp0
	fbngt	.hc
	moveq	#1,d0
.hc:	moveq	#15,d1
	fmove.s	K_ZERO(pc),fp1
	bsr	sd_repeat
	; the commentator's voice (0x24820)
.cstep:	move.l	SD_VH(a4),d0
	moveq	#-1,d1
	cmp.l	d1,d0
	beq.s	.cs1
	move.l	d0,-(sp)
	SDF	SF_PLAYING
	addq.l	#4,sp
	tst.l	d0
	bne	.world
	move.l	#-1,SD_VH(a4)
	tst.l	SD_NQ(a4)
	beq.s	.cs0
	bsr	sd_pop
.cs0:	clr.l	SD_VCLK(a4)
	bra	.world
.cs1:	fmove.s	SD_VCLK(a4),fp1
	fsadd.s	g_dt_smooth,fp1
	fmove.s	fp1,SD_VCLK(a4)
	move.l	SD_NQ(a4),d2
	beq	.world
	lea	SD_QUEUE(a4),a2
	moveq	#0,d1				; the shortest delay first
	moveq	#1,d0
.f:	cmp.l	d2,d0
	bge.s	.fd
	move.l	d1,d5
	mulu.l	#12,d5
	fmove.s	8(a2,d5.l),fp0
	move.l	d0,d6
	mulu.l	#12,d6
	fcmp.s	8(a2,d6.l),fp0
	fbngt	.fn
	move.l	d0,d1
.fn:	addq.l	#1,d0
	bra.s	.f
.fd:	tst.l	d1
	beq.s	.sw0
	mulu.l	#12,d1
	lea	(a2,d1.l),a0
	move.l	(a0),d0
	move.l	(a2),(a0)
	move.l	d0,(a2)
	move.l	4(a0),d0
	move.l	4(a2),4(a0)
	move.l	d0,4(a2)
	move.l	8(a0),d0
	move.l	8(a2),8(a0)
	move.l	d0,8(a2)
.sw0:	fcmp.s	8(a2),fp1
	fblt	.world
	move.l	(a2),d4				; its recording (0x24a24)
	move.l	4(a2),d0
	move.l	SX_EVS(a5),a1
	move.l	d4,d5
	mulu.l	#12,d5
	add.l	d5,a1
	cmp.l	#2,d0
	bhi.s	.turn
	move.l	(a1,d0.l*4),d2
	bra.s	.pk
.turn:	lea	SD_TURN(a4),a0
	move.l	(a0,d4.l*4),d0
	moveq	#2,d6
.t1:	addq.l	#1,d0
	divsl.l	#3,d1:d0
	move.l	d1,d0
	move.l	(a1,d0.l*4),d2
	bpl.s	.t2
	dbf	d6,.t1
.t2:	move.l	d0,(a0,d4.l*4)
.pk:	move.l	d2,-(sp)
	SDF	SF_PLAY
	addq.l	#4,sp
	move.l	d0,SD_VH(a4)
	moveq	#-1,d1
	cmp.l	d1,d0
	bne.s	.world
	bsr	sd_pop				; nothing to say for it: dropped
	clr.l	SD_VCLK(a4)
.world:	move.l	80(a3),SD_YAW(a4)		; heard from the player's car
	move.l	d3,-(sp)
	move.l	72(a3),-(sp)
	move.l	68(a3),-(sp)
	move.l	a5,-(sp)
	bsr	sw68k
	lea	16(sp),sp
	move.l	g_dt_smooth,-(sp)
	SDF	SF_RENDER
	addq.l	#4,sp
	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a5
	unlk	a6
	rts

; ---------------------------------------------------------------- the surface under a point (main.c surface_pick_c)
; int sp68k(const sp_ctx *x, float px, float py, float ref, int below, float *out): of the track's floor faces
; (|normal y| >= 0.5) under (px, py), the one nearest ref (below = 0) or the highest not above it (below = 1);
; g_pick_mat / g_pick_obj as the C sets them.  The corners as place() / tilt() put them (the sines worked out once
; an object, the C's kept ones give the same numbers).
SPX_OBJ		equ	0
SPX_N		equ	4
SPX_SIN		equ	8
SPX_COS		equ	12
SPX_MAT		equ	16
SPX_OBJI	equ	20
; frame: -48 the corners p[4][3], -52 c, -56 s, -60 cp, -64 sp, -68 cr, -72 sr, -76 best, -80 found, -84 nz
	xdef	_sp68k
	xdef	sp68k
_sp68k:
sp68k:
	link	a6,#-84
	movem.l	d2-d7/a2-a5,-(sp)
	fmovem.x fp2-fp7,-(sp)
	move.l	8(a6),a5
	fmove.s	12(a6),fp6			; x
	fmove.s	16(a6),fp7			; y
	clr.l	-80(a6)
	clr.l	-76(a6)
	moveq	#0,d5
	move.l	SPX_OBJ(a5),a2
.ol:	cmp.l	SPX_N(a5),d5
	bge	.end
	move.l	(a2),d0
	beq	.on
	move.l	d0,a3
	fmove.s	24(a2),fp0			; within its radius
	fssub.x	fp6,fp0
	fmove.s	28(a2),fp1
	fssub.x	fp7,fp1
	fsmul.x	fp0,fp0
	fsmul.x	fp1,fp1
	fsadd.x	fp1,fp0
	fmove.s	48(a2),fp1
	fsmul.x	fp1,fp1
	fcmp.x	fp1,fp0
	fbgt	.on
	fmove.s	36(a2),fp0
	MSIN	SPX_COS
	fmove.s	fp0,-52(a6)
	fmove.s	36(a2),fp0
	MSIN	SPX_SIN
	fmove.s	fp0,-56(a6)
	fmove.s	40(a2),fp0
	fbeq	.np
	MSIN	SPX_COS
	fmove.s	fp0,-60(a6)
	fmove.s	40(a2),fp0
	MSIN	SPX_SIN
	fmove.s	fp0,-64(a6)
.np:	fmove.s	44(a2),fp0
	fbeq	.nr
	MSIN	SPX_COS
	fmove.s	fp0,-68(a6)
	fmove.s	44(a2),fp0
	MSIN	SPX_SIN
	fmove.s	fp0,-72(a6)
.nr:	moveq	#0,d2				; the faces
.fl:	cmp.l	82(a3),d2
	bge	.on
	move.l	12(a3),a0			; a floor
	move.l	d2,d0
	mulu.l	#12,d0
	fsabs.s	4(a0,d0.l),fp0
	fcmp.s	K_HALF(pc),fp0
	fblt	.fn
	move.l	4(a3),a0
	moveq	#0,d4
	move.b	(a0,d2.l),d4			; nc
	beq	.plane				; (none: the corners as they were, as the C)
	lea	-48(a6),a4			; its corners
	moveq	#0,d3
.cl:	move.l	8(a3),a0
	move.l	d2,d0
	lsl.l	#4,d0
	add.l	d0,a0
	move.l	(a0,d3.l*4),d0
	bmi	.fn
	mulu.l	#12,d0
	move.l	(a3),a1
	add.l	d0,a1
	bsr	sp_place
	lea	12(a4),a4
	addq.l	#1,d3
	cmp.l	d4,d3
	blt.s	.cl
	moveq	#0,d3				; inside it, seen from above
	moveq	#0,d6
	moveq	#0,d7
	lea	-48(a6),a4
.il:	move.l	d3,d0
	addq.l	#1,d0
	divsl.l	d4,d1:d0
	mulu.l	#12,d1
	lea	-48(a6,d1.l),a0
	fmove.s	(a0),fp0
	fssub.s	(a4),fp0
	fmove.x	fp7,fp1
	fssub.s	4(a4),fp1
	fsmul.x	fp1,fp0
	fmove.s	4(a0),fp1
	fssub.s	4(a4),fp1
	fmove.x	fp6,fp3
	fssub.s	(a4),fp3
	fsmul.x	fp3,fp1
	fssub.x	fp1,fp0
	ftst.x	fp0
	fbngt	.i1
	addq.l	#1,d6
	bra.s	.i2
.i1:	fbnlt	.i2
	addq.l	#1,d7
.i2:	lea	12(a4),a4
	addq.l	#1,d3
	cmp.l	d4,d3
	blt.s	.il
	tst.l	d6
	beq.s	.plane
	tst.l	d7
	bne	.fn
.plane:	fmove.s	-36(a6),fp2			; the height on the plane through the first three corners
	fssub.s	-48(a6),fp2			; ux
	fmove.s	-32(a6),fp3
	fssub.s	-44(a6),fp3			; uy
	fmove.s	-24(a6),fp4
	fssub.s	-48(a6),fp4			; vx
	fmove.s	-20(a6),fp5
	fssub.s	-44(a6),fp5			; vy
	fmove.x	fp2,fp0
	fsmul.x	fp5,fp0
	fmove.x	fp3,fp1
	fsmul.x	fp4,fp1
	fssub.x	fp1,fp0				; nz
	fsabs.x	fp0,fp1
	fcmp.s	K_EM3(pc),fp1
	fblt	.fn
	fmove.s	fp0,-84(a6)
	fmove.s	-28(a6),fp0
	fssub.s	-40(a6),fp0			; uz
	fmove.s	-16(a6),fp1
	fssub.s	-40(a6),fp1			; vz
	fsmul.x	fp1,fp3				; uy vz
	fsmul.x	fp0,fp5				; uz vy
	fssub.x	fp5,fp3				; nx
	fsmul.x	fp4,fp0				; uz vx
	fsmul.x	fp1,fp2				; ux vz
	fssub.x	fp2,fp0				; ny
	fmove.x	fp6,fp1
	fssub.s	-48(a6),fp1
	fsmul.x	fp1,fp3
	fmove.x	fp7,fp1
	fssub.s	-44(a6),fp1
	fsmul.x	fp1,fp0
	fsadd.x	fp0,fp3
	fsdiv.s	-84(a6),fp3
	fmove.s	-40(a6),fp0
	fssub.x	fp3,fp0				; z
	tst.l	24(a6)
	beq.s	.near
	fcmp.s	20(a6),fp0			; below: the highest not above ref
	fbgt	.fn
	tst.l	-80(a6)
	beq.s	.take
	fcmp.s	-76(a6),fp0
	fbngt	.fn
	bra.s	.take
.near:	tst.l	-80(a6)				; the nearest to ref
	beq.s	.take
	fmove.x	fp0,fp1
	fssub.s	20(a6),fp1
	fsabs.x	fp1,fp1
	fmove.s	-76(a6),fp2
	fssub.s	20(a6),fp2
	fsabs.x	fp2,fp2
	fcmp.x	fp2,fp1
	fbnlt	.fn
.take:	fmove.s	fp0,-76(a6)
	move.l	#1,-80(a6)
	move.l	16(a3),a0
	move.l	(a0,d2.l*4),d0
	bpl.s	.t1
	add.l	#15,d0
.t1:	asr.l	#4,d0
	move.l	SPX_MAT(a5),a0
	move.l	d0,(a0)
	move.l	SPX_OBJI(a5),a0
	move.l	d5,(a0)
.fn:	addq.l	#1,d2
	bra	.fl
.on:	addq.l	#1,d5
	lea	76(a2),a2
	bra	.ol
.end:	move.l	-80(a6),d0
	beq.s	.x
	move.l	28(a6),a0
	move.l	-76(a6),(a0)
.x:	fmovem.x (sp)+,fp2-fp7
	movem.l	(sp)+,d2-d7/a2-a5
	unlk	a6
	rts

; a corner as place() puts it: a1 the model's corner, a2 the object, a4 where; the sines in the frame above
sp_place:
	fmove.s	(a1),fp5			; x
	fmove.s	4(a1),fp2			; y
	fmove.s	8(a1),fp3			; z
	fmove.s	40(a2),fp0			; pitch
	fbeq	.r
	fmove.s	-60(a6),fp4
	fsmul.x	fp2,fp4
	fmove.x	fp3,fp1
	fsmul.s	-64(a6),fp1
	fsmul.s	-60(a6),fp3
	fsmul.s	-64(a6),fp2
	fssub.x	fp2,fp3
	fmove.x	fp4,fp2
	fsadd.x	fp1,fp2
.r:	fmove.s	44(a2),fp0			; roll
	fbeq	.p
	fmove.s	-68(a6),fp4
	fsmul.x	fp5,fp4
	fmove.x	fp2,fp1
	fsmul.s	-72(a6),fp1
	fsmul.s	-68(a6),fp2
	fsmul.s	-72(a6),fp5
	fsadd.x	fp5,fp2
	fmove.x	fp4,fp5
	fssub.x	fp1,fp5
.p:	fmove.x	fp5,fp0
	fsmul.s	-52(a6),fp0
	fsadd.s	24(a2),fp0
	fmove.x	fp3,fp1
	fsmul.s	-56(a6),fp1
	fssub.x	fp1,fp0
	fmove.s	fp0,(a4)
	fmove.x	fp5,fp0
	fsmul.s	-56(a6),fp0
	fsadd.s	28(a2),fp0
	fmove.x	fp3,fp1
	fsmul.s	-52(a6),fp1
	fsadd.x	fp1,fp0
	fmove.s	fp0,4(a4)
	fmove.s	32(a2),fp0
	fsadd.x	fp2,fp0
	fmove.s	fp0,8(a4)
	rts

	cnop	0,4
K_ZERO:	dc.l	$00000000
K_ONE:	dc.l	$3f800000
K_HALF:	dc.l	$3f000000
K_DT:	dc.l	$3ca3d70a			; 0.02f (DRIVE_DT)
K_002:	dc.l	$3ca3d70a			; 0.02f
K_TWO:	dc.l	$40000000
K_MTWO:	dc.l	$c0000000
K_5030:	dc.l	$3f800000			; PER_FRAME_K: 1 (AMIGA: a step is a picture; elsewhere 50 / 30)
K_PI:	dc.l	$40490fdb			; (float)M_PI
K_MPI:	dc.l	$c0490fdb
K_2PI:	dc.l	$40c90fdb
K_THREE: dc.l	$40400000
K_TEN:	dc.l	$41200000
K_3000:	dc.l	$453b8000
K_4000:	dc.l	$457a0000
K_5000:	dc.l	$459c4000
K_120:	dc.l	$42f00000			; 6000.0f * DRIVE_DT
K_04:	dc.l	$3ecccccd
K_06:	dc.l	$3f19999a
K_M1:	dc.l	$bf800000
K_12:	dc.l	$41400000
K_24:	dc.l	$41c00000
K_4PI:	dc.l	$41490fdb			; 12.566371f
K_005:	dc.l	$3d4ccccd			; 0.05f
K_1117:	dc.l	$3f8ef9db			; 1.117f
K_M1117: dc.l	$bf8ef9db
K_226:	dc.l	$43620000			; 226.0f
K_QTR:	dc.l	$3e800000			; 0.25f
K_250:	dc.l	$437a0000
K_150:	dc.l	$43160000
K_1500:	dc.l	$44bb8000
K_600:	dc.l	$44160000
K_30:	dc.l	$41f00000
K_DT500: dc.l	$41200000			; dt 500
K_DT1000: dc.l	$41a00000			; dt 1000
K_THR:	dc.l	$3e48320d			; 200.0f / 1023.0f
K_PI2A:	dc.l	$3fc90fda			; 1.5707963f
K_PI2B:	dc.l	$3fc90fdb			; 1.5707964f
K_SM1:	dc.l	$3e97e9d9			; 0.296706f
K_SM2:	dc.l	$3c8efa39			; 0.0174533f
K_1EM5:	dc.l	$3727c5ac
K_0008:	dc.l	$3a51b717
K_1EM4:	dc.l	$38d1b717
K_15EM5: dc.l	$391d4952
K_SLIPM: dc.l	$3fc50a67			; 1.53938f
K_02:	dc.l	$3e4ccccd
K_01:	dc.l	$3dcccccd
K_512:	dc.l	$3f002008			; 512.0f / 1023.0f
K_1EM3:	dc.l	$3a83126f
K_09:	dc.l	$3f666666
K_FIVE:	dc.l	$40a00000
K_6000:	dc.l	$45bb8000
K_2000:	dc.l	$44fa0000
K_0002:	dc.l	$3b03126f			; 0.002f
K_003:	dc.l	$3cf5c28f			; 0.03f
K_256:	dc.l	$43800000
K_1086:	dc.l	$42d93333			; 108.6f
K_15:	dc.l	$3fc00000			; 1.5f
K_00175: dc.l	$3ae56042			; 0.00175f
K_15EM9: dc.l	$30ce288f			; 1.5e-9f
K_LEAN:	dc.l	$42140000			; 37.0f (main.c LEAN_FPS)
K_FRAME: dc.l	$3d088889			; 1.0f / 30.0f
K_452:	dc.l	$43e20000
K_935:	dc.l	$4469c000
K_FOUR:	dc.l	$40800000
K_FRAMES: dc.l	$3f800000			; FRAMES_PER_STEP: 1 (AMIGA: a step is a picture)
K_40:	dc.l	$42200000			; dt 2000
K_14:	dc.l	$3fb33333			; 1.4f
K_0008B: dc.l	$3c03126f			; 0.008f
K_00015: dc.l	$3ac49ba6			; 0.0015f
K_03:	dc.l	$3e99999a
K_08:	dc.l	$3f4ccccd
K_50:	dc.l	$42480000
K_M20000: dc.l	$c69c4000
K_100:	dc.l	$42c80000
K_52000: dc.l	$474b2000
K_1E30:	dc.l	$7149f2ca			; 1e30f
K_36E6:	dc.l	$4c095440			; 6000.0f * 6000.0f
K_99995: dc.l	$3f7ffcb9			; 0.99995f
K_200:	dc.l	$43480000
K_WS:	dc.l	$4082b0b5			; 4.0840706f
K_FULLC: dc.l	$406738a2			; 3.6128317f
K_023:	dc.l	$3e6b851f
K_65535: dc.l	$477fff00
K_M1E6:	dc.l	$c9742400			; -1.0e6f
K_8000:	dc.l	$45fa0000
K_15F:	dc.l	$41700000			; 15.0f
K_015:	dc.l	$3e19999a
K_16383: dc.l	$38800200			; 1.0f / 16383.0f
K_075:	dc.l	$3f400000
K_021:	dc.l	$3e570a3d			; 0.21f
K_2EM4:	dc.l	$3951b717			; 0.0002f
K_07:	dc.l	$3f333333			; 0.7f
K_1024PI: dc.l	$43a2f983			; 1024.0f / (float)M_PI
K_2047:	dc.l	$44ffe000
K_22:	dc.l	$41b00000
K_65536: dc.l	$47800000
K_32768: dc.l	$47000000
K_70000: dc.l	$4788b800
K_39:	dc.l	$421c0000
K_159:	dc.l	$431f0000
K_16384H: dc.l	$46800100			; 16384.5f
K_PULL:	dc.l	$00000000,$40a00000,$40600000,$40000000,$3f733333,$3f47ae14,$3f3851ec,$00000000
K_PI4:	dc.l	$3f490fdb			; pi / 4
K_FOURTEEN: dc.l	$41600000
K_1000:	dc.l	$447a0000
K_SEVEN: dc.l	$40e00000
K_EIGHT: dc.l	$41000000
K_29:	dc.l	$4039999a			; 2.9f
K_40000: dc.l	$471c4000
K_35000: dc.l	$4708b800
K_VOPP:	dc.l	$3f380170			; 23552 / 32767
K_NINE:	dc.l	$41100000
K_2P4:	dc.l	$4019999a			; 2.4f
K_13568: dc.l	$46540000
K_15000: dc.l	$466a6000
K_EM3:	dc.l	$3a83126f			; 1e-3f

; THE STEP'S TIME (drive.h, OS_ORIG_TICK: the original's, one step a picture; drive.c drive_timing writes them):
; g_dt_smooth every integration, g_dt_raw the clocks.  Here, so that the vasm reads them by name.
	section	data,data
	cnop	0,4
	xdef	_g_dt_smooth
	xdef	g_dt_smooth
	xdef	_g_dt_raw
	xdef	g_dt_raw
_g_dt_smooth:
g_dt_smooth:	dc.l	$3ca3d70a			; 0.02f
_g_dt_raw:
g_dt_raw:	dc.l	$3ca3d70a
	xdef	_g_dt500
	xdef	g_dt500
	xdef	_g_dt1000
	xdef	g_dt1000
_g_dt500:
g_dt500:	dc.l	$41200000			; g_dt_smooth x 500, x 1000 (gcc's dt * 500.0f: one rounding)
_g_dt1000:
g_dt1000:	dc.l	$41a00000
	xdef	_g_dt2000
	xdef	g_dt2000
	xdef	_g_dt6000
	xdef	g_dt6000
_g_dt2000:
g_dt2000:	dc.l	$42200000			; x 2000 (a flying prop's slowing), x 6000 (a fall)
_g_dt6000:
g_dt6000:	dc.l	$42f00000
