include bt1ttl.inc
SUBTTL initialization & diagnostic check


;
;
;	power-on/reset boot entry (the diagnostic boot entry)
;
;


name btdiag; 

;
;	diagnostic plugin rom board
;
diag	segment	at 0D000H;

	diagloc	proc	far;
	diagloc	endp;

diag	ends;	

;
;	segment for the boot code
;	(also is at 0FC00h, due to memory address wiring)
;
btseg	segment at 0FE00h;

boot	equ	$;		boot starts at this address

btseg	ends;


	
;
;	segment for the power on/reset code (this module)
;	(define a dummy segment to avoid a relocatable reference
;	in the JMP at the end of the ROM)
;
poweron	segment at 0FFD0h;

reset_code	equ	$;	power on/reset code starts here

poweron	ends;


;
;	segment to test I/O for pic, parallel, keyboard, and user ports
;
extra_io	segment at 0E000h;

		org	0000h;		the programmable interrupt controller
pic_port0	db	?
pic_port1	db	?

		org	8020h;		the parallel interface port
prlddr		equ	0FF03h;		parallel data direction register
parallel0	db	?
parallel1	db	?
parallel2	db	?
parallel3	db	?
parallel4  	db	?
parallel5  	db	?
parallel6	db	?
parallel7	db	?
parallel8	db	?
parallel9	db	?
parallelA	db	?
parallelB	db	?	
parallelC	db	?
parallelD	db	?
parallelE	db	?
parallelF	db	?

		org	8040H;		keyboard port 6522 register addresses
kbdddr		equ	03FFh;		keyboard data direction register
keyboard0	db	?
keyboard1	db	?
keyboard2	db	?
keyboard3	db	?
keyboard4	db	?
keyboard5	db	?
keyboard6	db	?
keyboard7	db	?
keyboard8	db	?
keyboard9	db	?
keyboardA	db	?
keyboardB	db	?
keyboardC	db	?
keyboardD	db	?
keyboardE	db	?
keyboardF	db	?

		org	8080H;		user port 6522 register addresses
usrddr		equ	0FFFFh;		user port data direction register
user0		db	?
user1		db	?
user2		db	?
user3		db	?
user4		db	?
user5		db	?
user6		db	?
user7		db	?
user8		db	?
user9		db	?
userA		db	?
userB		db	?
userC		db	?
userD		db	?
userE		db	?
userF		db	?

extra_io	ends;




;
;	segment containing the power-on/reset diagnostic boot
;	(locate this segment at FFD0:0)
;
diagn	segment;

FE_version	equ	0F3F6h;	version of ROM for FE's

ioport	equ	0FFFFh;		port to tell field service what's wrong
FE_screen	equ	01h;	FE error unreproducable screen ram error
FE_bad_chksum	equ	02h;	FE error code for bad ROM checksum
FE_16K		equ	03h;	FE error unreproducable error in first 16K
FE_bad_screen	equ	10h;	FE error code for bad screen ram
FE_screen_mult	equ	20h;	FE error code for bad screen ram, >1 bit error
FE_16K_error	equ	30h;	FE error code for error in first 16K
FE_16K_mult	equ	40h;	FE error code for error in first 16K, >1 bit

;
;	bits to set in non-fatal error vector
;
pic_mask_init_errflg	equ	01000h;	pic error
parallel_init_errflg	equ	00200h;	parallel port error
keyboard_init_errflg	equ	00030h;	keyboard port error
user_init_errflg	equ	00004h;	user port error


diagid	equ	0E9H;		jmp instruction is in diagnostic ROM
chcksum	equ	02152H;		boot ROM's checksum value
crt	equ	0E800H;		I/O register for the CRT
screen	equ	0F000h;		segment of screen ram
svr	equ	300h+7Eh;	save registers in ram at 0:7E/7Fh and down
nfatals	equ	300h+30Ch;	flags for non-fatal errors detected

assume	cs:diagn,ds:diag

;
;	main entry point to this module
;
;	NOTE: since this segment is at FFD0:0000,
;	      offsets of 300h+x using cs address 0000:x.
;
dent	proc;
	mov	cs:word ptr [300h+00h],0;	clear boot option flag

;	The following code is a trick.  Store an address in the non-
;	maskable interrupt vector, which points to one of the bytes
;	of that vector.  Through design, that byte is also an IRET (0CFh).

	mov	cs:[300h+08h],0CFF9h;	non-maskable interrupt vector,
	mov	cs:[300h+0Ah],0F301h;	set to execute an IRET

	mov	cs:word ptr svr,sp;	save old stack pointer

	mov	sp,crt;			establish addressability to crt
	mov	es,sp;
	mov	byte ptr es:[0],1;
	mov	byte ptr es:[1],0;	shut down crt

	mov	sp,cs;			set stack segment
	mov	ss,sp;			set up stack to start at 0:07Eh
	mov	sp,svr;			(where old sp was saved) and below

	push	ax;			save registers
	push	bx;			for debug
	push	cx;			of previously-
	push	dx;			executing programs
	push	si;
	push	di;
	push	bp;

;
;	validate checksum of the boot rom
;
	mov	cx,2000h/2;		ROM is 8k bytes (do in words)

	mov	ax,seg btseg;		start address of the ROM
	mov	es,ax;
	xor	si,si;			offset for start of the test

	xor	ax,ax;			initialize checksum accumulator
checksum_loop:;
	add	ax,es:[si];		add words of rom into checksum
	inc	si;
	inc	si;			next word
	loop	checksum_loop;		until end of rom

	cmp	ax,chcksum;		calculated checksum correct ?
	jz	good_checksum2;		yes, skip
	jmp	bad_checksum;		no, error in the rom

;
; test for ram at diagnostic board location
;
good_checksum2:;
	mov	ax,seg diagloc;		get a pointer to diagnostic plug-in
	mov	ds,ax;

	mov	ax,word ptr diagloc;	read first word of the plug-in
	mov	bx,ax;			and save it (may be destroyed)

	not	ax;
	mov	word ptr diagloc,ax;	now, change the word's value
	cmp	word ptr diagloc,ax;	did it "take" ?
	mov	word ptr diagloc,bx;	restore the stuff
	jz	short ontoboot;		it changed, it's ram, not diag rom


;
;	it's ROM (or non-existent memory), see if it has the right stuff in it
;

	mov	cx,100;			try 100 times, ensure JMP not a fluke
bingo:
	cmp	byte ptr diagloc,diagid;
	jne	ontoboot;		test first byte for JMP opcode
	loop	bingo;
	jmp	diagloc;		it passed the test, transfer control


;
;	No diagnostic ROM, so boot must check out memory . . .
;
;	Test screen ram, to ensure CRT could possibly operate.
;
;	Tests 0:0 to 0:3FFF, which totals to 16K.
;
;	NOTE:  testing 00 to FF is bypassed to allow storing data between
;	boots (date, time, etc.).  Because of the nature of the particular
;	memory test performed, errors in this area would be indicated by
;	errors in the rest of the first 16K (or, due to the lackings in the
;	limited test performed, would not be detected at all).
;
;	Test with 55AA and AA55 hex.  Leave memory at 0000.
;

ontoboot:;

;
;	test screen ram
;
	mov	ax,screen;		base of screen ram
	mov	es,ax;

	mov	ax,055AAh;		first test pattern

test_screen_ram:;
	xor	di,di;			start at offset of 0
	mov	cx,2048;		for 2K words (4K bytes)
	cld;				auto-incrementing locations
	rep	stosw;

	cmp	ax,word ptr 0;			done ?
	jz	screen_ram_ok;		yes.

	xor	di,di;			compare starting at offset 0
	mov	cx,2048;		for 2K words
	repz	scasw;
	jnz	bad_screen_ram;		error, did not match

	xor	ax,word ptr 0FFFFh;		switch pattern from 55AA to AA55
;	db	35h,0ffh,0ffh	; JWasm generates 83F0FF for xor above
	jl	test_screen_ram;	not done, test with pattern #2

	xor	ax,ax;			final pattern is zeroes
	jmp	test_screen_ram;	fill with zeroes


;
;	screen ram is bad . . .
;
bad_screen_ram:;
	mov	cl,FE_bad_screen;	error code for field service

;
;	here when failed a memory test . . .
;
;	inputs:		es:di addresses the word after the failing location
;			ax is the test pattern which failed
;			cl is the base FE error code
;
bad_memory:;
	sub	di,2;			point to failing location
	mov	bx,es:[di];		read the data which failed
	xor	bx,ax;			compute the incorrect bits
	jz	cannot_reproduce;	cannot reproduce the failure

	mov	ch,15;			start at bit 15

find_failed_bit:;
	cmp	bx,0;			this bit failed ?
	jl	have_failure;		yes, skip out
	shl	bx,1;			look at next bit
	dec	ch;			and update bit's position
	jmp	find_failed_bit;	continue until find the bit

;
;	here if can't find bit that failed, say multiple bits
;
cannot_reproduce:;
	xor	ch,ch;			cannot say which bit failed

	shr	cl,1;
	shr	cl,1;			convert code of 10 or 30
	shr	cl,1;			to a code of 1 or 3
	shr	cl,1;			(unreproducable memory error)

	jmp short display_error;	and output FE information

have_failure:;
	shl	bx,1;			shift out failed bit
	or	bx,bx;			multiple bit error ?
	jz	display_error;		no, skip

	add	cl,10h;			yes, convert to multi-bit error code
;					(change 10 or 30 to 20 or 40)
display_error:;
	xchg	ax,cx;			put pattern in cx, error in ax
	or	al,ah;			combine error code and bit in error

	mov	dx,ioport;		select field engineering's I/O port

memory_error_loop:;
	out	dx,al;			issue the error code
	mov	es:[di],cx;		write pattern to failing location
	mov	bx,es:[di];		read the failing location
	jmp	memory_error_loop;	for ever . . .

;
;	invalid checksum in the boot ROM
;
bad_checksum:;
	mov	al,FE_bad_chksum;
	mov	dx,ioport;		field engineering's I/O port

error_display:;
	out	dx,al;			issue the error for FE scoping
	jmp	error_display;		that's all for now

;
;	now, perform the test on the first 16K
;
screen_ram_ok:;
	xor	ax,ax;		start the test at 0:0
	mov	es,ax;

	mov	ax,55AAh;	alternate-bit pattern #1

;
;	fill memory with a particular pattern
;
tm:
	mov	di,100h;	start at offset 100 hex
	mov	cx,(4000h-100h)/2;	length of 16K bytes
	rep	stosw;		store ax in memory

	cmp	ax,word ptr 0;		through with the test ?
	jz	test_nfatals;	yes, memory is zeroed

;
;	test memory for a particular pattern
;
	mov	di,100h;	start at offset 100 hex
	mov	cx,(4000h-100h)/2;	length of 16K bytes
	repz	scasw;		test memory for ax
	jnz	diagmerr;	failed memory test

;
;	try next pattern
;
	xor	ax,word ptr 0FFFFh;	switch test pattern
	jl	tm;		try the AA55 pattern

	xor	ax,ax;		and then set to zeroes
	jmp	tm;


;
;	routine to effectively handle a bad memory (first 16K bad)
;
diagmerr:;
	mov	cl,FE_16K_error;	error code for error in first 16K
	jmp	bad_memory;


;
;	test hardware for non-fatal problems
;
test_nfatals:;
init_pic:;				initialize intel 8259 PIC
	mov	word ptr cs:nfatals,0;	zero error flags

	mov	ax,seg extra_io;
	mov	es,ax;			address the memory-mapped I/O

	mov	es:pic_port0,17h;	edge triggered mode
	mov	es:pic_port1,20h;	ICW2
	mov	es:pic_port1,01h;	ICW4 = 8086 mode

chk_pic_mask:;
	cmp	es:pic_port1,00h;	check mask init state
	jne	pic_mask_fail;		exit if error

	mov	es:pic_port1,0AAh;	set pic mask = AAh
	cmp	es:pic_port1,0AAh;	check pic mask
	jne	pic_mask_fail;		exit if error

	mov	es:pic_port1,55h;	set pic mask = 55h
	cmp	es:pic_port1,55h;	check pic mask
	jne	pic_mask_fail;		exit if error

	mov	es:pic_port1,0FFh;	set pic mask = FFH
	cmp	es:pic_port1,0FFh;	check pic mask
	jne	pic_mask_fail;		exit if error

 	mov	cx,8;			all interrupts are masked
	mov	al,60h;			set up to clear all int pending
					
cl1:;
 	mov	es:pic_port0,al;	issue SEOI
 	inc	al;
 	loop	cl1;			clear all ISR bits
	jmp	no_pic_fail;
	nop

pic_mask_fail:;
	or	word ptr cs:nfatals,pic_mask_init_errflg;

no_pic_fail:;
;
;	check the initialization of the parallel 6522
;
parallel_init_check:;

	mov	es:word ptr parallel2,prlddr;
	cmp	es:word ptr parallel2,prlddr;
	jne	parallel_fail;			init DDR's and check

	mov	al,es:parallel1;
	cmp	al,es:parallelF;		RA = RAX ?
	jne	parallel_fail;

	mov	ax,es:word ptr parallel4;
	cmp	ax,es:word ptr parallel4;
	je	parallel_fail;

	mov	ax,es:word ptr parallel8;
	cmp	ax,es:word ptr parallel8;
	jne	no_parallel_fail;

parallel_fail:;
	or	word ptr cs:nfatals,parallel_init_errflg;

no_parallel_fail:;
;
;	check the initialization of the keyboard 6522
;
keyboard_init_check:;

	mov	es:word ptr keyboard2,kbdddr;
	cmp	es:word ptr keyboard2,kbdddr;
	jne	keyboard_fail;		init DDR's and check

	mov	al,es:keyboard1;
	cmp	al,es:keyboardF;	RA = RAX ?
	jne	keyboard_fail;

	mov	ax,es:word ptr keyboard4;
	cmp	ax,es:word ptr keyboard4;
	je	keyboard_fail;

	mov	ax,es:word ptr keyboard8;
	cmp	ax,es:word ptr keyboard8;
	jne	no_keyboard_fail;

keyboard_fail:;
	or	word ptr cs:nfatals,word ptr keyboard_init_errflg;

no_keyboard_fail:;
;
;	check the initialization of the user 6522
;
user_init_check:;

	mov	es:word ptr user2,usrddr;
	cmp	es:word ptr user2,word ptr usrddr;
	jne	user_fail;		init DDR's and check

	mov	es:word ptr user2,0000h;
	cmp	es:word ptr user2,0000h;
	jne	user_fail;		reset user DDR's

	mov	al,es:user1;
	cmp	al,es:userF;		RA = RAX ?
	jne	user_fail;

	mov	ax,es:word ptr user4;
	cmp	ax,es:word ptr user4;
	je	user_fail;

	mov	ax,es:word ptr user8;
	cmp	ax,es:word ptr user8;
	jne	no_user_fail;

user_fail:;
	or	word ptr cs:nfatals,word ptr user_init_errflg;

no_user_fail:;
	jmp	far ptr boot;		jump to the boot's base module


dent	endp;



;
;	these are the two boot vector jumps at the end of the ROM
;
	org	02F0h;
	jmp	far ptr reset_code;	FFFF0 is power-on/reset vector
	jmp     far ptr boot;		FFFF5 is boot initialization routine

;
;	version number and checksum
;
;		version number is at FFFFA and FFFFB
;		IBM PC compatibility flag is at FFFFE and FFFFF
;
version	dw	FE_version;	version number (least significant byte first)
makeit	dw	?;		kludge word so checksum calculates correctly
pcflag	dw	0FFFFh;		flags that we are IBM PC-Compatible

diagn	ends;

end;

