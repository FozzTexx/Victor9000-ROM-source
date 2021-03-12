AS=jwasm
ASFLAGS=-0 -c -Sg -Fl -Zm -Zne -omf
EXT=o

all: borked universal.hex universal.rom

universal.hex: universal.rom
	hexdump -v -C $< > $@

universal.exe: bt1base.$(EXT)  bt1cuopn.$(EXT) bt1ntdvc.$(EXT) bt1chint.$(EXT) \
	       bt1iconc.$(EXT) bt1vars.$(EXT)  bt1fddvc.$(EXT) bt1hddvc.$(EXT) \
	       bt1init.$(EXT)
	alink -o $(basename $@).exe $^

universal.rom: universal.exe
	dd if=$(basename $@).exe bs=1 skip=64 count=7424 > $@
	tail -c 768 $(basename $@).exe >> $@
	./add-checksum.py $@

%.$(EXT): %.asm
	$(AS) $(ASFLAGS) $<

borked: universal.hex
	diff $< ../sirius1_universal_f3f6.hex > $@

bt1base.$(EXT): bt1ul.str bt1bvt.str bt1lrb.str

bt1cuopn.$(EXT): bt1lrb.str

bt1fddvc.$(EXT): bt1lrb.str bt1fdlbl.str

bt1hddvc.$(EXT): bt1bvt.str bt1hdlbl.str bt1bvt.str

bt1ntdvc.$(EXT): bt1lrb.str bt1ntctl.str bt1ntlbl.str

bt1vars.$(EXT): bt1ntctl.str bt1bvt.str bt1lrb.str
