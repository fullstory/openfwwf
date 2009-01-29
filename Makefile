BCMASM = b43-asm
PREFIX ?= /lib/firmware/b43-open
DEBUG ?= 1

all: ucode5.fw

ucode5.fw: ucode5.asm
	$(BCMASM) ucode5.asm ucode5.fw --cpp-args -DDEBUG=$(DEBUG) -- --ivalext .fw --psize

install: all
	-install -d -o 0 -g 0 -m 755 $(PREFIX)
	-install -o 0 -g 0 -m 644 ucode5.fw $(PREFIX)/open_ucode5.fw

clean:
	-rm -f *.fw *.orig *.rej *~

.PHONY: all install clean
