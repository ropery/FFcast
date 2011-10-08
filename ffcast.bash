#!/bin/bash
#
# FFcast @VERSION@
# Copyright (C) 2011  lolilolicon <lolilolicon@gmail.com>
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

set -e
shopt -s extglob

readonly progname=ffcast progver='@VERSION@'
readonly cast_cmd_pattern='@(ffmpeg|byzanz-record|recordmydesktop)'
declare -a cast_args x11grab_opts
declare -a cast_cmdline=(ffmpeg -v 1 -r 25 -- -vcodec libx264 \
    "$progname-$(date +%Y%m%d-%H%M%S).mkv")
declare -- cast_cmd=${cast_cmdline[0]}
declare -- region_select_action
declare -i borderless=1 mod16=0 print_geometry_only=0 verbosity=0
PS4='debug: command: '  # for set -x
x='+x'; [[ $- == *x* ]] && x='-x'  # save set -x
readonly x

#---
# Functions

_msg() {
    local prefix=$1
    shift || return 0
    local fmt=$1
    shift || return 0
    printf "$prefix$fmt\n" "$@"
}

debug() {
    (( verbosity >= 2 )) || return 0
    _msg 'debug: ' "$@"
} >&2

verbose() {
    (( verbosity >= 1 )) || return 0
    _msg 'verbose: ' "$@"
} >&2

msg() {
    (( verbosity >= 0 )) || return 0
    _msg ':: ' "$@"
} >&2

warn() {
    (( verbosity >= -1 )) || return 0
    _msg 'warning: ' "$@"
} >&2

error() {
    (( verbosity >= -1 )) || return 0
    _msg 'error: ' "$@"
} >&2

list_cast_cmds() {
    local -a cmds
    IFS='|' read -a cmds <<< "${cast_cmd_pattern:2: -1}"
    printf "%s\n" "${cmds[@]}"
}

parse_geospec_get_corners() {
    local geospec=$1
    local _x _y x_ y_ w h
    local n='?([-+])+([0-9])'
    local m='?(-)+([0-9])'
    local N='+([0-9])'
    # strip whitespaces
    IFS=$' \t' read -r geospec <<< "$geospec"
    case $geospec in
        $n,$n+([' \t'])$n,$n)  # x1,y1 x2,y2
            IFS=$', \t' read _x _y x_ y_ <<< "$geospec"
            ;;
        ${N}x${N}\+${m}\+${m})  # wxh+x+y
            IFS='x+' read w h _x _y <<< "$geospec"
            (( x_ = rootw - _x - w )) || :
            (( y_ = rooth - _y - h )) || :
            ;;
        *)
            error "invalid geometry specification: \`%s'" "$geospec"
            return 1
            ;;
    esac
    printf '%d,%d %d,%d' $_x $_y $x_ $y_
}

region_intersect_corners() {
    local corners
    local _x _y x_ y_
    local _X _Y X_ Y_
    # Initialize variable- otherwise bash will fallback to 0
    IFS=' ,' read _X _Y X_ Y_ <<< "$1"
    shift || return 1
    for corners in "$@"; do
        IFS=' ,' read _x _y x_ y_ <<< "$corners"
        (( _X = _x > _X ? _x : _X )) || :
        (( _Y = _y > _Y ? _y : _Y )) || :
        (( X_ = x_ > X_ ? x_ : X_ )) || :
        (( Y_ = y_ > Y_ ? y_ : Y_ )) || :
    done
    printf '%d,%d %d,%d' $_X $_Y $X_ $Y_
}

region_union_corners() {
    local corners
    local _x _y x_ y_
    local _X _Y X_ Y_
    # Initialize variable- otherwise bash will fallback to 0
    IFS=' ,' read _X _Y X_ Y_ <<< "$1"
    shift || return 1
    for corners in "$@"; do
        IFS=' ,' read _x _y x_ y_ <<< "$corners"
        (( _X = _x < _X ? _x : _X )) || :
        (( _Y = _y < _Y ? _y : _Y )) || :
        (( X_ = x_ < X_ ? x_ : X_ )) || :
        (( Y_ = y_ < Y_ ? y_ : Y_ )) || :
    done
    printf '%d,%d %d,%d' $_X $_Y $X_ $Y_
}

select_region_get_corners() {
    msg "%s" "please select a region using mouse"
    xrectsel_get_corners
}

select_window_get_corners() {
    msg "%s" "please click once in target window"
    LC_ALL=C xwininfo | xwininfo_get_corners
}

# stdout: x1,y1 x2,y2
xrectsel_get_corners() {
    # Note: requires xrectsel 0.3
    xrectsel "%x,%y %X,%Y"
}

# stdin: xwininfo output (locale: C)
# stdout: ${width}x${height}
xwininfo_get_dimensions() {
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
            printf '%dx%d' $w $h
            return
        fi
    done
    return 1
}

# stdin: xwininfo output (locale: C)
# stdout: x1,y1 x2,y2
xwininfo_get_corners() {
    local line
    local _x _y x_ y_ b
    local n='-?[0-9]+'
    local corners="^Corners: *\\+($n)\\+($n) *-$n\\+$n *-($n)-($n) *\\+$n-$n\$"
    # Note: explicitly set IFS to ensure stripping of whitespaces
    while IFS=$' \t' read -r line; do
        if [[ $line == 'Border width: '+([0-9]) ]]; then
            b=${line#'Border width: '}
        elif [[ $line =~ $corners ]]; then
            _x=${BASH_REMATCH[1]}
            _y=${BASH_REMATCH[2]}
            x_=${BASH_REMATCH[3]}
            y_=${BASH_REMATCH[4]}
        else
            continue
        fi
        [[ -n $_x ]] || continue
        if  (( ! borderless )); then
            :
        elif [[ -n $b ]]; then
            (( _x += b )) || :
            (( _y += b )) || :
            (( x_ += b )) || :
            (( y_ += b )) || :
        else
            continue
        fi
        printf '%d,%d, %d,%d' $_x $_y $x_ $y_
        return
    done
    return 1
}

#---
# Process arguments passed to ffcast

usage() {
    cat <<EOF
$progname $progver
Usage: ${0##*/} [arguments] [ffmpeg command]

  Arguments:
    -s           select a rectangular region by mouse
    -w           select a window by mouse click
    -b           include borders of selected window
    -m           trim selected region to be mod 16
    -p           print region geometry only
    -l           list supported screencast commands
    -q           less verbose
    -v           more verbose
    -h           print this help and exit
    <geospec>    geometry specification

  If no region-selecting argument is passed, select fullscreen.
  All the arguments can be repeated, and are processed in order.
  For example, -vv is more verbose than -v.
EOF
if (( verbosity < 1 )); then
cat <<EOF

  Use \`${0##*/} -vh' for detailed help.
EOF
else
cat <<EOF
  Any number of selections are supported, e.g., -sw is valid.
  All selected regions are combined by union.

  FFmpeg command is run as given, with x11grab input options inserted,
  either replacing the first instance of '--' or, if no '--' is given,
  after 'ffmpeg'.  You can give any valid ffmpeg command line, e.g.,

    ${0##*/} -s ffmpeg -r 25 -- -f alsa -i hw:0 -vcodec libx264 cast.mkv

  <geospec> is usually not used.  It is intended as a way to use external
  region selection commands.  For example,

    ${0##*/} "\$(xrectsel '%x,%y %X,%Y')"

  <geospec> must conform to one of the following syntax:

  - x1,y1 x2,y2  (x1,y1) = (left,top) offset of the region
                 (x2,y2) = (right,bottom) offset of the region
  - wxh+x+y      (wxh) = dimensions of the region
                 (+x+y) = (+left+top) offset of the region
EOF
fi
  exit $1
}

OPTIND=1
i=0
while getopts 'bhlmpqsvw' opt; do
    case $opt in 
        h)
            usage 0
            ;;
        l)
            list_cast_cmds
            exit
            ;;
        m)
            mod16=1
            ;;
        s)
            region_select_action+='s'
            ;;
        w)
            region_select_action+='w'
            ;;
        b)
            borderless=0
            ;;
        p)
            print_geometry_only=1
            ;;
        q)
            (( verbosity-- )) || :
            ;;
        v)
            (( verbosity++ )) || :
            ;;
    esac
done
shift $(( OPTIND -1 ))

#---
# Process region geometry

declare rootw=0 rooth=0 _x=0 _y=0 x_=0 y_=0 w=0 h=0
IFS='x' read rootw rooth <<< "$(LC_ALL=C xwininfo -root | xwininfo_get_dimensions)"
# Note: this is safe because xwininfo_get_dimensions ensures that its output is
# either {int}x{int} or empty, a random string like "rootw" is impossible.
if ! (( rootw && rooth )); then
    # %d is OK even if rootw and rooth are empty, in which case they're valued 0.
    error 'invalid root window dimensions: %dx%d' "$rootw" "$rooth"
    exit 1
fi

while (( $# )); do
    if [[ $1 == $cast_cmd_pattern ]]; then
        cast_cmd=$1
        break
    fi
    # The rest are geometry specifications
    corners_list[i++]=$(parse_geospec_get_corners "$1")
    debug "corners: %s" "${corners_list[-1]}"
    shift
done

while read -n 1; do
    case $REPLY in
        's')
            corners_list[i++]=$(select_region_get_corners)
            debug "corners: %s" "${corners_list[-1]}"
            ;;
        'w')
            corners_list[i++]=$(select_window_get_corners)
            debug "corners: %s" "${corners_list[-1]}"
            ;;
    esac
done <<< "$region_select_action"

if (( i )); then
    corners=$(region_union_corners "${corners_list[@]}")
    debug "corners union all selections: %s" "${corners}"
    corners=$(region_intersect_corners "$corners" "0,0 0,0")
    debug "corners rootwin intersection: %s" "${corners}"
    IFS=' ,' read _x _y x_ y_ <<< "$corners"
fi

if ! (( w = rootw - _x - x_ )) || (( w < 0 )); then
    error 'region: invalid width: %d' "$w"
    exit 1
fi
if ! (( h = rooth - _y - y_ )) || (( h < 0 )); then
    error 'region: invalid height: %d' "$h"
    exit 1
fi

if (( print_geometry_only )); then
    printf "%dx%d+%d+%d\n" $w $h $_x $_y
    exit
fi

# x264 requires frame size divisible by 2, mod 16 is said to be optimal.
# Adapt by reducing- expanding could exceed screen edges, and would not
# be much beneficial anyway.
(( mod = mod16 ? 16 : 2 ))

w_old=$w
h_old=$h

if ! (( w = mod * (w / mod) )); then
    error 'region: width too small for mod%d: %d' $mod $w_old
    exit 1
fi
if ! (( h = mod * (h / mod) )); then
    error 'region: height too small for mod%d: %d' $mod $h_old
    exit 1
fi

if (( verbosity >= 1 )); then
    if (( w < w_old )); then
        verbose 'region: trim width from %d to %d' $w_old $w
    fi
    if (( h < h_old )); then
        verbose 'region: trim height from %d to %d' $h_old $h
    fi
fi

#---
# Validate cast command, set up x11grab options

if shift; then
    cast_cmdline=("$cast_cmd" "$@")
fi

# Important validation
case $cast_cmd in
    ffmpeg)
        x11grab_opts=(-f x11grab -s "${w}x${h}" -i "${DISPLAY}+${_x},${_y}")
        ;;
    byzanz-record)
        x11grab_opts=(--x="$_x" --y="$_y" --width="$w" --height="$h" \
            --display="$DISPLAY")
        ;;
    recordmydesktop)
        x11grab_opts=(-display "$DISPLAY")
        # As of recordMyDesktop 0.3.8.1, x- and y-offsets default to 0, but
        # -x and -y don't accept 0 as an argument. #FAIL
        (( _x )) && x11grab_opts+=(-x "$_x")
        (( _y )) && x11grab_opts+=(-y "$_y")
        x11grab_opts+=(-width "$w" -height "$h")
        ;;
    *)
        error "invalid cast command: \`%s'" "$cast_cmd"
        exit 1
        ;;
esac

readonly cast_cmd

#---
# Insert x11grab options into cast command line.

set -- "${cast_cmdline[@]}"

if ! shift; then
    error 'no cast command line specified'
    exit 1
fi

while (( $# )); do
    if [[ $1 == '--' ]]; then
        cast_args+=("${x11grab_opts[@]}")
        break
    else
        cast_args+=("$1")
        shift
    fi
done

if shift; then  # got '--'
    cast_args+=("$@")
else  # no '--', then put x11grab options at first
    cast_args=("${x11grab_opts[@]}" "${cast_args[@]}")
fi

(( verbosity >= 2 )) && set -x
"${cast_cmd}" "${cast_args[@]}"
set $x

# vim:ts=4:sw=4:et:
