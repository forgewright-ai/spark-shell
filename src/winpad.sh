# shellcheck extended-analysis=false
# --- winpad
# sets: WINPAD_BIN WINPAD_KEEP
# reads: BAR_PID DIALOG_URL OS PANEL_SEP REPO STATE_DIR TERM_APP_PREFIX TERM_NAME TMP WM_NAME
WINPAD_BIN=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/spark-winpad
winpad_lock() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-winpad.pid"; }   # the pad's lock, its pid inside
winpad_state() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-winpad.state"; }   # what the pad says of itself: hidden 0|1, count N
winpad_release_tag() {   # -> clone_tag when it pins a pad and component/winpad/ is unchanged since; false otherwise
    _pdr=$(clone_tag) || return 1
    git -C "$REPO" cat-file -e "$_pdr:component/winpad/winpad.env" 2>/dev/null || return 1
    git -C "$REPO" diff --quiet "$_pdr" -- component/winpad 2>/dev/null || return 1
    printf '%s\n' "$_pdr"
}
winpad_want_sha() {   # -> the sha256 the release tag's tree pins for this machine, or nothing
    _pdk=WINPAD_SHA256_$(wallpaper_target | tr 'a-z-' 'A-Z_'); _pdr=$(winpad_release_tag) || return 0
    git -C "$REPO" show "$_pdr:component/winpad/winpad.env" 2>/dev/null | sed -n "s/^$_pdk=\([0-9a-f]\{64\}\)$/\1/p"
}
winpad_ok() { [ -x "$WINPAD_BIN" ] && _pdw=$(winpad_want_sha) && [ -n "$_pdw" ] && [ "$(sha256_of "$WINPAD_BIN")" = "$_pdw" ]; }   # the binary in place is the one the tree pins
winpad_cmd() { if [ -n "${SPARK_SHELL_WINPAD:-}" ]; then [ -x "$SPARK_SHELL_WINPAD" ] && printf '%s' "$SPARK_SHELL_WINPAD"; elif winpad_ok; then printf '%s' "$WINPAD_BIN"; else return 1; fi; }   # -> SPARK_SHELL_WINPAD (another build, as it is), else the pinned pad; false when none
winpad_here() { winpad_cmd >/dev/null 2>&1; }   # a winpad can run on this machine
winpad_mic() { ! winpad_here || ! voice_here || printf '%s' " <span foreground='#$HEX_ANSI_1'>&#x25CB;</span> "; }   # -> the mic at rest on a band, red in every palette; the pad takes the title over from here, with the meter at its right end
winpad_buttons() { ! winpad_here || printf '%s' ' &#x2715;  &#x25BD;  &#x25A1; '; }   # -> close, minimize, fill, the start of every title, as pango character references so the render stays ASCII (the component's GLYPH_REFS); nothing where no winpad can run: no button is drawn that does not click
winpad_install() {   # the pad's row of on desktop: in place as pinned, or fetched for the signed tag and checked
    _pdt=$(wallpaper_target) || { skip pad "no spark-winpad built for $(uname -m) yet: Super+minus brings back the window minimized last"; return 0; }
    _pdr=$(winpad_release_tag) || { row todo pad "this clone is past its release: spark-winpad comes with the next tag"; return 0; }
    _pdw=$(winpad_want_sha); [ -n "$_pdw" ] || { skip pad "$_pdr pins no spark-winpad: Super+minus brings back the window minimized last"; return 0; }
    if winpad_ok; then ok pad "$WINPAD_BIN, the sha256 $_pdr pins"; return 0; fi
    [ "$DIALOG_URL" != none ] || { skip pad "no release to fetch it from (SPARK_SHELL_DIALOG_URL=none)"; return 0; }
    tag_signed "$_pdr" || { row todo pad "$_pdr is not signed by a key in allowed-signers: spark-winpad not installed"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo pad "curl is not installed: spark-winpad cannot be fetched (spark-shell on installs it)"; return 0; }
    need pad "fetch spark-winpad for $_pdr and check its sha256" || return 0
    _pdf=$TMP/spark-winpad
    curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$_pdf" "$DIALOG_URL/$_pdr/spark-winpad-$_pdt" 2>/dev/null || { rm -f "$_pdf"; row todo pad "could not fetch spark-winpad for $_pdr -- spark-shell on desktop again"; return 0; }
    [ "$(sha256_of "$_pdf")" = "$_pdw" ] || { rm -f "$_pdf"; row todo pad "the spark-winpad fetched for $_pdr is not the one the tree pins: not installed"; return 0; }
    mkdir -p "$(dirname "$WINPAD_BIN")" && cp "$_pdf" "$WINPAD_BIN.new" && chmod 755 "$WINPAD_BIN.new" && mv "$WINPAD_BIN.new" "$WINPAD_BIN"
    rm -f "${WINPAD_BIN%/*}/spark-pad"   # the binary under its name through v0.141
    row ok pad "spark-winpad installed for $_pdr ($WINPAD_BIN), sha256 checked"
    _winpad_again=''; winpad_again   # a pad running the build before takes the new one
    for _pdx in pid state log; do rm -f "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-pad.$_pdx"; done   # spark-pad's, through v0.141
}
winpad_session() {   # on desktop's last pad row: the pad runs for the session (v0.140), and sway starts it at login alone, so a session that began before, as an update's, has none until this starts it, through sway, as login does
    wm_up && winpad_cmd >/dev/null || return 0
    ! winpad_pid >/dev/null || return 0
    [ -z "${_winpad_started:-}" ] || return 0   # this run started one already (winpad_again), its lock not taken yet
    need pad "start the pad for this session, through sway as at login" || return 0
    wm_exec "$REPO/spark-shell desktop pad start" >/dev/null 2>&1 || { row todo pad "sway did not start the pad -- it starts at the next login"; return 0; }
    ok pad "the pad runs for this session now"
}
winpad_pid_in() {   # winpad_pid_in LOCK -> the pid in LOCK when it runs; false otherwise
    _pdl=$1; [ -s "$_pdl" ] || return 1
    _pdp=''; read -r _pdp 2>/dev/null < "$_pdl" || [ -n "$_pdp" ] || return 1   # a pid with no new line after it is read too
    case $_pdp in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_pdp" 2>/dev/null || return 1
    [ ! -r "/proc/$_pdp/cmdline" ] || tr '\0' ' ' < "/proc/$_pdp/cmdline" | grep -q 'spark-\(win\)\{0,1\}pad' || return 1
    printf '%s\n' "$_pdp"
}
winpad_pid() { winpad_pid_in "$(winpad_lock)" || winpad_pid_in "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-pad.pid"; }   # -> the running winpad's pid; the second lock is spark-pad's, its name through v0.141
winpad_hidden() { winpad_pid >/dev/null || return 0; grep -qx 'hidden 1' "$(winpad_state)" 2>/dev/null; }   # 0 when the pad is hidden, or none runs
winpad_list() {   # winpad_list TREEFILE -> the windows on the pad, oldest first: ID<tab>APP<tab>TITLE
    jq -r '.. | objects | select(.type == "workspace" and .name == "__i3_scratch") | .floating_nodes[]?
        | select(any((.marks // [])[]; startswith("_spark-shell.min.")))
        | "\(.id)\t\(.app_id // .window_properties.class // "a window")\t\(.name // "")"' "$1" 2>/dev/null || :
}
winpad_count() { wm_session || { echo 0; return; }; wm_tree | jq '[.. | objects | select(.type == "workspace" and .name == "__i3_scratch") | .floating_nodes[]? | select(any((.marks // [])[]; startswith("_spark-shell.min.")))] | length' 2>/dev/null || echo 0; }   # -> how many windows wait on the pad
# the keeper: winpad again when it ends by itself, a crash; a stop on purpose (0) stays a stop, and so does a session
# that is gone or a winpad that ends five times within a minute of its start
WINPAD_KEEP='n=0; while :; do t=$(date +%s); "$0" "$@"; rc=$?; case $rc in 0|2) break ;; esac; [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY:-none}" ] || break; [ $(( $(date +%s) - t )) -lt 60 ] || n=0; n=$((n + 1)); [ "$n" -le 5 ] || break; echo "spark-winpad ended ($rc): started again" >&2; sleep 1; done'
winpad_run() {   # winpad_run [--keys] -- spark-winpad started in its own session, under its keeper; false when none can run here
    _pdc=$(winpad_cmd) || return 1
    theme_load 2>/dev/null || :
    _pdlog=${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-winpad.log
    mkdir_private "$STATE_DIR"
    (
        # WINPAD_BAND on|off, WINPAD_BAND_HEX its color; WINPAD_GAP the outer gap; WINPAD_VIEW icons|titles; WINPAD_HEIGHT 0 as many as needed
        SPARK_SHELL=$REPO/spark-shell WINPAD_FG=$HEX_FG WINPAD_ACCENT=$HEX_ACCENT WINPAD_MUTED=$PANEL_MUTED WINPAD_GROUND=$HEX_BG WINPAD_CLOSE=$HEX_ANSI_1 WINPAD_MIN=$HEX_ANSI_3 WINPAD_FILL=$HEX_ANSI_2 WINPAD_SURFACE=$PANEL_BG WINPAD_LIT=$PANEL_HI WINPAD_BAND_HEX=$PANEL_BAND
        WINPAD_ALPHA=$ALPHA WINPAD_FONT=$(bar_line_font) WINPAD_PLACE=$WINPAD_PLACE WINPAD_WIDTH=$WINPAD_WIDTH WINPAD_SIDE_WIDTH=$WINPAD_SIDE_WIDTH WINPAD_HEIGHT=${WINPAD_HEIGHT:-0} WINPAD_BAR=$(bar_place)
        WINPAD_VOICE=$(voice_here && echo yes || echo no) WINPAD_VOICE_STATE=$(voice_state)
        WINPAD_TERM=$TERM_NAME WINPAD_TERM_ALSO=$TERM_APP_PREFIX WINPAD_TITLE=$BAND_TITLE WINPAD_TERM_TITLE=$BAND_TERM_TITLE WINPAD_BAND=${WINPAD_BAND:-off} WINPAD_VIEW=${WINPAD_VIEW:-icons} WINPAD_GAP=${GAPS_OUTER:-} WINPAD_LOCK=$(winpad_lock) WINPAD_STATE=$(winpad_state) WINPAD_BAR_PID=$BAR_PID
        export SPARK_SHELL WINPAD_VOICE WINPAD_VOICE_STATE WINPAD_TERM_ALSO WINPAD_FG WINPAD_ACCENT WINPAD_MUTED WINPAD_GROUND WINPAD_CLOSE WINPAD_MIN WINPAD_FILL WINPAD_TERM WINPAD_TITLE WINPAD_TERM_TITLE WINPAD_SURFACE WINPAD_LIT WINPAD_BAND_HEX WINPAD_ALPHA WINPAD_FONT WINPAD_PLACE WINPAD_WIDTH WINPAD_SIDE_WIDTH WINPAD_HEIGHT WINPAD_BAR WINPAD_BAND WINPAD_VIEW WINPAD_GAP WINPAD_LOCK WINPAD_STATE WINPAD_BAR_PID
        if command -v setsid >/dev/null 2>&1; then setsid sh -c "$WINPAD_KEEP" "$_pdc" "$@" </dev/null >/dev/null 2>"$_pdlog" &
        else ( trap '' HUP; exec sh -c "$WINPAD_KEEP" "$_pdc" "$@" ) </dev/null >/dev/null 2>"$_pdlog" & fi
    )
}
winpad_wake() { winpad_pid >/dev/null || winpad_run 2>/dev/null || :; }   # the pad up when it is not; never waited for
winpad_look() { winpad_pid >/dev/null 2>&1 || return 0; wm_tick spark-winpad.look >/dev/null 2>&1 || :; }   # the pad reads the tree now: a window a command moved, which sway tells no one
winpad_again() {   # a running pad restarted, so it takes a new look or bar place; once a run
    [ -z "${_winpad_again:-}" ] || return 0; _winpad_again=1
    _pdo=$(winpad_pid) || return 0
    kill "$_pdo" 2>/dev/null || :
    _pdi=0; while [ "$_pdi" -lt 20 ] && kill -0 "$_pdo" 2>/dev/null; do sleep 0.1; _pdi=$((_pdi + 1)); done
    if winpad_run 2>/dev/null; then _winpad_started=1; fi   # winpad_session asks for no second one before this one takes its lock
}
winpad_place_words() {   # winpad_place_words PLACE -> where it sits, in words
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
winpad_band_words() { if [ "$1" = on ]; then echo "the band under its handle says pad and how many wait"; else echo "the handle alone across its top"; fi; }   # winpad_band_words on|off -> what the pad shows, in words
winpad_view_words() { if [ "$1" = titles ]; then echo "a slot a window, its icon, its app and its title"; else echo "one icon a window, its title beside it on hover"; fi; }   # winpad_view_words icons|titles -> how the pad shows its windows, in words
layout_pad() {   # layout_pad [keys|toggle|place PLACE WIDTH SIDE [HEIGHT]|band [on|off]|view [icons|titles]|start|again] -- the pad
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own Dock"
    case ${1:-} in
        place) shift
            # a pad sends three; the height in the config stays then
            case $# in 3|4) ;; *) refuse "pad place takes PLACE WIDTH SIDE [HEIGHT]: \"bottom center\" 0 36 0" ;; esac
            winpad_place_ok "$1" || refuse "pad place: top, bottom, left or right and center, start, end or pixels along that edge, or free X Y"
            winpad_width_ok "$2" 0 || refuse "pad place: the width is pixels, 0 to 9999 (0: as wide as the screen allows)"
            winpad_width_ok "$3" 36 || refuse "pad place: the width at a side is pixels, 36 to 9999"
            [ "$#" = 3 ] || winpad_width_ok "$4" 0 || refuse "pad place: the height is pixels, 0 to 9999 (0: as many rows as needed)"
            config_set WINPAD_PLACE "$1" >/dev/null; config_set WINPAD_WIDTH "$2" >/dev/null; config_set WINPAD_SIDE_WIDTH "$3" >/dev/null
            [ "$#" = 3 ] || config_set WINPAD_HEIGHT "$4" >/dev/null
            WINPAD_PLACE=$1; WINPAD_WIDTH=$2; WINPAD_SIDE_WIDTH=$3; [ "$#" = 3 ] || WINPAD_HEIGHT=$4; export WINPAD_PLACE WINPAD_WIDTH WINPAD_SIDE_WIDTH WINPAD_HEIGHT
            [ -n "${WINPAD_LOCK:-}" ] || winpad_again   # drawn again at its place; the pad's own save after a drag keeps it as it is
            echo "the pad sits $(winpad_place_words "$1")"; return ;;
        band) [ "$#" -le 2 ] || refuse "pad band takes on or off"
            case ${2:-} in
                '') echo "pad band $WINPAD_BAND $PANEL_SEP $(winpad_band_words "$WINPAD_BAND")"; return ;;
                on|off) ;;
                *) refuse "pad band takes on or off" ;;
            esac
            [ "$2" != "$WINPAD_BAND" ] || refuse "the pad's band is $2 already"
            config_set WINPAD_BAND "$2" >/dev/null; WINPAD_BAND=$2; export WINPAD_BAND
            winpad_again   # drawn again, with the band or without it
            echo "pad band $2 $PANEL_SEP $(winpad_band_words "$2")"; return ;;
        view) [ "$#" -le 2 ] || refuse "pad view takes icons or titles"   # WINPAD_VIEW
            case ${2:-} in
                '') echo "pad view $WINPAD_VIEW $PANEL_SEP $(winpad_view_words "$WINPAD_VIEW")"; return ;;
                icons|titles) ;;
                *) refuse "pad view takes icons or titles" ;;
            esac
            [ "$2" != "$WINPAD_VIEW" ] || refuse "the pad's view is $2 already"
            config_set WINPAD_VIEW "$2" >/dev/null; WINPAD_VIEW=$2; export WINPAD_VIEW
            winpad_again   # drawn again in that view
            echo "pad view $2 $PANEL_SEP $(winpad_view_words "$2")"; return ;;
        ''|keys|toggle|start|again) ;;
        *) refuse "pad takes keys, toggle, place PLACE WIDTH SIDE [HEIGHT], band on|off or view icons|titles" ;;
    esac
    [ "${1:-}" != again ] || { winpad_again; return 0; }
    wm_up || { [ "${1:-}" != start ] || return 0; refuse "the pad is the desktop's: run it inside it"; }
    wm_tree > "$TMP/tree" || refuse "$WM_NAME did not answer"
    winpad_list "$TMP/tree" > "$TMP/pad"
    _pdn=$(grep -c '' "$TMP/pad" || :)
    case ${1:-} in
        '') if [ "$_pdn" = 0 ]; then echo "no window is on the pad"
            else _pdw=window; [ "$_pdn" = 1 ] || _pdw=windows
                echo "the pad has $_pdn $_pdw: $(cut -f2 "$TMP/pad" | paste -sd, - | sed 's/,/, /g')"; fi ;;
        start) winpad_pid >/dev/null || ! winpad_here || ! sparkbar_draws || sparkbar_wait   # sway starts the bar and the pad at once at login: where spark's bar draws, its lock first, two seconds at most, so a pad keeping its strip starts after the bar
            winpad_wake ;;   # resident: it sets the buttons on each title and keeps the focus order
        keys) [ "$_pdn" != 0 ] || refuse "no window is on the pad"
            if _pdp=$(winpad_pid); then kill -USR1 "$_pdp" 2>/dev/null || :
            elif ! winpad_run --keys; then layout_window restore; return; fi   # no pad here: the window minimized last comes back
            echo "the pad has the keys: Enter brings the window back, Esc leaves" ;;
        toggle) [ "$_pdn" != 0 ] || refuse "no window is on the pad"
            if _pdp=$(winpad_pid); then
                if winpad_hidden; then _pds='back in sight'; else _pds=hidden; fi
                kill -USR2 "$_pdp" 2>/dev/null || :
            else winpad_run || refuse "spark-winpad is not installed -- spark-shell on desktop"; _pds='back in sight'; fi
            echo "the pad is $_pds" ;;
    esac
}
