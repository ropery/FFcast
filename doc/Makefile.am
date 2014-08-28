include $(top_srcdir)/local.mk

man_MANS = ffcast.1

EXTRA_DIST = \
	ffcast.1.pod

MOSTLYCLEANFILES = $(man_MANS) $(man_MANS:.1=.pod)

# purpose for saving as foo.pod: make pod2man auto-set --name=FOO
%.1: %.1.pod Makefile
	$(do_sub) < $< > $*.pod
	$(AM_V_at)touch -r $< -- $*.pod
	$(POD2MAN) \
		--center='$(PACKAGE_NAME) Manual' \
		--release='$(PACKAGE_NAME) $(PACKAGE_VERSION)' \
		--section=1 $*.pod > $@
