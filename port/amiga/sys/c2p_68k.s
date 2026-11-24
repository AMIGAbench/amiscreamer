; c2p_68k.s - THE AGA PICTURE (amiga_video.c): chunky -> 8 contiguous bitplanes (bplsize bytes each, no modulo), a
; wrapper round Mikael Kalms' c2p1x1_8_c5_040 (68040 / 68060, public domain, unchanged in c2p/).
;   void c2p_init(uint32_t w, uint32_t h, uint32_t bplsize)       w a multiple of 32
;   void c2p_conv(const uint8_t *chunky, uint8_t *planes)
;   void c2pl_delta(chunky, planes, ref, npix, bplsize, rowbytes)   (c2p.library's delta conversion)
;   void c2p_conv080(const uint8_t *chunky, uint8_t *planes, uint32_t n64)   (V080 only: AMMX, 320x200)
	section	code,code
	xdef	_c2p_init
	xdef	c2p_init
_c2p_init:
c2p_init:
	movem.l	d2-d6,-(sp)
	move.l	24(sp),d0			; w
	move.l	28(sp),d1			; h
	move.l	32(sp),d5			; bplsize
	moveq	#0,d2
	moveq	#0,d3				; scroffsy
	moveq	#0,d4
	moveq	#0,d6
	bsr	c2p1x1_8_c5_040_init
	movem.l	(sp)+,d2-d6
	rts
	xdef	_c2p_conv
	xdef	c2p_conv
_c2p_conv:
c2p_conv:
	move.l	4(sp),a0
	move.l	8(sp),a1
	bra	c2p1x1_8_c5_040			; (it keeps d2-d7 / a2-a6 itself)

	ifd	V080
; 68080 (AMMX), c2p_conv080:
;   void c2p_conv080(const uint8_t *chunky, uint8_t *planes, uint32_t n64)
; the planes contiguous C2P_BPL apart (320x200: 8000 bytes), n64 = pixels / 64. Each 64 pixels: 8 loads + c2p (group
; k: byte i = bit 7-i of the 8 pixels, the left pixel in the top bit), the 8x8 byte matrix transposed in three vperm
; stages, one 64-bit store a plane (8 bytes = 64 pixels). The same bytes as Kalms' (amiga_video.c tests it at the
; start). E registers e8..e23: only with the task registered as an AMMX user (span.c, its task switch keeps them).
C2P_BPL	equ	8000
	xdef	_c2p_conv080
	xdef	c2p_conv080
_c2p_conv080:
c2p_conv080:
	move.l	a2,-(sp)
	movem.l	8(sp),a0/a1			; chunky, planes
	move.l	16(sp),d0			; n64
	lea	4*C2P_BPL(a1),a2		; planes 4..7
	beq	c8_e
c8_l:	c2p	(a0)+,e8			; groups R0..R7 (8 pixels each) straight from memory (C2P <vea>,d: no load
	c2p	(a0)+,e9			; first, 8 fewer AMMX instructions a pass); byte i = plane bit 7-i
	c2p	(a0)+,e10
	c2p	(a0)+,e11
	c2p	(a0)+,e12
	c2p	(a0)+,e13
	c2p	(a0)+,e14
	c2p	(a0)+,e15
	vperm	#$08192A3B,e8,e9,e16		; stage 1: bytes in pairs (R0,R1) ... (R6,R7)
	vperm	#$4C5D6E7F,e8,e9,e17
	vperm	#$08192A3B,e10,e11,e18
	vperm	#$4C5D6E7F,e10,e11,e19
	vperm	#$08192A3B,e12,e13,e20
	vperm	#$4C5D6E7F,e12,e13,e21
	vperm	#$08192A3B,e14,e15,e22
	vperm	#$4C5D6E7F,e14,e15,e23
	vperm	#$018923AB,e16,e18,e8		; stage 2: word pairs -> index 0/1 of R0..R3
	vperm	#$45CD67EF,e16,e18,e9		; Index 2/3
	vperm	#$018923AB,e17,e19,e10		; Index 4/5
	vperm	#$45CD67EF,e17,e19,e11		; Index 6/7
	vperm	#$018923AB,e20,e22,e12		; the same for R4..R7
	vperm	#$45CD67EF,e20,e22,e13
	vperm	#$018923AB,e21,e23,e14
	vperm	#$45CD67EF,e21,e23,e15
	vperm	#$012389AB,e8,e12,e16		; stage 3: index 0 = plane 7 ... index 7 = plane 0
	vperm	#$4567CDEF,e8,e12,e17
	vperm	#$012389AB,e9,e13,e18
	vperm	#$4567CDEF,e9,e13,e19
	vperm	#$012389AB,e10,e14,e20
	vperm	#$4567CDEF,e10,e14,e21
	vperm	#$012389AB,e11,e15,e22
	vperm	#$4567CDEF,e11,e15,e23
	store	e16,3*C2P_BPL(a2)		; Plane 7
	store	e17,2*C2P_BPL(a2)		; 6
	store	e18,C2P_BPL(a2)			; 5
	store	e19,(a2)			; 4
	store	e20,3*C2P_BPL(a1)		; 3
	store	e21,2*C2P_BPL(a1)		; 2
	store	e22,C2P_BPL(a1)			; 1
	store	e23,(a1)			; 0
	addq.l	#8,a1
	addq.l	#8,a2
	subq.l	#1,d0
	bne	c8_l
c8_e:	move.l	(sp)+,a2
	rts
	endif

;   void c2pl_delta(const uint8_t *chunky, uint8_t *planes, uint8_t *ref, uint32_t npix, uint32_t bplsize,
;                   uint32_t rowbytes)
; THE CHANGED PARTS (amiga_video.c): c2p.library's delta conversion (sys/c2plib, MIT, unchanged), with write-back --
; each 32 pixels against ref (what the planes show); only those that differ are converted (its 040 kernel) and
; copied into ref. npix a multiple of 32, the planes contiguous bplsize apart.
	xdef	_c2pl_delta
	xdef	c2pl_delta
	xref	_c2p_8x8_delta_writeback
_c2pl_delta:
c2pl_delta:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a0			; chunky
	move.l	52(sp),a1			; planes
	move.l	56(sp),a3			; ref
	move.l	60(sp),d0			; pixels
	move.l	64(sp),d1			; bitplane size
	move.l	68(sp),d2			; bitplane row size
	moveq	#0,d3				; (not interleaved)
	jsr	_c2p_8x8_delta_writeback
	movem.l	(sp)+,d2-d7/a2-a6
	rts

	include	"amiga/sys/c2p/c2p1x1_8_c5_040.s"
