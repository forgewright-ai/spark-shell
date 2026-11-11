# shellcheck extended-analysis=false
# --- the layouts
# sets: LAYOUTS_DIR LAYOUT_LAST LAYOUT_NOT_APPS LAYOUT_PENDING LAYOUT_SMALL_WORDS LAYOUT_VERBS LAYOUT_WAIT REFUSE_AS
# reads: APPS CONFIG_DIR DIALOG_BIN KEPT_LAYOUTS LAYOUT_ON NOTES_DIR OS PANEL_APP REPO TAB TMP VERBOSE
# a layout (a desk, in the code);
# every rendered line passes the gate before sway sees it
LAYOUTS_DIR=$CONFIG_DIR/layouts
LAYOUT_LAST=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/desk.last
LAYOUT_PENDING=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/desk.pending
LAYOUT_VERBS="workspace rename splith splitv layout resize focus move floating fullscreen exec session window window-rule"   # session and window: the tmux lines
LAYOUT_NOT_APPS="sh bash zsh dash fish ksh sudo doas su pkexec"   # a shell or a way to root
LAYOUT_WAIT=30                                                    # seconds for a window to map


apps_marked() { [ -f "$APPS" ] && grep -q '^[A-Za-z0-9]' "$APPS"; }
layout_apps() {   # layout_apps NEED -> the lines
    sbom_entries
    awk -F'\t' '{print $1 "\t" $6}' "$TMP/entries" > "$TMP/exec"
    {
        if apps_marked; then
            [ -s "$TMP/sbom" ] || sbom_collect
            grep '^[A-Za-z0-9]' "$APPS" | while IFS= read -r m; do
                n=${m%%:*}; n=$(printf '%s' "$n" | tr -d ' '); note=''; case $m in *:*) note=$(printf '%s' "${m#*:}" | sed 's/^ *//') ;; esac
                e=$(awk -F'\t' -v n="$n" '$1 == n {print $3 "\t" $4}' "$TMP/entries" | head -1)
                if [ -n "$e" ]; then what=${e%	*}; term=${e#*	}
                else
                    what=$(awk -F'\t' -v n="$n" '$2 == n || (" " $7 " ") ~ (" " n " ") {print $6; exit}' "$TMP/sbom"); term=yes
                    if ! layout_on_path "$n"; then   # a package name: its first command here
                        for cmd in $(awk -F'\t' -v n="$n" '$2 == n {print $7; exit}' "$TMP/sbom"); do
                            layout_on_path "$cmd" && { n=$cmd; break; }
                        done
                    fi
                fi
                layout_on_path "$n" || [ -n "$e" ] || continue
                [ -z "$note" ] || what=$note
                [ "$term" = yes ] && printf '%s: %s, terminal\n' "$n" "${what:-$n}" || printf '%s: %s\n' "$n" "${what:-$n}"
            done
        else
            awk -F'\t' '{printf "%s: %s%s\n", $1, $3, ($4 == "yes" ? ", terminal" : "")}' "$TMP/entries"
        fi
        for w in $1; do
            w=$(printf '%s' "$w" | tr -cd 'A-Za-z0-9_.-' | tr 'A-Z' 'a-z')
            [ -z "$w" ] || ! layout_on_path "$w" || printf '%s: named in the need, terminal\n' "$w"
        done
        echo "shell: a terminal with a prompt, terminal"   # a desk word, not an app
    } | grep -v "^\\($(printf '%s' "sway swaybg swaymsg foot footclient xdg-open $LAYOUT_NOT_APPS" | sed 's/ /\\|/g')\\):" \
      | sort -t: -s -u -k1,1   # the desktop itself: not apps
}
REFUSE_AS=desktop   # the verb a refusal names
refuse() { echo "spark-shell $REFUSE_AS: $1"; exit 1; }
cmd_apps() {   # the picker: fzf over the apps and tools
    command -v fzf >/dev/null 2>&1 || refuse "fzf is not installed (spark-shell on)"
    [ -t 0 ] || refuse "the picker needs a terminal -- the file is $APPS (name[: your words], one per line)"
    sbom_collect
    # apps, chosen tools, dependency tools; an allowed row wears a *
    marks=$(apps_marked && grep '^[A-Za-z0-9]' "$APPS" | sed 's/[: ].*//' | paste -sd' ' - || true)
    picked=$(awk -F'\t' -v marks=" $marks " '
        FILENAME == ARGV[1] { ent[$1] = $3; next }
        function star(n) { return (index(marks, " " n " ") > 0) ? "* " : "  " }
        $1 == "app" {   # its entries are the apps; its other commands are part of them
            m = split($8, es, " ")
            for (j = 1; j <= m; j++) { split(es[j], kv, "="); if (kv[1] != "") printf "0\t%s\t%s%s: %s  [app]\n", kv[1], star(kv[1]), kv[1], ent[kv[1]] } }
        $1 == "tool" {
            n = split($7, c, " "); first = ""
            for (i = 1; i <= n; i++) if (c[i] ~ /^[A-Za-z]/) { first = c[i]; break }
            if (first == "") next
            name = ($2 ~ /^[A-Za-z]/) ? $2 : first
            shown = (index(" " $7 " ", " " name " ") > 0) ? name : name " (" first ")"
            printf "%d\t%s\t%s%s: %s  [tool]\n", ($5 == "chosen" ? 1 : 2), name, star(name), shown, $6 }' "$TMP/entries" "$TMP/sbom" \
             | sort -t'	' -k1,1n -k2,2f -u | cut -f3 \
             | grep -v "^..\\($(printf '%s' "sway swaybg swaymsg foot footclient xdg-open $LAYOUT_NOT_APPS" | sed 's/ /\\|/g')\\)[ :(]" \
             | fzf --multi --prompt "apps> " --layout=reverse --no-info --color=16 --no-unicode \
                   --header "The allowed apps: what a layout may open. A tool opens in a terminal window.
Tab flips a row, Enter saves, Esc leaves the list as it was. A * row is allowed.
Allowed now: ${marks:-no list, so every app with a desktop entry}") || { echo "nothing changed"; return 0; }
    [ -n "$picked" ] || { echo "nothing changed"; return 0; }
    flipped=$(printf '%s\n' "$picked" | sed 's/^..//; s/[:(].*//; s/ *$//')
    mkdir -p "$CONFIG_DIR"
    {
        printf '# the allowed apps, what a layout may open, one per line: name[: your words] -- yours to edit\n'
        for n in $marks; do   # the allowed minus the flipped
            printf '%s\n' "$flipped" | grep -qx "$n" && continue
            grep "^$n *\(:.*\)\{0,1\}$" "$APPS" 2>/dev/null | head -1 || printf '%s\n' "$n"
        done
        printf '%s\n' "$flipped" | while IFS= read -r n; do
            if [ -n "$n" ] && ! printf ' %s ' "$marks" | grep -q " $n "; then printf '%s\n' "$n"; fi
        done
        :
    } > "$TMP/apps.new"
    cp "$TMP/apps.new" "$APPS"
    if apps_marked; then echo "allowed apps: $(grep '^[A-Za-z0-9]' "$APPS" | sed 's/[: ].*//' | paste -sd' ' -) ($APPS)"
    else echo "allowed apps: no list, so every app with a desktop entry ($APPS)"; fi
}
cmd_notes() {   # spark-shell notes [new | NAME | open NAME | add WORDS | find WORDS]
    config_load
    case ${1:-} in
        '') notes_list > "$TMP/notes.l"
            [ -s "$TMP/notes.l" ] || { echo "no notes yet in ~/notes (spark-shell notes new writes one)"; return 0; }
            while IFS="$TAB" read -r _e _nm _f; do printf '  %-14s %s\n' "$(note_when "$_e")" "$_nm"; done < "$TMP/notes.l" ;;
        new) [ $# -eq 1 ] || refuse_in notes "new takes no words (spark-shell notes add WORDS writes them)"
            mkdir_private "$NOTES_DIR"; _f=$NOTES_DIR/$(date +%Y-%m-%d-%H%M%S).md; [ -e "$_f" ] || (umask 077 && printf '# \n' > "$_f")
            note_here "$_f" "a new note" ;;
        add|find) _a=$1; shift; [ $# -gt 0 ] || refuse_in notes "$_a takes the words"
            _l=$(notes_act "$_a" "$*") || refuse_in notes "$_l"; echo "$_l" ;;
        -*) refuse_in notes "$1 is not an option here: new, a note's name, add WORDS or find WORDS" ;;
        *) [ "$1" != open ] || shift; [ $# -gt 0 ] || refuse_in notes "open takes a note's name"
            _f=$(note_file "$*") || refuse_in notes "no unique note named $*; use its filename (spark-shell notes lists them)"
            note_here "$_f" "$*" ;;
    esac
}
note_here() {   # note_here FILE NAME
    if [ -t 0 ] && [ -t 1 ]; then
        _ed=$(editor_pick) || refuse_in notes "no editor here: set EDITOR in ~/.config/spark-shell/rc"
        # shellcheck disable=SC2086   # EDITOR may carry its flags
        $_ed "$1"
        [ "$2" != "a new note" ] || [ "$(cat "$1" 2>/dev/null)" != '# ' ] || { rm -f "$1"; echo "nothing written, so no new note"; }
    else _l=$(note_open_file "$1" "$2") || refuse_in notes "$_l"; echo "$_l"; fi
}
cmd_reminders() {   # spark-shell reminders [add DAY TIME WORDS | done NAME | snooze NAME | delete NAME|UID | restore NAME]
    config_load
    case ${1:-} in
        '') _now=$(date +%Y%m%d%H%M); rem_list > "$TMP/rem.l"
            [ -s "$TMP/rem.l" ] || { echo "no reminders ahead (spark-shell reminders add tomorrow 9:00 call the dentist sets one)"; return 0; }
            _gp=''
            while IFS="$TAB" read -r _s _u _t _f; do   # a shared name carries its UID
                _g=$(rem_group "$_s" "$_now")
                [ "$_g" = "$_gp" ] || { [ -z "$_gp" ] || echo; if [ "$_g" = due ]; then echo 'due now'; else echo "$_g"; fi; _gp=$_g; }
                _tw=''; [ "$(awk -F '\t' -v t="$(panel_lower "$_t")" 'tolower($3) == t' "$TMP/rem.l" | grep -c .)" -le 1 ] || _tw="  $_u"
                printf '  %-16s %s%s\n' "$(rem_column "$_s" "$_g")" "$_t" "$_tw"
            done < "$TMP/rem.l" ;;
        add|done|snooze|delete|restore) _a=$1; shift
            [ $# -gt 0 ] || [ "$_a" = add ] || refuse_in reminders "$_a takes the reminder's name (spark-shell reminders lists them)"
            _l=$(rem_act "$_a" "$*") || refuse_in reminders "$_l"; echo "$_l" ;;
        *) refuse_in reminders "$1 is not something reminders does: add, done, snooze, delete or restore" ;;
    esac
}
cmd_apps_verb() {   # spark-shell apps: the picker
    config_load
    [ "$OS" = Darwin ] || pm_detect
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own desktop"
    cmd_apps
}
layout_on_path() { case $(command -v "$1" 2>/dev/null) in /*) return 0 ;; *) return 1 ;; esac; }   # a program, not a keyword or builtin
layout_app_known() { grep -q "^$1: " "$TMP/apps"; }                       # layout_app_known NAME
layout_app_term() { grep "^$1: " "$TMP/apps" | grep -q ', terminal$'; }   # layout_app_term NAME
layout_launch() {   # layout_launch NAME ARGS -> the command line
    _l=$(grep "^$1	" "$TMP/exec" 2>/dev/null | head -1 | cut -f2-)
    [ -n "$_l" ] || _l="$1 %U"
    case $_l in *%[fFuU]*) _l="${_l%%"%"[fFuU]*}$2${_l#*"%"[fFuU]}" ;; *) _l="$_l $2" ;; esac
    printf '%s' "$_l" | sed 's/  */ /g; s/ *$//'
}
# $TMP/screens: a line per active output, `NAME WxH left|middle|right`;
# never make, model or serial
layout_screens() {
    [ ! -f "$TMP/screens" ] || return 0
    swaymsg -t get_outputs 2>/dev/null | jq -r '[.[] | select(.active != false)] | sort_by(.rect.x) | length as $n | to_entries[]
        | "\(.value.name) \(.value.rect.width // .value.current_mode.width)x\(.value.rect.height // .value.current_mode.height) \(if .key == 0 then "left" elif .key == $n - 1 then "right" else "middle" end)"' > "$TMP/screens" 2>/dev/null || true
    [ -s "$TMP/screens" ] || echo "- 1920x1080 left" > "$TMP/screens"
}
layout_said() { paste -sd, - | sed "s/,\([^,]*\)\$/ $1 \1/; s/,/, /g"; }   # layout_said and|or, stdin lines -> "a, b and c"
layout_screens_say() {   # -> the brief's words
    if [ "$(wc -l < "$TMP/screens")" -le 1 ]; then echo "one screen, $(cut -d' ' -f2 "$TMP/screens")"
    else echo "screens: $(awk '{print $3, $2}' "$TMP/screens" | paste -sd, - | sed 's/,/, /g')"; fi
}
layout_ws_said() { sed -n 's/^workspace number //p' "$1" | layout_said and; }   # layout_ws_said FILE -> "3" or "3 and 4"
layout_next_ws() {   # layout_next_ws [SKIP...] -> the lowest free workspace not in SKIP
    used="$(swaymsg -t get_workspaces 2>/dev/null | jq -r '.[].num' 2>/dev/null) $*"
    n=1; while printf '%s\n' $used | grep -qx "$n"; do n=$((n + 1)); done
    echo "$n"
}
layout_windows() {   # layout_windows N -> its window count
    swaymsg -t get_tree 2>/dev/null | jq "[.. | objects | select(.type? == \"workspace\" and .num? == $1) | .. | objects | select(.pid? != null)] | length" 2>/dev/null || echo 0
}

layout_gate() {   # the gate: layout_gate LINE -> '' or why not
    verb=${1%% *}
    if [ "$verb" = window-rule ]; then
        case $1 in 'window-rule floating enable'|'window-rule floating disable'|'window-rule border normal'|'window-rule border none'|'window-rule border pixel') return ;; *) echo 'invalid window rule'; return ;; esac
    fi
    case " $LAYOUT_VERBS " in *" $verb "*) ;; *) echo "$verb is not a layout command"; return ;; esac
    bad=$(printf '%s' "$1" | LC_ALL=C tr -d 'A-Za-z0-9 _.:/=,%~@#+?[]"-' | head -c 1)   # what a sway line may hold; the rest is sh's
    [ -z "$bad" ] || { echo "shell syntax or a control character"; return; }
    # sway splits at a comma too: the rest of an exec would go unchecked
    case $verb in exec|window) case $1 in *,*) echo "a comma starts a second sway command"; return ;; esac ;; esac
    case $1 in 'focus output '*) grep -q "^${1#focus output } " "$TMP/screens" 2>/dev/null || echo "${1#focus output } is not a screen here"; return ;; esac
    [ "$verb" = exec ] || [ "$verb" = window ] || return 0
    set -- $1; shift
    if [ "$verb" = window ]; then   # window NAME [CMD ARGS]: bare is a shell
        [ $# -gt 0 ] || { echo "window with no name"; return; }
        shift; [ $# -gt 0 ] || return 0
    elif [ "${1:-}" = foot ]; then   # foot -e CMD is judged as CMD
        [ $# -gt 1 ] || return 0
        [ "${2:-}" != -e ] || shift 2
    fi
    if [ "${1:-}" = python3 ] && [ "${2:-}" = "$REPO/lib/layout.py" ]; then
        [ "$#" -ge 6 ] || { echo "invalid terminal launch"; return; }
        case $3 in "$TMP"/term.*) ;; *) echo "invalid terminal lease"; return ;; esac
        case $4:$5 in *[!0-9:]*) echo "invalid terminal size"; return ;; esac
        [ "$4" -ge 20 ] && [ "$4" -le 240 ] && [ "$5" -ge 5 ] && [ "$5" -le 100 ] || { echo "invalid terminal size"; return; }
        shift 5
    fi
    # a = makes the word a variable, not the program
    case ${1:-} in *=*) echo "a variable before a program is shell syntax"; return ;; esac
    [ -n "${KEPT:-}" ] || case ${1:-} in */*) echo "an app is named, not a path"; return ;; esac
    app=${1:-}; app=${app##*/}
    [ -n "$app" ] || { echo "exec of nothing"; return; }
    case " $LAYOUT_NOT_APPS " in *" $app "*) echo "$app is not an app"; return ;; esac
    # the model's answer stays in its list
    if [ -n "${KEPT:-}" ]; then layout_on_path "$app" || layout_app_known "$app" || echo "$app is not on this machine"
    elif layout_app_known "$app"; then shift; layout_args_ok "$app" "$@"
    elif layout_on_path "$app"; then echo "$app is not one of the allowed apps (spark-shell apps adds it)"
    else echo "$app is not on this machine"; fi
}
layout_args_ok() {   # layout_args_ok APP WORD... -> '' when no word is a new flag
    _dwa=$1; shift
    _dwo=" $(grep "^$_dwa	" "$TMP/exec" 2>/dev/null | head -1 | cut -f2-) ${ED:-} "
    for _dw in "$@"; do
        case $_dw in -*|*\"*) case $_dwo in *" $_dw "*) ;; *) echo "a page or a file, not a flag"; return ;; esac ;; esac
    done
}

# `workspace number N`, never `workspace N output`, which would pin
layout_windows_of() {   # layout_windows_of JSONFILE -> $TMP/windows: SCREEN<tab>APP<tab>INDEX<tab>ARGS, the main first
    jq -r --rawfile s "$TMP/screens" '
        ($s | split("\n") | map(select(. != "") | split(" "))) as $scr
        | def out(w; dflt): (w.screen // "") as $n | ([$scr[] | select(.[0] == $n or .[2] == $n)] | first // [dflt]) | .[0];
        out(.main; $scr[0][0]) as $mo | ([.main] + (.side // [])) as $all
        | ([$all[] | (.screen // "") | select(. != "" and (. as $n | [$scr[] | .[0], .[2]] | index($n)) == null)] | first // "") as $miss
        | $mo, $miss, ($all | to_entries[] | "\(out(.value; $mo))\t\(.value.app)\t\(.key)\t\(.value.args // "")")' "$1" > "$TMP/windows.all"
    # a tab-split read would drop an empty field
    mo=$(sed -n 1p "$TMP/windows.all"); miss=$(sed -n 2p "$TMP/windows.all")
    sed 1,2d "$TMP/windows.all" > "$TMP/windows"
    [ -z "$miss" ] || echo "  the $miss screen is not here -- all on $mo"
}
layout_words_full() { case " $(panel_lower "$1") " in *' fullscreen '*|*' full screen '*|*' full-screen '*) echo true ;; *) echo false ;; esac; }   # layout_words_full WORDS
layout_words_ws() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -n 's/.*workspace \([1-9][0-9]*\).*/\1/p' | sed -n 1p; }   # layout_words_ws WORDS -> the workspace named
layout_term_line() {   # layout_term_line JSON INDEX APP ARGS -> the exec foot line
    _min=$(jq -r --argjson n "$2" --arg app "$3" '[.main] + (.side // []) | .[$n] |
        [(.min_columns // (if $app == "btop" then 80 else 0 end)), (.min_rows // 24)] |
        if all(.[]; type == "number" and . == floor) and .[0] >= 20 and .[0] <= 240 and .[1] >= 5 and .[1] <= 100 then "\(.[0]) \(.[1])" else empty end' "$1")
    if [ -n "$_min" ]; then
        _lease=$(mktemp "$TMP/term.XXXXXX"); echo wait > "$_lease"
        printf 'exec foot -e python3 %s/lib/layout.py %s %s %s\n' "$REPO" "$_lease" "$_min" "$(layout_launch "$3" "$4")"
    else printf 'exec foot -e %s\n' "$(layout_launch "$3" "$4")"; fi
}
layout_terminal_ready() {   # false when a lease did not confirm
    _dtr_failed=0
    for _lease in "$TMP"/term.*; do
        [ -f "$_lease" ] || continue
        case $_lease in *.result) continue ;; esac
        echo ready > "$_lease"
    done
    for _lease in "$TMP"/term.*; do
        [ -f "$_lease" ] || continue
        case $_lease in *.result) continue ;; esac
        _wait=0
        while [ ! -s "$_lease.result" ] && [ "$_wait" -lt 100 ]; do sleep 0.05; _wait=$((_wait + 1)); done
        if [ ! -s "$_lease.result" ]; then echo '  terminal app did not confirm its minimum size'; _dtr_failed=1
        elif [ "$(cat "$_lease.result")" != ready ]; then printf '  %s\n' "$(cat "$_lease.result" | scrub_text)"; _dtr_failed=1; fi
    done
    [ "$_dtr_failed" = 0 ]
}
layout_lines() {   # layout_lines WS JSONFILE -> the sway lines
    w=$1; used=''; main=1; many=$(wc -l < "$TMP/screens" | tr -d ' ')
    for scr in $(cut -f1 "$TMP/windows" | awk '!seen[$0]++'); do
        [ "$many" -le 1 ] || printf 'focus output %s\n' "$scr"
        [ -z "$used" ] || w=$(layout_next_ws $used)
        used="$used $w"
        printf 'workspace number %s\n' "$w"
        [ -z "${LAYOUT_LABEL:-}" ] || printf 'rename workspace to "%s %s"\n' "$w" "$LAYOUT_LABEL"   # the bar reads "3 writing"
        grep "^$scr	" "$TMP/windows" | {
            i=0
            while IFS='	' read -r _ app index args; do
                [ "$app" != editor ] || [ -n "$ED" ] || continue
                case $i in 1) echo splith ;; 2) echo splitv ;; esac   # the next window's split
                case $app in
                    shell) echo "exec foot" ;;
                    editor) if editor_windowed; then printf 'exec %s\n' "$(layout_launch "$ED" "$args")"; else layout_term_line "$2" "$index" "$ED" "$args"; fi ;;
                    *) if layout_app_term "$app" || { ! layout_app_known "$app" && layout_on_path "$app"; }; then layout_term_line "$2" "$index" "$app" "$args"; else printf 'exec %s\n' "$(layout_launch "$app" "$args")"; fi ;;
                esac
                jq -r --argjson n "$index" '[.main] + (.side // []) | .[$n] |
                    (if (.floating | type) == "boolean" then "window-rule floating " + (if .floating then "enable" else "disable" end) else empty end),
                    (if (.border as $b | ["normal", "none", "pixel"] | index($b)) != null then "window-rule border " + .border else empty end)' "$2"
                [ "$i" -ne 0 ] || [ -z "$main" ] || [ "$(jq -r '.main.fullscreen // false' "$2")" != true ] || echo "fullscreen enable"
                i=$((i + 1))
            done
            if [ -n "$main" ] && [ "$i" -gt 1 ]; then
                echo "focus left"
                printf 'resize set width %s ppt\n' "$(jq -r '.main.width // 70 | if . < 20 then 20 elif . > 90 then 90 else floor end' "$2")"
            fi
            [ -z "$main" ] || case $(jq -r '.arrange // ""' "$2") in tabs) echo 'layout tabbed' ;; stacked) echo 'layout stacking' ;; esac
        }
        main=''
    done
}
layout_rooms() {   # layout_rooms NAME JSONFILE -> the lines
    printf 'session %s\n' "$1"
    jq -r '[.main] + (.side // []) | .[] | "\(.app) \(.args // "")"' "$2" | sed 's/ *$//' | while IFS= read -r line; do
        app=${line%% *}; args=''; case $line in *' '*) args=${line#* } ;; esac
        case $app in
            shell) echo "window shell" ;;
            editor) [ -z "$ED" ] || printf 'window editor %s\n' "$(layout_launch "$ED" "$args")" ;;
            *) printf 'window %s %s\n' "$app" "$(layout_launch "$app" "$args")" ;;
        esac
    done
}
layout_play_rooms() {   # layout_play_rooms FILE -> true when a room ran
    name=$(sed -n 's/^session //p' "$1" | head -1)
    if tmux has-session -t "=$name" 2>/dev/null; then echo "  the tmux session $name is open already"; return 0; fi
    ran=0
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in ''|'#'*) continue ;; esac
        why=$(layout_gate "$line")
        if [ -n "$why" ]; then echo "  refused  $line  ($why)"; continue; fi
        [ "$VERBOSE" != 1 ] || echo "  $line"
        case $line in 'session '*) continue ;; esac
        set -- $line; shift; room=$1; shift; cmd=$*; prog=${1:-}; prog=${prog##*/}
        if [ "$prog" = "$room" ]; then shown=$cmd; else shown="$room $cmd"; fi; shown=${shown% }
        # the model's answer keeps to the terminal apps offered
        if [ -z "${KEPT:-}" ] && [ -n "$prog" ] && layout_app_known "$prog" && ! layout_app_term "$prog"; then echo "  $shown -- needs the desktop"; continue; fi
        if [ "$ran" -eq 0 ]; then set -- new-session -d -s "$name" -n "$room"; else set -- new-window -t "=$name" -n "$room"; fi
        [ -z "$cmd" ] || set -- "$@" "$cmd"   # one argument: tmux hands it to sh -c
        tmux "$@" || { echo "  tmux refused: $line"; continue; }
        ran=$((ran + 1)); echo "  $shown"
    done < "$1"
    [ "$ran" -gt 0 ]
}
layout_join() {   # layout_join NAME
    if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$1"
    elif [ -t 0 ] && [ -t 1 ]; then tmux attach-session -t "=$1"
    else echo "tmux session $1 -- tmux attach-session -t $1 joins it"; fi
}
layout_editor() {   # -> what the `editor` word opens
    if [ -n "${EDITOR:-}" ]; then printf '%s\n' "${EDITOR##*/}"
    elif _de=$(editor_entry); then printf '%s\n' "$_de" | cut -f1
    elif layout_on_path vi; then echo vi
    else return 1; fi
}
LAYOUT_SMALL_WORDS='["and","or","with","the","a","an","in","on","for","to","my","of","at","plus","also","then","now","please","open","window","windows","layout","desktop","terminal","workspace","fullscreen","full","screen","it","them","me","i","some"]'   # words that ground nothing
layout_named() {   # layout_named JSONFILE NEED -> JSONFILE narrowed to what the need names
    # a window stays when the need quotes or names it; the rest is suggested
    _w=" $(printf '%s' "$2" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_.+-' ' ' | sed 's/[.-]*  */ /g; s/[.-]*$//; s/  */ /g') "
    _ed=$(printf '%s' "$ED" | tr 'A-Z' 'a-z'); _names=''
    for _x in $_w; do
        if [ "$_x" = editor ]; then [ -z "$ED" ] || _names="$_names$_x
"; continue; fi
        _n=$(awk -F': ' -v w="$_x" 'tolower($1) == w {print $1; exit}' "$TMP/apps")
        [ -z "$_n" ] || _names="$_names$_n
"
    done
    jq --arg w "$_w" --arg ed "$_ed" --arg names "$_names" --argjson small "$LAYOUT_SMALL_WORDS" '
        def key: ascii_downcase as $a | if $a == "editor" or ($ed != "" and $a == $ed) then "editor" else $a end;
        def named: (.app | ascii_downcase) as $a
            | ($w | contains(" " + $a + " "))
              or ($a == "editor" and $ed != "" and ($w | contains(" " + $ed + " ")))
              or ($ed != "" and $a == $ed and ($w | contains(" editor ")));
        def grounded: ((.app // "") | ascii_downcase) as $app
            | ((.quote // "") | ascii_downcase | gsub("[^a-z0-9_.+-]+"; " ") | split(" ")
               | map(select(. != "" and (. as $x | ($small | index($x) | not) or ($app == "shell" and (["terminal", "shell", "console"] | index($x)))))) ) as $fw
            | ($fw | length) > 0 and all($fw[]; . as $x | $w | contains(" " + $x + " "));   # a shell is grounded by the words that name a terminal, which ground no other window
        ([.main] + (.side // [])) as $all
        | (any($all[]; has("quote"))) as $tied
        | ([$all[] | select(named or ($tied and grounded))] | reduce .[] as $x ([]; if any(.[]; (.app | ascii_downcase) == ($x.app | ascii_downcase) and (.args // "") == ($x.args // "")) then . else . + [$x] end)) as $k
        | ($names | split("\n") | map(select(. != ""))
           | reduce .[] as $n ([]; if (map(key) | index([$n | key])) then . else . + [$n] end)) as $nm
        | ($k | map(.app | key)) as $have
        | [$nm[] | select((key) as $x | $have | index([$x]) | not) | {app: ., args: ""}] as $add
        | ($k + $add) as $open
        | if ($open | length) == 0 then .
          else .main.width as $wd
            | .main = ($open[0] + (if $open[0].width == null and $wd != null then {width: $wd} else {} end))
            | .side = $open[1:] | .suggested = ([$all[] | select((named or ($tied and grounded)) | not) | .app] | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end))
          end' "$1" > "$TMP/named.json" 2>/dev/null || return 0
    _s=''
    for a in $(jq -r '.suggested // [] | .[]' "$TMP/named.json"); do   # only an app on the list
        case $a in shell|editor) ;; *) layout_app_known "$a" || continue ;; esac
        _s="$_s$a
"
    done
    jq --arg s "$(printf '%s' "$_s" | paste -sd, -)" '.suggested = ($s | split(",") | map(select(. != "")))' "$TMP/named.json" > "$1"   # the panel's rows read it
    [ -n "$_s" ] || return 0
    if [ "$(printf '%s' "$_s" | wc -l)" -gt 1 ]; then _it=them; else _it=it; fi
    echo "  also suggested: $(printf '%s' "$_s" | layout_said and) -- add $_it to your words to open $_it"
}
layout_set() { jq -c '[.main] + (.side // []) | map([.app, (.args // "")])' "$1" 2>/dev/null; }   # layout_set JSONFILE -> its windows
layout_has() { jq -e --arg a "$2" '[.main] + (.side // []) | any(.app == $a)' "$1" >/dev/null 2>&1; }   # layout_has JSONFILE APP
layout_in_sway() { [ -n "${SWAYSOCK:-}" ] && [ -n "$(swaymsg -t get_version 2>/dev/null)" ]; }   # a sway that answers
layout_on() {   # -> desktop or terminal; LAYOUT_ON forces one
    if [ -n "${LAYOUT_ON:-}" ]; then echo "$LAYOUT_ON"; elif layout_in_sway; then echo desktop; else echo terminal; fi
}
layout_render() {   # layout_render JSONFILE -> $TMP/desk; ws the main's workspace
    ED=$(layout_editor) || ED=''
    : "${LAYOUT_LABEL:=$(layout_ws_label "$(layout_words "$1")")}"
    [ -n "$ED" ] || ! layout_has "$1" editor || echo "  editor -- no editor on this machine: set EDITOR in ~/.config/spark-shell/rc"
    if [ "$LAYOUT_ON" = terminal ]; then layout_rooms "$(layout_name_of "$(layout_words "$1")")" "$1" > "$TMP/desk"; return; fi
    layout_screens
    layout_windows_of "$1"
    ws=$(layout_words_ws "$(layout_words "$1")"); [ -n "$ws" ] || ws=$(layout_next_ws)
    layout_lines "$ws" "$1" > "$TMP/desk"
}
layout_show() {   # layout_show WHOSE -- KEPT=1 for a kept one
    if [ "$LAYOUT_ON" = terminal ]; then
        name=$(sed -n 's/^session //p' "$TMP/desk" | head -1)
        layout_play_rooms "$TMP/desk" || refuse "nothing ran"
        echo "tmux session $name -- $1"
        if layout_in_sway; then   # a foot window of its own
            _w=$(layout_next_ws); printf 'workspace number %s\nrename workspace to "%s %s"\nexec foot -e tmux attach-session -t =%s\n' "$_w" "$_w" "$(layout_ws_label "$name")" "$name" > "$TMP/desk.win"
            KEPT=1 layout_play "$TMP/desk.win" >/dev/null || refuse 'the layout workspace could not be opened'; : > "$TMP/opened"
        else layout_join "$name"; fi
        return
    fi
    # the panel's window goes with the desk
    [ -z "${ASKED:-}" ] || swaymsg -- "[app_id=$PANEL_APP] move container to workspace number $ws" >/dev/null 2>&1 || true
    layout_play "$TMP/desk" || refuse "the layout did not finish; some windows may already be open"
    : > "$TMP/opened"   # the panel's window closes on it
    echo "on workspace $(layout_ws_said "$TMP/desk")${1:+ -- $1}"
    [ -z "${ASKED:-}" ] || swaymsg -- "[app_id=$PANEL_APP] focus" >/dev/null 2>&1 || true   # the keys stay the panel's
}

layout_play() {   # layout_play FILE -> the lines sent to sway
    sent=0; nowin=0; _ws=''; _new_id=''; _dp_failed=0
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in ''|'#'*) continue ;; exec*) _new_id='' ;; esac
        why=$(layout_gate "$line")
        if [ -n "$why" ]; then echo "  refused  $line  ($why)"; _dp_failed=1; case $line in exec*) nowin=1 ;; esac; continue; fi
        # a split with no window would cut the one before it
        case $line in split*) [ "$nowin" = 0 ] || { [ "$VERBOSE" != 1 ] || echo "  skipped  $line  (no window to split)"; nowin=0; continue; } ;; esac
        [ "$VERBOSE" != 1 ] || echo "  $line"
        case $line in 'workspace number '*) _ws=${line#workspace number } ;; esac
        case $line in 'window-rule '*)
            if [ -n "$_new_id" ]; then swaymsg -- "[con_id=$_new_id] ${line#window-rule }" >/dev/null || { echo "  window rule refused"; _dp_failed=1; }
            else echo "  window rule skipped: no single new window"; _dp_failed=1; fi
            continue ;;
        esac
        case $line in exec*) swaymsg -t get_tree 2>/dev/null | jq '[.. | objects | select(.pid? != null) | .id]' > "$TMP/old.windows" ;; esac
        before=$(layout_windows "$_ws")
        swaymsg -- "$line" >/dev/null || { echo "  sway refused: $line"; _dp_failed=1; continue; }
        sent=$((sent + 1))
        case $line in exec*)
            # until its window maps; 3 s grace for a program that ended
            set -- $line; shift; [ "${1:-}" = foot ] && [ "${2:-}" = -e ] && shift 2
            if [ "${1:-}" = python3 ] && [ "${2:-}" = "$REPO/lib/layout.py" ]; then shift 5; fi
            prog=${1##*/}; shown=$*; t=0
            layout_pulse
            while [ "$(layout_windows "$_ws")" -le "$before" ] && [ "$t" -lt $((LAYOUT_WAIT * 4)) ]; do
                [ "$t" -lt 12 ] || pgrep -u "$(id -u)" -x "$prog" >/dev/null 2>&1 || break
                sleep 0.25; t=$((t + 1))
            done
            layout_pulse_stop
            _new_id=$(swaymsg -t get_tree 2>/dev/null | jq -r --slurpfile old "$TMP/old.windows" --argjson ws "$_ws" '
                [.. | objects | select(.type? == "workspace" and .num? == $ws) | .. | objects | select(.pid? != null) | .id | select(. as $id | $old[0] | index($id) | not)] |
                if length == 1 and (.[0] | type) == "number" then .[0] else empty end' 2>/dev/null)
            if [ "$(layout_windows "$_ws")" -gt "$before" ]; then nowin=0; echo "  $shown"; else nowin=1; _dp_failed=1; echo "  $shown -- no window"; fi ;;
        esac
    done < "$1"
    layout_terminal_ready || _dp_failed=1
    [ "$sent" -gt 0 ] && [ "$_dp_failed" = 0 ]
}

layout_make() {   # layout_make NEED -> the desk laid out
    command -v jq >/dev/null 2>&1 || refuse "jq is not installed (spark-shell on)"
    spark=$(spark_bin)
    [ -n "$spark" ] || refuse "spark is not installed -- spark picks the apps for a layout (github.com/forgewright-ai/spark)"
    [ "$LAYOUT_ON" != terminal ] || command -v tmux >/dev/null 2>&1 || refuse "tmux is not installed (spark-shell on)"
    layout_apps "$1" > "$TMP/apps"
    [ -s "$TMP/apps" ] || refuse "no apps found on this machine (no desktop entries, no chosen packages)"
    [ "$LAYOUT_ON" = terminal ] || layout_screens
    about=$(layout_brief)
    [ -n "${ASKED:-}" ] || printf 'layout> %s\n' "$1"
    layout_pulse
    st=0; "$spark" edit --type json --name layout.json --about "$about" -- "write the layout for this need: $1" </dev/null > "$TMP/desk.json" 2>"$TMP/desk.err" || st=$?
    layout_pulse_stop
    [ "$st" -eq 0 ] || refuse "spark did not answer: $(head -1 "$TMP/desk.err")"
    jq -e '.main.app | strings' "$TMP/desk.json" >/dev/null 2>&1 || refuse "the answer was not a layout (spark-shell layout -v shows it)"
    # never the model's: window rules and minimum sizes
    jq '.main |= del(.floating, .border, .min_columns, .min_rows) | .side = ((.side // []) | map(del(.floating, .border, .min_columns, .min_rows)))' "$TMP/desk.json" > "$TMP/desk.clean"
    mv "$TMP/desk.clean" "$TMP/desk.json"
    ED=$(layout_editor) || ED=''
    answer=$(layout_set "$TMP/desk.json")
    layout_named "$TMP/desk.json" "$1" > "$TMP/named.say"
    changed=''; [ "$(layout_set "$TMP/desk.json")" = "$answer" ] || changed=1
    why=$(layout_why "$TMP/desk.json")
    [ -n "$changed" ] || [ -z "$why" ] || printf '  %s\n' "$why"
    for a in $(jq -r '[.main] + (.side // []) | .[].app' "$TMP/desk.json"); do
        [ "$a" != editor ] || continue   # a layout word, not an app
        layout_app_known "$a" && continue
        if layout_on_path "$a"; then echo "  $a is not one of the allowed apps -- laid out without it (spark-shell apps adds it)"
        else echo "  $a is not on this machine -- laid out without it"; fi
    done
    cat "$TMP/named.say"
    mkdir_private "$(dirname "$LAYOUT_LAST")"
    jq --arg w "$1" --arg ch "$changed" --argjson full "$(layout_words_full "$1")" '{words: $w} + . | if $ch == "" then . else del(.why) end | if $full then .main.fullscreen = true else . end' "$TMP/desk.json" > "$LAYOUT_LAST"
    layout_render "$LAYOUT_LAST"
    layout_keep "$1"
    if [ -n "${ASKED:-}" ]; then layout_show ''; else layout_show "spark-shell layout save NAME saves it"; fi   # the panel has its save row
}
layout_keep() {   # layout_keep WORDS
    _kn=$(layout_name_of "$1"); [ -n "$_kn" ] || return 0
    mkdir_state "$KEPT_LAYOUTS"; jq 'del(.suggested)' "$LAYOUT_LAST" > "$KEPT_LAYOUTS/$_kn.new" 2>/dev/null && mv "$KEPT_LAYOUTS/$_kn.new" "$KEPT_LAYOUTS/$_kn"
    kept_note layout "$_kn"
}
layout_kept_file() { if [ -f "$LAYOUTS_DIR/$1" ]; then printf '%s' "$LAYOUTS_DIR/$1"; elif [ -f "$KEPT_LAYOUTS/$1" ]; then printf '%s' "$KEPT_LAYOUTS/$1"; else return 1; fi; }   # layout_kept_file NAME -> its saved or kept file
layout_replay() {   # layout_replay NAME -- no model call
    _rf=$(layout_kept_file "$1") || refuse "no saved layout named $1"
    LAYOUT_LABEL=$(layout_ws_label "$1")
    why=$(layout_open "$_rf"); [ -z "$why" ] || refuse "$why"
    layout_apps "$(layout_words "$_rf")" > "$TMP/apps"   # its words, not its name
    [ -n "${ASKED:-}" ] || printf 'layout> %s\n' "$(layout_words "$_rf")"
    why=$(layout_why "$_rf"); [ -z "$why" ] || printf '  %s\n' "$why"
    layout_render "$_rf"
    if [ -f "$LAYOUTS_DIR/$1" ]; then KEPT=1 layout_show "the saved layout $1"; else layout_show "the layout $1 again"; fi   # saved is yours (KEPT); kept is still the model's
    [ -n "${KEPT_BACK:-}" ] || kept_note layout "$1"
}
layout_back() {   # one step back each time
    while :; do
        _n=$(kept_back layout) || refuse "no layout before this one in the last ten"
        ! layout_kept_file "$_n" >/dev/null || break
    done
    echo "back to $_n"
    KEPT_BACK=1 KEPT_ALSO=1 layout_need "$_n"
}
# the brief for the model
layout_brief() {
    ex='{"why": "one sentence, from the need to the apps chosen", "main": {"app": "NAME", "quote": "the words of the need this window is for", "args": "", "width": 70, "fullscreen": false}, "side": [{"app": "NAME", "quote": "the words of the need this window is for", "args": ""}]}'
    rule=' The need is read part by part: each thing it names, split at and or a comma, is one window of its own, with quote: the words of that part as they are in the need (two things named, two windows, each with the words of its own part). A window the need has no words for is not in the layout, and one window never answers two parts. main fullscreen is true only when the need says fullscreen or full screen: that window alone fills the screen, and side is then empty.'
    if [ "$LAYOUT_ON" = terminal ]; then
        opening="A layout of tmux windows: the apps for one need, each in a terminal window, on a $(tput cols 2>/dev/null || echo 80)x$(tput lines 2>/dev/null || echo 24) terminal."
        apps=$(grep ', terminal$' "$TMP/apps")
    else
        opening="A layout: the windows for one need, on $(layout_screens_say)."
        apps=$(cat "$TMP/apps")
        if [ "$(wc -l < "$TMP/screens")" -gt 1 ]; then
            ex='{"why": "one sentence, from the need to the apps chosen", "main": {"app": "NAME", "quote": "the words of the need this window is for", "args": "", "width": 70, "fullscreen": false, "screen": "left"}, "side": [{"app": "NAME", "quote": "the words of the need this window is for", "args": "", "screen": "right"}]}'
            rule="$rule A window is on one screen; screen is $(cut -d' ' -f3 "$TMP/screens" | layout_said or); one screen unless the need names two or the work needs two."
        fi
    fi
    echo "$opening Apps on this machine (name: what it does): $(printf '%s\n' "$apps" | sed 's/, terminal$//' | paste -sd ';' - | sed 's/;/; /g'). Rules: an app the need names by name is in the layout; otherwise only the apps the work itself needs, as few windows as that takes (one to four), never an app the need does not call for (no helper, no shell, no monitor the need did not ask for); an app may appear twice with different args (a browser on two pages: one window per page, args is that page's URL).$rule Answer with one JSON object and nothing else: $ex -- main is the big window at the left, width its percent of the screen; side is the windows stacked at the right, top to bottom."
}

layout_pulse() { [ ! -t 1 ] || { panel_colors; pulse_start think; }; }   # at a tty only
layout_pulse_stop() { pulse_stop; }
# the old shape (sway lines) is refused
layout_json_ok() { jq -e '(.words | strings) and (.main.app | strings)' "$1" >/dev/null 2>&1; }
layout_old_shape() { head -1 "$1" 2>/dev/null | grep -q '^# desk: '; }
layout_words() { jq -r '.words // ""' "$1" 2>/dev/null; }   # layout_words FILE
layout_why() { jq -r '.why // "" | gsub("[\\n\\r]"; " ")' "$1" 2>/dev/null; }
layout_open() {   # layout_open FILE -> '' or why not
    if layout_old_shape "$1"; then
        echo "$1 is a layout of the old shape (sway lines). spark-shell layout \"$(sed -n 's/^# desk: \(.*\) -- rendered by spark-shell.*/\1/p' "$1" | head -1)\" makes it again, then spark-shell layout save saves it."
    elif ! layout_json_ok "$1"; then echo "$1 is not a layout spark-shell made (one JSON object: words, why, main, side) -- left alone."; fi
}
layout_name_of() {   # layout_name_of WORDS... -> a file name, 40 at most
    printf '%s' "$*" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-40
}
layout_ws_label() {   # layout_ws_label WORDS... -> whole words up to 24
    printf '%s' "$*" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' ' ' | awk '{ s = ""; for (i = 1; i <= NF; i++) { t = (s == "" ? $i : s " " $i); if (length(t) > 24 && s != "") break; s = t } print s }' | cut -c1-24
}
layout_list() {
    [ -d "$LAYOUTS_DIR" ] && [ -n "$(ls -A "$LAYOUTS_DIR" 2>/dev/null)" ] || { echo "no saved layouts yet -- try: spark-shell layout \"focused news reading and music\""; return 0; }
    for f in "$LAYOUTS_DIR"/*; do
        printf '  %-24s %s\n' "${f##*/}" "$(layout_words "$f")"
    done
    echo "spark-shell layout NAME opens one -- layout save [NAME] saves the last layout, layout delete NAME deletes one"
}
layout_save() {   # layout_save [NAME...] -- under its words by default
    [ -f "$LAYOUT_LAST" ] || refuse "no layout to save yet -- spark-shell layout \"WORDS\" makes one"
    why=$(layout_open "$LAYOUT_LAST"); [ -z "$why" ] || refuse "$why"
    name=$(layout_name_of "$*")
    [ -n "$name" ] || name=$(layout_name_of "$(layout_words "$LAYOUT_LAST")")
    [ -n "$name" ] || refuse "save NAME -- a name for it"
    mkdir -p "$LAYOUTS_DIR"; jq 'del(.suggested)' "$LAYOUT_LAST" > "$LAYOUTS_DIR/$name"   # what opened, not what was suggested
    kept_note layout "$name"
    echo "saved $name -- spark-shell layout $name opens it ($LAYOUTS_DIR/$name)"
}
layout_delete() {   # layout_delete NAME...
    name=$(layout_name_of "$*"); [ -n "$name" ] || refuse "delete NAME -- which layout?"
    if [ ! -f "$LAYOUTS_DIR/$name" ] && kept_names layout | grep -qxF -- "$name"; then   # a recent one forgotten
        _kh=$(kept_hist layout); awk -F '\t' -v n="$name" '$2 != n' "$_kh" > "$_kh.new" && mv "$_kh.new" "$_kh"; kept_prune layout
        echo "forgot $name"; return 0
    fi
    [ -f "$LAYOUTS_DIR/$name" ] || refuse "no saved layout named $name"
    why=$(layout_open "$LAYOUTS_DIR/$name"); [ -z "$why" ] || refuse "$why"
    kept_delete_ok layout "$name" || return 0
    if [ -n "${LAYOUT_DELETED:-}" ]; then mkdir -p "$LAYOUT_DELETED" && mv "$LAYOUTS_DIR/$name" "$LAYOUT_DELETED/$name" || refuse "could not delete $name"   # the dialog's undo brings it back
    else rm -f "${LAYOUTS_DIR:?}/${name:?}"; fi
    _kh=$(kept_hist layout); [ ! -f "$_kh" ] || { awk -F '\t' -v n="$name" '$2 != n' "$_kh" > "$_kh.new" && mv "$_kh.new" "$_kh"; }; kept_prune layout
    echo "deleted $name"
}
layout_rename() {   # layout_rename NAME NEW... -- its history lines follow
    _ro=$(layout_name_of "${1:-}"); [ $# -eq 0 ] || shift
    _rn=$(layout_name_of "$*")
    [ -n "$_ro" ] && [ -n "$_rn" ] || refuse "rename NAME NEW -- the layout and its new name"
    if [ ! -f "$LAYOUTS_DIR/$_ro" ] && [ -f "$KEPT_LAYOUTS/$_ro" ]; then   # a recent one saved under a name
        [ ! -e "$LAYOUTS_DIR/$_rn" ] || refuse "$_rn is a layout already: pick another name"
        mkdir -p "$LAYOUTS_DIR"; cp "$KEPT_LAYOUTS/$_ro" "$LAYOUTS_DIR/$_rn"; kept_note layout "$_rn"
        echo "saved as $_rn"; return 0
    fi
    [ -f "$LAYOUTS_DIR/$_ro" ] || refuse "no saved layout named $_ro"
    [ "$_rn" != "$_ro" ] || refuse "$_ro is its name already"
    [ ! -e "$LAYOUTS_DIR/$_rn" ] || refuse "$_rn is a layout already: pick another name"
    mv "$LAYOUTS_DIR/$_ro" "$LAYOUTS_DIR/$_rn"
    _kh=$(kept_hist layout); [ ! -f "$_kh" ] || { awk -F '\t' -v o="$_ro" -v n="$_rn" 'BEGIN { OFS = "\t" } $2 == o { $2 = n } { print }' "$_kh" > "$_kh.new" && mv "$_kh.new" "$_kh"; }
    echo "$_ro renamed to $_rn"
}
layout_label() {   # layout_label FILE -> its words when the name is only those
    _dw=$(layout_words "$1"); _dn=${1##*/}
    if [ -n "$_dw" ] && [ "$(layout_name_of "$_dw")" = "$_dn" ]; then printf '%s' "$_dw"; else printf '%s' "$_dn"; fi
}
layout_need() {   # layout_need WORDS... -- a saved layout first, else the model
    command -v jq >/dev/null 2>&1 || refuse "jq is not installed (spark-shell on)"
    case " $* " in *" -"*|" layout "*|" help "|" save "*|" delete "*|" rename "*|" back "*) refuse "\"$*\" is a command, not what a layout is for (spark-shell layout save|delete|rename|back)" ;; esac
    LAYOUT_ON=$(layout_on)
    if [ "$LAYOUT_ON" = desktop ] && ! layout_in_sway; then layout_start "$*"; return; fi
    [ "$LAYOUT_ON" = terminal ] || [ "$OS" != Darwin ] || refuse "not on macOS, which has its own desktop"
    [ "$LAYOUT_ON" = terminal ] || [ "$DESKTOP" = sway ] || refuse "DESKTOP=$DESKTOP -- spark-shell on desktop first"
    kept=$(layout_name_of "$*")
    if [ -n "$kept" ] && [ -f "$LAYOUTS_DIR/$kept" ]; then layout_replay "$kept"
    elif [ -n "$kept" ] && [ -f "$KEPT_LAYOUTS/$kept" ] && { [ -n "${KEPT_ALSO:-}" ] || [ "$kept" = "$*" ]; }; then layout_replay "$kept"   # by its name alone, or from back
    else layout_make "$*"; fi
}

cmd_layout() {   # cmd_layout [save [NAME] | delete NAME | rename NAME NEW | NAME | WORDS | --ask | --pending]
    config_load
    [ "$OS" = Darwin ] || pm_detect
    REFUSE_AS=layout
    case ${1:-} in
        '') layout_list ;;
        save) shift; layout_save "$@" ;;
        delete) shift; layout_delete "$@" ;;
        rename) shift; layout_rename "$@" ;;
        back) [ $# -le 1 ] || refuse "back takes no word"; layout_back ;;
        --ask) cmd_panel layout ;;
        --pending) layout_pending ;;
        -*) refuse "$1 is not an option here (spark-shell -h)" ;;
        *) layout_need "$@" ;;
    esac
}
layout_pending() {   # at the desktop's start
    ( notify_keep ) </dev/null >/dev/null 2>&1 &
    # the dialog opens warm
    ( _dw=$(dialog_transitions); cat "$REPO/spark-shell" "$DIALOG_BIN" ${_dw:+"$_dw"/*.gif} ) </dev/null >/dev/null 2>&1 &
    # search ranks by meaning
    ( semantic_start ) </dev/null >/dev/null 2>&1 &
    # a command's words out of the history
    _kh=$(kept_hist layout); [ ! -f "$_kh" ] || { awk -F '\t' '$2 !~ /^(layout-(delete|rename|save|back|help)(-|$)|-|help$)/' "$_kh" > "$_kh.new" && mv "$_kh.new" "$_kh"; kept_prune layout; }
    # for spark's prompt line and spark mcp
    if machine_live; then machine_start </dev/null >/dev/null 2>&1 & fi
    [ -f "$LAYOUT_PENDING" ] || return 0
    need=$(head -1 "$LAYOUT_PENDING"); rm -f "$LAYOUT_PENDING"
    [ -z "$need" ] || layout_need "$need"
}

