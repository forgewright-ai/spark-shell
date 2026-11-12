# shellcheck extended-analysis=false
# --- the pad
# sets: PAD_BIN
# reads: BAR_PID DIALOG_URL OS PANEL_SEP REPO STATE_DIR TMP WM_NAME
PAD_BIN=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/spark-pad
pad_lock() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-pad.pid"; }   # the pad's lock, its pid inside
pad_state() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-pad.state"; }   # what the pad says of itself: hidden 0|1, count N
pad_release_tag() {   # -> clone_tag when it pins a pad and component/pad/ is unchanged since; false otherwise
    _pdr=$(clone_tag) || return 1
    git -C "$REPO" cat-file -e "$_pdr:component/pad/pad.env" 2>/dev/null || return 1
    git -C "$REPO" diff --quiet "$_pdr" -- component/pad 2>/dev/null || return 1
    printf '%s\n' "$_pdr"
}
pad_want_sha() {   # -> the sha256 the release tag's tree pins for this machine, or nothing
    _pdk=PAD_SHA256_$(wallpaper_target | tr 'a-z-' 'A-Z_'); _pdr=$(pad_release_tag) || return 0
    git -C "$REPO" show "$_pdr:component/pad/pad.env" 2>/dev/null | sed -n "s/^$_pdk=\([0-9a-f]\{64\}\)$/\1/p"
}
pad_ok() { [ -x "$PAD_BIN" ] && _pdw=$(pad_want_sha) && [ -n "$_pdw" ] && [ "$(sha256_of "$PAD_BIN")" = "$_pdw" ]; }   # the binary in place is the one the tree pins
pad_cmd() { if [ -n "${SPARK_SHELL_PAD:-}" ]; then [ -x "$SPARK_SHELL_PAD" ] && printf '%s' "$SPARK_SHELL_PAD"; elif pad_ok; then printf '%s' "$PAD_BIN"; else return 1; fi; }   # -> SPARK_SHELL_PAD (another build, as it is), else the pinned pad; false when none
pad_install() {   # the pad's row of on desktop: in place as pinned, or fetched for the signed tag and checked
    _pdt=$(wallpaper_target) || { skip pad "no spark-pad built for $(uname -m) yet: Super+minus brings back the window minimized last"; return 0; }
    _pdr=$(pad_release_tag) || { row todo pad "this clone is past its release: spark-pad comes with the next tag"; return 0; }
    _pdw=$(pad_want_sha); [ -n "$_pdw" ] || { skip pad "$_pdr pins no spark-pad: Super+minus brings back the window minimized last"; return 0; }
    if pad_ok; then ok pad "$PAD_BIN, the sha256 $_pdr pins"; return 0; fi
    [ "$DIALOG_URL" != none ] || { skip pad "no release to fetch it from (SPARK_SHELL_DIALOG_URL=none)"; return 0; }
    tag_signed "$_pdr" || { row todo pad "$_pdr is not signed by a key in allowed-signers: spark-pad not installed"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo pad "curl is not installed: spark-pad cannot be fetched (spark-shell on installs it)"; return 0; }
    need pad "fetch spark-pad for $_pdr and check its sha256" || return 0
    _pdf=$TMP/spark-pad
    curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$_pdf" "$DIALOG_URL/$_pdr/spark-pad-$_pdt" 2>/dev/null || { rm -f "$_pdf"; row todo pad "could not fetch spark-pad for $_pdr -- spark-shell on desktop again"; return 0; }
    [ "$(sha256_of "$_pdf")" = "$_pdw" ] || { rm -f "$_pdf"; row todo pad "the spark-pad fetched for $_pdr is not the one the tree pins: not installed"; return 0; }
    mkdir -p "$(dirname "$PAD_BIN")" && cp "$_pdf" "$PAD_BIN.new" && chmod 755 "$PAD_BIN.new" && mv "$PAD_BIN.new" "$PAD_BIN"
    row ok pad "spark-pad installed for $_pdr ($PAD_BIN), sha256 checked"
    _pad_again=''; pad_again   # a pad running the build before takes the new one
}
pad_pid() {   # -> the running pad's pid from its lock; false when none runs
    _pdl=$(pad_lock); [ -s "$_pdl" ] || return 1
    _pdp=''; read -r _pdp 2>/dev/null < "$_pdl" || [ -n "$_pdp" ] || return 1   # a pid with no new line after it is read too
    case $_pdp in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_pdp" 2>/dev/null || return 1
    [ ! -r "/proc/$_pdp/cmdline" ] || tr '\0' ' ' < "/proc/$_pdp/cmdline" | grep -q 'spark-pad' || return 1
    printf '%s\n' "$_pdp"
}
pad_hidden() { pad_pid >/dev/null || return 0; grep -qx 'hidden 1' "$(pad_state)" 2>/dev/null; }   # 0 when the pad is hidden, or none runs
pad_list() {   # pad_list TREEFILE -> the windows on the pad, oldest first: ID<tab>APP<tab>TITLE
    jq -r '.. | objects | select(.type == "workspace" and .name == "__i3_scratch") | .floating_nodes[]?
        | select(any((.marks // [])[]; startswith("_spark-shell.min.")))
        | "\(.id)\t\(.app_id // .window_properties.class // "a window")\t\(.name // "")"' "$1" 2>/dev/null || :
}
pad_count() { wm_session || { echo 0; return; }; wm_tree | jq '[.. | objects | select(.type == "workspace" and .name == "__i3_scratch") | .floating_nodes[]? | select(any((.marks // [])[]; startswith("_spark-shell.min.")))] | length' 2>/dev/null || echo 0; }   # -> how many windows wait on the pad
pad_run() {   # pad_run [--keys] -- spark-pad started in its own session; false when none can run here
    _pdc=$(pad_cmd) || return 1
    theme_load 2>/dev/null || :
    _pdlog=${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-pad.log
    mkdir_private "$STATE_DIR"
    (
        # PAD_BAND on|off, PAD_BAND_HEX its color; PAD_GAP the outer gap; PAD_VIEW icons|titles; PAD_HEIGHT 0 as many as needed
        SPARK_SHELL=$REPO/spark-shell PAD_FG=$HEX_FG PAD_ACCENT=$HEX_ACCENT PAD_MUTED=$PANEL_MUTED PAD_TITLE_MUTED=$HEX_MUTED PAD_LOW=$PANEL_LOW PAD_SURFACE=$PANEL_BG PAD_LIT=$PANEL_HI PAD_BAND_HEX=$PANEL_BAND
        PAD_ALPHA=$ALPHA PAD_FONT=$(bar_line_font) PAD_PLACE=$PAD_PLACE PAD_WIDTH=$PAD_WIDTH PAD_SIDE_WIDTH=$PAD_SIDE_WIDTH PAD_HEIGHT=${PAD_HEIGHT:-0} PAD_BAR=$(bar_place)
        PAD_BAND=${PAD_BAND:-off} PAD_VIEW=${PAD_VIEW:-icons} PAD_GAP=${GAPS_OUTER:-} PAD_LOCK=$(pad_lock) PAD_STATE=$(pad_state) PAD_BAR_PID=$BAR_PID
        export SPARK_SHELL PAD_FG PAD_ACCENT PAD_MUTED PAD_TITLE_MUTED PAD_LOW PAD_SURFACE PAD_LIT PAD_BAND_HEX PAD_ALPHA PAD_FONT PAD_PLACE PAD_WIDTH PAD_SIDE_WIDTH PAD_HEIGHT PAD_BAR PAD_BAND PAD_VIEW PAD_GAP PAD_LOCK PAD_STATE PAD_BAR_PID
        if command -v setsid >/dev/null 2>&1; then setsid "$_pdc" "$@" </dev/null >/dev/null 2>"$_pdlog" &
        else ( trap '' HUP; exec "$_pdc" "$@" ) </dev/null >/dev/null 2>"$_pdlog" & fi
    )
}
pad_wake() { pad_pid >/dev/null || pad_run 2>/dev/null || :; }   # the pad up when it is not; never waited for
pad_again() {   # a running pad restarted, so it takes a new look or bar place; once a run
    [ -z "${_pad_again:-}" ] || return 0; _pad_again=1
    _pdo=$(pad_pid) || return 0
    kill "$_pdo" 2>/dev/null || :
    _pdi=0; while [ "$_pdi" -lt 20 ] && kill -0 "$_pdo" 2>/dev/null; do sleep 0.1; _pdi=$((_pdi + 1)); done
    pad_run 2>/dev/null || :
}
pad_place_words() {   # pad_place_words PLACE -> where it sits, in words
    case $1 in
        free\ *) echo 'where you left it' ;;
        *\ center) echo "at the ${1% *} edge, in the middle" ;;
        top\ start|bottom\ start) echo "at the ${1% *} edge, at its left end" ;;
        top\ end|bottom\ end) echo "at the ${1% *} edge, at its right end" ;;
        *\ start) echo "at the ${1% *} edge, at its top" ;;
        *\ end) echo "at the ${1% *} edge, at its bottom" ;;
        *) echo "at the ${1% *} edge" ;;
    esac
}
pad_band_words() { if [ "$1" = on ]; then echo "the band under its handle says pad and how many wait"; else echo "the handle alone across its top"; fi; }   # pad_band_words on|off -> what the pad shows, in words
pad_view_words() { if [ "$1" = titles ]; then echo "a slot a window, its icon, its app and its title"; else echo "one icon a window, its title beside it on hover"; fi; }   # pad_view_words icons|titles -> how the pad shows its windows, in words
layout_pad() {   # layout_pad [keys|toggle|place PLACE WIDTH SIDE [HEIGHT]|band [on|off]|view [icons|titles]|start|again] -- the pad
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own Dock"
    case ${1:-} in
        place) shift
            # a pad sends three; the height in the config stays then
            case $# in 3|4) ;; *) refuse "pad place takes PLACE WIDTH SIDE [HEIGHT]: \"bottom center\" 0 36 0" ;; esac
            pad_place_ok "$1" || refuse "pad place: top, bottom, left or right and center, start, end or pixels along that edge, or free X Y"
            pad_width_ok "$2" 0 || refuse "pad place: the width is pixels, 0 to 9999 (0: as wide as the screen allows)"
            pad_width_ok "$3" 36 || refuse "pad place: the width at a side is pixels, 36 to 9999"
            [ "$#" = 3 ] || pad_width_ok "$4" 0 || refuse "pad place: the height is pixels, 0 to 9999 (0: as many rows as needed)"
            config_set PAD_PLACE "$1" >/dev/null; config_set PAD_WIDTH "$2" >/dev/null; config_set PAD_SIDE_WIDTH "$3" >/dev/null
            [ "$#" = 3 ] || config_set PAD_HEIGHT "$4" >/dev/null
            echo "the pad sits $(pad_place_words "$1")"; return ;;
        band) [ "$#" -le 2 ] || refuse "pad band takes on or off"
            case ${2:-} in
                '') echo "pad band $PAD_BAND $PANEL_SEP $(pad_band_words "$PAD_BAND")"; return ;;
                on|off) ;;
                *) refuse "pad band takes on or off" ;;
            esac
            [ "$2" != "$PAD_BAND" ] || refuse "the pad's band is $2 already"
            config_set PAD_BAND "$2" >/dev/null; PAD_BAND=$2; export PAD_BAND
            pad_again   # drawn again, with the band or without it
            echo "pad band $2 $PANEL_SEP $(pad_band_words "$2")"; return ;;
        view) [ "$#" -le 2 ] || refuse "pad view takes icons or titles"   # PAD_VIEW
            case ${2:-} in
                '') echo "pad view $PAD_VIEW $PANEL_SEP $(pad_view_words "$PAD_VIEW")"; return ;;
                icons|titles) ;;
                *) refuse "pad view takes icons or titles" ;;
            esac
            [ "$2" != "$PAD_VIEW" ] || refuse "the pad's view is $2 already"
            config_set PAD_VIEW "$2" >/dev/null; PAD_VIEW=$2; export PAD_VIEW
            pad_again   # drawn again in that view
            echo "pad view $2 $PANEL_SEP $(pad_view_words "$2")"; return ;;
        ''|keys|toggle|start|again) ;;
        *) refuse "pad takes keys, toggle, place PLACE WIDTH SIDE [HEIGHT], band on|off or view icons|titles" ;;
    esac
    [ "${1:-}" != again ] || { pad_again; return 0; }
    wm_up || { [ "${1:-}" != start ] || return 0; refuse "the pad is the desktop's: run it inside it"; }
    wm_tree > "$TMP/tree" || refuse "$WM_NAME did not answer"
    pad_list "$TMP/tree" > "$TMP/pad"
    _pdn=$(grep -c '' "$TMP/pad" || :)
    case ${1:-} in
        '') if [ "$_pdn" = 0 ]; then echo "no window is on the pad"
            else _pdw=window; [ "$_pdn" = 1 ] || _pdw=windows
                echo "the pad has $_pdn $_pdw: $(cut -f2 "$TMP/pad" | paste -sd, - | sed 's/,/, /g')"; fi ;;
        start) pad_wake ;;   # resident: it draws each window's glyphs and keeps the focus order
        keys) [ "$_pdn" != 0 ] || refuse "no window is on the pad"
            if _pdp=$(pad_pid); then kill -USR1 "$_pdp" 2>/dev/null || :
            elif ! pad_run --keys; then layout_window restore; return; fi   # no pad here: the window minimized last comes back
            echo "the pad has the keys: Enter brings the window back, Esc leaves" ;;
        toggle) [ "$_pdn" != 0 ] || refuse "no window is on the pad"
            if _pdp=$(pad_pid); then
                if pad_hidden; then _pds='back in sight'; else _pds=hidden; fi
                kill -USR2 "$_pdp" 2>/dev/null || :
            else pad_run || refuse "spark-pad is not installed -- spark-shell on desktop"; _pds='back in sight'; fi
            echo "the pad is $_pds" ;;
    esac
}
