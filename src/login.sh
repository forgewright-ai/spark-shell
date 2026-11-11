# shellcheck extended-analysis=false
# the gsettings color-scheme is yours: put back only while spark-shell's
# sets: GREETD_CONF LOGIN_ETC LOGIN_FILES LOGIN_FONTS LOGIN_ICONS LOGIN_LIB LOGIN_MARK LOGIN_SUDOERS OLD_GREETD_CONF OLD_GREETD_DIRS OLD_GREETD_FILES
# reads: DIALOG_BIN DISTRO FACES_OTHER FAMILIES_SAID MODE NEON_STYLES NL OS POINTER_DIR POINTER_THEMES RENDERED REPO ROOT SCREENS_CONF SOUND_CONF SOUND_SV SPARK_CONFIG_DIR STATE_DIR TMP
# last value still holds; an outside change takes it back
portal_ready() {
    [ "$OS" != Darwin ] && notify_bus && command -v gsettings >/dev/null 2>&1 &&
        gsettings list-keys org.gnome.desktop.interface 2>/dev/null | grep -qx color-scheme
}
portal_look() (
    [ "$MODE" = apply ] && [ "$DESKTOP" = sway ] && portal_ready || exit 0
    wanted="'prefer-light'"; ! theme_is_dark || wanted="'prefer-dark'"
    current=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || exit 0
    [ "$current" != "$wanted" ] || exit 0
    saved=$STATE_DIR/portal-color-scheme
    prior=$current
    if [ -f "$saved" ] && [ "$(sed -n 2p "$saved")" = "$current" ]; then prior=$(sed -n 1p "$saved"); fi
    if gsettings set org.gnome.desktop.interface color-scheme "$wanted" 2>/dev/null; then
        mkdir_private "$STATE_DIR"
        (umask 077; printf '%s\n%s\n' "$prior" "$wanted" > "$saved")
    fi
)
portal_off() (
    [ "$MODE" = apply ] && [ -f "$STATE_DIR/portal-color-scheme" ] || exit 0
    portal_ready || exit 0
    saved=$STATE_DIR/portal-color-scheme
    current=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || exit 0
    if [ "$current" = "$(sed -n 2p "$saved")" ]; then
        gsettings set org.gnome.desktop.interface color-scheme "$(sed -n 1p "$saved")" 2>/dev/null || exit 0
    fi
    rm -f "$saved"
)
desk_portals() {
    [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] || refuse "portals need the sway desktop"
    [ -n "${WAYLAND_DISPLAY:-}" ] && notify_bus || refuse "portals need the running desktop and its session bus"
    command -v dbus-update-activation-environment >/dev/null 2>&1 || refuse "the desktop bus tools are missing (spark-shell on desktop)"
    XDG_CURRENT_DESKTOP=sway; export XDG_CURRENT_DESKTOP
    dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP SWAYSOCK || return 1
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP SWAYSOCK 2>/dev/null || :
    fi
    theme_load
    portal_look
    echo "the desktop portal environment is ready"
}
portal_check() {
    missing=''
    for package in xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk gsettings-desktop-schemas; do
        pkg_installed "$package" || missing="$missing $package"
    done
    if [ -n "$missing" ]; then chk portals warn "not installed:$missing" "spark-shell on desktop"; return; fi
    if ! command -v dbus-update-activation-environment >/dev/null 2>&1 || ! command -v gsettings >/dev/null 2>&1; then
        chk portals warn "the desktop bus or settings tools are missing" "spark-shell on desktop"
    elif [ -n "${WAYLAND_DISPLAY:-}" ] && ! notify_bus; then
        chk portals warn "the desktop has no session bus" "log out and in again"
    elif [ ! -f "$HOME/.config/xdg-desktop-portal/sway-portals.conf" ]; then
        chk portals warn "the desktop portal choices are missing" "spark-shell on desktop"
    else chk portals ok "native settings and file picker via gtk, screen sharing via wlr"; fi
}

notify_check() {   # the notify row of check, on a desktop machine
    if ! mako_here; then chk notify warn "mako is not installed, so no notification shows" "spark-shell on desktop"
    elif ! command -v notify-send >/dev/null 2>&1; then chk notify warn "notify-send is not installed, so a reminder or a drive plugged in says nothing" "spark-shell on desktop"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then chk notify ok "the notifications show on the desktop"
    elif notify_up; then _nw=''; ! notify_dnd || _nw=', do not disturb on'; chk notify ok "the notifications show$_nw"
    else chk notify warn "$(notify_why)" "log out and in again"; fi
}
storage_check() {   # the storage row of check
    if ! udisks_here; then chk storage warn "udisks2 is not installed, so no drive shows" "spark-shell on desktop"
    elif [ "$(init_shape)" = runit ] && [ ! -s "$STATE_DIR/storage.polkit" ]; then chk storage warn "with no logind, a drive mounts only with the polkit rule" "spark-shell on desktop"
    else chk storage ok "udisks2 mounts and ejects drives for you"; fi
}
power_check() {   # the power row of check
    if [ -z "$(power_tool)" ]; then chk power warn "$(power_why)" "spark-shell on desktop"
    elif power_sleeps; then chk power ok "lock, log out, suspend, restart and shut down from the dialog"
    else chk power ok "lock, log out, restart and shut down from the dialog (this machine cannot suspend)"; fi
}
sound_check() {   # the sound rows of check, on a desktop machine
    if ! command -v pipewire >/dev/null 2>&1; then
        case $(snd_tool) in
            '') chk sound warn "no audio system found, so no out or mic block" "spark-shell on desktop" ;;
            pactl) chk sound warn "PipeWire is not installed: the bar reads PulseAudio" "spark-shell on desktop" ;;
            *) chk sound warn "PipeWire is not installed: the bar reads plain ALSA" "spark-shell on desktop" ;;
        esac
        return 0
    fi
    if [ "$(snd_tool)" = wpctl ]; then chk sound ok "PipeWire runs from $(sound_from): out $(wp_default Sinks | grep . || echo none), mic $(wp_default Sources | grep . || echo none)"
    elif [ "$(init_shape)" = runit ] && sound_svc_up; then chk sound warn "PipeWire runs from boot, and does not answer" "tail $STATE_DIR/log/sound/current"
    elif [ "$(init_shape)" != systemd ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then chk sound ok "PipeWire starts with the desktop"
    else chk sound warn "PipeWire does not answer" "leave the desktop and log in again"; fi
    if [ "$(init_shape)" = runit ] && [ ! -e "$SOUND_SV" ] && [ ! -L "$SOUND_SV" ] && [ -z "$(sound_svc_why)" ]; then
        chk sound warn "PipeWire starts with the desktop, so a console has no sound" "spark-shell on desktop"
    elif sound_svc_ours; then
        sound_svc_render; _f=$(sound_svc_differ)
        [ -z "$_f" ] || chk sound warn "$SOUND_SV is out of date:$_f" "spark-shell on desktop"
    fi
    _miss=$(sound_links_missing)
    [ -z "$_miss" ] || chk sound warn "ALSA programs skip PipeWire: /$SOUND_CONF lacks$_miss" "spark-shell on desktop"
    ! sound_group_needed || in_group audio "$(id -un)" || chk sound warn "$(id -un) is not in the audio group, so the sound devices stay closed" "spark-shell on desktop"
    if _tf=$(al_theirs); then chk sound warn "$(al_theirs_said "$_tf"), so ALSA programs that use it skip PipeWire" "take the default out of it"; fi
    if pgrep -x bluealsa >/dev/null 2>&1 || pgrep -x bluealsad >/dev/null 2>&1; then chk sound warn "bluez-alsa runs beside PipeWire, and only one of them can offer Bluetooth sound" "turn one of them off"; fi
    return 0
}

# the old login screen (greetd with tuigreet, systemd): on and off hand
# tty1 back to getty for the next boot where spark-shell's files for it
# remain, never stopping greetd live (that would end this session)
OLD_GREETD_CONF=etc/greetd/config.toml
OLD_GREETD_FILES="etc/greetd/spark-shell/desktop.desktop etc/greetd/spark-shell/console.desktop etc/systemd/system/greetd.service.d/spark-shell.conf"
OLD_GREETD_DIRS="etc/greetd/spark-shell etc/systemd/system/greetd.service.d"
unit_enabled() { systemctl is-enabled "$1" >/dev/null 2>&1; }
old_greetd_here() { grep -q 'rendered by spark-shell from templates/etc/greetd' "$ROOT/$OLD_GREETD_CONF" 2>/dev/null || [ -e "$ROOT/$OLD_GREETD_CONF.spark-orig" ]; }
old_greetd_off() {
    [ "$OS" != Darwin ] && old_greetd_here || return 0
    need login "the normal console login on tty1 from the next boot: the login screen turned off, its files removed (sudo)" || return 0
    if ! root_can; then row todo login "the old login screen stays -- spark-shell on at a terminal (sudo once)"; acting=0; return 0; fi
    root_sudo_once "the login screen on tty1" || { row todo login "sudo refused -- spark-shell on at a terminal (sudo once)"; acting=0; return 0; }
    # getty first: tty1 never loses its login
    root_do systemctl enable getty@tty1.service >/dev/null 2>&1 || true
    root_do systemctl disable greetd.service >/dev/null 2>&1 || true
    conf=$ROOT/$OLD_GREETD_CONF
    if [ -e "$conf.spark-orig" ]; then root_do mv "$conf.spark-orig" "$conf"
    else root_do rm -f "$conf"; fi
    for rel in $OLD_GREETD_FILES; do [ ! -e "$ROOT/$rel" ] || root_do rm -f "$ROOT/$rel"; done
    for d in $OLD_GREETD_DIRS; do [ -d "$ROOT/$d" ] && root_do rmdir "$ROOT/$d" 2>/dev/null || true; done
    root_do systemctl daemon-reload >/dev/null 2>&1 || true
    ok login "the normal console login is back on tty1 from the next boot: the login screen is off, its packages stay"
}

# the login screen (LOGIN=yes): greetd on tty1 runs sway as its own
# account with one window, `spark-dialog login`. Its files are root's
# (LOGIN_ETC, LOGIN_LIB, greetd's config.toml, the package's own kept as
# .spark-shell-orig). tty1 changes hands at the next boot, never under a
# running login: systemd enables greetd, Void runs login-boot from
# /etc/rc.local with a sudoers file for reboot and poweroff only
LOGIN_ETC=etc/spark-shell/login
LOGIN_LIB=usr/local/lib/spark-shell
LOGIN_ICONS=usr/share/icons   # the spark pointer for the login screen's account, a copy of the two themes
LOGIN_FONTS=usr/share/fonts/spark-shell   # Monaspace Neon for the login screen's account, a copy of the four faces spark-shell installed
GREETD_CONF=etc/greetd/config.toml
LOGIN_SUDOERS=etc/sudoers.d/spark-shell-login
LOGIN_MARK=' #spark-shell-login#'
LOGIN_FILES="session window run sway.conf foot.ini screens.conf"
login_wanted() { [ -z "$(login_na)" ] && [ "$LOGIN" = yes ]; }
login_rec() { [ -e "$ROOT/$LOGIN_ETC/$1" ]; }                       # login_rec NAME -- a record of a change spark-shell made
login_record() { root_do touch "$ROOT/$LOGIN_ETC/$1"; }
login_unrecord() { root_do rm -f "$ROOT/$LOGIN_ETC/$1"; }
login_line() { printf '[ -x /%s/login-boot ] && /%s/login-boot' "$LOGIN_LIB" "$LOGIN_LIB"; }   # the rc.local line (runit)
greetd_here() { [ -e "$ROOT/usr/bin/greetd" ] || [ -e "$ROOT/usr/sbin/greetd" ]; }
greetd_live() { pgrep -x greetd >/dev/null 2>&1; }
greetd_ours() { grep -q 'rendered by spark-shell from templates/login/config.toml' "$ROOT/$GREETD_CONF" 2>/dev/null; }
login_account_here() { awk -F: -v u="$LOGIN_ACCOUNT" '$1 == u { f = 1 } END { exit !f }' "$ROOT/etc/passwd" 2>/dev/null; }
login_screen_traces() { [ -d "$ROOT/$LOGIN_ETC" ] || greetd_ours || [ -e "$ROOT/$GREETD_CONF.spark-shell-orig" ] || [ -n "$(marked "$ROOT/etc/rc.local" "$LOGIN_MARK")" ]; }
login_switched() {   # does the login screen take tty1 at boot?
    if [ "$(init_shape)" = systemd ]; then unit_enabled greetd.service && ! unit_enabled getty@tty1.service
    else [ "$(cat "$ROOT/$LOGIN_ETC/boot" 2>/dev/null)" = on ] && [ "$(marked "$ROOT/etc/rc.local" "$LOGIN_MARK")" = "$(login_line)" ]; fi
}
login_port() {   # -> spark's port for the screen's spark row, or nothing without spark
    [ -n "$(spark_bin)" ] || return 0
    _p=$(sed -n 's/^SPARK_PORT=//p' "$SPARK_CONFIG_DIR/spark.env" 2>/dev/null | tail -1 | tr -d "\"'")
    case $_p in ''|*[!0-9]*) _p=8080 ;; esac
    printf '%s' "$_p"
}
login_render() {   # -> the screen's files in $TMP/login, from template/login in the palette
    mkdir -p "$TMP/login"
    if [ "$(init_shape)" = systemd ]; then _pw=' --restart "/usr/bin/systemctl reboot" --shutdown "/usr/bin/systemctl poweroff"'
    else _pw=' --restart "/usr/bin/sudo -n /usr/bin/reboot" --shutdown "/usr/bin/sudo -n /usr/bin/poweroff"'; fi
    _p=$(login_port); [ -z "$_p" ] || _pw="$_pw --spark-port $_p"
    _d=off; ! desktop_wanted || _d=on
    if wall_there; then _bg="/$LOGIN_ETC/wallpaper fill"; else _bg=$WALL_BG; fi
    _le="$EXPR${NL}s|@LOGIN_ETC@|$LOGIN_ETC|g${NL}s|@LOGIN_LIB@|$LOGIN_LIB|g${NL}s|@LOGIN_ACCOUNT@|$(esc "$LOGIN_ACCOUNT")|g"
    _le="$_le${NL}s|@LOGIN_DESKTOP@|$_d|g${NL}s|@LOGIN_ARGS@|$(esc "$_pw")|g${NL}s|@LOGIN_BG@|$(esc "$_bg")|g${NL}s|@PANEL_MUTED@|$PANEL_MUTED|g"
    for f in $LOGIN_FILES config.toml sudoers login-boot; do
        if [ "$f" = screens.conf ]; then login_screens > "$TMP/login/$f"; continue; fi   # no template: the lines of your screens.conf
        render_sed "$_le" "$REPO/template/login/$f" > "$TMP/login/$f"
        if grep -q '@[A-Z_0-9]*@' "$TMP/login/$f"; then
            printf 'spark-shell: template/login/%s: unrendered placeholder: %s\n' "$f" "$(grep -o '@[A-Z_0-9]*@' "$TMP/login/$f" | head -1)" >&2
            exit 1
        fi
    done
}
login_screens() {   # -> the login screen's screens.conf: the output lines of yours, so its screens sit and turn as the desktop's do
    echo '# rendered by spark-shell from your screens.conf -- the screens as the desktop has them; spark-shell off login removes it'
    [ ! -f "$SCREENS_CONF" ] || grep -e '^output ' -e '^workspace 1 output ' "$SCREENS_CONF" || :   # the main screen too: its form goes there
}
login_screens_follow() {   # after a screen setting: the login screen's copy now when root asks no password, else said in one line
    login_wanted && [ -f "$ROOT/$LOGIN_ETC/sway.conf" ] || return 0
    mkdir -p "$TMP/login"; login_screens > "$TMP/login/screens.conf"
    ! cmp -s "$TMP/login/screens.conf" "$ROOT/$LOGIN_ETC/screens.conf" || return 0
    if [ -n "$ROOT" ] || [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then root_put "$TMP/login/screens.conf" "$ROOT/$LOGIN_ETC/screens.conf"
    else echo "the login screen takes the screens at spark-shell on login (sudo)"; fi
}
login_mode() { case $1 in session|window|run|login-boot) echo 0755 ;; sudoers) echo 0440 ;; *) echo 0644 ;; esac; }
login_pointer_put() {   # the two spark themes copied under /usr/share/icons, where the login screen's account finds them
    for _t in $POINTER_THEMES; do
        [ -d "$POINTER_DIR/$_t" ] || continue
        root_do rm -rf "$ROOT/$LOGIN_ICONS/$_t"
        root_do mkdir -p "$ROOT/$LOGIN_ICONS"
        root_do cp -R "$POINTER_DIR/$_t" "$ROOT/$LOGIN_ICONS/$_t"
        root_do chmod -R u=rwX,go=rX "$ROOT/$LOGIN_ICONS/$_t"
    done
}
login_fonts_differ() {   # the four faces in your fonts are not the login screen's copy, nor are the curated faces beside them
    neon_ours || return 1
    for _s in $NEON_STYLES; do cmp -s "$NEON_DIR/MonaspaceNeon-$_s.otf" "$ROOT/$LOGIN_FONTS/MonaspaceNeon-$_s.otf" || return 0; done
    for _fo in $FACES_OTHER; do face_ours "$_fo" || continue; for _s in $NEON_STYLES; do _ff=$(face_file "$_fo" "$_s"); cmp -s "$(face_dir "$_fo")/$_ff" "$ROOT/$LOGIN_FONTS/$_ff" || return 0; done; done
    return 1
}
login_fonts_put() {   # the copy under /usr/share/fonts, where the login screen's account finds it: your fonts are yours alone; the curated faces installed beside Neon too
    neon_ours || return 0
    for _s in $NEON_STYLES; do root_put "$NEON_DIR/MonaspaceNeon-$_s.otf" "$ROOT/$LOGIN_FONTS/MonaspaceNeon-$_s.otf"; done
    for _fo in $FACES_OTHER; do face_ours "$_fo" || continue; for _s in $NEON_STYLES; do _ff=$(face_file "$_fo" "$_s"); root_put "$(face_dir "$_fo")/$_ff" "$ROOT/$LOGIN_FONTS/$_ff"; done; done
    ! command -v fc-cache >/dev/null 2>&1 || root_do fc-cache -f "$ROOT/$LOGIN_FONTS" >/dev/null 2>&1 || :
}
login_files_differ() {   # -> the screen's files that differ from what spark-shell would write, by name
    for f in $LOGIN_FILES; do cmp -s "$TMP/login/$f" "$ROOT/$LOGIN_ETC/$f" || printf ' %s' "$f"; done
    cmp -s "$DIALOG_BIN" "$ROOT/$LOGIN_LIB/spark-dialog" || printf ' spark-dialog'
    cmp -s "$TMP/login/config.toml" "$ROOT/$GREETD_CONF" || printf ' config.toml'
    if wall_there; then cmp -s "$(wall_path)" "$ROOT/$LOGIN_ETC/wallpaper" || printf ' wallpaper'
    elif [ -e "$ROOT/$LOGIN_ETC/wallpaper" ]; then printf ' wallpaper'; fi
    for _t in $POINTER_THEMES; do   # the pointer's copy, when the themes are drawn: the same version
        [ ! -d "$POINTER_DIR/$_t" ] || [ "$(cat "$ROOT/$LOGIN_ICONS/$_t/version" 2>/dev/null)" = "$(cat "$POINTER_DIR/$_t/version")" ] || printf ' %s' "$_t"
    done
    ! login_fonts_differ || printf ' fonts'   # Monaspace Neon's copy, when spark-shell installed it in your fonts
    if [ "$DISTRO" = void ]; then
        sudoers_same || printf ' sudoers'
        cmp -s "$TMP/login/login-boot" "$ROOT/$LOGIN_LIB/login-boot" || printf ' login-boot'
    fi
}
# /etc/sudoers.d is root's alone (0750): read as root, never asking (a
# password asked for is the write's, after the would row)
sudoers_same() { if [ -n "$ROOT" ]; then cmp -s "$TMP/login/sudoers" "$ROOT/$LOGIN_SUDOERS"; else sudo -n cmp -s "$TMP/login/sudoers" "/$LOGIN_SUDOERS" 2>/dev/null; fi; }
status_login() {   # the login row of status
    if _s=$(login_na) && [ -n "$_s" ]; then _w=na
    elif [ "$LOGIN" != yes ]; then _w=console; _s="the console login on tty1 (spark-shell on login shows the login screen)"
    elif ! greetd_here; then _w=screen; _s="greetd is not installed (spark-shell on login)"
    elif ! login_switched; then _w=screen; _s="not set up yet (spark-shell on login)"
    elif greetd_live; then _w=screen; _s="the login screen on tty1, the console login on tty2"
    else _w=screen; _s="the login screen on tty1 from the next boot, the console login on tty2"; fi
    printf '  login %-16s %s\n' "$_w" "$_s"
}
login_root() {   # login_root VERB -- a root to write with, asked once; else a todo row and false
    if ! root_can; then row todo login "root is needed for the login screen -- spark-shell $1 login at a terminal (sudo once)"; acting=0; return 1; fi
    root_sudo_once "the login screen on tty1" || { row todo login "sudo refused -- spark-shell $1 login at a terminal (sudo once)"; acting=0; return 1; }
}
login_screen_apply() {   # the login rows of `on` with LOGIN=yes
    login_wanted || return 0
    [ -n "$LOGIN_ACCOUNT" ] || { row todo login "the login screen knows $FAMILIES_SAID"; acting=0; return 0; }   # the family's file names greetd's account; without one, no screen
    console_linux || { skip login "$(login_na)"; return 0; }   # the system it skips, by name: macOS or WSL
    [ "$(init_shape)" != none ] || { skip login "no systemd or runit here: nothing starts a login screen"; return 0; }
    if ! greetd_here; then
        need login "the login screen on tty1, once greetd is installed (the packages)" || return 0
        row todo login "greetd is not installed -- spark-shell on login (the packages)"; acting=0; return 0
    fi
    login_account_here || { row todo login "greetd's account $LOGIN_ACCOUNT is missing -- install greetd again, then spark-shell on login"; acting=0; return 0; }
    desktop_wanted || dialog_install
    if ! dialog_ok; then
        need login "the login screen on tty1, once spark-dialog is in place" || return 0
        row todo login "the login screen needs spark-dialog -- the dialog row says why"; acting=0; return 0
    fi
    login_render
    _f=$(login_files_differ)
    if [ -z "$_f" ]; then ok login "the login screen's files are in place (/$LOGIN_ETC)"
    elif need login "write the login screen's files:$_f (sudo)" && login_root on; then
        if [ "$DISTRO" = void ] && ! root_do visudo -cf "$TMP/login/sudoers" >/dev/null 2>&1; then
            row todo login "visudo refused the sudoers file -- nothing written, spark-shell on login again"; acting=0; return 0
        fi
        root_do mkdir -p "$ROOT/$LOGIN_ETC" "$ROOT/$LOGIN_LIB"
        for f in $LOGIN_FILES; do
            _m=$(login_mode "$f")
            if [ "$_m" = 0755 ]; then root_swap "$TMP/login/$f" "$ROOT/$LOGIN_ETC/$f" "$_m"; else root_put "$TMP/login/$f" "$ROOT/$LOGIN_ETC/$f" "$_m"; fi
        done
        root_swap "$DIALOG_BIN" "$ROOT/$LOGIN_LIB/spark-dialog" 0755
        if wall_there; then root_put "$(wall_path)" "$ROOT/$LOGIN_ETC/wallpaper"
        else root_do rm -f "$ROOT/$LOGIN_ETC/wallpaper"; fi
        login_pointer_put
        login_fonts_put
        if [ -e "$ROOT/$GREETD_CONF" ] && ! greetd_ours && [ ! -e "$ROOT/$GREETD_CONF.spark-shell-orig" ]; then
            root_do cp "$ROOT/$GREETD_CONF" "$ROOT/$GREETD_CONF.spark-shell-orig"
        fi
        root_put "$TMP/login/config.toml" "$ROOT/$GREETD_CONF"
        if [ "$DISTRO" = void ]; then
            sudoers_same || root_put "$TMP/login/sudoers" "$ROOT/$LOGIN_SUDOERS" 0440   # written once; a pass for another file leaves it
            root_swap "$TMP/login/login-boot" "$ROOT/$LOGIN_LIB/login-boot" 0755
        fi
        ok login "the login screen's files are written (/$LOGIN_ETC)"
    else return 0
    fi
    # Void: the account takes the screen through seatd, as you do
    if [ "$DISTRO" = void ] && ! in_group _seatd "$LOGIN_ACCOUNT"; then
        if need login "add $LOGIN_ACCOUNT to the _seatd group, so the login screen can draw (sudo)" && login_root on; then
            if root_do usermod -aG _seatd "$LOGIN_ACCOUNT"; then login_record seatd.group; ok login "$LOGIN_ACCOUNT is in the _seatd group"
            else row todo login "usermod could not add $LOGIN_ACCOUNT to _seatd -- spark-shell on login again"; acting=0; fi
        fi
    fi
    if login_switched; then ok login "the login screen takes tty1 at boot (tty2 keeps the console login)"; return 0; fi
    need login "the login screen on tty1 from the next boot, tty2 keeps the console login (sudo)" || return 0
    login_root on || return 0
    if [ "$(init_shape)" = systemd ]; then
        # greetd first: tty1 never loses its login
        if ! unit_enabled greetd.service; then
            root_do systemctl enable greetd.service >/dev/null 2>&1 || { row todo login "systemctl could not enable greetd -- another display manager may hold tty1"; acting=0; return 0; }
            login_record greetd.on
        fi
        if unit_enabled getty@tty1.service; then root_do systemctl disable getty@tty1.service >/dev/null 2>&1 && login_record getty.off; fi
    else
        printf 'on\n' > "$TMP/login/boot"
        root_put "$TMP/login/boot" "$ROOT/$LOGIN_ETC/boot"
        login_line > "$TMP/line"; echo >> "$TMP/line"
        { [ -f "$ROOT/etc/rc.local" ] || printf '#!/bin/sh\n'; marked_text "$ROOT/etc/rc.local" "$LOGIN_MARK" "$TMP/line" exit; } > "$TMP/rc.local"
        root_put "$TMP/rc.local" "$ROOT/etc/rc.local" 0755
    fi
    ok login "the login screen takes tty1 from the next boot (tty2 keeps the console login)"
}
login_follow() {   # theme and wallpaper: the login screen takes the new look too, when it is on
    login_wanted || return 0
    theme_load; EXPR=$(render_expr)
    login_screen_apply
}
login_screen_off() {   # by the records alone: the boot back to getty, the screen's files gone once greetd stopped
    [ "$OS" != Darwin ] && login_screen_traces || return 0
    if [ "$MODE" = dry ]; then row would login "the console login on tty1 from the next boot, the login screen's files removed (sudo)"; return 0; fi
    login_root off || return 0
    if [ "$(init_shape)" = systemd ]; then
        # getty first: tty1 never loses its login
        if login_rec getty.off; then root_do systemctl enable getty@tty1.service >/dev/null 2>&1 && login_unrecord getty.off; fi
        if login_rec greetd.on; then root_do systemctl disable greetd.service >/dev/null 2>&1 && login_unrecord greetd.on; fi
        _pending=0
    else
        [ ! -d "$ROOT/$LOGIN_ETC" ] || { printf 'off\n' > "$TMP/boot"; root_put "$TMP/boot" "$ROOT/$LOGIN_ETC/boot"; }
        _pending=0; if login_rec getty.off || login_rec greetd.on; then _pending=1; fi
    fi
    if login_rec seatd.group; then
        if ! in_group _seatd "$LOGIN_ACCOUNT" || root_do gpasswd -d "$LOGIN_ACCOUNT" _seatd >/dev/null 2>&1; then login_unrecord seatd.group; fi
    fi
    root_do rm -f "$ROOT/$LOGIN_SUDOERS"
    if greetd_live || [ "$_pending" = 1 ]; then
        row todo login "the login screen runs until the next boot, then tty1 has the console login -- spark-shell off login again after it removes the rest"; acting=0
        return 0
    fi
    if [ -e "$ROOT/$GREETD_CONF.spark-shell-orig" ]; then root_do mv "$ROOT/$GREETD_CONF.spark-shell-orig" "$ROOT/$GREETD_CONF"
    elif greetd_ours; then root_do rm -f "$ROOT/$GREETD_CONF"; fi
    _line=$(marked "$ROOT/etc/rc.local" "$LOGIN_MARK")
    if [ -n "$_line" ]; then
        marked_text "$ROOT/etc/rc.local" "$LOGIN_MARK" > "$TMP/rc.local"
        if [ "$(cat "$TMP/rc.local")" = '#!/bin/sh' ]; then root_do rm -f "$ROOT/etc/rc.local"   # the one spark-shell made
        else root_put "$TMP/rc.local" "$ROOT/etc/rc.local"; fi
    fi
    for f in $LOGIN_FILES wallpaper boot; do root_do rm -f "$ROOT/$LOGIN_ETC/$f"; done
    for _t in $POINTER_THEMES; do root_do rm -rf "$ROOT/$LOGIN_ICONS/$_t"; done
    root_do rm -rf "$ROOT/$LOGIN_FONTS"
    root_do rm -f "$ROOT/$LOGIN_LIB/spark-dialog" "$ROOT/$LOGIN_LIB/login-boot"
    for d in "$LOGIN_ETC" etc/spark-shell "$LOGIN_LIB"; do [ ! -d "$ROOT/$d" ] || root_do rmdir "$ROOT/$d" 2>/dev/null || true; done
    row ok login "the console login is back on tty1 from the next boot, the login screen's files are gone (its package stays)"
}

render_all() {
    theme_load
    EXPR=$(render_expr)
    for rel in $RENDERED; do
        render_one "$REPO/template/$rel" "$HOME/$rel"
    done
    prompt_render
    if desktop_wanted; then desktop_apply; fi
}

hand_back() {   # hand_back REL... -- each render of ours under HOME (marker or.bak) restored
    for rel in "$@"; do
        p=$HOME/$rel
        if [ -f "$p" ] && [ ! -L "$p" ]; then
            if grep -q 'rendered by spark-shell' "$p" 2>/dev/null || [ -e "$p.bak" ]; then
                restore_one "$p"
            fi
        fi
    done
}
restore_one() {   # restore_one PATH --.bak back, or gone; never a husk
    [ -e "$1" ] || [ -L "$1" ] || return 0
    rm -f "$1"
    if [ -e "$1.bak" ] || [ -L "$1.bak" ]; then
        mv "$1.bak" "$1"
        row ok restore "$1 -- back from ${1##*/}.bak"
    else
        row ok restore "$1 -- removed (no ${1##*/}.bak: there was no file before)"
    fi
}

tmux_reload() {
    command -v tmux >/dev/null 2>&1 || return 0
    tmux list-sessions >/dev/null 2>&1 || return 0
    if [ -f "$HOME/.tmux.conf" ]; then
        # what a source-file cannot unset: an older render's console
        # hook and its appended truecolor override
        tmux set-hook -gu client-attached >/dev/null 2>&1 || true
        tmux set -gu terminal-overrides >/dev/null 2>&1 || true
        tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 || true
        row ok tmux "reloaded (~/.tmux.conf)"
    fi
}

