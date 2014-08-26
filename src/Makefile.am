bin_SCRIPTS = ffcast
pkglibexec_SCRIPTS = subcmd

EXTRA_DIST = \
	ffcast.bash \
	subcmd.bash

MOSTLYCLEANFILES = $(bin_SCRIPTS) $(pkglibexec_SCRIPTS)

include $(top_srcdir)/automake.d/common.am

%: %.bash Makefile
	$(do_sub) < $< > $@
	chmod go-w,+x $@
