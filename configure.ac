AC_INIT([FFcast], [2.4.1], [https://github.com/lolilolicon/FFcast/issues],
        [ffcast], [https://github.com/lolilolicon/FFcast])

AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([foreign -Wall])

AC_PROG_SED

AC_PATH_PROG([POD2MAN], [pod2man])
AS_IF([test -z "$POD2MAN"], [AC_MSG_ERROR([pod2man is required])])

AC_CONFIG_FILES([
  Makefile
  aux/zsh_completion/Makefile
  doc/Makefile
  src/Makefile
])

AC_ARG_ENABLE([zsh-completion],
  [AS_HELP_STRING([--disable-zsh-completion],
    [do not install zsh completion file])],
  [wantzshcomp=$enableval], [wantzshcomp=yes])
AM_CONDITIONAL([WANT_ZSH_COMPLETION], [test "x$wantzshcomp" = xyes])

AC_ARG_ENABLE([xrectsel],
  [AS_HELP_STRING([--enable-xrectsel],
    [make xrectsel @<:@default=check@:>@])],
  [wantxrectsel=$enableval], [wantxrectsel=check])

AS_IF([test "x$wantxrectsel" != xno],
  [AC_CHECK_FILE([$srcdir/src/xrectsel/xrectsel.c],
    [AC_CONFIG_SUBDIRS([src/xrectsel])],
    [AS_IF([test "x$wantxrectsel" != xcheck],
      [AC_MSG_FAILURE(
        [--enable-xrectsel was given, but xrectsel.c does not exist])])])])

AC_OUTPUT
