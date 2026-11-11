# shellcheck extended-analysis=false
# on_console -> 0 on /dev/tty1 and up (not XDG_VTNR: logind's, and Void has none)
on_console() { case $(tty 2>/dev/null) in /dev/tty[1-9]*) return 0 ;; *) return 1 ;; esac; }
# runtime_dir -- XDG_RUNTIME_DIR when unset (sway needs it; Void has no logind):
# a 0700 directory of yours under TMPDIR, never a symlink
runtime_dir() {
    [ -z "${XDG_RUNTIME_DIR:-}" ] || return 0
    _uid=$(id -u); _rd=${TMPDIR:-/tmp}; _rd=${_rd%/}/$_uid-runtime-dir
    [ -e "$_rd" ] || [ -L "$_rd" ] || mkdir -m 0700 "$_rd" 2>/dev/null || true
    if [ -d "$_rd" ] && [ ! -L "$_rd" ] && [ "$(ls -ldn "$_rd" | awk '{print $3}')" = "$_uid" ] && chmod 0700 "$_rd"; then
        XDG_RUNTIME_DIR=$_rd; export XDG_RUNTIME_DIR; return 0
    fi
    refuse "$_rd is not a private directory of yours, and sway needs one (XDG_RUNTIME_DIR)"
}
# runtime_adopt -- outside the desktop (ssh, a service) takes the directory
# runtime_dir made, where the sound lives, only when yours and 0700; never makes it
runtime_adopt() {
    [ -z "${XDG_RUNTIME_DIR:-}" ] && [ "$OS" != Darwin ] || return 0
    _uid=$(id -u); _rd=${TMPDIR:-/tmp}; _rd=${_rd%/}/$_uid-runtime-dir
    [ -d "$_rd" ] && [ ! -L "$_rd" ] || return 0
    case $(ls -ldn "$_rd" | awk '{print $1, $3}') in "drwx------ $_uid"|"drwx------. $_uid") XDG_RUNTIME_DIR=$_rd; export XDG_RUNTIME_DIR ;; esac
}

# cmd_desktop [WORDS] -- the desktop verb; alone, sway now on this console,
# as a child, never exec: the EXIT trap still cleans TMP and the cursor comes back
cmd_desktop() {
    config_load
    [ "$OS" = Darwin ] || pm_detect
    case ${1:-} in
        on) shift; cmd_on desktop "$@"; return ;;
        off) shift; cmd_off desktop "$@"; return ;;
        wallpaper) refuse "the wallpaper is a theme word now: spark-shell theme wallpaper ${2:-X}" ;;   # an older spelling
        apps|tools) cmd_apps_verb; return ;;   # older spellings of apps
        keep) shift; desk_save "$@"; return ;;       # older spellings of layout save and layout delete
        forget) shift; desk_delete "$@"; return ;;
        --ask) cmd_panel layout; return ;;           # older spellings of layout --ask and layout --pending
        --pending) desk_pending; return ;;
        --motion) theme_load 2>/dev/null || :; motion_follow; return ;;   # the moving wallpaper at the desktop's start
        --chat) python3 "$REPO/lib/home.py" open "$REPO/spark-shell" chat; return ;;   # an older spelling of home chat
        home) python3 "$REPO/lib/home.py" open "$REPO/spark-shell" "${2:-}"; return ;;
        keys) desk_keys; return ;;   # the key list, from the template
        lock) theme_load 2>/dev/null || :; desk_lock; return ;;
        idle) shift; theme_load 2>/dev/null || :; desk_idle "$@"; return ;;   # swayidle runs both   # a palette that fails to load must not keep the lock away
        network) shift; desk_network "$@"; return ;;
        time) shift; desk_time "$@"; return ;;
        display) shift; desk_display "$@"; return ;;
        keyboard) shift; desk_keyboard "$@"; return ;;
        pointer) shift
            [ "$OS" != Darwin ] || refuse "not on macOS, which has its own pointer settings"
            if [ "$#" = 0 ]; then panel_title pointer; else [ "$#" = 2 ] || refuse "pointer takes tap on|off, scroll on|off or speed N"; input_setting pointer "$1" "$2"; fi
            return ;;
        portals) desk_portals; return ;;
        --machine) case ${2:-all} in all|now|tick) machine_write "${2:-all}"; return ;; *) refuse "--machine takes all, now or tick" ;; esac ;;   # the machine files now, as the start (all) and the bar (now, tick) write them: the tests' door
        screen|screens) shift; desk_screen "$@"; return ;;
        window) shift; desk_window "$@"; return ;;
        pad) shift; desk_pad "$@"; return ;;
        capture) shift; desk_capture "$@"; return ;;
        notifications) shift; desk_notifications "$@"; return ;;
        storage) shift; desk_storage "$@"; return ;;
        power) shift; desk_power "$@"; return ;;
        --first)   # the desktop's first window: home once, then your shell, always
            if [ ! -f "$DESK_SEEN" ]; then
                { mkdir_private "$(dirname "$DESK_SEEN")" && : > "$DESK_SEEN"; } 2>/dev/null || true
                if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v foot >/dev/null 2>&1; then bar_panel_open ''; fi
            fi
            # the config's exports stay out of the shell (PROMPT is zsh's prompt string)
            # shellcheck disable=SC2086   # the -u words, split on purpose
            rm -rf "$TMP"; trap - EXIT; exec env $CONFIG_UNSET "${SHELL:-/bin/sh}" ;;
        ''|-*) ;;
        *) desk_need "$@"; return ;;   # an older spelling of layout WORDS
    esac
    desk_start ''
}
# The display: DISPLAY_IDLE and DISPLAY_LOCK in minutes, 0 never. The idle screen goes
# once the lock is up (swaylock --daemonize returns then), so no saver runs behind it
idle_exec() {   # -> the swayidle command the template and a live change run
    _l="$REPO/spark-shell desktop lock || swaylock -f"
    printf 'swayidle -w'
    [ "${DISPLAY_IDLE:-10}" = 0 ] || printf " timeout %s '%s desktop idle' resume '%s desktop idle off'" "$((DISPLAY_IDLE * 60))" "$REPO/spark-shell" "$REPO/spark-shell"
    [ "${DISPLAY_LOCK:-15}" = 0 ] || printf " timeout %s '%s; %s desktop idle off' timeout %s 'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"'" "$((DISPLAY_LOCK * 60))" "$_l" "$REPO/spark-shell" "$((DISPLAY_LOCK * 60))"
    printf " before-sleep '%s'" "$_l"
}
# The idle screen: one foot window a screen, tiled alone on a workspace named idle or
# "idle PORT" with no gaps (a fullscreen foot window would be solid: foot's own rule)
IDLE_APP="spark-idle"
IDLE_ALPHA=0.8
IDLE_FROM=$STATE_DIR/idle.from   # PORT<tab>NAME a line: each screen's workspace before the idle screen, the focused one last
desk_idle() {   # desk_idle [off|--clock|--side] -- the idle screen up, down, or what a window draws: the clock, or a side screen
    case ${1:-} in
        --clock) trap 'idle_back; exit 0' INT TERM HUP; idle_clock; idle_back; return ;;   # any end of the window brings the desktop back
        --side) trap 'idle_back; exit 0' INT TERM HUP; idle_side; idle_back; return ;;   # a screen beside the main one
        off) desk_in_sway || return 0
            idle_back
            return 0 ;;
        '') ;;
        *) refuse "idle takes off, or nothing: the idle screen now" ;;
    esac
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own desktop"
    desk_in_sway || refuse "the idle screen is the desktop's: run it inside it"
    command -v foot >/dev/null 2>&1 || refuse "foot is not installed (spark-shell on desktop)"
    ! idle_up || return 0
    theme_load
    _sz=$(look_font_size); : "${_sz:=12}"; _fc=$(foot_colors)
    # each screen's workspace, the focused screen's last so the focus ends there
    screens_json | jq -r '[.[] | select(.active and (.current_workspace // "") != "" and .current_workspace != "idle" and (.current_workspace | startswith("idle ") | not))]
        | (map(select(.focused | not)) + map(select(.focused)))[] | [.name, .current_workspace] | @tsv' > "$TMP/idle.from" 2>/dev/null || :
    [ ! -s "$TMP/idle.from" ] || { mkdir_private "$STATE_DIR"; cat "$TMP/idle.from" > "$IDLE_FROM"; }
    swaymsg -- "bar mode invisible" >/dev/null 2>&1 || :
    _fs=$(font_spec); _foot="foot --app-id $IDLE_APP -o 'font=${_fs%%:*}:size=$((_sz * 2))' -o $_fc.alpha=$IDLE_ALPHA -o $_fc.background=$HEX_BG -o pad=0x0 -e $REPO/spark-shell desktop idle"
    # the other screens first, the main one last so the focus ends on the clock; exec opens where it ran
    _main=$(idle_main)
    screens_json | jq -r --arg m "$_main" '.[] | select(.active and .name != $m) | .name' 2>/dev/null | while IFS= read -r _o; do
        case $_o in *[\"\\]*) continue ;; esac
        swaymsg -- "mouse_warping none; focus output \"$_o\"; workspace \"idle $_o\"; gaps inner current set 0; gaps outer current set 0; exec $_foot --side; mouse_warping output" >/dev/null 2>&1 || :
    done
    _at=''; case $_main in ''|*[\"\\]*) ;; *) _at="focus output \"$_main\"; " ;; esac
    swaymsg -- "mouse_warping none; ${_at}workspace idle; exec $_foot --clock; mouse_warping output" >/dev/null 2>&1 || refuse "could not open the idle screen"
}
idle_main() {   # -> the port the clock goes on: the main screen while it is on, else the focused one
    screens_json | jq -r --arg m "$(screen_main || :)" '[.[] | select(.active)] as $on
        | ([$on[] | select($m != "" and (.name == $m or ([.make, .model, .serial] | map(if . == null or . == "" then "Unknown" else . end) | join(" ")) == $m))]
           + [$on[] | select(.focused)] + $on)[0].name // empty' 2>/dev/null || :
}
idle_up() { swaymsg -t get_tree 2>/dev/null | jq -e --arg a "$IDLE_APP" '[.. | objects | select(.app_id? == $a)] | length > 0' >/dev/null 2>&1; }   # the idle window is on the screen
idle_back() {   # idle_back -- each screen's workspace back by name (never a toggle: off and each window's end may all run it), the bar, then the other idle windows go
    desk_in_sway || return 0
    if swaymsg -t get_workspaces 2>/dev/null | jq -e '[.[] | select((.visible or .focused) and (.name == "idle" or (.name | startswith("idle "))))] | length > 0' >/dev/null 2>&1; then
        _ib=''
        [ -f "$IDLE_FROM" ] && while IFS="$TAB" read -r _io _iw; do
            [ -n "$_iw" ] || { _iw=$_io; _io=''; }   # a name alone: no port
            case $_io$_iw in *[\"\\]*) continue ;; esac   # a name sway could not take in quotes
            case $_iw in ''|idle|'idle '*) continue ;; esac
            [ -z "$_io" ] || _ib="$_ib focus output \"$_io\";"
            _ib="$_ib workspace \"$_iw\";"
        done < "$IDLE_FROM" || :
        if [ -n "$_ib" ]; then swaymsg -- "mouse_warping none;$_ib mouse_warping output" >/dev/null 2>&1 || :   # one command: two ways out at once cannot cross
        else swaymsg -- "workspace back_and_forth" >/dev/null 2>&1 || :; fi   # no name kept
    fi
    [ "$DESKTOP_BAR" != yes ] || swaymsg -- "bar mode dock" >/dev/null 2>&1 || :
    idle_close
}
idle_close() {   # every idle window but this one (its foot is this shell's parent)
    swaymsg -t get_tree 2>/dev/null | jq -r --arg a "$IDLE_APP" --argjson p "${PPID:-0}" '.. | objects | select(.app_id? == $a and .pid != $p) | .id' 2>/dev/null \
        | while IFS= read -r _ic; do swaymsg -- "[con_id=$_ic] kill" >/dev/null 2>&1 || :; done
}
idle_wait() {   # idle_wait SECONDS -> 0 when a key or a mouse move came first, 1 when the time ran out (stty min 0 time 10: a byte or nothing a second)
    _iw=0
    while [ "$_iw" -lt "$1" ]; do
        [ -z "$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" ] || return 0
        _iw=$((_iw + 1))
    done
    return 1
}
idle_clock_end() { { printf '\033[?1003l\033[?25h\033[0m'; [ -z "${_ist:-}" ] || stty "$_ist"; } 2>/dev/null || :; }   # the mouse unreported, the cursor and the terminal as they were
saver_version() { sed -n 's/^VERSION = "\(.*\)".*/\1/p' "$REPO/lib/saver.py" 2>/dev/null; }   # read without python3
saver_can() { case ${SAVER_CAN_NOW:-} in 1) return 0 ;; 0) return 1 ;; esac; _sver=$(saver_version); [ -n "$_sver" ] && [ "$(python3 "$REPO/lib/saver.py" --version 2>/dev/null)" = "$_sver" ]; }   # a python3 that runs the savers (not a stub, not missing)
saver_known() { for _sn in clock $SAVER_NAMES; do [ "$_sn" != "$1" ] || return 0; done; return 1; }   # saver_known NAME -> a whole word of the list, never a part of one
saver_words() { if [ "$1" = clock ]; then echo "the clock alone"; else echo "the $1 saver"; fi; }   # saver_words NAME
saver_problem() {   # saver_problem NAME -> why it cannot be the idle screen's, in one line; nothing when it can
    if ! saver_known "$1"; then echo "saver takes clock, spark, starfield or drift"; return 0; fi
    [ "$1" = clock ] || saver_can || echo "saver $1 needs python3, which cannot run it here"
}
idle_clock() {   # idle_clock -- the time large at the lower left, the date under it, drawn again each minute until the window goes; under 9 rows or 38 columns, on one line
    if [ "${DISPLAY_SAVER:-clock}" != clock ] && saver_can; then python3 "$REPO/lib/saver.py" "$DISPLAY_SAVER" && return 0; fi   # a signal ends it cleanly; a failure falls through to the clock
    printf '\033[?25l'; trap 'idle_clock_end; idle_back; exit 0' INT TERM HUP
    _a='38;5;16'; _m='38;5;20'   # foot.ini's slots 16 and 20: the accent, and the muted color that reads on a panel
    _ist=''   # a byte at a time, every mouse move reported: a key or a move ends the clock
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
idle_side() {   # idle_side -- a side screen's window: the saver without its clock, or the dimmed wallpaper alone
    case ${DISPLAY_SAVER:-clock} in
        clock|drift) ;;   # the clock alone, or the clock bouncing: nothing to draw without the clock
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
idle_restart() {   # the running desktop's swayidle, again with the settings now
    desk_in_sway || return 0
    # only the swayidle that locks with spark-shell, never another session's
    pkill -u "$(id -u)" -f "^swayidle .*$(printf '%s' "$REPO/spark-shell desktop lock" | sed 's/[][\.*^$+?(){}|]/\\&/g')" 2>/dev/null || :
    swaymsg -- exec "$(idle_exec)" >/dev/null 2>&1 || :
}
idle_words() { if [ "$1" = 0 ]; then echo never; elif [ "$1" = 1 ]; then echo "after 1 minute"; else echo "after $1 minutes"; fi; }   # idle_words MINUTES
desk_display() {   # desk_display [idle|lock N | saver [NAME] | brightness N|up|down]
    case ${1:-} in
        '') _sv=''; [ "$DISPLAY_SAVER" = clock ] || _sv=" $PANEL_SEP $DISPLAY_SAVER saver"   # a saver is said only when one is chosen
            echo "idle screen $(idle_words "$DISPLAY_IDLE")$_sv $PANEL_SEP lock and display off $(idle_words "$DISPLAY_LOCK")"
            [ "$OS" = Darwin ] || { _b=$(light_get); [ -z "$_b" ] || echo "brightness ${_b%% *}%"; } ;;
        idle|lock) _k=DISPLAY_IDLE; [ "$1" = idle ] || _k=DISPLAY_LOCK
            case ${2:-} in 0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;; never) set -- "$1" 0 ;; *) refuse "display $1 takes minutes, 0 to 999 (0: never)" ;; esac
            [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop first"
            config_set "$_k" "$2" >/dev/null; eval "$_k=\$2"; export "${_k?}"
            sway_file_apply; idle_restart
            if [ "$1" = idle ]; then echo "idle screen $(idle_words "$2")"; else echo "lock and display off $(idle_words "$2")"; fi ;;
        saver) if [ -z "${2:-}" ]; then   # the savers, the one in use ticked
                for _x in clock $SAVER_NAMES; do if [ "$_x" = "$DISPLAY_SAVER" ]; then echo "$PANEL_TICK $_x"; else echo "  $_x"; fi; done; return 0; fi
            _p=$(saver_problem "$2"); [ -z "$_p" ] || refuse "display $_p"
            [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop first"
            config_set DISPLAY_SAVER "$2" >/dev/null; DISPLAY_SAVER=$2; export DISPLAY_SAVER   # the idle window reads it as it starts: nothing to restart
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

# The keyboard: KEYBOARD is the layouts by their xkb names, a variant after
# a plus (us br+intl); the first is in use at start, empty leaves sway's own
kb_line() {   # kb_line layout|variant -> the template's input line, or a comment when KEYBOARD is empty
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
kb_names() { swaymsg -t get_inputs 2>/dev/null | jq -r '[.[] | select(.type == "keyboard" and (.xkb_layout_names // [] | length) > 0)][0] | if . == null then empty else (.xkb_active_layout_index | tostring) + "\t" + (.xkb_layout_names | join("\t")) end' 2>/dev/null || :; }   # -> ACTIVE<tab>NAME<tab>NAME..., the long names sway knows
kb_known() {   # kb_known LAYOUT -> 0 when xkb lists it (no list to read: every name passes)
    _lst=${SPARK_SHELL_XKB_LST:-/usr/share/X11/xkb/rules/evdev.lst}
    [ -r "$_lst" ] || return 0
    awk -v n="${1%%+*}" '/^! layout/ {on = 1; next} /^!/ {on = 0} on && $1 == n {f = 1} END {exit !f}' "$_lst"
}
desk_keyboard() {   # desk_keyboard [next | LAYOUT...]
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own keyboard settings"
    case ${1:-} in
        repeat-delay|repeat-rate|caps) [ "$#" = 2 ] || refuse "keyboard $1 takes one value"; input_setting keyboard "$1" "$2" ;;
        '') if [ -z "$KEYBOARD" ]; then echo "keyboard: sway's own layout (spark-shell desktop keyboard us br sets some)"; return 0; fi
            _a=$(kb_names | cut -f1); _i=0
            for _x in $KEYBOARD; do if [ "$_i" = "${_a:-0}" ]; then echo "$PANEL_TICK $_x"; else echo "  $_x"; fi; _i=$((_i + 1)); done ;;
        next) desk_in_sway || refuse "switches the desktop's keyboard: run it inside it (Super+Ctrl+space)"
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

