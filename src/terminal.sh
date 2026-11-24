# shellcheck extended-analysis=false
# --- the terminal: the one module that names it (foot)
# sets: TERM_APP_PREFIX TERM_APP_RE TERM_CLIENT TERM_CONFIG_REL TERM_DIALOG_REL TERM_HEX TERM_LOGIN_CONF TERM_NAME TERM_OWN TERM_PALETTE_FORMATS
TERM_NAME=foot
TERM_PALETTE_FORMATS="env|$TERM_NAME|kitty|ghostty|alacritty"
TERM_CLIENT=footclient            # its client's process name when it runs as a server
TERM_OWN='foot footclient'        # its own processes: never apps
TERM_CONFIG_REL=.config/foot/foot.ini
TERM_DIALOG_REL=.config/foot/dialog.ini
TERM_LOGIN_CONF=foot.ini   # the login screen's own config for it, in template/login
TERM_APP_PREFIX=spark-shell-   # an app of the menu opens in a window of the terminal under this app id
TERM_APP_RE="^($TERM_NAME|$TERM_APP_PREFIX.*)$"   # the compositor's criterion for every window of the terminal
TERM_HEX="242424 f62b5a 47b413 e3c401 24acd4 f2affd 13c299 e6e6e6 616161 ff4d51 35d450 e9e836 5dc5f8 feabf2 24dfc4 ffffff"   # its default colors: text ffffff on ground 242424

term_here() { command -v foot >/dev/null 2>&1; }
term_missing() { echo 'foot is not installed (spark-shell on desktop)'; }
term_config_file() { printf '%s\n' "$HOME/$TERM_CONFIG_REL"; }
term_dialog_pad() {   # -> "X Y", the air between the dialog window's corner and its first cell: none in a window the dialog draws itself (it says so to what it starts), else the terminal's padding
    case ${SPARK_DIALOG_OWN_WINDOW:-} in 1) echo '0 0'; return 0 ;; esac
    sed -n 's/^pad=\([0-9]*\)x\([0-9]*\).*/\1 \2/p' "$HOME/$TERM_DIALOG_REL" 2>/dev/null | head -1
}
term_is_ours() { case ${TERM:-} in foot*) return 0 ;; *) return 1 ;; esac; }   # TERM says we run inside it
term_own_process() { [ "${1##*/}" = foot ]; }                                 # term_own_process COMM
term_runs() { [ "${1:-}" = foot ] && [ "${2:-}" = -e ]; }                      # term_runs WORD1 WORD2: a line that runs a command in a window
term_run() { printf 'foot -e %s' "$1"; }                                       # -> the line that runs COMMAND in a window
term_run_bare() { printf 'foot %s' "$1"; }                                     # the same without -e (a stub sees the difference)
term_in_dir() { printf "foot --working-directory='%s'" "$1"; }
term_window_cmd() {   # term_window_cmd APP-ID FACE SIZE ALPHA BACKGROUND COMMAND -> the line that opens a bare window
    _tcs=$(term_colors_section)
    printf "foot --app-id %s -o 'font=%s:size=%s' -o %s.alpha=%s -o %s.background=%s -o pad=0x0 -e %s" "$1" "$2" "$3" "$_tcs" "$4" "$_tcs" "$5" "$6"
}
term_since() {   # term_since MINOR -> 0 for a foot of 1.MINOR or newer, and for one that says no version
    _v=$(PATH=$HOME/.local/bin:$PATH foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
    case $_v in '') return 0 ;; '1 '*) [ "${_v#* }" -ge "$1" ] ;; *) [ "${_v%% *}" -gt 1 ] ;; esac
}
term_colors_section() { if term_since 26; then echo colors-dark; else echo colors; fi; }   # the name of its color section
term_fill() { ! term_since 17 || echo 'resize-by-cells=no'; }   # the line that has a floating window fill what the compositor gives: from 1.17 on it is cut to whole cells, and what is left shows the wallpaper; an older one refuses the key
# a program in a terminal, at the far end of an ssh too, may put words on the clipboard and never read what is there
term_security_section() { ! term_since 20 || echo '[security]'; }
term_security() { ! term_since 20 || echo 'osc52=copy-enabled'; }
term_version() { foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9.]*\).*/\1/p'; }
term_osc_bg() { printf '[%s]#%s' "$(awk -v a="$1" 'BEGIN { printf "%d", a * 100 + 0.5 }')" "$2"; }   # term_osc_bg ALPHA HEX -> its OSC 11 form: opacity in percent, then the color
