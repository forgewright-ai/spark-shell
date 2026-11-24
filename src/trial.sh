# shellcheck extended-analysis=false
# --- a screen being tried: a resolution, a scale or a turn the dialog asked for, live at once and written only when it is
# kept. A timer in a session of its own puts back what was there, whatever ends the dialog or its provider; screens.conf is
# left alone until then, so a crash or a logout leaves the next login as it was
# sets: TRIAL_SECONDS
# reads: REPO TAB TMP US WM_NAME
TRIAL_SECONDS=15   # before a change nobody kept goes back
trial_seconds() { case ${SPARK_SHELL_TRIAL_SECONDS:-} in [1-9]|[1-5][0-9]|60) printf '%s' "$SPARK_SHELL_TRIAL_SECONDS" ;; *) printf '%s' "$TRIAL_SECONDS" ;; esac; }   # the variable is the suite's alone
# the state, one file a session: KEY US VALUES a line, every value checked or a number before it is written
#   token       this trial's own word: the timer acts on its own trial alone
#   pid         the timer
#   port, ref   the screen tried, and the word its lines go by
#   tried, said what changed, in the compositor's words and as a person reads it
#   undo        the step that takes it back once kept
#   back        what the compositor is told to take it back now
#   was         PORT REF MODE SCALE TURN X Y of each screen on, before
#   keep        a line for screens.conf: screen REF WORDS SIDE OTHER, or place REF X Y
trial_file() {   # -> this session's state in the runtime folder; false with none
    [ -n "${XDG_RUNTIME_DIR:-}" ] || return 1
    eval "_tfs=\${$(wm_env_name):-}"
    printf '%s/spark-shell/trial.%s' "$XDG_RUNTIME_DIR" "$(printf '%s' "$_tfs" | cksum | cut -d' ' -f1)"
}
trial_get() { awk -F '\037' -v k="$1" '$1 == k { print $2; exit }' "$_trf" 2>/dev/null || :; }   # trial_get KEY -> its first value
trial_put() { ( umask 077; mkdir -p "${_trf%/*}" && _tpn=$(mktemp "$_trf.XXXXXX") && cat > "$_tpn" && mv -f "$_tpn" "$_trf" ); }   # stdin -> the state, whole, 0600
trial_locked() (   # trial_locked COMMAND... -- one at a time, _trf the state: the dialog's calls and the timer
    _trf=$(trial_file) || { echo 'a screen is tried with XDG_RUNTIME_DIR set, and it is not here'; exit 1; }
    ( umask 077; mkdir -p "${_trf%/*}" ) 2>/dev/null || { echo "nothing can be noted in $XDG_RUNTIME_DIR, so no change is tried"; exit 1; }
    _tln=0
    until lock_take "$_trf.lock"; do
        _tln=$((_tln + 1)); [ "$_tln" -ne 80 ] || lock_drop "$_trf.lock"   # eight seconds: its holder died
        [ "$_tln" -lt 160 ] || { echo 'another change is under way: try again'; exit 1; }
        sleep 0.1
    done
    trap 'lock_drop "$_trf.lock"' EXIT; trap 'exit 143' INT TERM HUP
    "$@"
)
trial_start() {   # trial_start PORT scale|mode|transform VALUE -- the change at once; it goes back unless kept. What the dialog shows is $TMP/screen.trial
    [ "$(screen_find "$1" | cut -f3)" = on ] || { layout_screen "$@"; return; }   # a screen off shows nothing to judge: as any other change
    wm_up || refuse "changes the desktop's screens: run it inside it"
    trial_locked trial_apply "$@"
}
trial_apply() {   # trial_apply PORT KIND VALUE -- under the lock
    _tar=$(screen_find "$1"); _tap=$(printf '%s' "$_tar" | cut -f1)
    _tai=$(screen_ref "$(printf '%s' "$_tar" | cut -f2)" "$_tap") || refuse "that screen has no name $WM_NAME can be told"
    screen_setting "$_tap" "$2" "$3"   # _cmd
    if trial_in_use "$_tar" "$2" "$3"; then printf 'null' > "$TMP/screen.undo"; echo "$_tap is $(trial_words "$2" "$3") already"; return 0; fi
    case $2 in
        mode) _tab=$(printf '%s' "$_tar" | cut -f4); [ -n "$_tab" ] || refuse "the resolution $_tap has now is not known, so none is tried" ;;
        scale) _tab=$(printf '%s' "$_tar" | cut -f5) ;;
        *) _tab=$(printf '%s' "$_tar" | cut -f11); : "${_tab:=normal}" ;;
    esac
    [ ! -s "$_trf" ] || trial_write >/dev/null   # a second change keeps the first: the person has seen it
    _tat=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n'); _tas=$(trial_words "$2" "$3")
    { printf '%s\n' "token$US$_tat" "port$US$_tap" "ref$US$_tai" "tried$US$_cmd" "said$US$_tas" "undo$US$2 $_tap $2=$_tab" "back$US$2 $_tab"; trial_was; } > "$TMP/trial"
    # the state, then the timer, then the change: cut short anywhere, what was there comes back
    trial_put < "$TMP/trial" 2>/dev/null || refuse "nothing can be noted in $XDG_RUNTIME_DIR, so no change is tried"
    trial_timer_start "$_tat"; printf '%s\n' "pid$US$_tti" >> "$TMP/trial"; trial_put < "$TMP/trial" || :
    screen_send "$_tai" "$_tap" "$_cmd" || { trial_end; refuse "$WM_NAME refused: output $_tap $_cmd"; }
    SCREEN_TRIED=$TMP/trial.keep; : > "$SCREEN_TRIED"
    screen_save "$_tai" "$_cmd"
    [ "$2" != transform ] || screen_beside_again "$_tai"   # its width changed: the screens beside it move, live alone
    screen_origin >/dev/null
    SCREEN_TRIED=''
    [ "$(trial_get token)" != "$_tat" ] || cat "$TMP/trial" "$TMP/trial.keep" | trial_put || :
    layout_refit_soon screen
    jq -cn --arg said "$_tas" --argjson s "$(trial_seconds)" --arg n "$_tap" \
        '{said: $said, seconds: $s, keep: {name: "display_keep", arguments: {screen: $n}}, back: {name: "display_back", arguments: {screen: $n}}}' > "$TMP/screen.trial"
    echo "$_tap $_tas, back in $(trial_seconds) seconds unless kept"
}
trial_in_use() {   # trial_in_use ROW KIND VALUE -> 0 when the screen has it already
    case $2 in
        mode) _tiu=$(printf '%s' "$1" | cut -f4); [ "$_tiu" = "$3" ] || [ "${_tiu%%@*}" = "$3" ] ;;
        scale) awk -v a="$(printf '%s' "$1" | cut -f5)" -v b="$3" 'BEGIN { d = a - b; exit !(d < 0.005 && d > -0.005) }' ;;   # the compositor rounds a scale to a 120th
        *) _tiu=$(printf '%s' "$1" | cut -f11); [ "${_tiu:-normal}" = "$3" ] ;;
    esac
}
trial_words() {   # trial_words KIND VALUE -> 1920x1080 60 Hz, scale 150%, turned right
    case $1:$2 in
        mode:*@*Hz) _twr=${2#*@}; printf '%s %s Hz' "${2%%@*}" "$(awk -v r="${_twr%Hz}" 'BEGIN { s = sprintf("%.2f", r); sub(/[.]?0+$/, "", s); print s }')" ;;
        mode:*) printf '%s' "$2" ;;
        scale:*) awk -v s="$2" 'BEGIN { printf "scale %d%%", s * 100 + 0.5 }' ;;
        transform:90) printf 'turned right' ;;
        transform:180) printf 'upside down' ;;
        transform:270) printf 'turned left' ;;
        *) printf 'upright' ;;
    esac
}
trial_was() {   # -> a was line a screen on
    screen_rows | awk -F '\t' -v OFS='\t' '$3 == "on" { print $1, $2, ($4 == "" ? "-" : $4), $5, ($11 == "" ? "normal" : $11), $6, $7 }' \
        | while IFS="$TAB" read -r _twn _twi _twm _tws _twt _twx _twy; do
            _twi=$(screen_ref "$_twi" "$_twn") || continue
            printf '%s\n' "was$US$_twn$US$_twi$US$_twm$US$_tws$US$_twt$US$_twx$US$_twy"
        done
}
trial_timer_start() {   # trial_timer_start TOKEN -- _tti its pid: its own session, no wire of the provider's held open
    set -- sh "$REPO/spark-shell" desktop --trial "$1" "$(trial_seconds)"
    if command -v setsid >/dev/null 2>&1; then setsid "$@" </dev/null >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
    else ( trap '' HUP; exec "$@" ) </dev/null >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- & fi
    _tti=$!
}
trial_timer() {   # trial_timer TOKEN SECONDS -- the timer itself: what was there back, when its trial still stands
    case ${1:-} in ''|*[!0-9a-f]*) return 1 ;; esac
    case ${2:-} in ''|*[!0-9]*) return 1 ;; esac
    trap '' HUP
    sleep "$2" & _tts=$!
    trap 'kill "$_tts" 2>/dev/null || :; exit 143' TERM
    wait "$_tts" || :
    trial_locked trial_over "$1" || :
}
trial_over() { [ "$(trial_get token)" != "$1" ] || trial_restore; }   # trial_over TOKEN -- under the lock
trial_restore() {   # under the lock: what was there before, live, then the places of what moved with it; the state gone
    _trp=$(trial_get port)
    screen_send "$(trial_get ref)" "$_trp" "$(trial_get back)" || :
    for _tro in settings places; do   # the places last, by what the compositor says after the rest
        screen_rows > "$TMP/trial.now"
        while IFS="$US" read -r _trk _trn _tri _trm _trs _trt _trx _try; do
            [ "$_trk" = was ] || continue
            _trr=$(awk -F '\t' -v n="$_trn" '$1 == n && $3 == "on"' "$TMP/trial.now")
            [ -n "$_trr" ] || [ ! -s "$TMP/trial.now" ] || continue   # unplugged meanwhile, or off
            if [ "$_tro" = places ]; then
                [ "$(printf '%s' "$_trr" | cut -f6,7)" = "$_trx$TAB$_try" ] || screen_send "$_tri" "$_trn" "position $_trx $_try" || :
            elif [ "$_trn" = "$_trp" ] && [ -n "$_trr" ]; then
                [ "$_trm" = - ] || trial_in_use "$_trr" mode "$_trm" || screen_send "$_tri" "$_trn" "mode $_trm" || :
                trial_in_use "$_trr" scale "$_trs" || screen_send "$_tri" "$_trn" "scale $_trs" || :
                trial_in_use "$_trr" transform "$_trt" || screen_send "$_tri" "$_trn" "transform $_trt" || :
            fi
        done < "$_trf"
    done
    trial_end
    layout_refit_soon screen
}
trial_write() {   # under the lock: what is tried into screens.conf, as the change made another way writes it; the state gone
    while IFS="$US" read -r _twk _twa _twb _twc _twd _twe; do
        case $_twk:$_twa in keep:screen) screen_save "$_twb" "$_twc" "$_twd" "$_twe" ;; keep:place) screen_place_save "$_twb" "$_twc" "$_twd" ;; esac
    done < "$_trf"
    trial_end
    login_screens_follow
    layout_refit_soon screen
}
trial_again() {   # under the lock: what is tried live again, where the compositor read its config anew meanwhile and put the old back
    # shellcheck disable=SC2046   # a kind and its value, split on purpose
    ! trial_in_use "$(screen_find "$(trial_get port)")" $(trial_get tried) || return 0
    while IFS="$US" read -r _tak _taa _tab _tac _tad _; do
        case $_tak:$_taa in keep:screen) screen_send "$_tab" "$_tab" "$_tac" || : ;; keep:place) screen_send "$_tab" "$_tab" "position $_tac $_tad" || : ;; esac
    done < "$_trf"
}
trial_end() {   # under the lock: the state gone, its timer with it
    _tep=$(trial_get pid); _tet=$(trial_get token); rm -f "$_trf"
    case $_tep in ''|*[!0-9]*|"$$") return 0 ;; esac   # never itself
    if { tr '\0' '\n' < "/proc/$_tep/cmdline"; } 2>/dev/null | grep -qxF -- "$_tet"; then kill "$_tep" 2>/dev/null || :; fi   # this trial's, by its token; with no /proc it ends by itself and finds nothing
    return 0
}
trial_settle() {   # a change made another way while one is tried keeps that one first
    _tsf=$(trial_file) && [ -s "$_tsf" ] || return 0
    trial_locked trial_settle_now >/dev/null || :
}
trial_settle_now() { [ ! -s "$_trf" ] || trial_write; }
trial_answer() {   # trial_answer keep|back PORT -- the person's word on the one being tried
    trial_locked trial_answer_now "$@"
}
trial_answer_now() {
    [ -s "$_trf" ] && [ "$(trial_get port)" = "$2" ] || { echo "nothing is being tried on $2: it was kept, or it went back"; return 1; }
    if [ "$1" = back ]; then trial_restore; echo "$2 is back as it was"; return 0; fi
    _tns=$(trial_get said); _tnu=$(trial_get undo)
    trial_again
    trial_write > "$TMP/trial.said"
    if [ -n "$_tnu" ] && action_tool display "$_tnu"; then tool_call_json "$_tool" "$_tv" > "$TMP/screen.undo"; fi
    echo "$2 $_tns kept"
    cat "$TMP/trial.said"
}
