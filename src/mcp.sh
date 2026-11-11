# shellcheck extended-analysis=false
# --- the wire: the MCP server on stdio, one process on fd 3
# sets: PROVIDE_POLL PROVIDE_WATCHED
# reads: ANIMATION_NAMES CONFIG FONT_FACES GLYPH_FAMILIES NOTES_DIR OS PROVIDE_LINE_MAX PROVIDE_PROTOCOL PROVIDE_SECTIONS REPO TAB THEME_ENV THEME_KEYS TMP TOOLS_CHECK
# the wire: only MCP reaches stdout, fd 3; fd 1 goes to stderr before any
# step runs. One process writes fd 3, the loop; the reader ("in LINE") and
# the watcher ("poke") feed it through one FIFO, a line under a lock
rpc_send() { ( printf '%s\n' "$1" >&3 ) 2>/dev/null || :; }   # from a subshell: a closed wire (the dialog gone) ends the subshell, never the provider mid-request
rpc_result() { printf '%s' "$2" | jq -c --argjson id "$1" '{jsonrpc: "2.0", id: $id, result: .}' >&3; }   # rpc_result ID JSON (the result on stdin to jq: no argument grows past a limit)
rpc_error() { rpc_send "$(jq -cn --argjson id "$1" --argjson c "$2" --arg m "$3" '{jsonrpc: "2.0", id: $id, error: {code: $c, message: $m}}')"; }   # rpc_error ID CODE MESSAGE
rpc_note() { rpc_send "$(jq -cn --arg m "$1" --argjson p "$2" '{jsonrpc: "2.0", method: $m, params: $p}')"; }   # rpc_note METHOD PARAMS -- a notification
fifo_put() {   # fifo_put LINE -- one line into the loop's FIFO (fd 5), under the lock, so a long line is never cut by a poke
    # a lock older than two seconds was left by a writer killed mid-line, and is taken
    _fpw=0; until lock_take "$PLOCK"; do _fpw=$((_fpw + 1)); [ "$_fpw" -lt 200 ] || { lock_drop "$PLOCK"; _fpw=0; }; sleep 0.01; done
    printf '%s\n' "$1" >&5 || :; lock_drop "$PLOCK"
}
PROVIDE_POLL=${SPARK_SHELL_PROVIDE_POLL:-}   # the watcher's seconds between looks; the tests set it
# the sections the desktop changes behind the dialog; every other changes only by a step, whose answer carries its rows
PROVIDE_WATCHED=${SPARK_SHELL_PROVIDE_WATCHED:-wifi bt out mic storage window notifications}
provide_seen() { cksum < "$TMP/rows.last" > "$TMP/rows.seen"; }   # the rows the host was last sent, as the watcher compares them
provide_watch() {   # provide_watch SECTION [PAGE] -- the rows, or a page, read again every few seconds; a change pokes the loop. Its own TMP
    _seen=$TMP/rows.seen; _wpage=${2:-}; TMP=$TMP/watch; mkdir -p "$TMP"
    _every=$PROVIDE_POLL; [ -n "$_every" ] || case $(panel_cost "$1") in slow) _every=15 ;; fast) _every=5 ;; *) _every=3 ;; esac
    if [ -n "$_wpage" ]; then   # a page: every change pokes
        _last=$(provide_tools_page "$_wpage" 2>/dev/null | cksum)
        while :; do
            sleep "$_every"
            _now=$(provide_tools_page "$_wpage" 2>/dev/null | cksum)
            [ "$_now" = "$_last" ] || { _last=$_now; fifo_put poke; }
        done
    fi
    _last=$(provide_rows "$1" 2>/dev/null | cksum)
    while :; do
        sleep "$_every"
        config_load; theme_load
        _now=$(provide_rows "$1" 2>/dev/null | cksum)
        # a change pokes once; rows the host already has (a call's answer carried them) poke nothing
        _had=''; [ ! -f "$_seen" ] || IFS= read -r _had < "$_seen" || :
        [ "$_now" = "$_last" ] || { _last=$_now; [ "$_now" = "$_had" ] || fifo_put poke; }
    done
}
provide_watch_check() {   # provide_watch_check SUM -- the check's record read again every few seconds; a change pokes the loop. SUM the record as it was before the answer, so a check that ends at once is not missed
    _every=${PROVIDE_POLL:-3}; _last=$1
    while :; do
        sleep "$_every"
        _now=$({ cksum < "$TOOLS_CHECK"; } 2>/dev/null)
        [ "$_now" = "$_last" ] || { _last=$_now; fifo_put poke; }
    done
}
provide_input() {   # stdin -> the loop's FIFO, a line each; a pairing agent's answers go to it directly
    while IFS= read -r _l || [ -n "$_l" ]; do
        if [ -S "$TMP/bt.sock" ] && [ "${#_l}" -le "$PROVIDE_LINE_MAX" ]; then
            if printf '%s' "$_l" | jq -e '(.id | type) == "string" and (.id | startswith("bt-pair-")) and (has("method") | not)' >/dev/null 2>&1; then
                printf '%s\n' "$_l" | python3 "$REPO/lib/bt_agent.py" --reply "$TMP" || :
                _l=''; continue
            fi
            if printf '%s' "$_l" | jq -e --slurpfile id "$TMP/bt.call-id" '.method == "notifications/cancelled" and .params.requestId == $id[0]' >/dev/null 2>&1; then
                : > "$TMP/bt.cancel"; _l=''; continue
            fi
        fi
        fifo_put "in $_l"; _l=''
    done
    [ ! -S "$TMP/bt.sock" ] || : > "$TMP/bt.cancel"
    fifo_put eof
}

provide_main() {   # provide_main SECTION -- serve it until stdin ends
    sec=$1
    case " $PROVIDE_SECTIONS " in *" $sec "*) ;; *) refuse_in provide "${sec:-a section} is not one: $(printf '%s' "$PROVIDE_SECTIONS" | sed 's/ /, /g')" >&2 ;; esac   # a refusal on stderr: stdout is the wire
    command -v jq >/dev/null 2>&1 || refuse_in provide "jq is not installed (spark-shell on)" >&2
    command -v mkfifo >/dev/null 2>&1 || refuse_in provide "mkfifo is not installed" >&2
    config_load; [ "$OS" = Darwin ] || pm_detect; theme_load; SND=''; [ "$OS" = Darwin ] || SND=$(snd_tool)
    PANEL_VERSION_NOW=$(panel_version); PANEL_VERSION_READ=1   # once a provider: the release does not change under it
    [ "$sec" != display ] || { if saver_can; then SAVER_CAN_NOW=1; else SAVER_CAN_NOW=0; fi; }   # python3 asked once a provider, not twice a read
    [ "$sec" != tools ] || tools_sbom_warm   # the installed list, ready before software opens
    exec 3>&1 1>&2 6<&0   # fd 3 the wire out, fd 6 the wire in; whatever a step prints goes to stderr
    WATCH=''; READER=''; SUBSCRIBED=''; PLOCK=$TMP/in.lock; PROOTS=$TMP/roots; CLIENT_ROOTS=''; CLIENT_PAIRING=''; : > "$PROOTS"
    REM_DELETED=$TMP/deleted   # a reminder deleted here is kept until the provider ends: its undo
    LAYOUT_DELETED=$TMP/deleted-layouts   # and a layout
    trap '{ [ -z "$WATCH" ] || kill "$WATCH"; [ -z "$READER" ] || kill "$READER"; files_stop; files_sound_stop; } 2>/dev/null || :; rm -rf "$TMP"' EXIT   # the reader has ended with stdin: a kill that finds nobody is no failure
    trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # a signal ends the provider through the EXIT trap
    mkfifo "$TMP/in"
    ( provide_input ) <&6 5>"$TMP/in" 3>&- & READER=$!
    exec 4<"$TMP/in" 6<&-
    while IFS= read -r _msg <&4; do
        case $_msg in
            eof) break ;;
            poke) [ -z "$SUBSCRIBED" ] || rpc_note notifications/resources/updated "$(jq -cn --arg u "spark-shell://$sec/rows" '{uri: $u}')" ;;
            "in "*) provide_one "${_msg#in }" || : ;;
        esac
    done
}
provide_one() {   # provide_one LINE -- one message: a request answered, a notification taken, anything else refused
    [ "${#1}" -le "$PROVIDE_LINE_MAX" ] || { rpc_error null -32600 "a message is $PROVIDE_LINE_MAX bytes at most"; return 0; }
    # one jq reads the message, a line each: compact JSON holds no newline, a method's control characters are spaces
    _parts=$(printf '%s' "$1" | jq -r 'if type != "object" or .jsonrpc != "2.0" then "bad", "null", "", "{}", "{}"
        else (if (has("method") | not) then "answer" elif has("id") then "request" else "note" end),
            (.id | tojson), (.method // "" | tostring | gsub("[\u0000-\u001f]"; " ")), (.params // {} | tojson), (.result // {} | tojson) end' 2>/dev/null) \
        || { rpc_error null -32700 "not JSON"; return 0; }
    { IFS= read -r _kind; IFS= read -r _id; IFS= read -r _method; IFS= read -r _params; IFS= read -r _result; } <<EOF
$_parts
EOF
    case $_kind in
        request) ;;
        answer)   # the one question this server asks: the host's roots
            [ "$_id" = '"roots"' ] && provide_roots "$_result"; return 0 ;;
        note)   # ask the host for its roots when it has them
            case $_method in notifications/initialized|notifications/roots/list_changed)
                [ -z "$CLIENT_ROOTS" ] || rpc_send "$(jq -cn '{jsonrpc: "2.0", id: "roots", method: "roots/list"}')" ;; esac
            return 0 ;;
        *) rpc_error null -32600 "one JSON-RPC 2.0 object a line"; return 0 ;;
    esac
    case $_id in '"'*|[0-9]*|-[0-9]*) ;; *) rpc_error null -32600 "an id is a string or a number"; return 0 ;; esac
    case $_method in
        initialize)
            PROVIDE_CLIENT=$(printf '%s' "$_params" | jq -r '.clientInfo.name // "" | tostring | gsub("[^A-Za-z0-9._-]"; "")')
            [ "$(printf '%s' "$_params" | jq -r '.capabilities.experimental["spark-shell/pairing"] == true')" != true ] || CLIENT_PAIRING=1
            [ "$(printf '%s' "$_params" | jq -r '.capabilities.roots != null')" != true ] || CLIENT_ROOTS=1
            rpc_result "$_id" "$(jq -cn --arg v "$PROVIDE_PROTOCOL" --arg n "$sec" --arg t "$(provide_title "$sec")" --arg ver "$(panel_version)" \
                '{protocolVersion: $v, capabilities: {tools: {listChanged: true}, resources: {subscribe: true, listChanged: true}, logging: {}}, serverInfo: {name: $n, title: $t, version: $ver}}')" ;;
        ping|logging/setLevel) rpc_result "$_id" '{}' ;;
        tools/list) rpc_result "$_id" "$(provide_tools "$sec" | jq -c '{tools: .}')" ;;
        tools/call) provide_call "$_id" "$_params" ;;
        resources/list) rpc_result "$_id" "$(jq -cn --arg u "spark-shell://$sec/rows" --arg s "$sec" '{resources: [{uri: $u, name: "rows", title: ($s + " rows"), mimeType: "application/json"}]}')" ;;
        resources/templates/list) if [ "$sec" = files ]; then rpc_result "$_id" '{"resourceTemplates":[{"uriTemplate":"spark-shell://files/rows/{folder}{?from}","name":"folder","title":"a folder under the roots, a page of it from an entry","mimeType":"application/json"},{"uriTemplate":"spark-shell://files/rows/match/{words}","name":"match","title":"the names under your home that hold the words","mimeType":"application/json"},{"uriTemplate":"spark-shell://files/preview/{file}{?page}","name":"preview","title":"a file shown as a page","mimeType":"application/json"}]}'
            else rpc_result "$_id" "$(jq -cn --arg s "$sec" '{resourceTemplates: ([{uriTemplate: ("spark-shell://" + $s + "/page/{row}"), name: "page", title: "a row shown as a page", mimeType: "application/json"}] + (if $s == "notes" then [{uriTemplate: "spark-shell://notes/rows/find/{words}", name: "find", title: "the notes whose text holds the words", mimeType: "application/json"}] else [] end))}')"; fi ;;
        resources/read|resources/subscribe|resources/unsubscribe)
            _uri=$(printf '%s' "$_params" | jq -r '.uri // "" | tostring')
            if [ "$sec" = files ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://files/rows/?*) true ;; *) false ;; esac; then   # a folder under the roots, or the trash
                if provide_files_rows "$_uri" > "$TMP/folder.json"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/folder.json")"
                else rpc_error "$_id" -32002 "no folder at that uri"; fi
                return 0
            fi
            if [ "$sec" = files ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://files/preview/?*) true ;; *) false ;; esac; then   # a file shown as a page
                _pu=${_uri#spark-shell://files/preview/}; _ppg=1; _ppf=''
                case $_pu in *'?'*) _pq=${_pu#*'?'}; _pu=${_pu%%'?'*}
                    case "&$_pq&" in *'&page='*) _ppg=${_pq#*page=}; _ppg=${_ppg%%'&'*} ;; esac
                    case "&$_pq&" in *'&full=1&'*) _ppf=full ;; esac ;;
                esac
                if _pp=$(files_unb64 "$_pu") && files_page "$_pp" "$_ppg" "$_ppf" > "$TMP/page.out"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/page.out")"
                else rpc_error "$_id" -32002 "no file at that uri"; fi
                return 0
            fi
            if [ "$sec" = theme ] && [ "$_uri" = "spark-shell://theme/rows/wallpapers" ] && [ "$_method" = resources/read ]; then   # the wallpaper list
                provide_wall_rows > "$TMP/wall.last"   # the rows the host has: the gate's
                rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/wall.last")"; return 0
            fi
            if [ "$sec" = theme ] && [ "$_uri" = "spark-shell://theme/rows/animations" ] && [ "$_method" = resources/read ]; then   # the animation list
                rpc_result "$_id" "$(provide_anim_rows | jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}')"; return 0
            fi
            if [ "$sec" = display ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://display/rows/screen/?*) true ;; *) false ;; esac; then
                if provide_screen_rows "${_uri##*/}" > "$TMP/screen.json"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/screen.json")"
                else rpc_error "$_id" -32002 "no screen at that uri"; fi
                return 0
            fi
            if { [ "$sec" = lan ] || [ "$sec" = wifi ]; } && [ "$_method" = resources/read ] && case $_uri in spark-shell://"$sec"/rows/network/?*) true ;; *) false ;; esac; then
                if provide_network_rows "$sec" "${_uri##*/}" > "$TMP/network.rows"; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/network.rows")"
                else rpc_error "$_id" -32002 "no network interface at that uri"; fi
                return 0
            fi
            if [ "$sec" = window ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://window/rows/?*) true ;; *) false ;; esac; then   # a picker of the workspace place
                rpc_result "$_id" "$(provide_window_rows "$_uri" | jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}')"; return 0
            fi
            if [ "$sec" = tools ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://tools/rows/?*) true ;; *) false ;; esac; then   # a tool's page
                if provide_tools_page "${_uri#spark-shell://tools/rows/}" > "$TMP/tools.page" 2>/dev/null && [ -s "$TMP/tools.page" ]; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/tools.page")"
                else rpc_error "$_id" -32002 "no tool page at that uri"; fi
                return 0
            fi
            if [ "$sec" = clock ] && [ "$_method" = resources/read ] && [ "$_uri" = "spark-shell://clock/rows/settings" ]; then
                rpc_result "$_id" "$(provide_rows clock settings | jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}')"; return 0
            fi
            if [ "$_method" = resources/read ] && case $_uri in "spark-shell://$sec/page/"?*) true ;; *) false ;; esac; then   # a row shown as a page, Space's
                if _pid=$(files_unb64 "${_uri#"spark-shell://$sec/page/"}") && provide_page "$sec" "$_pid" > "$TMP/rowpage.json" 2>/dev/null && [ -s "$TMP/rowpage.json" ]; then rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/rowpage.json")"
                else rpc_error "$_id" -32002 "no page at that uri"; fi
                return 0
            fi
            if [ "$sec" = notes ] && [ "$_method" = resources/read ] && case $_uri in spark-shell://notes/rows/find/?*) true ;; *) false ;; esac; then   # the notes whose text holds every word, for a search from Home
                if NOTES_WORDS=$(files_unb64 "${_uri##*/}") && [ -n "$NOTES_WORDS" ] && provide_rows notes > "$TMP/notes.found.json"; then
                    rpc_result "$_id" "$(jq -c --arg u "$_uri" '.rows |= map(select(.tool.name == "notes_open")) | .short = [] | {contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/notes.found.json")"
                else rpc_error "$_id" -32002 "no search at that uri"; fi
                NOTES_WORDS=''
                return 0
            fi
            if [ "$sec" = tools ] && [ "$_uri" = "spark-shell://tools/rows/running" ]; then   # running, read again every 3 seconds while it is on screen
                case $_method in
                    resources/subscribe) SUBSCRIBED=1; [ -n "$WATCH" ] || { provide_watch tools running 5>"$TMP/in" 3>&- 4<&- & WATCH=$!; }; rpc_result "$_id" '{}' ;;
                    resources/unsubscribe) SUBSCRIBED=''; [ -z "$WATCH" ] || { kill "$WATCH" 2>/dev/null || :; wait "$WATCH" 2>/dev/null || :; WATCH=''; }; rpc_result "$_id" '{}' ;;
                esac
                return 0
            fi
            [ "$_uri" = "spark-shell://$sec/rows" ] || { rpc_error "$_id" -32002 "no resource at that uri"; return 0; }
            case $_method in
                resources/read) provide_rows "$sec" > "$TMP/rows.last"; provide_seen   # the rows the host has: the gate's, the watcher's
                    rpc_result "$_id" "$(jq -c --arg u "$_uri" '{contents: [{uri: $u, mimeType: "application/json", text: tojson}]}' "$TMP/rows.last")" ;;
                resources/subscribe) SUBSCRIBED=1
                    case " $PROVIDE_WATCHED " in *" $sec "*) [ -n "$WATCH" ] || { provide_watch "$sec" 5>"$TMP/in" 3>&- 4<&- & WATCH=$!; } ;; esac
                    [ "$sec" != tools ] || [ -n "$WATCH" ] || { _sum=$({ cksum < "$TOOLS_CHECK"; } 2>/dev/null); provide_watch_check "$_sum" 5>"$TMP/in" 3>&- 4<&- & WATCH=$!; }
                    rpc_result "$_id" '{}' ;;
                resources/unsubscribe) SUBSCRIBED=''; [ -z "$WATCH" ] || { kill "$WATCH" 2>/dev/null || :; wait "$WATCH" 2>/dev/null || :; WATCH=''; }; rpc_result "$_id" '{}' ;;
            esac ;;
        *) rpc_error "$_id" -32601 "no method $_method here" ;;
    esac
}
provide_notes_append() {   # two typed arguments; note contents never travel through the panel's token grammar
    printf '%s' "$2" | jq -e 'type == "object" and keys == ["name","text"]
        and (.name | type == "string" and length > 0 and length <= 255 and (test("[\u0000-\u001f\u007f-\u009f/]") | not))
        and (.text | type == "string" and length > 0 and length <= 16384 and (test("[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]") | not))' >/dev/null 2>&1 \
        || { rpc_error "$1" -32602 'notes_append takes an exact filename and text of 1 to 16384 characters; only tabs and line breaks are allowed controls'; return 0; }
    _pna_name=$(printf '%s' "$2" | jq -r .name)
    printf '%s' "$2" | jq -j .text > "$TMP/note.append" || { provide_refuse "$1" 'the text could not be prepared; nothing appended'; return 0; }
    rm -f "$TMP/action.effect"
    if _pna_out=$(PROVIDE_EFFECT=1 note_append "$_pna_name" "$TMP/note.append" 2>/dev/null); then
        rm -f "$TMP/note.append"
        [ -s "$TMP/action.effect" ] || { provide_refuse "$1" 'the text may have been appended, but the note could not be read back; check it before trying again'; return 0; }
        rpc_result "$1" "$(jq -cn --arg r "$_pna_out" --slurpfile e "$TMP/action.effect" '{receipt:$r,effect:$e[0]}' | jq -c '{content:[{type:"text",text:tojson}],structuredContent:.,isError:false}')"
        [ -z "$SUBSCRIBED" ] || rpc_note notifications/resources/updated '{"uri":"spark-shell://notes/rows"}'
    else
        rm -f "$TMP/note.append"
        provide_refuse "$1" "${_pna_out:-could not append the text; check the note before trying again}"
    fi
}
provide_notes_step() {   # provide_notes_step ID TOOL ARGS -- a note renamed, put in the trash or brought back: by its exact filename, the undo in its result
    printf '%s' "$3" | jq -e --arg t "$2" 'type == "object" and (.name | type == "string" and length <= 255 and test("^[^./\u0000-\u001f\u007f][^/\u0000-\u001f\u007f]*[.]md$"))
        and (if $t == "notes_rename" then keys == ["name","to"] and (.to | type == "string" and length > 0 and length <= 255 and (test("[\u0000-\u001f\u007f-\u009f]") | not)) else keys == ["name"] end)' >/dev/null 2>&1 \
        || { rpc_error "$1" -32602 "$2 takes a note's exact filename$([ "$2" != notes_rename ] || echo ', and a title of 1 to 255 characters')"; return 0; }
    _nsn=$(printf '%s' "$3" | jq -r .name)
    _nsd=$(realpath "$NOTES_DIR" 2>/dev/null) || { provide_refuse "$1" "notes: there is no ~/notes"; return 0; }
    _nsf=$_nsd/$_nsn
    case $2 in notes_rename|notes_trash) [ -f "$_nsf" ] && [ ! -L "$_nsf" ] || { provide_refuse "$1" "notes: no note is called $_nsn now"; return 0; } ;; esac
    _nsp=${PROOTS:-}; files_home_root > "$TMP/notes.roots"; PROOTS=$TMP/notes.roots   # the trash a note goes to is your home's, whatever roots the host gave
    case $2 in
        notes_rename)
            _nst=$(printf '%s' "$3" | jq -r .to)
            _nso=$(awk 'NF { sub(/^#+[ \t]*/, ""); print; exit }' "$_nsf"); [ -n "$_nso" ] || _nso=${_nsn%.md}   # the old title as written, for the undo
            _nsw=$(note_name "$_nsf")
            if note_retitle "$_nsf" "$_nst"; then files_result "$1" "$_nsw renamed to $(note_name "$_nsf")" notes_rename "$(jq -cn --arg n "$_nsn" --arg t "$_nso" '{name: $n, to: $t}')"
            else provide_refuse "$1" "notes: could not rename $_nsw"; fi ;;
        notes_trash)
            _nsw=$(note_name "$_nsf")
            if _nsx=$(files_trash "$_nsf"); then files_result "$1" "$_nsw is in the trash" notes_restore "$(jq -cn --arg n "$_nsn" '{name: $n}')"
            else provide_refuse "$1" "notes: $_nsx"; fi ;;
        notes_restore)
            if _nsx=$(files_restore "$_nsf"); then files_result "$1" "$(note_name "$_nsf") is back" notes_trash "$(jq -cn --arg n "$_nsn" '{name: $n}')"
            else provide_refuse "$1" "notes: $_nsx"; fi ;;
    esac
    PROOTS=$_nsp
}
note_retitle() {   # note_retitle FILE TITLE -- the first line that says something becomes TITLE, its hashes kept; none: TITLE as a heading
    _nrt=$(mktemp "${1%/*}/.retitle.XXXXXX") || return 1
    T=$2 awk 'BEGIN { t = ENVIRON["T"] } !done && NF { if (match($0, /^#+[ \t]*/)) print substr($0, 1, RLENGTH) t; else print t; done = 1; next } { print } END { if (!done) print "# " t }' "$1" > "$_nrt" \
        && mv "$_nrt" "$1" || { rm -f "$_nrt"; return 1; }
}
provide_ask() {   # provide_ask CALL-ID MESSAGE FIELD TITLE -> what the person typed for FIELD (MCP elicitation); false when declined, cancelled or unanswered in five minutes
    _aid="ask-$1"
    rpc_send "$(jq -cn --arg i "$_aid" --arg m "$2" --arg f "$3" --arg t "$4" '{jsonrpc: "2.0", id: $i, method: "elicitation/create", params: {message: $m, requestedSchema: {type: "object", properties: {($f): {type: "string", title: $t, maxLength: 256}}, required: [$f]}}}')"
    ( sleep 300; fifo_put "in $(jq -cn --arg i "$_aid" '{jsonrpc: "2.0", id: $i, result: {action: "cancel"}}')" ) >/dev/null 2>&1 3>&- 4<&- & _ag=$!   # its own fds: this function runs in a command substitution, and a child holding its stdout would hold the answer five minutes
    _ans=''; _ast=1
    while IFS= read -r _am <&4; do   # the loop's lines until the answer: a poke is dropped, another request is told to wait, eof ends the provider
        case $_am in
            eof) kill "$_ag" 2>/dev/null || :; exit 0 ;;   # the wire ended: the provider with it
            poke) continue ;;
            "in "*) _al=${_am#in }
                case $(printf '%s' "$_al" | jq -r --arg i "$_aid" 'if .id == $i and (has("method") | not) then "mine" elif has("method") and has("id") then "request" else "other" end' 2>/dev/null) in
                    mine) _ans=$(printf '%s' "$_al" | jq -r --arg f "$3" 'select(.result.action == "accept") | .result.content[$f] // "" | tostring' 2>/dev/null | scrub_text | tr -d '\n' | cut -c1-256)
                        [ -z "$_ans" ] || _ast=0
                        break ;;
                    request) rpc_error "$(printf '%s' "$_al" | jq -c '.id')" -32000 "a question is open: answer it, or Esc" ;;
                esac ;;
        esac
    done
    { ! command -v pgrep >/dev/null 2>&1 || kill $(pgrep -P "$_ag") 2>/dev/null; kill "$_ag" 2>/dev/null; } || :   # the sleeper and its sleep
    [ "$_ast" -eq 0 ] || return 1
    printf '%s' "$_ans"
}
provide_call() {   # provide_call ID PARAMS -- the step: the tool, its arguments checked, the row, the gate, then the step
    # the name, the arguments and the progress token in one jq: a line each, compact JSON holds no newline
    _parts=$(printf '%s' "$2" | jq -r '(.name // "" | tostring | gsub("[\u0000-\u001f]"; " ")), (.arguments // {} | tojson), (._meta.progressToken // "" | if . == "" then "" else tojson end)')
    { IFS= read -r _name; IFS= read -r _args; IFS= read -r _tok; } <<EOF
$_parts
EOF
    case $_name in *[!a-z0-9_]*|[!a-z]*|'') rpc_error "$1" -32602 "no tool by that name"; return 0 ;; esac
    WIN_LABELS_READ=''   # a call's own read of the windows is its alone
    { tool_spec "$_name" && [ "$_ts" = "$sec" ]; } || { rpc_error "$1" -32602 "no tool $_name in $sec"; return 0; }
    case $_th in *p*) provide_person_ok || { rpc_error "$1" -32602 "$_name runs from its row in the dialog, never from a plan"; return 0; } ;; esac
    _title=$_tt   # the call's own title: the undo's tool_spec below sets _tt to its own
    [ "$_name" != notes_append ] || { provide_notes_append "$1" "$_args"; return 0; }
    case $_name in notes_rename|notes_trash|notes_restore) provide_notes_step "$1" "$_name" "$_args"; return 0 ;; esac   # a note's file by its exact name, as the append
    _bad=$(printf '%s' "$_args" | jq -r --arg p "$_tp" --arg k "$_tk" --arg q "$_tq" --arg x "$_te" '
        def plain: test("^[^\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff\u2028\u2029]{1,256}$");
        ($x | split(" ") | map(select(. != "") | split(":") | [(.[0] | rtrimstr("?")), .[1], (.[0] | endswith("?"))])) as $xs | ($xs | map(.[0])) as $xk | . as $a |
        [$xs[] | select(.[1] != "text" and .[1] != "seconds" and .[1] != "pixels" and (.[2] | not))] as $xr | [$xs[] | select(. as $e | $a | has($e[0]))] as $xp |   # the extras a call must give; the ones this call gave
        if type != "object" then "arguments are an object"
        elif (keys - [$p, $q] - $xk - [""]) != [] then "no argument " + ((keys - [$p, $q] - $xk)[0])
        elif $p != "" and (has($p) | not) then "missing " + $p
        elif ([$xr[] | select(. as $e | $a | has($e[0]) | not)] | length) > 0 then "missing " + ([$xr[] | select(. as $e | $a | has($e[0]) | not)][0][0])
        elif ([$xp[] | select(.[1] != "text" and .[1] != "name" and .[1] != "filename" and .[1] != "path" and .[1] != "coordinate" and .[1] != "scale" and .[1] != "mode" and .[1] != "port" and .[1] != "net" and .[1] != "seconds" and .[1] != "pixels") | . as $e | select((($e[1] | split("|")) | index([$a[$e[0]]])) | not)] | length) > 0 then ([$xp[] | select(.[1] != "text" and .[1] != "name" and .[1] != "filename" and .[1] != "path" and .[1] != "coordinate" and .[1] != "scale" and .[1] != "mode" and .[1] != "port" and .[1] != "net" and .[1] != "seconds" and .[1] != "pixels") | . as $e | select((($e[1] | split("|")) | index([$a[$e[0]]])) | not)][0] | .[0] + " is one of " + (.[1] | split("|") | join(", ")))
        elif any($xp[]; . as $e | .[1] == "filename" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | length) < 1 or ($a[$e[0]] | length) > 255 or ($a[$e[0]] | test("[\u0000-\u001f\u007f/]")))) then "name is one name, no slash, 255 characters at most"
        elif any($xp[]; . as $e | .[1] == "path" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | startswith("/") | not) or ($a[$e[0]] | length) > 4096 or ($a[$e[0]] | test("[\u0000-\u001f\u007f]")))) then "to is a whole path, plain text"
        elif ([$xs[] | select(.[1] == "text" or .[1] == "name") | . as $e | select(($a | has($e[0])) and ((($a[$e[0]] | type) != "string") or (($a[$e[0]] | length) > 40) or (($a[$e[0]]) | plain | not)))] | length) > 0 then ([$xs[] | select(.[1] == "text" or .[1] == "name") | .[0]][0]) + " is plain text, 40 characters at most"
        elif any($xs[]; . as $e | .[1] == "coordinate" and (($a[$e[0]] | type) != "number" or $a[$e[0]] < -65535 or $a[$e[0]] > 65535 or $a[$e[0]] != ($a[$e[0]] | floor))) then "coordinates are whole numbers, -65535 to 65535"
        elif any($xs[]; . as $e | .[1] == "scale" and (if ($a[$e[0]] | type) != "string" then true else ($a[$e[0]] | length) > 16 or ($a[$e[0]] | test("^[0-9]+([.][0-9]+)?$") | not) or (($a[$e[0]] | tonumber? // 0) <= 0) end)) then "scale is a positive decimal"
        elif any($xs[]; . as $e | .[1] == "mode" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | test("^[0-9]{2,5}x[0-9]{2,5}(@[0-9]{1,4}([.][0-9]{1,3})?Hz)?$") | not))) then "mode is WIDTHxHEIGHT or WIDTHxHEIGHT@REFRESHHz"
        elif any($xs[]; . as $e | .[1] == "net" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | test("^[A-Za-z0-9.,:/-]{1,80}$") | not))) then "network values are addresses, none or auto"
        elif any($xs[]; . as $e | .[1] == "seconds" and ($a | has($e[0])) and (($a[$e[0]] | type) != "number" or $a[$e[0]] < 0 or $a[$e[0]] > 86400)) then "at is a number of seconds, 0 to 86400"
        elif any($xs[]; . as $e | .[1] == "pixels" and ($a | has($e[0])) and (($a[$e[0]] | type) != "number" or $a[$e[0]] < 0 or $a[$e[0]] > 65535 or $a[$e[0]] != ($a[$e[0]] | floor))) then "x, y, w and h are whole numbers of pixels, 0 to 65535"
        elif any($xs[]; . as $e | .[1] == "port" and (($a[$e[0]] | type) != "string" or ($a[$e[0]] | test("^[A-Za-z0-9_.:-]{1,80}$") | not))) then "other is a connected screen port"
        elif $p == "" then ""
        elif $k == "level" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 0 and .[$p] <= 100 then "" else $p + " is a whole number, 0 to 100" end)
        elif $k == "delta" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= -100 and .[$p] <= 100 then "" else $p + " is a whole number of percentage points, -100 to 100" end)
        elif $k == "bright" then (if ((.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 1 and .[$p] <= 100) or ((.[$p] | type) == "string" and (.[$p] | test("^(up|down|[1-9][0-9]?|100)$"))) then "" else $p + " is up, down or a whole number, 1 to 100" end)
        elif $k == "minutes" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 0 and .[$p] <= 999 then "" else $p + " is a whole number of minutes, 0 to 999" end)
        elif $k == "speed" then (if (.[$p] | type) == "number" and .[$p] >= -1 and .[$p] <= 1 then "" else $p + " is a number, -1 to 1" end)
        elif $k == "delay" then (if (.[$p] | type) == "number" and .[$p] == (.[$p] | floor) and .[$p] >= 100 and .[$p] <= 2000 then "" else $p + " is a whole number, 100 to 2000" end)
        elif $k == "alpha" then (if (.[$p] | type) == "number" and .[$p] >= 0 and .[$p] <= 1 then "" else $p + " is a number, 0 to 1" end)
        elif $k == "path" then (if (.[$p] | type) == "string" and (.[$p] | startswith("/")) and (.[$p] | length) <= 4096 and (.[$p] | test("[\u0000-\u001f\u007f]") | not) then "" else $p + " is a whole path, plain text" end)
        elif (.[$p] | type) != "string" or ((.[$p]) | plain | not) then $p + " is plain text, 256 characters at most"
        elif ($k | contains("|")) and (.[$p] as $x | $k | split("|") | any(. == $x) | not) then $p + " is one of " + ($k | split("|") | join(", "))
        else "" end
        + (if $q != "" and has($q) and ((.[$q] | type) != "string" or (.[$q] | length) > 256) then "; " + $q + " is text, 256 characters at most" else "" end)')
    [ -z "$_bad" ] || { rpc_error "$1" -32602 "$_name: $_bad"; return 0; }
    [ "$sec" != files ] || { provide_files_call "$1" "$_name" "$_args"; return 0; }   # files: the four lines, not the panel's gate; a name whole, never its slug
    # the step's value (a text extra as its slug) and the arguments without the secret: one jq, a line each
    _parts=$(printf '%s' "$_args" | jq -r --arg p "$_tp" --arg x "$_te" --arg q "$_tq" '. as $a
        | (if $p == "" then "" else [$a[$p] | tostring] + [$x | split(" ")[] | select(. != "") | split(":") | [(.[0] | rtrimstr("?")), .[1]] | . as $e | select($a[$e[0]] != null) | $e[0] + "=" + (($a[$e[0]] | tostring) | if $e[1] == "text" or $e[1] == "name" then ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] else . end)] | join(" ") end),
          (if $q == "" then . else del(.[$q]) end | tojson)')
    { IFS= read -r _v; IFS= read -r _plain; } <<EOF
$_parts
EOF
    PANEL_PASS=''; [ -z "$_tq" ] || PANEL_PASS=$(printf '%s' "$_args" | jq -r --arg q "$_tq" '.[$q] // ""')   # a password: a shell variable for the step, never a file, never a line out
    case $_name in
        notes_open) _resolved=$(note_file "$_v") || { provide_refuse "$1" 'select one note by its filename; that name is missing or ambiguous'; return 0; }; _v=${_resolved##*/} ;;
        reminders_done|reminders_snooze|reminders_delete) _resolved=$(rem_find "$_v") || { provide_refuse "$1" 'select one reminder by its UID; that name is missing or ambiguous'; return 0; }; _v=$(printf '%s' "$_resolved" | cut -f2) ;;
        window_focus|window_close) win_label > "$TMP/win.labels"; WIN_LABELS_READ=1   # the windows read once for the call: its check, its name, the step's
            _v=$(win_named "$_v") || { provide_refuse "$1" 'select one open window by its ID; that name is missing or ambiguous'; return 0; } ;;
    esac
    case $_name in notes_open|reminders_done|reminders_snooze|reminders_delete|window_focus|window_close) _plain=$(jq -cn --arg n "$_v" '{name:$n}') ;; esac
    _act=$_ta; _arg=$_v; [ "$_ta" != '=' ] || { _act=$_v; _arg=''; }   # a palette's step is its name alone
    if [ "$_name" = reminders_add ] && ! rem_parse "$_v" >/dev/null 2>&1; then   # no day and time in the words: one question, then the step with the answer in front
        case $(printf '%s' "$_v" | tr 'A-Z' 'a-z') in "remind me to "*) _v=$(printf '%s' "$_v" | cut -c14-) ;; "remind me "*) _v=$(printf '%s' "$_v" | cut -c11-) ;; esac   # the title is what follows
        _when=$(provide_ask "$1" "When" when "5pm, tomorrow 9:00, in 20 min") || { provide_refuse "$1" "not done: no time given"; return 0; }
        _v="$_when $_v"; _arg=$_v
    fi
    PANEL_ROW_MATCHED=''
    case $_th in *f*) ;; *)   # the rows are the allowlist: the ones the host was last sent, else read now
        provide_quick "$sec" "$_name" "$_v" && _quick=1 || _quick=''
        if [ -z "$_quick" ]; then
            [ -s "$TMP/rows.last" ] || provide_rows "$sec" > "$TMP/rows.last"
            cat "$TMP/rows.last" > "$TMP/rows.json"
            if [ "$sec" = theme ]; then   # the wallpaper list's rows are the theme's too
                [ -s "$TMP/wall.last" ] || provide_wall_rows > "$TMP/wall.last"
                cat "$TMP/wall.last" >> "$TMP/rows.json"
            fi
            jq -e -s --arg n "$_name" --argjson a "$_plain" 'any(.[] | ((.rows // [])[] | .tool, (.more // [])[], (.step // empty | . as $s | $s.values[] | . as $v | $s.set | .arguments[$s.key] = $v.sent), .switch.turn_on, .switch.turn_off, .look), .look_back | select(. != null); .name == $n and .arguments == $a)' "$TMP/rows.json" >/dev/null 2>&1 \
                && PANEL_ROW_MATCHED=1
        fi
        [ -n "$_quick$PANEL_ROW_MATCHED" ] || provide_in_use "$sec" "$_name" "${_arg:-$_act}" \
            || { provide_refuse "$1" "${_arg:-$_act} is not in the list now"; return 0; } ;;
    esac
    _g=$(panel_gate "$sec" "$_act" "$_arg") || { PANEL_ROW_MATCHED=''; provide_refuse "$1" "$(printf '%s' "$_g" | scrub_text)"; return 0; }
    PANEL_ROW_MATCHED=''
    # the inverse read once, before the step: the state now is what undo puts back; panel_step takes it as it is
    _undo='null'; PANEL_INV=$(panel_inverse "$sec" "$_act" "$_g"); PANEL_INV_READ=1; _inv=${PANEL_INV%%"$TAB"*}
    if [ -n "$_inv" ] && action_tool "$sec" "$_inv"; then _undo=$(tool_call_json "$_tool" "$_tv") || _undo='null'; fi
    BT_BRIDGE=''
    if [ "$_name" = bt_pair ]; then
        [ -n "$CLIENT_PAIRING" ] || { provide_refuse "$1" "pairing needs a client that supports native pairing questions"; return 0; }
        BT_BRIDGE=$TMP
        rm -f "$TMP/bt.cancel" "$TMP/bt.ask"
        printf '%s\n' "$1" > "$TMP/bt.call-id"
    fi
    export BT_BRIDGE
    rm -f "$TMP/opened" "$TMP/action.effect"
    : > "$TMP/step.mark"   # the settings read again after the step only when it wrote them
    PROVIDE_EFFECT=1; PANEL_JOURNAL=off   # the terminal panel's recent picks and undo journal are its own: a host's step writes neither
    ( set +e; panel_step "$sec" "$_act" "$_g" > "$TMP/call.out" 2>&1; echo $? > "$TMP/call.rc" ) 3>&- 4<&- 5>&- & _w=$!
    if [ -n "$_tok$BT_BRIDGE" ]; then
        _i=0
        while kill -0 "$_w" 2>/dev/null; do
            if [ -f "$TMP/bt.ask" ]; then rpc_send "$(cat "$TMP/bt.ask")"; rm -f "$TMP/bt.ask"; fi
            if [ -n "$_tok" ]; then _i=$((_i + 1)); rpc_note notifications/progress "$(jq -cn --argjson t "$_tok" --argjson p "$_i" --arg s "$sec" '{progressToken: $t, progress: $p, message: ($s + ": working")}')"; fi
            if [ -n "$BT_BRIDGE" ]; then sleep 0.1; else sleep 0.5; fi
        done
    fi
    wait "$_w" 2>/dev/null || :
    PANEL_PASS=''; BT_BRIDGE=''; PANEL_INV=''; PANEL_INV_READ=''; PANEL_JOURNAL=''; WIN_LABELS_READ=''; rm -f "$TMP/bt.call-id" "$TMP/bt.ask"
    _rc=$(cat "$TMP/call.rc" 2>/dev/null || echo 1); _out=$(scrub_text < "$TMP/call.out")
    if [ -n "$(find "$CONFIG" "$THEME_ENV" -newer "$TMP/step.mark" 2>/dev/null)" ]; then   # the step changed the settings: the rows read them anew
        for _k in $THEME_KEYS; do unset "$_k"; done; config_load; theme_load
    fi
    if [ "$_rc" -ne 0 ]; then provide_refuse "$1" "${_out:-$sec: $_title did not work}"; return 0; fi
    case $_name in notes_add|reminders_*|out_level|out_adjust|out_mute|out_unmute|mic_level|mic_adjust|mic_mute|mic_unmute|window_focus|window_close)
        [ -s "$TMP/action.effect" ] || { provide_refuse "$1" 'the action may have happened, but its result could not be read back; check the current state before trying again'; return 0; } ;;
    esac
    _pal='null'; _trn='null'   # a theme step: the palette now, so the dialog repaints itself
    [ "$sec" != theme ] || { _trn=$(dialog_transitions); _trn=$(jq -cn --arg t "$_trn" '$t'); }   # and its animation now, read again by an open dialog: "" plays none
    if [ "$_name" = theme_preview ]; then   # a look: the colors on the screen, no animation changed, nothing to undo
        _trn=null; _undo=null; _pal=$(cat "$TMP/preview.palette" 2>/dev/null || :); [ -n "$_pal" ] || _pal=null; rm -f "$TMP/preview.palette"
    fi
    [ "$sec" != theme ] || [ "$_name" = theme_preview ] || { panel_load; _pal=$(jq -cn --arg f "$HEX_FG" --arg a "$HEX_ACCENT" --arg m "$PANEL_MUTED" --arg b "$PANEL_BG" --arg h "$PANEL_HI" --arg r "${HEX_ANSI_1:-}" --arg g "${HEX_ANSI_2:-}" --arg y "$(bar_style GLYPH_FAMILY stone)" '{HEX_FG: $f, HEX_ACCENT: $a, PANEL_MUTED: $m, PANEL_BG: $b, PANEL_HI: $h, HEX_ANSI_1: $r, HEX_ANSI_2: $g, GLYPH_FAMILY: $y}
        + ($ENV | with_entries(select(.key | test("^HEX_ANSI_([0-9]|1[0-5])$"))))'); }   # and the glyph family and the 16 colors, for a piece the dialog draws
    if [ -s "$TMP/network.undo" ]; then _undo=$(tool_call_json "${sec}_restore" "$(cat "$TMP/network.undo")"); fi
    if [ -s "$TMP/sound.undo" ]; then _undo=$(tool_call_json "${sec}_level" "$(cat "$TMP/sound.undo")"); fi
    # the rows as the step left them go with the answer: the host reads nothing again, the gate and the watcher take them as seen
    [ -s "$TMP/action.effect" ] || printf 'null' > "$TMP/action.effect"
    if [ -f "$TMP/opened" ] || [ "$sec" = tools ]; then printf 'null' > "$TMP/rows.last.new"   # tools: the page on screen changed, not the six; with no rows the host reads both again
    else provide_rows "$sec" > "$TMP/rows.last.new" && cp "$TMP/rows.last.new" "$TMP/rows.last" && provide_seen; fi
    rpc_result "$1" "$(jq -cn --arg r "$_out" --argjson u "$_undo" --argjson p "$_pal" --argjson t "$_trn" --argjson o "$([ -f "$TMP/opened" ] && echo true || echo false)" \
        --slurpfile e "$TMP/action.effect" --slurpfile rows "$TMP/rows.last.new" '
        (if $o then {opened: true}
         else {receipt: $r} + (if $u == null then {} else {undo: $u} end) + (if $p == null then {} else {palette: $p} end)
            + (if $t == null then {} else {transitions: $t} end) + (if $rows[0] == null then {} else {rows: $rows[0]} end) end)
        + (if $e[0] == null then {} else {effect: $e[0]} end)
        | {content: [{type: "text", text: (del(.rows) | tojson)}], structuredContent: ., isError: false}')"
    rm -f "$TMP/action.effect" "$TMP/rows.last.new"
}
provide_quick() {   # provide_quick SECTION TOOL VALUE -> 0 for a pick the theme's rows always list, without drawing them
    [ "$1" = theme ] || return 1
    case $2 in
        theme_palette) case $(theme_kind "$3") in shipped|yours|saved|none) return 0 ;; look) [ "$3" = "${THEME:-}" ] ;; *) return 1 ;; esac ;;
        theme_wallpaper) [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && { wall_shipped "$3" || [ "$3" = default ]; } ;;
        theme_text) case $3 in bigger|smaller|[6-9]|[1-3][0-9]|40) [ -n "$(look_font_size)" ] ;; *) return 1 ;; esac ;;   # a size as it is, the dialog's step
        theme_transparency) case ${3%\%} in more|less|[0-9]|[1-4][0-9]|50) return 0 ;; *) return 1 ;; esac ;;
        theme_preview) [ "$3" = off ] || case $(theme_kind "$3") in shipped|yours) return 0 ;; *) return 1 ;; esac ;;   # a palette's look, or the look in use again
        theme_animation) case " next back none $ANIMATION_NAMES " in *" $3 "*) return 0 ;; *) return 1 ;; esac ;;
        theme_glyphs) case $3 in signs|words) return 0 ;; *) return 1 ;; esac ;;
        theme_icons) case $3 in on|off) return 0 ;; *) return 1 ;; esac ;;
        theme_spacing) case $3 in none|groups|rows) return 0 ;; *) return 1 ;; esac ;;
        theme_family) case " $GLYPH_FAMILIES " in *" ${3:-none} "*) return 0 ;; *) return 1 ;; esac ;;
        theme_face) case " $FONT_FACES " in *" ${3:-none} "*) return 0 ;; *) return 1 ;; esac ;;
        theme_motion) case $3 in on|off) return 0 ;; *) return 1 ;; esac ;;
        *) return 1 ;;
    esac
}
provide_refuse() { rpc_result "$1" "$(jq -cn --arg t "$2" '{content: [{type: "text", text: $t}], isError: true}')"; }   # provide_refuse ID SENTENCE -- a tool's refusal, in the result
cmd_provide() {   # cmd_provide SECTION -- the verb
    [ $# -eq 1 ] || refuse_in provide "one section: $(printf '%s' "$PROVIDE_SECTIONS" | sed 's/ /, /g')" >&2
    provide_main "$1"
}

