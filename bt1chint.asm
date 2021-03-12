include bt1ttl.inc
name  charasm

;
;
;	module to initialize the character set
;	(which consists of specially-made icons)
;
;


data	segment	public 'data';
	extrn	dot_ram:word;
data	ends;


cgroup group code;
dgroup group data;
assume cs:cgroup,ds:dgroup;



;
;
;	main entry point to initialize the character set
;
;
code	segment	public 'code';
	extrn	charset:word;

char_init	proc;
public		char_init;

	push	ds;			destination segment
	pop	es;
	lea	di,dgroup:dot_ram;	destination offset is font table

	push	ds;			save caller's ds

	lea	si,cgroup:charset;	get address of icon definitions
	push	cs;
	pop	ds;			source segment is the code area

	mov	cx,cs:[si];		length is stored at front of set
	add	si,2;			source offset is stored next

	cld;				set to auto-increment the move
	rep	movsw;			copy character set to font table

	pop	ds;			restore caller's DS !
	ret;

char_init	endp;


code	ends;

	end

