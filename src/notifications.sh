# shellcheck extended-analysis=false
# --- the notifications
# sets: NOTIFY_MODE NOTIFY_SEEN
# reads: MODE STATE_DIR TMP US
NOTIFY_MODE=do-not-disturb
mako_here() { [ -z "${SPARK_SHELL_NO_MAKO:-}" ] && command -v mako >/dev/null 2>&1; }   # SPARK_SHELL_NO_MAKO: for the tests
notify_mode() { read_once notify.mode makoctl mode; }   # -> the modes on
notify_up() { command -v makoctl >/dev/null 2>&1 && notify_mode >/dev/null 2>&1; }
notify_reload() { ! notify_up || makoctl reload >/dev/null 2>&1 || :; }
notify_dnd() { read_once notify.dnd notify_dnd_now; }
notify_dnd_now() { notify_mode 2>/dev/null | grep -qx "$NOTIFY_MODE"; }
notify_anchor() { if [ "$DESKTOP_BAR" = yes ] && [ "$BAR_POSITION" = bottom ]; then echo bottom-right; else echo top-right; fi; }
# the ids looked at; mako's ids restart with the session
NOTIFY_SEEN=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; NOTIFY_SEEN=${NOTIFY_SEEN:-$STATE_DIR}/notify-seen
notify_ids() { { notify_list list; notify_list history; } | cut -d "$US" -f1 | grep -x '[0-9][0-9]*' | sort -un || :; }   # -> mako's ids, one a line
notify_unseen() {   # -> how many nobody looked at
    notify_ids > "$TMP/notify.ids"
    if [ -s "$NOTIFY_SEEN" ]; then grep -cvxFf "$NOTIFY_SEEN" "$TMP/notify.ids" || :; else grep -c . "$TMP/notify.ids" || :; fi
}
notify_seen() {   # notify_seen [ID...] -- looked at, all by default
    notify_up || return 0
    mkdir -p "$(dirname "$NOTIFY_SEEN")" 2>/dev/null || return 0
    notify_ids > "$TMP/notify.ids"
    if [ $# -eq 0 ]; then cp "$TMP/notify.ids" "$NOTIFY_SEEN.new"
    else { cat "$NOTIFY_SEEN" 2>/dev/null || :; printf '%s\n' "$@"; } | grep -xFf "$TMP/notify.ids" | sort -un > "$NOTIFY_SEEN.new" || :; fi
    mv -f "$NOTIFY_SEEN.new" "$NOTIFY_SEEN"; bar_redraw
}
notify_bus() { [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; }   # its own bus, or logind's
notify_keep() {   # do not disturb as configured, once mako answers
    [ "$DO_NOT_DISTURB" = yes ] && command -v makoctl >/dev/null 2>&1 || return 0
    _nk=0; while [ "$_nk" -lt 20 ] && ! makoctl mode >/dev/null 2>&1; do sleep 0.25; _nk=$((_nk + 1)); done
    makoctl mode -a "$NOTIFY_MODE" >/dev/null 2>&1 || :
}
notify_start() {   # on desktop's notify row
    [ "$MODE" = apply ] && mako_here && notify_bus && layout_in_sway || return 0
    ! notify_up || return 0
    swaymsg -- exec mako >/dev/null 2>&1 || return 0
    ok notify "the notifications show now"
}
notify_list() { read_once "notify.$1" notify_list_now "$1"; }   # notify_list list|history -> ID US APP US SUMMARY, newest first; mako 1.7 and 1.8: JSON
notify_list_now() {
    _nlo=$(makoctl "$1" 2>/dev/null) || return 0
    case $_nlo in
        '{'*) printf '%s\n' "$_nlo" | jq -r '.data[0][]? | [(.id.data // 0 | tostring), (."app-name".data // ""), (.summary.data // "")] | @tsv' 2>/dev/null || : ;;
        *)
        awk '/^Notification [0-9]+:/ { if (id != "") print id "\t" app "\t" sum; id = $2; sub(/:$/, "", id); sum = $0; sub(/^Notification [0-9]+: ?/, "", sum); gsub(/\t/, " ", sum); app = ""; next }
            /^  App name: / { app = $0; sub(/^  App name: /, "", app); gsub(/\t/, " ", app) }
            END { if (id != "") print id "\t" app "\t" sum }' <<NOTIFY
$_nlo
NOTIFY
        ;;
    esac | scrub_text | awk -F '\t' -v OFS='\037' '{ $1 = $1; print }'   # scrubbed first: the scrubber drops US
}
notify_send() {   # notify_send CATEGORY SUMMARY [BODY] -- mako's config reads the category
    [ -n "${WAYLAND_DISPLAY:-}" ] && command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a spark-shell -c "$1" -- "$2" "${3:-}" >/dev/null 2>&1 </dev/null || :
}
notify_why() {
    if ! mako_here; then echo "mako is not installed (spark-shell on desktop)"
    elif ! notify_bus; then echo "no session bus yet: notifications start at your next login"
    else echo "the notifications are not running: they start at your next login"; fi
}
notify_act() {   # notify_act do-not-disturb on|off | dismiss | restore -> one line
    notify_up || { notify_why; return 1; }
    case $1 in
        do-not-disturb) case ${2:-} in
                on) makoctl mode -a "$NOTIFY_MODE" >/dev/null 2>&1 || { echo "mako did not take do not disturb"; return 1; }; config_set DO_NOT_DISTURB yes >/dev/null; DO_NOT_DISTURB=yes
                    echo "do not disturb on: notifications wait out of sight" ;;
                off) makoctl mode -r "$NOTIFY_MODE" >/dev/null 2>&1 || { echo "mako did not take do not disturb"; return 1; }; config_set DO_NOT_DISTURB no >/dev/null; DO_NOT_DISTURB=no
                    echo "do not disturb off" ;;
                *) echo "do-not-disturb takes on or off"; return 1 ;;
            esac
            bar_redraw ;;
        dismiss) makoctl dismiss -a >/dev/null 2>&1 || { echo "nothing to dismiss"; return 1; }; notify_seen; echo "dismissed" ;;
        restore) [ -n "$(notify_list history)" ] || { echo "nothing in the history"; return 1; }
            makoctl restore >/dev/null 2>&1 || { echo "mako did not show it again"; return 1; }; echo "the last one is on the screen again" ;;
        *) echo "$1 is not something notifications does"; return 1 ;;
    esac
}

