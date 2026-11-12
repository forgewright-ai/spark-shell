# shellcheck extended-analysis=false
# the seat on Void: no logind, so sway takes the screen through seatd (a
# sets: SEATD_LINK SEATD_SV
# reads: DISTRO OS ROOT STATE_DIR
# runit service, group _seatd). STATE_DIR records the steps spark-shell
# took; off undoes those, and leaves seatd while a desktop runs
SEATD_SV=etc/sv/seatd
SEATD_LINK=var/service/seatd
seat_needed() { [ "$OS" != Darwin ] && [ "$DISTRO" = void ]; }
in_group() {   # in_group GROUP USER -- USER is a member of GROUP in /etc/group
    awk -F: -v g="$1" -v u="$2" '$1 == g { n = split($4, m, ","); for (i = 1; i <= n; i++) if (m[i] == u) f = 1 } END { exit !f }' "$ROOT/etc/group" 2>/dev/null
}
seatd_on() { [ -e "$ROOT/$SEATD_LINK" ] || [ -L "$ROOT/$SEATD_LINK" ]; }
seat_ready() { seatd_on && in_group _seatd "$(id -un)"; }
desktop_running() { [ -n "${WAYLAND_DISPLAY:-}" ] || wm_running_any; }
seat_root() {   # seat_root VERB [FOR] -- a root to write with, asked once; else a todo row and false
    if ! root_can; then row todo desktop "root is needed for ${2:-seatd} -- spark-shell $1 desktop at a terminal (sudo once)"; acting=0; return 1; fi
    root_sudo_once "${2:-seatd} for the desktop" || { row todo desktop "sudo refused -- spark-shell $1 desktop at a terminal (sudo once)"; acting=0; return 1; }
}
seat_apply() {
    seat_needed || return 0
    if [ ! -d "$ROOT/$SEATD_SV" ]; then
        need desktop "seatd at every boot and you in its group, once the packages are in (sudo)" || return 0
        row todo desktop "seatd is not installed -- spark-shell on desktop (the packages)"; acting=0; return 0
    fi
    _me=$(id -un)
    if seatd_on; then ok desktop "seatd starts at every boot (/$SEATD_LINK)"
    elif need desktop "seatd: link /$SEATD_SV into /var/service, it starts now and at every boot (sudo)" && seat_root on; then
        if root_do ln -s "/$SEATD_SV" "$ROOT/$SEATD_LINK"; then
            mkdir_private "$STATE_DIR"; : > "$STATE_DIR/seatd.linked"
            ok desktop "seatd runs now and at every boot"
        else row todo desktop "the link /$SEATD_LINK failed -- spark-shell on desktop again"; acting=0; fi
    fi
    if in_group _seatd "$_me"; then ok desktop "$_me is in the _seatd group"
    elif ! grep -q '^_seatd:' "$ROOT/etc/group" 2>/dev/null; then row todo desktop "there is no _seatd group: the seatd package makes it -- spark-shell on desktop"
    elif need desktop "add $_me to the _seatd group (sudo)" && seat_root on; then
        if root_do usermod -aG _seatd "$_me"; then
            mkdir_private "$STATE_DIR"; : > "$STATE_DIR/seatd.group"
            ok desktop "$_me is in the _seatd group now: it takes effect at your next login"
        else row todo desktop "usermod could not add $_me to _seatd -- spark-shell on desktop again"; acting=0; fi
    fi
}
seat_off() {   # by the records alone: the link spark-shell made, the membership it added
    [ -e "$STATE_DIR/seatd.linked" ] || [ -e "$STATE_DIR/seatd.group" ] || return 0
    need desktop "seatd's link and your _seatd membership removed, as spark-shell made them (sudo)" || return 0
    _keep=0
    if [ -e "$STATE_DIR/seatd.linked" ] && desktop_running; then
        _keep=1
        row todo desktop "seatd stays while a desktop runs (stopping it would end the desktop) -- spark-shell off desktop again after leaving it"; acting=0
    fi
    seat_root off || return 0
    _me=$(id -un)
    if [ "$_keep" = 0 ] && [ -e "$STATE_DIR/seatd.linked" ]; then
        if [ ! -L "$ROOT/$SEATD_LINK" ] || root_do rm -f "$ROOT/$SEATD_LINK"; then
            rm -f "$STATE_DIR/seatd.linked"
            row ok desktop "seatd no longer starts at boot (the link spark-shell made is gone)"
        else row todo desktop "the link /$SEATD_LINK stays -- spark-shell off desktop again"; fi
    fi
    if [ -e "$STATE_DIR/seatd.group" ]; then
        if ! in_group _seatd "$_me" || root_do gpasswd -d "$_me" _seatd >/dev/null 2>&1; then
            rm -f "$STATE_DIR/seatd.group"
            row ok desktop "$_me is out of the _seatd group spark-shell added: it takes effect at your next login"
        else row todo desktop "gpasswd could not take $_me out of _seatd -- spark-shell off desktop again"; fi
    fi
}

