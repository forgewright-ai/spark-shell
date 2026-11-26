# shellcheck extended-analysis=false
# --- the notifications
# sets: NOTIFY_NAME NOTIFY_OWN
# reads: MODE OS REPO SPARKBAR_NOTIFY STATE_DIR TMP US
# spark-shell's own server (lib/notifications.py) holds the notifications' name on the session bus. It keeps the list
# and writes it to one state file, and spark-bar notifications draws what pops up. sway starts it at login, and the
# bus when a program notifies and none runs (the service file on desktop renders). This module is the rest of
# spark-shell's door to it: the list read from the state file, a step asked over the bus. The look and do not
# disturb go the other way, in a file of KEY=value lines the server reads at its start and when told to
NOTIFY_NAME=org.freedesktop.Notifications
NOTIFY_OWN=ai.forgewright.SparkShell.Notifications   # the server's own methods, beside the standard ones
notify_file() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-notifications.$1"; }   # notify_file state|look|log -> the server's file of that kind, in the runtime folder
notify_here() { [ -z "${SPARK_SHELL_NO_NOTIFY:-}" ] && command -v python3 >/dev/null 2>&1 && command -v dbus-send >/dev/null 2>&1; }   # what the server and a step take; SPARK_SHELL_NO_NOTIFY: for the tests
notify_bus() { [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; }   # its own bus, or logind's
notify_up() { notify_here && notify_bus; }   # they can show: the bus starts the server at the first one
notify_stat() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d ' ' -f 1,20; }   # notify_stat PID -> its state's letter and the clock tick it started at (with its pid, that process and no later one); nothing with no such process
notify_runs() { case $(notify_stat "$1") in ''|Z*) return 1 ;; esac; }   # notify_runs PID: it runs. One that ended and waits for its parent to take its end does not
notify_pid() {   # -> the running server's pid, from its state file; false when none runs: no pid there, a server that ended, or the pid is another process now
    _npf=$(notify_file state); [ -s "$_npf" ] || return 1
    _npp=$(jq -r '"\(.pid // "") \(.born // "")"' "$_npf" 2>/dev/null) || return 1
    _npb=${_npp#* }; _npp=${_npp%% *}
    case $_npp in ''|*[!0-9]*) return 1 ;; esac
    _nps=$(notify_stat "$_npp"); case $_nps in ''|Z*) return 1 ;; esac
    [ -n "$_npb" ] && [ "${_nps#* }" = "$_npb" ] || return 1
    printf '%s\n' "$_npp"
}
notify_draws() { [ "$(jq -r '.drawer' "$(notify_file state)" 2>/dev/null)" = true ]; }   # the server has a drawer: what comes pops up
notify_call() {   # notify_call INTERFACE.METHOD [ARG...] -> the answer's last line; false when no server of ours runs, or it does not answer in three seconds
    notify_pid >/dev/null || return 1
    _ncr=$(dbus-send --session --print-reply --reply-timeout=3000 --dest="$NOTIFY_NAME" /org/freedesktop/Notifications "$@" 2>/dev/null) || return 1
    printf '%s\n' "$_ncr" | tail -1
}
notify_owner() {   # -> the pid and the name of the program that holds the notifications' name on the bus; nothing when none does
    _nop=$(dbus-send --session --print-reply --reply-timeout=3000 --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID "string:$NOTIFY_NAME" 2>/dev/null | sed -n 's/^ *uint32 \([0-9][0-9]*\)$/\1/p') || return 0
    [ -z "$_nop" ] || printf '%s %s\n' "$_nop" "$(cat "/proc/$_nop/comm" 2>/dev/null || echo another program)"
}
notify_dnd() { [ "$(bar_style DO_NOT_DISTURB "${DO_NOT_DISTURB:-no}" | tr -d '"')" = yes ]; }   # the config's word now: a loop that runs for hours reads it at each line
notify_anchor() { if [ "$DESKTOP_BAR" = yes ] && [ "$BAR_POSITION" = bottom ]; then echo bottom; else echo top; fi; }   # the corner by the bar
# the look the server hands its drawer, and do not disturb: the dialog's ground and the palette's text in the bar's
# face at the text's own size, a card thirty cells wide with half the dialog's air, the bar's motion
notify_look() {
    _nls=$(look_font_size); : "${_nls:=12}"
    _nld=no; ! notify_dnd || _nld=yes
    printf 'fg=%s\naccent=%s\nmuted=%s\nground=%s\nlit=%s\nalert=%s\nfont=%s\nwidth=%s\npad_x=%s\npad_y=%s\nanchor=%s\nmotion=%s\ndnd=%s\n' \
        "$HEX_FG" "$HEX_ACCENT" "$PANEL_MUTED" "$PANEL_BG" "$PANEL_HI" "$HEX_ANSI_1" "$(bar_font "$(font_spec)")" "$((_nls * 30))" "$((_nls * 3 / 2))" "$_nls" "$(notify_anchor)" "$(bar_style BAR_MOTION yes | tr -d '"')" "$_nld"
}
notify_reload() {   # a new look, or do not disturb changed: the file written again and a server that runs told to read it; nothing when the file says the same
    notify_pid >/dev/null || return 0
    [ -n "${HEX_FG:-}" ] && [ -n "${PANEL_BG:-}" ] || theme_load 2>/dev/null || return 0   # a verb that read no palette yet
    notify_look > "$TMP/notify.look" 2>/dev/null || return 0
    ! cmp -s "$TMP/notify.look" "$(notify_file look)" || return 0
    cp "$TMP/notify.look" "$(notify_file look)" 2>/dev/null && notify_call "$NOTIFY_OWN.Reload" >/dev/null || :
}
# desktop notifications start [--bus]: the server for this desktop. sway starts it at login, and on desktop in a
# session that had none: in a session of its own, so it outlives the command that started it. --bus is the session
# bus's, when a program notifies and none runs: the bus waits for the name, and some end what they started when its
# command leaves (dbus-broker), so the server is then this very process. The bus knows no desktop: with none in its
# environment this asks sway to start the server, and leaves once it is up. With no sway the server runs all the
# same and keeps the list; nothing pops up. A server that a desktop before this one left ends first
notify_serve() {   # notify_serve [--bus] -> false when the bus asked and no server came of it
    if [ "$OS" = Darwin ] || ! notify_up; then case ${1:-} in --bus) return 1 ;; esac; return 0; fi
    if _nsr=$(notify_pid); then
        notify_stale "$_nsr" || return 0
        notify_stop
    fi
    if [ -z "${WAYLAND_DISPLAY:-}" ] && _nsp=$(wm_pid) && [ -n "$_nsp" ] && [ -S "$(wm_socket_of "$_nsp")" ]; then
        wm_exec_at "$(wm_socket_of "$_nsp")" "$REPO/spark-shell desktop notifications start" >/dev/null 2>&1 || :
        case ${1:-} in --bus) notify_wait || return 1 ;; esac
        return 0
    fi
    theme_load 2>/dev/null || :
    _nsd=''; [ -z "${WAYLAND_DISPLAY:-}" ] || _nsd=$(sparkbar_cmd 2>/dev/null) || _nsd=''
    mkdir_private "$STATE_DIR"
    notify_look > "$(notify_file look)" || { case ${1:-} in --bus) return 1 ;; esac; return 0; }
    case ${1:-} in --bus)
        rm -rf "$TMP"   # no end of this shell comes after the exec to remove it
        exec python3 "$REPO/lib/notifications.py" "$(notify_file state)" "$(notify_file look)" ${_nsd:+"$_nsd" "$SPARKBAR_NOTIFY"} </dev/null >/dev/null 2>"$(notify_file log)" ;;
    esac
    if command -v setsid >/dev/null 2>&1; then setsid python3 "$REPO/lib/notifications.py" "$(notify_file state)" "$(notify_file look)" ${_nsd:+"$_nsd" "$SPARKBAR_NOTIFY"} </dev/null >/dev/null 2>"$(notify_file log)" &
    else ( trap '' HUP; exec python3 "$REPO/lib/notifications.py" "$(notify_file state)" "$(notify_file look)" ${_nsd:+"$_nsd" "$SPARKBAR_NOTIFY"} ) </dev/null >/dev/null 2>"$(notify_file log)" & fi
}
notify_wait() { _nwn=0; until notify_pid >/dev/null; do [ "$_nwn" -lt 50 ] || return 1; sleep 0.1; _nwn=$((_nwn + 1)); done; }   # five seconds at most for a server asked for to be up
notify_stale() {   # notify_stale PID -> true for a server that cannot draw on this desktop: one started under another compositor (a login before this one), or with no drawer where one runs now
    [ -n "${WAYLAND_DISPLAY:-}" ] || return 1
    [ "$(tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p')" = "$WAYLAND_DISPLAY" ] || return 0
    ! notify_draws && sparkbar_cmd >/dev/null 2>&1
}
notify_stop() {   # the server of ours ends and the name is free: at the desktop's end, at off, before one for a new desktop. Three seconds at most
    _nxp=$(notify_pid) || return 0
    kill "$_nxp" 2>/dev/null || return 0
    _nxn=0; while notify_runs "$_nxp" && [ "$_nxn" -lt 30 ]; do sleep 0.1; _nxn=$((_nxn + 1)); done
}
notify_off() {   # off, off desktop: the server ends with the desktop's files, and the name is free for a program of yours
    notify_pid >/dev/null || return 0
    if [ "$MODE" = dry ]; then row would notify "the notifications' server ended"; return 0; fi
    notify_stop; row ok notify "the notifications' server ended"
}
# on desktop's notify row: what v0.169 left of mako goes, and the server is up in a session that runs, with no login.
# Another program that holds the name is yours, and stays
notify_apply() {
    notify_mako_off
    [ "$MODE" = apply ] && notify_up && wm_up || return 0
    ! notify_pid >/dev/null || return 0
    [ -z "$(notify_owner)" ] || return 0
    wm_exec "$REPO/spark-shell desktop notifications start" >/dev/null 2>&1 || return 0
    ok notify "the notifications show now"
}
# before v0.170 mako drew them, by a config spark-shell rendered. That render is handed back, and the mako that
# runs by it ends, a second at most for the name to be free. A mako with a config of your own is yours: it stays,
# and shows them
notify_mako_off() {
    [ -f "$HOME/.config/mako/config" ] && grep -q 'rendered by spark-shell' "$HOME/.config/mako/config" 2>/dev/null || return 0
    changes=$((changes + 1))
    if [ "$MODE" = dry ]; then row would notify "mako's config, rendered before v0.170, handed back"; return 0; fi
    _nmo=$(notify_owner)
    case ${_nmo#* } in mako)
        kill "${_nmo%% *}" 2>/dev/null || :
        _nmn=0; while [ -n "$(notify_owner)" ] && [ "$_nmn" -lt 10 ]; do sleep 0.1; _nmn=$((_nmn + 1)); done ;;
    esac
    hand_back .config/mako/config
    row render notify "mako's config, rendered before v0.170, handed back: spark-shell's own server shows the notifications"
}
notify_hush() { notify_pid >/dev/null && [ "$(jq -r '.paused' "$(notify_file state)" 2>/dev/null)" = false ] && notify_call "$NOTIFY_OWN.Pause" >/dev/null; }   # the idle screen is up: what would pop up waits. True when it was not held and is now
notify_unhush() { notify_call "$NOTIFY_OWN.Resume" >/dev/null || :; }   # the person is back: what waited shows
notify_list() { read_once "notify.$1" notify_list_now "$1"; }   # notify_list list|history -> ID US APP US SUMMARY, newest first: the ones on the screen, or the last ten that left it
notify_list_now() {
    _nlk=shown; [ "$1" != history ] || _nlk=history
    notify_pid >/dev/null || return 0
    jq -r --arg k "$_nlk" '.[$k][]? | [(.id | tostring), (.app // ""), (.summary // "") | gsub("[\t\n\r]"; " ")] | join("\t")' "$(notify_file state)" 2>/dev/null \
        | scrub_text | awk -F '\t' -v OFS='\037' '{ $1 = $1; print }'   # scrubbed first: the scrubber drops US
}
notify_unseen() { if notify_pid >/dev/null; then jq -r '.unseen // 0' "$(notify_file state)" 2>/dev/null || echo 0; else echo 0; fi; }   # -> how many nobody looked at
notify_seen() {   # notify_seen [ID...] -- looked at, all by default (an id of 0 says every one)
    _nsi=$(printf '%s' "$*" | tr -cs '0-9' ','); _nsi=${_nsi#,}; _nsi=${_nsi%,}
    notify_call "$NOTIFY_OWN.Seen" "array:uint32:${_nsi:-0}" >/dev/null || return 0
    bar_redraw
}
# notify_send CATEGORY SUMMARY [BODY [PLACE WORDS]] -- one of spark-shell's own. With PLACE, a click on it opens home
# there, and WORDS say so on the card: notify-send waits for the click or the card's end, so it runs in a session of
# its own and who sent it goes on. One too old to offer an action sends the card alone
notify_send() {
    [ -n "${WAYLAND_DISPLAY:-}" ] && command -v notify-send >/dev/null 2>&1 || return 0
    if [ -z "${4:-}" ]; then notify-send -a spark-shell -c "$1" -- "$2" "${3:-}" >/dev/null 2>&1 </dev/null || :; return 0; fi
    _nsc='k=$(notify-send -a spark-shell -c "$1" -A "default=$5" -- "$2" "$3" 2>/dev/null) || { notify-send -a spark-shell -c "$1" -- "$2" "$3"; exit 0; }; [ "$k" != default ] || exec "$0" desktop home "$4"'
    if command -v setsid >/dev/null 2>&1; then setsid sh -c "$_nsc" "$REPO/spark-shell" "$1" "$2" "${3:-}" "$4" "${5:-open it}" </dev/null >/dev/null 2>&1 &
    else ( trap '' HUP; exec sh -c "$_nsc" "$REPO/spark-shell" "$1" "$2" "${3:-}" "$4" "${5:-open it}" ) </dev/null >/dev/null 2>&1 & fi
}
notify_other() {   # -> the program that shows the notifications when it is not spark-shell's server; nothing when ours does, or none does yet: the bus starts ours at the first one
    ! notify_pid >/dev/null || return 0
    _noo=$(notify_owner); case ${_noo#* } in ''|python3*) ;; *) printf '%s\n' "${_noo#* }" ;; esac   # python3: our own, on its way up
}
notify_why() {   # -> why none shows, or who shows them when it is not spark-shell
    if ! notify_here; then echo "python3 or dbus-send is not installed (spark-shell on desktop)"
    elif ! notify_bus; then echo "no session bus yet: notifications start at your next login"
    else echo "$(notify_other) shows the notifications here, not spark-shell"; fi
}
notify_act() {   # notify_act do-not-disturb on|off | dismiss | restore | open -> one line
    notify_up && [ -z "$(notify_other)" ] || { notify_why; return 1; }
    case $1 in
        do-not-disturb) case ${2:-} in
                on) config_set DO_NOT_DISTURB yes >/dev/null; DO_NOT_DISTURB=yes; notify_reload
                    echo "do not disturb on: notifications wait out of sight" ;;
                off) config_set DO_NOT_DISTURB no >/dev/null; DO_NOT_DISTURB=no; notify_reload
                    echo "do not disturb off" ;;
                *) echo "do-not-disturb takes on or off"; return 1 ;;
            esac
            bar_redraw ;;
        dismiss) _nai=$(notify_list_now list | cut -d "$US" -f1 | paste -sd, -); [ -n "$_nai" ] || { echo "nothing to dismiss"; return 1; }
            # by their ids, the ones the person saw: sent away by their own hand, so looked at, and their apps hear a person did it
            notify_call "$NOTIFY_OWN.Dismiss" "array:uint32:$_nai" >/dev/null || :
            bar_redraw; echo "dismissed" ;;
        restore) [ -n "$(notify_list_now history)" ] || { echo "nothing in the history"; return 1; }
            case $(notify_call "$NOTIFY_OWN.Restore") in
                *'boolean true') echo "the last one is on the screen again" ;;
                *) echo "the last one stays in the list: nothing pops up now"; return 1 ;;
            esac ;;
        open) [ -n "$(notify_list_now list)" ] && notify_call "$NOTIFY_OWN.Open" >/dev/null || { echo "nothing on the screen to open"; return 1; }
            echo "the notifications have the keys" ;;
        *) echo "$1 is not something notifications does"; return 1 ;;
    esac
}
