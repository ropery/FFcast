#!/bin/bash

sub_commands['help']='print help for a sub-command'
sub_cmdfuncs['help']=subcmd_help
subcmd_help() {
    local sub_cmd=$1
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
        error "no such sub-command '%s'" "$sub_cmd"
    fi
    exit 1
}

sub_commands['png']='take a screenshot and save it as a PNG image'
png() {
    local outfile=${1:-screenshot-${w}x$h.png}
    msg 'saving to file: %s' "$outfile"
    cmdline=(ffmpeg -loglevel quiet -f x11grab -show_region 1
        -video_size "${w}x$h" -i "$DISPLAY+$_x,$_y" -frames:v 1
        -codec:v png -f image2 "$outfile")
}

sub_commands['%']='bypass predefined sub-commands, to avoid name conflicts'
sub_cmdfuncs['%']=nop
nop() {
    cmdline=("$@")
}

# vim:ts=4:sw=4:et:cc=80:
