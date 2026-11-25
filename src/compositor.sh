# shellcheck extended-analysis=false
# --- the compositor: the one module that names it (sway)
# sets: WM_CONFIG_REL WM_LINE WM_LOGIN_CONF WM_NAME WM_OWN WM_TRAY
# reads: BAR_PROC REPO TAB
WM_NAME=sway
WM_OWN='sway swaybar swaybg swaymsg swaylock swayidle'   # its own processes: never apps, never ended
WM_CONFIG_REL=.config/sway/config
WM_TRAY=spark-tray   # its bar that hosts the apps' icons alone, beside spark's bar: that id, or spark-tray.2 and on
WM_LINE=spark-line   # its bar that runs spark-shell bar status where spark's bar draws none: the id the template gives it, or spark-line.2 and on
WM_LOGIN_CONF=sway.conf   # the login screen's own config for it, in template/login

wm_session() { [ -n "${SWAYSOCK:-}" ]; }         # inside a session
wm_live() { [ -S "${SWAYSOCK:-}" ]; }            # its socket is open
wm_here() { command -v swaymsg >/dev/null 2>&1; }
wm_up() { wm_session && [ -n "$(swaymsg -t get_version 2>/dev/null)" ]; }   # it answers
wm_running_socket() {   # -> the socket of the one sway of yours that answers in the runtime folder, where SWAYSOCK names one that is gone, as a terminal older than the login hands it on; false where SWAYSOCK names none, and where none or several answer
    wm_session && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -z "${RUNTIME_ADOPTED:-}" ] || return 1   # a folder the caller was handed, as its login's
    _wrf=''
    for _wrs in "$XDG_RUNTIME_DIR/sway-ipc.$(id -u)."*.sock; do
        [ -S "$_wrs" ] && [ -O "$_wrs" ] && [ -n "$(SWAYSOCK=$_wrs swaymsg -t get_version 2>/dev/null)" ] || continue
        [ -z "$_wrf" ] || return 1
        _wrf=$_wrs
    done
    [ -n "$_wrf" ] && printf '%s\n' "$_wrf"
}
wm_with() {   # wm_with COMMAND... -- run where sway answers: in this shell, or, for a SWAYSOCK that is gone, in a shell of its own with the running one's (WM_APART); false, and nothing run, where none answers
    if wm_up; then "$@"; return; fi
    _wws=$(wm_running_socket) || return 1
    ( SWAYSOCK=$_wws; export SWAYSOCK; WM_APART=yes; "$@" )
}
wm_covered() { wm_tree | jq -e 'any(.. | objects; .fullscreen_mode? == 2) or any(.. | objects | select(.type? == "workspace" and any(.. | objects; .focused? == true)) | .. | objects; .type? != "workspace" and (.fullscreen_mode? // 0) >= 1)' >/dev/null 2>&1; }   # 0 when a full-screen window covers the focused screen
wm_running_any() { pgrep -x sway >/dev/null 2>&1; }
wm_pid() {   # -> your sway's pid: the one whose socket is in this runtime folder, past a nested or a headless one that has its own, else the first; nothing for none
    _wpf=''
    for _wpp in $(pgrep -u "$(id -u)" -x sway 2>/dev/null); do
        [ ! -S "$(wm_socket_of "$_wpp")" ] || { _wpf=$_wpp; break; }
        _wpf=${_wpf:-$_wpp}
    done
    [ -z "$_wpf" ] || printf '%s\n' "$_wpf"
}
wm_socket_of() { printf '%s\n' "${XDG_RUNTIME_DIR:-/nonexistent}/sway-ipc.$(id -u).$1.sock"; }   # wm_socket_of PID
wm_background_pid() {   # -> the session's newest background drawer (swaybg, a child of the sway whose socket is SWAYSOCK); false for none
    _wbs=${SWAYSOCK##*/sway-ipc.}; _wbs=${_wbs%.sock}; _wbs=${_wbs#*.}; case $_wbs in ''|*[!0-9]*) return 1 ;; esac   # sway-ipc.UID.PID.sock -> PID
    for _wbk in $(cat "/proc/$_wbs"/task/*/children 2>/dev/null); do [ "$(cat "/proc/$_wbk/comm" 2>/dev/null)" != swaybg ] || printf '%s %s\n' "$(proc_ticks "$_wbk")" "$_wbk"; done \
        | sort -n | tail -1 | cut -d' ' -f2 | grep .   # its children read from /proc: an image may have no pgrep
}
wm_env_name() { printf 'SWAYSOCK'; }             # the session's variable, for a bus or a service manager
wm_proc_has() {   # wm_proc_has /proc/PID NAME=VALUE... -> 0 when that process was started with each of them; false where its environment cannot be read
    _wph=$(tr '\n\0' ' \n' 2>/dev/null < "$1/environ") || return 1
    shift; for _wpv in "$@"; do printf '%s\n' "$_wph" | grep -qxF -- "$_wpv" || return 1; done
}
wm_config_file() { printf '%s\n' "$HOME/$WM_CONFIG_REL"; }
wm_config_template() { printf '%s\n' "$REPO/template/$WM_CONFIG_REL"; }
wm_portals_conf() { printf '%s\n' "$HOME/.config/xdg-desktop-portal/sway-portals.conf"; }
# Firefox under a band draws a title bar of its own and round corners the wallpaper shows through, unless it is told the
# window has its decoration; a person's own value stays
wm_start() { XDG_CURRENT_DESKTOP=sway MOZ_GTK_TITLEBAR_DECORATION=${MOZ_GTK_TITLEBAR_DECORATION:-none} PATH=$HOME/.local/bin:$PATH env "$@" sway; }   # wm_start ENV-WORDS...; the log is the caller's

# the queries: JSON, as the IPC gives it
wm_tree() { swaymsg -t get_tree 2>/dev/null; }
wm_outputs() { swaymsg -t get_outputs 2>/dev/null; }
wm_workspaces() { swaymsg -t get_workspaces 2>/dev/null; }
wm_inputs() { swaymsg -t get_inputs 2>/dev/null; }
wm_version() { swaymsg -t get_version 2>/dev/null; }
wm_bar_config() { swaymsg -t get_bar_config "$@" 2>/dev/null; }
wm_events() { swaymsg -r -t subscribe -m "$1" 2>/dev/null; }   # wm_events '["window"]' -> one event a line
wm_events_for() { exec timeout "$1" swaymsg -r -t subscribe -m "$2" 2>/dev/null; }   # wm_events_for SECONDS EVENTS, in the background: the job becomes the watcher

# its own bars (swaybar), a name each: the line's, which runs spark-shell bar status where spark's bar draws none, shown
# or hidden, and the tray's host beside spark's; a person's own, in config.d, has another id and is never touched. The
# first `bar ID SUBCOMMAND` for an id it does not know makes that bar and starts its program, which reads what the one
# message said; once the program ended nothing but a reload starts it, so the next bar takes a fresh id, and a reload
# drops each bar the config does not have (sway 1.9 to 1.12). A bar is made whole and never changed as it runs: going
# invisible would stop its line, one that had no tray takes none, and one held to a screen of several ends where a
# screen has no maker's name (a headless one)
wm_bar_ids() { wm_bar_config | tr -d '[]" \n' | tr ',' '\n'; }
wm_bar_newest() { wm_bar_ids | awk -v n="$1" '$0 == n || index($0, n ".") == 1 { id = $0 } END { if (id != "") print id }'; }   # wm_bar_newest NAME -> the id made last under NAME, its program running or ended; nothing for none
wm_bar_id() {   # -> the bar it draws itself, never the tray's host: the one made last in this session, else the first
    wm_bar_ids | awk -v tray="$WM_TRAY" -v line="$WM_LINE" '
        function named(n) { return $0 == n || index($0, n ".") == 1 }
        named(tray) { next } named(line) { made = $0 } first == "" { first = $0 }
        END { if (made != "") first = made; if (first != "") print first }'
}
wm_bar_running() {   # wm_bar_running NAME -> PID:ID for each of NAME's bars whose program runs in this session, from /proc: an image may have no pgrep, and the program is sway's child from 1.11 on alone
    for _wbp in /proc/[0-9]*; do
        _wbc=''; { read -r _wbc < "$_wbp/comm"; } 2>/dev/null || continue
        [ "$_wbc" = swaybar ] && wm_proc_has "$_wbp" "SWAYSOCK=${SWAYSOCK:-}" || continue
        _wbc=$(tr '\0' '\n' 2>/dev/null < "$_wbp/cmdline" | sed -n '/^-b$/{n;p;}')
        case $_wbc in "$1"|"$1".[0-9]*) printf '%s:%s\n' "${_wbp##*/}" "$_wbc" ;; esac
    done
}
wm_bars_mode() {   # wm_bars_mode invisible|dock -- the line's bar, and the tray's host with it: out of sight, or back as each stands, the host over spark's bar and taking no room of its own
    _wbm=$(wm_bar_id); [ -z "$_wbm" ] || swaymsg -- "bar $_wbm mode $1"
    _wbt=$(wm_bar_running "$WM_TRAY" | sed -n '$s/^[0-9]*://p'); [ -z "$_wbt" ] || swaymsg -- "bar $_wbt mode $(if [ "$1" = dock ]; then echo hide; else echo invisible; fi)"
}
wm_bar_end() {   # wm_bar_end NAME [ID] -- the programs of NAME's bars ended, but for ID's, waited for two seconds at most; no subcommand goes to a bar a reload may have dropped: it would make one
    for _wbe in $(wm_bar_running "$1"); do
        [ "${_wbe#*:}" != "${2:-}" ] || continue
        kill "${_wbe%%:*}" 2>/dev/null
        _wbn=0; while [ "$_wbn" -lt 20 ] && grep -q . "/proc/${_wbe%%:*}/cmdline" 2>/dev/null; do sleep 0.1; _wbn=$((_wbn + 1)); done
    done
}
wm_bar_make() {   # wm_bar_make NAME SUBCOMMANDS -- a bar made whole, its subcommands, a line each, in one message, under the first id of NAME's that sway has none of
    _wmi=$1; _wmn=1
    while wm_bar_ids | grep -qxF -- "$_wmi"; do _wmn=$((_wmn + 1)); _wmi=$1.$_wmn; done
    swaymsg -- "$(printf '%s\n' "$2" | awk -v bar="bar $_wmi " '{ printf "%s%s%s", (NR > 1 ? "; " : ""), bar, $0 }')" >/dev/null 2>&1
}
wm_config_bar() {   # wm_config_bar [FILE] -> the bar its config has, or FILE, a subcommand a line, the mode first, its id left out; nothing for none
    awk '/^bar \{$/ { on = 1; next } !on { next } /^\}$/ { exit }
        { sub(/^[ \t]+/, "") }
        /^#/ || /^id / || $0 == "" { next } /\{$/ { group = $1 " "; next } /^\}$/ { group = ""; next }
        $1 == "mode" { print; next } { rest = rest group $0 "\n" }
        END { printf "%s", rest }' "${1:-$(wm_config_file)}" 2>/dev/null
}
wm_bar_follow() {   # the line's bar in the running session as its config has it now, with no reload: the one that runs ended, the config's made
    wm_bar_end "$WM_LINE"
    _wfb=$(wm_config_bar); [ -z "$_wfb" ] || wm_bar_make "$WM_LINE" "$_wfb"
}
wm_tray_make() {   # wm_tray_make OUTPUT LEFT HEIGHT PADDING top|bottom -- the tray's host on that screen, LEFT pixels in from its left edge, its ground clear, unseen until it is whole; the newest alone stays, whoever made one at the same moment
    wm_bar_make "$WM_TRAY" "$(printf '%s\n' 'mode invisible' 'hidden_state show' 'modifier none' "position $5" "output $1" "tray_output $1" "height $3" \
        "tray_padding $4" "gaps 0 0 0 $2" 'workspace_buttons no' 'binding_mode_indicator no' 'colors background #00000000' 'mode hide')" || return 1
    _wtn=$(wm_bar_newest "$WM_TRAY"); _wti=0
    while [ "$_wti" -lt 20 ] && ! wm_bar_running "$WM_TRAY" | grep -qx "[0-9]*:$_wtn"; do sleep 0.1; _wti=$((_wti + 1)); done   # its program is there, two seconds at most: one not yet started is not found, and the next maker's end would pass it by
    wm_bar_end "$WM_TRAY" "$_wtn"
}

# the commands, in its own language; send and on end the options first, cmd and act do not (a stub sees the difference)
wm_cmd() { swaymsg "$@"; }
wm_send() { swaymsg -- "$@"; }
wm_on() { swaymsg -- "[$1] $2"; }                 # wm_on 'con_id=N' 'focus'
wm_act() { swaymsg "[$1] $2"; }
wm_exec() { swaymsg -- exec "$1"; }
wm_exec_at() { SWAYSOCK=$1 swaymsg -- exec "$2"; }   # through another session's socket
wm_workspace() { swaymsg -- workspace "$@"; }
wm_output() { swaymsg -- output "$@"; }
wm_input() { swaymsg -- input "$@"; }
# the layout switched on the keyboards that have layouts, by identifier, and never on type:keyboard: sway 1.12 ends, the
# session with it, when a layout switch reaches a keyboard with no keymap, as a virtual keyboard that never typed is.
# Every virtual keyboard has the one identifier, so an identifier is sent only where each keyboard under it has a layout
wm_kb_layout() {   # wm_kb_layout next|INDEX -> 0 when the keyboards took it; false, and nothing sent, where no identifier is safe
    _wkl=$(wm_inputs | jq -r '[.[] | select(.type == "keyboard" and (.identifier | type) == "string")] | group_by(.identifier)[] | select(all(.[]; (.xkb_layout_names // [] | length) > 0)) | .[0].identifier | @json' 2>/dev/null) || return 1
    [ -n "$_wkl" ] || return 1
    printf '%s\n' "$_wkl" | while IFS= read -r _wki; do swaymsg -- "input $_wki xkb_switch_layout $1" || exit 1; done
}
wm_tick() { swaymsg -t send_tick "$1"; }   # wm_tick PAYLOAD -- a word to every subscriber of ticks
wm_reload() { swaymsg reload; }
wm_exit() { swaymsg exit; }
wm_main_screen_lines() {   # wm_main_screen_lines ID -- the main screen, in the config's words; false, and no line, for an id with a sign in it: the second line is a shell's
    case $1 in ''|*[!A-Za-z0-9\ ._:\(\)+/,-]*) return 1 ;; esac
    printf 'workspace 1 output "%s"\nexec swaymsg focus output %s\n' "$1" "'\"$1\"'"
}
wm_main_screen_strip() { grep -v -e '^workspace 1 output ' -e '^exec swaymsg focus output '; }
wm_main_screen_of() { sed -n 's/^workspace 1 output "\(.*\)"$/\1/p' "$1" | head -1; }   # wm_main_screen_of FILE

# the lock, the idle watcher, the background, the capture, the clipboard
wm_lock_here() { command -v swaylock >/dev/null 2>&1; }
wm_lock_pids() {   # -> the pids of this session's swaylocks, locked or still starting
    # a lock of this session's alone: another session's (a second desktop, on tty2) leaves this one open. From outside, with
    # no display, it is the session of wm_pid. One whose environment cannot be read is not counted: swaylock refuses a second by itself
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then set -- "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
    else set -- "$(wm_env_name)=$(wm_socket_of "$(wm_pid)")"; fi
    for _wlp in $(pgrep -u "$(id -u)" -x swaylock 2>/dev/null); do ! wm_proc_has "$BAR_PROC/$_wlp" "$@" || printf '%s\n' "$_wlp"; done
}
wm_lock_running() { [ -n "$(wm_lock_pids)" ]; }   # one is here: it may read its pictures still, the screen open
# swaylock reads its pictures, locks, and as the compositor says it is locked leaves its caller's session (--daemonize):
# one that has not left it yet is no lock. Its password helper never leaves it
wm_lock_up() {   # -> 0 once this session is locked, never before
    for _wlu in $(wm_lock_pids); do
        ! awk -v p="$_wlu" '{ sub(/.*\) /, ""); up = $4 == p } END { exit !up }' "$BAR_PROC/$_wlu/stat" 2>/dev/null || return 0   # nothing read, as of one that ends: not up
    done
    return 1
}
wm_lock() { swaylock --daemonize "$@"; }   # -> 0 once locked; not 0: not locked, or locked by another
wm_lock_within() {   # wm_lock_within SECONDS ARG... -> as wm_lock, ended when it has not locked by then. What ends in between unlocks nothing: a lock whose owner is gone stays, and the next one takes it
    _wls=$1; shift; { timeout -s KILL "$_wls" swaylock --daemonize "$@"; } 2>/dev/null
}
wm_lock_fallback() { printf 'swaylock -f'; }
wm_idle_cmd() {   # wm_idle_cmd LOCK-LINE IDLE-SECONDS LOCK-SECONDS -> the watcher command; 0 seconds: no timer
    printf 'swayidle -w'
    [ "$2" = 0 ] || printf " timeout %s '%s desktop idle' resume '%s desktop idle off'" "$2" "$REPO/spark-shell" "$REPO/spark-shell"
    [ "$3" = 0 ] || printf " timeout %s '%s; %s desktop idle off'" "$3" "$1" "$REPO/spark-shell"
    printf " before-sleep '%s'" "$1"
}
wm_idle_stop() { pkill -u "$(id -u)" -f "^swayidle .*$(printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g')" 2>/dev/null || :; }   # wm_idle_stop LOCK-LINE: ours alone
wm_background_here() { command -v swaybg >/dev/null 2>&1; }
wm_background() {   # started in the background only: exec, so the pid its caller keeps and ends is the wallpaper's, not a shell's
    if [ "${1:-}" = -i ]; then   # a picture: a screen with a still of its own wears it, as the desktop shows it (v0.166.4: a turned screen blinked the landscape while sway reloaded)
        while IFS="$TAB" read -r _wbn _wbf; do
            [ -n "$_wbn" ] && [ -n "$_wbf" ] && set -- "$@" -o "$_wbn" -i "$_wbf" -m fill
        done <<EOF
$(art_screen_stills)
EOF
    fi
    exec swaybg -o '*' "$@"
}
wm_capture_here() { command -v grim >/dev/null 2>&1; }
wm_capture() { grim -c "$@" 2>/dev/null; }       # wm_capture [-o OUTPUT|-g GEOMETRY] FILE; -c: the pointer too
wm_pick_here() { command -v slurp >/dev/null 2>&1; }
wm_pick() { slurp 2>/dev/null; }                   # -> a geometry drawn by the person
wm_copy_here() { command -v wl-copy >/dev/null 2>&1; }
wm_copy() { wl-copy "$@"; }
wm_paste_here() { command -v wl-paste >/dev/null 2>&1; }
wm_focused_id() { wm_tree | jq -r '[.. | objects | select(.focused? == true and .pid? != null)][0].id // empty' 2>/dev/null | grep -x '[0-9][0-9]*'; }   # -> the window with the focus; false when none has it
wm_type_here() { command -v wtype >/dev/null 2>&1; }
# the pause first: the compositor takes the keyboard's map a moment after it is handed over, and a word
# typed in that moment loses its first character
wm_type() { wtype -s 20 -- "$1"; }   # wm_type TEXT -- typed into the focused window, through the compositor's virtual keyboard
wm_erase() {   # wm_erase N -- N characters back
    _wen=$1; [ "$_wen" -gt 0 ] || return 0
    set -- -s 20
    while [ "$_wen" -gt 0 ]; do set -- "$@" -k BackSpace; _wen=$((_wen - 1)); done
    wtype "$@"
}
wm_missing() {   # wm_missing lock|capture|pick|copy|capture-failed -> the line that says so
    case $1 in
        lock) echo 'swaylock is not installed (spark-shell on desktop)' ;;
        capture) echo 'grim is not installed: run spark-shell on desktop' ;;
        pick) echo 'slurp is not installed: run spark-shell on desktop' ;;
        copy) echo 'cannot copy: wl-copy is not installed (spark-shell on desktop)' ;;
        type) echo 'wtype is not installed (spark-shell on desktop)' ;;
        capture-failed) echo 'grim could not take the picture' ;;
    esac
}

# what the model is told
wm_tools_said() {
    _wts=''
    if wm_capture_here; then _wts='screenshots grim'; ! wm_pick_here || _wts="$_wts + slurp"; fi
    if wm_copy_here; then _wts="${_wts:+$_wts, }clipboard wl-copy"; ! wm_paste_here || _wts="$_wts and wl-paste"; fi
    printf '%s' "$_wts"
}
wm_client() { printf 'swaymsg'; }
wm_queries_said() { printf 'swaymsg -t get_outputs|get_workspaces|get_tree|get_inputs'; }
wm_workspace_said() { printf 'swaymsg workspace number N goes to one'; }
