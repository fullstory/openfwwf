BCMASM = b43-asm
PREFIX ?= /lib/firmware/b43
DEBUG ?= 1

all: ucode5.fw

ucode5.fw: ucode5.asm
	$(BCMASM) ucode5.asm ucode5.fw --cpp-args -DDEBUG=$(DEBUG) -- --ivalext .fw --psize

install: all
	-install -d -o 0 -g 0 -m 755 $(PREFIX)
	-install -o 0 -g 0 -m 644 ucode5.fw $(PREFIX)/ucode5.fw
	-install -o 0 -g 0 -m 644 b0g0initvals5.fw $(PREFIX)/b0g0initvals5.fw
	-install -o 0 -g 0 -m 644 b0g0bsinitvals5.fw $(PREFIX)/b0g0bsinitvals5.fw

clean:
	-rm -f *.fw *.orig *.rej *~

.PHONY: all install clean
