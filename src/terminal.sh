# shellcheck extended-analysis=false
# --- the terminal: the one module that names it (foot)
# sets: TERM_CLIENT TERM_CONFIG_REL TERM_DIALOG_REL TERM_HEX TERM_LOGIN_CONF TERM_NAME TERM_OWN
TERM_NAME=foot
TERM_CLIENT=footclient            # its client's process name when it runs as a server
TERM_OWN='foot footclient'        # its own processes: never apps
TERM_CONFIG_REL=.config/foot/foot.ini
TERM_DIALOG_REL=.config/foot/dialog.ini
TERM_LOGIN_CONF=foot.ini   # the login screen's own config for it, in template/login
TERM_HEX="242424 f62b5a 47b413 e3c401 24acd4 f2affd 13c299 e6e6e6 616161 ff4d51 35d450 e9e836 5dc5f8 feabf2 24dfc4 ffffff"   # its default colors: text ffffff on ground 242424

term_here() { command -v foot >/dev/null 2>&1; }
term_missing() { echo 'foot is not installed (spark-shell on desktop)'; }
term_config_file() { printf '%s\n' "$HOME/$TERM_CONFIG_REL"; }
term_dialog_pad() { sed -n 's/^pad=\([0-9]*\)x\([0-9]*\).*/\1 \2/p' "$HOME/$TERM_DIALOG_REL" 2>/dev/null | head -1; }   # -> "X Y", the dialog window's padding
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
term_colors_section() {   # the name of its color section: [colors] before 1.26, [colors-dark] from it
    _v=$(PATH=$HOME/.local/bin:$PATH foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
    set -- ${_v:-1 26}
    if [ "$1" -gt 1 ] || [ "$2" -ge 26 ]; then echo colors-dark; else echo colors; fi
}
term_version() { foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9.]*\).*/\1/p'; }
term_osc_bg() { printf '[%s]#%s' "$(awk -v a="$1" 'BEGIN { printf "%d", a * 100 + 0.5 }')" "$2"; }   # term_osc_bg ALPHA HEX -> its OSC 11 form: opacity in percent, then the color
