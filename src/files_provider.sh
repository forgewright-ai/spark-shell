# shellcheck extended-analysis=false
# --- the files provider: the rows, the trash, opening, the calls
# reads: FILES_SHOW_LINES FILES_SHOW_MAX FILES_THUMB_DIR OS PANEL_SEP REPO SCRUB_JQ TAB TMP US
provide_files_rows() {   # provide_files_rows [URI] -> the rows the uri names: the roots', a folder's, the trash's, a search's; false when it names no folder files_ok allows
    _fu=${1:-spark-shell://files/rows}; _fhere=''; FILES_N=0; FILES_B=0; FILES_D=0
    [ ! -d "$FILES_THUMB_DIR" ] || rm -rf "$FILES_THUMB_DIR"   # an old cache, removed
    _ffm=''; ! files_manager_ok || _ffm=1   # browse and reveal only where a system file manager is configured
    case $_fu in
        spark-shell://files/rows)
            files_roots | while IFS= read -r _fr; do [ -n "$_fr" ] && printf 'files:root:%s\037opens\037%s\037%s\037\037\037\037\037\037root\037\n' "$(files_b64 "$_fr")" "$(files_home "$_fr" | scrub_text)" "$(files_uri "$_fr")"; done > "$TMP/files.rows"
            _ft='files' ;;
        spark-shell://files/rows/trash)   # the trash, opened as a folder
            files_trash_rows > "$TMP/files.rows"; _ft='trash' ;;
        spark-shell://files/rows/find/?*|spark-shell://files/rows/say/?*|spark-shell://files/rows/match/?*)
            _fk=${_fu#spark-shell://files/rows/}; _fk=${_fk%%/*}; _fw=$(files_unb64 "${_fu##*/}") || return 1
            files_search "$_fk" "$_fw" > "$TMP/files.rows" || return 1
            _ft="$_fk $(printf '%s' "$_fw" | scrub_text)" ;;
        *)
            _fq=${_fu#spark-shell://files/rows/}; _ffrom=0   # a page of a large folder: ?from=N
            case $_fq in *'?from='*) _ffrom=${_fq##*'?from='}; _fq=${_fq%%'?'*}; case $_ffrom in ''|*[!0-9]*) return 1 ;; esac ;; esac
            _fp=$(files_unb64 "$_fq") && _fp=$(files_ok "$_fp" dir) || return 1
            _ft=$(files_home "$_fp" | scrub_text); _fhere=$_fp; _fg=''; : > "$TMP/files.rows"
            files_is_root "$_fp" || printf 'files:up\037opens\037..\037%s\037\037\037\037\037\037up\037\n' "$(files_uri "$(dirname "$_fp")")" >> "$TMP/files.rows"
            _fr=''; if [ "$_fp" = "$(files_home_root)" ] && [ "$_ffrom" = 0 ]; then files_recent > "$TMP/files.recent"; [ ! -s "$TMP/files.recent" ] || { _fr=1; _fg=home; }; fi
            files_list "$_fp" "$_fg" "$_ffrom" >> "$TMP/files.rows"
            [ "${FILES_LEFT:-0}" -eq 0 ] || printf 'files:more\037opens\037the next page\037%s?from=%s\037\037%s more\037\037%s\037\037more\037\n' "$(files_uri "$_fp")" "$FILES_NEXT" "$(files_num "$FILES_LEFT")" "$_fg" >> "$TMP/files.rows"
            [ "$_fp" != "$(files_home_root)" ] || [ "$_ffrom" != 0 ] || printf 'files:trash\037opens\037trash\037spark-shell://files/rows/trash\037\037%s\037\037%s\037\037trashdir\037\n' "$(files_trash_count)" "$_fg" >> "$TMP/files.rows"   # the trash's row
            [ -z "$_fr" ] || cat "$TMP/files.recent" >> "$TMP/files.rows"   # the recent files under your home's row
            [ "$_fp" != "$(files_home_root)" ] || files_drives | while IFS="$TAB" read -r _fdn _fdm _fdf; do printf 'files:drive:%s\037opens\037%s\037%s\037\037%s\037\037drives\037\037drive\037\n' "$(files_b64 "$_fdm")" "$(printf '%s' "$_fdn" | scrub_text)" "$(files_uri "$_fdm")" "$_fdf"; done >> "$TMP/files.rows"
            # this folder's own row at the end
            _fw=''; [ "$FILES_D" -eq 0 ] || { _fw="folders"; [ "$FILES_D" != 1 ] || _fw="folder"; _fw="$(files_num "$FILES_D") $_fw"; }
            [ "$FILES_N" -eq 0 ] || { _fx="files"; [ "$FILES_N" != 1 ] || _fx="file"; _fw="${_fw:+$_fw $PANEL_SEP }$(files_num "$FILES_N") $_fx $PANEL_SEP $(files_size "$FILES_B")"; }
            printf 'files:here\037opens\037this folder %s %s\037\037%s\037\037\037\037\037here\037\n' "$PANEL_SEP" "${_fw:-empty}" "$_fp" >> "$TMP/files.rows" ;;
    esac
    jq -Rn --arg t "$_ft" --arg here "$_fhere" --arg fm "$_ffm" '
        def steps: (if $fm != "" then [{name: "files_reveal", said: "reveal in the system file manager"}] else [] end) + [{name: "files_rename", ask: ["name"], said: "rename"},
            {name: "files_move", pick: "to", said: "move to a folder"}, {name: "files_copy", pick: "to", said: "copy to a folder"}, {name: "files_trash", said: "trash"}];
        # the steps once a list, by kind: a row of a kind takes them with its own path, so a page of a thousand stays small
        {file: {tool: {name: "files_open", said: "open"}, more: ([{name: "files_app", said: "open in app"}, {name: "files_preview", said: "view"}, {name: "files_attach", said: "attach"}] + steps)},
         dir: ({more: ((if $fm != "" then [{name: "files_app", said: "open in app"}] else [] end) + steps)} + (if $fm != "" then {tool: {name: "files_browse", said: "open in the system file manager"}} else {} end)),
         trashed: {tool: {name: "files_restore", said: "restore"}, more: [{name: "files_purge", said: "delete for good"}]}} as $kinds |
        [inputs | split("\u001f") | {id: .[0], sign: .[1], text: .[2], children: (if .[3] == "" then null else .[3] end), path: .[4], c1: .[5], c2: .[6], group: (if .[7] == "" then null else .[7] end), c3: .[8], kind: .[9], preview: .[10], kw: .[11], stamp: .[12]}
            | {path: .path} as $a
            | {id, sign, text: (.text | '"$SCRUB_JQ"'), children, group, columns: ([.c1, .c2, .c3] | if (.[2] // "") != "" and (.[0] // "") != "" then map((. // "") | '"$SCRUB_JQ"') else map(select(. != null and . != "") | '"$SCRUB_JQ"') end),   # a folder found keeps its empty date column, its folder under the folders of the files found
               wide: (if (.kind == "file" or .kind == "dir") and (.kw // "") != "" then ([.kw, .c1, .stamp, .c3] | map((. // "") | '"$SCRUB_JQ"'))
                      elif .kind == "trashdir" or .kind == "drive" then (["", .c1, "", ""] | map((. // "") | '"$SCRUB_JQ"')) else null end),
               page: (if .kind == "file" then "spark-shell://files/preview/" + (.id | ltrimstr("files:file:")) elif .kind == "dir" then "spark-shell://files/preview/" + (.id | ltrimstr("files:dir:")) else null end),
               kind: (if .kind == "file" or .kind == "dir" or .kind == "trashed" then .kind else null end), args: (if .kind == "file" or .kind == "dir" then $a elif .kind == "trashed" then $a + {item: .kw} else null end),
               more: (if .kind == "here" then [{name: "files_new_folder", arguments: $a, ask: ["name"], said: "new folder"}, {name: "files_new_text", arguments: $a, ask: ["name"], said: "new file"}]
                          + (if $fm != "" then [{name: "files_browse", arguments: $a, said: "open in the system file manager"}] else [] end)
                      elif .kind == "trash-here" then [{name: "files_empty", arguments: {}, said: "empty the trash"}] else null end),
               preview: (if .preview != "" then .preview else null end)}
              | with_entries(select(.value != null))] as $rows
        | {title: $t, kinds: $kinds, rows: $rows, short: [$rows[] | select(.id | startswith("files:root:")) | .id]} + (if $here == "" then {} else {here: $here} end)' "$TMP/files.rows"
}
files_urlenc() { printf '%s' "$1" | od -An -tx1 -v | tr -s ' \n' ' ' | awk '{ o = ""; for (i = 1; i <= NF; i++) { h = tolower($i); d = (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1; if ((d >= 48 && d <= 57) || (d >= 65 && d <= 90) || (d >= 97 && d <= 122) || d == 45 || d == 46 || d == 95 || d == 126 || d == 47) o = o sprintf("%c", d); else o = o "%" toupper(h) } printf "%s", o }'; }   # files_urlenc PATH -> the path as a.trashinfo writes it (RFC 2396: the unreserved and the slash as they are, every other byte %XX)
files_urldec() { printf '%s' "$1" | awk '{ o = ""; s = $0; while (match(s, /%[0-9A-Fa-f][0-9A-Fa-f]/)) { o = o substr(s, 1, RSTART - 1) "\\" sprintf("%03o", (index("0123456789abcdef", tolower(substr(s, RSTART + 1, 1))) - 1) * 16 + index("0123456789abcdef", tolower(substr(s, RSTART + 2, 1))) - 1); s = substr(s, RSTART + 3) } printf "%s", o s }' | { IFS= read -r _fud || :; printf "$_fud"; }; }   # files_urldec TEXT -> the path a.trashinfo holds (%XX bytes back, through octal escapes: awk's %c is a character, not a byte, under gawk)
files_trash_dir() {   # files_trash_dir PATH -> the spec's trash for PATH: XDG_DATA_HOME/Trash under your home, .Trash-UID at a drive's top; false when it cannot be made
    _ftr=$(files_root_of "$1") || return 1
    if [ "$_ftr" = "$(files_home_root)" ]; then _ftd=${XDG_DATA_HOME:-$HOME/.local/share}/Trash; else _ftd=$_ftr/.Trash-$(id -u); fi
    (umask 077 && mkdir -p "$_ftd/files" "$_ftd/info") 2>/dev/null || return 1
    printf '%s\n' "$_ftd"
}
files_trash() {   # files_trash PATH -> one line: PATH in the trash, by gio where it is, else by the spec by hand
    _ftd=$(files_trash_dir "$1") || { echo "no trash can be made for ${1##*/}"; return 1; }
    if [ -z "${SPARK_SHELL_NO_GIO:-}" ] && command -v gio >/dev/null 2>&1; then
        gio trash -- "$1" >/dev/null 2>&1 || { echo "could not trash ${1##*/}"; return 1; }
    else
        _ftn=${1##*/}; _ftk=2
        while [ -e "$_ftd/files/$_ftn" ] || [ -L "$_ftd/files/$_ftn" ] || [ -e "$_ftd/info/$_ftn.trashinfo" ]; do _ftn="${1##*/}.$_ftk"; _ftk=$((_ftk + 1)); done
        _ftp=$1; [ "$_ftd" = "${XDG_DATA_HOME:-$HOME/.local/share}/Trash" ] || _ftp=${1#"${_ftd%/.Trash-*}"/}   # on a drive the spec keeps the path from the drive's top
        printf '[Trash Info]\nPath=%s\nDeletionDate=%s\n' "$(files_urlenc "$_ftp")" "$(date +%Y-%m-%dT%H:%M:%S)" > "$_ftd/info/$_ftn.trashinfo" && mv "$1" "$_ftd/files/$_ftn" \
            || { rm -f "$_ftd/info/$_ftn.trashinfo"; echo "could not trash ${1##*/}"; return 1; }
    fi
    echo "${1##*/} is in the trash"
}
files_trash_holds() {   # files_trash_holds RECORD PATH -> true when RECORD (NAME.trashinfo) is the trash's own, with its file, and says PATH
    _frp=$(files_urldec "$(sed -n 's/^Path=//p' "$_ftd/info/$1" 2>/dev/null | head -1)")
    case $_frp in /*) ;; *) _frp=${_ftd%/.Trash-*}/$_frp ;; esac
    [ "$_frp" = "$2" ] && { [ -e "$_ftd/files/${1%.trashinfo}" ] || [ -L "$_ftd/files/${1%.trashinfo}" ]; }
}
files_trashed() {   # files_trashed PATH [ITEM] -> the name under files/ the trash holds from PATH: ITEM when it is one, else the newest; nothing when none
    if [ -n "${2:-}" ]; then
        case $2 in .|..|*/*) return 0 ;; esac
        if files_trash_holds "$2.trashinfo" "$1"; then printf '%s\n' "$2"; fi
        return 0
    fi
    ls -t "$_ftd/info" 2>/dev/null | while IFS= read -r _fri; do
        case $_fri in *.trashinfo) ;; *) continue ;; esac
        files_trash_holds "$_fri" "$1" || continue
        printf '%s\n' "${_fri%.trashinfo}"; break
    done
}
files_restore() {   # files_restore PATH [ITEM] -> one line: ITEM, else the newest file the trash holds from PATH, put back where it was
    _ftd=$(files_trash_dir "$1") || { echo "no trash holds ${1##*/}"; return 1; }
    [ ! -e "$1" ] && [ ! -L "$1" ] || { echo "${1##*/} already exists"; return 1; }
    _frn=$(files_trashed "$1" "${2:-}"); [ -n "$_frn" ] || { echo "the trash holds nothing from ${1##*/}"; return 1; }
    mv "$_ftd/files/$_frn" "$1" || { echo "could not bring ${1##*/} back"; return 1; }
    rm -f "$_ftd/info/$_frn.trashinfo"
    echo "${1##*/} is back"
}
files_purge() {   # files_purge PATH [ITEM] -> one line: ITEM, else the newest file the trash holds from PATH, deleted for good, its record with it
    _ftd=$(files_trash_dir "$1") || { echo "no trash holds ${1##*/}"; return 1; }
    _frn=$(files_trashed "$1" "${2:-}"); [ -n "$_frn" ] || { echo "the trash holds nothing from ${1##*/}"; return 1; }
    rm -rf -- "$_ftd/files/$_frn" && rm -f -- "$_ftd/info/$_frn.trashinfo" || { echo "could not delete ${1##*/}"; return 1; }
    echo "${1##*/} is deleted for good"
}
files_empty() {   # -> one line: your home's trash emptied; a drive's own stays
    _ftd=${XDG_DATA_HOME:-$HOME/.local/share}/Trash
    _fen=$(find "$_ftd/files" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    [ "${_fen:-0}" -gt 0 ] || { echo "the trash is empty already"; return 0; }
    find "$_ftd/files" "$_ftd/info" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || { echo "could not empty the trash"; return 1; }
    rm -f -- "$_ftd/directorysizes"
    echo "the trash is empty: $(files_num "$_fen") deleted for good"
}
files_trash_count() {   # -> the things in your home's trash, in words: 2 files, empty
    _ftc=$(find "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    case $_ftc in 0|'') echo empty ;; 1) echo '1 item' ;; *) echo "$(files_num "$_ftc") items" ;; esac
}
files_trash_rows() {   # -> the rows of your home's trash, the newest first, then the trash's own row
    _ftd=${XDG_DATA_HOME:-$HOME/.local/share}/Trash
    find "$_ftd/info" -mindepth 1 -maxdepth 1 -name '*.trashinfo' -print0 2>/dev/null | files_nul > "$TMP/trash.infos"
    # each record: when, its name under files/, the path it had
    xargs -0 awk -F= '/^Path=/ && !p[FILENAME] { p[FILENAME] = substr($0, 6) } /^DeletionDate=/ && !d[FILENAME] { d[FILENAME] = substr($0, 14) }
        END { for (f in p) { n = f; sub(/.*\//, "", n); sub(/\.trashinfo$/, "", n); print d[f] "\t" n "\t" p[f] } }' < "$TMP/trash.infos" 2>/dev/null | sort -t "$TAB" -k1,1r -k2,2 > "$TMP/trash.list"
    cut -f2 "$TMP/trash.list" | while IFS= read -r _ftn; do printf '%s/files/%s\0' "$_ftd" "$_ftn"; done | files_stats > "$TMP/trash.stats"
    LC_ALL=C awk -F '\t' -v us="$US" -v sep="$PANEL_SEP" -v home="$(files_home_root)" -v stats="$TMP/trash.stats" -v sum="$TMP/files.sum" \
        -v today="$(date +%Y%m%d)" -v yday="$(date -d "@$(( $(date +%s) - 86400 ))" +%Y%m%d 2>/dev/null || date -r "$(( $(date +%s) - 86400 ))" +%Y%m%d)" -v year="$(date +%Y)" '
        function hex(c) { return index("0123456789abcdef", tolower(c)) - 1 }
        function dec(s,   r, i) { r = ""; for (i = 1; i <= length(s); i++) if (substr(s, i, 1) == "%" && i + 2 <= length(s)) { r = r sprintf("%c", hex(substr(s, i + 1, 1)) * 16 + hex(substr(s, i + 2, 1))); i += 2 } else r = r substr(s, i, 1); return r }
        function clean(s) { gsub(/[\001-\037\177]|\302[\200-\237]|\342\200[\213-\217\250-\256]|\342\201[\240\246-\251]|\357\273\277/, "", s); return s }
        function size(n) { if (n < 1024) return sprintf("%d B", n); if (n < 1048576) return sprintf("%d KB", n / 1024); if (n < 1073741824) return sprintf("%.1f MB", n / 1048576); return sprintf("%.1f GB", n / 1073741824) }
        function when(d) { if (d == today) return "today"; if (d == yday) return "yesterday"; if (substr(d, 1, 4) == year) return substr(d, 7, 2) " " mon[substr(d, 5, 2) + 0]; return substr(d, 1, 4) }
        BEGIN {
            split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", mon, " ")
            while ((getline l < stats) > 0) { split(l, sf, us); q = substr(l, length(sf[1] sf[2] sf[3] sf[4] sf[5]) + 6); k = q; sub(/.*\//, "", k); t[k] = tolower(sf[1]); z[k] = sf[2] }
        }
        {
            if (!($2 in t)) next   # a record with nothing under files/: not listed
            p = dec($3); if (p !~ /^\//) next; if (p ~ /[\001-\037\177]/ || $2 ~ /[\001-\037\177]/) next
            name = p; sub(/.*\//, "", name); d = p; sub(/\/[^\/]*$/, "", d); f = d; sub(/.*\//, "", f); if (d == home) f = "~"
            day = substr($1, 1, 4) substr($1, 6, 2) substr($1, 9, 2)
            n++; if (t[$2] !~ /^dir/) b += z[$2]
            print "files:trashed:" clean($2) us "blank" us clean(name) us "" us p us (t[$2] ~ /^dir/ ? "folder" : size(z[$2])) us when(day) us "" us clean(f) us "trashed" us "" us $2
        }
        END { printf "%d 0 %.0f\n", n, b > sum }' "$TMP/trash.list"
    read -r _ftn _ftx _ftb < "$TMP/files.sum"
    _ftw=empty; [ "$_ftn" -eq 0 ] || { _ftw="item"; [ "$_ftn" = 1 ] || _ftw="items"; _ftw="$(files_num "$_ftn") $_ftw $PANEL_SEP $(files_size "$_ftb")"; }
    printf 'files:here\037opens\037the trash %s %s\037\037\037\037\037\037\037trash-here\037\n' "$PANEL_SEP" "$_ftw"
}
files_unreplace() { [ -z "${_fend:-}" ] || files_restore "$_fone" >/dev/null 2>&1 || :; }   # a replace whose move or copy failed: the one there comes back from the trash
files_result() {   # files_result ID RECEIPT [UNDO-TOOL UNDO-ARGS-JSON] [open=URI] -- a step's result: the receipt, its undo, the uri to open
    _fr=$(jq -cn --arg r "$2" '{receipt: $r}')
    [ -z "${3:-}" ] || _fr=$(printf '%s' "$_fr" | jq -c --arg n "$3" --argjson a "$4" '. + {undo: {name: $n, arguments: $a}}')
    case ${5:-} in open=*) _fr=$(printf '%s' "$_fr" | jq -c --arg u "${5#open=}" '. + {open: $u}') ;; esac
    rpc_result "$1" "$(printf '%s' "$_fr" | jq -c '{content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
    [ -z "$SUBSCRIBED" ] || rpc_note notifications/resources/updated "{\"uri\":\"spark-shell://${sec:-files}/rows\"}"
}
files_opened() {   # files_opened ID BEFORE RECEIPT-FILE -- opened, so the dialog closes; a short wait for a new window so a fresh app takes the focus (a browser open already shows none)
    if wm_session; then
        _ow=0; while [ "$(layout_windows_all)" -le "$2" ] && [ "$_ow" -lt 4 ]; do sleep 0.25; _ow=$((_ow + 1)); done
        rpc_result "$1" "$(jq -cn '{opened: true} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
    else rpc_result "$1" "$(jq -c '{content: [{type: "text", text: tojson}], structuredContent: ., isError: false}' "$3")"; fi
}
files_manager_ok() { [ "$OS" = Darwin ] || { command -v xdg-open >/dev/null 2>&1 && [ -n "$(xdg-mime query default inode/directory 2>/dev/null)" ]; }; }   # a system file manager is configured (Finder on macOS)
files_text() { [ -f "$1" ] && { [ ! -s "$1" ] || LC_ALL=C grep -qI . "$1" 2>/dev/null; }; }   # a text file: grep reads it as text; an empty file is one
files_open_text() {   # files_open_text ID PATH -- a text file in the editor in a terminal window (xdg-open would start a terminal editor with none); 1 on macOS, without sway or an editor, or a path sway would split
    [ "$OS" != Darwin ] && files_text "$2" && wm_up && _fed=$(editor_pick) || return 1
    case $2 in *[,\;\'\"]*) return 1 ;; esac
    _wr=0; win_exec "$(editor_exec "$2")" || _wr=$?
    [ "$_wr" -ne 2 ] || { provide_refuse "$1" "files: could not start the editor"; return 0; }
    if [ "$_wr" -eq 0 ]; then rpc_result "$1" "$(jq -cn '{opened: true} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
    else files_result "$1" "$(printf '%s' "${2##*/}" | scrub_text) opens in ${_fed%% *}"; fi
}
files_app_terminal() {   # files_app_terminal PATH -> 0 when the app the system assigns to PATH runs in a terminal
    [ "$OS" != Darwin ] && command -v xdg-mime >/dev/null 2>&1 || return 1
    _fam=$(xdg-mime query filetype "$1" 2>/dev/null); _fad=$(xdg-mime query default "$_fam" 2>/dev/null); [ -n "$_fad" ] || return 1
    _fai=$IFS; IFS=:; set -- ${XDG_DATA_HOME:-$HOME/.local/share} ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; IFS=$_fai
    for _fax in "$@"; do [ ! -f "$_fax/applications/$_fad" ] || { grep -qx 'Terminal=true' "$_fax/applications/$_fad"; return; }; done
    return 1
}
files_open_with() {   # files_open_with ID PATH [--reveal] -- the path through the system's opener (xdg-open, open; a reveal selects it in the file manager)
    if [ "$OS" != Darwin ]; then
        command -v xdg-open >/dev/null 2>&1 || { provide_refuse "$1" "files: xdg-open is not installed, so nothing opens files"; return 0; }
        [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || { provide_refuse "$1" "files: opening a file needs the desktop"; return 0; }
        if { [ -d "$2" ] || [ "${3:-}" = --reveal ]; } && [ -z "$(xdg-mime query default inode/directory 2>/dev/null)" ]; then provide_refuse "$1" "files: no system file manager is configured; folders can still be browsed here"; return 0; fi
    fi
    _before=''; ! wm_session || _before=$(layout_windows_all)
    if ! python3 "$REPO/lib/launch.py" "$OS" "$2" ${3:-} > "$TMP/open.result" 2> "$TMP/open.error"; then provide_refuse "$1" "$(scrub_text < "$TMP/open.error")"; return 0; fi
    files_opened "$1" "$_before" "$TMP/open.result"
}
provide_files_call() {   # provide_files_call ID TOOL ARGUMENTS -- a step over a path files_ok allows; a write answers with its undo
    _fa=$(printf '%s' "$3" | jq -r '.path // ""'); _fto=$(printf '%s' "$3" | jq -r '.to // ""'); _fnm=$(printf '%s' "$3" | jq -r '.name // ""'); _fws=$(printf '%s' "$3" | jq -r '.words // ""')
    case $2 in
        files_stop) files_stop; files_result "$1" "stopped"; return 0 ;;
        files_empty) _fo=$(files_empty) || { provide_refuse "$1" "files: $_fo"; return 0; }; files_result "$1" "$_fo"; return 0 ;;   # for good: no undo
        files_find|files_say) files_call_search "$@"; return 0 ;;
        files_restore|files_purge) files_call_trashed "$@"; return 0 ;;
        files_new_folder|files_new_text) files_call_new "$@"; return 0 ;;
        files_browse) _ff=$(files_ok "$_fa" dir) || { provide_refuse "$1" "files: that is not a folder in the folders given"; return 0; } ;;
        files_open|files_show|files_attach|files_play) _ff=$(files_ok "$_fa" file) || { provide_refuse "$1" "files: that is not a file in the folders given"; return 0; } ;;
        *) _ff=$(files_ok "$_fa" any) || { provide_refuse "$1" "files: that is not a file or a folder in the folders given"; return 0; } ;;
    esac
    _fname=$(printf '%s' "${_ff##*/}" | scrub_text)
    case $2 in files_rename|files_move|files_copy|files_trash) ! files_is_root "$_ff" || { provide_refuse "$1" "files: your home and a drive stay as they are"; return 0; } ;; esac
    case $2 in
        files_open) files_open_text "$1" "$_ff" || files_open_with "$1" "$_ff" ;;
        files_play) files_call_play "$@" ;;
        files_browse) files_open_with "$1" "$_ff" ;;
        files_app)   # the app the system assigns; a terminal program gets a terminal
            if files_app_terminal "$_ff"; then files_open_text "$1" "$_ff" || files_open_with "$1" "$_ff"
            else files_open_with "$1" "$_ff"; fi ;;
        files_reveal) files_open_with "$1" "$_ff" --reveal ;;
        files_show|files_attach) files_call_show "$@" ;;
        files_rename)
            _fn=$(files_new_ok "${_ff%/*}" "$_fnm") || { provide_refuse "$1" "files: $_fn"; return 0; }
            mv "$_ff" "$_fn" 2>/dev/null || { provide_refuse "$1" "files: could not rename $_fname"; return 0; }
            files_result "$1" "$_fname renamed to $_fnm" files_rename "$(jq -cn --arg p "$_fn" --arg n "${_ff##*/}" '{path: $p, name: $n}')" ;;
        files_move|files_copy) files_call_put "$@" ;;
        files_trash)
            _fo=$(files_trash "$_ff") || { provide_refuse "$1" "files: $_fo"; return 0; }
            files_result "$1" "$_fo" files_restore "$(jq -cn --arg p "$_ff" '{path: $p}')" ;;
    esac
}
files_call_search() {   # files_call_search ID TOOL ARGUMENTS -- find (names) or say (text): the count, and the list to open
    _fk=${2#files_}; _fsw=$(printf '%s' "$_fws" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
    [ -n "$_fsw" ] || { provide_refuse "$1" "files: $_fk takes the words to look for"; return 0; }
    _fsu="spark-shell://files/rows/$_fk/$(files_b64 "$_fsw")"
    provide_files_rows "$_fsu" > "$TMP/files.search" || { provide_refuse "$1" "files: $_fk takes plain words, 256 characters at most"; return 0; }
    _fsc=$(jq '[.rows[] | select(.id != "files:total")] | length' "$TMP/files.search")
    if [ "$_fsc" -eq 0 ]; then if [ "$_fk" = find ]; then files_result "$1" "nothing under your home is named $_fsw"; else files_result "$1" "no text file under your home says $_fsw"; fi; return 0; fi
    if [ "$_fk" = find ]; then files_result "$1" "$_fsc named $_fsw" '' '' "open=$_fsu"; else files_result "$1" "$_fsc say $_fsw" '' '' "open=$_fsu"; fi
}
files_call_trashed() {   # files_call_trashed ID TOOL ARGUMENTS -- restore brings one back from the trash to the path it had; purge deletes it for good (no undo)
    _ff=$_fa; case $_ff in /*) ;; *) provide_refuse "$1" "files: that is not a path in the folders given"; return 0 ;; esac
    _ffd=$(files_ok "$(dirname "$_ff")" dir) || { provide_refuse "$1" "files: that is not a folder in the folders given"; return 0; }
    files_name_ok "${_ff##*/}" || { provide_refuse "$1" "files: that is not a name in the folders given"; return 0; }
    _fit=$(printf '%s' "$3" | jq -r '.item // ""')
    if [ "$2" = files_restore ]; then
        _fo=$(files_restore "$_ffd/${_ff##*/}" "$_fit") || { provide_refuse "$1" "files: $_fo"; return 0; }
        files_result "$1" "$_fo" files_trash "$(jq -cn --arg p "$_ffd/${_ff##*/}" '{path: $p}')"
    else
        _fo=$(files_purge "$_ffd/${_ff##*/}" "$_fit") || { provide_refuse "$1" "files: $_fo"; return 0; }
        files_result "$1" "$_fo"
    fi
}
files_call_new() {   # files_call_new ID TOOL ARGUMENTS -- a folder, or an empty text file opened in the editor
    _fn=$(files_new_ok "$_fa" "$_fnm") || { provide_refuse "$1" "files: $_fn"; return 0; }
    if [ "$2" = files_new_folder ]; then mkdir "$_fn" 2>/dev/null || { provide_refuse "$1" "files: could not make $_fnm"; return 0; }
        files_result "$1" "folder $_fnm made in $(files_home "${_fn%/*}")" files_trash "$(jq -cn --arg p "$_fn" '{path: $p}')"; return 0; fi
    : > "$_fn" 2>/dev/null || { provide_refuse "$1" "files: could not make $_fnm"; return 0; }
    if wm_up && editor_pick >/dev/null; then   # in the editor, in a terminal window: the window is the receipt
        case $_fn in *[,\;\'\"]*) ;; *)
            if win_exec "$(editor_exec "$_fn")"; then rpc_result "$1" "$(jq -cn '{opened: true} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"; return 0; fi ;;
        esac
    fi
    files_result "$1" "$_fnm made in $(files_home "${_fn%/*}")" files_trash "$(jq -cn --arg p "$_fn" '{path: $p}')"
}
files_call_play() {   # files_call_play ID TOOL ARGUMENTS -- a video over the box the dialog gives, or a sound with no window
    _fat=$(printf '%s' "$3" | jq -r '.at // 0 | if type == "number" and . >= 0 and . < 86400 then (. * 10 | floor) / 10 else 0 end')
    if [ "$(files_kind "$_ff")" = video ] && command -v mpv >/dev/null 2>&1 && files_video_here; then   # over its frame
        _fbx=$(printf '%s' "$3" | jq -r '[.x, .y, .w, .h] | if all(type == "number" and . >= 0 and . <= 65535) then map(floor | tostring) | join(" ") else "" end')
        [ -n "$_fbx" ] || { provide_refuse "$1" "files: a video plays over its view: the dialog gives the box"; return 0; }
        # shellcheck disable=SC2086   # four numbers, split on purpose
        _fpv=$(files_play_video "$_ff" "$_fat" $_fbx) || { provide_refuse "$1" "files: ${_fpv:-$_fname could not be played here}"; return 0; }
        files_result "$1" "playing $_fname"; return 0
    fi
    [ "$(files_kind "$_ff")" = sound ] && command -v mpv >/dev/null 2>&1 || { provide_refuse "$1" "files: $_fname is no sound mpv plays here"; return 0; }
    files_play "$_ff" "$_fat"; files_result "$1" "playing $_fname"
}
files_call_show() {   # files_call_show ID TOOL ARGUMENTS -- show: the first lines of a text file; attach: the file for spark, when its type plus attaches
    set -- "$1" "$2" "$(files_stat "$_ff" | cut -d' ' -f1)"
    [ "$3" -le "$FILES_SHOW_MAX" ] || { provide_refuse "$1" "files: $_fname is larger than $((FILES_SHOW_MAX / 1024)) kB"; return 0; }
    [ "$(tr -d '\000' < "$_ff" | wc -c | tr -d ' ')" = "$3" ] || { provide_refuse "$1" "files: $_fname is not text"; return 0; }
    if [ "$2" = files_show ]; then
        rpc_result "$1" "$(head -n "$FILES_SHOW_LINES" "$_ff" | scrub_text | jq -Rs --arg n "$_fname" '{receipt: ($n + "\n" + (. | rtrimstr("\n")))} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
    else
        _fx=$(printf '%s' "${_ff##*/}" | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | tr 'A-Z' 'a-z')
        case " $DIALOG_ATTACH_TYPES " in *" ${_fx:-.} "*) ;; *) provide_refuse "$1" "files: $_fname is not a type plus attaches ($DIALOG_ATTACH_TYPES)"; return 0 ;; esac
        rpc_result "$1" "$(jq -cn --arg r "attached $_fname" --arg p "$_ff" '{receipt: $r, attach: $p} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
    fi
}
files_call_put() {   # files_call_put ID TOOL ARGUMENTS -- move or copy into another folder, under the name given or its own; a name there already is refused unless there says keep or replace
    _fd=$(files_ok "$_fto" dir) || { provide_refuse "$1" "files: that is not a folder in the folders given"; return 0; }
    [ "$_fd" != "${_ff%/*}" ] || { provide_refuse "$1" "files: $_fname is in $(files_home "$_fd") already"; return 0; }
    case $_fd in "$_ff"|"$_ff"/*) provide_refuse "$1" "files: a folder does not go inside itself"; return 0 ;; esac
    # the name it takes there: the one given, else its own. One there already is refused unless there says
    # keep (NAME 2.EXT, the first free) or replace (the one there to the trash first)
    _fnn=${_fnm:-${_ff##*/}}; _fth=$(printf '%s' "$3" | jq -r '.there // ""'); _fend=''
    files_name_ok "$_fnn" || { provide_refuse "$1" "files: a name is one plain name: no slash, not hidden, 255 characters at most"; return 0; }
    if [ -e "$_fd/$_fnn" ] || [ -L "$_fd/$_fnn" ]; then
        case $_fth in
            keep) _fnk='file'; [ ! -d "$_ff" ] || _fnk=dir; _fnn=$(files_free "$_fd" "$_fnn" "$_fnk") ;;
            replace) _fone=$(files_ok "$_fd/$_fnn" any) || { provide_refuse "$1" "files: $_fnn there is not a file or a folder: it stays"; return 0; }
                _fo=$(files_trash "$_fone") || { provide_refuse "$1" "files: $_fo"; return 0; }; _fend=', the one there is in the trash' ;;
            *) provide_refuse "$1" "files: $_fnn already exists"; return 0 ;;
        esac
    fi
    _fn=$(files_new_ok "$_fd" "$_fnn") || { provide_refuse "$1" "files: $_fn"; return 0; }
    _fas=''; [ "$_fnn" = "${_ff##*/}" ] || _fas=" as $(printf '%s' "$_fnn" | scrub_text)"   # the receipt names the name it took when that is not its own
    if [ "$2" = files_move ]; then
        mv "$_ff" "$_fn" 2>/dev/null || { files_unreplace; provide_refuse "$1" "files: could not move $_fname"; return 0; }
        _fub=$(jq -cn --arg p "$_fn" --arg t "${_ff%/*}" --arg n "${_ff##*/}" --arg k "$_fnn" '{path: $p, to: $t} + (if $n == $k then {} else {name: $n} end)')   # back, under its old name
        files_result "$1" "$_fname moved to $(files_home "$_fd")$_fas$_fend" files_move "$_fub"
    else
        cp -Rp "$_ff" "$_fn" 2>/dev/null || { rm -rf "$_fn"; files_unreplace; provide_refuse "$1" "files: could not copy $_fname"; return 0; }
        files_result "$1" "$_fname copied to $(files_home "$_fd")$_fas$_fend" files_trash "$(jq -cn --arg p "$_fn" '{path: $p}')"
    fi
}
provide_roots() {   # provide_roots RESULT -- the host's roots kept in PROOTS, each a folder's realpath, never /
    printf '%s' "$1" | jq -r '.roots // [] | .[] | .uri // "" | select(startswith("file://")) | ltrimstr("file://")
        | [match("%[0-9A-Fa-f]{2}|[^%]+|%"; "g").string | if (startswith("%") and length == 3) then ([.[1:] | ascii_downcase | explode | map(if . >= 97 then . - 87 else . - 48 end) | .[0] * 16 + .[1]] | implode) else . end] | add // ""' 2>/dev/null \
        | while IFS= read -r _fr; do _fr=$(realpath "$_fr" 2>/dev/null) && [ "$_fr" != / ] && [ -d "$_fr" ] && printf '%s\n' "$_fr"; done > "$PROOTS.new" || :
    mv "$PROOTS.new" "$PROOTS"
    rpc_note notifications/resources/updated '{"uri":"spark-shell://files/rows"}'   # a read that came before the roots answered with none: the host reads again now
}

