_Head:
	/* Set _Entry address */
	adr		x1, _Payload

	/* Jump to the real code */
	b		_Start

	/* Fake Linux kernel header */

_StackBase:
	/* Text Offset */
	.quad UEFI_BASE

_StackSize:
	/* Image Size */
	.quad UEFI_SIZE

	/* Flags */
	.quad 0

	/* Reserved */
	.quad 0

	/* Reserved */
	.quad 0

	/* Reserved */
	.quad 0

	/* ARM64 Magic */
	.ascii "ARM\x64"

	/* Reserved */
	.long 0

_Start:
	mov		x19, x1
	ldr		w0, [x19]
	movz	w1, #0x457f
	movk	w1, #0x464c, lsl #16
	cmp		w0, w1
	b.eq	_LoadElf

	mov		x4, x19
	ldr		x5, _StackBase
	cmp		x4, x5
	beq		_Entry
	ldr		x6, _StackSize

_CopyLoop:
	ldp		x2, x3, [x4], #16
	stp		x2, x3, [x5], #16
	subs	x6, x6, #16
	b.ne	_CopyLoop
	ldr		x5, _StackBase

_Entry:
	br		x5

_LoadElf:
	ldrb	w2, [x19, #4]
	cmp		w2, #1
	b.eq	_LoadElf32
	cmp		w2, #2
	b.eq	_LoadElf64
	b		_Dead

_LoadElf32:
	ldr		w20, [x19, #0x18]	/* e_entry */
	ldr		w21, [x19, #0x1c]	/* e_phoff */
	add		x21, x19, x21
	ldrh	w22, [x19, #0x2a]	/* e_phentsize */
	ldrh	w23, [x19, #0x2c]	/* e_phnum */
	b		_LoadElfPhdrLoop32

_LoadElfPhdrLoop32:
	cbz		w23, _JumpElfEntry32
	ldr		w0, [x21]			/* p_type */
	cmp		w0, #1				/* PT_LOAD */
	b.ne	_NextElfPhdr32
	ldr		w1, [x21, #4]		/* p_offset */
	ldr		w2, [x21, #12]		/* p_paddr */
	ldr		w3, [x21, #16]		/* p_filesz */
	ldr		w4, [x21, #20]		/* p_memsz */
	add		x1, x19, x1
	bl		_CopyLoadSegment

_NextElfPhdr32:
	add		x21, x21, x22
	subs	w23, w23, #1
	b.ne	_LoadElfPhdrLoop32

_JumpElfEntry32:
	mov		x5, x20
	br		x5

_LoadElf64:
	ldr		x20, [x19, #0x18]	/* e_entry */
	ldr		x21, [x19, #0x20]	/* e_phoff */
	add		x21, x19, x21
	ldrh	w22, [x19, #0x36]	/* e_phentsize */
	ldrh	w23, [x19, #0x38]	/* e_phnum */
	b		_LoadElfPhdrLoop64

_LoadElfPhdrLoop64:
	cbz		w23, _JumpElfEntry64
	ldr		w0, [x21]			/* p_type */
	cmp		w0, #1				/* PT_LOAD */
	b.ne	_NextElfPhdr64
	ldr		x1, [x21, #8]		/* p_offset */
	ldr		x2, [x21, #24]		/* p_paddr */
	ldr		x3, [x21, #32]		/* p_filesz */
	ldr		x4, [x21, #40]		/* p_memsz */
	add		x1, x19, x1
	bl		_CopyLoadSegment

_NextElfPhdr64:
	add		x21, x21, x22
	subs	w23, w23, #1
	b.ne	_LoadElfPhdrLoop64

_JumpElfEntry64:
	mov		x5, x20
	br		x5

_CopyLoadSegment:
	mov		x7, x3
	cbz		x7, _ZeroFillSegment

_CopyLoadSegmentLoop:
	ldrb	w6, [x1], #1
	strb	w6, [x2], #1
	subs	x7, x7, #1
	b.ne	_CopyLoadSegmentLoop

_ZeroFillSegment:
	subs	x4, x4, x3
	cbz		x4, _CopyLoadSegmentDone

_ZeroFillSegmentLoop:
	strb	wzr, [x2], #1
	subs	x4, x4, #1
	b.ne	_ZeroFillSegmentLoop

_CopyLoadSegmentDone:
	ret

_Dead:
	/* We should never get here */
	b		_Dead

.text
.align 4

_Payload:
	/* Your code will get ran right after this binary */
