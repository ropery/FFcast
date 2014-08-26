SUBDIRS = doc src $(subdirs)

EXTRA_DIST = \
	zsh_completion \
	README.asciidoc

install-data-local:
	$(MKDIR_P) '$(DESTDIR)$(datarootdir)/zsh/site-functions/'
	$(INSTALL_DATA) zsh_completion \
		'$(DESTDIR)$(datarootdir)/zsh/site-functions/_ffcast'

uninstall-local:
	cd '$(DESTDIR)$(datarootdir)/zsh/site-functions' && $(RM) _ffcast
