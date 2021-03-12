include bt1ttl.inc


;
;
;	data area for boot program
;
;
name	vars
dgroup	group data;


data segment public 'data'

public bootflg,sw_entry,bstck,bvt,b_count,blink_toggle,char,char_mode,dot_ram;
public bootr,lrb,cu_table;
public send_buffer,receive_buffer,ccb,netctl;
public sec,trk,curspd,seccnt,sav_seccnt,sector_retry,fldma,curtrk,state;
public hdctlcmd,hdctlimg,hdctlop,sense,rgncnt,lalist,dada;


;
; this segment is at 0000h
;
	org	0h;
bootflg	dw	?;	flag to boot program,
;				left byte non-zero => bypass memory tests
;				right byte non-zero => bypass entering program

sw_entry	dd	?;	if bypass entering program, address to enter

;
;	area from 0:2 to 0:FF is reserved for software saving information
;	(area from 7F down is used to save old program's registers)
;	(COMMAND saves time/date in this area)
;


	org	120h;		don't mess up interrupt vectors (100 to 11F)
;
;	network buffers overlay hard disk region lists
;
include		bt1ntctl.str
send_buffer	boot_send	<>;	transmission buffer
receive_buffer	boot_receive	<>;	receive buffer (minus data)


	org	120h;
;
;	hard disk variables
;
lalist		dd	(56+1)*2 dup (0);table to find region's physical address
dada		dd	?;		save area for a disk address
sense		db	4 dup (0);	sense information for error status
hdctlcmd	db	?;		control field to send with commands
hdctlimg	db	?;		control register image for hard disk
hdctlop		db	?;		hard disk controller outputting to
rgncnt		db	?;		count of hard disk regions



;
;	the boot vector table has data passed to loaded software
;
	org	300h;
include	bt1bvt.str

bvt	bvts	<>;


;
;	load request block used by all drivers
;
include	bt1lrb.str;
lrb	lrbs	<>;			load request block



;
;	starting after BVT and LRB are internal variables and tables
;
char_mode	dw	?;	character mode--attribute setting & offset
char		dw	?;	character position on 25th line (cursor)
b_count		dw	?;	count down for blinking time
cu_table	dw	1+5*10 dup (0);	list of boot units, room for 10 devices
blink_toggle	db	?;	toggle for blinking prompt on/off


;
;	network variables
;
netctl		netctls	<>;		network control variables
ccb		ccbs	<>;		omninet command control block



;
;	floppy disk variables
;
fldma		dd	?;	current dma address
curspd		dw	?;	current speed of motor
curtrk		db	2 dup (0);	current track for drives A/B
state		db	2 dup (0);	state of disk in drive (for Vicki)
sec		db	?;	sector work variable
trk		db	?;	track work variable
seccnt		db	?;	count down of number of sectors to read
sav_seccnt	db	?;	permanent copy of number sectors read
sector_retry	db	?;	retry counter for reading bad sectors



;
;	stack is from 0:3C0 to 0:3FB
;
	org	3FCh;		don't write over interrupt 255 vector
bstck	equ	$;




;
;	character set/font definition table
;
 	org	400h;
dot_ram	dw	(0);



;
;	buffer for the boot program
;	(must be last of variables area, since
;	may be overlayed by the system load)
;
	org	0C00h;
bootr	db	(0);	label/working buffer


data ends;

end;

