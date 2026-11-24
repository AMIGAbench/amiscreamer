; hud_68k.s - THE RACE SCREEN'S PIXELS in vasm (C references in main.c: hud_blit_c, hud_darken_c; OS_HUDASM=0).
; Rows left to right, the destination through (a1)+.
; vasmm68k_mot -quiet -no-opt -m68060

	section	code,code

; void hud_blit68k(const hud_blit *b)    {0 dst, 4 dpitch, 8 src, 12 spitch, 16 w, 20 h, 24 add}
; every source byte that is not 0 goes to the picture as byte + add (a letter's shade + colour x 16, a sprite's
; colour + 0); a 0 leaves the picture's byte
	xdef	_hud_blit68k
	xdef	hud_blit68k
_hud_blit68k:
hud_blit68k:
	movem.l	d2-d6/a2-a3,-(sp)
	move.l	32(sp),a0
	move.l	(a0),a2				; destination row
	move.l	4(a0),d6			; its pitch
	move.l	8(a0),a3			; source row
	move.l	12(a0),d2			; its pitch
	move.l	16(a0),d4			; w
	move.l	20(a0),d5			; h
	move.l	24(a0),d3			; add
	ifd	V080
	tst.l	hud_v080			; the 080 (main.c hud_asm: tested against hud_blit_c) and add a multiple of 16
	beq.s	hb_sc				; (a letter: shade 1..15 + colour x 16, a sprite: + 0 -- a byte not 0 stays
	moveq	#15,d0				; not 0, so storem3's "only bytes not 0" is the reference's test): hb_v
	and.l	d3,d0
	beq	hb_v
hb_sc:
	endif
	subq.l	#1,d4
	bmi.s	hb_out
	subq.l	#1,d5
	bmi.s	hb_out
hb_row:	move.l	a3,a0
	move.l	a2,a1
	move.l	d4,d1
hb_px:	move.b	(a0)+,d0
	beq.s	hb_tr
	add.b	d3,d0
	move.b	d0,(a1)+
	dbra	d1,hb_px
	bra.s	hb_nx
hb_tr:	addq.l	#1,a1				; (0: the picture's byte stays -- not read and written back: on the
	dbra	d1,hb_px			; V1200 a cold line's read and a store less)
hb_nx:	adda.l	d6,a2
	adda.l	d2,a3
	dbra	d5,hb_row
hb_out:	movem.l	(sp)+,d2-d6/a2-a3
	rts
	ifd	V080
; 8 pixels at a time: load, pcmpeqb against 0, paddb add, pandn (0 stays 0), storem3 (only bytes not 0); the row's rest
; through a mask of its first n bytes (the load may read up to 7 bytes past the row: reading only)
hb_v:	tst.l	d4
	ble.s	hb_out
	tst.l	d5
	ble.s	hb_out
	moveq	#0,d0
	vperm	#$4567CDEF,d0,d0,e1		; 0 x 8
	and.l	#255,d3
	mulu.l	#$01010101,d3
	vperm	#$4567CDEF,d3,d3,e5		; add x 8
	move.l	d4,d0				; (d6: the destination's pitch, d2 the source's, a2 / a3 their rows)
	and.l	#7,d0
	lea	hb_mask(pc),a1
	lea	(a1,d0.l*8),a1
	load	(a1),e6				; the rest's mask
	lsr.l	#3,d4				; whole groups
hv_row:	move.l	a3,a0
	move.l	a2,a1
	move.l	d4,d1
	bra.s	hv_g2
hv_g:	load	(a0)+,e0
	pcmpeqb	e1,e0,e2
	paddb	e5,e0,e3
	pandn	e2,e3,e3
	storem3	e3,d1,(a1)+			; (d1: mode 1, vasm's way of writing #1)
hv_g2:	dbra	d1,hv_g
	load	(a0),e0				; the rest (0..7 bytes; mask 0 = nothing)
	pcmpeqb	e1,e0,e2
	paddb	e5,e0,e3
	pandn	e2,e3,e3
	pand	e6,e3,e3
	storem3	e3,d1,(a1)
	adda.l	d6,a2
	adda.l	d2,a3
	subq.l	#1,d5
	bne.s	hv_row
	bra	hb_out
	cnop	0,8
hb_mask:	dc.l	0,0
	dc.l	$ff000000,0
	dc.l	$ffff0000,0
	dc.l	$ffffff00,0
	dc.l	$ffffffff,0
	dc.l	$ffffffff,$ff000000
	dc.l	$ffffffff,$ffff0000
	dc.l	$ffffffff,$ffffff00
	endif
	section	data,data
	xdef	_hud_v080
	xdef	hud_v080
	cnop	0,4
_hud_v080:
hud_v080:	dc.l	0				; 1 = hud_blit68k's AMMX way (only the 080 build sets it, after its test)
	section	code,code

; void hud_darken68k(uint8_t *dst, int pitch, int w, int h, const uint8_t *tab)
; every byte of the window through tab: byte by byte to the next long word, then long words through four pre-shifted
; long tables hd_t (hd_t + k*1024: tab[i] << 8k, made again when tab's 256 bytes differ from the copy hd_c): the long
; word's four bytes each looked up in its own table, the results or-ed (no chain through one register); the rest byte
; by byte
	xdef	_hud_darken68k
	xdef	hud_darken68k
_hud_darken68k:
hud_darken68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a3			; dst
	move.l	56(sp),d0			; w
	ble	hd_out
	move.l	60(sp),d7			; h
	subq.l	#1,d7
	bmi	hd_out
	move.l	64(sp),a2			; tab
	lea	hd_c,a0				; the same table as the last time?
	move.l	a2,a1
	moveq	#63,d1
hd_cc:	cmpm.l	(a1)+,(a0)+
	dbne	d1,hd_cc
	beq.s	hd_ok
	lea	hd_c,a0				; no: copy it and make the four long tables
	move.l	a2,a1
	moveq	#63,d1
hd_cp:	move.l	(a1)+,(a0)+
	dbra	d1,hd_cp
	lea	hd_t,a0
	move.l	a2,a1
	move.w	#255,d1
	moveq	#0,d2
hd_mk:	move.b	(a1)+,d2
	move.l	d2,(a0)
	move.l	d2,d3
	lsl.l	#8,d3
	move.l	d3,1024(a0)
	lsl.l	#8,d3
	move.l	d3,2048(a0)
	lsl.l	#8,d3
	move.l	d3,3072(a0)
	addq.l	#4,a0
	dbra	d1,hd_mk
hd_ok:	lea	hd_t,a0				; tab << 0 (the long word's last byte)
	lea	1024(a0),a4			; << 8
	lea	2048(a0),a5			; << 16
	lea	3072(a0),a6			; << 24 (its first byte)
	moveq	#0,d1				; the indices: only their low byte / word is ever written
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
hd_row:	move.l	a3,a1
	move.l	56(sp),d6			; bytes left in the row
hd_hd:	move.l	a1,d0				; to the long word
	and.l	#3,d0
	beq.s	hd_l
	move.b	(a1),d1
	move.b	(a2,d1.l),(a1)+
	subq.l	#1,d6
	bne.s	hd_hd
	bra.s	hd_nx
hd_l:	move.l	d6,d5
	lsr.l	#2,d5
	beq.s	hd_t0
	subq.l	#1,d5
hd_ll:	move.l	(a1),d0				; p0 p1 p2 p3
	move.b	d0,d1				; p3
	move.w	d0,d2
	swap	d0
	lsr.w	#8,d2				; p2
	move.b	d0,d3				; p1
	lsr.w	#8,d0				; p0 (the index only its low word)
	move.l	(a0,d1.w*4),d4
	or.l	(a4,d2.w*4),d4
	or.l	(a5,d3.w*4),d4
	or.l	(a6,d0.w*4),d4
	move.l	d4,(a1)+
	dbra	d5,hd_ll
	and.l	#3,d6
hd_t0:	subq.l	#1,d6
	bmi.s	hd_nx
hd_tl:	move.b	(a1),d1
	move.b	(a2,d1.l),(a1)+
	dbra	d6,hd_tl
hd_nx:	adda.l	52(sp),a3
	dbra	d7,hd_row
hd_out:	movem.l	(sp)+,d2-d7/a2-a6
	rts

	section	bss,bss
	cnop	0,4
hd_t:	ds.l	1024				; hud_darken68k's four pre-shifted tables
hd_c:	ds.b	256				; and the table they were made from (0s: made on the first call, tab[0] != 0
	section	code,code			; or not -- a table of 0s gives hd_t of 0s, which it is)

; void hud_line68k(const hud_line *l)  {0 fb, 4 pitch, 8 x0, 12 y0, 16 x1, 20 y1, 24 colour, 28 clip x0, 32 clip x1,
;                                       36 clip y0, 40 clip y1, 44 oy}
; main.c hud_radar's line exactly: point k of n = max(|dx|, |dy|) at x0 + dx k / n (C's division, towards 0) -- as
; magnitudes stepped without a division: acc += |dx|, past n at most once a step -> one pixel on -- then hud_put's
; y + oy and cut
	xdef	_hud_line68k
	xdef	hud_line68k
_hud_line68k:
hud_line68k:
	movem.l	d2-d7/a2-a5,-(sp)
	move.l	44(sp),a5			; l
	move.l	8(a5),d0			; both ends on one side outside the cut: no point of the line inside it
	move.l	16(a5),d1			; (every point lies between the ends' x and y)
	cmp.l	28(a5),d0
	bge.s	hl_t1
	cmp.l	28(a5),d1
	blt	hl_out
hl_t1:	cmp.l	32(a5),d0
	blt.s	hl_t2
	cmp.l	32(a5),d1
	bge	hl_out
hl_t2:	move.l	12(a5),d0
	move.l	20(a5),d1
	add.l	44(a5),d0
	add.l	44(a5),d1
	cmp.l	36(a5),d0
	bge.s	hl_t3
	cmp.l	36(a5),d1
	blt	hl_out
hl_t3:	cmp.l	40(a5),d0
	blt.s	hl_t4
	cmp.l	40(a5),d1
	bge	hl_out
hl_t4:	move.l	8(a5),d0			; x
	move.l	12(a5),d1			; y
	add.l	44(a5),d1			; (+ oy)
	move.l	16(a5),d2
	sub.l	8(a5),d2			; |dx|, sx
	moveq	#1,d6
	tst.l	d2
	bpl.s	hl_1
	neg.l	d2
	moveq	#-1,d6
hl_1:	move.l	20(a5),d3
	sub.l	12(a5),d3			; |dy|, sy
	moveq	#1,d7
	tst.l	d3
	bpl.s	hl_2
	neg.l	d3
	moveq	#-1,d7
hl_2:	move.l	d2,d4				; n = max(|dx|, |dy|): n + 1 points
	cmp.l	d3,d4
	bge.s	hl_3
	move.l	d3,d4
hl_3:	move.l	d4,a1				; n
	suba.l	a2,a2				; acc x
	suba.l	a3,a3				; acc y
	move.l	a6,-(sp)
	move.l	4(a5),d5			; the point's address stepped with it: fb + y pitch + x once, then +-1 and
	move.l	d5,a6				; +-pitch (no muls.l a point), the colour in d5
	muls.l	d1,d5
	add.l	d0,d5
	move.l	(a5),a4
	add.l	d5,a4
	tst.l	d7
	bpl.s	hl_4
	move.l	a6,d5
	neg.l	d5
	move.l	d5,a6				; sy pitch
hl_4:	move.l	24(a5),d5			; (the colour: its low byte)
hl_lp:	cmp.l	28(a5),d0			; hud_put's cut
	blt.s	hl_no
	cmp.l	32(a5),d0
	bge.s	hl_no
	cmp.l	36(a5),d1
	blt.s	hl_no
	cmp.l	40(a5),d1
	bge.s	hl_no
	move.b	d5,(a4)
hl_no:	subq.l	#1,d4
	bmi.s	hl_end
	adda.l	d2,a2				; x on?
	cmpa.l	a1,a2
	blt.s	hl_nx
	suba.l	a1,a2
	add.l	d6,d0
	adda.l	d6,a4
hl_nx:	adda.l	d3,a3				; y on?
	cmpa.l	a1,a3
	blt.s	hl_lp
	suba.l	a1,a3
	add.l	d7,d1
	adda.l	a6,a4
	bra.s	hl_lp
hl_end:	move.l	(sp)+,a6
hl_out:	movem.l	(sp)+,d2-d7/a2-a5
	rts
