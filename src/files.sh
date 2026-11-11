# shellcheck extended-analysis=false
# --- the files provider
# sets: FILES_DEPTH FILES_FOUND_MAX FILES_MATCH_MAX FILES_NAMES FILES_NAMES_AGE FILES_RECENT_DAYS FILES_RECENT_MAX FILES_ROWS_BYTES FILES_ROWS_MAX FILES_SEARCH_T FILES_SHOW_LINES FILES_SHOW_MAX FILES_SKIP FILES_THUMB_DIR FILES_WALK_T
# reads: NOTES_DIR OS TAB THUMB_DIR TMP US
FILES_SHOW_MAX=1048576   # a file shown or attached: a megabyte at most
FILES_SHOW_LINES=12      # the lines a show puts in the exchange
FILES_RECENT_DAYS=7      # the files touched in the last days, at the top of your home
FILES_RECENT_MAX=8
FILES_FOUND_MAX=200      # a search lists this many at most
FILES_DEPTH=12           # a search and the recent list walk this deep
FILES_SKIP='node_modules target __pycache__ build dist venv Library'   # the folders a walk never enters
FILES_THUMB_DIR=$THUMB_DIR/files   # an old cache, removed when seen
files_roots() {   # -> the roots, one realpath a line: the host's, then every drive mounted
    [ -z "${PROOTS:-}" ] || cat "$PROOTS" 2>/dev/null || :
    files_drives | cut -f2
}
files_drives() {   # -> NAME<tab>MOUNT<tab>FREE per drive mounted now, each its own realpath
    [ "$OS" != Darwin ] && udisks_here || return 0
    storage_list | awk -F '\037' '$1 == "fs" && $5 != "" { print $2 "\t" $5 }' | while IFS="$TAB" read -r _dn _dm; do
        _dm=$(realpath "$_dm" 2>/dev/null) && [ "$_dm" != / ] && [ -d "$_dm" ] && printf '%s\t%s\t%s\n' "$_dn" "$_dm" "$(storage_kb "$(storage_free "$_dm")") free" || :
    done
}
files_home_root() { realpath "$HOME" 2>/dev/null || printf '%s\n' "$HOME"; }   # -> your home as a root names it
files_b64() { printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'; }   # files_b64 PATH -> the folder's part of its uri
files_unb64() {   # files_unb64 PART -> the path, or false
    _fx=$(printf '%s' "$1" | tr -- '-_' '+/'); case $(( ${#_fx} % 4 )) in 2) _fx="$_fx==" ;; 3) _fx="$_fx=" ;; 1) return 1 ;; esac
    printf '%s' "$_fx" | base64 -d 2>/dev/null || printf '%s' "$_fx" | base64 -D 2>/dev/null
}
files_uri() { printf 'spark-shell://files/rows/%s' "$(files_b64 "$1")"; }
files_root_of() {   # files_root_of PATH -> the deepest root PATH sits under, or false
    _fro=''
    while IFS= read -r _fr; do [ -n "$_fr" ] || continue; case $1 in "$_fr"|"$_fr"/*) [ "${#_fr}" -le "${#_fro}" ] || _fro=$_fr ;; esac; done <<ROOTS
$(files_roots)
ROOTS
    [ -n "$_fro" ] || return 1
    printf '%s\n' "$_fro"
}
files_ok() {   # files_ok PATH dir|file|any -> the path when it passes the four checks below, else false
    _fp=$(realpath "$1" 2>/dev/null) || return 1
    [ "$_fp" = "$1" ] || return 1   # resolves to itself
    _froot=$(files_root_of "$_fp") || return 1   # under a root
    case /${_fp#"$_froot"}/ in */.*/*) return 1 ;; esac   # no part of it hidden
    case $2 in dir) [ -d "$_fp" ] && [ ! -L "$_fp" ] ;; file) [ -f "$_fp" ] && [ ! -L "$_fp" ] ;; *) { [ -d "$_fp" ] || [ -f "$_fp" ]; } && [ ! -L "$_fp" ] ;; esac || return 1
    printf '%s\n' "$_fp"
}
files_name_ok() {   # files_name_ok NAME -> 0 for one plain name: not hidden, no slash, no control character, 255 bytes at most
    [ -n "$1" ] && [ "${#1}" -le 255 ] || return 1
    case $1 in .*|*/*) return 1 ;; esac
    [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" = "$1" ] && [ "$(printf '%s' "$1" | wc -c | tr -d ' ')" -le 255 ]
}
files_new_ok() {   # files_new_ok FOLDER NAME -> FOLDER/NAME when a file may be made there, else the reason on stdout
    _fnd=$(files_ok "$1" dir) || { echo "that is not a folder in the folders given"; return 1; }
    files_name_ok "$2" || { echo "a name is one plain name: no slash, not hidden, 255 characters at most"; return 1; }
    [ ! -e "$_fnd/$2" ] && [ ! -L "$_fnd/$2" ] || { echo "$2 already exists"; return 1; }
    printf '%s\n' "$_fnd/$2"
}
files_free() {   # files_free FOLDER NAME dir|file -> NAME 2.EXT, NAME 3.EXT, ... the first not in FOLDER
    _ffs=$2; _ffe=''
    [ "$3" = dir ] || case $2 in *.*) _ffs=${2%.*}; _ffe=.${2##*.} ;; esac
    _ffk=2
    while [ -e "$1/$_ffs $_ffk$_ffe" ] || [ -L "$1/$_ffs $_ffk$_ffe" ]; do _ffk=$((_ffk + 1)); done
    printf '%s\n' "$_ffs $_ffk$_ffe"
}
files_is_root() { files_roots | grep -qxF -- "$1"; }   # files_is_root PATH -> 0 for your home or a drive itself
files_stat() {   # files_stat PATH -> "SIZE EPOCH" (GNU stat, else BSD's)
    stat -c '%s %Y' "$1" 2>/dev/null || stat -f '%z %m' "$1" 2>/dev/null || echo '0 0'
}
files_size() { awk -v n="$1" 'BEGIN { if (n < 1024) printf "%d B", n; else if (n < 1048576) printf "%d KB", n / 1024; else if (n < 1073741824) printf "%.1f MB", n / 1048576; else printf "%.1f GB", n / 1073741824 }'; }   # files_size BYTES -> 14 KB, 2.1 MB
files_when() {   # files_when EPOCH -> today, yesterday, 18 Oct, or the year
    _fd=$(date -d "@$1" +%Y%m%d 2>/dev/null || date -r "$1" +%Y%m%d 2>/dev/null) || { echo ''; return 0; }
    _now=$(date +%s); _today=$(date +%Y%m%d); _yday=$(date -d "@$((_now - 86400))" +%Y%m%d 2>/dev/null || date -r "$((_now - 86400))" +%Y%m%d 2>/dev/null)
    if [ "$_fd" = "$_today" ]; then echo today; elif [ "$_fd" = "$_yday" ]; then echo yesterday
    elif [ "${_fd%????}" = "$(date +%Y)" ]; then date -d "@$1" '+%d %b' 2>/dev/null || date -r "$1" '+%d %b' 2>/dev/null
    else echo "${_fd%????}"; fi
}
files_home() { _tl='~'; _fhr=$(files_home_root); case $1 in "$HOME"|"$_fhr") echo "$_tl" ;; "$HOME"/*) echo "$_tl/${1#"$HOME"/}" ;; "$_fhr"/*) echo "$_tl/${1#"$_fhr"/}" ;; *) echo "$1" ;; esac; }   # files_home PATH -> with ~ for your home
FILES_ROWS_MAX=1000      # a folder lists this many at a time, its last row opening the next
FILES_ROWS_BYTES=400000  # a page's rows stay under the 512 kB of a resource the dialog reads
FILES_WALK_T=4           # the recent list and a folder's item counts walk this many seconds at most
FILES_SEARCH_T=8         # a search walks this many seconds at most
files_num() { awk -v n="$1" 'BEGIN { s = sprintf("%d", n); r = ""; while (length(s) > 3) { r = "," substr(s, length(s) - 2) r; s = substr(s, 1, length(s) - 3) } print s r }'; }   # files_num N -> 12,345
files_low() {   # files_low CMD... -- CMD at a low priority, ionice too where it is
    if command -v ionice >/dev/null 2>&1; then nice -n 10 ionice -c 2 -n 7 "$@"; else nice -n 10 "$@"; fi
}
files_timed() {   # files_timed SECONDS CMD... -- CMD at a low priority, stopped after SECONDS where timeout is; $TMP/walk.stopped says it was
    _ftt=$1; shift
    if command -v timeout >/dev/null 2>&1; then files_low timeout "$_ftt" "$@" || { [ $? != 124 ] || : > "$TMP/walk.stopped"; }
    else files_low "$@" || :; fi
}
files_nul() { tr '\n\000' '\001\n' | grep -v "$(printf '\001')" | tr '\n' '\000' || :; }   # NUL-separated paths -> the same, a name with a line feed left out
files_stats() {   # NUL-separated paths on stdin -> TYPE US SIZE US EPOCH US DATE US LINK US PATH a line (GNU stat, else BSD's)
    if stat --version >/dev/null 2>&1; then QUOTING_STYLE=literal xargs -0 stat --printf='%F\037%s\037%Y\037%y\037%N\037%n\n' 2>/dev/null || :
    else xargs -0 stat -f "%HT$US%z$US%m$US%Sm$US%Y$US%N" -t '%Y-%m-%d %H:%M' 2>/dev/null || :; fi
}
files_counts() {   # files_counts [FOLDER] -> PATH US COUNT a line, for each folder in FOLDER or each named on stdin NUL-separated
    if [ -n "${1:-}" ]; then files_timed "$FILES_WALK_T" find "$1" -mindepth 2 -maxdepth 2 ! -name '.*' -print0 2>/dev/null
    else xargs -0 sh -c 'exec find "$@" -mindepth 1 -maxdepth 1 ! -name ".*" -print0' sh 2>/dev/null || :; fi \
        | files_nul | tr '\000' '\n' | awk -v us="$US" '{ sub(/\/[^\/]*$/, ""); n[$0]++ } END { for (d in n) print d us n[d] }'
}
files_rows_fmt() {   # files_rows_fmt GROUP FOLDERS [COUNTS] < files_stats' lines -> KEY US ID US SIGN US TEXT US CHILDREN US PATH US SIZE US DATE US GROUP US COLUMN3 US KIND US PREVIEW US KIND-WORD US DATE-AND-TIME a row (KEY 1 file, 0 folder, 2 link); FOLDERS yes fills COLUMN3; $TMP/files.sum "FILES FOLDERS BYTES"
    _frs=''; [ ! -e "$TMP/walk.stopped" ] || _frs=1
    LC_ALL=C awk -F "$US" -v us="$US" -v group="$1" -v folders="$2" -v counts="${3:-}" -v cstop="$_frs" -v home="$(files_home_root)" \
        -v today="$(date +%Y%m%d)" -v yday="$(date -d "@$(( $(date +%s) - 86400 ))" +%Y%m%d 2>/dev/null || date -r "$(( $(date +%s) - 86400 ))" +%Y%m%d)" \
        -v year="$(date +%Y)" -v sum="$TMP/files.sum" -v links="$TMP/files.links" '
        function b64(s,   r, i, n, t) {   # base64url, no padding: files_b64
            r = ""; n = length(s)
            for (i = 1; i <= n; i += 3) {
                t = ord[substr(s, i, 1)] * 65536 + (i + 1 <= n ? ord[substr(s, i + 1, 1)] * 256 : 0) + (i + 2 <= n ? ord[substr(s, i + 2, 1)] : 0)
                r = r substr(B, int(t / 262144) + 1, 1) substr(B, int(t / 4096) % 64 + 1, 1)
                if (i + 1 <= n) r = r substr(B, int(t / 64) % 64 + 1, 1)
                if (i + 2 <= n) r = r substr(B, t % 64 + 1, 1)
            }
            return r
        }
        function clean(s) { gsub(/[\001-\037\177]|\302[\200-\237]|\342\200[\213-\217\250-\256]|\342\201[\240\246-\251]|\357\273\277/, "", s); return s }   # SCRUB_JQ, on bytes
        function size(n) { if (n < 1024) return sprintf("%d B", n); if (n < 1048576) return sprintf("%d KB", n / 1024); if (n < 1073741824) return sprintf("%.1f MB", n / 1048576); return sprintf("%.1f GB", n / 1073741824) }
        function when(d) { if (d == today) return "today"; if (d == yday) return "yesterday"; if (substr(d, 1, 4) == year) return substr(d, 7, 2) " " mon[substr(d, 5, 2) + 0]; return substr(d, 1, 4) }
        function stamp(s,   d) { d = substr(s, 1, 4) substr(s, 6, 2) substr(s, 9, 2); if (substr(d, 1, 4) != year) return substr(d, 7, 2) " " mon[substr(d, 5, 2) + 0] " " substr(d, 1, 4); return when(d) " " substr(s, 12, 5) }   # a wide list: the date with the time, the year in place of the time for another year
        function kindof(n,   e) {   # what a file is, by its type: a word a person says, never a MIME type
            e = tolower(n); if (e !~ /\.[^.\/]+$/) return "file"; sub(/.*\./, "", e)
            if (e ~ /^(jpe?g|png|gif|webp|bmp|tiff?|svg|heic|heif|avif)$/) return "picture"
            if (e ~ /^(mp3|flac|wav|ogg|oga|opus|m4a|aac|aiff?|wma)$/) return "sound"
            if (e ~ /^(mp4|m4v|mkv|webm|mov|avi|wmv|ogv)$/) return "video"
            if (e == "pdf") return "PDF"; if (e ~ /^docx?$/) return "Word"; if (e ~ /^xlsx?$/) return "Excel"; if (e ~ /^pptx?$/) return "PowerPoint"
            if (e ~ /^(odt|rtf)$/) return "document"; if (e == "ods") return "spreadsheet"; if (e == "odp") return "slides"; if (e == "csv") return "CSV"
            if (e ~ /^(md|markdown)$/) return "Markdown"; if (e ~ /^(txt|log)$/) return "text"; if (e ~ /^(json|ya?ml|toml|xml|ini|conf)$/) return "data"
            if (e ~ /^(sh|py|rs|js|ts|c|h|cc|cpp|go|rb|java|lua|pl|html?|css)$/) return "code"
            if (e ~ /^(zip|tar|gz|tgz|xz|bz2|zst|7z|rar)$/) return "archive"; if (e ~ /^(iso|img|dmg)$/) return "disk image"
            return toupper(e)
        }
        BEGIN {
            B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"; for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
            split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", mon, " ")
            if (counts != "") while ((getline l < counts) > 0) { k = index(l, us); if (k) cnt[substr(l, 1, k - 1)] = substr(l, k + 1) }
            while ((getline l < links) > 0) { k = index(l, us); if (k) to[substr(l, 1, k - 1)] = substr(l, k + 1) }   # a link and where it points (readlink: stat quotes its %N its own way)
        }
        {
            p = substr($0, length($1 $2 $3 $4 $5) + 6)   # the path, whole: the last field, whatever it holds
            if (p == "" || p ~ /[\001-\037\177]/) next   # a name with a control character in it is not listed
            t = tolower($1); name = p; sub(/.*\//, "", name); id = b64(p); text = clean(name); c3 = ""
            if (folders == "yes") { d = p; sub(/\/[^\/]*$/, "", d); if (d == home) c3 = "~"; else { c3 = d; sub(/.*\//, "", c3); c3 = clean(c3) } }
            if (t ~ /^dir/) {
                nd++; c = (p in cnt) ? cnt[p] : (counts != "" && !cstop ? 0 : "")
                print "0" us "files:dir:" id us "opens" us text us "spark-shell://files/rows/" id us p us (c == "" ? "" : c " " (c == 1 ? "item" : "items")) us "" us group us c3 us "dir" us "" us "folder" us ""
            } else if (t ~ /^regular/) {
                nf++; nb += $2
                print "1" us "files:file:" id us "blank" us text us "" us p us size($2) us when(substr($4, 1, 4) substr($4, 6, 2) substr($4, 9, 2)) us group us c3 us "file" us "" us kindof(name) us stamp($4)
            } else if (t ~ /^symbolic/) {
                print "2" us "files:link:" id us "blank" us text " -> " clean(to[p]) us "" us "" us "" us "" us group us "" us "link" us ""
            }   # a device, a socket, a pipe: not listed
        }
        END { printf "%d %d %.0f\n", nf, nd, nb > sum }'
}
files_slice() {   # files_slice FROM < row lines -> the page's rows from FROM: FILES_ROWS_MAX at most and about FILES_ROWS_BYTES of JSON; $TMP/files.left "NEXT LEFT"
    awk -F "$US" -v from="$1" -v max="$FILES_ROWS_MAX" -v bytes="$FILES_ROWS_BYTES" -v left="$TMP/files.left" '
        NR <= from { next }
        !stop { b += length($0) + ($10 == "file" ? length($1) + 150 : 120); if (k > 0 && (k >= max || b > bytes)) { stop = 1; at = NR - 1 } }   # its JSON, near enough (a file repeats its id in its page); a page holds one row at least
        stop { rest++; next }
        { k++; print }
        END { printf "%d %d\n", (stop ? at : NR), rest > left }'
}
files_list() {   # files_list FOLDER [GROUP] [FROM] -> a page of the folder's rows from FROM, folders then files by name; FILES_N, FILES_D, FILES_B count the whole folder, FILES_NEXT and FILES_LEFT the rest
    rm -f "$TMP/walk.stopped"
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -print0 2>/dev/null | files_nul | files_stats > "$TMP/files.stats"
    awk -F "$US" 'tolower($1) ~ /^symbolic/ { print substr($0, length($1 $2 $3 $4 $5) + 6) }' "$TMP/files.stats" \
        | while IFS= read -r _fll; do printf '%s%s%s\n' "$_fll" "$US" "$(readlink "$_fll")"; done > "$TMP/files.links"   # a folder's links are few
    files_counts "$1" > "$TMP/files.counts"
    files_rows_fmt "${2:-}" no "$TMP/files.counts" < "$TMP/files.stats" | sort -t "$US" -k1,1 -k4,4 | cut -d "$US" -f2- | files_slice "${3:-0}"
    read -r FILES_N FILES_D FILES_B < "$TMP/files.sum"; read -r FILES_NEXT FILES_LEFT < "$TMP/files.left"
}
files_walk() {   # files_walk ROOT f|fd [FIND-TESTS...] -> the files (f) or files and folders (fd) under ROOT, FILES_DEPTH deep, FILES_WALK_LIMIT (else FILES_WALK_T) seconds at most
    _fwr=$1; _fwk=$2; shift 2
    if [ "$_fwk" = f ]; then set -- -type f "$@" -print; else set -- '(' -type f -o -type d ')' "$@" -print; fi
    set -- ')' ')' -prune -o ! -name '.*' ! -type l "$@"
    for _fws in $FILES_SKIP; do set -- -o -name "$_fws" "$@"; done
    set -- "$_fwr" -mindepth 1 -maxdepth "$FILES_DEPTH" '(' -type d '(' -name '.*' "$@"
    files_timed "${FILES_WALK_LIMIT:-$FILES_WALK_T}" find "$@"
}
files_recent() {   # -> the files under your home touched in the last FILES_RECENT_DAYS days, the newest first, FILES_RECENT_MAX at most
    rm -f "$TMP/walk.stopped"
    files_walk "$(files_home_root)" f -mtime "-$FILES_RECENT_DAYS" 2>/dev/null | tr '\n' '\000' | files_stats | sort -t "$US" -k3,3nr | head -n "$FILES_RECENT_MAX" > "$TMP/files.rstats"
    files_rows_fmt recent yes < "$TMP/files.rstats" | cut -d "$US" -f2- | files_slice 0
}
# the search from Home ranks a cached list of the names under your home,
# walked again in the background once FILES_NAMES_AGE minutes old
FILES_NAMES=${XDG_CACHE_HOME:-$HOME/.cache}/spark-shell/files.names
FILES_NAMES_AGE=10
FILES_MATCH_MAX=60       # a search from Home ranks this many names at most
files_names_build() {   # -> FILES_NAMES walked anew, a path a line
    mkdir_private "${FILES_NAMES%/*}" || return 1
    lock_take "$FILES_NAMES.lock" || return 0   # one walk at a time
    _fnt=$(mktemp "$FILES_NAMES.XXXXXX") || { lock_drop "$FILES_NAMES.lock"; return 1; }
    FILES_WALK_LIMIT=$FILES_SEARCH_T; files_walk "$(files_home_root)" fd > "$_fnt" 2>/dev/null || :; unset FILES_WALK_LIMIT
    mv "$_fnt" "$FILES_NAMES" || rm -f "$_fnt"
    lock_drop "$FILES_NAMES.lock"
}
files_match() {   # files_match WORDS -> the paths under your home whose name holds every word, FILES_MATCH_MAX at most, scored: the name's start 4, a word's start 3, inside 2, one edit off 1
    [ -z "$(find "$FILES_NAMES.lock" -mmin +2 2>/dev/null)" ] || lock_drop "$FILES_NAMES.lock"   # a walk that died left its lock
    if [ ! -s "$FILES_NAMES" ]; then files_names_build
    elif [ -z "$(find "$FILES_NAMES" -mmin "-$FILES_NAMES_AGE" 2>/dev/null)" ]; then ( files_names_build ) >/dev/null 2>&1 </dev/null 3>&- 4<&- 5>&- & fi
    [ -s "$FILES_NAMES" ] || return 0
    _fmn=$(realpath "$NOTES_DIR" 2>/dev/null || printf '%s' "$NOTES_DIR")   # the notes folder is left to notes
    W=$1 N=$_fmn/ awk -v max="$FILES_MATCH_MAX" '
        function near(a, b,   la, lb, i, d, j, t) {   # one edit apart at most
            la = length(a); lb = length(b)
            if (la == lb) {
                d = 0; for (i = 1; i <= la; i++) if (substr(a, i, 1) != substr(b, i, 1)) { if (!d) j = i; d++ }
                return d <= 1 || (d == 2 && substr(a, j, 1) == substr(b, j + 1, 1) && substr(a, j + 1, 1) == substr(b, j, 1))
            }
            if (la - lb != 1 && lb - la != 1) return 0
            if (la < lb) { t = a; a = b; b = t; lb = la }
            for (i = 1; i <= lb && substr(a, i, 1) == substr(b, i, 1); i++) ;
            return substr(a, i + 1) == substr(b, i)
        }
        function one(w, n,   k, p, i, c, lw, f) {
            if (index(n, w) == 1) return 4
            k = split(n, p, /[^a-z0-9]+/)
            for (i = 1; i <= k; i++) if (p[i] != "" && index(p[i], w) == 1) return 3
            if (index(n, w)) return 2
            lw = length(w); if (lw < 4) return 0
            for (i = 1; i <= k; i++) {
                c = p[i]; if (c == "") continue
                f = substr(c, 1, 1) == substr(w, 1, 1) || (substr(c, 1, 1) == substr(w, 2, 1) && substr(c, 2, 1) == substr(w, 1, 1))
                if (f && (near(w, substr(c, 1, lw)) || near(w, substr(c, 1, lw + 1)) || near(w, substr(c, 1, lw - 1)) || near(w, c))) return 1
            }
            return 0
        }
        BEGIN { nw = split(tolower(ENVIRON["W"]), ws, /[ \t]+/) }
        index($0, ENVIRON["N"]) == 1 { next }
        { n = $0; sub(/.*\//, "", n); n = tolower(n); t = 0
          for (i = 1; i <= nw; i++) { if (ws[i] == "") continue; s = one(ws[i], n); if (!s) next; t += s }
          if (t) printf "%d\t%d\t%s\n", t, length(n), $0 }' "$FILES_NAMES" | sort -t "$TAB" -k1,1nr -k2,2n | head -n "$FILES_MATCH_MAX" | cut -f3-
}
files_search() {   # files_search find|say|match WORDS -> the rows of a search over every root: find by name, say by contents, match scored; FILES_FOUND_MAX and FILES_SEARCH_T seconds at most
    _fsw=$(printf '%s' "$2" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'); [ -n "$_fsw" ] && [ "${#_fsw}" -le 256 ] || return 1
    [ "$(printf '%s' "$_fsw" | tr -d '\000-\037\177')" = "$_fsw" ] || return 1
    : > "$TMP/files.found"; rm -f "$TMP/walk.stopped"; FILES_WALK_LIMIT=$FILES_SEARCH_T
    files_roots | while IFS= read -r _fsr; do
        [ -n "$_fsr" ] || continue
        if [ "$1" = match ]; then [ "$_fsr" != "$(files_home_root)" ] || files_match "$_fsw"
        elif [ "$1" = find ]; then
            _fs1=${_fsw%% *}
            files_walk "$_fsr" fd -iname "*$(printf '%s' "$_fs1" | sed 's/[][*?\\]/\\&/g')*" 2>/dev/null | while IFS= read -r _fsf; do
                _fsn=$(printf '%s' "${_fsf##*/}" | tr 'A-Z' 'a-z'); _fsk=1
                for _fsq in $_fsw; do case $_fsn in *"$(printf '%s' "$_fsq" | tr 'A-Z' 'a-z')"*) ;; *) _fsk='' ;; esac; done
                [ -z "$_fsk" ] || printf '%s\n' "$_fsf"
            done
        else
            files_walk "$_fsr" f -size -1024k 2>/dev/null | tr '\n' '\000' | files_low xargs -0 grep -lisFI -- "$_fsw" 2>/dev/null || :
        fi
    done | sort | head -n "$FILES_FOUND_MAX" > "$TMP/files.found"
    unset FILES_WALK_LIMIT
    while IFS= read -r _fsf; do files_ok "$_fsf" any || :; done < "$TMP/files.found" | tr '\n' '\000' | files_stats > "$TMP/files.stats"
    awk -F "$US" 'tolower($1) ~ /^dir/ { print substr($0, length($1 $2 $3 $4 $5) + 6) }' "$TMP/files.stats" | tr '\n' '\000' | files_counts > "$TMP/files.counts"
    files_rows_fmt '' yes "$TMP/files.counts" < "$TMP/files.stats" | sort -t "$US" -k1,1 -k4,4 -k6,6 | cut -d "$US" -f2- | files_slice 0   # by kind, name, then path: two of one name in a fixed order
    read -r _fsn _fsd _fsb < "$TMP/files.sum"
    if [ $((_fsn + _fsd)) -eq 0 ] && [ ! -e "$TMP/walk.stopped" ]; then printf 'files:total\037blank\037%s\037\037\037\037\037\037\037total\037\n' "nothing found"
    elif [ -e "$TMP/walk.stopped" ]; then printf 'files:total\037blank\037%s\037\037\037\037\037\037\037total\037\n' "the search stopped at $FILES_SEARCH_T seconds: $((_fsn + _fsd)) found"; fi
}
