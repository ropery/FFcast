PACKAGE = ffcast
VERSION = 1.1

OUT = xrectsel
SRC = $(wildcard *.c)
OBJ = $(SRC:.c=.o)

PREFIX ?= /usr/local
MANPREFIX ?= $(PREFIX)/share/man

CFLAGS := --std=c99 -g -pedantic -Wall -Wextra -Wno-variadic-macros $(CFLAGS)
CPPFLAGS := -DVERSION=\"$(VERSION)\" $(CPPFLAGS)
LDFLAGS := -lX11 $(LDFLAGS)

all: $(OUT) doc ffcast

$(OUT): $(OBJ)
	$(CC) -o $@ $(OBJ) $(LDFLAGS)

%: %.bash
	sed 's/@VERSION@/$(VERSION)/g' <$@.bash >$@ && chmod go-w,+x $@

doc: ffcast.1

ffcast.1: ffcast.1.pod
	pod2man --center="FFcast Manual" --name="FFCAST" --release="$(PACKAGE) $(VERSION)" --section=1 $< > $@

strip: $(OUT)
	strip --strip-all $(OUT)

install: ffcast ffcast.1 xrectsel
	install -D -m755 xrectsel $(DESTDIR)$(PREFIX)/bin/xrectsel
	install -D -m755 ffcast $(DESTDIR)$(PREFIX)/bin/ffcast
	install -D -m755 ffcast.1 $(DESTDIR)$(MANPREFIX)/man1/ffcast.1

uninstall:
	@echo removing executable file from $(DESTDIR)$(PREFIX)/bin
	rm -f $(DESTDIR)$(PREFIX)/bin/xrectsel
	rm -f $(DESTDIR)$(PREFIX)/bin/ffcast
	@echo removing man page from $(DESTDIR)$(MANPREFIX)/man1/ffcast.1
	rm -f $(DESTDIR)$(MANPREFIX)/man1/ffcast.1

dist:
	install -d release
	git archive --prefix=$(PACKAGE)-$(VERSION)/ -o release/$(PACKAGE)-$(VERSION).tar.gz $(VERSION)

clean:
	$(RM) $(OUT) $(OBJ) ffcast ffcast.1

.PHONY: clean dist doc install uninstall
