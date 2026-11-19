; mem_68k.s - THE PORT'S COPY (pure vasm; replaces memcpy -- newlib's / libnix's CopyMem -- through
; -Wl,--wrap=memcpy, and the video's row copy).
;   g_copy_kind 0: 68020/030: four long words into registers, then four out (16 bytes a pass)
;               1: 68040/060: 8 x move.l (a0)+,(a1)+ (32 bytes a pass)
	;               3: (080 build) AMMX load / store, 8 bytes a step -- set by mem.c os_copy_ammx after its test
;               2: as 1, and MOVE16 in blocks of 64 bytes where source and destination lie alike on 16
;                  and neither is in Chip RAM (< $200000) -- set only after mem.c's test on the machine
; The rest always byte by byte.  vasmm68k_mot -quiet -no-opt -m68060

	section	data,data
	xdef	_g_copy_kind
	xdef	g_copy_kind
	cnop	0,4
_g_copy_kind:
g_copy_kind:
	dc.l	1

	section	code,code
	xdef	_os_copy
	xdef	os_copy
	xdef	___wrap_memcpy
	xdef	__wrap_memcpy
; void *os_copy(void *d, const void *s, uint32_t n)   (the destination back in d0, as memcpy's)
___wrap_memcpy:
__wrap_memcpy:
_os_copy:
os_copy:
	move.l	4(sp),a1			; d
	move.l	8(sp),a0			; s
	move.l	12(sp),d1			; n
	cmp.l	#16,d1
	blo	oc_bytes
	move.l	g_copy_kind,d0
	beq	oc_020
	ifd	V080
	cmp.l	#3,d0				; 3: AMMX (080 build, after mem.c os_copy_ammx's test)
	beq.s	oc_ammx
	endif
	subq.l	#2,d0
	bne	oc_long
	; MOVE16: both out of Chip RAM, alike on 16, at least one block after the head
	cmp.l	#$200000,a0
	blo	oc_long
	cmp.l	#$200000,a1
	blo	oc_long
	move.l	a0,d0
	sub.l	a1,d0
	and.l	#15,d0
	bne	oc_long
	move.l	a1,d0				; the head: to the destination's next 16
	neg.l	d0
	and.l	#15,d0
	sub.l	d0,d1
	cmp.l	#64,d1
	blo.s	oc_m16no
	bra.s	oc_hd
oc_hl:	move.b	(a0)+,(a1)+
oc_hd:	dbra	d0,oc_hl			; (0..15 bytes)
	move.l	d1,d0
	lsr.l	#6,d0				; blocks of 64
oc_m16:	move16	(a0)+,(a1)+
	move16	(a0)+,(a1)+
	move16	(a0)+,(a1)+
	move16	(a0)+,(a1)+
	subq.l	#1,d0
	bne.s	oc_m16
	and.l	#63,d1
	bra.s	oc_long
oc_m16no:
	add.l	d0,d1				; (no block: the head back into the count)
oc_long:					; 32 bytes a pass, the rest byte by byte
	move.l	d1,d0
	lsr.l	#5,d0
	beq.s	oc_bytes
oc_l32:	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	subq.l	#1,d0
	bne.s	oc_l32
	and.l	#31,d1
	bra.s	oc_bytes
oc_020:						; 16 bytes a pass through four registers
	movem.l	d2-d5,-(sp)
	move.l	d1,d0
	lsr.l	#4,d0
oc_l16:	move.l	(a0)+,d2
	move.l	(a0)+,d3
	move.l	(a0)+,d4
	move.l	(a0)+,d5
	move.l	d2,(a1)+
	move.l	d3,(a1)+
	move.l	d4,(a1)+
	move.l	d5,(a1)+
	subq.l	#1,d0
	bne.s	oc_l16
	movem.l	(sp)+,d2-d5
	and.l	#15,d1
	ifd	V080
oc_ammx:					; 8 bytes a step (load / store, any alignment), the rest byte by byte
	move.l	d1,d0
	lsr.l	#3,d0
oc_al:	load	(a0)+,e0
	store	e0,(a1)+
	subq.l	#1,d0
	bne.s	oc_al
	and.l	#7,d1
	endif
oc_bytes:
	subq.l	#1,d1
	bmi.s	oc_done
oc_b:	move.b	(a0)+,(a1)+
	dbra	d1,oc_b				; (under 32 bytes here)
oc_done:
	move.l	4(sp),d0
	move.l	d0,a0				; (the answer in d0, and in a0 for m68k Linux's ABI)
	rts


; void scale_row68k(uint8_t *dst, const uint8_t *src, uint32_t w, uint32_t n): each of the row's w pixels n times
; (n = 2 or 3; amiga_video.c's window with --scale: the bigger pixels)
	xdef	_scale_row68k
	xdef	scale_row68k
_scale_row68k:
scale_row68k:
	move.l	4(sp),a1			; dst
	move.l	8(sp),a0			; src
	move.l	12(sp),d0			; w
	beq.s	sr_x
	cmp.l	#3,16(sp)
	beq.s	sr_3
sr_2:	move.b	(a0)+,d1			; two
	move.b	d1,(a1)+
	move.b	d1,(a1)+
	subq.l	#1,d0
	bne.s	sr_2
	rts
sr_3:	move.b	(a0)+,d1			; three
	move.b	d1,(a1)+
	move.b	d1,(a1)+
	move.b	d1,(a1)+
	subq.l	#1,d0
	bne.s	sr_3
sr_x:	rts
