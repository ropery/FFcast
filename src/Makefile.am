include $(top_srcdir)/local.mk

bin_SCRIPTS = ffcast
pkglibexec_SCRIPTS = subcmd

EXTRA_DIST = \
	ffcast.bash \
	subcmd.bash

MOSTLYCLEANFILES = $(bin_SCRIPTS) $(pkglibexec_SCRIPTS)

%: %.bash Makefile
	$(do_sub) < $< > $@
	chmod go-w,+x $@
