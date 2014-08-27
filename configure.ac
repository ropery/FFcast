AC_INIT([FFcast], [2.2.0], [https://github.com/lolilolicon/FFcast/issues],
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

AC_ARG_ENABLE(xrectsel,
  [AS_HELP_STRING([--enable-xrectsel],
    [make xrectsel @<:@default=check@:>@])],
  [xrectsel=$enableval], [xrectsel=check])

AS_IF([test "x$xrectsel" != xno],
  [AC_CHECK_FILE([$srcdir/src/xrectsel/xrectsel.c],
    [AC_CONFIG_SUBDIRS([src/xrectsel])],
    [if test "x$xrectsel" != xcheck; then
       AC_MSG_FAILURE(
         [--enable-xrectsel was given, but xrectsel.c does not exist])
     fi])])

AC_OUTPUT
