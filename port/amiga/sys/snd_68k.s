; snd_68k.s - THE GAME'S SOUND ON THE AMIGA, in vasm.
;
;  - The effects: port/src/sound.c's calls (snd_play / stop / playing / pitch / volume / pan / swap / play_once /
;    masters / forget, the game's 0x1f708 ...) on top of the mixer (mixer_68k.s, mx_*): 16 voices, a handle
;    = serial << 4 | voice, so a stale handle does nothing; a voice the mixer has played to its end is free again (the
;    commentary waits for that).  Volume = the sample's (SFXSBASE.DTR) until the game sets the voice's own (distance)
;    -> 0..127, pan -1..+1 -> 0..127 (63 the middle), pitch 16.16 -> Hz of the 11025 Hz samples; the game's effects
;    master (1 = 0x6000 of 0x7fff) -> the mixer's master 95 (levels, snd_masters).
;  - The output: a process of its own (prio 21) with audio.device channels 0 (left) / 1 (right), 3 x 512 samples of
;    chip memory each, period (clock + 7800) / 15625 (~15.6 kHz), each buffer mixed straight into chip memory
;    (mx_render_l) under a SignalSemaphore against the game's calls.
;  - The music: the CD's tracks as files (<data>/MUSIC/trackNN.raw, "SMUS", rate,
;    block B, length; then B bytes left + B bytes right, 8 bit signed, 22050 Hz), streamed by a second process (prio 20)
;    onto channels 3 (left) / 2 (right), 3 chip buffers a side, read by dos.library straight into them; commands from
;    the game through a semaphore + CTRL_D; the end of the file = from the top again.  The game's MUSICn = track n+1
;    (the CD's numbering, song_for() in main.c); its volume (the CD's, 1 = 0x6000) -> Paula's 0..64.
;  The samples are loaded by amiga/snd_load.c into snd_tab here (40 bytes a sample); no C symbol is used from here
;  (the Amiga's names have '_', the qemu test's not), dos.library is opened here.
;
; C calling: arguments on the stack, d0/d1/a0/a1/fp0/fp1 free, d0 the result.

MIX_VOICES	equ	16
SM_DATA		equ	0			; snd_tab: a sample
SM_LEN		equ	4
SM_VOL		equ	8			; float 0..1
SM_LOOP		equ	12			; -1 for ever, 0 once, n times round
SM_LS		equ	16
SM_LL		equ	20
SM_SIZE		equ	40

; exec / dos / graphics
LVO_Forbid	equ	-132
LVO_FindTask	equ	-294
LVO_SetSignal	equ	-306
LVO_Wait	equ	-318
LVO_Signal	equ	-324
LVO_AllocSignal	equ	-330
LVO_FreeSignal	equ	-336
LVO_CloseLibrary equ	-414
LVO_OpenDevice	equ	-444
LVO_CloseDevice	equ	-450
LVO_CheckIO	equ	-468
LVO_WaitIO	equ	-474
LVO_AbortIO	equ	-480
LVO_OpenLibrary	equ	-552
LVO_InitSemaphore equ	-558
LVO_ObtainSemaphore equ	-564
LVO_ReleaseSemaphore equ -570
LVO_CreateIORequest equ	-654
LVO_DeleteIORequest equ	-660
LVO_CreateMsgPort equ	-666
LVO_DeleteMsgPort equ	-672
LVO_AllocVec	equ	-684
LVO_FreeVec	equ	-690
LVO_Open	equ	-30
LVO_Close	equ	-36
LVO_Read	equ	-42
LVO_Seek	equ	-66
LVO_CreateNewProc equ	-498
DEV_BEGINIO	equ	-30

LN_PRI		equ	9
MN_REPLYPORT	equ	14
IO_DEVICE	equ	20
IO_UNIT		equ	24
IO_COMMAND	equ	28
IO_FLAGS	equ	30
IOA_DATA	equ	34
IOA_LENGTH	equ	38
IOA_PERIOD	equ	42
IOA_VOLUME	equ	44
IOA_CYCLES	equ	46
IOA_SIZE	equ	68
MP_SIGBIT	equ	15
GFX_DISPLAYFLAGS equ	206
PAL		equ	4
CMD_WRITE	equ	3
ADIOF_PERVOL	equ	16
ADIOF_NOWAIT	equ	64
MEMF_CHIP_CLEAR	equ	$10002
MEMF_ANY_CLEAR	equ	$10000
SIGF_C		equ	$1000			; CTRL_C
SIGF_D		equ	$2000			; CTRL_D
NP_Entry	equ	$800003eb
NP_Name		equ	$800003f4
NP_Priority	equ	$800003f5
NP_StackSize	equ	$800003f3
MODE_OLDFILE	equ	1005
OFFSET_BEGINNING equ	-1

SND_BUFS	equ	3
SND_LEN		equ	512
MUS_BUFS	equ	3
MUS_HDR		equ	16
MUS_MAXB	equ	16384

	xref	_mx_init
	xref	_mx_play
	xref	_mx_set
	xref	_mx_master
	xref	_mx_stop
	xref	_mx_active
	xref	_mx_render_l

	section	code,code

; ---------------------------------------------------------------- the semaphore round the mixer (only when it plays)
lock:
	tst.l	snd_on
	beq.s	.x
	movem.l	d0-d1/a0-a1/a6,-(sp)
	lea	snd_sem,a0
	move.l	4.w,a6
	jsr	LVO_ObtainSemaphore(a6)
	movem.l	(sp)+,d0-d1/a0-a1/a6
.x:	rts
unlock:
	tst.l	snd_on
	beq.s	.x
	movem.l	d0-d1/a0-a1/a6,-(sp)
	lea	snd_sem,a0
	move.l	4.w,a6
	jsr	LVO_ReleaseSemaphore(a6)
	movem.l	(sp)+,d0-d1/a0-a1/a6
.x:	rts

; d0 = handle -> d0 = its voice, or -1 (no such voice, or it has ended); keeps d1-d7/a0-a6
voice_of:
	tst.l	d0
	ble.s	.no
	move.l	d1,-(sp)
	moveq	#MIX_VOICES-1,d1
	and.l	d0,d1
	lea	v_handle,a1
	cmp.l	(a1,d1.l*4),d0
	bne.s	.no1
	move.l	d1,d0
	movem.l	d0/a0,-(sp)
	move.l	d0,-(sp)
	jsr	_mx_active
	addq.l	#4,sp
	tst.l	d0
	movem.l	(sp)+,d0/a0
	beq.s	.no1
	move.l	(sp)+,d1
	rts
.no1:	move.l	(sp)+,d1
.no:	moveq	#-1,d0
	rts

; d0 = sample number -> a0 = its snd_tab row, Z clear; Z set when there is none (number out of range, no data)
sample_of:
	tst.l	d0
	bmi.s	.no
	cmp.l	snd_n,d0
	bge.s	.no
	move.l	d0,d1
	mulu.w	#SM_SIZE,d1
	lea	snd_tab,a0
	add.l	d1,a0
	tst.l	SM_DATA(a0)
	rts
.no:	moveq	#0,d1				; Z set
	rts

; d2 = voice -> d0 = its volume 0..127, d1 = its pan 0..127 (from v_sample / v_gain / v_pan):
; the volume is the game's 0..0x7fff -- the voice's own once the game has set one (as the
; driver: a voice's volume REPLACES the sample's; v_gain < 0 = none set, the sample's SFXSBASE.DTR one) -- times
; 127 / 0x7fff, cut; the pan the game's 0x8000 +- 32767 x pan (cut) times 127 / 0xffff, cut (the middle = 63).
levels:
	lea	v_gain,a0
	fmove.s	(a0,d2.l*4),fp0
	ftst.x	fp0
	fbge.w	.g				; the game's own for this voice
	lea	v_sample,a0
	move.l	(a0,d2.l*4),a0
	fmove.s	SM_VOL(a0),fp0
.g:	fmul.s	#32767.0,fp0
	fmove.l	fp0,d0				; back to the game's 0..0x7fff (to the nearest)
	tst.l	d0
	bpl.s	.v0
	moveq	#0,d0
.v0:	cmp.l	#32767,d0
	ble.s	.v1
	move.l	#32767,d0
.v1:	mulu.l	#127,d0
	divu.l	#32767,d0
	lea	v_pan,a0
	fmove.s	(a0,d2.l*4),fp0
	fmul.s	#32767.0,fp0
	fintrz.x	fp0
	fmove.l	fp0,d1
	cmp.l	#-32767,d1
	bge.s	.p0
	move.l	#-32767,d1
.p0:	cmp.l	#32767,d1
	ble.s	.p1
	move.l	#32767,d1
.p1:	add.l	#$8000,d1			; 1 .. $ffff
	mulu.l	#127,d1
	divu.l	#65535,d1
	rts

; d2 = voice: the mixer told its rate, volume, pan
vset:
	bsr	levels
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	lea	v_rate,a0
	move.l	(a0,d2.l*4),-(sp)
	move.l	d2,-(sp)
	jsr	_mx_set
	lea	16(sp),sp
	rts

; d2 = voice, v_sample[d2] the sample: the mixer starts it from its beginning
vstart:
	bsr	levels
	lea	v_sample,a0
	move.l	(a0,d2.l*4),a0
	move.l	SM_LOOP(a0),-(sp)
	move.l	SM_LL(a0),-(sp)
	move.l	SM_LS(a0),-(sp)
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	lea	v_rate,a1
	move.l	(a1,d2.l*4),-(sp)
	move.l	SM_LEN(a0),-(sp)
	move.l	SM_DATA(a0),-(sp)
	move.l	d2,-(sp)
	jsr	_mx_play
	lea	36(sp),sp
	rts

; int snd_play(int id): 0x1f708; a handle, -1 = none
	xdef	_snd_play
	xdef	snd_play
_snd_play:
snd_play:
	movem.l	d2-d3/a2,-(sp)
	move.l	12+4(sp),d0
	bsr	sample_of
	beq.s	.none
	move.l	a0,a2
	bsr	lock
	moveq	#0,d2
.find:	move.l	d2,-(sp)
	jsr	_mx_active
	addq.l	#4,sp
	tst.l	d0
	beq.s	.free
	addq.l	#1,d2
	cmp.w	#MIX_VOICES,d2
	blo.s	.find
	bsr	unlock
.none:	moveq	#-1,d0
	movem.l	(sp)+,d2-d3/a2
	rts
.free:	move.l	v_serial,d3
	addq.l	#1,d3
	and.l	#$07ffffff,d3
	bne.s	.s1
	moveq	#1,d3
.s1:	move.l	d3,v_serial
	lsl.l	#4,d3
	or.l	d2,d3				; the handle
	lea	v_handle,a0
	move.l	d3,(a0,d2.l*4)
	lea	v_sample,a0
	move.l	a2,(a0,d2.l*4)
	lea	v_gain,a0
	move.l	#$bf800000,(a0,d2.l*4)		; -1.0: none set yet, the sample's volume
	lea	v_pan,a0
	clr.l	(a0,d2.l*4)
	lea	v_rate,a0
	move.l	#11025,(a0,d2.l*4)		; as recorded
	bsr	vstart
	bsr	unlock
	move.l	d3,d0
	movem.l	(sp)+,d2-d3/a2
	rts

; int snd_stop(int handle): 0x1f870; -1, the "no voice" handle, as the game's
	xdef	_snd_stop
	xdef	snd_stop
_snd_stop:
snd_stop:
	bsr	lock
	move.l	4(sp),d0
	bsr	voice_of
	tst.l	d0
	bmi.s	.x
	lea	v_handle,a0
	clr.l	(a0,d0.l*4)
	move.l	d0,-(sp)
	jsr	_mx_stop
	addq.l	#4,sp
.x:	bsr	unlock
	moveq	#-1,d0
	rts

; int snd_playing(int handle)
	xdef	_snd_playing
	xdef	snd_playing
_snd_playing:
snd_playing:
	bsr	lock
	move.l	4(sp),d0
	bsr	voice_of
	bsr	unlock
	not.l	d0				; -1 -> 0
	beq.s	.x
	moveq	#1,d0
.x:	rts

; void snd_pitch(int handle, int pitch): 0x1f7d4, 16.16, 0x10000 = the sample as recorded (11025 Hz)
	xdef	_snd_pitch
	xdef	snd_pitch
_snd_pitch:
snd_pitch:
	move.l	d2,-(sp)
	bsr	lock
	move.l	4+4(sp),d0
	bsr	voice_of
	move.l	d0,d2
	bmi.s	.x
	move.l	4+8(sp),d0
	bgt.s	.p
	moveq	#1,d0
.p:	move.l	d0,d1
	clr.w	d1
	swap	d1				; whole part
	and.l	#$ffff,d0			; fraction
	mulu.l	#11025,d1
	mulu.l	#11025,d0
	clr.w	d0
	swap	d0
	add.l	d1,d0				; pitch * 11025 >> 16, no 64-bit product
	lea	v_rate,a0
	move.l	d0,(a0,d2.l*4)
	bsr	vset
.x:	bsr	unlock
	move.l	(sp)+,d2
	rts

; void snd_volume(int handle, float gain): the voice's own loudness, 0..1
	xdef	_snd_volume
	xdef	snd_volume
_snd_volume:
snd_volume:
	lea	v_gain,a1
	moveq	#0,d1				; clamp 0..1
	bra.s	vf_set

; void snd_pan(int handle, float pan): 0xc6670, -1 left .. +1 right
	xdef	_snd_pan
	xdef	snd_pan
_snd_pan:
snd_pan:
	lea	v_pan,a1
	moveq	#1,d1				; clamp -1..1
vf_set:
	move.l	d2,-(sp)
	fmove.s	4+8(sp),fp0
	fcmp.s	#1.0,fp0
	fble.w	.c1
	fmove.s	#1.0,fp0
.c1:	tst.l	d1
	bne.s	.cp
	ftst.x	fp0
	fbge.w	.c2
	fmove.s	#0.0,fp0
	bra.s	.c2
.cp:	fcmp.s	#-1.0,fp0
	fbge.w	.c2
	fmove.s	#-1.0,fp0
.c2:	bsr	lock
	move.l	4+4(sp),d0
	move.l	a1,-(sp)
	bsr	voice_of
	move.l	(sp)+,a1
	move.l	d0,d2
	bmi.s	.x
	fmove.s	fp0,(a1,d2.l*4)
	bsr	vset
.x:	bsr	unlock
	move.l	(sp)+,d2
	rts

; void snd_swap(int handle, int id): 0x1f754, the same voice carries on with another sample (at its pitch)
	xdef	_snd_swap
	xdef	snd_swap
_snd_swap:
snd_swap:
	movem.l	d2/a2,-(sp)
	move.l	8+8(sp),d0
	bsr	sample_of
	beq.s	.n
	move.l	a0,a2
	bsr	lock
	move.l	8+4(sp),d0
	bsr	voice_of
	move.l	d0,d2
	bmi.s	.x
	lea	v_sample,a0
	cmp.l	(a0,d2.l*4),a2
	beq.s	.x
	move.l	a2,(a0,d2.l*4)
	bsr	vstart
.x:	bsr	unlock
.n:	movem.l	(sp)+,d2/a2
	rts

; int snd_play_once(int id, int handle): 0x1f79c, start it unless this handle is already playing it
	xdef	_snd_play_once
	xdef	snd_play_once
_snd_play_once:
snd_play_once:
	move.l	a2,-(sp)
	move.l	4+4(sp),d0
	bsr	sample_of
	beq.s	.new
	move.l	a0,a2
	bsr	lock
	move.l	4+8(sp),d0
	bsr	voice_of
	tst.l	d0
	bmi.s	.new1
	lea	v_sample,a0
	cmp.l	(a0,d0.l*4),a2
	bne.s	.new1
	bsr	unlock
	move.l	4+8(sp),d0
	move.l	(sp)+,a2
	rts
.new1:	bsr	unlock
.new:	move.l	(sp)+,a2
	bra	snd_play			; (its id is where snd_play wants it)

; void snd_masters(float effects, float music): 0x1f93c, 1 = where the game starts them (0x6000 of 0x7fff).
; Each back to the game's 0..0x7fff, times 127 / 0x7fff (cut) -- the effects' = the mixer's master (0x6000 -> 95);
; the music's, under 96, x 64 / 96 (cut), 96 and over Paula's full 64 (0x6000 -> 95 -> 63).  The music = the CD
; volume alone (main.c MUSIC_MASTER: a MIDI volume would move nothing).
	xdef	_snd_masters
	xdef	snd_masters
_snd_masters:
snd_masters:
	fmove.s	4(sp),fp0
	bsr.s	vol127
	move.l	d0,-(sp)
	bsr	lock
	jsr	_mx_master
	bsr	unlock
	addq.l	#4,sp
	fmove.s	8(sp),fp0
	bsr.s	vol127
	moveq	#64,d1
	cmp.l	#96,d0
	bge.s	.m1
	move.l	d0,d1
	lsl.l	#6,d1				; x 64
	divu.l	#96,d1
.m1:	move.l	d1,mus_vol
	rts
; fp0 = a master (1 = 0x6000) -> d0 = the game's number x 127 / 0x7fff, 0..127
vol127:
	fmul.s	#24576.0,fp0
	fmove.l	fp0,d0				; (to the nearest)
	tst.l	d0
	bpl.s	.c0
	moveq	#0,d0
.c0:	cmp.l	#32767,d0
	ble.s	.c1
	move.l	#32767,d0
.c1:	mulu.l	#127,d0
	divu.l	#32767,d0
	rts
; void snd_halt(void): every voice stopped (before the samples are let go or loaded again)
	xdef	_snd_halt
	xdef	snd_halt
_snd_halt:
snd_halt:
	move.l	d2,-(sp)
	bsr	lock
	moveq	#MIX_VOICES-1,d2
.l:	lea	v_handle,a0
	clr.l	(a0,d2.l*4)
	move.l	d2,-(sp)
	jsr	_mx_stop
	addq.l	#4,sp
	dbf	d2,.l
	bsr	unlock
	move.l	(sp)+,d2
	rts

; void snd_forget(void): every sample let go, the device left open (the music plays on)
	xdef	_snd_forget
	xdef	snd_forget
_snd_forget:
snd_forget:
	bsr	snd_halt
	clr.l	snd_n
	rts

; ---------------------------------------------------------------- Screamer 2's CD calls: not in this build
	xdef	_snd_cd
	xdef	_snd_cd_track
	xdef	_snd_cd_paused
	xdef	_cd_audio_find
	xdef	_snd_cd_volume
	xdef	_snd_cd_pause
	xdef	snd_cd
	xdef	snd_cd_track
	xdef	snd_cd_paused
	xdef	cd_audio_find
	xdef	snd_cd_volume
	xdef	snd_cd_pause
_snd_cd:
_snd_cd_track:
_snd_cd_paused:
_cd_audio_find:
snd_cd:
snd_cd_track:
snd_cd_paused:
cd_audio_find:
	moveq	#0,d0
_snd_cd_volume:
_snd_cd_pause:
snd_cd_volume:
snd_cd_pause:
	rts

; ---------------------------------------------------------------- the output process
; int snd_dev_open(void): the mixer started at Paula's rate, the output and music processes running; 0 = sound
	xdef	_snd_dev_open
	xdef	snd_dev_open
_snd_dev_open:
snd_dev_open:
	movem.l	d2-d3/a2/a6,-(sp)
	tst.l	snd_on
	bne	.ok
	tst.l	snd_failed
	bne	.fail
	move.l	4.w,a6
	lea	dosname(pc),a1
	moveq	#36,d0
	jsr	LVO_OpenLibrary(a6)
	move.l	d0,dos_base
	beq	.fail1
	lea	gfxname(pc),a1			; Paula's clock: PAL or NTSC
	moveq	#0,d0
	jsr	LVO_OpenLibrary(a6)
	move.l	#3546895,d2
	tst.l	d0
	beq.s	.clk
	move.l	d0,a1
	btst	#2,GFX_DISPLAYFLAGS+1(a1)	; (PAL = 4, a word)
	bne.s	.pal
	move.l	#3579545,d2
.pal:	jsr	LVO_CloseLibrary(a6)
.clk:	move.l	d2,paula_clock
	move.l	d2,d0
	add.l	#7800,d0
	divu.l	#15625,d0
	move.l	d0,snd_period
	move.l	d2,d1
	divu.l	d0,d1
	move.l	d1,snd_rate
	move.l	d1,-(sp)
	jsr	_mx_init
	addq.l	#4,sp
	move.l	d2,d0				; music: 22050 Hz
	add.l	#11025,d0
	divu.l	#22050,d0
	move.l	d0,mus_period
	lea	snd_sem,a0
	jsr	LVO_InitSemaphore(a6)
	lea	mus_sem,a0
	jsr	LVO_InitSemaphore(a6)
	sub.l	a1,a1
	jsr	LVO_FindTask(a6)
	move.l	d0,main_task
	moveq	#-1,d0
	jsr	LVO_AllocSignal(a6)
	move.l	d0,sig_ready
	bmi	.fail1
	moveq	#0,d0
	move.l	sig_ready,d1
	bset	d1,d0
	move.l	d0,d1
	moveq	#0,d0
	jsr	LVO_SetSignal(a6)
	; AHI (SCREAMER_SND=ahi, snd_load.c sets snd_ahi_open): snd_ahi.c's process plays the mixer's sum and the music,
	; the commands of snd_music go to it (mus_task); it failing, Paula as ever
	move.l	snd_ahi_open,d0			; (a function of snd_ahi.c's: this file names no C symbol)
	beq.s	.paula
	move.l	d0,a0
	jsr	(a0)
	move.l	4.w,a6
	tst.l	d0
	beq.s	.paula
	move.l	d0,snd_task
	move.l	d0,mus_task
	move.l	#1,snd_ahi_on
	move.l	#1,snd_on
	bra	.ok
.paula:	; the output process
	clr.l	snd_quit
	clr.l	snd_state
	lea	snd_proc(pc),a0
	lea	sndname(pc),a1
	moveq	#21,d0
	move.l	#16384,d1
	bsr	newproc
	beq	.fail2
	move.l	d0,snd_task
	lea	snd_state,a2
	bsr	wait_state
	tst.l	snd_state
	bmi	.fail2
	move.l	#1,snd_on
	; the music's process (no music = the effects alone)
	clr.l	mus_quit
	clr.l	mus_state
	lea	mus_proc(pc),a0
	lea	musname(pc),a1
	moveq	#20,d0
	move.l	#8192,d1
	bsr	newproc
	beq.s	.ok
	move.l	d0,mus_task
	lea	mus_state,a2
	bsr	wait_state
	tst.l	mus_state
	bpl.s	.ok
	clr.l	mus_task
.ok:	moveq	#0,d0
	movem.l	(sp)+,d2-d3/a2/a6
	rts
.fail2:	move.l	sig_ready,d0
	jsr	LVO_FreeSignal(a6)
.fail1:	move.l	#1,snd_failed
.fail:	moveq	#-1,d0
	movem.l	(sp)+,d2-d3/a2/a6
	rts

; a0 = entry, a1 = name, d0 = priority, d1 = stack -> d0 = the process (Z when none); a6 = SysBase kept
newproc:
	movem.l	a6,-(sp)
	lea	np_tags,a6
	move.l	#NP_Entry,(a6)+
	move.l	a0,(a6)+
	move.l	#NP_Name,(a6)+
	move.l	a1,(a6)+
	move.l	#NP_Priority,(a6)+
	move.l	d0,(a6)+
	move.l	#NP_StackSize,(a6)+
	move.l	d1,(a6)+
	clr.l	(a6)
	move.l	d2,-(sp)
	move.l	#np_tags,d1
	move.l	dos_base,a6
	jsr	LVO_CreateNewProc(a6)
	move.l	(sp)+,d2
	movem.l	(sp)+,a6
	tst.l	d0
	rts

; a2 = a process' state: wait while it is 0 (starting) / 1 (running, for the end: see wait_end); a6 = SysBase
wait_state:
	tst.l	(a2)
	bne.s	.x
	moveq	#0,d0
	move.l	sig_ready,d1
	bset	d1,d0
	jsr	LVO_Wait(a6)
	bra.s	wait_state
.x:	rts
wait_end:
	cmp.l	#1,(a2)
	bne.s	.x
	moveq	#0,d0
	move.l	sig_ready,d1
	bset	d1,d0
	jsr	LVO_Wait(a6)
	bra.s	wait_end
.x:	rts

; signal the main task that a state changed; a6 = SysBase
tell_main:
	moveq	#0,d0
	move.l	sig_ready,d1
	bset	d1,d0
	move.l	main_task,a1
	jmp	LVO_Signal(a6)

; void amiga_audio_close(void): both processes ended, their memory given back
	xdef	_amiga_audio_close
	xdef	amiga_audio_close
_amiga_audio_close:
amiga_audio_close:
	movem.l	a2/a6,-(sp)
	tst.l	snd_on
	beq	.x
	bsr	snd_halt
	move.l	4.w,a6
	tst.l	snd_ahi_on
	beq.s	.pa
	move.l	snd_ahi_close,a0		; (snd_ahi.c: its process ended)
	jsr	(a0)
	move.l	4.w,a6
	clr.l	snd_ahi_on
	clr.l	mus_task
	clr.l	snd_on
	move.l	sig_ready,d0
	jsr	LVO_FreeSignal(a6)
	bra.s	.x
.pa:	move.l	mus_task,d0
	beq.s	.m
	move.l	#1,mus_quit
	move.l	d0,a1
	move.l	#SIGF_C,d0
	jsr	LVO_Signal(a6)
	lea	mus_state,a2
	bsr	wait_end
	clr.l	mus_task
.m:	move.l	#1,snd_quit
	move.l	snd_task,a1
	move.l	#SIGF_C,d0
	jsr	LVO_Signal(a6)
	lea	snd_state,a2
	bsr	wait_end
	clr.l	snd_on
	move.l	sig_ready,d0
	jsr	LVO_FreeSignal(a6)
.x:	movem.l	(sp)+,a2/a6
	rts

; int amiga_audio_init(void): (SDL's audio: not used, the game's sound is this file's)
	xdef	_amiga_audio_init
	xdef	amiga_audio_init
_amiga_audio_init:
amiga_audio_init:
	moveq	#-1,d0
	rts

; a2 = &req[0] (6 longs: buffer b, side c at b*2+c), a3 = &buf[0], d2 = their length -> d0 = 0 when all are made;
; a4 = the port; a6 = SysBase
make_reqs:
	movem.l	d3,-(sp)
	moveq	#5,d3
.l:	move.l	a4,a0
	moveq	#IOA_SIZE,d0
	jsr	LVO_CreateIORequest(a6)
	move.l	d0,(a2,d3.l*4)
	beq.s	.f
	move.l	d2,d0
	move.l	#MEMF_CHIP_CLEAR,d1
	jsr	LVO_AllocVec(a6)
	move.l	d0,(a3,d3.l*4)
	beq.s	.f
	dbf	d3,.l
	moveq	#0,d0
	movem.l	(sp)+,d3
	rts
.f:	moveq	#-1,d0
	movem.l	(sp)+,d3
	rts

; a2 = &req[0], a3 = &buf[0], a4 = port, a5 = the channel byte (3 or 12), d2 = length, d3 = period, d4 = volume,
; d5 = unit mask left, d6 = right -> d0 = 0 when audio.device gave the channels; a6 = SysBase
open_audio:
	movem.l	d7,-(sp)
	move.l	(a2),a1
	move.b	#127,LN_PRI(a1)
	move.l	a5,IOA_DATA(a1)
	move.l	#1,IOA_LENGTH(a1)
	move.b	#ADIOF_NOWAIT,IO_FLAGS(a1)
	lea	audioname(pc),a0
	moveq	#0,d0
	moveq	#0,d1
	jsr	LVO_OpenDevice(a6)
	tst.l	d0
	bne.s	.x
	move.l	(a2),a0
	move.l	IO_UNIT(a0),d7			; the channels given
	moveq	#5,d1
.l:	move.l	(a2,d1.l*4),a1
	tst.l	d1
	beq.s	.own
	move.l	(a2),a0				; device, key: copied from the first
	moveq	#IOA_SIZE/4-1,d0
.c:	move.l	(a0)+,(a1)+
	dbf	d0,.c
	move.l	(a2,d1.l*4),a1
.own:	move.l	a4,MN_REPLYPORT(a1)
	move.l	d1,d0
	and.l	#1,d0
	beq.s	.left
	move.l	d6,d0
	bra.s	.side
.left:	move.l	d5,d0
.side:	and.l	d7,d0
	move.l	d0,IO_UNIT(a1)
	move.w	#CMD_WRITE,IO_COMMAND(a1)
	move.b	#ADIOF_PERVOL,IO_FLAGS(a1)
	move.l	(a3,d1.l*4),IOA_DATA(a1)
	move.l	d2,IOA_LENGTH(a1)
	move.w	d3,IOA_PERIOD(a1)
	move.w	d4,IOA_VOLUME(a1)
	move.w	#1,IOA_CYCLES(a1)
	dbf	d1,.l
	moveq	#0,d0
.x:	movem.l	(sp)+,d7
	rts

; a2 = &req[0], a3 = &buf[0], a4 = port, d0 = 1 when the device is open, d1 = a mask of the pairs in flight
; (bit b) or -1 = all; a6 = SysBase: all aborted, closed, given back
free_audio:
	movem.l	d2-d3,-(sp)
	move.l	d0,d2
	move.l	d1,d3
	tst.l	d2
	beq.s	.cl
	moveq	#5,d1
.a:	move.l	d1,d0
	lsr.l	#1,d0
	btst	d0,d3
	beq.s	.an
	move.l	d1,-(sp)
	move.l	(a2,d1.l*4),a1
	jsr	LVO_AbortIO(a6)
	move.l	(sp),d1
	move.l	(a2,d1.l*4),a1
	jsr	LVO_WaitIO(a6)
	move.l	(sp)+,d1
.an:	dbf	d1,.a
	move.l	(a2),a1
	jsr	LVO_CloseDevice(a6)
.cl:	moveq	#5,d2
.f:	move.l	(a2,d2.l*4),d0
	beq.s	.f1
	move.l	d0,a0
	jsr	LVO_DeleteIORequest(a6)
.f1:	move.l	(a3,d2.l*4),d0
	beq.s	.f2
	move.l	d0,a1
	jsr	LVO_FreeVec(a6)
.f2:	dbf	d2,.f
	move.l	a4,d0
	beq.s	.x
	move.l	d0,a0
	jsr	LVO_DeleteMsgPort(a6)
.x:	movem.l	(sp)+,d2-d3
	rts

; a1 = an IORequest: BeginIO; a6 = SysBase kept
begin_io:
	move.l	a6,-(sp)
	move.l	IO_DEVICE(a1),a6
	jsr	DEV_BEGINIO(a6)
	move.l	(sp)+,a6
	rts

; d2 = the pair b: both sides mixed (mx_render_l under the semaphore) and started
snd_fill:
	movem.l	d2/a6,-(sp)
	lea	snd_sem,a0
	jsr	LVO_ObtainSemaphore(a6)
	move.l	#SND_LEN,-(sp)
	lea	snd_buf,a0
	move.l	4(a0,d2.l*8),-(sp)
	move.l	(a0,d2.l*8),-(sp)
	jsr	_mx_render_l
	lea	12(sp),sp
	cmp.l	snd_peak,d0
	ble.s	.pk
	move.l	d0,snd_peak
.pk:	addq.l	#1,snd_played
	lea	snd_sem,a0
	jsr	LVO_ReleaseSemaphore(a6)
	move.l	(sp),d2
	lea	snd_req,a0
	move.l	(a0,d2.l*8),a1
	bsr	begin_io
	lea	snd_req,a0
	move.l	4(a0,d2.l*8),a1
	bsr	begin_io
	movem.l	(sp)+,d2/a6
	rts

snd_proc:
	move.l	4.w,a6
	movem.l	d2-d7/a2-a5,-(sp)
	lea	snd_req,a2
	lea	snd_buf,a3
	moveq	#5,d0
.z:	clr.l	(a2,d0.l*4)
	clr.l	(a3,d0.l*4)
	dbf	d0,.z
	jsr	LVO_CreateMsgPort(a6)
	move.l	d0,a4
	moveq	#0,d7				; device not open
	tst.l	d0
	beq	.out
	move.l	#SND_LEN,d2
	bsr	make_reqs
	tst.l	d0
	bne	.out
	lea	sndchans(pc),a5
	move.l	snd_period,d3
	moveq	#64,d4
	moveq	#1,d5
	moveq	#2,d6
	bsr	open_audio
	tst.l	d0
	bne	.out
	moveq	#1,d7
	move.l	#1,snd_state
	bsr	tell_main
	moveq	#0,d2				; every buffer filled and started; audio.device plays each side's queue on
.f:	bsr	snd_fill
	addq.l	#1,d2
	cmp.w	#SND_BUFS,d2
	blo.s	.f
	moveq	#0,d6				; the next to come back
.loop:	tst.l	snd_quit
	bne.s	.out
	moveq	#0,d0
	move.b	MP_SIGBIT(a4),d1
	bset	d1,d0
	or.l	#SIGF_C,d0
	jsr	LVO_Wait(a6)
.done:	tst.l	snd_quit			; the buffers in order, when both sides are through
	bne.s	.out
	move.l	(a2,d6.l*8),a1
	jsr	LVO_CheckIO(a6)
	tst.l	d0
	beq.s	.loop
	move.l	4(a2,d6.l*8),a1
	jsr	LVO_CheckIO(a6)
	tst.l	d0
	beq.s	.loop
	move.l	(a2,d6.l*8),a1
	jsr	LVO_WaitIO(a6)
	move.l	4(a2,d6.l*8),a1
	jsr	LVO_WaitIO(a6)
	move.l	d6,d2
	bsr	snd_fill
	addq.l	#1,d6
	cmp.w	#SND_BUFS,d6
	blo.s	.done
	moveq	#0,d6
	bra.s	.done
.out:	move.l	d7,d0
	moveq	#-1,d1
	bsr	free_audio
	jsr	LVO_Forbid(a6)			; (the code stays loaded until the process is gone)
	moveq	#2,d0
	tst.l	d7
	bne.s	.st
	moveq	#-1,d0
.st:	move.l	d0,snd_state
	bsr	tell_main
	movem.l	(sp)+,d2-d7/a2-a5
	moveq	#0,d0
	rts

; ---------------------------------------------------------------- the music
; int snd_music(const char *dir, int number): MUSIC<number> = <data>/MUSIC/track<number+1>.raw, round and round;
; 0 stops it.  1 = playing
	xdef	_snd_music
	xdef	snd_music
_snd_music:
snd_music:
	movem.l	d2-d4/a2/a6,-(sp)
	tst.l	mus_task
	beq	.no
	move.l	20+8(sp),d4
	bgt.s	.play
	moveq	#2,d4				; stop
	moveq	#0,d2
	moveq	#0,d3
	bra	.cmd
.play:	move.l	snd_dir,d0			; the file's name
	bne.s	.d
	move.l	#nodir,d0
.d:	move.l	d0,a0
	lea	mus_path,a1
	move.l	a1,a2
	tst.b	(a0)
	beq.s	.nm
.cp:	move.b	(a0)+,(a1)+
	bne.s	.cp
	subq.l	#1,a1
	move.b	-1(a1),d0
	cmp.b	#':',d0
	beq.s	.nm
	cmp.b	#'/',d0
	beq.s	.nm
	move.b	#'/',(a1)+
.nm:	lea	trackname(pc),a0
.cp2:	move.b	(a0)+,(a1)+
	bne.s	.cp2
	move.l	d4,d0
	addq.l	#1,d0				; the CD's track
	divu.w	#10,d0
	add.b	#'0',d0
	move.b	d0,-5-2(a1)			; "trackNN.raw": the tens, the units
	swap	d0
	add.b	#'0',d0
	move.b	d0,-5-1(a1)
	move.l	dos_base,a6
	move.l	a2,d1
	move.l	#MODE_OLDFILE,d2
	jsr	LVO_Open(a6)
	move.l	d0,d3				; the file
	beq	.no
	move.l	d3,d1
	move.l	#mus_hdr,d2
	move.l	d3,-(sp)
	moveq	#MUS_HDR,d3
	jsr	LVO_Read(a6)
	move.l	(sp)+,d3
	moveq	#MUS_HDR,d1
	cmp.l	d1,d0
	bne	.bad
	cmp.l	#'SMUS',mus_hdr
	bne	.bad
	move.l	mus_hdr+8,d2			; the block
	beq	.bad
	btst	#0,d2
	bne	.bad
	cmp.l	#MUS_MAXB,d2
	bhi	.bad
	moveq	#1,d4
.cmd:	move.l	4.w,a6				; to the music's process
	lea	mus_sem,a0
	jsr	LVO_ObtainSemaphore(a6)
	move.l	mus_newfh,d1
	beq.s	.c1
	move.l	dos_base,a6			; (one not yet taken)
	jsr	LVO_Close(a6)
	move.l	4.w,a6
.c1:	move.l	d3,mus_newfh
	move.l	d2,mus_newblk
	move.l	d4,mus_cmd
	lea	mus_sem,a0
	jsr	LVO_ReleaseSemaphore(a6)
	move.l	mus_task,a1
	move.l	#SIGF_D,d0
	jsr	LVO_Signal(a6)
	moveq	#1,d0
	cmp.l	#1,d4
	beq.s	.x
.no:	moveq	#0,d0
.x:	movem.l	(sp)+,d2-d4/a2/a6
	rts
.bad:	move.l	d3,d1
	jsr	LVO_Close(a6)
	bra.s	.no

; the music's process; registers: a2 req, a3 buf, a4 port, d4 the file, d5 the block, d6 next, d7 pairs in flight
; (bit b), mus_eof, mus_loop in memory
mus_proc:
	move.l	4.w,a6
	movem.l	d2-d7/a2-a5,-(sp)
	lea	mus_req,a2
	lea	mus_buf,a3
	moveq	#5,d0
.z:	clr.l	(a2,d0.l*4)
	clr.l	(a3,d0.l*4)
	dbf	d0,.z
	moveq	#0,d4
	moveq	#0,d7
	clr.l	mus_open
	jsr	LVO_CreateMsgPort(a6)
	move.l	d0,a4
	tst.l	d0
	beq	.out
	move.l	#MUS_MAXB,d2
	bsr	make_reqs
	tst.l	d0
	bne	.out
	lea	muschans(pc),a5
	move.l	mus_period,d3
	moveq	#64,d4
	moveq	#8,d5				; left = channel 3
	moveq	#4,d6				; right = channel 2
	bsr	open_audio
	moveq	#0,d4
	tst.l	d0
	bne	.out
	move.l	#1,mus_open
	move.l	#1,mus_state
	bsr	tell_main
	moveq	#0,d6
.loop:	tst.l	mus_quit
	bne	.out
	moveq	#0,d0
	move.b	MP_SIGBIT(a4),d1
	bset	d1,d0
	or.l	#SIGF_C|SIGF_D,d0
	jsr	LVO_Wait(a6)
	tst.l	mus_quit
	bne	.out
	and.l	#SIGF_D,d0
	beq.s	.fill
	lea	mus_sem,a0			; a command
	jsr	LVO_ObtainSemaphore(a6)
	move.l	mus_cmd,d2
	move.l	mus_newfh,d3
	move.l	mus_newblk,a5
	clr.l	mus_cmd
	clr.l	mus_newfh
	lea	mus_sem,a0
	jsr	LVO_ReleaseSemaphore(a6)
	tst.l	d2
	bne.s	.c
	move.l	d3,d1				; (no command: a file left over)
	beq.s	.fill
	bsr	dos_close
	bra.s	.fill
.c:	moveq	#1,d0				; the playing buffers stopped, the file closed
	move.l	d7,d1
	bsr	abort_pairs
	moveq	#0,d7
	move.l	d4,d1
	beq.s	.c1
	bsr	dos_close
.c1:	moveq	#0,d4
	cmp.l	#1,d2
	bne.s	.fill
	move.l	d3,d4
	beq.s	.fill
	move.l	a5,d5
	clr.l	mus_eof
	moveq	#0,d6
.fill:	; free buffers filled and started, in order from the next
	tst.l	d4
	beq	.loop
	moveq	#MUS_BUFS-1,d3
.fl:	btst	d6,d7
	beq.s	.free
	move.l	(a2,d6.l*8),a1			; not yet played: nor are the later ones
	jsr	LVO_CheckIO(a6)
	tst.l	d0
	beq.s	.fe
	move.l	4(a2,d6.l*8),a1
	jsr	LVO_CheckIO(a6)
	tst.l	d0
	beq.s	.fe
	move.l	(a2,d6.l*8),a1
	jsr	LVO_WaitIO(a6)
	move.l	4(a2,d6.l*8),a1
	jsr	LVO_WaitIO(a6)
	bclr	d6,d7
	addq.l	#1,mus_played
.free:	tst.l	mus_eof
	bne.s	.nx
	bsr	mus_read
	tst.l	d0
	beq.s	.nx
	move.l	(a2,d6.l*8),a1
	move.l	d5,IOA_LENGTH(a1)
	move.w	mus_vol+2,IOA_VOLUME(a1)
	bsr	begin_io
	move.l	4(a2,d6.l*8),a1
	move.l	d5,IOA_LENGTH(a1)
	move.w	mus_vol+2,IOA_VOLUME(a1)
	bsr	begin_io
	bset	d6,d7
.nx:	addq.l	#1,d6
	cmp.w	#MUS_BUFS,d6
	blo.s	.n1
	moveq	#0,d6
.n1:	dbf	d3,.fl
.fe:	tst.l	mus_eof			; the end without a loop: when all is played
	beq	.loop
	tst.l	d7
	bne	.loop
	move.l	d4,d1
	bsr	dos_close
	moveq	#0,d4
	bra	.loop
.out:	move.l	mus_open,d0
	move.l	d7,d1
	bsr	free_audio
	move.l	d4,d1
	beq.s	.o1
	bsr	dos_close
.o1:	jsr	LVO_Forbid(a6)
	moveq	#2,d0
	tst.l	mus_open
	bne.s	.st
	moveq	#-1,d0
.st:	move.l	d0,mus_state
	bsr	tell_main
	movem.l	(sp)+,d2-d7/a2-a5
	moveq	#0,d0
	rts

; d0 = 1, d1 = the pairs in flight: aborted (the device stays open); a2, a6 = SysBase
abort_pairs:
	movem.l	d2-d3,-(sp)
	move.l	d1,d3
	moveq	#5,d2
.a:	move.l	d2,d0
	lsr.l	#1,d0
	btst	d0,d3
	beq.s	.n
	move.l	(a2,d2.l*4),a1
	jsr	LVO_AbortIO(a6)
	move.l	(a2,d2.l*4),a1
	jsr	LVO_WaitIO(a6)
.n:	dbf	d2,.a
	movem.l	(sp)+,d2-d3
	rts

; d1 = a file: closed; a6 = SysBase kept
dos_close:
	move.l	a6,-(sp)
	move.l	dos_base,a6
	jsr	LVO_Close(a6)
	move.l	(sp)+,a6
	rts

; the pair d6 read from the file d4 (block d5: d5 bytes left, then d5 right, straight into chip memory); the end:
; from the top (a file of whole blocks), the rest of a short block silent -> d0 = 1 when there is one; a6 = SysBase
mus_read:
	movem.l	d2-d3/a6,-(sp)
	move.l	dos_base,a6
	move.l	(a3,d6.l*8),d2
	bsr	.rd
	tst.l	d0
	bgt.s	.l1
	move.l	d4,d1				; the end: from the top
	moveq	#MUS_HDR,d2
	moveq	#OFFSET_BEGINNING,d3
	jsr	LVO_Seek(a6)
	move.l	(a3,d6.l*8),d2
	bsr	.rd
	tst.l	d0
	ble.s	.eof
.l1:	move.l	d0,-(sp)
	move.l	4(a3,d6.l*8),d2
	bsr	.rd
	move.l	(sp)+,d1
	cmp.l	d5,d1				; short: the rest silent, and that was all
	beq.s	.ok
	move.l	d0,-(sp)
	move.l	(a3,d6.l*8),a0
	bsr	.zero
	move.l	(sp)+,d1
	tst.l	d1
	bpl.s	.r0
	moveq	#0,d1
.r0:	move.l	4(a3,d6.l*8),a0
	bsr	.zero
	move.l	#1,mus_eof
.ok:	moveq	#1,d0
	movem.l	(sp)+,d2-d3/a6
	rts
.eof:	move.l	#1,mus_eof
	moveq	#0,d0
	movem.l	(sp)+,d2-d3/a6
	rts
.rd:	move.l	d4,d1				; d2 = where: d5 bytes
	move.l	d5,d3
	jmp	LVO_Read(a6)
.zero:	add.l	d1,a0				; a0 + d1 .. a0 + d5 cleared
	move.l	d5,d0
	sub.l	d1,d0
	bra.s	.zt
.zl:	clr.b	(a0)+
.zt:	dbf	d0,.zl
	rts

; ---------------------------------------------------------------- for the test of sound_load.c / the frame's status
	xdef	_snd_rate
	xdef	snd_rate
	xdef	_snd_played
	xdef	snd_played
	xdef	_snd_peak
	xdef	snd_peak
	xdef	_mus_played
	xdef	mus_played

gfxname:	dc.b	"graphics.library",0
dosname:	dc.b	"dos.library",0
audioname:	dc.b	"audio.device",0
sndname:	dc.b	"Screamer Ton",0
musname:	dc.b	"Screamer Musik",0
trackname:	dc.b	"track00.raw",0		; (in snd_dir: the music drawer, snd_load.c)
nodir:	dc.b	0
sndchans:	dc.b	3			; channels 0 + 1
muschans:	dc.b	12			; channels 2 + 3
	even

; int snd_music_on(void): the music's process runs
	xdef	_snd_music_on
	xdef	snd_music_on
_snd_music_on:
snd_music_on:
	moveq	#0,d0
	tst.l	mus_task
	sne	d0
	neg.b	d0
	rts


; ---------------------------------------------------------------- AHI's sum (snd_ahi.c)
; uint32_t ahi_mix68k(int16_t *out, const int8_t *l, const int8_t *r, uint32_t n, const int8_t *ml, const int8_t *mr,
;                     uint32_t *pos, uint32_t fill, uint32_t step, int32_t mv)
; out = (effect * 64 + music * mv) * 2, left and right interleaved; the music (ml/mr, NULL or mv 0: none) at *pos
; (16.16, + step a pair) up to its block's end fill: stops there (*pos >= fill << 16, the caller reads the next
; block) -> the pairs made
	xdef	_ahi_mix68k
	xdef	ahi_mix68k
_ahi_mix68k:
ahi_mix68k:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	48(sp),a0			; out
	move.l	52(sp),a1			; l
	move.l	56(sp),a2			; r
	move.l	60(sp),d7			; n
	move.l	64(sp),a3			; ml
	move.l	68(sp),a4			; mr
	move.l	72(sp),a5			; &pos
	move.l	76(sp),d6			; fill
	move.l	80(sp),d5			; step
	move.l	84(sp),d4			; mv
	moveq	#0,d0
	tst.l	d7
	beq	am_x
	move.l	a3,d1
	beq.s	am_fx
	tst.l	d4
	beq.s	am_fx
	swap	d6
	clr.w	d6				; fill << 16
	move.l	(a5),d3				; pos
am_l:	move.l	d3,d1
	clr.w	d1
	swap	d1
	movea.l	d1,a6				; the music's sample
	move.b	(a3,a6.l),d1
	ext.w	d1
	muls.w	d4,d1
	move.b	(a1)+,d2
	ext.w	d2
	asl.w	#6,d2
	ext.l	d2
	add.l	d1,d2
	add.l	d2,d2
	move.w	d2,(a0)+
	move.b	(a4,a6.l),d1
	ext.w	d1
	muls.w	d4,d1
	move.b	(a2)+,d2
	ext.w	d2
	asl.w	#6,d2
	ext.l	d2
	add.l	d1,d2
	add.l	d2,d2
	move.w	d2,(a0)+
	addq.l	#1,d0
	add.l	d5,d3
	cmp.l	d6,d3
	bhs.s	am_e
	cmp.l	d7,d0
	blo.s	am_l
am_e:	move.l	d3,(a5)
	bra.s	am_x
am_fx:	move.b	(a1)+,d2			; the effects alone
	ext.w	d2
	asl.w	#7,d2				; (* 64 * 2)
	move.w	d2,(a0)+
	move.b	(a2)+,d2
	ext.w	d2
	asl.w	#7,d2
	move.w	d2,(a0)+
	addq.l	#1,d0
	cmp.l	d7,d0
	blo.s	am_fx
am_x:	movem.l	(sp)+,d2-d7/a2-a6
	rts

; void snd_set_dir(const char *music_dir): where the trackNN.raw are (kept, not copied)
	xdef	_snd_set_dir
	xdef	snd_set_dir
_snd_set_dir:
snd_set_dir:
	move.l	4(sp),snd_dir
	rts

	section	data,data
	cnop	0,4
_snd_rate:
snd_rate:	dc.l	15625
	xdef	_mus_vol
	xdef	_snd_ahi_open
	xdef	snd_ahi_open
	xdef	_snd_ahi_close
	xdef	snd_ahi_close
_mus_vol:
mus_vol:	dc.l	64
_snd_ahi_open:
snd_ahi_open:	dc.l	0			; AHI wanted: snd_ahi.c's ahi_open (snd_load.c, SCREAMER_SND=ahi)
_snd_ahi_close:
snd_ahi_close:	dc.l	0
	xdef	_snd_ahi_on
_snd_ahi_on:
snd_ahi_on:	dc.l	0

	section	bss,bss
	cnop	0,4
	xdef	_snd_tab
	xdef	snd_tab
	xdef	_snd_n
	xdef	snd_n
_snd_tab:
snd_tab:	ds.b	SM_SIZE*96		; SND_MAX
_snd_n:
snd_n:		ds.l	1
	xdef	_snd_sem
	xdef	_mus_sem
	xdef	_mus_cmd
	xdef	_mus_newfh
	xdef	_mus_newblk
snd_on:		ds.l	1			; the output runs: the mixer's calls under snd_sem
snd_failed:	ds.l	1
_snd_sem:
snd_sem:	ds.b	48
_mus_sem:
mus_sem:	ds.b	48
v_handle:	ds.l	MIX_VOICES
v_sample:	ds.l	MIX_VOICES
v_gain:		ds.l	MIX_VOICES
v_pan:		ds.l	MIX_VOICES
v_rate:		ds.l	MIX_VOICES
v_serial:	ds.l	1
paula_clock:	ds.l	1
dos_base:	ds.l	1
snd_dir:	ds.l	1
snd_period:	ds.l	1
mus_period:	ds.l	1
main_task:	ds.l	1
sig_ready:	ds.l	1
snd_task:	ds.l	1
snd_quit:	ds.l	1
snd_state:	ds.l	1
_snd_played:
snd_played:	ds.l	1
_snd_peak:
snd_peak:	ds.l	1
snd_req:	ds.l	6
snd_buf:	ds.l	6
np_tags:	ds.l	9
mus_task:	ds.l	1
mus_quit:	ds.l	1
mus_state:	ds.l	1
mus_open:	ds.l	1
_mus_cmd:
mus_cmd:	ds.l	1
_mus_newfh:
mus_newfh:	ds.l	1
_mus_newblk:
mus_newblk:	ds.l	1
mus_eof:	ds.l	1
_mus_played:
mus_played:	ds.l	1
mus_req:	ds.l	6
mus_buf:	ds.l	6
mus_hdr:	ds.b	MUS_HDR
mus_path:	ds.b	320
