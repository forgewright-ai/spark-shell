# shellcheck extended-analysis=false
# --- the window
# reads: BAR_FULL CONFIG_DIR OS PANEL_APP PANEL_CROSS PANEL_DOWN PANEL_IN PANEL_LOOKS PANEL_MARK PANEL_ORDER PANEL_PROMPT PANEL_SEP PANEL_TICK PANEL_UP PULSE REPO TAB THEME_KEYS TMP
panel_quit() { kill "${FZF:-}" 2>/dev/null || :; panel_tick_stop; panel_pulse_kill; stty echo 2>/dev/null || :; }
panel_tick_start() {   # panel_tick_start ROW -- the time drawn again at ROW as each minute turns, until panel_tick_stop
    [ -t 1 ] || return 0
    _row=$1
    ( while :; do
        _s=$(date +%S); _s=${_s#0}; sleep $((60 - ${_s:-0}))
        if panel_fzf_head; then panel_glance "$width" > "$TMP/glance"; panel_head > "$TMP/head"; kill -WINCH "${FZF:-0}" 2>/dev/null || exit 0   # fzf draws its first lines again
        else _r=$_row; clock_rows | while IFS= read -r _l; do printf '\0337\033[%s;%sH%s%s%s\0338' "$_r" "$((PANEL_IN + 1))" "$PANEL_MARK" "$_l" "$PANEL_UNMARK"; _r=$((_r + 1)); done; fi
      done ) &
    TICK=$!
}
panel_tick_stop() { [ -z "${TICK:-}" ] || { kill "$TICK" 2>/dev/null || :; wait "$TICK" 2>/dev/null || :; TICK=''; }; }
panel_full_aside() {   # a fullscreen window on the panel's workspace steps aside (sway draws nothing else over it); FULL_ID remembers it
    FULL_ID=$(wm_tree | jq -r --argjson p "$PPID" '[.. | objects | select(.type? == "workspace") | select([.. | objects | select(.pid? == $p)] | length > 0) | .. | objects | select((.type? == "con" or .type? == "floating_con") and (.fullscreen_mode? // 0) > 0 and .pid? != $p) | .id] | first // empty' 2>/dev/null)   # a window or a container, never the workspace (it says fullscreen too)
    [ -n "$FULL_ID" ] || return 0
    wm_on "con_id=$FULL_ID" "fullscreen disable" >/dev/null 2>&1 || { FULL_ID=''; return 0; }
    wm_on "app_id=$PANEL_APP" "focus" >/dev/null 2>&1 || :
    printf '%s\n' "$FULL_ID" > "$TMP/full.aside"; SPARK_SHELL_ASIDE=$TMP/full.aside; export SPARK_SHELL_ASIDE   # a provider reads the window as full screen, and placing it clears this
}
panel_full_back() {   # the window that stepped aside is fullscreen again, unless a pick opened or placed a window
    [ -n "${FULL_ID:-}" ] && [ ! -f "$TMP/opened" ] && [ -s "$TMP/full.aside" ] || return 0
    wm_on "con_id=$FULL_ID" "fullscreen enable" >/dev/null 2>&1 || :
}
panel_reload() {   # the settings read again: a pick may have changed them
    config_load
    for _k in $THEME_KEYS; do unset "$_k"; done   # theme none leaves no file to read: the defaults, not the old palette
    theme_load; panel_colors
}
panel_paint() {   # the panel's window takes the palette and the surface the settings say now
    osc_render plain; cat "$TMP/osc.plain"
    printf '\033]11;#%s\033\\' "$PANEL_BG"
}
panel_pulse_kill() { [ -f "$TMP/pulse.pid" ] && kill "$(cat "$TMP/pulse.pid")" 2>/dev/null; rm -f "$TMP/pulse.pid"; :; }   # a march left by a list that fzf stopped reading
panel_chat_why() {   # -> why there is no chat here, or nothing
    [ -n "$(spark_bin)" ] || echo "spark is not installed, so there is no chat (github.com/forgewright-ai/spark)"
}
panel_chat() {   # spark chat takes this window; without spark, one line that waits to be read
    _why=$(panel_chat_why)
    if [ -n "$_why" ]; then echo "$_why"; printf 'Enter closes '; IFS= read -r _ || true; return 0; fi
    # shellcheck disable=SC1091   # our own render, when there is one
    [ ! -f "$CONFIG_DIR/sgr.sh" ] || . "$CONFIG_DIR/sgr.sh"
    stty echo 2>/dev/null || :
    rm -rf "$TMP"; trap - EXIT; exec "$(spark_bin)" chat
}
panel_open_count() {   # -> how many panel windows a running sway shows (0 without sway)
    wm_session && wm_here || { echo 0; return 0; }
    _c=$(wm_tree | jq -r --arg a "$PANEL_APP" '[.. | objects | select(.app_id? == $a)] | length' 2>/dev/null || :)
    echo "${_c:-0}"   # a sway that does not answer: none
}
panel_warm() {   # panel_warm SECTION ROW -- a slow section that opened the panel is probed first, the march at ROW
    case $1 in wifi) panel_fresh wifi.scan 60 || { pulse_start march 'looking around' "$2"; wifi_scan >/dev/null; pulse_stop "$2"; } ;; esac
}
panel_stream_live() {   # panel_stream_live FIRST ROW -> the short list (rows.short), the march at ROW while slow sections look; rows.full holds every section whole
    _slow=''; : > "$TMP/rows.short"; : > "$TMP/rows.full"
    for s in $(panel_sections "$1"); do
        if [ "$s" != "$1" ] && [ "$(panel_cost "$s")" = slow ] && ! panel_fresh wifi.scan 60; then _slow="$_slow $s"; continue; fi
        panel_section_rows "$s" "$1" | tee -a "$TMP/rows.short"; panel_section_rows "$s" "$s" >> "$TMP/rows.full"
    done
    [ -n "$_slow" ] || return 0
    pulse_start march 'looking around' "$2" >/dev/tty 2>/dev/null; echo "${PULSE:-}" > "$TMP/pulse.pid"
    for s in $_slow; do panel_section_rows "$s" "$1" | tee -a "$TMP/rows.short"; panel_section_rows "$s" "$s" >> "$TMP/rows.full"; done
    pulse_stop "$2" >/dev/tty 2>/dev/null; rm -f "$TMP/pulse.pid"
}
panel_run() {   # panel_run KIND CMD... -> CMD's lines as they land, the pulse of KIND at PULSE_ROW, PULSE_COL until CMD ends; the lines in $TMP/run.out
    _kind=$1; shift
    : > "$TMP/run.out"
    "$@" > "$TMP/run.out" 2>&1 & _w=$!
    if [ -t 1 ]; then
        family_set "${GLYPH_FAMILY:-stone}"   # the pulse's family, once
        _n=0; i=0; _t0=$(date +%s); _in=$(printf "%${PANEL_IN}s" '')
        while kill -0 "$_w" 2>/dev/null; do
            _m=$(grep -c '' "$TMP/run.out" || :)
            while [ "$_n" -lt "$_m" ]; do _n=$((_n + 1)); printf '\r\033[2K%s%s\n' "$_in" "$(panel_line_sign "$(sed -n "${_n}p" "$TMP/run.out")")"; done
            printf '\0337\033[%s;%sH\033[K%s\0338' "${PULSE_ROW:-2}" "${PULSE_COL:-1}" "$(pulse_line "$_kind" "$i" "$_t0")"; i=$((i + 1)); sleep 0.35
        done
        printf '\0337\033[%s;%sH\033[K\0338' "${PULSE_ROW:-2}" "${PULSE_COL:-1}"
    fi
    wait "$_w"
}
panel_own_window() {   # the terminal is the panel's own window: foot our parent under sway, its window with the panel's app id
    wm_session && wm_here || return 1
    _c=$(cat "/proc/$PPID/comm" 2>/dev/null || ps -o comm= -p "$PPID" 2>/dev/null); [ "${_c##*/}" = foot ] || return 1
    _i=0
    while :; do   # foot maps its window a moment after it starts us: up to a second for the tree to show it
        _a=$(wm_tree | jq -r --argjson p "$PPID" '[.. | objects | select(.pid? == $p) | .app_id // empty] | first // empty' 2>/dev/null)
        [ -z "$_a" ] && [ "$_i" -lt 10 ] || break
        sleep 0.1; _i=$((_i + 1))
    done
    [ "$_a" = "$PANEL_APP" ]
}
panel_fzf_new() { fzf --version 2>/dev/null | awk '{ split($1, v, "."); exit !(v[1] > 0 || v[2] >= 54) }'; }   # fzf 0.54 or newer: the picked row lit across, no pointer cell
panel_fzf_head() { fzf --version 2>/dev/null | awk '{ split($1, v, "."); exit !(v[1] > 0 || v[2] >= 57) }'; }   # fzf 0.57 or newer: header lines, and a click on them told with its line and column
panel_fzf() {   # panel_fzf HEIGHT HEAD -- fzf over the list, HEAD lines of glance as its header; stdin the lines, stdout the query and the pick
    _c="fg:-1,bg:-1,fg+:-1,bg+:#$PANEL_HI,hl:#$HEX_ACCENT,hl+:#$HEX_ACCENT,prompt:#$HEX_ACCENT,header:#$PANEL_MUTED,gutter:-1,query:-1,scrollbar:#$HEX_MUTED"
    _h=$1
    if panel_fzf_head; then
        _again="cat $TMP/head; if [ -n {q} ]; then cat $TMP/rows.full; else cat $TMP/rows.short; fi"   # the first letter searches everything; the prompt cleared, the short list again
        set -- --highlight-line --pointer '' --marker '' --padding "1,0,0,$((PANEL_IN - 2))" --header-lines="$2" --bind "change:reload($_again)" --bind "resize:reload($_again)" \
            --bind "click-header:transform(if [ \"\$FZF_CLICK_HEADER_LINE\" = 1 ] && [ \"\$FZF_CLICK_HEADER_COLUMN\" -ge $CLOSE_COL ]; then echo abort; fi)"   # resize: the tick's SIGWINCH draws the time again; a click on the corner closes
        _h=100%
    elif panel_fzf_new; then set -- --highlight-line --pointer '' --marker '' --padding "0,0,0,$((PANEL_IN - 2))" --bind "change:reload(if [ -n {q} ]; then cat $TMP/rows.full; else cat $TMP/rows.short; fi)"   # the first letter searches everything; the prompt cleared, the short list again
    else set -- --pointer ' ' --padding "0,0,0,$((PANEL_IN - 3))"; fi
    exec fzf --delimiter "$TAB" --with-nth 1 --print-query --exact --ansi --layout=reverse-list --no-info --no-separator --color="$_c" \
        --prompt "$PANEL_PROMPT " --header "$(printf ' \n%s' "$(panel_hint)")" --height="$_h" "$@"
}
panel_head() {   # -> the lines over the list: the glance with the close glyph, the receipt when there is one, a row of air
    _in='  '; [ "${view:-home}" != about ] || _in=''   # the glance two cells in; the splash at the edge
    awk -v w="$((cols - 2 * PANEL_IN))" -v i="$_in" -v g="$PANEL_DIM$PANEL_PROMPT$PANEL_UNMARK" 'NR == 1 { n = w - 1 - length(i) - length($0); if (n < 1) n = 1; printf "%s%s%" n "s%s\n", i, $0, "", g; next } { print i $0 }' "$TMP/glance"   # the glyph in the last cell
    [ ! -s "$TMP/receipt" ] || { echo; sed "s/^/$_in/" "$TMP/receipt"; }
    echo
}
panel_loop() {   # panel_loop SECTION -- the window: the glance, the receipt and the list in fzf, again after each pick until one opens a window
    panel_colors
    ASKED=1; export ASKED   # a layout asked here: its window follows the layout, and the layout> line is not repeated
    FZF=''; PULSE=''; TICK=''; FULL_ID=''
    trap 'panel_quit; panel_full_back; rm -rf "$TMP"' EXIT
    trap 'trap "" TERM INT HUP; kill "${FZF:-}" 2>/dev/null || :; exit 0' TERM INT HUP   # the window closed under us: one signal is enough, a second must not cut the leaving short
    what=$1; said=''; own=''; view=home; [ "$what" != about ] || { view=about; what=glance; }   # about: the splash first, the list behind it
    ! panel_own_window || { own=yes; panel_full_aside; }
    while :; do
        _sz=$({ stty size </dev/tty; } 2>/dev/null || :); lines=${_sz%% *}; cols=${_sz#* }   # read each time: a font step changes the cells (tput reads 80x24 when its error stream is not the terminal)
        [ "$cols" -ge 24 ] 2>/dev/null || cols=$(tput cols 2>/dev/null || echo 76); [ "$cols" -ge 24 ] 2>/dev/null || cols=76
        [ "$lines" -ge 12 ] 2>/dev/null || lines=$(tput lines 2>/dev/null || echo 36); [ "$lines" -ge 12 ] 2>/dev/null || lines=36
        width=$((cols - PANEL_IN)); PULSE_ROW=2; PULSE_COL=$((cols - PANEL_IN - PULSE_W - 2)); [ "$PULSE_COL" -ge $((PANEL_IN + 25)) ] || PULSE_COL=$((PANEL_IN + 25))   # the text's width; the march's corner, right of the longest date and short of the close glyph
        [ -z "$own" ] || panel_paint
        CLOSE_COL=$((cols - 2 * PANEL_IN - 1))   # the close glyph's cell: a click there, or one cell before it, closes
        if [ "$view" = about ]; then panel_about $((cols - 2 * PANEL_IN + 2)) > "$TMP/glance"; else panel_glance "$width" > "$TMP/glance"; fi
        : > "$TMP/receipt"
        [ -z "$said" ] || printf '%s\n' "$said" | fold -s -w "$width" | while IFS= read -r _r; do panel_line_sign "$_r"; echo; done > "$TMP/receipt"   # the receipt: what the last pick or want did
        if panel_fzf_head; then
            panel_head > "$TMP/head"; n=$(grep -c '' "$TMP/head" || :)
            printf '\033[2J\033[H'; h=$lines
        else
            printf '\033[2J\033[H\n'   # a row of air on top, as at the sides
            panel_indent < "$TMP/glance"
            n=$(( $(grep -c '' "$TMP/glance" || :) + 1 ))
            [ ! -s "$TMP/receipt" ] || { echo; panel_indent < "$TMP/receipt"; n=$((n + 1 + $(grep -c '' "$TMP/receipt" || :))); }
            echo   # a row of air over the list
            h=$((lines - n - 2)); [ "$h" -ge 6 ] || h=6   # the list fills the rest, the hint and the prompt at the foot, a row of air under them
        fi
        [ "$view" = about ] || panel_warm "$what" "$PULSE_ROW"
        if [ "$view" = about ]; then : > "$TMP/rows.short"; : > "$TMP/rows.full"; fi
        if panel_fzf_head; then { cat "$TMP/head"; [ "$view" = about ] || panel_stream_live "$what" "$PULSE_ROW"; } | panel_fzf "$h" "$n" > "$TMP/sel" 2>/dev/null & FZF=$!
        else panel_stream_live "$what" "$PULSE_ROW" | panel_fzf "$h" 0 > "$TMP/sel" 2>/dev/null & FZF=$!; fi
        [ "$view" = about ] || panel_tick_start $(( $(grep -nF "$BAR_FULL" "$TMP/glance" | head -1 | cut -d: -f1) + 1 ))   # the time's first row: the glance's first row with a stroke, under the air
        st=0; wait "$FZF" || st=$?
        FZF=''; panel_tick_stop; panel_pulse_kill
        [ "$st" -lt 128 ] || { [ "$view" = about ] || break; view=home; said=''; continue; }   # Esc, the corner, Ctrl-C or the window closed: the splash gives the list back, the list ends the window
        q=$(sed -n 1p "$TMP/sel"); s=$(sed -n 2p "$TMP/sel")
        rm -f "$TMP/opened"; _was=$view; view=home
        if panel_fzf_head && { [ -n "$s" ] || [ -n "$q" ]; }; then   # fzf took its lines with it: the glance back under the step
            [ "$_was" = home ] || { panel_glance "$width" > "$TMP/glance"; : > "$TMP/receipt"; panel_head > "$TMP/head"; }
            printf '\033[2J\033[H\n'; sed 's/^/  /' "$TMP/head"
        fi
        if [ -n "$s" ]; then
            # shellcheck disable=SC2086   # the row's SECTION ACTION ARG, split on purpose, never a glob
            set -f; set -- ${s#*"$TAB"}; set +f; pg=$1; a=$2; shift 2
            case $pg:$a in
                spark:chat) _why=$(panel_chat_why); [ -n "$_why" ] || { panel_quit; panel_chat; }; said=$_why ;;   # exec: the conversation takes the window
                *:more) what=$pg; said='' ;;   # the section in full
                about:open) view=about; said='' ;;   # the splash, in this window
                *:show) ;;
                layout:save) printf 'a name for it: '; IFS= read -r _nm </dev/tty || _nm=''; [ -n "$_nm" ] || { said="not saved: no name"; continue; }
                   if panel_run march panel_step layout save "$_nm"; then said="$PANEL_TICK $(cat "$TMP/run.out")"; else said="$PANEL_CROSS $(cat "$TMP/run.out")"; fi ;;
                reminders:add) printf 'when and what (fri 9am call the vet): '; IFS= read -r _nm </dev/tty || _nm=''; [ -n "$_nm" ] || { said="no reminder: no words"; continue; }
                   if panel_run march panel_step reminders add "$_nm"; then said="$PANEL_TICK $(cat "$TMP/run.out")"; else said="$PANEL_CROSS $(cat "$TMP/run.out")"; fi ;;
                *) kind=march; [ "$pg" != layout ] || kind=steps
                   if step_risky "$pg" "$a" "$*" && ! step_yes "$pg $a${*:+ $*}"; then said="$PANEL_CROSS $pg $a${*:+ $*}: kept, not done (it takes a typed yes)"; continue; fi
                   panel_group_begin
                   if panel_run "$kind" panel_step "$pg" "$a" "$@"; then said="$PANEL_TICK $(cat "$TMP/run.out")"; else said="$PANEL_CROSS $(cat "$TMP/run.out")"; fi
                   panel_group_end ;;
            esac
        elif [ -n "$q" ]; then panel_group_begin; panel_run think want_play "$q" || :; panel_group_end; said=$(cat "$TMP/run.out")   # words that matched no row: a want
        fi
        if [ -f "$TMP/opened" ]; then   # a window came up: it is the receipt, and the panel goes
            printf '\033[2J\033[H\n'; printf '%s\n' "$said" | while IFS= read -r _r; do panel_line_sign "$_r"; echo; done | panel_indent
            break
        fi
        panel_reload
    done
}
panel_hint() {   # the one line under the list: the keys as keys
    if [ "${view:-home}" = about ]; then printf 'say what you would like %s %s closes' "$PANEL_SEP" "$(panel_chip Esc)"
    else printf '%s %s pick an option, or say what you would like %s %s closes' "$(panel_chip "$PANEL_UP")" "$(panel_chip "$PANEL_DOWN")" "$PANEL_SEP" "$(panel_chip Esc)"; fi
}
panel_version() { [ -z "${PANEL_VERSION_READ:-}" ] || { printf '%s\n' "$PANEL_VERSION_NOW"; return 0; }; clone_tag | sed 's/^v//'; }   # the release this copy is at, or nothing; a provider asks git once
panel_about() {   # panel_about WIDTH -> the splash: the logo, the version, the keys, the licence and the address
    _k=20; _w=$(($1 - _k)); [ "$_w" -ge 20 ] || _w=20
    _y1=''; _y2=''; _r=''; _b=''
    [ -z "$PANEL_CHIP" ] || { _y1=$(printf '\033[93m'); _y2=$(printf '\033[33m'); _r=$(printf '\033[31m'); _b=$(printf '\033[1m'); }
    echo
    printf '%s\342\226\210\342\226\200\342\226\200\342\226\200%s\n' "$_y1" "$PANEL_UNMARK"
    printf '%s\342\226\200\342\226\200\342\226\200\342\226\210%s  %s%s%s\n' "$_y2" "$PANEL_UNMARK" "$_b" "$PANEL_PROMPT" "$PANEL_UNMARK"
    printf '%s\342\226\200\342\226\200\342\226\200\342\226\200%s    %s\342\226\202%s\n' "$_r" "$PANEL_UNMARK" "$PANEL_MARK" "$PANEL_UNMARK"
    echo; printf '%sspark-shell %s%s\n' "$_b" "$(panel_version)" "$PANEL_UNMARK"; echo
    _i=0
    layout_keys | while IFS= read -r _l; do
        _i=$((_i + 1)); case $_i in 4|7|13|16) echo ;; esac   # the keys in their groups: opening, the window, moving, lock and capture, the rest
        case $_l in
            Super+*|Ctrl+*|Alt+*|Shift+*|Print\ *)
                _combo=${_l%% *}; _combo=${_combo%,}; _rest=${_l#* }
                _n=0; _c2=$_combo; while [ -n "$_c2" ]; do case $_c2 in *+*) _p=${_c2%%+*}; _c2=${_c2#*+} ;; *) _p=$_c2; _c2='' ;; esac; _n=$((_n + ${#_p} + 3)); done
                _pad=$((_k - _n + 1)); [ "$_pad" -ge 1 ] || _pad=1
                _first=1; printf '%s\n' "$_rest" | fold -s -w "$_w" | while IFS= read -r _s; do
                    if [ -n "$_first" ]; then printf '%s%*s%s\n' "$(panel_keys "$_combo")" "$_pad" '' "$_s"; _first=''; else printf '%*s%s\n' "$_k" '' "$_s"; fi
                done ;;
            *) printf '%s\n' "$_l" | fold -s -w "$1" ;;
        esac
    done
    echo; printf '%sMIT %s%s %sgithub.com/forgewright-ai/spark-shell%s\n' "$PANEL_DIM" "$PANEL_SEP" "$PANEL_UNMARK" "$PANEL_MARK" "$PANEL_UNMARK"
}

# --- the verb and the click
cmd_panel() {   # cmd_panel [SECTION] [--list | ACTION [ARG...]] | chat | "WORDS"
    config_load
    command -v jq >/dev/null 2>&1 || refuse_in panel "jq is not installed (spark-shell on)"
    [ "$OS" = Darwin ] || pm_detect
    theme_load; SND=''; [ "$OS" = Darwin ] || SND=$(snd_tool)   # on macOS the panel holds the chat and the layouts only
    case ${1:-} in
        chat) [ "$(panel_open_count)" -lt 2 ] || { wm_act "app_id=$PANEL_APP" "kill" >/dev/null 2>&1 || :; return 0; }   # the key again: a panel already open goes
              panel_chat; return ;;
        ''|--list) what=glance ;;
        -*) refuse_in panel "$1 is not an option here: a section ($(printf '%s' "$PANEL_ORDER $PANEL_LOOKS" | sed 's/ /, /g')), --list, or words for what you would like" ;;
        *) what=$1; shift; [ "$what" != look ] || what=theme   # look: a compatibility name for theme
           panel_section_ok "$what" || { bar_want "$what${1:+ $*}"; return; } ;;   # any other words: a want
    esac
    case ${1:-} in
        --list) panel_list "$what"; return 0 ;;
        '') ;;
        *) a=$1; shift; arg=$(panel_gate "$what" "$a" "$*") || { echo "spark-shell panel: $arg"; exit 1; }
           panel_group_begin
           panel_step "$what" "$a" "$arg"; st=$?   # the row's own ARG, one word: never re-split, never a glob
           panel_group_end; return "$st" ;;
    esac
    if { [ -t 0 ] || [ -n "${SPARK_SHELL_TEST_TTY:-}" ]; } && command -v fzf >/dev/null 2>&1; then   # the tests drive the window with an fzf of their own
        # the key again: this window is the second panel, so both go
        [ "$(panel_open_count)" -lt 2 ] || { wm_act "app_id=$PANEL_APP" "kill" >/dev/null 2>&1 || :; return 0; }
        panel_loop "$what"
    else panel_list "$what"; fi
}
bar_panel_open() {   # bar_panel_open [SECTION] -- home opened or focused, as the desktop key does
    python3 "$REPO/lib/home.py" open "$REPO/spark-shell" "${1:-}" >/dev/null 2>&1 </dev/null &
}

