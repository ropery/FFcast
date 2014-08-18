#!/bin/bash
#
# To register a sub-command 'foo', you MUST add this,
#
#     sub_commands['foo']='description'
#
# By default, running sub-command 'foo' will execute the function 'foo'.
# But you MAY explicitly associate sub-command 'foo' with function 'bar',
#
#     sub_cmdfuncs['foo']=bar
#
# This is useful in the cases when your sub-command isn't a valid function
# name, or when it conflicts with an existing function.
#
# As this file is sourced after all the geometry processing has been done, you
# have access to, among others, the variables $w $h $_x $_y $x_ $y_ and all the
# functions defined in ffcast.
#
# The positional arguments to a sub-command function are all the arguments
# after the sub-command as specified on the command line by the user.

sub_commands['help']='print help for a sub-command, or list all sub-commands'
sub_cmdfuncs['help']=subcmd_help
subcmd_help() {
    : 'usage: help [sub-command]'
    local sub_cmd=$1
    if ! (( $# )); then
        for sub_cmd in "${!sub_commands[@]}"; do
            printf "%s\t%s\n" "$sub_cmd" "${sub_commands[$sub_cmd]}"
        done | sort -k 1,1
        return
    fi
    if [[ -v sub_commands[$sub_cmd] ]]; then
        local sub_cmd_func=${sub_cmdfuncs[$sub_cmd]:-$sub_cmd}
        printf '%s: %s\n' "$sub_cmd" "${sub_commands[$sub_cmd]}"
        if [[ $(type -t "$sub_cmd_func") == function ]]; then
            declare -fp "$sub_cmd_func"
            return
        else
            error "sub-command '%s' function '%s' not found" "$sub_cmd" \
                "$sub_cmd_func"
        fi
    else
        error "no such sub-command '%s'; use 'help' to get a list." "$sub_cmd"
    fi
    exit 1
}

sub_commands['%']='look up external command only; bypass sub-commands'
sub_cmdfuncs['%']=run_external_command

sub_commands['dump']='dump region-related variables in bash code'
sub_cmdfuncs['dump']=subcmd_dump
subcmd_dump() {
    (( ! ${#head_ids[@]} )) || declare -p heads
    declare -p {root,}{w,h} _{x,y} {x,y}_ offsets_list
}

sub_commands['each']='run a sub-command on each selection consecutively'
sub_cmdfuncs['each']=subcmd_each
subcmd_each() {
    : 'usage: each [sub-command]'
    local offsets;
    for offsets in "${offsets_list[@]}"; do
        set_region_vars_by_offsets 1 || continue
        run_subcmd_or_command "$@"
    done
}

sub_commands['pad']='Add CSS-style padding to region'
sub_cmdfuncs['pad']=subcmd_pad
subcmd_pad() {
    : 'usage: pad <padding> [sub-command]'
    local -- t r b l
    IFS=' \t,' read -r t r b l <<< "$1"
    shift || return 0
    if [[ -z $t ]]; then
        return
    elif [[ -z $r ]]; then
        local -i t=$t r=$t b=$t l=$t
    elif [[ -z $b ]]; then
        local -i t=$t r=$r b=$t l=$r
    elif [[ -z $l ]]; then
        local -i t=$t r=$r b=$b l=$r
    else
        local -i t=$t r=$r b=$b l=$l
    fi
    (( _x -= l )) || :
    (( _y -= t )) || :
    (( x_ -= r )) || :
    (( y_ -= b )) || :
    verbose 'padding: top=%d right=%d bottom=%d left=%d' "$t" "$r" "$b" "$l"
    offsets="$_x $_y $x_ $y_"
    set_region_vars_by_offsets || exit
    run_subcmd_or_command "$@"
}

sub_commands['png']='take a screenshot and save it as a PNG image'
sub_cmdfuncs['png']=subcmd_png
subcmd_png() {
    : 'usage: png [filename]'
    local -a args=()
    while (( $# )); do
        args+=("$(format_to_string "$1")")
        shift
    done
    : ${args[0]="$(printf '%s-%(%s)T_%dx%d.png' screenshot -1 "$w" "$h")"}
    msg 'saving to file: %s' "${args[-1]}"  # unreliable
    verbose_run command -- \
        ffmpeg -loglevel error -f x11grab -draw_mouse 0 -show_region 1 \
        -video_size "${w}x$h" -i "$DISPLAY+$_x,$_y" \
        -f image2 -codec:v png -frames:v 1 "${args[@]}"
}

sub_commands['rec']='record a screencast'
sub_cmdfuncs['rec']=subcmd_rec
subcmd_rec() {
    : 'usage: rec [-m <n>] [filename.ext]'
    local -a args=()
    local -a v=(fatal error info verbose debug)  # ffmpeg loglevels
    local m=1 opt
    OPTIND=1
    while getopts ':m:' opt; do
        case $opt in
            m) m=$OPTARG;;
        esac
    done
    shift $(( OPTIND -1 ))
    while (( $# )); do
        args+=("$(format_to_string "$1")")
        shift
    done
    : ${args[0]="$(printf '%s-%(%s)T.mkv' screencast -1)"}
    msg 'saving to file: %s' "${args[-1]}"  # unreliable
    verbose_run command -- \
        ffmpeg -loglevel "${v[verbosity]}" -f x11grab -show_region 1 \
        -framerate 25 -video_size "${w}x$h" -i "$DISPLAY+$_x,$_y" \
        -filter:v crop="iw-mod(iw\\,$m):ih-mod(ih\\,$m)" "${args[@]}"
}

# vim:ts=4:sw=4:et:cc=80:
