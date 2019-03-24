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
# have access to, among others, the variables $rect_w $rect_h $rect_x $rect_y
# $rect_X $rect_Y and all the functions defined in ffcast.
#
# The positional arguments to a sub-command function are all the arguments
# after the sub-command as specified on the command line by the user.

sub_commands['help']='print help for a sub-command, or list all sub-commands'
sub_cmdfuncs['help']=subcmd_help
subcmd_help() {
    : 'usage: help [sub-command]'
    local sub_cmd=$1
    if ! (($#)); then
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
    declare -p root_{w,h} rect_{w,h,x,y,X,Y} rects heads regions windows
}

sub_commands['each']='run a sub-command on each selection consecutively'
sub_cmdfuncs['each']=subcmd_each
subcmd_each() {
    : 'usage: each [sub-command]'
    local -A fmtmap_each=(['i']='$i' ['n']='$((n + 1))' ['t']='$t')
    local -a __args
    local -i n
    local i t
    for ((n=0; n<${#rects[@]}; ++n)); do
        local -n ref_rect=${rects[n]}
        t=${rects[n]%%\[*}; t=${t%s}
        i=${rects[n]#*\[}; i=${i%\]}
        substitute_format_strings fmtmap_each __args "$@"
        <<<"$ref_rect" read rect_{x,y,X,Y}
        rect_w=root_w-rect_x-rect_X
        rect_h=root_h-rect_y-rect_Y
        report_active_rect "$n:${rects[n]}"
        run_subcmd_or_command "${__args[@]}"
        unset -n ref_rect
    done
}

sub_commands['abs']='swap corners to make region sizes non-negative'
sub_cmdfuncs['abs']=subcmd_abs
subcmd_abs() {
    : 'usage: abs [sub-command]'
    let rect_{x,X}+='rect_w<0?rect_w:0' || :
    let rect_{y,Y}+='rect_h<0?rect_h:0' || :
    rect_w=${rect_w#-}
    rect_h=${rect_h#-}
    report_active_rect "${FUNCNAME[0]#subcmd_}"
    run_subcmd_or_command "$@"
}

sub_commands['lag']='delay execution of a sub-command'
sub_cmdfuncs['lag']=subcmd_lag
subcmd_lag() {
    : 'usage: lag <duration> [sub-command]'
    msg 'delay: %s' "$1"
    command sleep $1 && shift || return
    run_subcmd_or_command "$@"
}

sub_commands['move']='move region by x,y pixels'
sub_cmdfuncs['move']=subcmd_move
subcmd_move() {
    : 'usage: move <x>[,<y>] [sub-command]'
    (($#)) || { run_default_command; return; }
    local x y
    IFS=$' \t,' read -r x y <<< "$1" && shift
    : ${x:=0} ${y:=0}
    subcmd_pad "-($y) $x $y -($x)" "$@"
}

sub_commands['pad']='add CSS-style padding to region'
sub_cmdfuncs['pad']=subcmd_pad
subcmd_pad() {
    : 'usage: pad <padding> [sub-command]'
    (($#)) || { run_default_command; return; }
    local -i rw=root_w rh=root_h $(printf ' %s%s' {w,h,x,y,X,Y}{=rect_,})
    local t r b l
    IFS=$' \t,' read -r t r b l <<< "$1" && shift
    local -i t=$t r=${r:-t} b=${b:-t} l=${l:-r}
    debug 'pad: top=%d right=%d bottom=%d left=%d' "$t" "$r" "$b" "$l"
    rect_x+=-l rect_y+=-t rect_X+=-r rect_Y+=-b
    rect_w=root_w-rect_x-rect_X
    rect_h=root_h-rect_y-rect_Y
    report_active_rect "${FUNCNAME[0]#subcmd_}"
    run_subcmd_or_command "$@"
}

sub_commands['png']='take a screenshot and save it as a PNG image'
sub_cmdfuncs['png']=subcmd_png
subcmd_png() {
    : 'usage: png [filename]'
    ensure_region_is_on_screen; verify_region_size
    local -a __args
    substitute_format_strings fmtmap __args "$@"
    : ${__args[0]="$(printf '%s-%(%s)T_%dx%d.png' screenshot -1 \
        "$rect_w" "$rect_h")"}
    msg 'saving to file: %s' "${__args[-1]}"  # unreliable
    verbose_run command \
        ffmpeg -loglevel error -nostdin \
        -f x11grab -draw_mouse 0 -show_region 0 \
        -video_size "$root_w"x"$root_h" -i "$DISPLAY" \
        -filter:v crop="$rect_w:$rect_h:$rect_x:$rect_y" \
        -f image2 -codec:v png -frames:v 1 "${__args[@]}"
}

sub_commands['rec']='record a screencast'
sub_cmdfuncs['rec']=subcmd_rec
subcmd_rec() {
    : 'usage: rec [-m <n>] [-r <fps>] [filename.ext]'
    ensure_region_is_on_screen; verify_region_size
    local -a __args
    local -a v=(fatal error info verbose debug)  # ffmpeg loglevels
    local m r opt
    OPTIND=1
    while getopts ':m:r:' opt; do
        case $opt in
            m) m=$OPTARG;;
            r) r=$OPTARG;;
        esac
    done
    shift $((OPTIND - 1))
    substitute_format_strings fmtmap __args "$@"
    : ${__args[0]="$(printf '%s-%(%s)T.mkv' screencast -1)"}
    msg 'saving to file: %s' "${__args[-1]}"  # unreliable
    verbose_run command \
        ffmpeg -hide_banner -loglevel "${v[verbosity]}" \
        -f x11grab -show_region 1 ${r:+-framerate "$r"} \
        -video_size "${rect_w}x$rect_h" -i "$DISPLAY+$rect_x,$rect_y" \
        ${m:+-filter:v crop="iw-mod(iw\,$m):ih-mod(ih\,$m)"} "${__args[@]}"
}

sub_commands['trim']='remove edges from region'
sub_cmdfuncs['trim']=subcmd_trim
subcmd_trim() {
    : 'usage: trim [-f <n[%]>] [sub-command]'
    local -i x y
    local f opt
    OPTIND=1
    while getopts ':f:' opt; do
        case $opt in
            f) f=$OPTARG;;
        esac
    done
    shift $((OPTIND - 1))
    verbosity=0 subcmd_png - |
    command convert - ${f:+-fuzz "$f"} -format '%@\n' info:- |
    tee >(read -r; debug 'trim bounding box: %s' "$REPLY") |
    IFS=x+ read -r rect_{w,h} x y
    rect_x+=x rect_X=root_w-rect_x-rect_w
    rect_y+=y rect_Y=root_h-rect_y-rect_h
    report_active_rect "${FUNCNAME[0]#subcmd_}"
    run_subcmd_or_command "$@"
}

# vim:ts=4:sw=4:et:cc=80:
