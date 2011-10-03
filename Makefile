OUT        = xrectsel
VERSION    = $(shell git describe)

SRC        = ${wildcard *.c}
OBJ        = ${SRC:.c=.o}
DISTFILES  = Makefile README ffcast.bash xrectsel.c

PREFIX    ?= /usr
MANPREFIX ?= ${PREFIX}/share/man

CPPFLAGS  := -DVERSION=\"${VERSION}\" ${CPPFLAGS}
CFLAGS    := --std=c99 -g -pedantic -Wall -Wextra -Werror ${CFLAGS}
LDFLAGS   := -lX11 ${LDFLAGS}

all: ${OUT}

${OUT}: ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS}

strip: ${OUT}
	strip --strip-all ${OUT}

install: xrectsel ffcast.bash
	install -D -m755 xrectsel ${DESTDIR}${PREFIX}/bin/xrectsel
	install -D -m755 ffcast.bash ${DESTDIR}${PREFIX}/bin/ffcast

uninstall:
	@echo removing executable file from ${DESTDIR}${PREFIX}/bin
	rm -f ${DESTDIR}${PREFIX}/bin/xrectsel
	rm -f ${DESTDIR}${PREFIX}/bin/ffcast

dist: clean
	mkdir ffcast-${VERSION}
	cp ${DISTFILES} ffcast-${VERSION}
	sed "s/\(^VERSION *\)= .*/\1= ${VERSION}/" < Makefile > ffcast-${VERSION}/Makefile
	sed "s/@VERSION[@]/${VERSION}/g" < ffcast.bash > ffcast-${VERSION}/ffcast.bash
	tar czf ffcast-${VERSION}.tar.gz ffcast-${VERSION}
	rm -rf ffcast-${VERSION}

clean:
	${RM} ${OUT} ${OBJ}

.PHONY: clean dist install uninstall
