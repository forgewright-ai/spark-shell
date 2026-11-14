# shellcheck extended-analysis=false
# --- sparkbar: spark's own bar (spark-bar), pinned like the pad; it runs `spark-shell bar status` and draws its line
# sets: SPARKBAR_BIN SPARKBAR_KEEP SPARKBAR_TRAY_SLOTS
# reads: DIALOG_URL MODE OS REPO STATE_DIR TMP
SPARKBAR_BIN=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/spark-bar
SPARKBAR_TRAY_SLOTS=4   # the apps' icons the strip at the bar's end holds
sparkbar_file() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-bar.$1"; }   # sparkbar_file pid|state|log|font|tray -> the bar's file of that kind, in the runtime folder
sparkbar_release_tag() {   # -> clone_tag when it pins a bar and component/bar/ is unchanged since; false otherwise
    _sbr=$(clone_tag) || return 1
    git -C "$REPO" cat-file -e "$_sbr:component/bar/bar.env" 2>/dev/null || return 1
    git -C "$REPO" diff --quiet "$_sbr" -- component/bar 2>/dev/null || return 1
    printf '%s\n' "$_sbr"
}
sparkbar_want_sha() {   # -> the sha256 the release tag's tree pins for this machine, or nothing
    _sbk=BAR_SHA256_$(wallpaper_target | tr 'a-z-' 'A-Z_'); _sbr=$(sparkbar_release_tag) || return 0
    git -C "$REPO" show "$_sbr:component/bar/bar.env" 2>/dev/null | sed -n "s/^$_sbk=\([0-9a-f]\{64\}\)$/\1/p"
}
sparkbar_ok() { [ -x "$SPARKBAR_BIN" ] && _sbw=$(sparkbar_want_sha) && [ -n "$_sbw" ] && [ "$(sha256_of "$SPARKBAR_BIN")" = "$_sbw" ]; }   # the binary in place is the one the tree pins
sparkbar_cmd() { if [ -n "${SPARK_SHELL_BAR:-}" ]; then [ -x "$SPARK_SHELL_BAR" ] && printf '%s' "$SPARK_SHELL_BAR"; elif sparkbar_ok; then printf '%s' "$SPARKBAR_BIN"; else return 1; fi; }   # -> SPARK_SHELL_BAR (another build, as it is), else the pinned bar; false when none
sparkbar_here() { sparkbar_cmd >/dev/null 2>&1; }   # a spark-bar can run on this machine
sparkbar_draws() { [ "$OS" != Darwin ] && [ "$DESKTOP_BAR" = yes ] && sparkbar_here; }   # spark-bar draws the bar; where it cannot run, or the bar is hidden, sway's own bar runs the line
sparkbar_install() {   # the bar's row of on desktop: in place as pinned, or fetched for the signed tag and checked
    _sbt=$(wallpaper_target) || { skip bar "no spark-bar built for $(uname -m) yet: sway's bar draws the bar"; return 0; }
    _sbr=$(sparkbar_release_tag) || { row todo bar "this clone is past its release: spark-bar comes with the next tag; sway's bar draws the bar"; return 0; }
    _sbw=$(sparkbar_want_sha); [ -n "$_sbw" ] || { skip bar "$_sbr pins no spark-bar: sway's bar draws the bar"; return 0; }
    if sparkbar_ok; then ok bar "$SPARKBAR_BIN, the sha256 $_sbr pins"; return 0; fi
    [ "$DIALOG_URL" != none ] || { skip bar "no release to fetch it from (SPARK_SHELL_DIALOG_URL=none): sway's bar draws the bar"; return 0; }
    tag_signed "$_sbr" || { row todo bar "$_sbr is not signed by a key in allowed-signers: spark-bar not installed"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo bar "curl is not installed: spark-bar cannot be fetched (spark-shell on installs it)"; return 0; }
    need bar "fetch spark-bar for $_sbr and check its sha256" || return 0
    _sbf=$TMP/spark-bar
    curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$_sbf" "$DIALOG_URL/$_sbr/spark-bar-$_sbt" 2>/dev/null || { rm -f "$_sbf"; row todo bar "could not fetch spark-bar for $_sbr -- spark-shell on desktop again"; return 0; }
    [ "$(sha256_of "$_sbf")" = "$_sbw" ] || { rm -f "$_sbf"; row todo bar "the spark-bar fetched for $_sbr is not the one the tree pins: not installed"; return 0; }
    mkdir -p "$(dirname "$SPARKBAR_BIN")" && cp "$_sbf" "$SPARKBAR_BIN.new" && chmod 755 "$SPARKBAR_BIN.new" && mv "$SPARKBAR_BIN.new" "$SPARKBAR_BIN"
    row ok bar "spark-bar installed for $_sbr ($SPARKBAR_BIN), sha256 checked"
    ! sparkbar_pid >/dev/null || { _sparkbar_again=''; sparkbar_again; }   # a bar running the build before takes the new one
}
sparkbar_session() {   # on desktop's last bar row: sway starts the bar at login alone, so a session that began before, as an update's, has none until this starts it, through sway, as login does
    sparkbar_draws && wm_up || return 0
    ! sparkbar_pid >/dev/null || return 0
    [ -z "${_sparkbar_started:-}" ] || return 0   # this run started one already (sparkbar_again), its lock not taken yet
    need bar "start the bar for this session, through sway as at login" || return 0
    wm_exec "$REPO/spark-shell bar start" >/dev/null 2>&1 || { row todo bar "sway did not start the bar -- it starts at the next login"; return 0; }
    ok bar "the bar runs for this session now"
    sparkbar_settle
}
sparkbar_pid() {   # -> the running bar's pid, from its lock; false when none runs
    _sbl=$(sparkbar_file pid); [ -s "$_sbl" ] || return 1
    _sbp=''; read -r _sbp 2>/dev/null < "$_sbl" || [ -n "$_sbp" ] || return 1   # a pid with no new line after it is read too
    case $_sbp in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_sbp" 2>/dev/null || return 1
    [ ! -r "/proc/$_sbp/cmdline" ] || tr '\0' ' ' < "/proc/$_sbp/cmdline" | grep -q 'spark-bar' || return 1
    printf '%s\n' "$_sbp"
}
sparkbar_height() {   # -> the bar's height in pixels: 2.25 times its text's, 36 at 12 points (16 pixels)
    _sbh=$(bar_line_font); _sbh=${_sbh##* }
    case $_sbh in *px) awk -v n="${_sbh%px}" 'BEGIN { printf "%d", n * 2.25 + 0.5 }' ;; *) awk -v n="$_sbh" 'BEGIN { printf "%d", n * 3 + 0.5 }' ;; esac
}
# the keeper: the bar again when it ends by itself, a crash; a stop on purpose (0) stays a stop, and so do wrong
# arguments (2), a session that is gone and a bar that ends five times within a minute of its start
SPARKBAR_KEEP='n=0; while :; do t=$(date +%s); "$0" "$@"; rc=$?; case $rc in 0|2) break ;; esac; [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY:-none}" ] || break; [ $(( $(date +%s) - t )) -lt 60 ] || n=0; n=$((n + 1)); [ "$n" -le 5 ] || break; echo "spark-bar ended ($rc): started again" >&2; sleep 1; done'
sparkbar_run() {   # spark-bar started in its own session, under its keeper; false when none can run here
    _sbc=$(sparkbar_cmd) || return 1
    theme_load 2>/dev/null || :
    _sblog=$(sparkbar_file log)
    mkdir_private "$STATE_DIR"
    (
        # the look before its first line (each line carries it then: bar_look), the muted lifted as the pad's; BAR_TRAY_WIDTH pixels stay clear at the right end of BAR_TRAY_OUTPUT, for the tray's host
        _sbs=''; [ "$BAR_TRAY" != yes ] || _sbs=$(sparkbar_tray_screen) || _sbs=''
        BAR_TRAY_OUTPUT=${_sbs% *}; BAR_TRAY_WIDTH=0; [ -z "$_sbs" ] || BAR_TRAY_WIDTH=$(( $(sparkbar_height) * SPARKBAR_TRAY_SLOTS ))
        SPARK_SHELL=$REPO/spark-shell BAR_FONT=$(bar_line_font) BAR_FG=$HEX_FG BAR_ACCENT=$HEX_ACCENT BAR_MUTED=$PANEL_MUTED BAR_GROUND=$HEX_BG BAR_LIT=$PANEL_HI BAR_ATTENTION=$HEX_ANSI_3 BAR_ALPHA=$ALPHA
        BAR_LOCK=$(sparkbar_file pid) BAR_STATE=$(sparkbar_file state)   # BAR_PINS and BAR_OVERFLOW as config_load read them
        export SPARK_SHELL BAR_POSITION BAR_FONT BAR_FG BAR_ACCENT BAR_MUTED BAR_GROUND BAR_LIT BAR_ATTENTION BAR_ALPHA BAR_PINS BAR_OVERFLOW BAR_TRAY_WIDTH BAR_TRAY_OUTPUT BAR_LOCK BAR_STATE
        if command -v setsid >/dev/null 2>&1; then setsid sh -c "$SPARKBAR_KEEP" "$_sbc" </dev/null >/dev/null 2>"$_sblog" &
        else ( trap '' HUP; exec sh -c "$SPARKBAR_KEEP" "$_sbc" ) </dev/null >/dev/null 2>"$_sblog" & fi
    )
}
sparkbar_wake() {   # bar start, sway's: the bar up when it is not; never waited for
    if sparkbar_draws; then sparkbar_pid >/dev/null || sparkbar_run 2>/dev/null || :; return 0; fi
    # sway's config starts a spark-bar that draws no more, its file gone or not the pinned one: rendered again, and sway's
    # own bar is back. Once: the new config has no line that runs this
    [ "$DESKTOP_BAR" = yes ] && grep -qxF "exec $REPO/spark-shell bar start" "$(wm_config_file)" 2>/dev/null && wm_up || return 0
    theme_load; EXPR=$(render_expr); desktop_look_apply >/dev/null
}
sparkbar_stop() {   # sparkbar_stop PID -- the bar told to end (it leaves with 0, so its keeper lets it), waited for two seconds
    kill "$1" 2>/dev/null || :
    _sbi=0; while [ "$_sbi" -lt 20 ] && kill -0 "$1" 2>/dev/null; do sleep 0.1; _sbi=$((_sbi + 1)); done
}
sparkbar_wait() { _sbi=0; while [ "$_sbi" -lt 20 ] && ! sparkbar_pid >/dev/null; do sleep 0.1; _sbi=$((_sbi + 1)); done; }   # the bar's lock, waited for two seconds at most
sparkbar_settle() { sparkbar_wait; _winpad_again=''; winpad_again; }   # the new bar has its lock, then the pad starts again: a pad keeping its strip starts after the bar, so the bar is not inside that strip
sparkbar_again() {   # the bar as the config has it now: a running one ended, so the next takes a new place, text or pins, and one started where it draws, through sway as at login, so it is sway's child in the session's environment; once a run
    [ -z "${_sparkbar_again:-}" ] || return 0; _sparkbar_again=1
    _sbo=$(sparkbar_pid) || _sbo=''; _sbd=''; ! sparkbar_draws || _sbd=1
    [ -n "$_sbo$_sbd" ] || return 0   # none runs and none draws here: sway is not asked
    wm_up || return 0   # a shell that cannot reach the session (ssh, a socket that is gone) would end the bar and start none: the bar stays
    [ -z "$_sbo" ] || sparkbar_stop "$_sbo"
    [ -n "$_sbd" ] && wm_exec "$REPO/spark-shell bar start" >/dev/null 2>&1 || return 0
    _sparkbar_started=1   # sparkbar_session asks for no second one before this one takes its lock
    sparkbar_settle
}
sparkbar_font_again() {   # sparkbar_font_again FONT -- the status loop's: its bar started again for the screen's font, apart, so the restart outlives the loop; once for a font, whatever the new bar is handed
    [ "$1" != "$(cat "$(sparkbar_file font)" 2>/dev/null)" ] || return 0
    printf '%s\n' "$1" > "$(sparkbar_file font)"
    if command -v setsid >/dev/null 2>&1; then setsid sh "$REPO/spark-shell" bar again </dev/null >/dev/null 2>&1 &
    else ( trap '' HUP; exec sh "$REPO/spark-shell" bar again ) </dev/null >/dev/null 2>&1 & fi
}
sparkbar_no_pins() {   # -> why a pin changes nothing here; nothing where spark-bar draws the bar and holds to the pins
    ! sparkbar_draws || return 0
    if [ "$DESKTOP_BAR" != yes ]; then echo "pins need the bar shown: it is hidden (spark-shell bar on --desktop shows it)"
    else echo "pins need spark-bar: sway's bar draws the bar here, and it shows every module (spark-shell on desktop)"; fi
}
sparkbar_keys() {   # Super+equal: the keyboard on the bar
    [ "$DESKTOP_BAR" = yes ] || refuse_in bar "the bar is hidden (spark-shell bar on --desktop shows it)"
    _sbp=$(sparkbar_pid) || refuse_in bar "the bar takes no keys here: spark-bar is not running (spark-shell on desktop)"
    kill -USR1 "$_sbp" 2>/dev/null || :
    echo "the bar has the keys: the arrows move, Enter acts, Esc leaves"
}
# the tray: sway's own bar hosts the apps' icons alone, over the strip spark-bar leaves clear at its right end, on the
# first screen. Its width is set while it runs: a host wider than its screen ends, and only a reload starts it again
sparkbar_tray_screen() { wm_live && wm_here || return 1; wm_outputs | jq -r '[.[] | select(.active)][0] | "\(.name) \(.rect.width)"' 2>/dev/null | grep -x '[^ ]* [0-9][0-9]*'; }   # -> the first screen on: NAME WIDTH
sparkbar_tray_place() {   # the host placed: sway's, at login and after each reload
    [ "$BAR_TRAY" = yes ] && sparkbar_draws || return 0
    _sts=$(sparkbar_tray_screen) || return 0
    _sth=$(sparkbar_height); _stl=$(( ${_sts#* } - _sth * SPARKBAR_TRAY_SLOTS )); [ "$_stl" -ge 0 ] || return 0
    wm_tray_place "${_sts% *}" "$_stl" "$_sth" "$(( (_sth * 2 + 4) / 9 ))" || return 0   # the icons 1.25 times the text
    printf '%s %s\n' "$_sts" "$_sth" > "$(sparkbar_file tray)"
}
sparkbar_tray_follow() {   # the status loop's: the host follows its screen's width and the bar's height; kept once for each, so nothing repeats
    [ "$(bar_style BAR_TRAY no)" = yes ] || return 0
    _stn=$(sparkbar_tray_screen) || return 0
    _stn="$_stn $(sparkbar_height)"; _sto=$(cat "$(sparkbar_file tray)" 2>/dev/null) || _sto=''
    [ "$_stn" != "$_sto" ] || return 0
    printf '%s\n' "$_stn" > "$(sparkbar_file tray)"
    set -- $_stn ${_sto:-- 0 0}
    if [ "$1" = "$4" ] && [ "$2" -lt "$5" ]; then wm_reload >/dev/null 2>&1 || :   # a narrower screen ended the host: the reload starts it, and places it
    else BAR_TRAY=yes sparkbar_tray_place; fi
    [ "$1" = "$4" ] || [ "$4" = - ] || sparkbar_font_again "screen $1"   # another screen is the first: the bar clears its strip there
}
sparkbar_off() {   # off, off desktop: the bar ended, its binary and its runtime files gone
    _sbo=$(sparkbar_pid) || _sbo=''
    [ -n "$_sbo" ] || [ -e "$SPARKBAR_BIN" ] || return 0
    if [ "$MODE" = dry ]; then row would bar "spark-bar ended and removed ($SPARKBAR_BIN)"; return 0; fi
    [ -z "$_sbo" ] || sparkbar_stop "$_sbo"
    rm -f "$SPARKBAR_BIN"
    for _sbx in pid state log font tray failed.out failed.mic; do rm -f "$(sparkbar_file "$_sbx")"; done
    [ -z "${XDG_RUNTIME_DIR:-}" ] || rm -rf "${XDG_RUNTIME_DIR:?}/spark-shell-bar.icons"   # the logo spark-bar drew and kept
    row ok bar "spark-bar ended and removed ($SPARKBAR_BIN)"
}
