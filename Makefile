PACKAGE = FFcast
VERSION = 1.1.1

OUT = xrectsel
SRC = $(wildcard *.c)
OBJ = $(SRC:.c=.o)

BINPROGS = ffcast $(OUT)
MANPAGES = ffcast.1

PREFIX ?= /usr/local
EXEC_PREFIX ?= $(PREFIX)
BINDIR = $(EXEC_PREFIX)/bin
DATAROOTDIR = $(PREFIX)/share
MANDIR = $(DATAROOTDIR)/man
MAN1DIR = $(MANDIR)/man1

CFLAGS += --std=c99 -g -pedantic -Wall -Wextra -Wno-variadic-macros
LDFLAGS += -lX11

uppercase = $(shell echo $(1) | tr a-z A-Z)

all: $(BINPROGS) $(MANPAGES)

$(OUT): $(OBJ)
	$(CC) -o $@ $(OBJ) $(LDFLAGS)

%: %.bash
	sed 's/@VERSION@/$(VERSION)/g' $< > $@ && chmod go-w,+x $@

%.1: %.1.pod
	pod2man \
		--center="$(PACKAGE) Manual" \
		--name="$(call uppercase,$*)" \
		--release="$(PACKAGE) $(VERSION)" \
		--section=1 $< > $@

clean:
	$(RM) $(OBJ) $(BINPROGS) $(MANPAGES)

install: all
	install -dm755 $(DESTDIR)$(BINDIR) $(DESTDIR)$(MAN1DIR)
	install -m755 $(BINPROGS) $(DESTDIR)$(BINDIR)
	install -m644 $(MANPAGES) $(DESTDIR)$(MAN1DIR)

uninstall:
	@echo removing executable files from $(DESTDIR)$(BINDIR)
	$(RM) $(DESTDIR)$(BINDIR)/$(BINPROGS)
	@echo removing man pages from $(DESTDIR)$(MAN1DIR)
	$(RM) $(DESTDIR)$(MAN1DIR)/$(MANPAGES)

dist:
	install -dm755 release
	git archive --prefix=$(PACKAGE)-$(VERSION)/ -o release/$(PACKAGE)-$(VERSION).tar.gz $(VERSION)

.PHONY: all clean install uninstall dist
