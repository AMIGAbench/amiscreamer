; sort_68k.s - THE PAINTER'S OBJECT SORT in vasm: a stable radix sort (least significant byte first) of the
; 16-byte pt_obj records {first, count, key, order} on key, the furthest (largest) first.  The records are
; made in order (order grows with the index), so a stable sort on the key alone gives qsort(pt_cmp)'s order
; exactly.  C reference: main.c pt_sort_c.  Byte b of key ^ $7fffffff (descending as ascending); a pass whose
; byte is the same for every record is skipped.  The histograms (4 x 256 long words) on the stack.
; void pt_sort68k(pt_obj *a, pt_obj *tmp, int n)            vasmm68k_mot -quiet -no-opt -m68060

PO_KEY	equ	8

	section	code,code
	xdef	_pt_sort68k
	xdef	pt_sort68k
_pt_sort68k:
pt_sort68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a2			; a
	move.l	52(sp),a3			; tmp
	move.l	56(sp),d7			; n
	cmp.l	#2,d7
	blt	ps_out
	lea	-4096(sp),sp
	move.l	sp,a4				; hist[4][256]
	move.l	a4,a0
	move.w	#1023,d0
	moveq	#0,d1
ps_clr:	move.l	d1,(a0)+
	dbra	d0,ps_clr
	; one pass over the records: all four histograms
	move.l	a2,a0
	move.l	d7,d0
	subq.l	#1,d0
	moveq	#0,d2
ps_cnt:	move.l	PO_KEY(a0),d1
	eor.l	#$7fffffff,d1
	lea	16(a0),a0
	move.b	d1,d2
	addq.l	#1,(a4,d2.l*4)
	lsr.l	#8,d1
	move.b	d1,d2
	addq.l	#1,1024(a4,d2.l*4)
	lsr.l	#8,d1
	move.b	d1,d2
	addq.l	#1,2048(a4,d2.l*4)
	lsr.l	#8,d1
	move.b	d1,d2
	addq.l	#1,3072(a4,d2.l*4)
	dbra	d0,ps_cnt
	; the passes: a0 from, a1 to, a5 this pass's histogram, d6 its shift
	move.l	a2,a0
	move.l	a3,a1
	move.l	a4,a5
	moveq	#0,d6
ps_pass:
	move.l	PO_KEY(a0),d1			; the first record's byte: all in one bucket -> nothing to do
	eor.l	#$7fffffff,d1
	lsr.l	d6,d1
	and.l	#255,d1
	cmp.l	(a5,d1.l*4),d7
	beq	ps_next
	move.l	a5,a6				; counts -> starts
	moveq	#0,d3
	move.w	#255,d0
ps_sum:	move.l	(a6),d4
	move.l	d3,(a6)+
	add.l	d4,d3
	dbra	d0,ps_sum
	move.l	a0,a6				; every record to its place
	move.l	d7,d0
	subq.l	#1,d0
ps_sc:	move.l	PO_KEY(a6),d1
	eor.l	#$7fffffff,d1
	lsr.l	d6,d1
	and.l	#255,d1
	move.l	(a5,d1.l*4),d2
	addq.l	#1,(a5,d1.l*4)
	lsl.l	#4,d2
	lea	(a1,d2.l),a2
	move.l	(a6)+,(a2)+
	move.l	(a6)+,(a2)+
	move.l	(a6)+,(a2)+
	move.l	(a6)+,(a2)+
	dbra	d0,ps_sc
	exg	a0,a1				; the sorted ones are the next pass's source
ps_next:
	lea	1024(a5),a5
	addq.l	#8,d6
	cmp.l	#32,d6
	blo	ps_pass
	lea	4096(sp),sp
	move.l	48(sp),a2			; ended in tmp: back to a
	cmpa.l	a2,a0
	beq	ps_out
	move.l	d7,d0
	subq.l	#1,d0
ps_cb:	move.l	(a0)+,(a2)+
	move.l	(a0)+,(a2)+
	move.l	(a0)+,(a2)+
	move.l	(a0)+,(a2)+
	dbra	d0,ps_cb
ps_out:	movem.l	(sp)+,d2-d7/a2-a6
	rts
