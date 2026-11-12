# shellcheck extended-analysis=false
# --- the dialog's search by meaning
# sets: MCP_ENV
# reads: DIALOG_BIN MODE OS PROVIDE_SECTIONS REPO SEMANTIC_LOG SEMANTIC_MODEL SEMANTIC_SHA256 SEMANTIC_SIZE SEMANTIC_URL SPARK_CONFIG_DIR STATE_DIR TMP
semantic_engine() {   # -> spark's llama-server: SPARK_ENGINE_DIR's, else the newest engine (the highest -bNNNN); false when none
    _sed=$(sed -n 's/^SPARK_ENGINE_DIR=//p' "$SPARK_CONFIG_DIR/spark.env" 2>/dev/null | tail -1 | sed 's/^"\(.*\)"$/\1/')
    tilde='~'; case $_sed in "$tilde"|"$tilde/"*) _sed=$HOME${_sed#"$tilde"} ;; esac
    if [ -n "$_sed" ]; then [ -x "$_sed/llama-server" ] && printf '%s\n' "$_sed/llama-server"; return; fi
    _seb=''; _sen=-2
    for _sex in "${XDG_DATA_HOME:-$HOME/.local/share}"/spark/engine/*/llama-server; do
        [ -f "$_sex" ] && [ -x "$_sex" ] || continue
        _sed=${_sex%/llama-server}; _sed=${_sed##*/}; _sek=-1
        case $_sed in *-b*) _sek=${_sed##*-b}; case $_sek in ''|*[!0-9]*) _sek=-1 ;; esac ;; esac
        [ "$_sek" -lt "$_sen" ] || { _sen=$_sek; _seb=$_sex; }   # of one number the last name wins, as spark sorts
    done
    [ -n "$_seb" ] && printf '%s\n' "$_seb"
}
semantic_model_here() { [ -f "$SEMANTIC_MODEL" ] && [ "$(stat -c %s "$SEMANTIC_MODEL" 2>/dev/null || stat -f %z "$SEMANTIC_MODEL" 2>/dev/null)" = "$SEMANTIC_SIZE" ]; }   # the model in place, by its size alone: asked at every open
semantic_model_ok() { semantic_model_here && [ "$(sha256_of "$SEMANTIC_MODEL")" = "$SEMANTIC_SHA256" ]; }   # the model in place is the one spark-shell pins
semantic_fetches() { [ -n "$(spark_bin)" ] && [ "$DIALOG_SEMANTIC" != no ] && [ "$SEMANTIC_URL" != none ] && ! semantic_model_here; }   # on desktop would fetch the model
semantic_why() {   # -> why the dialog keeps its word search; nothing when all is in place
    if [ "${DIALOG_SEMANTIC:-yes}" = no ]; then echo 'DIALOG_SEMANTIC=no'
    elif [ -z "$(spark_bin)" ]; then echo 'spark is not installed'
    elif ! semantic_engine >/dev/null; then echo "spark's engine is not installed (llama-server)"
    elif ! semantic_model_here; then echo 'the model is not installed (spark-shell on)'; fi
}
semantic_ours() { case $1 in ''|*[!0-9]*) return 1 ;; esac; { tr '\0' '\n' < "/proc/$1/cmdline"; } 2>/dev/null | grep -A1 -xF -- --host | grep -qxF -- "$SEMANTIC_SOCK"; }   # semantic_ours PID -- its --host is this session's socket (a reused pid, or the dialog's --semantic, is not)
semantic_pid() { _spp=$(cat "$SEMANTIC_PID" 2>/dev/null) || _spp=''; semantic_ours "$_spp" && printf '%s\n' "$_spp"; }   # -> the server's pid, while it is ours
semantic_up() {   # the server answers on the socket; with no curl to ask, its process is alive
    if command -v curl >/dev/null 2>&1; then curl --unix-socket "$SEMANTIC_SOCK" -sf -m 2 -o /dev/null http://localhost/health 2>/dev/null
    else semantic_pid >/dev/null; fi
}
semantic_start() {   # the server for this session, started when none answers or loads; not waited for
    semantic_where
    _sw=$(semantic_why); [ -z "$_sw" ] || refuse_in semantic "$_sw, so the dialog keeps its word search"
    ! semantic_up || return 0
    ! semantic_pid >/dev/null || return 0   # still loading: left to finish
    _sx=$(semantic_engine)
    mkdir_private "$SEMANTIC_RUN"; [ -L "$SEMANTIC_RUN" ] || chmod 700 "$SEMANTIC_RUN"
    # one start at a time
    [ -z "$(find "$SEMANTIC_RUN/semantic.lock" -mmin +1 2>/dev/null)" ] || lock_drop "$SEMANTIC_RUN/semantic.lock"   # a start that died left its lock
    lock_take "$SEMANTIC_RUN/semantic.lock" || return 0
    if semantic_up || semantic_pid >/dev/null; then lock_drop "$SEMANTIC_RUN/semantic.lock"; return 0; fi   # the other started it meanwhile
    semantic_stop
    mkdir_private "$STATE_DIR"
    set -- "$_sx" -m "$SEMANTIC_MODEL" --embedding --pooling mean --host "$SEMANTIC_SOCK" -ngl 0 -t 4 -c 2048 -b 2048 -ub 2048 --no-webui --log-disable --offline
    # its own session: a closed window never takes it
    if command -v setsid >/dev/null 2>&1; then setsid "$@" </dev/null >"$SEMANTIC_LOG" 2>&1 &
    else ( trap '' HUP; exec "$@" ) </dev/null >"$SEMANTIC_LOG" 2>&1 & fi
    _sk=$!; echo "$_sk" > "$SEMANTIC_PID"
    # the lock stays until the process is the server: before its exec its words are this script's
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do semantic_ours "$_sk" && break; [ -d "/proc/$_sk" ] || break; sleep 0.1; done
    lock_drop "$SEMANTIC_RUN/semantic.lock"
}
semantic_stop() {   # every server on this session's socket stopped; the pid file and the socket removed
    semantic_where
    _sps=$(semantic_pid || :)
    for _sc in $(grep -lF -- "$SEMANTIC_SOCK" /proc/[0-9]*/cmdline 2>/dev/null); do   # one read of every process's words
        _sq=${_sc#/proc/}; _sq=${_sq%/cmdline}
        ! semantic_ours "$_sq" || _sps="$_sps $_sq"
    done
    for _sp in $_sps; do
        kill "$_sp" 2>/dev/null || :
        for _i in 1 2 3 4 5 6 7 8 9 10; do semantic_ours "$_sp" || break; sleep 0.1; done   # gone before a new one takes the socket
    done
    rm -f "$SEMANTIC_PID" "$SEMANTIC_SOCK"
}
semantic_install() {   # the semantic row of on desktop: the model in place as pinned, or fetched and checked
    [ -n "$(spark_bin)" ] && [ "$DIALOG_SEMANTIC" != no ] || return 0
    if semantic_model_ok; then ok semantic "$SEMANTIC_MODEL, the sha256 spark-shell pins"; return 0; fi
    [ "$SEMANTIC_URL" != none ] || { skip semantic "no model to fetch (SPARK_SHELL_SEMANTIC_URL=none)"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo semantic "curl is not installed: the model cannot be fetched (spark-shell on installs it)"; return 0; }
    need semantic "fetch EmbeddingGemma 2 (310 MB) for the dialog's search by meaning and check its sha256" || return 0
    mkdir -p "$(dirname "$SEMANTIC_MODEL")"
    curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$SEMANTIC_MODEL.new" --connect-timeout 30 --speed-limit 1024 --speed-time 60 "$SEMANTIC_URL" 2>/dev/null || { rm -f "$SEMANTIC_MODEL.new"; row todo semantic "could not fetch EmbeddingGemma 2 -- spark-shell on again"; return 0; }
    [ "$(sha256_of "$SEMANTIC_MODEL.new")" = "$SEMANTIC_SHA256" ] || { rm -f "$SEMANTIC_MODEL.new"; row todo semantic "the EmbeddingGemma 2 fetched is not the one spark-shell pins: not installed"; return 0; }
    mv "$SEMANTIC_MODEL.new" "$SEMANTIC_MODEL"
    row ok semantic "EmbeddingGemma 2 installed ($SEMANTIC_MODEL), sha256 checked"
}
semantic_off() {   # off: the server stopped; the model stays
    semantic_where
    [ -e "$SEMANTIC_PID" ] || [ -e "$SEMANTIC_SOCK" ] || return 0
    if [ "$MODE" = dry ]; then row would semantic "stop the server of the dialog's search ($SEMANTIC_SOCK)"; return 0; fi
    semantic_stop; row ok semantic "the server of the dialog's search stopped"
}
cmd_semantic() {   # cmd_semantic start|stop|status -- the server of the dialog's search by meaning
    config_load
    semantic_where
    case ${1:-} in
        start) semantic_start ;;
        stop) semantic_stop ;;
        status) if semantic_up; then echo "semantic search: running at $SEMANTIC_SOCK"; else echo "semantic search: not running ($SEMANTIC_SOCK)"; fi ;;
        *) refuse_in semantic "start, stop or status: spark-shell semantic status" ;;
    esac
}

# --- spark's MCP list
MCP_ENV=${SPARK_MCP_ENV:-$SPARK_CONFIG_DIR/mcp.env}
mcp_spark() { _sp=$(spark_bin); [ -n "$_sp" ] && "$_sp" help </dev/null 2>/dev/null | grep -q '^ *spark mcp ' && printf '%s\n' "$_sp"; }   # -> spark, when it has the mcp verb
mcp_line() { [ -f "$MCP_ENV" ] || return 0; sed -n "s/^MCP_SERVER_$(printf '%s' "$1" | tr 'a-z' 'A-Z')=//p" "$MCP_ENV" | tail -1 | sed 's/^"\(.*\)"$/\1/'; }   # mcp_line NAME -> its program and words on spark's list
mcp_ours() { case $(mcp_line "$1") in */spark-shell" provide $1") return 0 ;; *) return 1 ;; esac; }   # spark-shell's line, this clone's or an older one's
mcp_mine() { for s in $PROVIDE_SECTIONS; do if mcp_ours "$s"; then printf ' %s' "$s"; fi; done; }   # -> " NAME..." the lines on spark's list that are ours
mcp_apply() {   # the mcp row of `on desktop`: each provider on spark's MCP list
    _sp=$(mcp_spark) || { skip mcp "spark 1.90 or newer lists the desktop's tools (spark update)"; return 0; }
    _want=''; _theirs=''
    for s in $PROVIDE_SECTIONS; do
        _l=$(mcp_line "$s")
        if [ "$_l" = "$REPO/spark-shell provide $s" ]; then continue; fi
        if [ -n "$_l" ] && ! mcp_ours "$s"; then _theirs="$_theirs $s"; else _want="$_want $s"; fi
    done
    [ -z "$_theirs" ] || row todo mcp "already on spark's MCP list as servers of yours, left as they are:$_theirs"
    if [ -z "$_want" ]; then ok mcp "spark-shell's providers are on spark's MCP list"; return 0; fi
    need mcp "put$_want on spark's MCP list" || return 0
    for s in $_want; do
        if mcp_ours "$s"; then "$_sp" mcp rm "$s" </dev/null >/dev/null 2>&1 || :; fi   # a line an older clone wrote
        "$_sp" mcp add "$s" "$REPO/spark-shell" provide "$s" </dev/null >/dev/null 2>"$TMP/mcp.err" || { row todo mcp "$s: $(head -1 "$TMP/mcp.err") -- spark-shell on desktop again"; return 0; }
    done
    row ok mcp "$(mcp_mine | wc -w | tr -d ' ') providers on spark's MCP list: the prompt line and spark do know the desktop's tools"
}
mcp_off() {   # off: our lines off spark's MCP list; a server of yours stays
    _sp=$(mcp_spark) || return 0
    _mo=$(mcp_mine); [ -n "$_mo" ] || return 0
    for s in $_mo; do "$_sp" mcp rm "$s" </dev/null >/dev/null 2>&1 || :; done
    row ok mcp "$(printf '%s' "$_mo" | wc -w | tr -d ' ') providers off spark's MCP list"
}
dialog_sections() {   # dialog_sections [FIRST] -> the providers the dialog starts, FIRST on top
    panel_sections "${1:-glance}" | grep -vxE 'spark|undo|glance|chat' || :
}
cmd_dialog() {   # cmd_dialog [SECTION|about|chat] -- home, its conversation, or a section
    if [ "${SPARK_DIALOG_WINDOW:-}" = 1 ] && [ "${1:-}" != chat ] && [ -t 0 ] && [ -t 1 ]; then
        # the dialog's own window: nothing drawn ahead of its opening; a key typed now lands at its prompt
        stty -echo -icanon 2>/dev/null || :
        printf '\033[?25l'
    else
        [ ! -t 1 ] || printf '\033[?25l'   # no cursor while it starts: the dialog puts it back
    fi
    _dwin=${SPARK_DIALOG_WINDOW:-}   # the window maps unseen; the dialog shows it once its opening is drawn
    unset SPARK_DIALOG_WINDOW   # read once: a terminal a step opens from here is no dialog's window
    config_load
    [ "$OS" != Darwin ] || refuse_in dialog "the dialog is the Linux desktop's; in a terminal here, spark-shell panel"
    command -v jq >/dev/null 2>&1 || refuse_in dialog "jq is not installed (spark-shell on)"
    pm_detect; theme_load; SND=$(snd_tool)
    _first=${1:-}
    case $_first in ''|about|help|chat|files) ;; *) panel_section_ok "$_first" || refuse_in dialog "$_first is not a section of the dialog" ;; esac
    _db=${SPARK_SHELL_DIALOG:-$DIALOG_BIN}
    if [ -n "${SPARK_SHELL_DIALOG:-}" ]; then
        [ -x "$_db" ] || refuse_in dialog "SPARK_SHELL_DIALOG is not executable"
    else
        dialog_ok || refuse_in dialog "the dialog is not installed, or not the release's -- spark-shell on"
    fi
    case $REPO in *[[:space:]]*) refuse_in dialog "the clone's path holds a space, and a provider is argv words: move it ($REPO)" ;; esac
    set --
    _ds=$_first; case $_ds in files|chat|help) _ds='' ;; esac   # built-in views are not provider sections
    for s in $(dialog_sections "$_ds"); do
        [ "$s" != about ] || set -- "$@" --provider "$REPO/spark-shell provide files"   # files just before about
        set -- "$@" --provider "$REPO/spark-shell provide $s"
    done
    case " $* " in *" provide files "*) ;; *) set -- "$@" --provider "$REPO/spark-shell provide files" ;; esac
    case " $* " in *" provide clock "*) ;; *) set -- "$@" --provider "$REPO/spark-shell provide clock" ;; esac   # clock: the calendar opens from any view
    case $_first in '') ;; *) set -- "$@" --home "$_first" ;; esac
    _dc=''; [ "$DIALOG_ATTACH" != yes ] || _dc=plus; [ "$DIALOG_MODEL" != yes ] || _dc="${_dc:+$_dc,}model"; [ "$DIALOG_TALK" != yes ] || _dc="${_dc:+$_dc,}talk"
    _sp=$(spark_bin); set -- "$@" --spark "$_sp"
    _ta=$(dialog_transitions); [ -z "$_ta" ] || set -- "$@" --transitions "$_ta"
    # started aside, never waited for; only inside the desktop, whose end stops it (ssh would leave it running)
    if [ -z "$(semantic_why)" ]; then
        semantic_where
        if wm_session || [ -n "${WAYLAND_DISPLAY:-}" ]; then ( semantic_start ) </dev/null >/dev/null 2>&1 & fi
        set -- "$@" --semantic "$SEMANTIC_SOCK"
    fi
    FULL_ID=''; ! panel_own_window || panel_full_aside
    ! desktop_wanted || case ${TERM:-} in foot*) SPARK_DIALOG_SLOTS=1; export SPARK_DIALOG_SLOTS ;; esac   # foot's five slots: a new look recolors the dialog in place
    st=0; "$_db" "$@" --composer "$_dc" --attach "$DIALOG_ATTACH_TYPES" --spark-shell "$REPO/spark-shell" || st=$?
    [ "$st" -eq 3 ] || panel_full_back   # 3: a step put a window on the screen, and the window is the receipt
    [ "$st" -eq 3 ] || [ "$st" -eq 0 ] || return "$st"
}

