# spark-shell ~/.bash_profile -- a login shell reads this, and everything lives in .bashrc.
[ -r ~/.bashrc ] && . ~/.bashrc

# The palette at login: when spark theme changed theme.env since the
# last render, spark-shell re-renders its own files and never touches
# yours. Otherwise it is one cksum.
if [[ $- == *i* ]] && [ -t 1 ] && command -v spark-shell >/dev/null 2>&1; then spark-shell follow; fi

# The greeting: once per interactive login on a terminal, never for a
# script. SITE_QUIET_START=yes in site.env silences it (spark quiet start
# on). The file is read directly, with no python on the login path, so
# the environment's SITE_QUIET_START is not honoured here.
if [[ $- == *i* ]] && [ -t 1 ] && [ -r ~/.config/spark/banner ]; then
    if command -v spark >/dev/null 2>&1; then                       # blank row, logo, version, credits
        grep -qx 'SITE_QUIET_START=yes' ~/.config/spark/site.env 2>/dev/null || spark ver
    else printf '\n%b\n' "$(cat ~/.config/spark/banner)"; fi        # before bootstrap has linked spark
fi
