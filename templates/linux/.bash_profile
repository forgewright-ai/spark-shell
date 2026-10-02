# spark-shell ~/.bash_profile -- a login shell reads this, and everything lives in .bashrc.
[ -r ~/.bashrc ] && . ~/.bashrc

# The palette at a console login: the escapes spark-shell theme wrote,
# then the cursor on (a quiet boot hides it). Nothing in an emulator.
if [ "$TERM" = linux ] && [ -t 1 ]; then
    [ -r ~/.config/spark-shell/console-colors ] && cat ~/.config/spark-shell/console-colors
    printf '\033[?25h'
fi

# The palette at login: when theme.env changed since the last time,
# spark-shell writes its own files again and never touches yours.
# Otherwise it is one cksum.
if [[ $- == *i* ]] && [ -t 1 ] && command -v spark-shell >/dev/null 2>&1; then spark-shell follow; fi

# The desktop at a login on tty1, when the config says DESKTOP=sway.
# Leaving the desktop ends this login and the login prompt comes back.
# Any other console (Alt+F2), a terminal window and ssh stay a plain
# shell. When the desktop cannot start, its reason stays on the screen
# and this shell goes on.
if [[ $- == *i* ]] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = /dev/tty1 ] \
    && grep -Eqx 'DESKTOP="?sway"?' "${XDG_CONFIG_HOME:-$HOME/.config}/spark-shell/config" 2>/dev/null \
    && command -v spark-shell >/dev/null 2>&1; then
    spark-shell desktop && exit
fi

# The greeting: once per interactive login on a terminal, never for a
# script. SITE_QUIET_START=yes in site.env silences it (spark quiet start
# on). The file is read directly, with no python on the login path, so
# the environment's SITE_QUIET_START is not honoured here.
if [[ $- == *i* ]] && [ -t 1 ] && [ -r ~/.config/spark/banner ]; then
    if command -v spark >/dev/null 2>&1; then                       # blank row, logo, version, credits
        grep -qx 'SITE_QUIET_START=yes' ~/.config/spark/site.env 2>/dev/null || spark ver
    else printf '\n%b\n' "$(cat ~/.config/spark/banner)"; fi        # before bootstrap has linked spark
fi
