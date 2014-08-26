AM_CFLAGS = -std=c99 -pedantic -Wall -Wextra -Wno-variadic-macros

bin_PROGRAMS = xrectsel
bin_SCRIPTS = ffcast
pkglibexec_SCRIPTS = subcmd
man_MANS = ffcast.1

EXTRA_DIST = \
	ffcast.bash \
	subcmd.bash \
	ffcast.1.pod \
	zsh_completion \
	README.asciidoc

MOSTLYCLEANFILES = \
	$(bin_SCRIPTS) \
	$(pkglibexec_SCRIPTS) \
	$(man_MANS) $(man_MANS:.1=.pod)

do_sub = $(SED) \
	-e 's|@PACKAGE[@]|$(PACKAGE)|g' \
	-e 's|@VERSION[@]|$(VERSION)|g' \
	-e 's|@pkglibexecdir[@]|$(pkglibexecdir)|g' \
	-e 's|@sysconfdir[@]|$(sysconfdir)|g'

%: %.bash Makefile
	$(do_sub) < $< > $@
	chmod go-w,+x $@

# purpose for saving as foo.pod: make pod2man auto-set --name=FOO
%.1: %.1.pod Makefile
	$(do_sub) < $< > $*.pod
	$(POD2MAN) \
		--center='$(PACKAGE_NAME) Manual' \
		--release='$(PACKAGE_NAME) $(PACKAGE_VERSION)' \
		--section=1 $*.pod > $@

install-data-local:
	$(MKDIR_P) '$(DESTDIR)$(datarootdir)/zsh/site-functions/'
	$(INSTALL_DATA) zsh_completion \
		'$(DESTDIR)$(datarootdir)/zsh/site-functions/_ffcast'

uninstall-local:
	cd '$(DESTDIR)$(datarootdir)/zsh/site-functions' && $(RM) _ffcast
