; win_68k.s - THE WINDOW's picture (OS_WINDOW / --window): a row of 8-bit pixels into the Workbench's pixel format
; through the table g_wpix (amiga_video.c win_pixel: 16 bits doubled in the long word, top = bottom).
; A C loop (byte loaded, at once an index) cost ~6.6
; cycles a pixel on the V1200; here 4 source pixels as one long word, the indices by register operations, then 4
; independent table loads, the stores grouped.  vasmm68k_mot -quiet -no-opt -m68020

	section	code,code

; void win_row16x1(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *tab)
; n pixels (a multiple of 4) as 16-bit pixels, two in a long word
	xdef	_win_row16x1
	xdef	win_row16x1
_win_row16x1:
win_row16x1:
	movem.l	d2-d5/a2,-(sp)
	move.l	24(sp),a0			; d
	move.l	28(sp),a1			; s
	move.l	32(sp),d5			; n
	move.l	36(sp),a2			; tab
	lsr.l	#2,d5
	beq.s	.x1e
	move.l	#$3fc,d4			; index * 4
.x1l:
	move.l	(a1)+,d0			; p0 p1 p2 p3
	move.l	d0,d1
	move.l	d0,d2
	move.l	d0,d3
	swap	d0
	swap	d1
	lsr.l	#6,d0				; p0 * 4
	lsl.l	#2,d1				; p1 * 4 (low)
	lsr.l	#6,d2				; p2 * 4
	lsl.l	#2,d3				; p3 * 4
	and.l	d4,d1
	and.l	d4,d2
	and.l	d4,d3
	and.l	d4,d0
	move.l	(a2,d1.l),d1
	move.l	(a2,d0.l),d0
	move.l	(a2,d3.l),d3
	move.l	(a2,d2.l),d2
	move.w	d1,d0				; p0 high, p1 low
	move.w	d3,d2
	move.l	d0,(a0)+
	move.l	d2,(a0)+
	subq.l	#1,d5
	bne.s	.x1l
.x1e:
	movem.l	(sp)+,d2-d5/a2
	rts

; void win_row32x1(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *tab)
; n pixels (a multiple of 4), a long word of the table each: 16 bits doubled (= 2x) or 32 bits (1x)
	xdef	_win_row32x1
	xdef	win_row32x1
_win_row32x1:
win_row32x1:
	movem.l	d2-d5/a2,-(sp)
	move.l	24(sp),a0			; d
	move.l	28(sp),a1			; s
	move.l	32(sp),d5			; n
	move.l	36(sp),a2			; tab
	lsr.l	#2,d5
	beq.s	.x2e
	move.l	#$3fc,d4
.x2l:
	move.l	(a1)+,d0
	move.l	d0,d1
	move.l	d0,d2
	move.l	d0,d3
	swap	d0
	swap	d1
	lsr.l	#6,d0
	lsl.l	#2,d1
	lsr.l	#6,d2
	lsl.l	#2,d3
	and.l	d4,d1
	and.l	d4,d2
	and.l	d4,d3
	and.l	d4,d0
	move.l	(a2,d0.l),d0
	move.l	(a2,d1.l),d1
	move.l	(a2,d2.l),d2
	move.l	(a2,d3.l),d3
	move.l	d0,(a0)+
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	subq.l	#1,d5
	bne.s	.x2l
.x2e:
	movem.l	(sp)+,d2-d5/a2
	rts

; void win_row32x2(uint32_t *d, const uint8_t *s, uint32_t n, const uint32_t *tab, uint32_t bpr)
; as win_row32x1, but into two rows at once (d and d + bpr): 16 bits 2x without a row copy afterwards
	xdef	_win_row32x2
	xdef	win_row32x2
_win_row32x2:
win_row32x2:
	movem.l	d2-d5/a2-a3,-(sp)
	move.l	28(sp),a0			; d
	move.l	32(sp),a1			; s
	move.l	36(sp),d5			; n
	move.l	40(sp),a2			; tab
	move.l	a0,a3
	add.l	44(sp),a3			; d + bpr
	lsr.l	#2,d5
	beq.s	.x3e
	move.l	#$3fc,d4
.x3l:
	move.l	(a1)+,d0
	move.l	d0,d1
	move.l	d0,d2
	move.l	d0,d3
	swap	d0
	swap	d1
	lsr.l	#6,d0
	lsl.l	#2,d1
	lsr.l	#6,d2
	lsl.l	#2,d3
	and.l	d4,d1
	and.l	d4,d2
	and.l	d4,d3
	and.l	d4,d0
	move.l	(a2,d0.l),d0
	move.l	(a2,d1.l),d1
	move.l	(a2,d2.l),d2
	move.l	(a2,d3.l),d3
	move.l	d0,(a0)+
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	move.l	d3,(a0)+
	move.l	d0,(a3)+
	move.l	d1,(a3)+
	move.l	d2,(a3)+
	move.l	d3,(a3)+
	subq.l	#1,d5
	bne.s	.x3l
.x3e:
	movem.l	(sp)+,d2-d5/a2-a3
	rts

; ---------------------------------------------------------------- the stack in the arena's field (sys/arena.c)
; int amiga_stack_run(void *lower, void *upper, int (*fn)(int, char **), int argc, char **argv)
; fn(argc, argv) on the stack [lower, upper): exec StackSwap there, the call, StackSwap back; its result.
; void amiga_stack_exit(int rc): from anywhere on that stack (arena.c __wrap_exit) -- straight back as if fn
; returned rc (the frames on it are dropped; the StackSwapStruct is on the caller's stack, its address in ss_sss)
	xdef	_amiga_stack_run
	xdef	_amiga_stack_exit
_amiga_stack_run:
	movem.l	d2-d7/a2-a6,-(sp)		; 44 bytes
	lea	-12(sp),sp			; struct StackSwapStruct { stk_Lower, stk_Upper, stk_Pointer }
	move.l	60(sp),(sp)			; lower
	move.l	64(sp),4(sp)			; upper
	move.l	64(sp),8(sp)			; the new sp: its top
	movea.l	68(sp),a2			; fn
	move.l	72(sp),d2			; argc
	move.l	76(sp),d3			; argv
	move.l	sp,ss_sss
	movea.l	sp,a0
	movea.l	4.w,a6
	jsr	-732(a6)			; StackSwap (now on the new stack)
	move.l	d3,-(sp)
	move.l	d2,-(sp)
	jsr	(a2)
ss_back:
	move.l	d0,d2				; (fn's result, or amiga_stack_exit's rc)
	movea.l	ss_sss,a0
	movea.l	4.w,a6
	jsr	-732(a6)			; StackSwap back (sp: the frame above again)
	clr.l	ss_sss
	move.l	d2,d0
	lea	12(sp),sp
	movem.l	(sp)+,d2-d7/a2-a6
	rts
_amiga_stack_exit:
	move.l	4(sp),d0
	bra.s	ss_back

	section	bss,bss
ss_sss:	ds.l	1
