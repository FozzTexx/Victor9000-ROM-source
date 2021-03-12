include bt1ttl.inc

name	floppy


;
;
;	floppy disk driver
;
;


;
;	errors generated by the floppy device driver . . .
;
;
no_sync		equ	01h;	no sync	
no_header_id	equ	02h;	header id didn't follow sync
header_checksum	equ	03h;	header checksum error
wrong_track	equ	04h;	requested track <> header track
wrong_sector	equ	05h;	no match on sector - error count expired
no_data_id	equ	06h;	data id didn't follow header
data_checksum	equ	07h;	data checksum error
long_sync	equ	08h;	sync present too long
door_opened	equ	09h;	door opened during operation
gcr_error	equ	0Ah;	gcr error
bad_dun		equ	20h;	invalid device/unit field in lrb
bad_da		equ	21h;	invalid sector address in lrb
no_system	equ	99h;	floppy label indicates no O/S on disk



page
;
;	define I/O registers for floppy disk
;
ioports		segment at 0E800h;	6500 address space

;
;	stepper motor control
;
		org	0A0h;		"peripheral B port"
motor_1		equ	byte ptr $;
f_motoff	equ	00Fh;		motor speed status ready
f_motorbits	equ	00Fh;		motor speed bits
f_stepbits	equ	0F0h;		stepper phase mask
f_stptk0	equ	0A0h;		flags if on track 0,4,8,...

		org	0A1h;		"peripheral A port"
motor_0		equ	byte ptr $;	same as above

		org	0A2h;		"data direction register B"
motor_ddb	equ	byte ptr $;

		org	0A3h;		"data direction register A"
motor_dda	equ	byte ptr $;	same as above

page
;
;	miscellaneous control registers
;
		org	0ACh;		"peripheral control register"
mode		equ	byte ptr $;	selects data mode

		org	0AEh;		"interrupt enable register"
intps		equ	byte ptr $;	interrupt enable flags

		org	0C0h;		"peripheral B port"
read_perb	equ	byte ptr $;	floppy door indicator
f_rdy0		equ	01h;		output motor speed for A
f_rdy1		equ	02h;		output motor speed for B
spc_data_rdy	equ	01h;		output controller handshake data ready
spc_data_rcvd	equ	02h;		output controller handshake data taken
f_screset	equ	04h;		output speed controller reset
f_door1		equ	08h;		input door open sense for B
f_door0		equ	10h;		input door open sense for A
f_s0enab	equ	40h;		NOT output stepper enable drive A
f_s1enab	equ	80h;		NOT output stepper enable drive B

		org	0C1h;		"peripheral A port"
clrgcr		equ	byte ptr $;	if read, will clear the gcr
	
		org	0C2h;		"data direction register, port B"
data_ddb	equ	byte ptr $;

		org	0C3h;		"data direction register, port A"
data_dda	equ	byte ptr $;

		org	0CCh;		"peripheral control register"
readwrite_erase	equ	byte ptr $;	disk read/write and erase head

		org	0CDh;		"interrupt flag register"
fgcr		equ	byte ptr $;	gcr register
gcrerr		equ	02h;		gcr error bit


page
		org	0CFh;		same as 0C1, but doesn't reset if read
read_pera	equ	byte ptr $;	sync indicator
f_led0		equ	01h;		output LED for drive A
drv0_trk0	equ	02h;		NOT drive A track 0 sense
f_led1		equ	04h;		output LED for drive B
drv1_trk0	equ	08h;		NOT drive B track 0 sense
f_sidesel	equ	10h;		output disk side selection
f_selbit	equ	20h;		output select drive A or B
f_wpsbit	equ	40h;		output write protect sense
fsynbit		equ	80h;		sync detect bit


;
;	registers for reading/writing disk data
;
		org	0E0h;		"data direction register port B"
dskout		equ	byte ptr $;	disk data outputs

		org	0E1h;		"data direction register port A"
dskdata		equ	byte ptr $;	disk data

		org	0E2h;		"data direction register port B"
diskout_ddb	equ	byte ptr $;

		org	0E3h;		"data direction register port A"
diskin_dda	equ	byte ptr $;

		org	0EBh;		"auxilliary control register"
acr		equ	byte ptr $;


ioports	ends;



page
;
;	miscellaneous disk equates
;

trk_mask	equ	7fh;		remove side information, get track only
max_tracks	equ	88;		maximum tracks arm may have to travel
label_size	equ	80h;		size of the floppy disk label
os_label	equ	0FFh;		flags system disk label
speed_header	equ	4;		4 bytes of header before speed zone data
speed_zones	equ	15;		15 speed zones on a disk
fhid		equ	7;		value for header id on disk
fdid		equ	8;		value for data id on disk




page

data	segment public 'data'

	extrn	sec:byte;		working sector
	extrn	trk:byte;		working track
	extrn	fldma:dword;		dma address in variables
	extrn	curtrk:byte;		track we're currently at (each drive)
	extrn	seccnt:byte;		count down of number of sectors to read
	extrn	sav_seccnt:byte;	permanent copy of number sectors read
	extrn	sector_retry:byte;	retry count for reading bad sectors
	include	bt1lrb.str;
	extrn	lrb:byte;		load request block (I/O parameters)
	include	bt1fdlbl.str;
	extrn	bootr:byte;		floppy disk label buffer

data	ends



cgroup	group code;
dgroup	group data;
assume	cs:cgroup,ds:dgroup,es:ioports;




code	segment public 'code';

extrn	err_intern:near;
extrn	time:near;
public	fd_reset;
public	fd_cup;
public	fd_dvcrdy;
public	fd_online;
public	fd_read;
public	fd_quiesce;
public	fd_status;


page
;
;	data area for tables and constants
;


;
;	speed tables used in reading floppy disks
;	NOTE:	prolog must directly preceed speeds !!!
;
prolog	db	15,4,17,1;				command prologue
speeds	db	3Eh,49h,53h,5Dh,67h,71h,7Bh,86h,8Ah;	speeds

tzones	db	3,15,26,37,47,59,70,82,97;		speed change locations
spt	db	19,18,17,16,15,14,13,12,11;		sectors per track


page
;
;	reset function for floppy disk
;
;	input:	none
;
;	output:	all registers destroyed
;
fd_reset	proc;

	xor	ax,ax;		flag good results
	ret;

fd_reset	endp;



;
;	checks to see if floppy disk control unit is present
;
;	input:	parameters as specified in load request block
;
;	output:	z-flag is set if and only if operation is successful
;		lrb's status field is set to which drives are present
;		all registers are destroyed
;

fd_cup	proc;

	mov	ax,seg ioports;		address the floppy I/O registers
	mov	es,ax;

	call	resethdw;		clear all floppy I/O registers

;
;	issue a test pattern to see if the controller is there
;
	mov	dl,1;			initial test pattern for hardware

test_loop:;

	or	dl,80h;			add the "set interrupt bit" flag
	mov	es:[intps],dl;		set the interrupt register
	mov	al,es:[intps];		read the register

	and	al,07Fh;		ignore high order bit
	and	dl,07Fh;
	cmp	al,dl;			pattern matches ?
	jz	pattern_matches;	yes.
	jmp	cu_not_there;		no, floppy controller is not there

pattern_matches:;
	shl	dl,1;			compute next test pattern

	mov	byte ptr es:[intps],07Fh;	reset all interrupt bits
 	mov	al,es:[intps];		read it
	and	al,07Fh;		ignore high-order bit
	jz	zeroed_ok;		was correctly reset
	jmp	cu_not_there;		wasn't reset, controller absent

zeroed_ok:;
	cmp	dl,80h;			done ?
	jnz	test_loop;		no, continue testing

;
;	controller is present, initialize it
;

	xor	ax,ax;
	mov	word ptr curtrk,ax;	flag both drives on track zero

;
;	turn the motor off on both drives & put arm on track 0,4,8,...
;
	mov	es:[motor_0],f_stptk0 or f_motoff;
	mov	es:[motor_1],f_stptk0 or f_motoff;
	mov	es:[motor_dda],f_motorbits or f_stepbits;
	mov	es:[motor_ddb],f_motorbits or f_stepbits;

;
;	set speed control processor to data mode so we can load it
;
	mov	es:[mode],0Eh;

;
;	initialize direction of lines for "peripheral port A"
;
	mov	es:[data_dda],f_led0 or f_led1 or f_selbit or f_sidesel;

;
;	reset speed controller and enable steppers
;
	mov	es:[read_perb],f_screset or f_s0enab or f_s1enab;
	mov	es:[data_ddb],f_screset or f_s0enab or f_s1enab;

;
;	erase head off, write off
;
	mov	es:[readwrite_erase],0EEh;

;
;	reset the speed control processor and ensure it "takes"
;
	xor	es:[read_perb],f_screset;

wait:;
	mov	al,es:[read_perb];
	and	al,spc_data_rdy or spc_data_rcvd;
	jnz	wait;			speed control processor reset ?


	mov	byte ptr es:[diskout_ddb],0FFh;	direction for disk output

	mov	byte ptr es:[acr],01h;	enable latching on diskdata (input)


page
;
;	controller is initialized, see which drives are there
;

	xor	dl,dl;		initially, no drives present
	xor	bl,bl;		start with drive 0

drive_test:;
	call	sel_drv;	light led on drive #bl

	call	zero_chk;	is drive on track 0 ?
	jnz	not_on_zero;	no, skip (drive is present)

	call	step_in;	drive is on track 0 (or not there)
	call	step_in;
	call	step_in;	do 4 step_in's to keep at multiple of 4
	call	step_in;	(leaves stepper phase at state 0)

	call	zero_chk;	still on track 0 ?
	jz	try_next;	yes, the drive must not be present

not_on_zero:;
	add	dl,bl;		drive is not on track 0, so must be present
	inc	dl;		bit 1 for drive 0, bit 2 for drive 1 present

try_next:;
	call	motor_off;	turn this drive's motor back off
	inc	bl;		next drive;
	cmp	bl,2;		done ?
	jnz	drive_test;	no, do drive 1
	
	mov	lrb.status,dl;	indicate which drives are there

	call	desel_drvs;	and turn the led's back off

;
;	return, control unit is there
;
	xor	ax,ax;		flag control unit is there

cu_not_there:;
	ret;			with z-flag being the result

fd_cup	endp;





page
;
;	test if floppy drive is ready (that is, the door is closed)
;
;	inputs:		load request block set up
;
;	results:	z-flag is set if device is ready
;			all registers are destroyed
;
fd_dvcrdy	proc;

	mov	ax,seg ioports;		address the floppy I/O registers
	mov	es,ax;

	mov	bl,byte ptr lrb.dun;	get device and unit
	and	bl,1;			get drive number (0 or 1)

check_again:;
	mov	cl,es:[read_perb];	read door statuses

	mov	dl,f_door0;
	or	bl,bl;			which drive ?
	jz	want_door0;		zero, skip
	mov	dl,f_door1;		select which drive's door

want_door0:;
	and	cl,dl;			cl has result for now

	mov	ax,200;			wait for 20,000 microseconds	
	call	time;			for debouncing the door status

	mov	al,byte ptr es:[read_perb];	read it again
	and	al,dl;			al has status for this time

	cmp	al,cl;			bouncing ?
	jnz	check_again;		yes, try again to debounce result

;
;	have a result for the door--
;		but if it is closed, turn on motor to seat disk properly
;
	or	al,al;			set z-flag to the result
	jnz	open;			it's open, just return

;
;	start the motor
;
	xor	bh,bh;			bl is drive, use bx as index

	lea	si,ioports:motor_0;	base of speed control registers
	sub	si,bx;			select drive's register
	mov	al,es:[si];		read motor information
	and	al,0FFh - f_motoff;	get rid of speed status
;					and use speed zone 0
	mov	es:[si],al;		and write to drive's motor control

	xor	ax,ax;			flag door is closed
open:;
	ret;				(zero if it's present)

fd_dvcrdy	endp;




;
;	Bring a floppy disk drive on-line.
;
;	(Read the label, update the boot vector table,
;	load request block, and set the speed control
;	processor.  The drive will have the motor on at
;	track 0 with the new speed set.  On error, the
;	motor is off, speed control processor isn't loaded.)
;
;	inputs:		load request block set up
;
;	outputs:	lrb updated, z-flag is set if success
;			all registers are destroyed
;
fd_online	proc;

	mov	ax,seg ioports;		address the floppy I/O registers
	mov	es,ax;

;
;	validate device/unit parameter from lrb
;
	mov	bx,lrb.dun;		get the device and unit

	cmp	bx,1;			drive too big ?
	jbe	no_error_in_dun;	no, skip the error

	mov	lrb.status,bad_dun;	set error of invalid dun
	jmp	online_error;


;
;	get the drive into a known state
;
no_error_in_dun:;
	mov	al,curtrk[bx];		get track on drive
	call	get_zon;		find out the zone for that track

	lea	si,ioports:motor_0;	base of speed control registers
	sub	si,bx;			select drive's register
	mov	al,es:[si];		read motor information
	and	al,0FFh - f_motoff;	get rid of speed status

	or	al,cl;			combine zone with read data
	mov	es:[si],al;		and write to drive's motor control

	call	sel_drv;		select the drive
	mov	al,es:[si];		read it's motor control
	and	al,f_motorbits;		ignore old stepper value
	or	al,f_stptk0;		set stepper to track 0,4,8,...
	mov	es:[si],al;		and issue the command

;
;	step outwards until on track zero
;
	mov	dx,max_tracks;		could take up to 88 tries

step_again:;
	call	zero_chk;		on track zero ?
	jz	set_on_track_zero;	yes, quit

	call	step_out;		no, step one more track

	dec	dx;			one more try ?
	jnz	step_again;		yes, step some more

;					no, just quit
set_on_track_zero:;

	mov	byte ptr curtrk[bx],0;	say on track 0 now


;
;	read label into buffer
;
	mov	ax,label_size;		set size of label
	mov	lrb.ssz,ax;

	xor	ax,ax;	
	mov	lrb.da,ax;		disk address of zero
	mov	lrb.da+2,ax;

	mov	word ptr lrb.dma+2,ax;	segment of label buffer
	lea	di,dgroup:bootr;	offset of label buffer
	mov	lrb.dma,di;

	inc	ax;
	mov	lrb.blkcnt,ax;		read one block

	call	fd_read;		read the label
	jz	read_ok;
	jmp	online_error;		couldn't read, error

read_ok:;
	cmp	bootr.valid,os_label;	valid label ?
	jz	label_valid;		yes, skip

	mov	lrb.status,no_system;	error, label says no O/S
	jmp	online_error;

label_valid:;
;
;	update bvt and lrb from floppy disk's label
;
	mov	ax,bootr.sector_size;
	mov	lrb.ssz,ax;			store sector size

	mov	ax,bootr.load;			copy load address for image
	mov	lrb.loadaddr,ax;

	mov	ax,bootr.paras;			and size in paragraphs
	mov	lrb.loadpara,ax;

	mov	ax,bootr.entry_offset;
	mov	word ptr lrb.loadentry,ax;	copy the O/S's entry address
	mov	ax,bootr.entry_segment;
	mov	word ptr lrb.loadentry+2,ax;

	mov	ax,bootr.boot_start;		and the disk address
	mov	lrb.da,ax;

;
;	load the speed control tables
;

;
;	reset speed control processor and reset handshake lines
;
	mov	al,es:[read_perb];	speed control processor data
	and	al,0FFh - spc_data_rdy - spc_data_rcvd;
	or	al,f_screset;
	mov	es:[read_perb],al;	reset the processor

	mov	al,es:[data_ddb];	data direction for speed controller
	or	al,spc_data_rdy or spc_data_rcvd;
	mov	es:[data_ddb],al;	reset the handshake lines

;
;	set motor speed to inputs
;
	mov	al,f_stepbits;		select bits for output to
	mov	es:[motor_dda],al;	set register to load processor
	mov	es:[motor_ddb],al;

	xor	es:[read_perb],f_screset;	unreset speed controller

;
;	wait for speed control processor ready
;
ready_wait:;
	mov	al,es:[motor_0];	get speed control outputs
	or	al,es:[motor_1];
	and	al,f_motorbits;		bits are all zero when ready
	jnz	ready_wait;		not ready, yet

;
;	acknowledge the speed control processor
;
	or	es:[read_perb],spc_data_rdy or spc_data_rcvd;

;
;	wait for speed control processor not ready
;
not_ready_wait:;
	mov	al,es:[motor_0];	get speed control outputs
	and	al,es:[motor_1];
	and	al,f_motorbits;		bits are one when not ready
	cmp	al,f_motorbits;
	jnz	not_ready_wait;		not not-ready, yet

;
;	make the motor and step bits outputs
;
	mov	es:[motor_dda],f_motorbits or f_stepbits;
	mov	es:[motor_ddb],f_motorbits or f_stepbits;

;
;	acknowledge the input
;
	xor	es:[data_ddb],spc_data_rcvd;

;
;	send speed control processor the speed tables
;
	xor	bp,bp;			index for table entry

send_next:;
	mov	al,es:[motor_0];	read motor speed register
	and	al,f_stepbits;		keep only the step bits
	or	al,cs:prolog[bp];	provide the speed data
	and	al,f_motorbits;		keep only the motor bits
	mov	es:[motor_0],al;

	mov	al,es:[motor_1];	read motor speed register
	and	al,f_stepbits;		keep only the step bits
	mov	ch,cs:prolog[bp];	provide the speed data
	mov	cl,4;
	shr	ch,cl;			move the bits down
	or	al,ch;
	mov	es:[motor_1],al;

;
;	tell processor data is there, wait for it to acknowledge receipt
;
	xor	es:[read_perb],spc_data_rdy;

ack_wait:;
	test	es:[read_perb],spc_data_rcvd;
	jnz	ack_wait;

;
;	clear data ready, wait for acknowledge to go away
;
	xor	es:[read_perb],spc_data_rdy;

not_ack_wait:;
	test	es:[read_perb],spc_data_rcvd;
	jz	not_ack_wait;

;
;	loop sending each byte of the speed control table
;
	inc	bp;		next byte
	cmp	bp,speed_header+speed_zones;	done ?
	jnz	send_next;	no, loop


;
;	speed control processor loaded, turn off motors
;
;
;	turn the motor off on both drives & put arm on track 0
;
	mov	es:[motor_0],f_stptk0 or f_motoff;
	mov	es:[motor_1],f_stptk0 or f_motoff;
	mov	es:[motor_dda],f_motorbits or f_stepbits;
	mov	es:[motor_ddb],f_motorbits or f_stepbits;
						
	xor	es:[read_perb],spc_data_rdy;	set data ready

ack_wait2:;
	test	es:[read_perb],spc_data_rcvd;
	jnz	ack_wait2;		wait for acknowledgement

	xor	es:[data_ddb],spc_data_rdy;	set ready for input

	xor	ax,ax;			return success in z-flag
	ret;

;
;	here if error occurred
;
online_error:;
	call	motor_off;		turn off the floppy's motor
	call	desel_drvs;		turn off led's
any_error:;
	mov	ax,1;			flag an error
	or	ax,ax;			z-flag is nz for errors
	ret;


fd_online	endp;




;
;	read a boot image from the floppy disk
;
;	inputs:		load request block set up
;
;	outputs:	z-flag is set for successful read
;			lrb updated
;			all registers destroyed
;
fd_read		proc;

	mov	ax,seg ioports;		address the floppy I/O registers
	mov	es,ax;

;
;	check validity of requested operation
;
	xor	cl,cl;			initially, no error found

	mov	bx,lrb.dun;		get device and unit
	cmp	bx,1;			more than 1 ?
	jbe	in_range;		no, skip

	mov	cl,bad_dun;		invalid unit specified

in_range:;
	cmp	word ptr lrb.da+2,0;	high-order sector address
	jz	sector_ok;		zero, valid

	mov	cl,bad_da;		invalid sector address

sector_ok:;
	or	cl,cl;			errors ?
	jz	no_errors;		no, skip

	mov	lrb.status,cl;		set the return status
	jmp	any_error;

;
;	set up for the read
;
no_errors:;
	mov	ax,word ptr lrb.dma;
	mov	cx,word ptr lrb.dma+2;
	mov	word ptr fldma,ax;	save dma address
	mov	word ptr fldma+2,cx;

	call	sel_drv;		select the drive


;
;	loop to read each block from disk, finally filling the request
;

read_next_block:;

	cmp	lrb.blkcnt,0;		done ?	
	jnz	read_more;		no
	jmp	dquit;			yes.

read_more:;
	mov	dx,word ptr lrb.da;	get absolute disk address

;
;	find out what zone the particular sector is in
;	in order to compute what track and sector to access
;	(non-trivial since there's a variable number of sectors per track)
;
	xor	bp,bp;			index through each speed zone
	xor	cl,cl;			initialize starting track of this zone
zone_search:;
	mov	al,cs:tzones[bp];	get ending track of this zone
	inc	al;			now, it's starting track of next zone
	sub	al,cl;			minus starting track of this zone
;					yields size of this zone in tracks
	xor	ah,ah;			prepare for multiplication
	mul	cs:spt[bp];		tracks in this zone * sectors per track
;					yields sectors in this zone
	cmp	dx,ax;			sector looking for in this zone ?
	jb	end_search;		yes, found it.

	sub	dx,ax;			subtract sectors in this zone
;					from sector looking for
	mov	cl,cs:tzones[bp];	last track of this zone
	inc	cl;			now, it's starting track of next zone

	inc	bp;			try next zone
	jmp	zone_search;

;
;	know zone for sector, compute track and sector
;
end_search:;
	mov	ax,dx;
	div	cs:spt[bp];		divide sector displacement in zone
;					by sectors per track . . .
;					ah = sector offset in track (modulo)
;					al = track offset in zone (quotient)
	mov	sec,ah;			save the sector
	add	al,cl;			add first track in zone to track
;					offset in zone (is track to access)
	mov	trk,al;			and save the track

	mov	dl,cs:spt[bp];		get number of sectors per track
	sub	dl,sec;			sectors per track minus
;					sector we're looking for
;					yields sectors left in track

	xor	dh,dh;
	cmp	dx,lrb.blkcnt;		sectors left less than number requested?
	jbe	skip;			yes, can only read rest of track
	mov	dx,lrb.blkcnt;		no, can read entire number requested
skip:;
	mov	seccnt,dl;		save number of sectors we're reading
	mov	sav_seccnt,dl;		and permanently save it

page
;
;	perform the read (up to a track's worth)
;

	mov	bp,10;			retries for offtrack seeks
;
;	seek to the desired track
;

;
;	find index and set speed
;
find_track:;
	lea	si,ioports:motor_0;	base of speed control registers
	sub	si,bx;			select drive's register
	mov	dl,es:[si];		read motor information

	mov	dh,dl;			save for later
	and	dl,0FFh - f_motorbits;	save the stepper bits only

	mov	al,trk;			track we want
	call	get_zon;		get zone number for this track

	or	al,dl;			get zone for speed control processor
	mov	es:[si],al;		and it will figure the speed

;
;	wait for speed control processor if motor was off
;
	and	dh,f_motorbits;		look at motor status (stepper)
	cmp	dh,f_motoff;		was off ?
	jne	was_on;			no, skip

	mov	ax,350;			wait 35,000 micro seconds
	call	time;
was_on:;

;
;	now, seek the the right track
;
	mov	dl,curtrk[bx];		get our present track setting
move_more:;
	cmp	trk,dl;			compare to where we want to be
	je	just_settle;		we're there, just let it settle

	jb	step_it_out;		outwards
	call	step_in;		inwards
	inc	dl;			new track number
	jmp	move_more;

step_it_out:;
	call	zero_chk;		on track zero ?
	jz	no_more;		yes, can't move more
	call	step_out;		otherwise move some more
no_more:;
	dec	dl;			new track number
	jmp	move_more;

;
;	at the new track
;
just_settle:;
	mov	curtrk[bx],dl;		save new track number

	mov	ax,350;			wait 35,000 microseconds for settling
	call	time;			stepper or speed processor settle time

;
;	head is on the track, now ready the motor
;

motor_wait:;
	mov	al,es:[read_perb];	read peripheral B register
	mov	dl,f_rdy0;		look at motor speed ready
	mov	cl,bl;			get drive
	shl	dl,cl;			compute bit to test for correct drive

	and	al,dl;			wait until it's ready
	jz	motor_wait;

	mov	ax,100;			then let it settle
	call	time;			wait 10,000 micro seconds


page


;
;	read the boot image
;


readseek:;
	mov	sector_retry,10;	retry counter for sector reads
	mov	si,255;			allow 255 soft errors per sector read

seek:;
	mov	dx,5000;		sync time out counter

	mov	cl,76h;			fine-tuned timing value

	mov	ah,f_door0;		drive 0	door bit
	test	bl,1;			see which drive
	jz	seek10;			skip if door 0
	mov	ah,f_door1;		make door1


;
;	wait for a sync to align on the track
;
seek10:;
	test	es:[read_pera],fsynbit;	test if sync present
	jz	seek15;			yes

	shl	al,cl;			no, wait 104 us
	test	es:[read_perb],ah;	see if door opened
	jnz	dooropnd;		yes, quit with an error

	dec	dx;			retry counter for seeing a sync
	jnz	seek10;			retry (total 114 us sample interval)

;
;	error, no sync found
;
	mov	ah,no_sync;		error 1, no sync
	jmp	harderr;

;
;	error, door opened during operation
;
dooropnd:;
	mov	ah,door_opened;		door opened error code
	jmp	harderr;	



;
;	sync has started, wait for end of it
;
seek15:;
	mov	al,es:[dskdata];	wait for data byte
	mov	dx,69;			retry for data (640us is too much sync)

seek16:;
	test	es:[read_pera],fsynbit;	9us loop
	jnz	seek18;			end of sync, in good shape

	dec	dx;			decrement retry counter
	jnz	seek16;			not too long, wait for end

;
;	error, sync is too long
;
	mov	ah,long_sync;		error 8, sync for too long a time
	jmp short softerr;		can retry this error



;
;	got the end of the sync, look for header
;
seek18:;
	cmp	dx,12;			sync long enough to qualify ?
	jbe	seek10;			no, pretend we didn't see a sync

	wait;				wait for synchronization from disk

	cmp	es:[dskdata],fhid;	is the data a header ID ?
	jz	seek20;			yes, found header

;
;	error, didn't find a header
;
	mov	ah,no_header_id;	didn't find header
	jmp short softerr;		can retry this one


;
;	found the header, check out our position on the track
;
seek20:;
	wait;				wait for disk data
	mov	al,es:[dskdata];	track number
	mov	dh,al;			checksum calculation in dh

	wait;				wait for disk data
	mov	ah,es:[dskdata];	sector number
	add	dh,ah;			add into checksum

	wait;				wait for disk data
	mov	dl,es:[dskdata];	header checksum

	cmp	dh,dl;			compare checksum
	jz	seek25;			ok

;
;	error, bad checksum in the header
;
	mov	ah,header_checksum;	error 3 is bad header checksum
	jmp short softerr;		can retry this one



;
;	read the header, check if it's the right track and sector
;
seek25:;
	cmp	trk,al;			test if right track
	jz	seek30;			correct, skip

;
;	error, requested track doesn't match the one we got
;
	mov	curtrk[bx],al;		say we're on this track, now
	dec	bp;			up to 10 tries for off-track errors
	jz	too_many_offtracks;
	jmp	find_track;		retry it.

too_many_offtracks:;
	mov	ah,wrong_track;		error 4, track mismatch
harderr2:;
	jmp	harderr;		unrecoverable error


seek30:;
	cmp	sec,ah;			test if right sector
	jz	readsector;		yes, read it



;
;	error, requested sector doesn't match the one we got
;
	mov	ah,wrong_sector;	error 5, try again to get sector

;
;	retryable error
;
softerr:;
	xor	dx,dx;			restore data segment
	mov	ds,dx;

	dec	si;			try again ?
	je	harderr2;		too many errors, harderror
	jmp	seek;			try again



page
;
;	have right sector, time to read it
;
readsector:;
	mov	cx,lrb.ssz;		sector byte count
	lds	di,fldma;		set destination of the read
;					CAUTION:  DS MUST BE RESTORED !!!

	xor	dx,dx;			initialize checksum
	xor	ah,ah;			high byte of read data

doread10:;
	test	es:[read_pera],fsynbit;	wait for data block
	jnz	doread10;

	mov	al,es:[dskdata];	reset sync interrupt request
	mov	al,es:[clrgcr];		clear latched gcr

	wait;				wait for disk data
	cmp	es:[dskdata],fdid;	test if a data block ID
	je	doread19;		yes, continue

;
;	error, no data block ID after the header
;
	mov	ah,no_data_id;		error 6, no data ID
	jmp	softerr;		is recoverable


;
;	have a data ID
;
doread19:;
	wait;				wait for disk data
	mov	al,es:[dskdata];	read a byte of data
	add	dx,ax;			calculate the checksum

	mov	ds:[di],al;		save the data byte

	inc	di;			advance "dma" pointer
	loop   doread19;		repeat until a sector is read

	xor	ax,ax;
	mov	ds,ax;			restore data segment

	wait;				wait for disk data
	mov	al,es:[dskdata];	read low byte of the checksum
	wait;				wait for disk data
	mov	ah,es:[dskdata];	read high byte of the checksum

	cmp	ax,dx;			checksum matches ?
	je	okchksum;		yes, continue tests


;
;	error in checksum on reading a sector
;
	mov	ah,data_checksum;	preset to checksum error
	dec	sector_retry;		read error counter
	jz	harderr;		quit, too many retries
	jmp	seek;			start seeking over again


;
;	checksum is valid, now test for gcr error
;
okchksum:;
	test	es:[fgcr],gcrerr;	see if error set
	jz	okgcr;			no, skip

;
;	error, bad gcr
;
	mov	ah,gcr_error;		error code for bad gcr
	jmp	softerr;		but is retryable


page
;
;	the gcr is valid, that sector was successfully read
;
okgcr:;
	inc	sec;			calculate next sector number

	mov	ax,lrb.ssz;		get sector size in bytes
	mov	cl,4;
	shr	ax,cl;			convert to paragraphs
	add	word ptr fldma+2,ax;	bump segment number for dma

	dec	seccnt;			one more sector read on track
	jz	 jobdone;		finished with this track
	jmp	readseek;		do next sector


;
;	error, block was not successfully read
;
harderr:;
	mov	lrb.status,ah;		set return status
	call	motor_off;		turn motor back off
	call	desel_drvs;
	mov	ah,1;
	or	ax,ax;			reflect error in z-flag
	ret;


;
;	all sectors in the track were read, do rest of the request
;
jobdone:;

	mov	al,sav_seccnt;		number of sectors read
	xor	ah,ah;

	sub	lrb.blkcnt,ax;		decrement blocks to read
	add	lrb.da,ax;		increment disk address by that amount

	jmp	read_next_block;	read next block from disk




;
;	the requested read is completed successfully
;
dquit:;
	mov	ax,word ptr fldma;	get current dma address
	mov	lrb.dma,ax;		and update lrb
	mov	ax,word ptr fldma+2;
	mov	lrb.dma+2,ax;

	call	motor_off;		turn motor back off
	call	desel_drvs;		deselect the drives

	xor	ax,ax;			flag no error in z-flag
	ret;


fd_read		endp;




page
;
;	quiesces a floppy disk unit (turns the motor off)
;
;	input:	parameters as specified in load request block
;
;	output:	z-flag is set if and only if operation is successful
;		all registers are destroyed
;

fd_quiesce	proc;

	mov	ax,seg ioports;		address the floppy I/O registers
	mov	es,ax;

	mov	bl,byte ptr lrb.dun;	get device and unit
	and	bl,1;			get drive number (0 or 1)

	call	motor_off;		turn off the motor

	xor	ax,ax;			flag no error
	ret;

fd_quiesce	endp;


page
;
;	test if floppy drive is ready (that is, the door is closed)
;	(do not turn on the motor if it is)
;
;	inputs:		load request block set up
;
;	results:	z-flag is set if device is ready
;			all registers are destroyed
;
fd_status	proc;

	mov	ax,seg ioports;		address the floppy I/O registers
	mov	es,ax;

	mov	bl,byte ptr lrb.dun;	get device and unit
	and	bl,1;			get drive number (0 or 1)

status_check_again:;
	mov	cl,es:[read_perb];	read door statuses

	mov	dl,f_door0;
	or	bl,bl;			which drive ?
	jz	status_want_door0;	zero, skip
	mov	dl,f_door1;		select which drive's door

status_want_door0:;
	and	cl,dl;			cl has result for now

	mov	ax,200;			wait for 20,000 microseconds	
	call	time;			for debouncing the door status

	mov	al,byte ptr es:[read_perb];	read it again
	and	al,dl;			al has status for this time

	cmp	al,cl;			bouncing ?
	jnz	status_check_again;	yes, try again to debounce result

;
;	have a result for the door--
;		but if it is closed, turn on motor to seat disk properly
;
	or	al,al;			set z-flag to the result
	ret;				(zero if it's present)

fd_status	endp;




page

;
;	Step selected drive out one track.
;
;	The stepper motor is issued "tab stops" to position it.
;	A value of "A hex" will position it on track 0,4,8,...
;	A value of "9 hex" will position it on track 3,7,11,...
;	A value of "5 hex" will position it on track 2,6,10,...
;	A value of "6 hex" will position it on track 1,5,9,...
;	By cycling values of A, 9, 5, 6, A, 9, 5, ... the arm will step out.
;
;	input:		bl = drive number
;
;	results:	ax,cx,si destroyed
;

step_out_table	db	050h,090h,060h,0A0h;

step_out	proc;

	push	di;			save caller's register
	lea	di,cgroup:step_out_table;address of table to step arm out

step_it:;
	lea	si,ioports:motor_0;	base of speed control registers
	sub	si,bx;			select drive's register
	mov	al,es:[si];		motor information (current position)
	mov	ch,al;			save for later

	mov	cl,5;
	shr	al,cl;			middle stepper bits are unique index
	and	al,03h;
	xor	ah,ah;
	add	di,ax;			index into stepper transition table

	mov	al,cs:[di];		get new stepper value
	and	ch,f_motorbits;		remove the stepper bits from original
	or	ch,al;			add in the new stepper value

	mov	es:[si],ch;		and output the new value

	mov	ax,50;			wait 5000 micro seconds
	call	time;			(5 milliseconds)

	pop	di;			restore caller's register
	ret;

step_out	endp;




;
;	Step selected drive in one track.
;
;	The stepper motor is issued "tab stops" to position it.
;	A value of "A hex" will position it on track 0,4,8,...
;	A value of "6 hex" will position it on track 1,5,9,...
;	A value of "5 hex" will position it on track 2,6,10,...
;	A value of "9 hex" will position it on track 3,7,11,...
;	By cycling values of A, 6, 5, 9, A, 6, 5, ... the arm will step in.
;
;	input:		bl = drive number
;
;	results:	ax,cx,si destroyed
;

step_in_table	db	0A0h,060h,090h,050h;

step_in		proc;

	push	di;			save caller's register
	lea	di,cgroup:step_in_table;address of table to step arm in
	jmp	step_it;		go to common stepping code

step_in		endp;



;
;	tells whether on track 0
;
;	input:		bl = drive to check
;
;	results:	z-flag is set if on track 0
;			ax,cx destroyed
;
zero_chk	proc;

	lea	si,ioports:motor_0;	base of speed control registers
	sub	si,bx;			select drive's register
	mov	al,es:[si];		motor information (current position)

	and	al,f_stepbits;		look at step bits
	cmp	al,f_stptk0;		on track 0, 4, 8, etc ?
	jnz	aint_on_zero;		no, can't be on zero

	mov	cl,bl;			get drive's number
	shl	cl,1;			for drive 0 or 1, get a 0 or 2

	mov	ch,drv0_trk0;		bit to test for drive 0
	shl	ch,cl;			position bit for drive's test

	test	es:[read_pera],ch;	get drive's NOT track 0 sense

aint_on_zero:;
	ret;

zero_chk	endp;



;
;	select a drive
;
;	input:		bl = drive to select
;
;	results:	ax, cx destroyed
;
sel_drv		proc;

;
;	set LED's and drive select
;
	mov	cl,es:[read_pera];
	and	cl,0FFh - f_selbit - f_led0 - f_led1;	led, select off

	mov	al,f_led0;		preset to drive 0 select and led
	or	bl,bl;			drive 1 ?
	jz	want_drive0;		no, skip
	mov	al,f_led1+f_selbit;	yes, that led and select drive 1

want_drive0:;
	or	al,cl;
	mov	es:[read_pera],al;	turn the proper led, select on

;
;	set stepper enables
;
	mov	ch,es:[read_perb];
	or	ch,f_s0enab or f_s1enab;	stepper enables

	mov	al,f_s0enab;
	mov	cl,bl;
	shl	al,cl;			select proper enable for the drive

	xor	al,0FFh;
	and	al,ch;			and turn that bit off
	mov	es:[read_perb],al;

	ret;

sel_drv		endp;






;
;	deselect the drives
;
;	inputs:		none
;
;	results:	ax destroyed
;
desel_drvs	proc;

	or	es:[read_perb],f_s0enab or f_s1enab;	motors off

	and	es:[read_pera],0FFh - f_led0 - f_led1;	and led's off

	ret;

desel_drvs	endp;





;
;	turn the motors off on both drives
;
;	inputs:		bl = drive's number
;
;	results:	ax destroyed
;
motor_off	proc;

	or	es:[motor_0],f_motorbits;	motors off
	or	es:[motor_1],f_motorbits;
	
	and	es:[read_pera],0FFh - f_led0 - f_led1;	turn the led's off, too
	call	desel_drvs;			and deselect both drives

	ret;

motor_off	endp;





;
;	return proper speed index for the track's zone
;
;	inputs:		al = track
;
;	outputs:	ax ,cx = speed zone index
;
get_zon		proc;

	push	bp;
	xor	bp,bp;		scan zone table from 0 to 14

next_entry:;
	cmp	al,cs:tzones[bp];
	ja	not_the_one;	not speed for this track, skip

	mov	ax,bp;		return the index of the zone
	mov	cx,bp;

	pop	bp;
	ret;

not_the_one:;
	inc	bp;		try next table element
	cmp	bp,speed_zones;	done ?
	jnz	next_entry;	no, loop

	jmp	err_intern;	yes, internal error (didn't find it)

get_zon		endp;




;
;	reset the floppy disk hardware
;
;	inputs:		none
;
;	results:	all registers destroyed
;
resethdw	proc;

	lea	di,ioports:motor_1;	base of I/O registers

	mov	cx,3;			3 sets to clear
;
;	clear programmed interface adapter registers
;
resetpl:;
	mov	dx,cx;
	mov	cx,14;			14 bytes to clear for each set
	cld;
	xor	al,al;
	rep	stosb;			zero the registers

	mov	al,7fh;			get the interrupt enable register
	stosb;				(must be set to 7F)

	mov	cx,dx;			restore set counter
	add	di,17;			displacement to next set
	loop	resetpl;		until all 3 sets cleared

	ret;

resethdw endp;	



code	ends;


	end;
