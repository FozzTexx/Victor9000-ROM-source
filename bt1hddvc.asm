include bt1ttl.inc

;
;
;	hard disk driver for the universal boot rom
;
;
name hddvc;



cgroup	group code;
dgroup  group data;
assume	cs:cgroup,ds:dgroup,es:hdspace;




data	segment 'data' public;


;
;	hard disk request equates
;
hdonln	equ	4000h+01h;	online request from the boot's base module
hdread	equ	0000h+01h;	internal read disk request
recal	equ	0000h+03h;	internal recalibrate disk request
hdldprm	equ	0000h+04h;	internal load controller parameters request


;
;	error return codes displayed by the boot base driver
;
hderrda		equ	3Ch;		bad disk address requested from S/W
hderrcmd	equ	3Dh;		invalid command requested from S/W
hderrto		equ	3Fh;		controller timeout
badop		equ	40h;		bad operation requested
badvars		equ	41h;		bad controller parameters
hderrbc		equ	4Fh;		invalid block count requested from S/W
badhlbl		equ	98h;		invalid hard disk label
nohdos		equ	99h;		no O/S on disk


extrn	hdctlop:byte;		flags hard disk controller which is in use
extrn	hdctlcmd:byte;		control field to send with commands
extrn	hdctlimg:byte;		save area for image of command to controller
extrn	sense:byte;		4-byte area for reading sense information

include	bt1lrb.str;		format of the load request block
extrn	lrb:lrbs;		load request block

include	bt1hdlbl.str;		format of hard disk label
extrn	bootr:hdlbl;		label buffer in low memory

include	bt1bvt.str;		format of the boot vector table
extrn	bvt:byte;		boot vector table to pass to O/S

extrn	rgncnt:byte;		number of regions on the disk
extrn	lalist:byte;		table for logical to physical address changing
extrn	dada:dword;		save area for disk address


data	ends;


page

;
;	hard disk I/O registers
;
hdspace segment at 0EF30h;


	org	00h;
hdctl	equ	byte ptr $;		control (write only)
;					initial condition = 04h
dmaen	equ	01h;			enable DMA
dmastb	equ	04h;			strobe DMA
dmadir	equ	08h;			dma direction (1 = to us)  
selct	equ	10h;			select request
reset	equ	20h;			1 => reset controller(s)  new DMA


	org	10h;
hdcsd	equ	byte ptr $;		command and status sense (read/write)
hderr	equ	2;			status bit indicates an error
hdlun	equ	7;			logical unit number mask
hdselm	equ	0F8h;			select mask


	org	20h;
hdbus	equ	byte ptr $;		bus status (read only)
input	equ	01h;			input mode
control	equ	02h;			control mode
busy	equ	04h;			busy
req	equ	08h;			request mode
msg	equ	10h;			message mode


	org	80h;
hddmal	equ	byte ptr $;		low byte of DMA address (read/write)


	org	0A0h;
hddmam	equ	byte ptr $;		middle byte of DMA address (read/write)


	org	0C0h;
hddmah	equ	byte ptr $;		high byte of DMA address (read/write)


;
;	miscellaneous equates
;
habsmsk		equ	01Fh;		masks logical unit from absolute sector

statuscmd	equ	00h;		status request
hdrecal		equ	01H;		recalibrate
senscmd		equ	03h;		sense request
hdrd		equ	08h;		read
hdwrt		equ	0Ah;		write
hdprmld		equ	0Ch;		load parameters



hdspace		ends;


page


code	segment	public 'code';

public	hd_reset;		reset hard disk subsystem
public	hd_cup;			test for hard disk control unit present
public	hd_dvcrdy;		test for device ready
public	hd_online;		bring hard disk on-line
public	hd_read;		read from hard disk
public	hd_quiesce;		quiesce the hard disk


;
;	general equates
;
ramdiag	equ	0E0h;		xebec internal ram diagnostic
ctldiag	equ	0E4h;		xebec internal controller diagnostic

bsyto	equ	0FFh;		retry counter for controller to go busy
ctlto	equ	0FFh;		retry counter for getting control mode
requto	equ	0FFh;		retry counter for getting request mode


page
;
;	constants in the code segment
;



;
;	table of commands for various hard disk operations
;
hicmd	equ	04h;		maximum command index for table below
cmdtab	db	hicmd,0,hdrd,hdwrt,hdrecal,hdprmld;


;
;	table of DMA state for various hard disk operations
;
dmaenab	equ	02h;		flags need DMA action
dmatab	db	0,dmaenab+dmadir,dmaenab+0,dmadir,dmaenab+0;


page

;
;	reset the hard disk subsystem
;
;	inputs:		none
;
;	outputs:	all registers destroyed
;

hd_reset	proc;

	xor	ax,ax;			flag no errors

	ret;

hd_reset endp;



;
;	test if control unit is present
;
;	inputs:		load request block set up
;
;	outputs:	z-flag set => no dma, no controller
;			non-zero => dma, controller attached
;
hd_cup		proc;

	mov	ax,hdspace;	address the hard disk I/O registers
	mov	es,ax;

;
;	check if DMA board is present
;
	call	hddmdis;	disable DMA activities

	mov	cx,2;		we'll try 2 test patterns of alternating bits

	mov	al,5h;		high nibble of test pattern
	mov	dx,0AA55h;	middle and low bytes of test pattern

hdcuctl:;
	call	loadma;		load test pattern into DMA registers

	mov	ah,al;		save current pattern
	mov	si,dx;

;
;	read the DMA registers
;
 	mov	al,es:hddmah;	high byte of DMA address
 	mov	dh,es:hddmam;	middle byte of DMA address
 	mov	dl,es:hddmal;	low byte of DMA address
	and	al,0fh;		only 20 bits maximum

	cmp	al,ah;		did we read what we wrote ?
	jne	hdcunod;	no, no DMA controller

	cmp	dx,si;
	jne	hdcunod;	no, no DMA controller

	not	al;		try second test pattern
	and	al,0fh;		20 bit address only
	not	dx;

	loop	hdcuctl;	try twice

page
;
;	the DMA is present past here - now see about disk controller
;
	xor	ax,ax;
	mov	hdctlop,ah;	flag processing controller 0

	call	hd_init;	initialize hardware and data areas

hdcutest:;
	call	hdgetlun;	al=logical unit, ch=select pattern

	mov	ah,ramdiag;	tell controller to do a RAM diagnostic
	call	hdhs;		issue the command
	jnz	hdcunctl;	timeout, no disk controller
	call	hdcmplt;	wait for operation to complete
	jnz	hdcunctl;	error, no disk controller

	call	hdgetlun;	al=logical unit, ch=select pattern

	mov	ah,ctldiag;	tell controller to do its diagnostics
	call	hdhs;		issue the command
	jnz	hdcunctl;	timeout, no disk controller
	call	hdcmplt;	wait for operation to complete
	jnz	hdcunctl;	error, say no disk controller

	ret;			z-flag indicates success

;
;	a control unit is missing, test for second controller
;
hdcunctl:;
	mov	ah,hdctlop;	get controller processing
	or	ah,ah;		doing controller 0 ?
	jnz	hdcunod;	no, no controllers at all

	inc	hdctlop;	do controller 1

	mov	ax,lrb.dun;
	inc	ah;		(flag controller 1 in lrb, too)
	mov	lrb.dun,ax;

	jmp	hdcutest;	now see if this controller is there

;
;	there is no DMA or neither control unit
;
hdcunod:;
	mov	ax,1;
	or	ax,ax;		flag no controller present
	ret;

hd_cup	endp;



page
;
;	see if the hard disk device is ready (see if we can get a good status)
;
;	inputs:		load request block set up
;
;	outputs:	all registers destroyed
;			z-flag set if ready
;			z-flag is nz if not ready
;
hd_dvcrdy	proc;

	mov	ax,hdspace;		address the hard disk I/O registers
	mov	es,ax;

	mov	ax,lrb.dun;		get controller and drive
	or	ah,hdctlop;		substitute proper controller number
	mov	lrb.dun,ax;

	call	hdgetlun;		al = logical unit, ch = select pattern

	call	hddmdis;		disable DMA channel

	mov	ah,statuscmd;		request the status
	call	hdhs;			send out the command	
	jnz	not_ready;		if error, not ready

hdstok:;
	call	hdcmplt;		wait for status read completed

not_ready:;
	ret;				indicate success in z-flag

hd_dvcrdy	endp;



;
;	bring hard disk on-line
;		recalibrate until home
;		read label and update lrb
;		load controller parameters from the label
;
;	inputs:		load request block set up
;
;	outputs:	load request block updated
;			all registers destroyed
;
;	assumes hardware init has already occurred
;
hd_online proc;

	mov	ax,hdspace;		address the hard disk I/O registers
	mov	es,ax;

	xor	ax,ax;
	mov	lrb.da,ax;		ensure valid disk address
	mov	lrb.da+2,ax;

	mov	lrb.blkcnt,ax;		and block count

;
;	recalibration
;
	mov	cx,5;			retry for recalibrate errors
tryfor0:;				recal until good or count done
	mov	lrb.op,recal;		set function to recalibrate

	push	cx;			save retry counter
	call	pblock_io;		read the label
	pop	cx;			restore retry counter

	loopnz	tryfor0;		error, retry the recalibration
	jz	okrecal;		success, recalibrated
	jmp	hdonlerr;		error in putting disk on-line

;
;	read the label
;
okrecal:;
	xor	ax,ax;
	mov	lrb.da,ax;		set to read absolute sector 0
	mov	lrb.da+2,ax;

	inc	ax;
	inc	ax;
	mov	lrb.blkcnt,ax;		read two sectors (the label)

	lea	ax,bootr;		buffer used for the label
	mov	lrb.dma,ax;		is the DMA address
	mov	lrb.dma+2,ds;

	mov	lrb.op,hdread;		operation code is read

	call	pblock_io;		read the label
	jz	hdonllok;
	jmp	hdonlerr;		error in reading the label

;
;	have read the label, verify it
;
hdonllok:;
	cmp	bootr.lbltyp,1;		valid format ?
	mov	ah,badhlbl;		preset to bad label error
	jnz	hdonleri;		invalid label format

	mov	cx,word ptr bootr.iplda;have an O/S on the disk ?
	or	cx,word ptr bootr.iplda+2;
	mov	ah,nohdos;		preset to no O/S error
	jz	hdonleri;		no, error

;
;	stuff disk parameters into controller
;
	lea	ax,bootr.ctlprm;
	mov	lrb.dma,ax;		do I/O from controller parameter area
	mov	lrb.dma+2,ds;

	mov	lrb.op,hdldprm;		operation is to load parameters

	call	pblock_io;		write parameters to the controller
	jz	hdonlpok;
	jmp	hdonlerr;		error

;
;	put the hard disk region maps (used for alternate track mapping)
;	into the boot vector table
;
hdonlpok:;
	push	ds;
	pop	es;			make es address data area
	cld;

	lea	si,bootr.varlst;	base of region lists
	lodsb;				how many in available region list
	mov	ah,8;			2 double words per entry
	mul	ah;			ax = offset to working region list
	add	si,ax;			si = address of working region list

	lodsb;				count for number of working regions
	mov	ah,badvars;		preset to bad region data error
	or	al,al;			any working regions ?
	jnz	hdonlgv;		yes, that's reasonable
hdonleri:;
	jmp	hdonlerri;		error, no regions

	nop
	
hdonlgv:;
	cmp	al,word ptr 56;			only 56 regions will fit
	jbe	hdonldwl;		not too many, skip
	mov	al,56;			only handle 56 of the regions

hdonldwl:;
	mov	rgncnt,al;		store number of regions in the bvt
	inc	al;			logical address list has one more

	mov	cl,al;			save number of regions for later
	mov	ch,0;

	mov	ah,4;			one double word per lalist entry
	mul	ah;			ax is logical address list size
	mov	bx,ax;			also into bx for indexing (below)

	lea	di,lalist;		di is base of lalist (logical addresses)
	lea	bx,[bx+di];		bx base of palist (physical addresses)

	xor	ax,ax;			first entry for logical address list
	mov	dx,ax;			is to be disk address 0
	jmp short hdonllup;		jump to set up entry(0)

;
;	from region definitions in the label,
;	create the logical and physical address lists
;
;	si = address of working region list from the label
;	di = address of the logical address list to build
;	bx = address of the physical address list to build
;
hdonldo:;

;
;	get the physical address of next region from the label
;
	lodsw;
	xchg	dx,ax;
	lodsw;				make ax:dx the double word address
	xchg	ax,dx;			get it straight for later

;
;	store the physical address of the region into the physical address list
;
	xchg	di,bx;			now di=[palist]
	stosw;
	xchg	ax,dx;			store double into physical address list
	stosw;
	xchg	di,bx;			restore di=[lalist]

;
;	compute this region's logical address
;	(previous logical address plus that region's size)
;
	lodsw;				load physical block count from label
	xchg	dx,ax;
	lodsw;				ax:dx=count
	add	dx,[di-4];
	adc	ax,[di-2];		make ax:dx=next bracket in lalist

;
;	store the logical address of this region in lalist
;
hdonllup:;
	xchg	ax,dx;		store double word entry in logical address list
	stosw;
	xchg	ax,dx;		(second word)
	stosw;

	loop	hdonldo;	continue until lists are built


;
;	the lists are built, fill in the IPL information in the LRB
;

	lea	di,lrb.loadaddr;	the destination
	lea	si,bootr.iplla;		the source
	mov	cx,4;
;				move:	segment to load O/S at (1 word)
;					length of the O/S in paragraphs (1 word)
;					entry address for the O/S (2 words)
;
	rep movsw;		

	mov	ax,word ptr bootr.iplda;
	mov	dx,word ptr bootr.iplda+2;
	mov	lrb.da,ax;		copy the O/S's disk address
	mov	lrb.da+2,dx;

	mov	ax,bootr.lblssz;	save the sector size
	mov	lrb.ssz,ax;

	mov	ah,bootr.ctlop;		fetch control field for commands
	mov	hdctlcmd,ah;		and save

	xor	ax,ax;			flag no error occurred
	ret;

;
;	an error occurred
;
hdonlerri:;
	mov	lrb.status,ah;		set the return code
hdonlerr:;
	or	ax,ax;			flag an error occurred
	ret;

hd_online endp;



;
;	read the hard disk
;
;	inputs:		load request block set up
;
;	outputs:	all registers destroyed
;			load request block updated
;			z-flag is set for success
;			z-flag is nz if an error occurred
;
hd_read		proc;

	mov	ax,hdspace;		address the hard disk I/O registers
	mov	es,ax;

	mov	lrb.op,hdread;		set operation to read disk

	mov	bl,rgncnt;		get count of regions on disk
	xor	bh,bh;
	shl	bx,1;			times 4 bytes per double word
	shl	bx,1;

	lea	si,ds:lalist[bx+4];	si is the physical address list

	mov	ax,lrb.da+2;		most significant word of disk address
	cmp	ax,word ptr lalist[bx+2];	is requested address in range ?
	ja	out_of_range;		no, error in disk address
	jb	in_range;		yes, most significant word is in range

	mov	ax,lrb.da;		most significant word is equal
	cmp	ax,word ptr lalist[bx];	check same for least significant word
	jb	in_range;

out_of_range:;
	mov	lrb.status,hderrda;	error, bad disk address
hd_read_error:;
	mov	ah,1;
	or	ax,ax;			flag error in z-flag
	ret;

;
;	disk address is valid, find the region for the address
;
in_range:;
	mov	ax,lrb.da;
	mov	word ptr dada,ax;	save starting disk address
	mov	ax,lrb.da+2;
	mov	word ptr dada+2,ax;

	xor	bx,bx;			initialize index into address table
check_region:;
	mov	ax,lrb.da+2;		is address searching for in region ?
	cmp	ax,word ptr lalist[bx+4+2];	(test if less than next region)
	jb	found_region;		yes, bx is the region's index
	ja	next_region;		no, try next region

	mov	ax,lrb.da;		most significant words are equal
	cmp	ax,word ptr lalist[bx+4];	check least significant words
	jb	found_region;

next_region:;
	add	bx,4;			next double word of table
	jmp	check_region;

;
;	found the region, get block count and compute the physical address
;
found_region:;
	mov	dx,lrb.blkcnt;		set dx to block count to read

	mov	bp,word ptr lalist[bx+4];	compute blocks in this region
	sub	bp,lrb.da;		(next region's address - start address)
;					(will be < 64K so needn't do other word)

	mov	ax,lrb.da;		get logical disk address
	sub	ax,word ptr lalist[bx];	minus region's starting logical address
	sbb	lrb.da+2,0;		propagate borrow to high order
;					(have distance into region in ax)
	add	ax,ds:[si+bx];		add region's physical address
	adc	lrb.da+2,0;		propagate carry to high order
	mov	lrb.da,ax;		store physical disk address

;
;	compute the above for the low order words
;
	mov	ax,lrb.da+2;		get logical disk address
	sub	ax,word ptr lalist[bx+2];minus region's starting logical address
;					(have distance into region in ax)
	add	ax,ds:[si+bx+2];	add region's physical address
	mov	lrb.da+2,ax;		store physical disk address



page

;
;	ready to perform the physical disk I/O
;

read_next_region:;

	cmp	bp,dx;			blocks in region > total blocks ?
	jbe	not_last;		no, read not within this region
	mov	bp,dx;			yes, set to number of blocks requested

not_last:;
	sub	dx,bp;			decrement number of blocks to read

;
;	transfer one region's worth
;
do_region:;
	or	bp,bp;			done with this region ?
	jz	end_region;		yes, quit

	mov	ax,bp;			get block count (only a byte's worth)
	or	ah,ah;			is transfer over 255 sectors ?
	jz	use_al;			no, can transfer the whole thing

	mov	al,0FFh;		yes, only do 255 sectors this time

use_al:;
	mov	byte ptr lrb.blkcnt,al;	set block count for region's read
	mov	lrb.op,hdread;		set operation to read disk

	push	bp;
	push	dx;			save registers
	push	bx;
	call	pblock_io;		perform physical block I/O
	pop	bx;
	pop	dx;			restore registers
	pop	bp;

	jnz	break;			error in reading disk

	sub	bp,lrb.blkcnt;		one more bunch of blocks read

	mov	ax,lrb.blkcnt;
	add	word ptr dada,ax; 	update the lrb's disk address
	adc	word ptr dada+2,0; 	(add in carry, too)
	jmp	do_region;		read the rest of the region

;
;	have completed a hard disk region's transfer
;
end_region:;
	or	dx,dx;			finished ?
	jz	break;			yes

;
;	do the next region's transfers
;
	add	bx,4;			update region's number (DWORD per entry)

	mov	ax,ds:[si+bx];		get new region's physical address
	mov	lrb.da,ax;		and use as next starting disk address
	mov	ax,ds:[si+bx+2];
	mov	lrb.da+2,ax;

	mov	bp,word ptr lalist[bx+4];set new transfer count to
	sub	bp,word ptr lalist[bx];	the new region's size
;					(next region's logical address -
;					 this region's logical address)

	jmp	read_next_region;	read the next region's data

;
;	disk read error, or finished
;
break:;

	mov	ah,lrb.status;		get return status
	or	ah,ah;			set z-flag according to success

	ret;

hd_read		endp;




;
;	quiesce the hard disk
;
;	inputs:		load request block set up
;
;	outputs:	all registers destroyed
;			z-flag will be 'z' (always successful)
;
hd_quiesce	proc;

	xor	ax,ax;		flag success
	ret;

hd_quiesce	endp;



page


;
;	physical block I/O for the hard disk
;		execute read, write, or parameter load
;
;	inputs:		load request block set-up
;
;	outputs:	load request block's blockcount set to actual count
;			z-flag set for success
;			z-flag nz for error (error status is set in LRB)
;			all registers destroyed
;
pblock_io	proc;

	mov	si,lrb.op;		fetch operation

	cmp	si,word ptr cmdtab;	request over maximum supported command ?
	mov	ah,hderrcmd;		preset to invalid command error
	ja	hdiox;			too large a command, error

	cmp	byte ptr lrb.blkcnt+1,0;high order byte of # blocks
	jz	pblobc;			is zero, okay
	mov	ah,hderrbc;		error, block count is too large

;
;	handle error, ah = error return status
;
hdiox:;
	mov	lrb.status,ah;		return status
	or	ax,ax;			indicate failure in z-flag
	ret;


pblobc:;
	mov	al,cmdtab+1[si];	look up hard disk command from table
	mov	byte ptr lrb.op,al;	and store into LRB operation

	or	hdctlimg,dmadir;	force DMA read
	mov	al,dmatab[si];		look up DMA command from table
	test	al,dmaenab;		does command use dma ?
	jz	pblnodma;		no, skip

;
;	command requires DMA, set it up
;
	call	hddmdis;		disable DMA
	and	al,dmadir;		get the present direction bit
	and	hdctlimg,not dmadir;	set up dma direction
	or	hdctlimg,al;

;
;	convert offset:segment into a 20-bit address
;
	mov	dx,word ptr lrb.dma;	fetch DMA offset
	mov	ax,word ptr lrb.DMA+2;	and segment
	push	ax;			save segment

	mov	cl,4;
	shl	ax,cl;			segment * 16 = it's address
	add	dx,ax;			add segment's address to offset

	pop	ax;			fetch segment again

	mov	al,0;
	adc	al,0;			carry into most significant value

	shr	ah,cl;			compute top 4 bits from segment
	add	al,ah;			al = most significant 4 bits

	call	loadma;			set the DMA registers
	call	hddmaen;		and enable dma

;
;	DMA is prepared, if necessary
;
pblnodma:;

;
;	Do the command and wait for completion.
;	Do sense if required (err or (80h and modf)=1).  
;	Always sends six byte sequence from the LRB.
;

	call	hdgetlun;		al = logical unit, ch = select pattern

	mov	ah,byte ptr lrb.da+2;	get physical disk address
	and	ah,habsmsk;		look at unit from that
	or	al,ah;			al is logical unit in bits 7, 6, & 5

	mov	dx,word ptr lrb.da;	dx is physical disk address
	mov	cl,byte ptr lrb.blkcnt;	cl is the block count
	mov	ah,byte ptr lrb.op;	ah is the operation code

	call	hdhs;			send the above command
	mov	ah,hderrto;		preset to controller timeout error
	jz	new_dma;		command succeeded
	jmp	hdiox;			command failed

;
;	update DMA address to reflect new address
;
new_dma:;
	mov	ax,lrb.blkcnt;		number of blocks transferred

	add	lrb.da,ax;		update sector address
	adc	lrb.da+2,0;

	mov	cl,5;			convert 512-byte block to paragraphs
	shl	ax,cl;			(shl 9 = *512, shr 4 = /16)
	add	lrb.dma+2,ax;		and add to segment of DMA

	call	hdcmplt;		wait for completion
	jz	return_good_io;		worked
	jmp	hdiox;			command failed

return_good_io:;
	xor	ax,ax;			flag good status in z-flag
	mov	lrb.status,ah;		and in status byte

	ret;

pblock_io	endp;



;
;	get logical unit number and select pattern
;
;	inputs:		none
;
;	outputs:	al = logical unit number
;			ch = select pattern for that drive
;
hdgetlun	proc;

	mov	cx,lrb.dun;	device/unit number 

	mov	al,cl;		unit number (which drive on the controller)
	mov	cl,5;		set unit to logical unit number position
	shl	al,cl;		(top 3 bits are the drive's number)

	mov	cl,ch;		device number (which controller)
	and	cl,7;		mask range
	mov	ch,1;		set bit for controller select
	shl	ch,cl;		rotate bit to position

	ret;

hdgetlun endp;




page

;
;	send a command sequence to the controller
;
;	inputs:		ah,al,dh,dl,cl = bytes to send
;			ch = select pattern
;
;	outputs:	z-flag set => not busy
;			z-flag nz => busy too long
;			ax, cx destroyed
;
hdhs		proc;

	call	hdsel;		select the hard disk drive
	jnz	hdhsto;		error, timeout

	call	hdack;		issue command byte
	jnz	hdhsto;		error, timeout

	mov	ah,al;
	call	hdack;		logical unit number/logical address 2
	jnz	hdhsto;

	mov	ah,dh;
	call	hdack;		logical address 1
	jnz	hdhsto;

	mov	ah,dl;
	call	hdack;		logical address 0
	jnz	hdhsto;

	mov	ah,cl;
	call	hdack;		sector count/interleave
	jnz	hdhsto;

	mov	ah,hdctlcmd;	control field
	call	hdack;

hdhsto:;
	ret;			results in z-flag

hdhs	endp;



page

;
;	wait for completion of hard disk command
;	and issue a sense command to check for errors
;
;	inputs:		none
;
;	outputs:	ah = sense error code
;			z-flag set => success
;			z-flag nz => error
;
hdcmplt		proc;

hdcmpltw:;
	mov	al,es:hdbus;		get bus status
	and	al,control or input or req or msg;
	cmp	al,word ptr (control or input or req);
	jnz	hdcmpltw;		wait until in control, input, & request

	mov	al,es:hdcsd;		get status
	nop;
	nop;
	nop;
	nop;				wait until operation completed

hdcmplu:;
	mov	ah,es:hdbus;		get bus status
	and	ah,control or input or req or msg;
	cmp	ah,control or input or req or msg;
	jnz	hdcmplu;		wait until in message mode

	mov	ah,es:hdcsd;		message (but doesn't work, H/W bug)



;
;	have completed the operation, get sense to check for errors
;
	call	hdgetlun;		al = logical unit, cl = select pattern

	or	hdctlimg,dmadir;	force DMA read
	mov	al,dmaenab+dmadir;

;
;	command requires DMA, set it up
;
	call	hddmdis;		disable DMA
	and	al,dmadir;		get the present direction bit
	and	hdctlimg,not dmadir;	set up dma direction
	or	hdctlimg,al;

	xor	ax,ax;			sense buffer is in low memory
	lea	dx,ds:sense;		at the variable "sense"
	call	loadma;			set the DMA registers
	call	hddmaen;		and enable dma

;
;	Do the command and wait for completion.
;

	call	hdgetlun;		al = logical unit, ch = select pattern

	mov	ah,senscmd;		set operation to a sense command
	xor	al,al;			drive 0

	call	hdhs;			send the sense command
	mov	ah,hderrto;		preset to controller timeout error
	jnz	hdsensefail;		command failed

hdcmpltw2:;
	mov	al,es:hdbus;		get bus status
	and	al,control or input or req or msg;
	cmp	al,word ptr (control or input or req);
	jnz	hdcmpltw2;		wait until in control, input, & request

	mov	al,es:hdcsd;		get status
	nop;
	nop;
	nop;
	nop;				wait until operation completed

hdcmplu2:;
	mov	ah,es:hdbus;		get bus status
	and	ah,control or input or req or msg;
	cmp	ah,control or input or req or msg;
	jnz	hdcmplu2;		wait until in message mode

	mov	ah,es:hdcsd;		message (but doesn't work, H/W bug)

	mov	ah,sense;		get the sense status byte
	and	ah,7fh;			ignore "address valid" bit

hdsensefail:;
	ret;

hdcmplt		endp;




page
;
;	issue a select for the hard disk controller
;
;	inputs:		ch = select pattern
;
;	outputs:	z-flag set => success
;			z-flag nz => busy for too long
;			ax, cx destroyed
;
hdsel		proc;

	push	ax;
	push	cx;			save caller's registers

hdnbsy:;
	test	es:hdbus,input or control or busy or req or msg;	busy ?
	jnz	hdnbsy;			yes, wait

	mov	es:hdcsd,ch;		set up select pattern

	mov	al,hdctlimg;		get control pattern so far
	or	al,selct;		set select
	mov	es:hdctl,al;		and output it

	mov	cx,bsyto;		retry counter for controller to go busy
hdbsyn:;
	test	es:hdbus,busy;		controller busy ?
	loopz	hdbsyn;			no, retry

	mov	al,hdctlimg;
	mov	es:hdctl,al;		issue control image to controller
	jz	hdselto;		dont continue, didn't go busy

	mov	cx,ctlto;		retry counter for control mode
hdcmdyr:;
	mov	al,es:hdbus;
	and	al,control+msg+input;	command mode bits
	cmp	al,word ptr control;		in control mode ?
	loopne	hdcmdyr;		no, wait some more
	jnz	hdselto;		error, timed out

	xor	ax,ax;			flag disk selected

	pop	cx;
	pop	ax;			restore caller's registers

	ret;

hdselto:;
	mov	ah,1;			flag an error in selecting
	or	ax,ax;

	pop	cx;
	pop	ax;			restore caller's registers

	ret;

hdsel	endp;




page
;
;	put out data to controller and do acknowledge sequence
;
;	inputs:		ah = data to output
;
;	outputs:	ah destroyed
;			z-flag set => operation suceeded
;			z-flag nz => timed out
;
hdack		proc;

	call	hdrequp;		wait for "request" signal high
	jz	hdackx;			timed out, abort

	mov	es:hdcsd,ah;		output byte, hardware will do ack
	nop;
	nop;
	nop;
	nop;
	nop;				make sure req/ack sequence complete

	xor	ah,ah;			flag success
	ret;

hdackx:;
	mov	ah,1;
	or	ax,ax;			flag failure
	ret;

hdack	endp;



page

;
;	wait for "request" status from controller
;
;	inputs:		none
;
;	outputs:	cx destroyed
;			z-flag set => "request" is set
;			z-flag nz => timed out
;
hdrequp		proc;

	push	cx;			save caller's registers

	mov	cx,requto;		retry counter for "request"
hdrequpa:;
	test	es:hdbus,req;		wait until "request"
	loopz	hdrequpa;		or timed out

	pop	cx;			restore caller's registers

	ret;				return result in z-flag

hdrequp	endp;



;
;	enable the DMA channel
;
;	inputs:		none
;
;	outputs:	ax destroyed
;
hddmaen		proc;

	mov	al,hdctlimg;		get control state so far
	or	al,dmaen;		set DMA enable
	and	al,not dmastb;		strobe it
	mov	es:hdctl,al;		set control reg

	or	al,dmastb;		strobe it
	mov	es:hdctl,al;
	mov	hdctlimg,al;		save the control image's state now

	ret;

hddmaen		endp;



;
;	disable the DMA channel from operating
;
;	inputs:		none
;
;	outputs:	ah destroyed
;
hddmdis		proc;

	mov	ah,hdctlimg;		get control image so far
	and	ah,not (dmastb or dmaen);	strobe it
	mov	es:hdctl,ah;

	or	ah,dmastb;		strobe again
	mov	es:hdctl,ah;		issue the I/O
	mov	hdctlimg,ah;		and save the control's state

	ret;

hddmdis		endp;





;
;	load the DMA registers
;
;	inputs:		al:dx = starting DMA address
;
;	outputs:	all registers intact
;
loadma		proc;

	mov	es:hddmah,al;	high byte of DMA address
	mov	es:hddmam,dh;	middle byte of DMA address
	mov	es:hddmal,dl;	low byte of DMA address

	ret;

loadma		endp;



;
;	initialize the hard disk controller
;
;	inputs:		none
;
;	outputs:	ax destroyed
;
hd_init		proc;

	mov	al,dmastb+reset;	reset disk controller
	mov	es:hdctl,al;		and output that

	xor	al,reset;		flip the reset bit
	mov	es:hdctl,al;		issue the I/O
	mov	hdctlimg,al;		and save the control image

	call	hddmdis;		disable DMA

	ret;

hd_init		endp;



code	ends;

end;

