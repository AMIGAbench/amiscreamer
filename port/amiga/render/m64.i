; 64-Bit-mul/div als Makros: 68080 (und Bauten ohne CPU060) Einbefehl, 68040/68060 (-DCPU060) Aufruf von
; m64_68k.s (die 64-Bit-Formen sind dort Traps). Quelle darf sp-relativ sein (wird zuerst gelesen).
; Flaggen: MULS64/MULU64 keine, DIVS64/DIVU64 wie divs.l/divu.l (V bei Überlauf, dann Operanden unverändert).
	ifd	CPU060
	xref	m64_muls
	xref	m64_mulu
	xref	m64_divs
	xref	m64_divu
	endif
MULS64	macro					; muls.l \1,\2:\3
	ifd	CPU060
	move.l	\1,-(sp)
	move.l	\3,-(sp)
	jsr	m64_muls
	move.l	(sp)+,\3
	move.l	(sp)+,\2
	else
	muls.l	\1,\2:\3
	endif
	endm
MULU64	macro					; mulu.l \1,\2:\3
	ifd	CPU060
	move.l	\1,-(sp)
	move.l	\3,-(sp)
	jsr	m64_mulu
	move.l	(sp)+,\3
	move.l	(sp)+,\2
	else
	mulu.l	\1,\2:\3
	endif
	endm
DIVS64	macro					; divs.l \1,\2:\3 (\2 = oberes Langwort/Rest, \3 = unteres/Quotient)
	ifd	CPU060
	move.l	\1,-(sp)
	move.l	\2,-(sp)
	move.l	\3,-(sp)
	jsr	m64_divs
	move.l	(sp)+,\3
	move.l	(sp)+,\2
	addq.l	#2,sp
	move.w	(sp)+,ccr
	else
	divs.l	\1,\2:\3
	endif
	endm
DIVU64	macro					; divu.l \1,\2:\3
	ifd	CPU060
	move.l	\1,-(sp)
	move.l	\2,-(sp)
	move.l	\3,-(sp)
	jsr	m64_divu
	move.l	(sp)+,\3
	move.l	(sp)+,\2
	addq.l	#2,sp
	move.w	(sp)+,ccr
	else
	divu.l	\1,\2:\3
	endif
	endm
SMULDIV	macro					; d0 = d0 * \1 / \2 über 64 Bit (= MULS64 \1,d1,d0 + DIVS64 \2,d1,d0), V bei Überlauf
	ifd	CPU060				; 060: Schnellweg mit muls.l/divs.l 32 Bit (V von muls.l = Produkt passt nicht)
	move.l	d0,d1
	muls.l	\1,d1
	bvs	smd_l\@
	divs.l	\2,d1
	bvs	smd_e\@			; nur -2^31 / -1: auch über 64 Bit Überlauf
	move.l	d1,d0
	bra	smd_e\@
smd_l\@:
	MULS64	\1,d1,d0
	DIVS64	\2,d1,d0
smd_e\@:
	else
	muls.l	\1,d1:d0
	divs.l	\2,d1:d0
	endif
	endm
