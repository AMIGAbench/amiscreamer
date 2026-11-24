; lzw_68k.s - THE CONTAINERS' LZW in vasm (port/src/port.c lzw_decode is the reference: OS_LZWASM=0 C, =c both,
; compared).  LSB-first codes of 9..12 bits, 0x100 clear, 0x101 end, no header.  The same answers as the C in every
; case: the end of the data (a code that does not fit is not read, bytes past the end are 0), the cut at `want`,
; -1 for a code past the next one or for the next one with nothing before it.
; Each code's string LENGTH is kept (s_len), so a string is written straight into its place from its end (no stack,
; no second copy); only a string that `want` cuts goes the C's way, through s_stack.
;
; long lzw68k(const unsigned char *src, long n, unsigned char *out, long want)
; d2 bit, d3 width, d4 threshold, d5 next, d6 prev, d7 got; a0 src, a1 out, a2 prefix (longs), a3 suffix,
; a4 length (words), a6 want; locals: 0 n * 8, 4 n, 8 the code, 12 1 = the code about to be made

	section	code,code

	xdef	_lzw68k
	xdef	lzw68k
_lzw68k:
lzw68k:
	movem.l	d2-d7/a2-a6,-(sp)
	lea	-16(sp),sp
	move.l	64(sp),a0
	move.l	72(sp),a1
	move.l	76(sp),a6
	move.l	68(sp),d0
	move.l	d0,4(sp)
	lsl.l	#3,d0
	move.l	d0,(sp)
	lea	s_prefix,a2
	lea	s_suffix,a3
	lea	s_len,a4
	move.l	#$00010001,d0			; the 256 bytes: strings of one
	moveq	#127,d1
	move.l	a4,a5
.il:	move.l	d0,(a5)+
	dbf	d1,.il
	moveq	#0,d2
	moveq	#0,d7
.clear:	moveq	#9,d3
	move.l	#$200,d4
	move.l	#$102,d5
	moveq	#-1,d6
.loop:	cmp.l	a6,d7				; while (got < want)
	bge	.done
	move.l	d2,d0
	add.l	d3,d0
	cmp.l	(sp),d0				; a code that does not fit: the end
	bgt	.done
	move.l	d2,d1
	lsr.l	#3,d1				; at
	lea	(a0,d1.l),a5
	addq.l	#2,d1
	cmp.l	4(sp),d1
	bge	.edge
	moveq	#0,d0				; three bytes, little-endian
	move.b	2(a5),d0
	lsl.w	#8,d0
	move.b	1(a5),d0
	lsl.l	#8,d0
	move.b	(a5),d0
.got3:	moveq	#7,d1
	and.l	d2,d1
	lsr.l	d1,d0
	moveq	#1,d1
	lsl.l	d3,d1
	subq.l	#1,d1
	and.l	d1,d0				; the code
	add.l	d3,d2
	cmp.l	#$101,d0
	beq	.done
	cmp.l	#$100,d0
	beq.s	.clear
	move.l	d0,8(sp)
	clr.l	12(sp)
	cmp.l	d5,d0
	blt.s	.known
	tst.l	d6				; the code about to be made: the last string + its own first byte
	bmi	.bad
	cmp.l	d5,d0
	bgt	.bad
	move.l	#1,12(sp)
	move.l	d6,d0
.known:	moveq	#0,d1
	move.w	(a4,d0.l*2),d1			; its length
	lea	(a1,d7.l),a5
	add.l	d1,a5				; written from its end
	add.l	d1,d7
	add.l	12(sp),d7			; got + its length
	cmp.l	a6,d7
	bgt.s	.slowb
	subq.l	#1,d1
	bra.s	.wt
.w:	move.b	(a3,d0.l),-(a5)
	move.l	(a2,d0.l*4),d0
.wt:	dbf	d1,.w
	move.b	d0,-(a5)			; d0 = its first byte
	tst.l	12(sp)
	beq.s	.add
	move.b	d0,-1(a1,d7.l)
.add:	tst.l	d6				; the table: prev + first
	bmi.s	.np
	cmp.l	#4096,d5
	bge.s	.np
	move.l	d6,(a2,d5.l*4)
	move.b	d0,(a3,d5.l)
	move.w	(a4,d6.l*2),d1
	addq.w	#1,d1
	move.w	d1,(a4,d5.l*2)
	addq.l	#1,d5
	cmp.l	d4,d5
	blt.s	.np
	cmp.l	#12,d3
	beq.s	.np
	addq.l	#1,d3
	add.l	d4,d4
.np:	move.l	8(sp),d6			; prev = code
	bra	.loop
.slowb:	sub.l	d1,d7				; (got as it was)
	sub.l	12(sp),d7
.slow:	lea	s_stack+4100,a5			; cut by want: the string into s_stack, as much of it as fits out
.sw:	cmp.l	#$ff,d0
	bls.s	.swf
	move.b	(a3,d0.l),-(a5)
	move.l	(a2,d0.l*4),d0
	bra.s	.sw
.swf:	move.b	d0,-(a5)
	move.l	#s_stack+4100,d1
.cp:	cmp.l	a6,d7
	bge.s	.cpd
	cmpa.l	d1,a5
	beq.s	.cpd
	move.b	(a5)+,(a1,d7.l)
	addq.l	#1,d7
	bra.s	.cp
.cpd:	tst.l	12(sp)
	beq.s	.add
	cmp.l	a6,d7
	bge.s	.add
	move.b	d0,(a1,d7.l)
	addq.l	#1,d7
	bra.s	.add
.edge:	moveq	#0,d0				; at the data's end: what is past it is 0
	subq.l	#1,d1
	cmp.l	4(sp),d1
	bge.s	.e1
	move.b	1(a5),d0
	lsl.l	#8,d0
.e1:	move.b	(a5),d0
	bra	.got3
.bad:	moveq	#-1,d0
	bra.s	.ret
.done:	move.l	d7,d0
.ret:	lea	16(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts

	section	bss,bss
	cnop	0,4
s_prefix:	ds.l	4096
s_len:		ds.w	4096
s_suffix:	ds.b	4096
s_stack:	ds.b	4100
	even

; uintptr_t nz68k(const uint32_t *p, const uint32_t *end): the next word from p on that is not zero, or end
; (port.c os_state_save: the zero-filled statics' few words that are not zero; 2 instructions a word)
	section	code,code
	xdef	_nz68k
	xdef	nz68k
_nz68k:
nz68k:
	move.l	4(sp),a0
	move.l	8(sp),d1
	sub.l	a0,d1
	lsr.l	#2,d1
	beq.s	.end
	subq.l	#1,d1
.l:	tst.l	(a0)+
	dbne	d1,.l
	bne.s	.found
	sub.l	#$10000,d1			; (more than 65536 words: the counter's high half)
	bcc.s	.l
.end:	move.l	8(sp),d0
	rts
.found:	move.l	a0,d0
	subq.l	#4,d0
	rts
