# shellcheck extended-analysis=false
# --- the signs and the sizes
PANEL_APP='spark-dialog'              # the desktop window's app id: the dialog's
PANEL_SIZE=60x40                      # columns x rows of the desktop window
PANEL_COL=9                           # the section column: as wide as reminders
PANEL_IN=4                            # the glance's indent
PULSE_W=32                            # the march's place: this many cells from the right margin
panel_col() { printf "%-${PANEL_COL}s  " "$1"; }   # panel_col SECTION -> the name in its column, two cells before the text
panel_sign() { case $1 in "$PANEL_DOT"|"$PANEL_TICK") printf '%s%s%s' "${PANEL_MARK:-}" "$1" "${PANEL_UNMARK:-}" ;; "$PANEL_CROSS") printf '%s%s%s' "${PANEL_RED:-}" "$1" "${PANEL_UNMARK:-}" ;; *) printf '%s' "$1" ;; esac; }   # panel_sign SIGN -> colored: what is current in the accent, a refusal red
panel_indent() { sed "s/^/$(printf "%${PANEL_IN}s" '')/"; }   # the glance's lines, in from the edge
panel_line_sign() { case $1 in "$PANEL_DOT "*|"$PANEL_TICK "*|"$PANEL_CROSS "*) printf '%s %s' "$(panel_sign "${1%% *}")" "${1#* }" ;; *) printf '%s' "$1" ;; esac; }   # panel_line_sign LINE -> the line, its leading sign colored
TAB=$(printf '\t')
PANEL_DOT=$(printf '\342\227\217')    # U+25CF, a filled circle: in use, connected
PANEL_RING=$(printf '\342\227\213')   # U+25CB, an empty circle: available
PANEL_TICK=$(printf '\342\234\223')   # U+2713, a check: current, saved; a step done
PANEL_CROSS=$(printf '\342\234\227')  # U+2717, a cross: a step refused
PANEL_GO=$(printf '\342\226\270')     # U+25B8, a small triangle: opens something
PANEL_WARN=$(printf '\342\232\240')   # U+26A0, a warning sign: an alarm
PANEL_SEP=$(printf '\302\267')        # U+00B7, a middle dot: between facts on a line
PANEL_PROMPT=$(printf '\342\235\257') # U+276F, a heavy angle: the prompt, as starship draws it
PANEL_UP=$(printf '\342\206\221')     # U+2191, up: the arrow keys in the hint
PANEL_DOWN=$(printf '\342\206\223')   # U+2193, down
PANEL_MARK=''; PANEL_UNMARK=''; PANEL_DIM=''; PANEL_CHIP=''   # the accent, its end, the muted color, a key's ground: set at a terminal
panel_chip() { if [ -n "$PANEL_CHIP" ]; then printf '%s %s %s' "$PANEL_CHIP" "$1" "$PANEL_UNMARK"; else printf '%s' "$1"; fi; }   # panel_chip KEY -> the key on the lit ground; plain on a pipe
panel_keys() {   # panel_keys COMBO -> each key of Super+d as a chip; the combo as written on a pipe
    [ -n "$PANEL_CHIP" ] || { printf '%s' "$1"; return 0; }
    _o=''; _rest=$1
    while [ -n "$_rest" ]; do case $_rest in *+*) _k=${_rest%%+*}; _rest=${_rest#*+} ;; *) _k=$_rest; _rest='' ;; esac; _o="$_o${_o:+ }$(panel_chip "$_k")"; done
    printf '%s' "$_o"
}
panel_colors() {   # the SGRs from our own render; a pipe gets none
    # shellcheck disable=SC1091   # our own render
    [ ! -f "$CONFIG_DIR/sgr.sh" ] || . "$CONFIG_DIR/sgr.sh"
    PANEL_MARK=$(printf '\033[%sm' "${SPARK_ACCENT_SGR:-1}"); PANEL_UNMARK=$(printf '\033[0m'); PANEL_DIM=$(printf '\033[%sm' "$(hex_sgr "$PANEL_MUTED")"); PANEL_RED=$(printf '\033[31m')
    PANEL_CHIP=$(printf '\033[%sm' "$(hex_bg_sgr "$PANEL_HI")")   # a key's ground: the lit row's shade
}

# --- the sections
PANEL_ORDER="undo spark apps printers layout notes reminders window display keyboard pointer notifications out mic bt wifi storage theme bar power tools about"   # by use; undo only while there is one
PANEL_BLOCKS="lan wifi bt out mic bat clock theme"      # the bar's blocks in the bar's order, and the palette
PANEL_LOOKS="lan bat clock"                            # blocks with nothing to set: shown only when they opened the panel
panel_blocks_here() {   # -> the bar's blocks this machine has, in the bar's order
    for p in $PANEL_BLOCKS; do
        case $p in
            lan) [ -n "$(bar_wired)" ] || continue ;;
            wifi) [ -n "$(bar_wireless)" ] || continue ;;
            bt) ls -d "$BAR_SYS"/class/bluetooth/hci* >/dev/null 2>&1 || continue ;;
            out|mic) [ -n "${SND:-}" ] || continue ;;
            bat) [ -n "$(bar_power)" ] || continue ;;
        esac
        echo "$p"
    done
}
panel_sections() {   # panel_sections [FIRST] -> the sections in order, FIRST on top, absent blocks left out (on macOS: spark and layout)
    _f=${1:-glance}; _here=" $(panel_blocks_here | paste -sd ' ' -) "
    [ "$_f" = glance ] || echo "$_f"
    for s in $PANEL_ORDER; do
        [ "$s" != "$_f" ] || continue
        case $s in undo) [ -s "$PANEL_CACHE/undo" ] || continue ;; spark|layout|about) ;; tools) [ "$OS" != Darwin ] || continue ;; printers) command -v lpstat >/dev/null 2>&1 || continue ;; apps) [ "$OS" != Darwin ] || continue ;; window|bar|display|keyboard|pointer|notes|reminders|notifications|storage|power) [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] || continue ;; *) case $_here in *" $s "*) ;; *) continue ;; esac ;; esac
        echo "$s"
    done
}
panel_cost() {   # panel_cost SECTION -> instant | fast | slow: what its rows cost to know
    case $1 in wifi) echo slow ;; bt|printers|out|mic|apps|display|notifications|storage) echo fast ;; *) echo instant ;; esac
}
panel_section_ok() { case " glance chat $PANEL_ORDER $PANEL_BLOCKS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }   # panel_section_ok WORD

# --- the cache
PANEL_CACHE=$STATE_DIR/panel
panel_cache() {   # panel_cache NAME AGE CMD... -> CMD's output, from the cache while younger than AGE seconds, else fresh (and kept)
    _pc_file=$PANEL_CACHE/$1; _pc_age=$2; _pc_now=$(date +%s); shift 2   # names of their own: CMD may use the short ones
    if [ -f "$_pc_file" ] && [ $(( _pc_now - $(sed -n 1p "$_pc_file") )) -lt "$_pc_age" ] 2>/dev/null; then sed 1d "$_pc_file"; return 0; fi
    panel_dir
    _pct=$_pc_file.$$; case $TMP in */watch) _pct=${_pct}w ;; esac   # a temp of each writer's own: a provider and its watcher share a pid
    { echo "$_pc_now"; "$@"; } > "$_pct" 2>/dev/null && mv "$_pct" "$_pc_file" || { rm -f "$_pct"; "$@"; return; }
    sed 1d "$_pc_file"
}
panel_forget() { rm -f "$PANEL_CACHE/$1"; }   # panel_forget NAME -- after a change the probe must see
dirs_cached() {   # dirs_cached NAME "DIR..." CMD -> CMD's output, kept until a file under the folders changes or the folders do
    _dcf=$PANEL_CACHE/dirs.$1; _dck=''
    for _dcd in $2; do [ ! -d "$_dcd" ] || _dck="$_dck $_dcd"; done   # the folders there now are the key
    if [ -f "$_dcf" ] && IFS= read -r _dcl < "$_dcf" && [ "$_dcl" = "#$_dck" ] && [ -z "$(find $_dck -newer "$_dcf" -print 2>/dev/null | sed -n 1p)" ]; then
        sed 1d "$_dcf"; return 0
    fi
    panel_dir
    _dct=$_dcf.$$; case $TMP in */watch) _dct=${_dct}w ;; esac   # a temp of each writer's own
    { printf '#%s\n' "$_dck"; eval "$3"; } > "$_dct" 2>/dev/null && mv "$_dct" "$_dcf" || { rm -f "$_dct"; eval "$3"; return; }
    sed 1d "$_dcf"
}
# ROWS_READ: the answers' file prefix while provide_rows runs; outside a read every probe asks afresh
read_once() {   # read_once KEY PROBE [ARG...] -> PROBE's lines and status, asked once a rows read
    [ -n "${ROWS_READ:-}" ] || { shift; "$@"; return; }
    set -- "$ROWS_READ.$1" "$@"   # the answer's file first: the probe may ask another through here
    if [ ! -s "$1.rc" ]; then
        # the first to ask claims the file (noclobber); the status is written last: a file with none is not done yet
        set -C; true 2>/dev/null > "$1"; _roc=$?; set +C
        [ "$_roc" -eq 0 ] || { shift 2; "$@"; return; }
        { read_once_ask "$@"; echo "$?" >&9; } > "$1" 9> "$1.rc"
    fi
    IFS= read -r _ros < "$1.rc" || _ros=1
    while IFS= read -r _rol || [ -n "$_rol" ]; do printf '%s\n' "$_rol"; done < "$1"   # no process: the shell's own read
    return "$_ros"
}
read_once_ask() { shift 2; "$@"; }   # FILE KEY PROBE [ARG...] -> the probe asked
read_once_end() { [ -n "${ROWS_READ:-}" ] || return 0; set -- "$ROWS_READ".*; [ ! -e "$1" ] || rm -f "$@"; }   # the read's answers removed
THEME_DIRS() { printf '%s %s' "$REPO/gallery/theme" "$PALETTE_DIR"; }   # the folders the palettes and the saved themes are read from
panel_dir() { mkdir_state "$PANEL_CACHE" && chmod 700 "$PANEL_CACHE"; }   # 700: names of networks, devices and apps
panel_age() {   # panel_age NAME SECONDS -- an answer made older by that much
    _pc_file=$PANEL_CACHE/$1; [ -f "$_pc_file" ] || return 0
    { echo $(( $(sed -n 1p "$_pc_file") - $2 )); sed 1d "$_pc_file"; } > "$_pc_file.new" && mv "$_pc_file.new" "$_pc_file"
}
# the journal: `undo` = the last group's inverse steps, newest first, as SECTION<tab>ACTION ARG<tab>WORDS; `recent` = the last picks, as SECTION<tab>ACTION ARG, newest first, 5 kept
panel_group_begin() { : > "$TMP/group"; }   # one group, one undo
panel_group_end() {   # the group's inverses become the undo; none: the old undo stays
    [ -s "$TMP/group" ] || return 0
    panel_dir; awk '{ l[NR] = $0 } END { for (i = NR; i >= 1; i--) print l[i] }' "$TMP/group" > "$PANEL_CACHE/undo"
}
panel_recent_add() {   # panel_recent_add SECTION "ACTION ARG" -- the newest first, once, five kept
    panel_dir; printf '%s\t%s\n' "$1" "$2" > "$TMP/recent.new"
    [ ! -f "$PANEL_CACHE/recent" ] || grep -vxF "$(printf '%s\t%s' "$1" "$2")" "$PANEL_CACHE/recent" | head -4 >> "$TMP/recent.new"
    mv "$TMP/recent.new" "$PANEL_CACHE/recent"
}
panel_fresh() {   # panel_fresh NAME AGE -> 0 when the cache would answer without a probe
    _f=$PANEL_CACHE/$1; [ -f "$_f" ] && [ $(( $(date +%s) - $(sed -n 1p "$_f") )) -lt "$2" ] 2>/dev/null
}

# --- the pulse
# the dialog draws the same frames; silent on a pipe
pulse_frame() {   # pulse_frame KIND TICK -> the eight cells: steps and march fill the gauge pair, any other kind walks the sign on dots
    family_set "${GLYPH_FAMILY:-stone}"
    _pc=''; _pi=0
    case $1 in
        steps|march) _pk=$(( $2 % 8 + 1 ))
            while [ "$_pi" -lt 8 ]; do if [ "$_pi" -lt "$_pk" ]; then _pc=$_pc$FAM_ON; else _pc=$_pc$FAM_OFF; fi; _pi=$((_pi + 1)); done ;;
        *) _pk=$(( $2 % 14 )); [ "$_pk" -lt 8 ] || _pk=$((14 - _pk))
            while [ "$_pi" -lt 8 ]; do if [ "$_pi" = "$_pk" ]; then _pc=$_pc$FAM_THINK; else _pc=$_pc$FAM_DOT; fi; _pi=$((_pi + 1)); done ;;
    esac
    printf '%s' "$_pc"
}
pulse_line() {   # pulse_line KIND TICK SINCE [LABEL] -> one line: the mark, the cells, the seconds from 2 s, the label
    _el=$(( $(date +%s) - $3 )); _s=''; [ "$_el" -lt 2 ] || _s=" $_el s"
    printf '%s*%s %s%s%s%s%s' "$PANEL_MARK" "$PANEL_UNMARK" "$PANEL_DIM" "$(pulse_frame "$1" "$2")" "$_s" "${4:+ $4}" "$PANEL_UNMARK"
}
pulse_start() {   # pulse_start KIND [LABEL] [ROW] -- redrawn every 0.35 s on the cursor's row (or at ROW) until pulse_stop
    [ -t 1 ] || return 0
    family_set "${GLYPH_FAMILY:-stone}"   # once, before the loop
    _k=$1; _l=${2:-}; _row=${3:-}; _t0=$(date +%s)
    ( i=0; while :; do
        if [ -n "$_row" ]; then printf '\0337\033[%s;%sH%*s\033[%s;%sH%s\0338' "$_row" "${PULSE_COL:-1}" "$PULSE_W" '' "$_row" "${PULSE_COL:-1}" "$(pulse_line "$_k" "$i" "$_t0" "$_l")"   # its own cells cleared then drawn; the close glyph right of them stays
        else printf '\r\033[2K%s' "$(pulse_line "$_k" "$i" "$_t0" "$_l")"; fi
        i=$((i + 1)); sleep 0.35
      done ) &
    PULSE=$!
}
pulse_stop() {   # pulse_stop [ROW] -- ends it, row cleared
    [ -n "${PULSE:-}" ] || return 0
    kill "$PULSE" 2>/dev/null || :; wait "$PULSE" 2>/dev/null || :; PULSE=''
    [ ! -t 1 ] || { if [ -n "${1:-}" ]; then printf '\0337\033[%s;%sH%*s\0338' "$1" "${PULSE_COL:-1}" "$PULSE_W" ''; else printf '\r\033[2K'; fi; }
}

