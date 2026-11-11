# shellcheck extended-analysis=false
# --- notes
NOTES_DIR=$HOME/notes
when_of() { date -d "@$1" "+$2" 2>/dev/null || date -r "$1" "+$2" 2>/dev/null; }   # when_of EPOCH FORMAT (GNU date, else BSD's)
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
note_name() {   # note_name FILE -> its first non-empty line, the heading's hashes off; else the file's name
    _nn=$(awk 'NF { sub(/^#+[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$1" 2>/dev/null | scrub_text | cut_chars 80)
    [ -n "$_nn" ] || { _nn=${1##*/}; _nn=${_nn%.md}; }
    printf '%s\n' "$_nn"
}
notes_list() { read_once notes.list notes_list_now; }   # -> EPOCH<tab>NAME<tab>FILE per note, the newest first
notes_list_now() {
    [ -d "$NOTES_DIR" ] || return 0
    for _f in "$NOTES_DIR"/*.md; do [ -f "$_f" ] && [ ! -L "$_f" ] || continue; printf '%s\t%s\t%s\n' "$(mtime_of "$_f")" "$(note_name "$_f")" "$_f"; done | sort -t "$TAB" -k1,1nr
}
note_file() {   # note_file ID -> the note's path; a title must name exactly one note
    notes_list | awk -F '\t' -v n="$(panel_lower "$1")" -v id="$1" '
        { f=$3; sub(/^.*\//,"",f); if (f == id) { exact=$3; ne++ }; if (tolower($2) == n) { title=$3; nt++ } }
        END { if (ne == 1) print exact; else if (ne > 1) exit 2;
              else if (id ~ /[.]md$/) exit 1; else if (nt == 1) print title; else if (nt > 1) exit 2; else exit 1 }'
}
note_when() {   # note_when EPOCH -> today 09:12, yesterday, Oct 17, or the year
    _d=$(when_of "$1" %Y%m%d); _now=$(date +%s)
    if [ "$_d" = "$(date +%Y%m%d)" ]; then echo "today $(when_of "$1" %H:%M)"
    elif [ "$_d" = "$(when_of "$((_now - 86400))" %Y%m%d)" ]; then echo yesterday
    elif [ "${_d%????}" = "$(date +%Y)" ]; then when_of "$1" '%b %d' | sed 's/ 0/ /'
    else echo "${_d%????}"; fi
}
editor_entry() {   # -> PROGRAM<tab>EXEC<tab>yes|no (runs in a terminal) for the text/plain desktop entry, read once; false without one
    if [ -z "${_EDITOR_ENTRY_SEEN:-}" ]; then
        _EDITOR_ENTRY_SEEN=yes; _EDITOR_ENTRY=''
        if command -v xdg-mime >/dev/null 2>&1 && _ee_d=$(xdg-mime query default text/plain 2>/dev/null) && [ -n "$_ee_d" ]; then
            for _ee_p in "${XDG_DATA_HOME:-$HOME/.local/share}" $(printf '%s' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ':' ' '); do
                _ee_f=$_ee_p/applications/$_ee_d; [ -f "$_ee_f" ] || continue
                _ee_x=$(sed -n '/^Exec=/{s/^Exec=//p;q;}' "$_ee_f" | sed 's/^env [^ ]* //; s/ *%[a-zA-Z]//g; s/  */ /g; s/^ *//; s/ *$//')
                [ -n "$_ee_x" ] || break
                _ee_n=${_ee_x%% *}; _ee_t=no; ! grep -q '^Terminal=true' "$_ee_f" || _ee_t=yes
                _EDITOR_ENTRY=$(printf '%s\t%s\t%s' "${_ee_n##*/}" "$_ee_x" "$_ee_t")
                break
            done
        fi
    fi
    [ -n "$_EDITOR_ENTRY" ] && printf '%s\n' "$_EDITOR_ENTRY"
}
editor_pick() {   # -> EDITOR when its program is here, else the text/plain entry's Exec, else vi; false with none
    if [ -n "${EDITOR:-}" ] && command -v "${EDITOR%% *}" >/dev/null 2>&1; then printf '%s\n' "$EDITOR"
    elif _ep=$(editor_entry); then printf '%s\n' "$_ep" | cut -f2
    elif command -v vi >/dev/null 2>&1; then echo vi
    else return 1; fi
}
editor_windowed() {   # -> 0 when the editor is a windowed application: no terminal wraps it
    [ -z "${EDITOR:-}" ] || ! command -v "${EDITOR%% *}" >/dev/null 2>&1 || return 1
    [ "$(editor_entry | cut -f3)" = no ]
}
editor_exec() {   # editor_exec FILE -> the exec line sway runs to open FILE in the editor; false with no editor
    _ex=$(editor_pick) || return 1
    if editor_windowed; then printf "%s '%s'\n" "$_ex" "$1"; else printf "foot -e %s '%s'\n" "$_ex" "$1"; fi
}
note_slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40; }   # note_slug WORDS -> a file name
note_open_file() {   # note_open_file FILE NAME -> one line; the note opens in the editor
    desk_in_sway || { echo "a note opens in the desktop's terminal: ${1#"$HOME"/} is the file"; return 1; }
    case $1 in *[,\;\'\"]*) echo "the file's name holds a comma, a quote or a semicolon, which sway would split: ${1##*/}"; return 1 ;; esac
    _ed=$(editor_exec "$1") || { echo "no editor here: set EDITOR in ~/.config/spark-shell/rc"; return 1; }
    swaymsg -- exec "$_ed" >/dev/null 2>&1 || { echo "could not open $2"; return 1; }
    : > "$TMP/opened"; echo "opened $2"
}
notes_act() {   # notes_act new|open|add|find [ARG]
    case $1 in
        new) mkdir_private "$NOTES_DIR"; _f=$NOTES_DIR/$(date +%Y-%m-%d-%H%M%S).md
            [ -e "$_f" ] || (umask 077 && printf '# \n' > "$_f")
            note_open_file "$_f" "a new note" ;;
        open) _f=$(note_file "$2") || { echo "no unique note named $2; select its file in Notes"; return 1; }; note_open_file "$_f" "$(note_name "$_f")" ;;
        add) [ -n "$2" ] || { echo "add takes the words of the note"; return 1; }
            mkdir_private "$NOTES_DIR"
            case $2 in *": "*) _f=$(note_file "${2%%: *}") || {
                    _nf=$?; [ "$_nf" -ne 2 ] || { echo "more than one note has that title; use its filename before the colon"; return 1; }
                    case ${2%%: *} in *.md) echo "that note file is no longer available"; return 1 ;; esac
                } ;; *) _f='' ;; esac
            if [ -n "$_f" ]; then
                printf -- '- %s\n' "${2#*: }" >> "$_f" || { echo "could not write the note"; return 1; }
                note_effect "$_f" appended
                echo "added to ${2%%: *}: ${2#*: }"; return 0
            fi
            _s=$(note_slug "$2"); [ -n "$_s" ] || _s=$(date +%Y-%m-%d-%H%M%S); _f=$NOTES_DIR/$_s.md; _n=2
            while [ -e "$_f" ]; do _f=$NOTES_DIR/$_s-$_n.md; _n=$((_n + 1)); done
            (umask 077 && printf '# %s\n' "$2" > "$_f") || { echo "could not write the note"; return 1; }
            note_effect "$_f" created
            echo "new note: $2" ;;
        find) [ -n "$2" ] || { echo "find takes the words to look for"; return 1; }
            notes_list | while IFS="$TAB" read -r _e _n _f; do
                _l=$({ tail -n +2 "$_f" | grep -i -m1 -F -- "$2" || head -1 "$_f" | grep -i -F -- "$2"; } 2>/dev/null | sed 's/^[#*-]*[[:space:]]*//' | scrub_text | cut -c1-120) || continue
                [ -z "$_l" ] || printf '%s\t%s\n' "$_n" "$_l"   # not false at the end: a last note with no match is no failure
            done > "$TMP/notes.found"
            _c=$(grep -c . "$TMP/notes.found" || :)
            if [ "${_c:-0}" -eq 0 ]; then echo "no note says $2"
            else _w='notes say'; [ "$_c" != 1 ] || _w='note says'; IFS="$TAB" read -r _n _l < "$TMP/notes.found"; echo "$_c $_w $2 $PANEL_SEP $_n: $_l"; fi ;;
        *) echo "$1 is not something notes does"; return 1 ;;
    esac
}
note_says() {   # note_says FILE WORDS -> 0 when the note holds every word, in any case
    printf '%s\n' "$2" | tr -s '[:space:]' '\n' | while IFS= read -r _nw; do
        [ -z "$_nw" ] || grep -qiF -- "$_nw" "$1" 2>/dev/null || exit 1
    done
}
note_effect() {   # note_effect FILE OPERATION -- the effect record for the provider
    [ -n "${PROVIDE_EFFECT:-}" ] || return 0
    jq -cn --arg id "${1##*/}" --arg title "$(note_name "$1")" --arg operation "$2" \
        '{kind: "note", id: $id, title: $title, operation: $operation}' > "$TMP/action.effect"
}
note_append() {   # note_append FILENAME PAYLOAD -- the payload file's text as one bullet in that note
    _nap=$(note_file "$1") || { echo 'select an existing note by its exact filename'; return 1; }
    [ "${_nap##*/}" = "$1" ] && [ -f "$_nap" ] && [ ! -L "$_nap" ] || { echo 'select an existing note by its exact filename'; return 1; }
    { printf '%s' '- ' && cat "$2" && printf '\n'; } >> "$_nap" || { echo 'could not finish appending; check the note before trying again'; return 1; }
    note_effect "$_nap" appended
    printf 'added to %s\n' "$1"
}

