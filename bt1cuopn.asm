include bt1ttl.inc
subttl control unit dispatcher for boot

;
;
;	handles control unit operations...
;	dispatcher for operations to devices
;
;

name	cuopn
cgroup	group code
dgroup	group data
assume	cs:cgroup,ds:dgroup;



;
bootopn	equ	40h;		class of boot-type operations




data	segment 'data' public;

include	bt1lrb.str
	extrn	lrb:lrbs;	load request block structure

data	ends;




code	segment	'code' public;


;
;	constant values in the code segment (ROM)
;

;
;	default control unit table (operation handlers)
;

extrn err_intern:near;
extrn fd_cup:near,fd_dvcrdy:near,fd_online:near,fd_read:near,fd_quiesce:near;
extrn fd_status:near;
extrn hd_cup:near,hd_dvcrdy:near,hd_online:near,hd_read:near,hd_quiesce:near;
extrn nt_cup:near,nt_dvcrdy:near,nt_online:near,nt_read:near,nt_quiesce:near;

cu_table	equ	$;
	dw	0502h;		maximum operation index and device index
	dw	err_intern;	internal error handler
;
;	floppy disk functions
;
	dw	fd_cup;		floppy disk control unit present
	dw	fd_dvcrdy;	floppy disk device ready
	dw	fd_online;	floppy disk device on-line
	dw	fd_read;	floppy disk read
	dw	fd_quiesce;	floppy disk quiesce
	dw	fd_status;	floppy disk status
;
;	hard disk functions
;
	dw	hd_cup;		hard disk control unit present
	dw	hd_dvcrdy;	hard disk device ready
	dw	hd_online;	hard disk device on-line
	dw	hd_read;	hard disk read
	dw	hd_quiesce;	hard disk quiesce
	dw	truely;		not supported
;
;	network functions
;
	dw	nt_cup;		network control unit present
	dw	nt_dvcrdy;	network device ready
	dw	nt_online;	network device on-line
	dw	nt_read;	network read
	dw	nt_quiesce;	network quiesce
	dw	truely;		not supported




;
;
;	CU_OPRN
;		main entry point to perform control unit operations
;
;	input:	load request block is the implied parameter
;	output:	z-flag is set if and only if operation is successful
;	function: Use device/unit field in lrb to go to handler by operation.
;
public cu_oprn
cu_oprn	proc;

	mov	lrb.status,0;			preset to good status

	mov	al,byte ptr lrb.dun+1;		control unit

	mov	cl,4;
	shr	al,cl;		high bits are control unit dispatch index

	mov	dx,lrb.op;	get the operation number
	xor	bx,bx;		in case error (select error branch)
	cmp	dh,bootopn;
	jne	cuopnfg;	error, invalid type of operation

	mov	ah,byte ptr cu_table+1;	maximum operation index
	cmp	dl,ah;		requested an operation over maximum ?
	jbe	cuopin;		no, skip
	mov	dl,ah;		yes, set to limit (which is quiesce)
cuopin:;

	cmp	al,byte ptr cu_table;	control unit within limits ?
	ja	cuopout;		no, exit with an error

	inc	ah;		change maximum operation into a count
	shl	ah,1;		times 2 bytes per offset

	mul	ah;		times control unit number => array index
	mov	bl,dl;		bx was 0

	inc	bx;		plus one to get around error exit
	shl	bx,1;		times 2 bytes per offset

	add	bx,ax;		have a pointer to the address

cuopnfg:;
cuopout:;
	jmp	word ptr cs:cu_table+2[bx];	transfer to handler
;


cu_oprn	endp;





;
;
;	this is a null routine which is used for operations
;	which are not required by devices (returns TRUE)
;
truely	proc;

	xor	ax,ax;			return z-flag of z
	ret;

truely	endp;



code	ends;

end;

