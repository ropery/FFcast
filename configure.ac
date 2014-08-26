AC_INIT([FFcast], [2.1.0], [https://github.com/lolilolicon/FFcast/issues],
        [ffcast], [https://github.com/lolilolicon/FFcast])

AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([foreign])

AC_PROG_SED

AC_PATH_PROG([POD2MAN], [pod2man])
if test -z "$POD2MAN"; then
  AC_MSG_ERROR([pod2man is required])
fi

AC_CONFIG_FILES([
  Makefile
  doc/Makefile
  src/Makefile
])
AC_CONFIG_SUBDIRS([src/xrectsel])
AC_OUTPUT
