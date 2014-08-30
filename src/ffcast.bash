#!/bin/bash
#
# ffcast @VERSION@
# Copyright (C) 2011-2014  lolilolicon <lolilolicon@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

if (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3 )) ||
   (( BASH_VERSINFO[0] < 4 )); then
    printf 'fatal: requires bash 4.3+ but this is bash %s\n' "$BASH_VERSION"
    exit 43
fi >&2

set -e +m -o pipefail
shopt -s extglob lastpipe
trap -- 'trap_err $LINENO' ERR

readonly -a srcdirs=(
    '@pkglibexecdir@'
    '@sysconfdir@/@PACKAGE@'
    "${XDG_CONFIG_HOME:-$HOME/.config}"/'@PACKAGE@')
readonly -a logl=(error warn msg verbose debug)
declare -A 'logp=([warn]="warning" [msg]=":")'
declare -- verbosity=2
declare -A sub_commands=() sub_cmdfuncs=()
declare -a rects=() regions=()
declare -A heads=() windows=() heads_all=()
declare -- rootw=0 rooth=0 _x=0 _y=0 x_=0 y_=0 w=0 h=0
declare -- borders=0 frame=0 frame_extents_support=1 intersection=0

declare -A fmtmap=(
    ['D']='$DISPLAY'
    ['h']='$h'
    ['w']='$w'
    ['x']='$_x'
    ['y']='$_y'
    ['X']='$x_'
    ['Y']='$y_'
    ['c']='$_x,$_y'
    ['C']='$x_,$y_'
    ['g']='${w}x$h+$_x+$_y'
    ['s']='${w}x$h')

#---
# Functions

msg_colors_on() {
    logp[error]=$'\e[1;31m''error'$'\e[m'
    logp[warn]=$'\e[1;33m''warning'$'\e[m'
    logp[msg]=$'\e[34m'':'$'\e[m'
    logp[verbose]=$'\e[32m''verbose'$'\e[m'
    logp[debug]=$'\e[36m''debug'$'\e[m'
}

trap_err() {
    set -- "$1" "${PIPESTATUS[@]}"
    printf '%s:%d: ERR:' "${BASH_SOURCE[0]}" "$1"; shift
    printf ' PIPESTATUS:'
    printf ' %d' "$@"
    printf '  BASH_COMMAND: %s\n' "$BASH_COMMAND"
} >&2

_msg() {
    local prefix=$1
    shift || return 0
    local fmt=$1
    shift || return 0
    printf '%s' "$prefix"
    printf -- "$fmt\n" "$@"
}

_quote_cmd_line() {
    local prefix=$1
    shift || return 0
    local cmd=$1
    shift || return 0
    printf '%s' "$prefix"
    printf '%q' "$cmd"
    (( $# )) && printf ' %q' "$@"
    printf '\n'
}

_report_array_by_key() {
    local varname=$1
    local -n ref_array=$1
    local key=$2
    printf '%q[%q]=%q\n' "$varname" "$key" "${ref_array[$key]}"
}

debug_array_by_key() {
    (( verbosity >= 4 )) || return 0
    printf '%s: ' "${logp[debug]}"
    _report_array_by_key "$@"
} >&2

for ((i=0; i<${#logl[@]}; ++i)); do
    eval "${logl[i]}() {
        (( verbosity >= $i )) || return 0
        _msg \"\${logp[${logl[i]}]-${logl[i]}}: \" \"\$@\"
    } >&2"
done

for ((i=3; i<${#logl[@]}; ++i)); do
    eval "${logl[i]}_dryrun() {
        (( verbosity >= $i )) || return 0
        _quote_cmd_line \"\${logp[${logl[i]}]-${logl[i]}}: cmdline: \" \"\$@\"
    } >&2
    ${logl[i]}_run() {
        ${logl[i]}_dryrun \"\$@\" && \"\$@\"
    }"
done

# $1: array variable of format string mappings
# $2: array variable to assign substitution results to
# ${@:3} are strings to be substituted
substitute_format_strings() {
    local -n ref_fmtmap=$1
    local -n ref_strarr=$2
    local fmt str c
    ref_strarr=()
    for fmt in "${@:3}"; do
        str=
        printf '%s' "$fmt" |
        while IFS= read -r -n 1 -d '' c; do
            if [[ $c == '%' ]]; then
                IFS= read -r -n 1 -d '' c || :
                if [[ -v ref_fmtmap[$c] ]]; then
                    eval "str+=${ref_fmtmap[$c]}"
                elif [[ $c == '%' ]]; then
                    str+='%'
                else
                    str+="%$c"
                fi
            else
                str+=$c
            fi
        done
        ref_strarr+=("$str")
    done
}

printf '%s %s\n' max '>' min '<' | while IFS=' ' read -r mom cmp; do
    eval 'get_'$mom'_offsets() {
        local offsets=$1 o
        shift || return 1
        local {,_}{l,t,r,b}
        IFS=" " read l t r b <<< "$offsets"
        for offsets in "$@"; do
            [[ -n $offsets ]] || continue
            IFS=" " read _{l,t,r,b} <<< "$offsets"
            for o in l t r b; do
                eval "(( (_$o '$cmp' $o) && ($o = _$o) )) || :"
            done
        done
        printf "%d %d %d %d\n" "$l" "$t" "$r" "$b"
    }'
done
unset -v mom cmp

# $1: a geospec
# $2: variable to assign offsets to
set_region_by_geospec() {
    local geospec=$1
    local _x _y x_ y_ w h
    local n='?([-+])+([0-9])'
    local m='?(-)+([0-9])'
    local N='+([0-9])'
    local s='@(*([ \t]),*([ \t])|+([ \t]))'
    # strip whitespaces
    IFS=$' \t' read -r geospec <<< "$geospec"
    case $geospec in
        $n$s$n$s$n$s$n)  # x1,y1 x2,y2
            IFS=$', \t' read _x _y x_ y_ <<< "$geospec"
            ;;
        ${N}x${N}\+${m}\+${m})  # wxh+x+y
            IFS='x+' read w h _x _y <<< "$geospec"
            (( x_ = rootw - _x - w )) || :
            (( y_ = rooth - _y - h )) || :
            ;;
        *)
            return 1
            ;;
    esac
    printf -v "$2" '%d %d %d %d' "$_x" "$_y" "$x_" "$y_"
}

# $1: variable to assign offsets to
set_region_interactively() {
    msg "%s" "please select a region using mouse"
    printf -v "$1" '%d %d %d %d' $(xrectsel_get_offsets)
}

# $1: array variable to modify
# $2: variable to assign window ID to
set_window_interactively() {
    msg "%s" "please click once in target window"
    local -a args
    if (( frame && !frame_extents_support )); then
        args=("-frame")
    fi
    xwininfo_get_window_by_ref "$1" "$2" "${args[@]}"
}

# $1: a window ID
# $2: array variable to modify
# $3: variable to assign window ID to
set_window_by_id() {
    # Unlike xprop, xwininfo simply ignores an invalid -id argument
    if [[ $1 != @(+([0-9])|0x+([[:xdigit:]])) ]] ||
        [[ $(printf '%d' "$1") == 0 ]]; then
        error 'invalid window id: %s' "$1"
        return 1
    fi
    xwininfo_get_window_by_ref "$2" "$3" -id "$1"
}

# stdin: xdpyinfo -ext XINERAMA (preferably sanitized)
# $1: array variable to assign heads to, i.e. =([id]=offsets ...)
xdpyinfo_get_heads_by_ref() {
    local line
    local i w h _x _y x_ y_
    local n='+([0-9])'
    # See print_xinerama_info() in xdpyinfo.c
    local head="head #$n: ${n}x$n @ $n,$n"
    while IFS=' ' read -r line; do
        if [[ $line == $head ]]; then
            IFS=' :x@,' read i w h _x _y <<< "${line#head #}"
            (( x_ = rootw - _x - w )) || :
            (( y_ = rooth - _y - h )) || :
            printf -v "$1[$i]" '%d %d %d %d' "$_x" "$_y" "$x_" "$y_"
        fi
    done
    [[ -n $i ]]
}

xdpyinfo_list_heads() {
    LC_ALL=C xdpyinfo -ext XINERAMA | grep '^  head #' | sed 's/^ *//'
}

# stdout: left, right, top, bottom
# $1: window ID
xprop_get_frame_extents() {
    LC_ALL=C xprop -id "$1" -notype _NET_FRAME_EXTENTS |
    grep '^_NET_FRAME_EXTENTS = ' | sed 's/.*= //'
}

# stdout: x1 y1 x2 y2
xrectsel_get_offsets() {
    # Note: requires xrectsel 0.3
    xrectsel "%x %y %X %Y"$'\n'
}

# stdin: xwininfo output (locale: C)
# stdout: ${width}x${height}
xwininfo_get_size() {
    local line
    local w h
    while IFS=$' \t' read -r line; do
        if [[ $line == 'Width: '+([0-9]) ]]; then
            w=${line#'Width: '}
        elif [[ $line == 'Height: '+([0-9]) ]]; then
            h=${line#'Height: '}
        else
            continue
        fi
        if (( w && h )); then
            printf '%dx%d\n' "$w" "$h"
            return
        fi
    done
    return 1
}

# $1: array variable to modify
# $2: variable to assign window ID to
# ${@:3} are passed to xwininfo
xwininfo_get_window_by_ref() {
    local line
    local _x _y x_ y_ b
    local fl fr ft fb id
    local n='-?[0-9]+'
    local corners="^Corners: *\\+($n)\\+($n) *-$n\\+$n *-($n)-($n) *\\+$n-$n\$"
    local window_id="^xwininfo: Window id: (0x[[:xdigit:]]+)"
    LC_ALL=C xwininfo "${@:3}" |
    # Note: explicitly set IFS to ensure stripping of whitespaces
    while IFS=$' \t' read -r line && [[ -z $id || -z $_x || -z $b ]]; do
        if [[ $line =~ $window_id ]]; then
            id=${BASH_REMATCH[1]}
        elif [[ $line == 'Border width: '+([0-9]) ]]; then
            b=${line#'Border width: '}
        elif [[ $line =~ $corners ]]; then
            _x=${BASH_REMATCH[1]}
            _y=${BASH_REMATCH[2]}
            x_=${BASH_REMATCH[3]}
            y_=${BASH_REMATCH[4]}
        fi
    done
    [[ -n $id && -n $_x && -n $b ]] || return 1
    if (( frame && frame_extents_support )); then
        if ! xprop_get_frame_extents "$id" | IFS=' ,' read fl fr ft fb; then
            warn "unable to determine frame extents for window %s" "$id"
        else
            (( _x -= fl )) || :
            (( _y -= ft )) || :
            (( x_ -= fr )) || :
            (( y_ -= fb )) || :
        fi
    elif (( ! borders )); then
            (( _x += b )) || :
            (( _y += b )) || :
            (( x_ += b )) || :
            (( y_ += b )) || :
    fi
    printf -v "$1[$id]" '%d %d %d %d' "$_x" "$_y" "$x_" "$y_"
    printf -v "$2" '%s' "$id"
}

run_default_command() {
    printf '%dx%d+%d+%d\n' "$w" "$h" "$_x" "$_y"
}

run_external_command() {
    local -- cmd=$1 extcmd
    shift || return 0
    local -a args=()
    # always substitute format strings for external commands
    substitute_format_strings fmtmap args "$@"
    # make sure it's an external command -- a disk file
    if ! extcmd=$(type -P "$cmd"); then
        error "external command '%s' not found" "$cmd"
        return 127
    fi
    verbose_run command -- "$extcmd" "${args[@]}"
}

run_subcmd_or_command() {
    local sub_cmd=$1
    if [[ -z $sub_cmd ]]; then
        run_default_command
        exit
    fi
    if [[ -v sub_commands[$sub_cmd] ]]; then
        shift
        local sub_cmd_func=${sub_cmdfuncs[$sub_cmd]:-$sub_cmd}
        if [[ $(type -t "$sub_cmd_func") == function ]]; then
            verbose_run "$sub_cmd_func" "$@"
        else
            error "sub-command '%s' function '%s' not found" "$sub_cmd" \
                "$sub_cmd_func"
            exit 1
        fi
    else
        run_external_command "$@" || exit
    fi
}

set_region_vars_by_offsets() {
    offsets=$(get_max_offsets "$offsets" '0 0 0 0')
    debug "sanitize offsets -> offsets='%s'" "$offsets"
    IFS=' ' read _x _y x_ y_ <<< "$offsets"
    (( w = rootw - _x - x_ )) || :
    (( h = rooth - _y - y_ )) || :
    local var
    debug 'set region variables'
    for var in w h _{x,y} {x,y}_; do
        debug '\t%s' "$(declare -p "$var")"
    done
    if ! (( w > 0 && h > 0 )); then
        "${logl[${1:-0}]}" 'invalid region size: %sx%s' "$w" "$h"
        return 1
    fi
}

#---
# Process command line options and rectangles

[[ ! -t 2 ]] || msg_colors_on

usage() {
    cat <<EOF
ffcast @VERSION@
Usage:
  ${0##*/} [options] [sub-command [args]] [command [args]]

Options:
  -g <geospec>  specify a region in numeric geometry
  -x <n|list>   select the Xinerama head of ID n
  -s            select a rectangular region by mouse
  -w            select a window by mouse click
  -# <n>        select a window by window ID
  -b            include window borders hereafter
  -f            include window frame hereafter
  -i            combine regions by intersection
  -q            be less verbose
  -v            be more verbose
  -h            print this help and exit

All options can be repeated, and are processed in order.
If no region is selected by the user, select fullscreen.

For more details see ffcast(1).
EOF
  exit "${1:-0}"
}

LC_ALL=C xwininfo -root | xwininfo_get_size | IFS=x read rootw rooth || usage 1

declare -- i=0 id= opt= var=
declare -a ids
OPTIND=1
while getopts ':#:bfg:hiqsvwx:' opt; do
    case $opt in
        h)  usage;;
        x)
            [[ $OPTARG != l?(ist) ]] || { xdpyinfo_list_heads; exit; }
            # cache list of all heads once
            if (( ! ${#heads_all[@]} )); then
                if ! xdpyinfo_list_heads |
                    xdpyinfo_get_heads_by_ref heads_all; then
                    error 'failed to get all Xinerama heads'
                    exit 1
                fi
                debug 'got all Xinerama heads'
                debug '\t%s' "$(declare -p heads_all)"
            fi
            if [[ $OPTARG == all ]]; then
                ids=("${!heads_all[@]}")
            else
                IFS=' ,' read -a ids <<< "$OPTARG"
            fi
            for id in "${ids[@]}"; do
                if [[ $id != +([0-9]) ]]; then
                    warn "ignored invalid head ID: \'%s'" "$id"
                elif [[ ! -v heads_all[$id] ]]; then
                    warn "ignored non-existent head ID: \`%s'" "$id"
                else
                    heads[$id]=${heads_all[$id]}
                    rects[i++]="heads[$id]"
                fi
            done
            ;;
        g)
            var="regions[${#regions[@]}]"
            if ! set_region_by_geospec "$OPTARG" "$var"; then
                warn "ignored invalid geospec: \`%s'" "$geospec"
            else
                rects[i++]=$var
            fi
            ;;
        s)
            var="regions[${#regions[@]}]"
            set_region_interactively "$var"
            rects[i++]=$var
            ;;
       \#)
            set_window_by_id "$OPTARG" windows var || exit
            var="windows[$var]"
            rects[i++]=$var
            ;;
        w)
            set_window_interactively windows var
            var="windows[$var]"
            rects[i++]=$var
            ;;
        b)
            borders=1
            verbose "windows: now including borders"
            ;;
        f)
            frame=1
            verbose "windows: now including window manager frame"
            if ! LC_ALL=C xprop -root -notype _NET_SUPPORTED |
                grep -qw _NET_FRAME_EXTENTS; then
                frame_extents_support=0
                warn 'no _NET_FRAME_EXTENTS support; using xwininfo -frame'
            fi
            ;;
        i)  intersection=1;;
        q)  (( (verbosity > 0) && verbosity-- )) || :;;
        v)  (( (verbosity < ${#logl[@]} - 1) && verbosity++ )) || :;;
      '?')  warn "invalid option: \`%s'" "$OPTARG";;
      ':')  error "option requires an argument: \`%s'" "$OPTARG"; exit 1;;
    esac
done
shift $(( OPTIND - 1 ))

#---
# Combine all rectangles

declare -- mom offsets=
declare -n ref_rect

(( intersection )) && mom=max || mom=min

for ref_rect in "${rects[@]}"; do
    offsets=$(get_"$mom"_offsets "$ref_rect" "${offsets}")
    debug "get_%s_offsets -> offsets='%s'" "$mom" "$offsets"
done
: ${offsets:='0 0 0 0'}
unset -n ref_rect
unset -v mom

set_region_vars_by_offsets || exit

#---
# Import predefined sub-commands

# a little optimization
(( $# )) || { run_default_command; exit; }

for srcdir in "${srcdirs[@]}"; do
    subcmdsrc=$srcdir/subcmd
    if [[ -r $subcmdsrc ]]; then
        verbose "importing sub-commands from file %s" "$subcmdsrc"
        . "$subcmdsrc"
    fi
done
unset -v srcdir subcmdsrc

# make sure these are not defined as sub-commands
for cmd in builtin command; do
    unset -f $cmd
    if [[ -v sub_commands[$cmd] ]]; then
        unset -v sub_commands[$cmd]
        warn 'unset sub-command %s' "$cmd"
    fi
done
unset -v cmd

#---
# Execute

run_subcmd_or_command "$@"

# vim:ts=4:sw=4:et:cc=80:
