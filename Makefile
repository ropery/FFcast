OUT        = xrectsel
VERSION    = $(shell git describe)

SRC        = ${wildcard *.c}
OBJ        = ${SRC:.c=.o}
DISTFILES  = Makefile README.asciidoc ffcast.1.pod ffcast.bash xrectsel.c

PREFIX    ?= /usr
MANPREFIX ?= ${PREFIX}/share/man

CPPFLAGS  := -DVERSION=\"${VERSION}\" ${CPPFLAGS}
CFLAGS    := --std=c99 -g -pedantic -Wall -Wextra -Wno-variadic-macros ${CFLAGS}
LDFLAGS   := -lX11 ${LDFLAGS}

all: ${OUT} doc

${OUT}: ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS}

doc: ffcast.1

ffcast.1: ffcast.1.pod
	pod2man --center="FFcast Manual" --name="FFCAST" --release="ffcast ${VERSION}" --section=1 $< > $@

strip: ${OUT}
	strip --strip-all ${OUT}

install: ffcast.1 ffcast.bash xrectsel
	install -D -m755 xrectsel ${DESTDIR}${PREFIX}/bin/xrectsel
	install -D -m755 ffcast.bash ${DESTDIR}${PREFIX}/bin/ffcast
	install -D -m755 ffcast.1 ${DESTDIR}${MANPREFIX}/man1/ffcast.1

uninstall:
	@echo removing executable file from ${DESTDIR}${PREFIX}/bin
	rm -f ${DESTDIR}${PREFIX}/bin/xrectsel
	rm -f ${DESTDIR}${PREFIX}/bin/ffcast
	@echo removing man page from ${DESTDIR}${MANPREFIX}/man1/ffcast.1
	rm -f ${DESTDIR}${MANPREFIX}/man1/ffcast.1

dist: clean
	mkdir ffcast-${VERSION}
	cp ${DISTFILES} ffcast-${VERSION}
	sed "s/\(^VERSION *\)= .*/\1= ${VERSION}/" < Makefile > ffcast-${VERSION}/Makefile
	sed "s/@VERSION[@]/${VERSION}/g" < ffcast.bash > ffcast-${VERSION}/ffcast.bash
	tar czf ffcast-${VERSION}.tar.gz ffcast-${VERSION}
	rm -rf ffcast-${VERSION}

clean:
	${RM} ${OUT} ${OBJ} ffcast.1

.PHONY: clean dist doc install uninstall
