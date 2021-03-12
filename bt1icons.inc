;
;	literal values regarding icon display
; 

left_arrow equ 12h;	 left part of arrow icon 
right_arrow equ 13h;	 right part of arrow icon 
left_disc equ 10h;	 left part of floppy icon 
right_disc equ 11h;	 right part of floppy icon 
fd_icon equ 1011h;	 whole floppy icon 
left_m equ 14h;		 left part of letter M icon 
right_m equ 15h;	 right part of letter M icon 
left_clock equ 16h;	 left part of clock icon 
right_clock equ 17h;	 right part of clock icon 
left_x equ 18h;		 left part of letter X icon 
right_x equ 19h;	 right part of letter X icon 
left_hd equ 1ah;	 left part of hard disk icon 
right_hd equ 1bh;	 right part of hard disk icon 
hd_icon equ 1a1bh;	 whole hard disk icon 
left_net equ 1ch;	 left part of network icon 
right_net equ 1dh;	 right part of network icon 
net_icon equ 1c1dh;	 whole network icon 
k equ 1eh;		 letter K icon 
blank equ 1fh;		 icon for a blank area 

;
;		layout for position of the icons
;
;
;          1         2         3         4         5         6         7
;01234567890123456789012345678901234567890123456789012345678901234567890123456
;                   MMbXXbnnnK BB     ^^b[]bn      []bXXbee
;                                     cc  
;
;
;KEY:   MM = letter M icon		^^ = arrow icon
;       b  = blank			[] = floppy icon
;       XX = letter X icon		ee = error code (2 digits)
;     nnnn = 4 hex digits		n  = unit's number
;       cc = clock icon			K  = letter K icon
;	BB = bit of memory in error


memory_y equ  19;	 position of letter M icon 
badmem_y equ  22;	 position of bad memory letter X 
mem_bits equ  30;	 position of which bits are bad error
msiz_y equ  25;		 position of memory size 
arrow_y equ  37;	 position of the arrow icon 
clock_y equ  37;	 position of clock icon 
disc_y equ  50;		 position of floppy icon 
baddsk_y equ  53;	 position of bad disk letter X 
