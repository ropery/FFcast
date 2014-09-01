FFcast - Hacking
================

This is the guide for anyone who wants to contribute to FFcast. It concerns
style and conventions for this project, as well as general best practice in
programming in the Bourne-Again SHell language.

Coding Style
------------

1.  All code should be indented with 4 spaces at each level. Do not use tabs.

2.  Physical lines should be no more than 80 characters long.

3.  The `test` and `[` builtin commands should never be used. Instead, use the
    `[[` compound command for conditional expression tests.

4.  Arithmetic binary operators should never be used by `[[`. Instead, use the
    `((` compound command for arithmetic comparison.

5.  Global variables should be declared at the top of the script. Local
    variables should be declared at the start of the function body.

6.  Do not create ALL_CAPS variables. Such variables are by convention reserved
    for environment variables that affect the behavior of programs or the shell.

7.  Generally, follow the style already present in the script.

On Call by Reference Functions
------------------------------

A call by reference function can be implemented in several ways:

    set_var_eval() {
        eval "$1=foo"
    }

    set_var_printfv() {
        printf -v "$1" '%s' foo
    }

    set_var_nameref() {
        local -n ref=$1
        ref=foo
    }

Such functions must be handled with care. Consider the following:

*   The caller cannot know what local variables are set in the function.
*   The function cannot predict what names will be passed by the caller.
*   When the function sets a local variable with the same name as the name passed
    by the caller, the external name is masked by the local name.

As such, artificial naming conventions have to be established, so that local
names will never overlap with external names passed as reference.

The following are the conventions used in this project:

1.  Significant global variables are treated as "well-known names"; functions
must not set any local variable with one of these names. This is reasonable,
because functions should not mask these names in the first place.

2.  Other names, iff they are to be passed as reference, shall be prefixed with
    `__`.

3.  A name shall be prefixed with `ref_` iff it has the nameref attribute.

Miscellaneous Remarks
---------------------

The behavior of the shell is controlled mainly via `set` and `shopt`. It's
important that you know how these shell options affect the shell's behavior.

Most shell builtin commands accept `--` to signify end of options. As a rule,
always explicitly insert `--` before start of normal arguments.
