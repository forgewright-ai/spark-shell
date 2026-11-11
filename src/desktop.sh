# shellcheck extended-analysis=false
# on_console -> 0 on /dev/tty1 and up (not XDG_VTNR: Void has no logind)
# sets: IDLE_ALPHA IDLE_APP IDLE_FROM
# reads: BAR_WS_ORDER CONFIG_DIR CONFIG_UNSET KB_RE LAYOUT_PENDING LAYOUT_SEEN NOTIFY_SEEN OS PANEL_SEP PANEL_TICK REPO SAVER_NAMES SCREENS_CONF STATE_DIR TAB TMP US
on_console() { case $(tty 2>/dev/null) in /dev/tty[1-9]*) return 0 ;; *) return 1 ;; esac; }
# runtime_dir -- XDG_RUNTIME_DIR when unset (Void has no logind)
runtime_dir() {
    [ -z "${XDG_RUNTIME_DIR:-}" ] || return 0
    _uid=$(id -u); _rd=${TMPDIR:-/tmp}; _rd=${_rd%/}/$_uid-runtime-dir
    [ -e "$_rd" ] || [ -L "$_rd" ] || mkdir -m 0700 "$_rd" 2>/dev/null || true
    if [ -d "$_rd" ] && [ ! -L "$_rd" ] && [ "$(ls -ldn "$_rd" | awk '{print $3}')" = "$_uid" ] && chmod 0700 "$_rd"; then
        XDG_RUNTIME_DIR=$_rd; export XDG_RUNTIME_DIR; return 0
    fi
    refuse "$_rd is not a private directory of yours, and the desktop needs one (XDG_RUNTIME_DIR)"
}
# runtime_adopt -- from ssh or a service; never makes the directory
runtime_adopt() {
    [ -z "${XDG_RUNTIME_DIR:-}" ] && [ "$OS" != Darwin ] || return 0
    _uid=$(id -u); _rd=${TMPDIR:-/tmp}; _rd=${_rd%/}/$_uid-runtime-dir
    [ -d "$_rd" ] && [ ! -L "$_rd" ] || return 0
    case $(ls -ldn "$_rd" | awk '{print $1, $3}') in "drwx------ $_uid"|"drwx------. $_uid") XDG_RUNTIME_DIR=$_rd; export XDG_RUNTIME_DIR ;; esac
}

# cmd_desktop [WORDS] -- sway as a child, never exec: the EXIT trap cleans TMP
cmd_desktop() {
    config_load
    [ "$OS" = Darwin ] || pm_detect
    case ${1:-} in
        on) shift; cmd_on desktop "$@"; return ;;
        off) shift; cmd_off desktop "$@"; return ;;
        wallpaper) refuse "the wallpaper is a theme word now: spark-shell theme wallpaper ${2:-X}" ;;
        apps|tools) cmd_apps_verb; return ;;
        keep) shift; layout_save "$@"; return ;;
        forget) shift; layout_delete "$@"; return ;;
        --ask) cmd_panel layout; return ;;
        --pending) layout_pending; return ;;
        --motion) theme_load 2>/dev/null || :; motion_follow; return ;;
        --chat) python3 "$REPO/lib/home.py" open "$REPO/spark-shell" chat; return ;;
        home) python3 "$REPO/lib/home.py" open "$REPO/spark-shell" "${2:-}"; return ;;
        keys) layout_keys; return ;;
        lock) theme_load 2>/dev/null || :; layout_lock; return ;;
        idle) shift; theme_load 2>/dev/null || :; layout_idle "$@"; return ;;   # a failed palette must not keep the lock away
        network) shift; layout_network "$@"; return ;;
        time) shift; layout_time "$@"; return ;;
        display) shift; layout_display "$@"; return ;;
        keyboard) shift; layout_keyboard "$@"; return ;;
        pointer) shift
            [ "$OS" != Darwin ] || refuse "not on macOS, which has its own pointer settings"
            if [ "$#" = 0 ]; then panel_title pointer; else [ "$#" = 2 ] || refuse "pointer takes tap on|off, scroll on|off or speed N"; input_setting pointer "$1" "$2"; fi
            return ;;
        portals) layout_portals; return ;;
        --machine) case ${2:-all} in all|now|tick) machine_write "${2:-all}"; return ;; *) refuse "--machine takes all, now or tick" ;; esac ;;   # the tests' door to machine_write
        screen|screens) shift; layout_screen "$@"; return ;;
        window) shift; layout_window "$@"; return ;;
        pad) shift; layout_pad "$@"; return ;;
        capture) shift; layout_capture "$@"; return ;;
        notifications) shift; layout_notifications "$@"; return ;;
        storage) shift; layout_storage "$@"; return ;;
        power) shift; layout_power "$@"; return ;;
        --first)   # home once, then your shell
            if [ ! -f "$LAYOUT_SEEN" ]; then
                { mkdir_private "$(dirname "$LAYOUT_SEEN")" && : > "$LAYOUT_SEEN"; } 2>/dev/null || true
                if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v foot >/dev/null 2>&1; then bar_panel_open ''; fi
            fi
            # the config's exports stay out of the shell (PROMPT is zsh's)
            # shellcheck disable=SC2086   # the -u words, split on purpose
            rm -rf "$TMP"; trap - EXIT; exec env $CONFIG_UNSET "${SHELL:-/bin/sh}" ;;
        ''|-*) ;;
        *) layout_need "$@"; return ;;
    esac
    layout_start ''
}
# the idle screen goes once the lock is up (swaylock --daemonize returns then)
idle_exec() {   # idle_exec -> the swayidle command
    _l="$REPO/spark-shell desktop lock || swaylock -f"
    printf 'swayidle -w'
    [ "${DISPLAY_IDLE:-10}" = 0 ] || printf " timeout %s '%s desktop idle' resume '%s desktop idle off'" "$((DISPLAY_IDLE * 60))" "$REPO/spark-shell" "$REPO/spark-shell"
    [ "${DISPLAY_LOCK:-15}" = 0 ] || printf " timeout %s '%s; %s desktop idle off' timeout %s 'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"'" "$((DISPLAY_LOCK * 60))" "$_l" "$REPO/spark-shell" "$((DISPLAY_LOCK * 60))"
    printf " before-sleep '%s'" "$_l"
}
# a foot window a screen, tiled alone, no gaps: fullscreen foot is solid
IDLE_APP="spark-idle"
IDLE_ALPHA=0.8
IDLE_FROM=$STATE_DIR/idle.from   # PORT<tab>NAME a line, the focused screen last
layout_idle() {   # layout_idle [off|--clock|--side]
    case ${1:-} in
        --clock) trap 'idle_back; exit 0' INT TERM HUP; idle_clock; idle_back; return ;;
        --side) trap 'idle_back; exit 0' INT TERM HUP; idle_side; idle_back; return ;;
        off) layout_in_sway || return 0
            idle_back
            return 0 ;;
        '') ;;
        *) refuse "idle takes off, or nothing: the idle screen now" ;;
    esac
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own desktop"
    layout_in_sway || refuse "the idle screen is the desktop's: run it inside it"
    command -v foot >/dev/null 2>&1 || refuse "foot is not installed (spark-shell on desktop)"
    ! idle_up || return 0
    theme_load
    _sz=$(look_font_size); : "${_sz:=12}"; _fc=$(foot_colors)
    # the focused screen's last, so the focus ends there
    screens_json | jq -r '[.[] | select(.active and (.current_workspace // "") != "" and .current_workspace != "idle" and (.current_workspace | startswith("idle ") | not))]
        | (map(select(.focused | not)) + map(select(.focused)))[] | [.name, .current_workspace] | @tsv' > "$TMP/idle.from" 2>/dev/null || :
    [ ! -s "$TMP/idle.from" ] || { mkdir_private "$STATE_DIR"; cat "$TMP/idle.from" > "$IDLE_FROM"; }
    swaymsg -- "bar mode invisible" >/dev/null 2>&1 || :
    _fs=$(font_spec); _foot="foot --app-id $IDLE_APP -o 'font=${_fs%%:*}:size=$((_sz * 2))' -o $_fc.alpha=$IDLE_ALPHA -o $_fc.background=$HEX_BG -o pad=0x0 -e $REPO/spark-shell desktop idle"
    # the main screen last: the focus ends on the clock
    _main=$(idle_main)
    screens_json | jq -r --arg m "$_main" '.[] | select(.active and .name != $m) | .name' 2>/dev/null | while IFS= read -r _o; do
        case $_o in *[\"\\]*) continue ;; esac
        swaymsg -- "mouse_warping none; focus output \"$_o\"; workspace \"idle $_o\"; gaps inner current set 0; gaps outer current set 0; exec $_foot --side; mouse_warping output" >/dev/null 2>&1 || :
    done
    _at=''; case $_main in ''|*[\"\\]*) ;; *) _at="focus output \"$_main\"; " ;; esac
    swaymsg -- "mouse_warping none; ${_at}workspace idle; exec $_foot --clock; mouse_warping output" >/dev/null 2>&1 || refuse "could not open the idle screen"
}
idle_main() {   # -> the main screen when on, else the focused one
    screens_json | jq -r --arg m "$(screen_main || :)" '[.[] | select(.active)] as $on
        | ([$on[] | select($m != "" and (.name == $m or ([.make, .model, .serial] | map(if . == null or . == "" then "Unknown" else . end) | join(" ")) == $m))]
           + [$on[] | select(.focused)] + $on)[0].name // empty' 2>/dev/null || :
}
idle_up() { swaymsg -t get_tree 2>/dev/null | jq -e --arg a "$IDLE_APP" '[.. | objects | select(.app_id? == $a)] | length > 0' >/dev/null 2>&1; }
idle_back() {   # never a toggle: off and each window's end may all run it
    layout_in_sway || return 0
    if swaymsg -t get_workspaces 2>/dev/null | jq -e '[.[] | select((.visible or .focused) and (.name == "idle" or (.name | startswith("idle "))))] | length > 0' >/dev/null 2>&1; then
        _ib=''
        [ -f "$IDLE_FROM" ] && while IFS="$TAB" read -r _io _iw; do
            [ -n "$_iw" ] || { _iw=$_io; _io=''; }
            case $_io$_iw in *[\"\\]*) continue ;; esac   # sway cannot quote it
            case $_iw in ''|idle|'idle '*) continue ;; esac
            [ -z "$_io" ] || _ib="$_ib focus output \"$_io\";"
            _ib="$_ib workspace \"$_iw\";"
        done < "$IDLE_FROM" || :
        if [ -n "$_ib" ]; then swaymsg -- "mouse_warping none;$_ib mouse_warping output" >/dev/null 2>&1 || :   # one command: two ways out cannot cross
        else swaymsg -- "workspace back_and_forth" >/dev/null 2>&1 || :; fi
    fi
    [ "$DESKTOP_BAR" != yes ] || swaymsg -- "bar mode dock" >/dev/null 2>&1 || :
    idle_close
}
idle_close() {   # all but this shell's parent foot
    swaymsg -t get_tree 2>/dev/null | jq -r --arg a "$IDLE_APP" --argjson p "${PPID:-0}" '.. | objects | select(.app_id? == $a and .pid != $p) | .id' 2>/dev/null \
        | while IFS= read -r _ic; do swaymsg -- "[con_id=$_ic] kill" >/dev/null 2>&1 || :; done
}
idle_wait() {   # idle_wait SECONDS -> 0 on input, 1 when the time ran out
    _iw=0
    while [ "$_iw" -lt "$1" ]; do
        [ -z "$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" ] || return 0
        _iw=$((_iw + 1))
    done
    return 1
}
idle_clock_end() { { printf '\033[?1003l\033[?25h\033[0m'; [ -z "${_ist:-}" ] || stty "$_ist"; } 2>/dev/null || :; }   # mouse reports off, cursor back
saver_version() { sed -n 's/^VERSION = "\(.*\)".*/\1/p' "$REPO/lib/saver.py" 2>/dev/null; }   # read without python3
saver_can() { case ${SAVER_CAN_NOW:-} in 1) return 0 ;; 0) return 1 ;; esac; _sver=$(saver_version); [ -n "$_sver" ] && [ "$(python3 "$REPO/lib/saver.py" --version 2>/dev/null)" = "$_sver" ]; }   # a real python3, not a stub
saver_known() { for _sn in clock $SAVER_NAMES; do [ "$_sn" != "$1" ] || return 0; done; return 1; }   # saver_known NAME
saver_words() { if [ "$1" = clock ]; then echo "the clock alone"; else echo "the $1 saver"; fi; }   # saver_words NAME
saver_problem() {   # saver_problem NAME -> why not, or nothing
    if ! saver_known "$1"; then echo "saver takes clock, spark, starfield or drift"; return 0; fi
    [ "$1" = clock ] || saver_can || echo "saver $1 needs python3, which cannot run it here"
}
idle_clock() {   # the time and the date, each minute
    if [ "${DISPLAY_SAVER:-clock}" != clock ] && saver_can; then python3 "$REPO/lib/saver.py" "$DISPLAY_SAVER" && return 0; fi   # a failure falls through to the clock
    printf '\033[?25l'; trap 'idle_clock_end; idle_back; exit 0' INT TERM HUP
    _a='38;5;16'; _m='38;5;20'   # foot.ini's slots 16 and 20: accent and muted
    _ist=''   # a byte at a time, every mouse move reported
    if [ -t 0 ]; then _ist=$(stty -g 2>/dev/null) && stty -icanon -echo min 0 time 10 2>/dev/null && printf '\033[?1003h' || _ist=''; fi
    while :; do
        # shellcheck disable=SC2046   # two numbers, split on purpose
        set -- $(stty size 2>/dev/null || echo 24 80)
        _h=${1:-24}; _d=$(date '+%A %e %B' | tr -s ' ')
        printf '\033[2J'
        if [ "$_h" -ge 9 ] && [ "${2:-80}" -ge 38 ]; then
            clock_rows | { _y=$((_h - 7)); while IFS= read -r _l; do printf '\033[%s;3H\033[%sm%s' "$_y" "$_a" "$_l"; _y=$((_y + 1)); done; }
            printf '\033[0m\033[%s;3H\033[%sm%s\033[0m' $((_h - 1)) "$_m" "$_d"
        else
            printf '\033[%s;3H\033[%sm%s\033[%s;3H\033[%sm%s\033[0m' $((_h - 2)) "$_a" "$(clock_text)" $((_h - 1)) "$_m" "$_d"
        fi
        _s=$(date +%S); _s=${_s#0}
        if [ -n "$_ist" ]; then ! idle_wait $((60 - ${_s:-0})) || break
        else sleep $((60 - ${_s:-0})) & wait $! || break; fi
    done
    idle_clock_end
}
idle_side() {   # the saver without its clock, or nothing
    case ${DISPLAY_SAVER:-clock} in
        clock|drift) ;;   # nothing to draw without the clock
        *) if saver_can; then python3 "$REPO/lib/saver.py" "$DISPLAY_SAVER" --no-clock && return 0; fi ;;
    esac
    printf '\033[?25l\033[2J'; trap 'idle_clock_end; idle_back; exit 0' INT TERM HUP
    _ist=''
    if [ -t 0 ]; then _ist=$(stty -g 2>/dev/null) && stty -icanon -echo min 0 time 10 2>/dev/null && printf '\033[?1003h' || _ist=''; fi
    while :; do
        if [ -n "$_ist" ]; then ! idle_wait 60 || break
        else sleep 60 & wait $! || break; fi
    done
    idle_clock_end
}
idle_restart() {
    layout_in_sway || return 0
    # never another session's swayidle
    pkill -u "$(id -u)" -f "^swayidle .*$(printf '%s' "$REPO/spark-shell desktop lock" | sed 's/[][\.*^$+?(){}|]/\\&/g')" 2>/dev/null || :
    swaymsg -- exec "$(idle_exec)" >/dev/null 2>&1 || :
}
idle_words() { if [ "$1" = 0 ]; then echo never; elif [ "$1" = 1 ]; then echo "after 1 minute"; else echo "after $1 minutes"; fi; }   # idle_words MINUTES
layout_display() {   # layout_display [idle|lock N | saver [NAME] | brightness N|up|down]
    case ${1:-} in
        '') _sv=''; [ "$DISPLAY_SAVER" = clock ] || _sv=" $PANEL_SEP $DISPLAY_SAVER saver"
            echo "idle screen $(idle_words "$DISPLAY_IDLE")$_sv $PANEL_SEP lock and display off $(idle_words "$DISPLAY_LOCK")"
            [ "$OS" = Darwin ] || { _b=$(light_get); [ -z "$_b" ] || echo "brightness ${_b%% *}%"; } ;;
        idle|lock) _k=DISPLAY_IDLE; [ "$1" = idle ] || _k=DISPLAY_LOCK
            case ${2:-} in 0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;; never) set -- "$1" 0 ;; *) refuse "display $1 takes minutes, 0 to 999 (0: never)" ;; esac
            [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop first"
            config_set "$_k" "$2" >/dev/null; eval "$_k=\$2"; export "${_k?}"
            sway_file_apply; idle_restart
            if [ "$1" = idle ]; then echo "idle screen $(idle_words "$2")"; else echo "lock and display off $(idle_words "$2")"; fi ;;
        saver) if [ -z "${2:-}" ]; then
                for _x in clock $SAVER_NAMES; do if [ "$_x" = "$DISPLAY_SAVER" ]; then echo "$PANEL_TICK $_x"; else echo "  $_x"; fi; done; return 0; fi
            _p=$(saver_problem "$2"); [ -z "$_p" ] || refuse "display $_p"
            [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop first"
            config_set DISPLAY_SAVER "$2" >/dev/null; DISPLAY_SAVER=$2; export DISPLAY_SAVER   # the idle window reads it at start: nothing to restart
            echo "idle screen shows $(saver_words "$2")" ;;
        brightness) light_set "${2:-}" ;;
        *) refuse "display takes idle N, lock N, saver NAME or brightness N|up|down" ;;
    esac
}

# Input settings
input_spec() {
    case $1:$2 in
        pointer:tap) input_key=POINTER_TAP; input_targets=touchpad; input_command=tap ;;
        pointer:scroll) input_key=POINTER_SCROLL; input_targets='pointer touchpad'; input_command=natural_scroll ;;
        pointer:speed) input_key=POINTER_SPEED; input_targets='pointer touchpad'; input_command=pointer_accel ;;
        keyboard:repeat-delay) input_key=KEY_REPEAT_DELAY; input_targets=keyboard; input_command=repeat_delay ;;
        keyboard:repeat-rate) input_key=KEY_REPEAT_RATE; input_targets=keyboard; input_command=repeat_rate ;;
        keyboard:caps) input_key=KEY_CAPS; input_targets=keyboard; input_command=xkb_options ;;
        *) return 1 ;;
    esac
}
input_valid() {
    case $1 in
        POINTER_TAP|POINTER_SCROLL) case $2 in on|off) return 0 ;; esac ;;
        KEY_CAPS) case $2 in caps|control|escape) return 0 ;; esac ;;
        POINTER_SPEED) [ ${#2} -le 32 ] && printf '%s\n' "$2" | awk '/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/ { if ($0 + 0 >= -1 && $0 + 0 <= 1) ok = 1 } END { exit !ok }' && return 0 ;;
        KEY_REPEAT_DELAY|KEY_REPEAT_RATE)
            case $2 in ''|*[!0-9]*|0[0-9]*) return 1 ;; esac
            if [ "$1" = KEY_REPEAT_DELAY ]; then [ "$2" -ge 100 ] && [ "$2" -le 2000 ] && return 0
            else [ "$2" -le 100 ] && return 0; fi ;;
    esac
    return 1
}
input_caps() { case $1 in control) echo ctrl:nocaps ;; escape) echo caps:escape ;; *) echo caps:capslock ;; esac; }
input_live() {
    _input_value=$2
    case $1 in POINTER_TAP|POINTER_SCROLL) if [ "$2" = on ]; then _input_value=enabled; else _input_value=disabled; fi ;; KEY_CAPS) _input_value=$(input_caps "$2") ;; esac
    for _input_type in $input_targets; do
        swaymsg -- input "type:$_input_type" "$input_command" "$_input_value" >/dev/null 2>&1 || return 1
    done
}
input_setting() {
    [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] || { echo "input settings need the sway desktop"; return 1; }
    input_spec "$1" "$2" && input_valid "$input_key" "$3" || { echo "$1: invalid $2 value"; return 1; }
    input_old=
    eval "input_old=\$$input_key"
    if [ -n "${SWAYSOCK:-}" ]; then
        if ! input_live "$input_key" "$3"; then
            input_live "$input_key" "$input_old" || :
            echo "sway did not apply $1 $2; the saved setting is unchanged"; return 1
        fi
    fi
    config_set "$input_key" "$3" >/dev/null
    export "$input_key=$3"
    sway_file_apply
    echo "$1 $2 $3"
}

# KEYBOARD: layouts by xkb name, a variant after a plus (us br+intl)
kb_line() {   # kb_line layout|variant -> the template's input line
    if [ -z "${KEYBOARD:-}" ]; then echo "# the keyboard: sway's own layout (spark-shell desktop keyboard us br sets some)"; return; fi
    _ls=''; _vs=''; _any=''
    for _x in $KEYBOARD; do
        case $_x in *+*) _v=${_x#*+}; _x=${_x%%+*}; _any=1 ;; *) _v='' ;; esac
        _ls="${_ls:+$_ls,}$_x"; _vs="$_vs${_vs:+,}$_v"; [ -n "$_vs" ] || _vs=' '
    done
    _vs=$(printf '%s' "$_vs" | sed 's/^ //')
    if [ "$1" = layout ]; then echo "input type:keyboard xkb_layout \"$_ls\""
    elif [ -n "$_any" ]; then echo "input type:keyboard xkb_variant \"$_vs\""
    else echo "# no variant"; fi
}
kb_names() { swaymsg -t get_inputs 2>/dev/null | jq -r '[.[] | select(.type == "keyboard" and (.xkb_layout_names // [] | length) > 0)][0] | if . == null then empty else (.xkb_active_layout_index | tostring) + "\t" + (.xkb_layout_names | join("\t")) end' 2>/dev/null || :; }   # -> ACTIVE<tab>NAME<tab>NAME..., sway's long names
kb_known() {   # kb_known LAYOUT -> 0 when xkb lists it (or has no list)
    _lst=${SPARK_SHELL_XKB_LST:-/usr/share/X11/xkb/rules/evdev.lst}
    [ -r "$_lst" ] || return 0
    awk -v n="${1%%+*}" '/^! layout/ {on = 1; next} /^!/ {on = 0} on && $1 == n {f = 1} END {exit !f}' "$_lst"
}
layout_keyboard() {   # layout_keyboard [next | LAYOUT...]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own keyboard settings"
    case ${1:-} in
        repeat-delay|repeat-rate|caps) [ "$#" = 2 ] || refuse "keyboard $1 takes one value"; input_setting keyboard "$1" "$2" ;;
        '') if [ -z "$KEYBOARD" ]; then echo "keyboard: sway's own layout (spark-shell desktop keyboard us br sets some)"; return 0; fi
            _a=$(kb_names | cut -f1); _i=0
            for _x in $KEYBOARD; do if [ "$_i" = "${_a:-0}" ]; then echo "$PANEL_TICK $_x"; else echo "  $_x"; fi; _i=$((_i + 1)); done ;;
        next) layout_in_sway || refuse "switches the desktop's keyboard: run it inside it (Super+Ctrl+space)"
            swaymsg -- input type:keyboard xkb_switch_layout next >/dev/null 2>&1 || refuse "sway took no layout switch"
            bar_redraw; kb_names | awk -F '\t' '{print "keyboard " $($1 + 2)}' ;;
        *) [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop first"
            _w=$(printf '%s ' "$@" | sed 's/ $//')
            printf '%s\n' "$_w" | grep -qE "$KB_RE" || refuse "$_w: layouts by their xkb names, a space between, a variant after a plus (us us+intl)"
            for _x in $_w; do kb_known "$_x" || refuse "$_x is no keyboard layout xkb knows (the two-letter names: us, br, de, fr, gb)"; done
            config_set KEYBOARD "$_w" >/dev/null; KEYBOARD=$_w; export KEYBOARD
            sway_file_apply; bar_redraw
            echo "keyboard $_w" ;;
    esac
}


# screen_x11_main -- the main screen as X11's primary (Xwayland names none)
screen_x11_main() {
    [ -n "${DISPLAY:-}" ] && command -v xrandr >/dev/null 2>&1 || return 0
    _xm=$(screen_main); [ -n "$_xm" ] || return 0
    _xp=$(screen_rows | awk -F '\t' -v i="$_xm" '($2 == i || $1 == i) && $3 == "on" { print $1; exit }')
    [ -n "$_xp" ] || return 0
    ! xrandr --listmonitors 2>/dev/null | grep -qF " +*$_xp " || return 0   # named already
    xrandr --output "$_xp" --primary >/dev/null 2>&1 || :
}
# X11 has nothing left of or above 0: a window there takes no click
screen_origin() {   # -> the screens moved, one line each
    screen_rows | awk -F '\t' '$3 == "on"' > "$TMP/origin"
    _sox=$(awk -F '\t' 'NR == 1 || $6 + 0 < m { m = $6 + 0 } END { print m + 0 }' "$TMP/origin")
    _soy=$(awk -F '\t' 'NR == 1 || $7 + 0 < m { m = $7 + 0 } END { print m + 0 }' "$TMP/origin")
    [ "$_sox" -lt 0 ] || [ "$_soy" -lt 0 ] || return 0
    [ "$_sox" -lt 0 ] || _sox=0; [ "$_soy" -lt 0 ] || _soy=0
    while IFS="$TAB" read -r _son _soi _ _ _ _sx _sy _; do
        _snx=$((_sx - _sox)); _sny=$((_sy - _soy))
        [ "$(awk -F '\t' -v i="$_soi" '$2 == i' "$TMP/origin" | grep -c .)" -eq 1 ] || _soi=$_son   # a shared name: the port's
        swaymsg -- output "\"$_soi\"" position "$_snx" "$_sny" >/dev/null 2>&1 || swaymsg -- output "$_son" position "$_snx" "$_sny" >/dev/null 2>&1 || continue
        mkdir -p "$CONFIG_DIR"
        { [ ! -f "$SCREENS_CONF" ] || grep -v -F -e "output \"$_soi\" position " -e '# rendered' "$SCREENS_CONF" || :; } > "$TMP/screens"
        { echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them'; grep . "$TMP/screens" || :; printf 'output "%s" position %s %s\n' "$_soi" "$_snx" "$_sny"; } > "$SCREENS_CONF"
        echo "$_son at $_snx,$_sny"
    done < "$TMP/origin"
}
layout_screen() {   # layout_screen [NAME [scale N | mode WxH | transform normal|90|180|270 | on | off | left-of|right-of|above|below OTHER]]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own display settings"
    layout_in_sway || refuse "changes the desktop's screens: run it inside it"
    if [ "${1:-}" = --ensure-visible ]; then
        if [ "$(screens_json | jq '[.[] | select(.active)] | length')" = 0 ]; then
            _first=$(screens_json | jq -r '.[0].name // empty')
            [ -z "$_first" ] || layout_screen "$_first" on
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
    _n=$(printf '%s' "$_r" | cut -f1); _id=$(printf '%s' "$_r" | cut -f2); _kind=${2:-}   # kept: a place replaces $2
    [ "$(screen_rows | awk -F '\t' -v i="$_id" '$2 == i' | grep -c .)" -eq 1 ] || _id=$_n   # a shared name (no serial) would set both: the port's
    case ${2:-} in
        scale) screen_scale_valid "${3:-}" || refuse "scale takes a positive decimal"
            _cmd="scale $3"; _said="$_n scale $3" ;;
        mode) screens_json | jq -e --arg n "$_n" --arg m "${3:-}" '.[] | select(.name == $n) | .modes[] | select("\(.width)x\(.height)" == $m or ("\(.width)x\(.height)@\((.refresh // 0) / 1000)Hz" == $m))' >/dev/null 2>&1 || refuse "$_n has no mode ${3:-}: $(screens_json | jq -r --arg n "$_n" '[.[] | select(.name == $n) | .modes[] | "\(.width)x\(.height)"] | unique | join(", ")')"
            _cmd="mode ${3}"; _said="$_n $3" ;;
        transform) case ${3:-} in normal|90|180|270) ;; *) refuse "transform takes normal, 90, 180 or 270 (clockwise); no mirrored orientation" ;; esac
            _cmd="transform $3"; if [ "$3" = normal ]; then _said="$_n upright"; else _said="$_n turned $3"; fi ;;
        main) [ "$(printf '%s' "$_r" | cut -f3)" = on ] || refuse "$_n is off: a screen off is no main one"
            screen_main_save "$_id"; swaymsg -- workspace 1 output "\"$_id\"" >/dev/null 2>&1 || :   # sway's now too, for a new workspace 1
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
    [ "$_kind" != transform ] || screen_beside_again "$_id"   # its width changed: the screens beside it move
    screen_origin > "$TMP/origin.said"
    login_screens_follow
    layout_refit_soon
    echo "$_said"
    [ ! -s "$TMP/origin.said" ] || echo "every screen moved by the same amount, so none sits left of or above 0 (X11 apps take clicks there)"
}

# Notifications, storage and power
layout_notifications() {   # layout_notifications [do-not-disturb on|off | dismiss | restore]
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
layout_storage() {   # layout_storage [mount|unmount|open|eject NAME]
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
layout_power() {   # layout_power [lock|suspend|logout|restart|shutdown]
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

# layout_lock -- swaylock in the palette
layout_lock() {
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own lock"
    [ -n "${WAYLAND_DISPLAY:-}" ] || refuse "locks the desktop: run it inside it (Super+Escape)"
    command -v swaylock >/dev/null 2>&1 || refuse "swaylock is not installed (spark-shell on desktop)"
    ! pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1 || return 0
    : "${HEX_BG:=242424}" "${HEX_FG:=ffffff}" "${HEX_ACCENT:=24acd4}" "${HEX_MUTED:=616161}" "${HEX_ANSI_1:=f62b5a}" "${HEX_ANSI_3:=e3c401}"   # foot's own, when no palette loaded
    if wall_there; then set -- --image "$(wall_path)" --scaling fill
    elif [ "$WALLPAPER" = default ]; then set -- --color "$(wall_ground | tr -d '#')"
    elif wall_color; then set -- --color "$(wall_hex "$WALLPAPER" | tr -d '#')"
    else set -- --color "$HEX_BG"; fi
    # e6: 90% of the background, the layout box too (swaylock's own is black)
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
# under the pictures folder user-dirs.dirs names, so ~/Pictures gets no twin
layout_capture() {   # layout_capture screen|area|window [--wait N]
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
        screen) _o=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null | head -1)
            if [ -n "$_o" ]; then set -- -o "$_o"; else set --; fi ;;
        area) _g=$(slurp 2>/dev/null) && [ -n "$_g" ] || { echo "no area picked: nothing captured"; return 1; }
            set -- -g "$_g" ;;
        window) _g=$(swaymsg -t get_tree 2>/dev/null | jq -r '[.. | objects | select(.focused? == true and .type? != "workspace" and .type? != "output")][0] | if . == null then "" else "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)" end' 2>/dev/null || :)
            [ -n "$_g" ] || refuse "no window in front to capture"
            set -- -g "$_g" ;;
    esac
    grim -c "$@" "$_f" 2>/dev/null || { rm -f "$_f"; refuse "grim could not take the picture"; }   # -c: the pointer in the picture
    _c=''
    if command -v wl-copy >/dev/null 2>&1 && wl-copy --type image/png < "$_f" 2>/dev/null; then _c=', and on the clipboard'; fi
    # shellcheck disable=SC2088   # the path as you read it, a tilde and all
    echo "~/${_f#"$HOME"/}$_c"
}
layout_start() {   # layout_start PENDING -- sway on this console, PENDING a layout's words
    pending=$1
    [ -z "$(desktop_na)" ] || refuse "$(desktop_na)"
    # the login screen still runs this: your shell, not a dead end
    if [ "$DESKTOP" != sway ] && on_console && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        echo "The desktop is off (spark-shell on desktop brings it back). This is your shell."
        rm -rf "$TMP"; trap - EXIT
        # shellcheck disable=SC2086   # the -u words, split on purpose
        exec env $CONFIG_UNSET "${SHELL:-/bin/sh}" -l
    fi
    [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop"
    [ -z "$(desktop_tools)" ] || refuse "not installed:$(desktop_tools) (spark-shell on)"
    [ -f "$HOME/.config/sway/config" ] && [ -f "$HOME/.config/foot/foot.ini" ] || refuse "the sway and foot settings are missing (spark-shell on)"
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then layout_list; return 0; fi
    on_console || refuse "needs a console login (tty1 to tty9): ssh and terminal windows cannot start sway"
    runtime_dir
    log_dir=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell
    mkdir_private "$log_dir"
    [ -z "${pending:-}" ] || printf '%s\n' "$pending" > "$LAYOUT_PENDING"
    rm -f "$BAR_WS_ORDER" "$STATE_DIR/ws-pool" "$NOTIFY_SEEN"   # a new login; mako's ids start again
    st=0
    sound_start "$log_dir/sound.log"
    # no session bus from logind (Void): dbus-run-session, so notifications reach mako
    _bus=''; notify_bus || ! command -v dbus-run-session >/dev/null 2>&1 || _bus=dbus-run-session
    # shellcheck disable=SC2086   # the -u words and the bus, split on purpose: sway and all it starts read the file, never a key from this login
    XDG_CURRENT_DESKTOP=sway PATH=$HOME/.local/bin:$PATH env $CONFIG_UNSET $_bus sway 2>"$log_dir/sway.log" || st=$?
    sound_stop
    semantic_stop
    machine_rm now
    [ "${TERM:-}" != linux ] || printf '\033[?25h'
    exit "$st"
}

# cmd_login [on|off]
cmd_login() {
    case ${1:-} in
        on) shift; cmd_on login "$@" ;;
        off) shift; cmd_off login "$@" ;;
        '') config_load; [ "$OS" = Darwin ] || pm_detect; status_login ;;
        *) refuse_in login "on or off: spark-shell login on" ;;
    esac
}

