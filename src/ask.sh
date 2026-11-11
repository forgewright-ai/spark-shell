# shellcheck extended-analysis=false
# --- ask: the words to the model and the steps it plans
# sets: LOCAL_RISK US WANT_ATTACH_MAX
# reads: APPS LAYOUTS_DIR LAYOUT_NOT_APPS OS PANEL_CROSS PANEL_GO PANEL_TICK PROVIDE_TOOLS TAB TMP
panel_brief_sections() {   # -> the sections the want path offers here, in the brief's order
    for p in layout apps printers window bar notes reminders display keyboard notifications storage power $(panel_blocks_here); do
        case $p in lan|bat|clock) continue ;; window|bar|display|keyboard|notifications|storage|power) [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] || continue ;; printers) command -v lpstat >/dev/null 2>&1 || continue ;; apps) [ "$OS" != Darwin ] || continue ;; esac
        printf '%s\n' "$p"
    done
}
panel_brief() {   # -> "section: action ARG,...; section:..." -- what spark may pick from
    for p in $(panel_brief_sections); do
        if [ "$p" = layout ]; then
            _saved=$(ls -A "$LAYOUTS_DIR" 2>/dev/null | sed 's/^/open /' | paste -sd, - | sed 's/,/, /g')
            _acts="${_saved:+$_saved, }new TASK"
        elif [ "$p" = apps ]; then
            [ "$OS" != Darwin ] || continue
            _acts=$(panel_apps_known | sed 's/^/open /' | paste -sd, - | sed 's/,/, /g')
        else
            _acts=$(panel_rows "$p" full | cut -f3 | grep -vx show | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')
            case $p in out|mic) _acts="${_acts:+$_acts, }level N, adjust DELTA" ;; theme) _acts="${_acts:+$_acts, }text bigger, text smaller, transparency more, transparency less" ;; esac
        fi
        [ -z "$_acts" ] || printf '%s: %s; ' "$p" "$_acts"
    done | sed 's/; $//'
}
want_names_app() {   # want_names_app WORDS -> the first word that names an app here (a desktop entry, or one allowed), or nothing
    sbom_entries >/dev/null 2>&1 || :   # $TMP/entries
    for w in $1; do
        w=$(printf '%s' "$w" | tr -cd 'A-Za-z0-9_.-' | tr 'A-Z' 'a-z'); [ -n "$w" ] || continue
        case " sway swaybg swaymsg foot footclient xdg-open $LAYOUT_NOT_APPS " in *" $w "*) continue ;; esac
        if [ -s "$TMP/entries" ] && awk -F '\t' -v w="$w" 'tolower($1) == w { f = 1 } { split($6, a, " "); b = a[1]; sub(/.*\//, "", b); if (tolower(b) == w) f = 1 } END { exit !f }' "$TMP/entries"; then echo "$w"; return 0; fi
        if apps_marked && grep -iq "^$w\([: ]\|$\)" "$APPS"; then echo "$w"; return 0; fi
    done
    return 1
}
want_says_close() { printf '%s\n' "$1" | grep -qiwE 'close|quit|kill|exit|stop|hide|minimi[sz]e'; }   # want_says_close WORDS -> 0 when the words end something
want_is_question() {   # want_is_question WORDS -> 0 when the words ask something (a question mark, or a question's first word)
    case $1 in *'?') return 0 ;; esac
    case " $(printf '%s' "$1" | tr 'A-Z' 'a-z' | cut -d' ' -f1) " in ' what '|' how '|' why '|' when '|' where '|' who '|' which '|' is '|' are '|' can '|' could '|' do '|' does '|' did '|' will '|' should '|' was '|' were ') return 0 ;; *) return 1 ;; esac
}
want_layout() { ( [ "$OS" = Darwin ] || pm_detect; REFUSE_AS=layout; layout_need "$1" ) || :; }   # want_layout WORDS -- a layout for the task
# the plan, $TMP/plan: a line each, its fields parted by US:
# "step SECTION ACTION ARG GATED", "say LINE" (an answer) or "no LINE"
# (a refusal); a step is in it only once panel_gate took it
US=$(printf '\037')
want_put() { _wp=''; for _f in "$@"; do _wp="$_wp${_wp:+$US}$(printf '%s' "$_f" | scrub_text)"; done; printf '%s\n' "$_wp" >> "$TMP/plan"; }   # want_put FIELD... -- one plan line, every field scrubbed
want_plan() {   # want_plan WORDS -> $TMP/plan; exit 1 when the words could not be read; WANT_Q set for a question
    : > "$TMP/plan"
    WANT_Q=''; ! want_is_question "$1" || WANT_Q=1   # a question's steps are proposals
    command -v jq >/dev/null 2>&1 || { want_put no "jq is not installed (spark-shell on)"; return 1; }
    spark=$(spark_bin); [ -n "$spark" ] || { want_put no "spark is not installed -- spark reads what you want (github.com/forgewright-ai/spark)"; return 1; }
    SND=${SND:-$(snd_tool)}
    if [ -z "$WANT_Q" ] && ! want_says_close "$1" && _app=$(want_names_app "$1"); then   # an app named opens, or is a layout for the task
        if [ "$(printf '%s\n' "$1" | wc -w | tr -d ' ')" -le 2 ] && [ "$(layout_words_full "$1")" = false ] && [ -z "$(layout_words_ws "$1")" ]; then   # a word or two and no layout word: the app itself, at once
            want_step apps open "$(panel_apps_known | awk -v w="$_app" 'tolower($0) == w && !d {print; d = 1}')"
        else want_put step layout new "$1" "$1"; fi   # the layout's model reads the whole sentence
        return 0
    fi
    if "$spark" help </dev/null 2>/dev/null | grep -q '^ *spark steps '; then want_steps "$1"; return; fi   # a spark with steps plans with the tools themselves; an older spark, the brief below
    _brief=$(panel_brief)
    [ -n "$_brief" ] || { want_put no "nothing on the panel takes an action on this machine"; return 1; }
    about="The panel of a desktop. What the bar shows now: $(panel_facts). What this machine can do now, by section -- $_brief. Rules: only steps from that list; N is a number (0 to 100 for level, 0 to 1 for alpha), NAME a name as listed, TASK the want in the user's own words, as {\"page\": \"layout\", \"action\": \"new\", \"arg\": \"write notes\"}, which opens the apps for that task, any program by name included; a layout step for a want that names a program or a task to do, never for a setting alone; as few steps as the want takes; no step when nothing on the list does it; when the words ask something rather than ask for a change, put the answer in \"answer\", one or two sentences, and give no steps. Answer with one JSON object and nothing else: {\"why\": \"one sentence\", \"answer\": \"\", \"steps\": [{\"page\": \"bt\", \"action\": \"connect\", \"arg\": \"NAME\"}]}"
    st=0; "$spark" edit --type json --name panel.json --about "$about" -- "do this on the desktop: $1" </dev/null > "$TMP/want.json" 2>"$TMP/want.err" || st=$?
    [ "$st" -eq 0 ] || { want_put no "$PANEL_CROSS spark did not answer: $(head -1 "$TMP/want.err")"; return 1; }
    jq -e '.steps | arrays' "$TMP/want.json" >/dev/null 2>&1 || { want_put no "$PANEL_CROSS the answer was not steps for the panel"; return 1; }
    if [ "$(jq -r '.steps | length' "$TMP/want.json")" -eq 0 ]; then want_nostep "$1"; return 0; fi
    jq -r '.steps[] | [(.page // "" | tostring), (.action // "" | tostring), (.arg // "" | tostring)] | @tsv' "$TMP/want.json" > "$TMP/want.steps"
    while IFS="$TAB" read -r pg ac ar; do want_step "$pg" "$ac" "$ar"; done < "$TMP/want.steps"
}
want_nostep() {   # want_nostep WORDS -- no step came back: the answer to a question, a refusal, or a layout for a task
    _ans=$(jq -r '.answer // "" | gsub("[\\n\\r]+"; " ")' "$TMP/want.json")
    if want_is_question "$1"; then if [ -n "$_ans" ]; then want_put say "$_ans"; else want_put say "nothing here answers that"; fi
    elif want_says_close "$1"; then want_put no "$PANEL_CROSS no step on the panel does that"
    elif [ "$(printf '%s\n' "$1" | wc -w | tr -d ' ')" -le 2 ]; then want_put no "$PANEL_CROSS no step on the panel does that"   # a word or two is no task
    else want_put step layout new "$1" "$1"; fi   # a task: the layout's model reads it
}
want_tools() {   # -> the desktop's tools as one tools/list result: the sections offered here, about and undo; never files
    _here=" $(panel_brief_sections | tr '\n' ' ')"
    for t in $PROVIDE_TOOLS; do
        [ -z "${WANT_ONLY:-}" ] || [ "$t" = "$WANT_ONLY" ] || continue   # WANT_ONLY: the one tool the words are for
        tool_spec "$t" || continue
        case $_th in *p*) continue ;; esac   # a person's step: never from a plan
        case $_ts in files) continue ;; about|undo) ;; *) case $_here in *" $_ts "*) ;; *) continue ;; esac ;; esac
        tool_json "$t"   # no enum of the names: a grammar held to them picks a wrong one for a name not listed; the gate refuses it instead
    done | jq -cs '{tools: .}'
}
want_name_rows() {   # -> TOOL<tab>NAME per name a tool takes now, as the rows write it; never the theme's words (listing them misleads the model)
    for p in $(panel_brief_sections); do
        case $p in
            theme) ;;
            layout) { ls -A "$LAYOUTS_DIR" 2>/dev/null; kept_names layout; } | awk '!s[$0]++' | sed 's/^/layout_open	/' ;;
            apps) panel_apps_known | sed 's/^/apps_open	/' ;;
            *) panel_rows "$p" full | cut -f3 | grep -vx show | while IFS= read -r a; do if action_tool "$p" "$a" && [ "$_tp" = name ] && [ -n "$_tv" ]; then printf '%s\t%s\n' "$_tool" "$_tv"; fi; done ;;   # an if: a row that takes no name is no failure under set -e
        esac
    done | awk '!seen[$0]++'
}
want_names() { awk -F '\t' '{ if (!($1 in l)) { o[++n] = $1; l[$1] = $2 } else l[$1] = l[$1] ", " $2 } END { for (i = 1; i <= n; i++) printf "%s%s: %s", (i > 1 ? "; " : ""), o[i], l[o[i]] }' "$TMP/want.names"; }   # -> "TOOL: NAME, NAME; ..." for the about
want_steps() {   # want_steps WORDS -> $TMP/plan from spark steps; exit 1 when spark did not answer
    want_name_rows > "$TMP/want.names"
    _about=$(printf 'A desktop. What the bar shows now: %s. The names each tool takes now -- %s. A name in a step is one of these, whole and exactly as written here.' "$(panel_facts)" "$(want_names)" | cut -c1-1800)
    st=0; want_tools | "$spark" steps --about "$_about" -- "$1" > "$TMP/want.json" 2>"$TMP/want.err" || st=$?
    [ "$st" -eq 0 ] || { want_put no "$PANEL_CROSS spark did not answer: $(head -1 "$TMP/want.err")"; return 1; }
    jq -e '.steps | arrays' "$TMP/want.json" >/dev/null 2>&1 || { want_put no "$PANEL_CROSS the answer was not steps for the panel"; return 1; }
    jq -r '.refused[]? | strings' "$TMP/want.json" > "$TMP/want.refused"
    while IFS= read -r l; do want_put no "$PANEL_CROSS $l"; done < "$TMP/want.refused"
    _n=$(jq -r '.steps | length' "$TMP/want.json")
    if [ "$_n" -eq 0 ]; then   # no step: the answer, else one line; never a layout of our own (layout_new is a tool spark picks itself)
        [ ! -s "$TMP/want.refused" ] || return 0
        _ans=$(jq -r '.answer // "" | gsub("[\\n\\r]+"; " ")' "$TMP/want.json")
        if [ -n "$_ans" ]; then want_put say "$_ans"
        elif want_is_question "$1"; then want_put say "nothing here answers that"
        else want_put no "$PANEL_CROSS no step on the panel does that"; fi
        return 0
    fi
    _i=0
    while [ "$_i" -lt "$_n" ]; do
        _sn=$(jq -r --argjson i "$_i" '.steps[$i].name // "" | tostring' "$TMP/want.json"); _i=$((_i + 1))
        if ! tool_spec "$_sn"; then want_put no "$PANEL_CROSS spark planned a step this desktop does not have"; continue; fi   # never the name it made up
        _sv=''; [ -z "$_tp" ] || _sv=$(jq -r --argjson i "$((_i - 1))" --arg p "$_tp" '.steps[$i].arguments[$p] // "" | tostring' "$TMP/want.json")
        [ -z "$_te" ] || _sv="$_sv $(jq -r --argjson i "$((_i - 1))" --arg x "$_te" '.steps[$i].arguments as $a | [$x | split(" ")[] | select(. != "") | split(":") | [(.[0] | rtrimstr("?")), .[1], (.[0] | endswith("?"))] | . as $e | select(($a[$e[0]] // "") != "" or ($e[1] != "text" and ($e[2] | not))) | $e[0] + "=" + (($a[$e[0]] // "" | tostring) | if $e[1] == "text" then ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] else . end)] | join(" ")' "$TMP/want.json")"
        printf '%s\n' "$_sn$US$_sv"
    done > "$TMP/steps.raw"
    # one look a request: a second theme_words step is refused, a theme_save before the words step moves after it,
    # and a palette step naming the theme the plan saves is dropped
    awk -F "$US" -v us="$US" '{ n[NR] = $1; v[NR] = $2; if ($1 == "theme_words") { w++; if (w == 1) last = NR } if ($1 == "theme_save") sv[$2] = 1 }
        END { for (i = 1; i <= NR; i++) if (!(n[i] == "theme_save" && last && i < last) && !(n[i] == "theme_palette" && (v[i] in sv))) print n[i] us v[i] us (n[i] == "theme_words" && i != last ? "again" : "");
              for (i = 1; i < last; i++) if (n[i] == "theme_save") print n[i] us v[i] us "" }' "$TMP/steps.raw" > "$TMP/steps.ordered"
    while IFS="$US" read -r _sn _sv _again; do
        tool_spec "$_sn" || continue
        [ "$_again" != again ] || { want_put no "$PANEL_CROSS one look a request: the first words step made it, $_sv was not"; continue; }
        case $_sn in theme_palette) want_step theme "$_sv" '' ;; *) want_step "$_ts" "$_ta" "$_sv" ;; esac   # a palette's step is its name alone
    done < "$TMP/steps.ordered"
}
want_step() {   # want_step SECTION ACTION ARG -- into the plan when panel_gate takes it, else its refusal
    if _g=$(panel_gate "$1" "$2" "$3"); then want_put step "$1" "$2" "$3" "$_g"; else want_put no "$PANEL_CROSS $_g"; fi
}
# the steps that wait for a typed yes whatever a tool's hint says;
# the dialog keeps the same list
LOCAL_RISK="wifi_forget window_close bt_pair"
step_risky() {   # step_risky SECTION ACTION [ARG] -> 0 when the step waits for a typed yes: its tool's destructive hint, or LOCAL_RISK
    action_tool "$1" "$2${3:+ $3}" || return 1
    case " $LOCAL_RISK " in *" $_tool "*) return 0 ;; esac
    tool_spec "$_tool" || return 1
    case $_th in *d*) return 0 ;; esac
    return 1
}
step_yes() {   # step_yes LINE -> 0 when yes was typed for this step at a terminal; with no terminal, never
    if [ -n "${SPARK_SHELL_TEST_TTY:-}" ]; then printf 'type yes to %s: ' "$1"; IFS= read -r _y || _y=''
    elif [ -t 0 ] && { : < /dev/tty; } 2>/dev/null; then printf 'type yes to %s: ' "$1" > /dev/tty; IFS= read -r _y < /dev/tty || _y=''
    else return 1; fi
    [ "$_y" = yes ]
}
want_run() {   # plays $TMP/plan: a question's steps are proposed, a risky step asks for yes, a step not done stops the rest
    _wf=''
    while IFS="$US" read -r k pg ac ar ga <&3; do
        case $k in
            say|no) printf '%s\n' "$pg" ;;
            step) _wl="$pg $ac${ar:+ $ar}"
                  if [ -n "${WANT_Q:-}" ]; then printf '%s proposed, not run: %s\n' "$PANEL_GO" "$_wl"; continue; fi
                  if [ -n "$_wf" ]; then printf '%s not run, for the step before was not done: %s\n' "$PANEL_CROSS" "$_wl"; continue; fi
                  if step_risky "$pg" "$ac" "$ga" && ! step_yes "$_wl"; then printf '%s %s: kept, not done (it takes a typed yes)\n' "$PANEL_CROSS" "$_wl"; _wf=1; continue; fi
                  if [ "$pg:$ac" = layout:new ]; then want_layout "$ar"
                  elif _l=$(panel_step "$pg" "$ac" "$ga" 2>&1); then printf '%s %s\n' "$PANEL_TICK" "$_l"; else printf '%s %s\n' "$PANEL_CROSS" "$_l"; _wf=1; fi ;;
        esac
    done 3< "$TMP/plan"
}
want_play() {   # want_play WORDS -> one line per step with its sign, or the answer to a question
    _st=0; want_plan "$1" || _st=$?
    want_run
    return "$_st"
}
want_json() {   # -> the plan as one JSON object for the dialog: {"answer", "question", "steps": [{"name", "arguments", "line"}], "refused": [LINE]}; a question's steps are the dialog's proposals
    while IFS="$US" read -r k pg ac ar ga; do
        case $k in
            say) jq -cn --arg t "$pg" '{answer: $t}' ;;
            no) jq -cn --arg t "$pg" '{refused: $t}' ;;
            step) if action_tool "$pg" "$ac${ar:+ $ar}"; then tool_call_json "$_tool" "$_tv" "$pg $ac${ar:+ $ar}"
                  else jq -cn --arg t "$PANEL_CROSS $pg: $ac is not a step the dialog takes" '{refused: $t}'; fi ;;
        esac
    done < "$TMP/plan" | jq -cs --arg q "${WANT_Q:-}" '{answer: ([.[] | .answer // empty] | join(" ")), question: ($q == "1"), steps: [.[] | select(.name)], refused: [.[] | .refused // empty]}'
}
want_attach() {   # want_attach FILE WORDS -> spark's answer about the file; exit 1 with one line when the file is refused
    [ "$DIALOG_ATTACH" = yes ] || { echo "attaching is off (DIALOG_ATTACH=no)"; return 1; }
    [ -f "$1" ] && [ -r "$1" ] || { echo "$1 is not a file that can be read"; return 1; }
    _ext=$(printf '%s' "${1##*/}" | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | tr 'A-Z' 'a-z')
    case " $DIALOG_ATTACH_TYPES " in *" ${_ext:-.} "*) ;; *) echo "${1##*/} is not a type plus attaches ($DIALOG_ATTACH_TYPES)"; return 1 ;; esac
    _n=$(wc -c < "$1" | tr -d ' ')
    [ "$_n" -gt 0 ] || { echo "${1##*/} is empty"; return 1; }
    [ "$(LC_ALL=C tr -d '\000' < "$1" | wc -c | tr -d ' ')" = "$_n" ] || { echo "${1##*/} is not text: spark reads text"; return 1; }
    ! command -v iconv >/dev/null 2>&1 || iconv -f UTF-8 -t UTF-8 < "$1" > /dev/null 2>&1 || { echo "${1##*/} is not UTF-8 text"; return 1; }
    spark=$(spark_bin); [ -n "$spark" ] || { echo "spark is not installed -- spark reads what you want (github.com/forgewright-ai/spark)"; return 1; }
    st=0
    if [ "$_n" -le "$WANT_ATTACH_MAX" ]; then "$spark" edit --source --name "${1##*/}" -- '?' "$2" < "$1" > "$TMP/attach.out" 2>"$TMP/attach.err" || st=$?
    else "$spark" read --name "${1##*/}" "$2" < "$1" > "$TMP/attach.out" 2>"$TMP/attach.err" || st=$?; fi   # a longer text: spark read takes it by parts
    [ "$st" -eq 0 ] || { echo "$PANEL_CROSS spark did not answer: $(head -1 "$TMP/attach.err" | scrub_text)"; return 1; }
    scrub_text < "$TMP/attach.out"
}
WANT_ATTACH_MAX=16000   # what spark edit reads whole (forge.FILE_MAX characters); a longer file goes to spark read
cmd_want() {   # cmd_want [--attach FILE] [--json] WORDS -- the one entry to the want path
    _file=''; _json=''
    while [ $# -gt 0 ]; do
        case $1 in
            --attach) [ $# -ge 2 ] || refuse_in want "--attach takes a file"; _file=$2; shift 2 ;;
            --json) _json=1; shift ;;
            --) shift; break ;;
            -*) refuse_in want "$1 is not an option here: --attach FILE, --json, then the words" ;;
            *) break ;;
        esac
    done
    [ $# -gt 0 ] && [ -n "$*" ] || refuse_in want "say what you would like, as spark-shell want \"mute everything\""
    config_load; [ "$OS" = Darwin ] || pm_detect; theme_load
    if [ -n "$_file" ]; then
        st=0; _a=$(want_attach "$_file" "$*") || st=$?
        if [ -n "$_json" ]; then if [ "$st" -eq 0 ]; then jq -cn --arg a "$_a" '{answer: $a, steps: [], refused: []}'; else jq -cn --arg r "$_a" '{answer: "", steps: [], refused: [$r]}'; fi
        else printf '%s\n' "$_a"; fi
        return "$st"
    fi
    SND=''; [ "$OS" = Darwin ] || SND=$(snd_tool)
    st=0; want_plan "$*" || st=$?
    if [ -n "$_json" ]; then want_json; return "$st"; fi
    panel_group_begin; want_run; panel_group_end
    return "$st"
}
bar_want() {   # bar_want WORDS -- from the shell: spark-shell panel "mute everything"
    [ -n "$(spark_bin)" ] || refuse_in panel "spark is not installed -- spark reads what you want (github.com/forgewright-ai/spark)"
    printf 'panel> %s\n' "$1"
    panel_group_begin
    st=0; want_play "$1" > "$TMP/want.out" 2>&1 || st=$?
    panel_group_end
    sed 's/^/  /' "$TMP/want.out"
    return "$st"
}

