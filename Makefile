PACKAGE = FFcast
PRGNAME = ffcast
VERSION = 2.0.3

OUT = xrectsel
SRC = $(wildcard *.c)
OBJ = $(SRC:.c=.o)

BINPROGS = ffcast $(OUT)
LIBSTUFF = subcmd
MANPAGES = ffcast.1

PREFIX ?= /usr/local
EXEC_PREFIX ?= $(PREFIX)
BINDIR = $(EXEC_PREFIX)/bin
LIBDIR = $(EXEC_PREFIX)/lib
DATAROOTDIR = $(PREFIX)/share
MANDIR = $(DATAROOTDIR)/man
MAN1DIR = $(MANDIR)/man1

CFLAGS += --std=c99 -g -pedantic -Wall -Wextra -Wno-variadic-macros
LDFLAGS += -lX11

uppercase = $(shell echo $(1) | tr a-z A-Z)

all: $(BINPROGS) $(LIBSTUFF) $(MANPAGES) zsh_completion

$(OUT): $(OBJ)
	$(CC) -o $@ $(OBJ) $(LDFLAGS)

%: %.bash
	sed -e 's/@VERSION@/$(VERSION)/g' \
		-e 's/@PRGNAME@/$(PRGNAME)/g' \
		-e 's|@LIBDIR@|$(LIBDIR)|g' $< > $@ && chmod go-w,+x $@

%.1: %.1.pod
	sed -e 's|@LIBDIR@|$(LIBDIR)|g' $< | pod2man \
		--center='$(PACKAGE) Manual' \
		--name='$(call uppercase,$*)' \
		--release='$(PACKAGE) $(VERSION)' \
		--section=1 > $@

clean:
	$(RM) $(OBJ) $(BINPROGS) $(LIBSTUFF) $(MANPAGES)

install: all
	install -dm755 \
		'$(DESTDIR)$(BINDIR)' \
		'$(DESTDIR)$(LIBDIR)/$(PRGNAME)' \
		'$(DESTDIR)$(MAN1DIR)'
	install -m755 $(BINPROGS) '$(DESTDIR)$(BINDIR)'
	install -m644 $(LIBSTUFF) '$(DESTDIR)$(LIBDIR)/$(PRGNAME)'
	install -m644 $(MANPAGES) '$(DESTDIR)$(MAN1DIR)'
	install -Dm644 zsh_completion \
		'$(DESTDIR)$(DATAROOTDIR)'/zsh/site-functions/_ffcast

uninstall:
	@echo removing executable files from $(DESTDIR)$(BINDIR)
	$(foreach f,$(BINPROGS),$(RM) '$(DESTDIR)$(BINDIR)'/$(f))
	@echo removing library files from $(DESTDIR)$(LIBDIR)/$(PRGNAME)
	$(foreach f,$(LIBSTUFF),$(RM) '$(DESTDIR)$(LIBDIR)/$(PRGNAME)'/$(f))
	@echo removing man pages from $(DESTDIR)$(MAN1DIR)
	$(foreach f,$(MANPAGES),$(RM) '$(DESTDIR)$(MAN1DIR)'/$(f))
	@echo removing zsh files from $(DESTDIR)$(DATAROOTDIR)/zsh/site-functions
	$(RM) '$(DESTDIR)$(DATAROOTDIR)'/zsh/site-functions/_ffcast

dist:
	install -dm755 release
	git archive --prefix=$(PACKAGE)-$(VERSION)/ -o release/$(PACKAGE)-$(VERSION).tar.gz $(VERSION)

version:
	@echo $(VERSION)

.PHONY: all clean install uninstall dist version
