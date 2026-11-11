# shellcheck extended-analysis=false
# screen_x11_main -- the main screen as X11's primary (Wine takes it as its first screen;
# Xwayland names none); nothing without xrandr, Xwayland or a main screen
screen_x11_main() {
    [ -n "${DISPLAY:-}" ] && command -v xrandr >/dev/null 2>&1 || return 0
    _xm=$(screen_main); [ -n "$_xm" ] || return 0
    _xp=$(screen_rows | awk -F '\t' -v i="$_xm" '($2 == i || $1 == i) && $3 == "on" { print $1; exit }')
    [ -n "$_xp" ] || return 0
    ! xrandr --listmonitors 2>/dev/null | grep -qF " +*$_xp " || return 0   # named already
    xrandr --output "$_xp" --primary >/dev/null 2>&1 || :
}
# The layout's origin at 0,0: X11 has nothing left of or above 0, so an X11 window on a
# screen placed there takes no click; every screen moves by the same amount, kept in screens.conf
screen_origin() {   # -> the screens moved, one line each, or nothing when none sat left of or above 0
    screen_rows | awk -F '\t' '$3 == "on"' > "$TMP/origin"
    _sox=$(awk -F '\t' 'NR == 1 || $6 + 0 < m { m = $6 + 0 } END { print m + 0 }' "$TMP/origin")
    _soy=$(awk -F '\t' 'NR == 1 || $7 + 0 < m { m = $7 + 0 } END { print m + 0 }' "$TMP/origin")
    [ "$_sox" -lt 0 ] || [ "$_soy" -lt 0 ] || return 0
    [ "$_sox" -lt 0 ] || _sox=0; [ "$_soy" -lt 0 ] || _soy=0
    while IFS="$TAB" read -r _son _soi _ _ _ _sx _sy _; do
        _snx=$((_sx - _sox)); _sny=$((_sy - _soy))
        [ "$(awk -F '\t' -v i="$_soi" '$2 == i' "$TMP/origin" | grep -c .)" -eq 1 ] || _soi=$_son   # a name two screens share: the port's
        swaymsg -- output "\"$_soi\"" position "$_snx" "$_sny" >/dev/null 2>&1 || swaymsg -- output "$_son" position "$_snx" "$_sny" >/dev/null 2>&1 || continue
        mkdir -p "$CONFIG_DIR"
        { [ ! -f "$SCREENS_CONF" ] || grep -v -F -e "output \"$_soi\" position " -e '# rendered' "$SCREENS_CONF" || :; } > "$TMP/screens"
        { echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them'; grep . "$TMP/screens" || :; printf 'output "%s" position %s %s\n' "$_soi" "$_snx" "$_sny"; } > "$SCREENS_CONF"
        echo "$_son at $_snx,$_sny"
    done < "$TMP/origin"
}
desk_screen() {   # desk_screen [NAME [scale N | mode WxH | transform normal|90|180|270 | on | off | left-of|right-of|above|below OTHER]]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own display settings"
    desk_in_sway || refuse "changes the desktop's screens: run it inside it"
    if [ "${1:-}" = --ensure-visible ]; then
        if [ "$(screens_json | jq '[.[] | select(.active)] | length')" = 0 ]; then
            _first=$(screens_json | jq -r '.[0].name // empty')
            [ -z "$_first" ] || desk_screen "$_first" on
        fi
        screen_origin >/dev/null
        return 0
    fi
    if [ "${1:-}" = --x11-main ]; then screen_x11_main; return 0; fi
    if [ -z "${1:-}" ]; then
        screen_rows | while IFS="$TAB" read -r n id on m sc x y w h _mo tr; do
            _tw=''; [ "${tr:-normal}" = normal ] || _tw="  turned $tr"
            if [ "$on" = on ]; then echo "$n  ${id:-a screen}  $m  scale $sc  at $x,$y$_tw"; else echo "$n  ${id:-a screen}  off"; fi
        done; return 0
    fi
    _r=$(screen_find "$1"); [ -n "$_r" ] || refuse "no screen named $1 (spark-shell desktop screen lists them)"
    _n=$(printf '%s' "$_r" | cut -f1); _id=$(printf '%s' "$_r" | cut -f2); _kind=${2:-}   # the kind, kept: a place replaces the positional parameters
    [ "$(screen_rows | awk -F '\t' -v i="$_id" '$2 == i' | grep -c .)" -eq 1 ] || _id=$_n   # a name two screens share (no serial, the same model) would set both: the port's name instead
    case ${2:-} in
        scale) screen_scale_valid "${3:-}" || refuse "scale takes a positive decimal"
            _cmd="scale $3"; _said="$_n scale $3" ;;
        mode) screens_json | jq -e --arg n "$_n" --arg m "${3:-}" '.[] | select(.name == $n) | .modes[] | select("\(.width)x\(.height)" == $m or ("\(.width)x\(.height)@\((.refresh // 0) / 1000)Hz" == $m))' >/dev/null 2>&1 || refuse "$_n has no mode ${3:-}: $(screens_json | jq -r --arg n "$_n" '[.[] | select(.name == $n) | .modes[] | "\(.width)x\(.height)"] | unique | join(", ")')"
            _cmd="mode ${3}"; _said="$_n $3" ;;
        transform) case ${3:-} in normal|90|180|270) ;; *) refuse "transform takes normal, 90, 180 or 270 (clockwise); no mirrored orientation" ;; esac
            _cmd="transform $3"; if [ "$3" = normal ]; then _said="$_n upright"; else _said="$_n turned $3"; fi ;;
        main) [ "$(printf '%s' "$_r" | cut -f3)" = on ] || refuse "$_n is off: a screen off is no main one"
            screen_main_save "$_id"; swaymsg -- workspace 1 output "\"$_id\"" >/dev/null 2>&1 || :   # the next start's, and sway's now for a workspace 1 made anew
            login_screens_follow; screen_x11_main
            echo "$_n is the main screen: workspace 1 and the login screen go to it from the next start"; return 0 ;;
        on) _cmd=enable; _said="$_n on" ;;
        off) [ "$(screen_rows | awk -F '\t' '$3 == "on"' | grep -c .)" -gt 1 ] || refuse "$_n is the only screen on: it stays on"
            _cmd=disable; _said="$_n off" ;;
        position) printf '%s\n' "${3:-}" "${4:-}" | awk 'BEGIN {ok=1} !/^-?[0-9]+$/ || $0 < -65535 || $0 > 65535 {ok=0} END {exit !ok}' || refuse "position takes two whole coordinates, -65535 to 65535"
            _cmd="position $3 $4"; _said="$_n at $3,$4" ;;
        left-of|right-of|above|below)
            _o=$(screen_find "${3:-}"); [ -n "$_o" ] || refuse "no screen named ${3:-} (spark-shell desktop screen lists them)"
            [ "$(printf '%s' "$_o" | cut -f3)" = on ] || refuse "the other screen is off"
            [ "$(printf '%s' "$_o" | cut -f1)" != "$_n" ] || refuse "a screen is not placed beside itself"
            # shellcheck disable=SC2046   # six numbers, split on purpose
            set -- "$2" $(printf '%s' "$_o" | cut -f6-9) $(printf '%s' "$_r" | cut -f8-9)   # SIDE OX OY OW OH W H
            case $1 in left-of) _x=$(($2 - $6)); _y=$3 ;; right-of) _x=$(($2 + $4)); _y=$3 ;; above) _x=$2; _y=$(($3 - $7)) ;; *) _x=$2; _y=$(($3 + $5)) ;; esac
            _cmd="position $_x $_y"; _said="$_n $1 $(printf '%s' "$_o" | cut -f1)" ;;
        *) refuse "screen NAME takes scale N, mode WxH, transform normal|90|180|270, on, off, main, or left-of, right-of, above or below another screen" ;;
    esac
    swaymsg -- output "\"$_id\"" "$_cmd" >/dev/null 2>&1 || swaymsg -- output "$_n" "$_cmd" >/dev/null 2>&1 || refuse "sway refused: output $_n $_cmd"
    case $_kind in left-of|right-of|above|below) _oi=$(printf '%s' "$_o" | cut -f2); [ "$(screen_rows | awk -F '\t' -v i="$_oi" '$2 == i' | grep -c .)" -eq 1 ] || _oi=$(printf '%s' "$_o" | cut -f1); screen_save "$_id" "$_cmd" "$_kind" "$_oi" ;;
        *) screen_save "$_id" "$_cmd" ;; esac
    [ "$_kind" != transform ] || screen_beside_again "$_id"   # its width changed: the screens placed beside it, and it beside another, placed again
    screen_origin > "$TMP/origin.said"
    login_screens_follow
    desk_refit_soon   # another size or place: the windows the keys placed take their places on it
    echo "$_said"
    [ ! -s "$TMP/origin.said" ] || echo "every screen moved by the same amount, so none sits left of or above 0 (X11 apps take clicks there)"
}

# Notifications, storage and power
desk_notifications() {   # desk_notifications [do-not-disturb on|off | dismiss | restore]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own notifications"
    case ${1:-} in
        '') notify_up || { notify_why; return 0; }
            if notify_dnd; then echo "do not disturb on"; else echo "do not disturb off"; fi
            notify_list history | while IFS="$US" read -r _ni _na _ns; do echo "  ${_na:-an app}: $_ns"; done ;;
        do-not-disturb) case ${2:-} in on|off) ;; *) refuse "do-not-disturb takes on or off" ;; esac
            notify_act do-not-disturb "$2" || exit 1 ;;
        dismiss|restore) notify_act "$1" || exit 1 ;;
        *) refuse "notifications takes do-not-disturb on|off, dismiss or restore" ;;
    esac
}
desk_storage() {   # desk_storage [mount|unmount|open|eject NAME]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own Finder"
    case ${1:-} in
        '') storage_list > "$TMP/storage.l"
            [ -s "$TMP/storage.l" ] || echo "no drive plugged in"
            while IFS="$US" read -r _sk _sn _sd _ss _sm _sdr _sf; do
                if [ "$_sk" = drive ]; then echo "$_sn  $(files_size "$_ss")"
                elif [ -n "$_sm" ]; then echo "  $_sn  mounted at $_sm"
                else echo "  $_sn  $(files_size "$_ss")"; fi
            done < "$TMP/storage.l"
            _sh=$(storage_here); [ -z "$_sh" ] || echo "this computer  $_sh" ;;
        mount|unmount|open|eject) [ -n "${2:-}" ] || refuse "$1 takes a drive's name (spark-shell desktop storage lists them)"
            _sa=$1; shift; storage_act "$_sa" "$*" || exit 1 ;;
        *) refuse "storage takes mount, unmount, open or eject, and a drive's name" ;;
    esac
}
desk_power() {   # desk_power [lock|suspend|logout|restart|shutdown]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own power menu"
    case ${1:-} in
        '') _pu=$(power_up); [ -z "$_pu" ] || echo "$_pu"
            _pt=$(power_tool)
            if [ -z "$_pt" ]; then power_why
            elif power_sleeps; then echo "suspend, restart and shut down from the dialog"
            else echo "restart and shut down from the dialog; this machine cannot suspend"; fi
            power_keys ;;
        lock|suspend|logout|restart|shutdown) power_now "$1" || exit 1 ;;
        *) refuse "power takes lock, suspend, logout, restart or shutdown" ;;
    esac
}

# desk_lock -- swaylock over the wallpaper, in the palette; a lock already up stays
desk_lock() {
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own lock"
    [ -n "${WAYLAND_DISPLAY:-}" ] || refuse "locks the desktop: run it inside it (Super+Escape)"
    command -v swaylock >/dev/null 2>&1 || refuse "swaylock is not installed (spark-shell on desktop)"
    ! pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1 || return 0
    : "${HEX_BG:=242424}" "${HEX_FG:=ffffff}" "${HEX_ACCENT:=24acd4}" "${HEX_MUTED:=616161}" "${HEX_ANSI_1:=f62b5a}" "${HEX_ANSI_3:=e3c401}"   # foot's own, when the palette did not load
    if wall_there; then set -- --image "$(wall_path)" --scaling fill
    elif [ "$WALLPAPER" = default ]; then set -- --color "$(wall_ground | tr -d '#')"
    elif wall_color; then set -- --color "$(wall_hex "$WALLPAPER" | tr -d '#')"
    else set -- --color "$HEX_BG"; fi
    # the inside at 90% of the background, the layout box on it too:
    # swaylock's own box is black, and a light palette's dark text vanished on it
    _in=${HEX_BG}e6
    rm -rf "$TMP"; trap - EXIT
    _sz=$(look_font_size); : "${_sz:=12}"; _fs=$(font_spec)
    exec swaylock --daemonize "$@" --font "${_fs%%:*}" --font-size $((_sz * 5 / 3)) --indicator-radius 72 --indicator-thickness 6 --show-failed-attempts \
        --inside-color "$_in" --ring-color "$HEX_ACCENT" --key-hl-color "$HEX_FG" --bs-hl-color "$HEX_ANSI_1" --text-color "$HEX_FG" \
        --line-color 00000000 --separator-color 00000000 --line-clear-color 00000000 --line-ver-color 00000000 --line-wrong-color 00000000 \
        --inside-clear-color "$_in" --ring-clear-color "$HEX_MUTED" --text-clear-color "$HEX_FG" \
        --inside-ver-color "$_in" --ring-ver-color "$HEX_FG" --text-ver-color "$HEX_FG" \
        --inside-wrong-color "$_in" --ring-wrong-color "$HEX_ANSI_1" --text-wrong-color "$HEX_ANSI_1" \
        --layout-text-color "$HEX_FG" --layout-bg-color "$_in" --layout-border-color 00000000 \
        --caps-lock-key-hl-color "$HEX_ANSI_3" --text-caps-lock-color "$HEX_ANSI_3" \
        --ring-caps-lock-color "$HEX_ANSI_3" --inside-caps-lock-color "$_in" --line-caps-lock-color 00000000 --caps-lock-bs-hl-color "$HEX_ANSI_1"
}
# Screen capture: grim, slurp for an area, sway's tree for the window in front; a PNG in
# screenshots under the pictures folder user-dirs.dirs names, so ~/Pictures gets no twin
desk_capture() {   # desk_capture screen|area|window [--wait N]
    CAPTURE_DIR=$(user_pictures)/screenshots
    _what=${1:-screen}; _wait=0
    if [ "${2:-}" = --wait ]; then _wait=${3:-}; fi
    case $_what in screen|area|window) ;; *) refuse "capture takes screen, area or window" ;; esac
    case $_wait in ''|*[!0-9]*) refuse "--wait takes whole seconds" ;; esac
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own (Shift+Command+5)"
    [ -n "${WAYLAND_DISPLAY:-}" ] || refuse "captures the desktop: run it inside it (Print)"
    command -v grim >/dev/null 2>&1 || refuse "grim is not installed: run spark-shell on desktop"
    [ "$_what" != area ] || command -v slurp >/dev/null 2>&1 || refuse "slurp is not installed: run spark-shell on desktop"
    [ "$_wait" = 0 ] || sleep "$_wait"
    mkdir -p "$CAPTURE_DIR"
    _b=$(date +%Y-%m-%d-%H%M%S); _f=$CAPTURE_DIR/$_b.png; _n=2
    while [ -e "$_f" ]; do _f=$CAPTURE_DIR/$_b-$_n.png; _n=$((_n + 1)); done
    case $_what in
        screen) _o=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null | head -1)   # the screen in use, with more than one
            if [ -n "$_o" ]; then set -- -o "$_o"; else set --; fi ;;
        area) _g=$(slurp 2>/dev/null) && [ -n "$_g" ] || { echo "no area picked: nothing captured"; return 1; }
            set -- -g "$_g" ;;
        window) _g=$(swaymsg -t get_tree 2>/dev/null | jq -r '[.. | objects | select(.focused? == true and .type? != "workspace" and .type? != "output")][0] | if . == null then "" else "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)" end' 2>/dev/null || :)
            [ -n "$_g" ] || refuse "no window in front to capture"
            set -- -g "$_g" ;;
    esac
    grim -c "$@" "$_f" 2>/dev/null || { rm -f "$_f"; refuse "grim could not take the picture"; }   # -c: the pointer in the picture, as it is on the screen
    _c=''
    if command -v wl-copy >/dev/null 2>&1 && wl-copy --type image/png < "$_f" 2>/dev/null; then _c=', and on the clipboard'; fi
    # shellcheck disable=SC2088   # the path as you read it, a tilde and all
    echo "~/${_f#"$HOME"/}$_c"
}
# PENDING: words a layout waits with for the sway about to start
desk_start() {   # desk_start PENDING -- sway now on this console; inside the desktop, the saved layouts
    pending=$1
    [ -z "$(desktop_na)" ] || refuse "$(desktop_na)"
    # the desktop off, but a login screen runs this until the next boot: your shell, never a dead end
    if [ "$DESKTOP" != sway ] && on_console && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        echo "The desktop is off (spark-shell on desktop brings it back). This is your shell."
        rm -rf "$TMP"; trap - EXIT
        # shellcheck disable=SC2086   # the -u words, split on purpose
        exec env $CONFIG_UNSET "${SHELL:-/bin/sh}" -l
    fi
    [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop"
    [ -z "$(desktop_tools)" ] || refuse "not installed:$(desktop_tools) (spark-shell on)"
    [ -f "$HOME/.config/sway/config" ] && [ -f "$HOME/.config/foot/foot.ini" ] || refuse "the sway and foot settings are missing (spark-shell on)"
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then desk_list; return 0; fi
    on_console || refuse "needs a console login (tty1 to tty9): ssh and terminal windows cannot start sway"
    runtime_dir
    log_dir=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell
    mkdir_private "$log_dir"
    [ -z "${pending:-}" ] || printf '%s\n' "$pending" > "$DESK_PENDING"
    rm -f "$BAR_WS_ORDER" "$STATE_DIR/ws-pool" "$NOTIFY_SEEN"   # gone at a new login; mako's ids start again
    st=0
    sound_start "$log_dir/sound.log"
    # no session bus from logind (Void): sway inside dbus-run-session, so notifications reach mako
    _bus=''; notify_bus || ! command -v dbus-run-session >/dev/null 2>&1 || _bus=dbus-run-session
    # shellcheck disable=SC2086   # the -u words and the bus, split on purpose: sway and all it starts read the file, never a key from this login
    XDG_CURRENT_DESKTOP=sway PATH=$HOME/.local/bin:$PATH env $CONFIG_UNSET $_bus sway 2>"$log_dir/sway.log" || st=$?
    sound_stop
    semantic_stop   # the server of the dialog's search ends with the session
    machine_rm now   # the session is over: nothing is open or in use any more
    [ "${TERM:-}" != linux ] || printf '\033[?25h'
    exit "$st"
}

# cmd_login [on|off] -- spellings of `on login` and `off login`; alone, the login row of status
cmd_login() {
    case ${1:-} in
        on) shift; cmd_on login "$@" ;;
        off) shift; cmd_off login "$@" ;;
        '') config_load; [ "$OS" = Darwin ] || pm_detect; status_login ;;
        *) refuse_in login "on or off: spark-shell login on" ;;
    esac
}

