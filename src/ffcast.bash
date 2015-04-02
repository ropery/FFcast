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

if ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3)) ||
   ((BASH_VERSINFO[0] < 4)); then
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
declare -- {root_{w,h},rect_{w,h,x,y,X,Y}}=0
declare -- borders=0 frame=0 frame_support=1 intersect=0

declare -A fmtmap=(
    ['D']='$DISPLAY'
    ['h']='$rect_h'
    ['w']='$rect_w'
    ['x']='$rect_x'
    ['y']='$rect_y'
    ['X']='$rect_X'
    ['Y']='$rect_Y'
    ['c']='$rect_x,$rect_y'
    ['C']='$rect_X,$rect_Y'
    ['g']='${rect_w}x$rect_h+$rect_x+$rect_y'
    ['s']='${rect_w}x$rect_h')

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
    printf '%s' "$1"
    printf -- "$2\n" "${@:3}"
}

_quote_cmd_line() {
    printf '%s' "$1"
    printf '%q' "$2"
    shift 2
    (($#)) && printf ' %q' "$@"
    printf '\n'
}

for ((i=0; i<${#logl[@]}; ++i)); do
    eval "${logl[i]}() {
        ((verbosity >= $i)) || return 0
        _msg \"\${logp[${logl[i]}]-${logl[i]}}: \" \"\$@\"
    } >&2"
done

for ((i=3; i<${#logl[@]}; ++i)); do
    eval "${logl[i]}_dryrun() {
        ((verbosity >= $i)) || return 0
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
    local -n ref_fmtmap=$1 ref_strarr=$2
    shift 2
    ref_strarr=()
    while (($#)); do
        ref_strarr+=('')
        printf '%s' "$1" |
        while IFS= read -r -n 1 -d ''; do
            if [[ $REPLY == '%' ]]; then
                IFS= read -r -n 1 -d '' || :
                if [[ -v ref_fmtmap[$REPLY] ]]; then
                    eval "ref_strarr[-1]+=${ref_fmtmap[$REPLY]}"
                elif [[ $REPLY == '%' ]]; then
                    ref_strarr[-1]+='%'
                else
                    ref_strarr[-1]+="%$REPLY"
                fi
            else
                ref_strarr[-1]+=$REPLY
            fi
        done
        shift
    done
}

printf '%s %s\n' max '>' min '<' | while IFS=' ' read -r mom cmp; do
    eval 'get_'$mom'_offsets() {
        local offsets=$1 o
        shift || return 1
        local {,_}{l,t,r,b}
        IFS=" " read l t r b <<< "$offsets"
        for offsets; do
            [[ -n $offsets ]] || continue
            IFS=" " read _{l,t,r,b} <<< "$offsets"
            for o in l t r b; do
                eval "(((_$o '$cmp' $o) && ($o = _$o))) || :"
            done
        done
        printf "%d %d %d %d\n" "$l" "$t" "$r" "$b"
    }'
done
unset -v mom cmp

set_region_vars_by_offsets() {
    offsets=$(get_max_offsets "$offsets" '0 0 0 0')
    debug 'sanitize offsets -> offsets="%s"' "$offsets"
    IFS=' ' read rect_{x,y,X,Y} <<< "$offsets"
    ((rect_w = root_w - rect_x - rect_X)) || :
    ((rect_h = root_h - rect_y - rect_Y)) || :
    set -- rect_{w,h,x,y,X,Y}
    debug 'set region variables'
    while (($#)); do
        debug '\t%s' "$(declare -p "$1")"
        shift
    done
    if ! ((rect_w > 0 && rect_h > 0)); then
        error 'invalid region size: %sx%s' "$rect_w" "$rect_h"
        return 1
    fi
}

# $1: a geospec
# $2: variable to assign offsets to
set_region_by_geospec() {
    printf -v "$2" '%s' "$(get_region_by_geospec "$1")"
}

# stdout: offsets
# $1: a geospec
get_region_by_geospec() {
    local IFS
    # sanitize whitespaces
    IFS=$' \t'; set -- $1; set -- "$*"
    case $1 in
        # x1,y1 x2,y2
        ?(-)+([0-9])+(\ |,)?(-)+([0-9])+(\ |,)?(-)+([0-9])+(\ |,)?(-)+([0-9]))
            IFS=' ,'
            set -- $1
            ;;
        # wxh+x+y
        +([0-9])x+([0-9])\+?(-)+([0-9])\+?(-)+([0-9]))
            IFS='x+'
            set -- $1
            set -- "$3" "$4" "$((root_w - $3 - $1))" "$((root_h - $4 - $2))"
            ;;
        *)
            return 1
            ;;
    esac
    IFS=' '
    printf '%s' "$*"
}

# $1: variable to assign offsets to
set_region_interactively() {
    msg '%s' "please select a region using mouse"
    printf -v "$1" '%s' "$(xrectsel '%x %y %X %Y')"
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

# $1: array variable to modify
# $2: variable to assign window ID to
set_window_interactively() {
    msg '%s' "please click once in target window"
    xwininfo_get_window_by_ref "$1" "$2"
}

# $1: array variable to modify
# $2: variable to assign window ID to
# ${@:3} are passed to xwininfo
xwininfo_get_window_by_ref() {
    local -n ref_windows=$1 ref_id=$2
    local -x LC_ALL=C
    xwininfo "${@:3}" `((!frame || frame_support)) || printf -- -frame` |
    awk -v borders="$borders" -v frame="$((frame && frame_support))" '
    BEGIN { OFS = " " }
    /^xwininfo: Window id: 0x[[:xdigit:]]+ / { _id = $4 }
    /^ *Border width: [[:digit:]]+$/ { _bw = $3 }
    $1 == "Corners:" && NF == 5 && split($2, a, /\+/) == 3 {
        _ol = a[2]
        _ot = a[3]
        if (split($3, a, /\+/) == 2) {
            _or = substr(a[1], 2)
            _ob = substr($4, length(a[1]) + 2)
        }
    }
    END {
        if (_id == "" || _bw == "" || _ob == "")
            exit 1
        if (frame) {
            xprop = "xprop -id \"" _id "\" -notype _NET_FRAME_EXTENTS"
            while ((xprop | getline) && ($1 != "_NET_FRAME_EXTENTS"));
            close(xprop)
            if ($1 == "_NET_FRAME_EXTENTS") {
                sub(/.*= /, "")
                split($0, a, /[ ,]+/)
                _ol -= a[1]; _ot -= a[3]; _or -= a[2]; _ob -= a[4]
            }
        }
        else if (!borders) {
            _ol += _bw; _ot += _bw; _or += _bw; _ob += _bw
        }
        print _id
        print _ol, _ot, _or, _ob
    }' |
    {
        read -r; ref_id=$REPLY
        read -r; ref_windows["$ref_id"]=$REPLY
    }
}

# stdout: wxh
# $@: passed to xwininfo
xwininfo_get_size() {
    local -x LC_ALL=C
    xwininfo "$@" |
    sed -n '
    $q1
    /^  Width: \([0-9]\+\)$/!d
    s//\1/; h; n
    /^  Height: \([0-9]\+\)$/!q1
    s//\1/; H; x; s/\n/x/; p; q'
}

# stdin: xdpyinfo -ext XINERAMA (preferably sanitized)
# $1: array variable to assign heads to, i.e. =([id]=offsets ...)
xdpyinfo_get_heads_by_ref() {
    local -n ref_heads=$1
    local IFS
    while IFS=' ' read -r REPLY; do
        REPLY=${REPLY#head #}
        if [[ $REPLY == \
            +([0-9]):\ +([0-9])x+([0-9])' @ '+([0-9]),+([0-9]) ]]; then
            IFS=' :x@,'
            set -- $REPLY
            set -- "$1" "$4" "$5" "$((root_w -$4 -$2))" "$((root_h -$5 -$3))"
            IFS=' '
            ref_heads["$1"]="${*:2}"
        fi
    done
    (($# == 5))
}

xdpyinfo_list_heads() {
    local -x LC_ALL=C
    xdpyinfo -ext XINERAMA |
    sed -n '
    /^XINERAMA extension not supported by xdpyinfo/ { p; q1 }
    /^XINERAMA version/!d
    :h; n; s/^  \(head #\)/\1/p; th; q'
}

run_default_command() {
    printf '%dx%d+%d+%d\n' "$rect_w" "$rect_h" "$rect_x" "$rect_y"
}

run_external_command() {
    local -- cmd=$1 extcmd
    shift || return 0
    local -a __args
    # always substitute format strings for external commands
    substitute_format_strings fmtmap __args "$@"
    # make sure it's an external command -- a disk file
    if ! extcmd=$(type -P "$cmd"); then
        error "external command '%s' not found" "$cmd"
        return 127
    fi
    verbose_run command -- "$extcmd" "${__args[@]}"
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

#---
# Process command line options and rectangles

[[ ! -t 2 ]] || msg_colors_on

usage() {
    cat <<EOF
ffcast @VERSION@
Usage:
  ${0##*/} [options] [command [args]]

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

xwininfo_get_size -root | IFS=x read root_{w,h} || usage 1

declare -- i=0 id= opt= var= __id
declare -a ids
OPTIND=1
while getopts ':#:bfg:hiqsvwx:' opt; do
    case $opt in
        h)  usage;;
        x)
            [[ $OPTARG != l?(ist) ]] || { xdpyinfo_list_heads; exit; }
            # cache list of all heads once
            if ((!${#heads_all[@]})); then
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
                if [[ ! -v heads_all[$id] ]]; then
                    warn "ignored invalid head ID: \`%s'" "$id"
                else
                    heads[$id]=${heads_all[$id]}
                    var="heads[$id]"
                    rects[i++]=$var; verbose 'rect: %s="%s"' "$var" "${!var}"
                fi
            done
            ;;
        g)
            var="regions[${#regions[@]}]"
            if ! set_region_by_geospec "$OPTARG" "$var"; then
                warn "ignored invalid geospec: \`%s'" "$OPTARG"
            else
                rects[i++]=$var; verbose 'rect: %s="%s"' "$var" "${!var}"
            fi
            ;;
        s)
            var="regions[${#regions[@]}]"
            set_region_interactively "$var"
            rects[i++]=$var; verbose 'rect: %s="%s"' "$var" "${!var}"
            ;;
       \#)
            set_window_by_id "$OPTARG" windows __id || exit
            var="windows[$__id]"
            rects[i++]=$var; verbose 'rect: %s="%s"' "$var" "${!var}"
            ;;
        w)
            set_window_interactively windows __id
            var="windows[$__id]"
            rects[i++]=$var; verbose 'rect: %s="%s"' "$var" "${!var}"
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
                frame_support=0
                warn 'no _NET_FRAME_EXTENTS support; using xwininfo -frame'
            fi
            ;;
        i)  intersect=1;;
        q)  ((verbosity > 0 && verbosity--)) || :;;
        v)  ((verbosity < ${#logl[@]} - 1 && verbosity++)) || :;;
      '?')  warn "invalid option: \`%s'" "$OPTARG";;
      ':')  error "option requires an argument: \`%s'" "$OPTARG"; exit 1;;
    esac
done
shift $((OPTIND - 1))

#---
# Combine all rectangles

declare -- mom offsets=
declare -n ref_rect

((intersect)) && mom=max || mom=min

for ref_rect in "${rects[@]}"; do
    offsets=$(get_"$mom"_offsets "$ref_rect" "$offsets")
    debug 'get_%s_offsets -> offsets="%s"' "$mom" "$offsets"
done
: ${offsets:='0 0 0 0'}
unset -n ref_rect
unset -v mom

set_region_vars_by_offsets || exit

# a little optimization
(($#)) || { run_default_command; exit; }

#---
# Import predefined sub-commands

for srcdir in "${srcdirs[@]}"; do
    subcmdsrc=$srcdir/subcmd
    if [[ -r $subcmdsrc ]]; then
        verbose "importing sub-commands from file %s" "$subcmdsrc"
        . "$subcmdsrc"
    fi
done
unset -v srcdir subcmdsrc

# make sure these are not defined as functions
unset -f builtin command

#---
# Execute

run_subcmd_or_command "$@"

# vim:ts=4:sw=4:et:cc=80:
