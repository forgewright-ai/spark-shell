# shellcheck extended-analysis=false
# --- the compositor: the one module that names it (sway)
# sets: WM_CONFIG_REL WM_LOGIN_CONF WM_NAME WM_OWN
# reads: REPO
WM_NAME=sway
WM_OWN='sway swaybar swaybg swaymsg swaylock swayidle'   # its own processes: never apps, never ended
WM_CONFIG_REL=.config/sway/config
WM_LOGIN_CONF=sway.conf   # the login screen's own config for it, in template/login

wm_session() { [ -n "${SWAYSOCK:-}" ]; }         # inside a session
wm_live() { [ -S "${SWAYSOCK:-}" ]; }            # its socket is open
wm_here() { command -v swaymsg >/dev/null 2>&1; }
wm_up() { wm_session && [ -n "$(swaymsg -t get_version 2>/dev/null)" ]; }   # it answers
wm_running_any() { pgrep -x sway >/dev/null 2>&1; }
wm_pid() { pgrep -u "$(id -u)" -x sway 2>/dev/null | head -1 || :; }
wm_socket_of() { printf '%s\n' "${XDG_RUNTIME_DIR:-/nonexistent}/sway-ipc.$(id -u).$1.sock"; }   # wm_socket_of PID
wm_env_name() { printf 'SWAYSOCK'; }             # the session's variable, for a bus or a service manager
wm_config_file() { printf '%s\n' "$HOME/$WM_CONFIG_REL"; }
wm_config_template() { printf '%s\n' "$REPO/template/$WM_CONFIG_REL"; }
wm_portals_conf() { printf '%s\n' "$HOME/.config/xdg-desktop-portal/sway-portals.conf"; }
wm_start() { XDG_CURRENT_DESKTOP=sway PATH=$HOME/.local/bin:$PATH env "$@" sway; }   # wm_start ENV-WORDS...; the log is the caller's

# the queries: JSON, as the IPC gives it
wm_tree() { swaymsg -t get_tree 2>/dev/null; }
wm_outputs() { swaymsg -t get_outputs 2>/dev/null; }
wm_workspaces() { swaymsg -t get_workspaces 2>/dev/null; }
wm_inputs() { swaymsg -t get_inputs 2>/dev/null; }
wm_version() { swaymsg -t get_version 2>/dev/null; }
wm_bar_config() { swaymsg -t get_bar_config "$@" 2>/dev/null; }
wm_bar_id() { swaymsg -t get_bar_config 2>/dev/null | tr -d '[]" \n' | cut -d, -f1; }
wm_events() { swaymsg -r -t subscribe -m "$1" 2>/dev/null; }   # wm_events '["window"]' -> one event a line
wm_events_for() { exec timeout "$1" swaymsg -r -t subscribe -m "$2" 2>/dev/null; }   # wm_events_for SECONDS EVENTS, in the background: the job becomes the watcher

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
wm_tick() { swaymsg -t send_tick "$1"; }   # wm_tick PAYLOAD -- a word to every subscriber of ticks
wm_reload() { swaymsg reload; }
wm_exit() { swaymsg exit; }
wm_main_screen_lines() { printf 'workspace 1 output "%s"\nexec swaymsg focus output %s\n' "$1" "'\"$1\"'"; }   # the main screen, in the config's words
wm_main_screen_strip() { grep -v -e '^workspace 1 output ' -e '^exec swaymsg focus output '; }
wm_main_screen_of() { sed -n 's/^workspace 1 output "\(.*\)"$/\1/p' "$1" | head -1; }   # wm_main_screen_of FILE

# the lock, the idle watcher, the background, the capture, the clipboard
wm_lock_here() { command -v swaylock >/dev/null 2>&1; }
wm_lock_running() { pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1; }
wm_lock() { exec swaylock --daemonize "$@"; }
wm_lock_fallback() { printf 'swaylock -f'; }
wm_idle_cmd() {   # wm_idle_cmd LOCK-LINE IDLE-SECONDS LOCK-SECONDS -> the watcher command; 0 seconds: no timer
    printf 'swayidle -w'
    [ "$2" = 0 ] || printf " timeout %s '%s desktop idle' resume '%s desktop idle off'" "$2" "$REPO/spark-shell" "$REPO/spark-shell"
    [ "$3" = 0 ] || printf " timeout %s '%s; %s desktop idle off'" "$3" "$1" "$REPO/spark-shell"
    printf " before-sleep '%s'" "$1"
}
wm_idle_stop() { pkill -u "$(id -u)" -f "^swayidle .*$(printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g')" 2>/dev/null || :; }   # wm_idle_stop LOCK-LINE: ours alone
wm_background_here() { command -v swaybg >/dev/null 2>&1; }
wm_background() { swaybg -o '*' "$@"; }
wm_capture_here() { command -v grim >/dev/null 2>&1; }
wm_capture() { grim -c "$@" 2>/dev/null; }       # wm_capture [-o OUTPUT|-g GEOMETRY] FILE; -c: the pointer too
wm_pick_here() { command -v slurp >/dev/null 2>&1; }
wm_pick() { slurp 2>/dev/null; }                   # -> a geometry drawn by the person
wm_copy_here() { command -v wl-copy >/dev/null 2>&1; }
wm_copy() { wl-copy "$@"; }
wm_paste_here() { command -v wl-paste >/dev/null 2>&1; }
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
