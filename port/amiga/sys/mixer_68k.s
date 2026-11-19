; mixer_68k.s - THE EFFECTS' MIXER for the Paula.  16 voices of 8-bit unsigned PCM (SOUND.DAT), the pitch a 16.16 step, volume and
; pan through tables: each voice's lr[256] = (left << 16) + right, so one add.l a voice-sample for both sides; the
; sum soft-limited to two 8-bit signed buffers.  The kernels (MIXV with two position chains, mix_outl68k, mix_tab68k)
; are hand-written; the control (mx_init .. mx_render_l) is a C mixer in vasm, the same results
; (tools/mixtest: against that C).  Not thread-safe: the caller holds a semaphore round mx_render_l and the changes.
; vasmm68k_mot -quiet -no-opt -m68060

	section	code,code

; void mix_voice68k(int32_t *acc, const uint8_t *pcm, const int32_t *lr, uint32_t *pos, uint32_t stp, uint32_t m)
; acc[j] += lr[pcm[pos >> 16]], pos += stp für j = 0..m-1 (pos 16.16 mit Überlauf wie uint32; m >= 1; stp <= $400000)
; mix_voiceset68k: gleich, aber acc[j] = ... (erste Stimme eines Blocks, spart das Nullen von acc)
; Zwei Positionsketten (gerade/ungerade Samples, Schritt 2 * stp): die Ladebefehle hängen nicht direkt am addx bzw. am
; eben geladenen Index. V1200 (vprobe --mix): 76 -> 63 ns je Stimmen-Sample gegen die einfache Kette (tests/vprobe_mix.s).
MIXV	macro
	movem.l	d2-d7/a2-a3,-(sp)
	move.l	36(sp),a0			; acc
	move.l	40(sp),a1			; pcm
	move.l	44(sp),a2			; lr
	move.l	48(sp),a3			; &pos
	move.l	(a3),d4
	moveq	#0,d2
	swap	d4
	move.w	d4,d2				; Kette A: d2.w ganzzahlig (oberes Wort 0)
	clr.w	d4				; d4 = Nachkomma << 16
	move.l	52(sp),d6			; stp
	move.l	56(sp),d7			; m
	moveq	#0,d0
	btst	#0,d7				; m ungerade: ein Sample vorweg
	beq	.e\@
	move.l	d6,d5
	swap	d5
	clr.w	d5
	move.l	d6,d3
	swap	d3
	move.b	(a1,d2.l),d0
	add.l	d5,d4
	addx.w	d3,d2
	move.l	(a2,d0.l*4),d3
	\1.l	d3,(a0)+
.e\@:	lsr.l	#1,d7				; Paare
	beq	.d\@
	move.l	d6,d0
	swap	d0
	clr.w	d0				; stp Nachkomma << 16
	move.l	d6,d1
	swap	d1				; d1.w = stp ganzzahlig
	move.l	d4,d5				; Kette B = A + stp
	moveq	#0,d3
	move.w	d2,d3
	add.l	d0,d5
	addx.w	d1,d3
	add.l	d6,d6				; 2 * stp
	move.l	d6,d0
	swap	d0
	clr.w	d0
	swap	d6				; d6.w = (2 * stp) ganzzahlig
	move.l	a3,-(sp)
	lea	(a0,d7.l*8),a3			; Ende von acc
	move.l	d0,-(sp)			; (sp) = (2 * stp) Nachkomma << 16
	move.l	d3,d7				; Kette B ganzzahlig
	moveq	#0,d0
	moveq	#0,d1
.l\@:	move.b	(a1,d2.l),d0			; Index gerades Sample
	move.b	(a1,d7.l),d1			; Index ungerades Sample
	add.l	(sp),d4
	addx.w	d6,d2
	move.l	(a2,d0.l*4),d3
	add.l	(sp),d5
	addx.w	d6,d7
	\1.l	d3,(a0)+
	move.l	(a2,d1.l*4),d3
	\1.l	d3,(a0)+
	cmpa.l	a3,a0
	bne	.l\@
	addq.l	#4,sp
	move.l	(sp)+,a3
.d\@:	swap	d2				; pos = Kette A
	swap	d4
	move.w	d4,d2
	move.l	d2,(a3)
	movem.l	(sp)+,d2-d7/a2-a3
	rts
	endm

	xdef	_mix_voice68k
	xdef	mix_voice68k
_mix_voice68k:
mix_voice68k:
	MIXV	add

	xdef	_mix_voiceset68k
	xdef	mix_voiceset68k
_mix_voiceset68k:
mix_voiceset68k:
	MIXV	move

; void mix_out68k(const int32_t *acc, int8_t *left, int8_t *right, uint32_t k, const int8_t *clamp)
; t = acc[i]: rechts b = (int16)t, links a = (t - b) >> 16; je auf -128..127 begrenzt über clamp[x] (x = -2048..2047,
; clamp zeigt auf den Eintrag 0)
	xdef	_mix_out68k
	xdef	mix_out68k
_mix_out68k:
mix_out68k:
	movem.l	d2/a2-a4,-(sp)
	movem.l	20(sp),a0/a3/a4			; acc, left, right
	move.l	32(sp),d2			; k >= 1
	move.l	36(sp),a2
	subq.l	#1,d2
mo_l:	move.l	(a0)+,d0
	move.w	d0,d1
	ext.l	d1
	sub.l	d1,d0
	swap	d0
	move.b	(a2,d1.w),(a4)+
	move.b	(a2,d0.w),(a3)+
	dbra	d2,mo_l
	sub.l	#$10000,d2
	bcc	mo_l
	movem.l	(sp)+,d2/a2-a4
	rts

; LONG mix_outl68k(const int32_t *acc, int8_t *left, int8_t *right, uint32_t k, const int8_t *clamp)
; wie mix_out68k, aber je 4 Samples als Langwort geschrieben (Ziel langwortausgerichtet, k Vielfaches von 8): Paula
; schreibt direkt in den Chip-Puffer, die Rechnung der nächsten Samples überdeckt den Chip-Zugriff. Rückgabe:
; Spitzenpegel max |left[i]| über i = 0, 8, 16, ... (wie snd_fill vorher)
MOUT	macro					; \1 = Sample-Nr. 0..3 in der Gruppe
	move.l	(a0)+,d0
	move.w	d0,d1
	ext.l	d1
	sub.l	d1,d0
	swap	d0
	lsl.l	#8,d5
	move.b	(a2,d1.w),d5			; rechts
	lsl.l	#8,d4
	move.b	(a2,d0.w),d4			; links
	endm
	xdef	_mix_outl68k
	xdef	mix_outl68k
_mix_outl68k:
mix_outl68k:
	movem.l	d2-d5/a2-a4,-(sp)
	movem.l	32(sp),a0/a3/a4			; acc, left, right
	move.l	44(sp),d2			; k >= 8
	move.l	48(sp),a2
	lsr.l	#3,d2
	subq.l	#1,d2
	moveq	#0,d3				; Spitzenpegel
.ol:	MOUT
	move.b	d4,d1				; Sample 0 der 8: |links| für den Spitzenpegel
	extb.l	d1
	bpl	.op
	neg.l	d1
.op:	cmp.l	d3,d1
	ble	.oq
	move.l	d1,d3
.oq:	MOUT
	MOUT
	MOUT
	move.l	d4,(a3)+
	move.l	d5,(a4)+
	MOUT
	MOUT
	MOUT
	MOUT
	move.l	d4,(a3)+
	move.l	d5,(a4)+
	dbra	d2,.ol
	move.l	d3,d0
	movem.l	(sp)+,d2-d5/a2-a4
	rts

; void mix_tab68k(int32_t *lr, const int8_t *tl, const int8_t *tr): lr[u] = (tl[u] << 16) + tr[u], u = 0..255
	xdef	_mix_tab68k
	xdef	mix_tab68k
_mix_tab68k:
mix_tab68k:
	movem.l	d2-d4/a2,-(sp)
	move.l	20(sp),a0			; lr
	move.l	24(sp),a2			; tl
	move.l	28(sp),a1			; tr
	moveq	#63,d2
mt_l:	move.b	(a2)+,d0
	extb.l	d0
	swap	d0
	clr.w	d0
	move.b	(a1)+,d1
	extb.l	d1
	add.l	d1,d0
	move.b	(a2)+,d3
	extb.l	d3
	swap	d3
	clr.w	d3
	move.b	(a1)+,d4
	extb.l	d4
	add.l	d4,d3
	move.l	d0,(a0)+
	move.l	d3,(a0)+
	move.b	(a2)+,d0
	extb.l	d0
	swap	d0
	clr.w	d0
	move.b	(a1)+,d1
	extb.l	d1
	add.l	d1,d0
	move.b	(a2)+,d3
	extb.l	d3
	swap	d3
	clr.w	d3
	move.b	(a1)+,d4
	extb.l	d4
	add.l	d4,d3
	move.l	d0,(a0)+
	move.l	d3,(a0)+
	dbra	d2,mt_l
	movem.l	(sp)+,d2-d4/a2
	rts


; ---------------------------------------------------------------------------------------------------------------
; THE CONTROL (mixer.c in vasm): the voices, their levels and tables, render_acc, the Paula output
MIX_VOICES equ	16
V_PCM	equ	0
V_LEN	equ	4
V_BASE	equ	8
V_POS	equ	12
V_STP	equ	16
V_LS	equ	20
V_LE	equ	24
V_LV	equ	28
V_RV	equ	32
V_VOL	equ	36
V_PAN	equ	40
V_LOOPS	equ	44
V_ACT	equ	48
V_TLV	equ	52
V_TRV	equ	56
V_LR	equ	60
V_SIZE	equ	1088

; void mx_init(uint32_t mixrate): the level tables (s_tab[l][u] = (u - 128) l / 64), the soft limit (linear to 80,
; then towards 127: 80 + 47 (a - 80) / ((a - 80) + 47)), every voice off
	xdef	_mx_init
	xdef	mx_init
_mx_init:
mx_init:
	movem.l	d2-d4/a2,-(sp)
	move.l	16+4(sp),d0
	bne.s	mi_1
	move.l	#11025,d0
mi_1:	move.l	d0,s_rate
	lea	s_tab,a0			; the levels
	moveq	#0,d2				; l
mi_l:	moveq	#0,d3				; u
mi_u:	move.l	d3,d0
	sub.l	#128,d0
	muls.l	d2,d0
	divsl.l	#64,d0:d0
	move.b	d0,(a0)+
	addq.l	#1,d3
	cmp.l	#256,d3
	blt.s	mi_u
	addq.l	#1,d2
	cmp.l	#64,d2
	ble.s	mi_l
	lea	s_clamp,a0			; the soft limit, x = -2048 .. 2047
	move.l	#-2048,d2
mi_c:	move.l	d2,d0
	bpl.s	mi_c1
	neg.l	d0
mi_c1:	cmp.l	#80,d0
	ble.s	mi_c2
	sub.l	#80,d0				; a - 80
	move.l	d0,d1
	add.l	#47,d1
	mulu.l	#47,d0
	divu.l	d1,d0
	add.l	#80,d0
mi_c2:	tst.l	d2
	bpl.s	mi_c3
	neg.l	d0
mi_c3:	move.b	d0,(a0)+
	addq.l	#1,d2
	cmp.l	#2048,d2
	blt.s	mi_c
	lea	s_v,a0				; the voices off, no table
	move.l	#MIX_VOICES*V_SIZE/4-1,d0
mi_z:	clr.l	(a0)+
	dbra	d0,mi_z
	lea	s_v,a0
	moveq	#MIX_VOICES-1,d0
	moveq	#-1,d1
mi_t:	move.l	d1,V_TLV(a0)
	move.l	d1,V_TRV(a0)
	lea	V_SIZE(a0),a0
	dbra	d0,mi_t
	movem.l	(sp)+,d2-d4/a2
	rts

; a0 the voice, d0 vol, d1 pan (0..127, 64 the middle): l = vol (127 - pan) / 64, r = vol pan / 64, each at most 127,
; vol first through the master; the levels l 64 / 127, r 64 / 127 (d0-d3 used)
mx_levels:
	move.l	d0,V_VOL(a0)
	move.l	d1,V_PAN(a0)
	muls.l	s_master,d0
	divsl.l	#127,d0:d0
	tst.l	d0
	bpl.s	ml_1
	moveq	#0,d0
ml_1:	cmp.l	#127,d0
	ble.s	ml_2
	moveq	#127,d0
ml_2:	tst.l	d1
	bpl.s	ml_3
	moveq	#0,d1
ml_3:	cmp.l	#127,d1
	ble.s	ml_4
	moveq	#127,d1
ml_4:	moveq	#127,d2				; l
	sub.l	d1,d2
	muls.l	d0,d2
	divsl.l	#64,d2:d2
	move.l	d0,d3				; r
	muls.l	d1,d3
	divsl.l	#64,d3:d3
	cmp.l	#127,d2
	ble.s	ml_5
	moveq	#127,d2
ml_5:	cmp.l	#127,d3
	ble.s	ml_6
	moveq	#127,d3
ml_6:	lsl.l	#6,d2
	divsl.l	#127,d2:d2
	move.l	d2,V_LV(a0)
	lsl.l	#6,d3
	divsl.l	#127,d3:d3
	move.l	d3,V_RV(a0)
	rts

; d0 = (rate << 16) / s_rate, exactly, without a 64-bit division: (rate / s) << 16 + ((rate % s) << 16) / s
mx_step:
	move.l	s_rate,d1
	divul.l	d1,d2:d0			; d0 = rate / s, d2 = rate % s
	swap	d0
	clr.w	d0
	swap	d2
	clr.w	d2
	divu.l	d1,d2
	add.l	d2,d0
	rts

; void mx_play(int voice, const uint8_t *pcm, uint32_t len, uint32_t rate, int vol, int pan, uint32_t loop_start,
;              uint32_t loop_len, int loops)
	xdef	_mx_play
	xdef	mx_play
_mx_play:
mx_play:
	movem.l	d2-d4/a2,-(sp)
	lea	16+4(sp),a1
	move.l	(a1)+,d0			; voice
	cmp.l	#MIX_VOICES,d0
	bhs	mp_x
	mulu.l	#V_SIZE,d0
	lea	s_v,a0
	add.l	d0,a0
	clr.l	V_ACT(a0)
	move.l	(a1)+,V_PCM(a0)
	move.l	(a1)+,V_LEN(a0)
	clr.l	V_POS(a0)
	clr.l	V_BASE(a0)
	move.l	(a1)+,d0			; rate
	move.l	d2,-(sp)
	bsr.s	mx_step
	move.l	(sp)+,d2
	move.l	d0,V_STP(a0)
	move.l	(a1)+,d0			; vol, pan
	move.l	(a1)+,d1
	move.l	a1,-(sp)
	bsr	mx_levels
	move.l	(sp)+,a1
	move.l	(a1)+,d2			; loop_start
	move.l	(a1)+,d3			; loop_len
	move.l	V_LEN(a0),d4
	tst.l	d3				; none, or past the end: the whole sample
	beq.s	mp_1
	cmp.l	d4,d2
	blo.s	mp_2
mp_1:	moveq	#0,d2
	move.l	d4,d3
mp_2:	move.l	d2,d0				; not past the end
	add.l	d3,d0
	cmp.l	d4,d0
	bls.s	mp_3
	move.l	d4,d3
	sub.l	d2,d3
mp_3:	move.l	d2,V_LS(a0)
	add.l	d2,d3
	move.l	d3,V_LE(a0)
	move.l	(a1),V_LOOPS(a0)
	moveq	#0,d0				; active = pcm && len
	tst.l	V_PCM(a0)
	beq.s	mp_4
	tst.l	d4
	beq.s	mp_4
	moveq	#1,d0
mp_4:	move.l	d0,V_ACT(a0)
mp_x:	movem.l	(sp)+,d2-d4/a2
	rts

; void mx_set(int voice, uint32_t rate, int vol, int pan)
	xdef	_mx_set
	xdef	mx_set
_mx_set:
mx_set:
	movem.l	d2-d3,-(sp)
	move.l	8+4(sp),d0
	cmp.l	#MIX_VOICES,d0
	bhs.s	ms_x
	mulu.l	#V_SIZE,d0
	lea	s_v,a0
	add.l	d0,a0
	move.l	8+8(sp),d0
	bsr	mx_step
	move.l	d0,V_STP(a0)
	move.l	8+12(sp),d0
	move.l	8+16(sp),d1
	bsr	mx_levels
ms_x:	movem.l	(sp)+,d2-d3
	rts

; void mx_master(int vol): 0..127 on every voice
	xdef	_mx_master
	xdef	mx_master
_mx_master:
mx_master:
	movem.l	d2-d4,-(sp)
	move.l	12+4(sp),d0
	bpl.s	mm_1
	moveq	#0,d0
mm_1:	cmp.l	#127,d0
	ble.s	mm_2
	moveq	#127,d0
mm_2:	move.l	d0,s_master
	lea	s_v,a0
	moveq	#MIX_VOICES-1,d4
mm_l:	move.l	V_VOL(a0),d0
	move.l	V_PAN(a0),d1
	bsr	mx_levels
	lea	V_SIZE(a0),a0
	dbra	d4,mm_l
	movem.l	(sp)+,d2-d4
	rts

; void mx_stop(int voice); int mx_active(int voice)
	xdef	_mx_stop
	xdef	mx_stop
_mx_stop:
mx_stop:
	move.l	4(sp),d0
	cmp.l	#MIX_VOICES,d0
	bhs.s	mt_x
	mulu.l	#V_SIZE,d0
	lea	s_v,a0
	clr.l	V_ACT(a0,d0.l)
mt_x:	rts
	xdef	_mx_active
	xdef	mx_active
_mx_active:
mx_active:
	move.l	4(sp),d1
	moveq	#0,d0
	cmp.l	#MIX_VOICES,d1
	bhs.s	ma_x
	mulu.l	#V_SIZE,d1
	lea	s_v,a0
	move.l	V_ACT(a0,d1.l),d0
ma_x:	rts

; render_acc: the voices of a block (d0 = k <= 1024) summed into s_acc; the first active voice stores instead of
; adding, what it leaves is cleared after it.  Locals: the voice's base, pos, loops, active, i, first
RA_BASE	equ	0
RA_POS	equ	4
RA_LOOPS equ	8
RA_ACT	equ	12
RA_I	equ	16
RA_FIRST equ	20
RA_K	equ	24
RA_LOC	equ	28
render_acc:
	movem.l	d2-d7/a2-a5,-(sp)
	lea	-RA_LOC(sp),sp
	move.l	d0,RA_K(sp)
	move.l	#1,RA_FIRST(sp)
	lea	s_v,a4
	moveq	#0,d7				; vi
ra_v:	tst.l	V_ACT(a4)
	beq	ra_vn
	move.l	V_LV(a4),d0			; the voice's table, if its levels changed
	cmp.l	V_TLV(a4),d0
	bne.s	ra_t
	move.l	V_RV(a4),d1
	cmp.l	V_TRV(a4),d1
	beq.s	ra_t1
ra_t:	move.l	V_RV(a4),d1
	move.l	d1,V_TRV(a4)
	move.l	d0,V_TLV(a4)
	lsl.l	#8,d1
	lea	s_tab,a0
	pea	(a0,d1.l)
	lsl.l	#8,d0
	pea	(a0,d0.l)
	pea	V_LR(a4)
	bsr	mix_tab68k
	lea	12(sp),sp
ra_t1:	move.l	V_BASE(a4),RA_BASE(sp)
	move.l	V_POS(a4),RA_POS(sp)
	move.l	V_LOOPS(a4),RA_LOOPS(sp)
	move.l	#1,RA_ACT(sp)
	clr.l	RA_I(sp)
	move.l	V_PCM(a4),a3			; pcm
	lea	V_LR(a4),a2			; lr
	move.l	V_STP(a4),d6			; stp
ra_w:	move.l	RA_I(sp),d0
	cmp.l	RA_K(sp),d0
	bhs	ra_we
	move.l	V_LEN(a4),d5			; end = loops ? le : len
	tst.l	RA_LOOPS(sp)
	beq.s	ra_w1
	move.l	V_LE(a4),d5
ra_w1:	move.l	RA_POS(sp),d4			; p = base + (pos >> 16)
	clr.w	d4
	swap	d4
	add.l	RA_BASE(sp),d4
	cmp.l	d5,d4
	bhs.s	ra_one
	cmp.l	#$400000,d6
	bls	ra_run
ra_one:	cmp.l	d5,d4				; one sample at a time: the end, a loop, a huge step
	blo.s	ra_o3
	tst.l	RA_LOOPS(sp)
	beq.s	ra_o1
	move.l	V_LE(a4),d0
	move.l	V_LS(a4),d1
	cmp.l	d1,d0
	bls.s	ra_o1
	sub.l	d1,d0				; p = ls + (p - ls) % (le - ls)
	move.l	d4,d2
	sub.l	d1,d2
	divul.l	d0,d3:d2
	move.l	d1,d4
	add.l	d3,d4
	tst.l	RA_LOOPS(sp)
	ble.s	ra_o3
	subq.l	#1,RA_LOOPS(sp)
	bra.s	ra_o3
ra_o1:	cmp.l	V_LEN(a4),d4
	bhs	ra_off
ra_o3:	cmp.l	V_LEN(a4),d4			; never past the sample
	bhs	ra_off
	moveq	#0,d0
	move.b	(a3,d4.l),d0
	move.l	(a2,d0.l*4),d0
	move.l	RA_I(sp),d1
	lea	s_acc,a0
	tst.l	RA_FIRST(sp)
	beq.s	ra_o4
	move.l	d0,(a0,d1.l*4)
	bra.s	ra_o5
ra_o4:	add.l	d0,(a0,d1.l*4)
ra_o5:	addq.l	#1,RA_I(sp)
	move.l	RA_POS(sp),d0			; fr = (pos & 0xffff) + (stp & 0xffff)
	and.l	#$ffff,d0
	move.l	d6,d1
	and.l	#$ffff,d1
	add.l	d1,d0
	move.l	d6,d1				; p += (stp >> 16) + (fr >> 16)
	clr.w	d1
	swap	d1
	add.l	d1,d4
	move.l	d0,d1
	clr.w	d1
	swap	d1
	add.l	d1,d4
	move.l	d4,d1				; base = p & ~0x7fff, pos = (p - base) << 16 | (fr & 0xffff)
	and.l	#$ffff8000,d1
	move.l	d1,RA_BASE(sp)
	sub.l	d1,d4
	swap	d4
	clr.w	d4
	and.l	#$ffff,d0
	or.l	d0,d4
	move.l	d4,RA_POS(sp)
	bra	ra_w
ra_run:	move.l	RA_POS(sp),d0			; the window kept below 32K
	cmp.l	#$80000000,d0
	blo.s	ra_r1
	move.l	d4,d1
	and.l	#$ffff8000,d1
	move.l	d1,RA_BASE(sp)
	move.l	d4,d2
	sub.l	d1,d2
	swap	d2
	clr.w	d2
	and.l	#$ffff,d0
	or.l	d2,d0
	move.l	d0,RA_POS(sp)
ra_r1:	sub.l	RA_BASE(sp),d5			; lend = end - base, at most (0xffffffff - stp) >> 16
	moveq	#-1,d0
	sub.l	d6,d0
	clr.w	d0
	swap	d0
	cmp.l	d0,d5
	bls.s	ra_r2
	move.l	d0,d5
ra_r2:	move.l	RA_K(sp),d3			; m = k - i, at most what the room holds
	sub.l	RA_I(sp),d3
	tst.l	d6
	beq.s	ra_r3
	swap	d5				; room = (lend << 16) - pos
	clr.w	d5
	sub.l	RA_POS(sp),d5
	subq.l	#1,d5				; can = (room - 1) / stp + 1
	divu.l	d6,d5
	addq.l	#1,d5
	cmp.l	d3,d5
	bhs.s	ra_r3
	move.l	d5,d3
ra_r3:	move.l	d3,-(sp)			; mix_voice(set)68k(acc + i, pcm + base, lr, &pos, stp, m)
	move.l	d6,-(sp)
	pea	RA_POS+8(sp)
	move.l	a2,-(sp)
	move.l	a3,d0
	add.l	RA_BASE+16(sp),d0
	move.l	d0,-(sp)
	move.l	RA_I+20(sp),d0
	lea	s_acc,a0
	pea	(a0,d0.l*4)
	tst.l	RA_FIRST+24(sp)
	beq.s	ra_r4
	bsr	mix_voiceset68k
	bra.s	ra_r5
ra_r4:	bsr	mix_voice68k
ra_r5:	lea	24(sp),sp
	add.l	d3,RA_I(sp)
	bra	ra_w
ra_off:	clr.l	RA_ACT(sp)
ra_we:	move.l	RA_BASE(sp),V_BASE(a4)
	move.l	RA_POS(sp),V_POS(a4)
	move.l	RA_LOOPS(sp),V_LOOPS(a4)
	move.l	RA_ACT(sp),V_ACT(a4)
	tst.l	RA_FIRST(sp)			; the first: what it left cleared
	beq.s	ra_vn
	clr.l	RA_FIRST(sp)
	move.l	RA_I(sp),d0
	bsr	ra_zero
ra_vn:	lea	V_SIZE(a4),a4
	addq.l	#1,d7
	cmp.l	#MIX_VOICES,d7
	blt	ra_v
	tst.l	RA_FIRST(sp)			; none active: all cleared
	beq.s	ra_x
	moveq	#0,d0
	bsr	ra_zero
ra_x:	lea	RA_LOC(sp),sp
	movem.l	(sp)+,d2-d7/a2-a5
	rts
; s_acc[d0 .. k) = 0 (the caller's locals at 4(sp))
ra_zero:
	move.l	RA_K+4(sp),d1
	sub.l	d0,d1
	bls.s	rz_x
	lea	s_acc,a0
	lea	(a0,d0.l*4),a0
	subq.l	#1,d1
rz_l:	clr.l	(a0)+
	dbra	d1,rz_l
rz_x:	rts

; int mx_render_l(int8_t *left, int8_t *right, uint32_t n): n samples a side (a multiple of 8, the targets long-word
; aligned: Paula's chip buffers), in blocks of 1024; returns the peak max |left[i]|, i = 0, 8, 16, ...
	xdef	_mx_render_l
	xdef	mx_render_l
_mx_render_l:
mx_render_l:
	movem.l	d2-d4/a2-a3,-(sp)
	movem.l	20+4(sp),a2/a3			; left, right
	move.l	20+12(sp),d3			; n
	moveq	#0,d4				; the peak
mr_l:	tst.l	d3
	beq.s	mr_x
	move.l	d3,d2				; k
	cmp.l	#1024,d2
	bls.s	mr_1
	move.l	#1024,d2
mr_1:	move.l	d2,d0
	bsr	render_acc
	pea	s_clamp+2048
	move.l	d2,-(sp)
	move.l	a3,-(sp)
	move.l	a2,-(sp)
	pea	s_acc
	bsr	mix_outl68k
	lea	20(sp),sp
	cmp.l	d4,d0
	ble.s	mr_2
	move.l	d0,d4
mr_2:	add.l	d2,a2
	add.l	d2,a3
	sub.l	d2,d3
	bra.s	mr_l
mr_x:	move.l	d4,d0
	movem.l	(sp)+,d2-d4/a2-a3
	rts

	section	data,data
	cnop	0,4
s_rate:	dc.l	11025
s_master: dc.l	127
	section	bss,bss
	cnop	0,4
s_v:	ds.b	MIX_VOICES*V_SIZE
s_acc:	ds.l	1024
s_tab:	ds.b	65*256
s_clamp: ds.b	4096
