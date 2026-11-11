# shellcheck extended-analysis=false
# --- the files provider
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
FILES_TEXT_MAX=131072    # a text's preview at most; past it the preview says where it ends
FILES_PAGE_PX=1600       # a preview's picture, its long side at most, in pixels
FILES_FULL_PX=4096       # the same for a zoom; the dialog decodes 4096 a side at most
FILES_TOOL_T=10          # a tool a preview runs on a file, at most this many seconds: a file is untrusted
FILES_SOUND_T=300        # a sound's waveform drawn aside, at most this many seconds
# a preview's kinds: a line each, the kind, then its extensions
FILES_KINDS='markdown md markdown
json json
code sh bash zsh fish py rb pl lua js mjs cjs ts tsx jsx c h cc cpp hpp cs java kt go rs swift sql html htm css scss xml yaml yml toml ini cfg conf env diff patch
text txt text log csv tsv jsonl ndjson rst org tex srt vtt
picture png jpg jpeg webp gif svg bmp tif tiff
pdf pdf
sound mp3 wav flac ogg oga opus m4a aac aif aiff aifc ac3 eac3 dts caf mka wv
video mp4 m4v mov webm mkv avi mpg mpeg mts m2ts wmv ogv mxf 3gp
office docx pptx xlsx odt odp ods'
FILES_WAVE_PX=160        # a sound's waveform, its height in pixels over the spectrogram (512)
MPV_SAFE='--no-config --no-ytdl --load-scripts=no --demuxer-lavf-o=protocol_whitelist=file'   # mpv on a file: no config of its own, no scripts, no network
files_kind() {   # files_kind PATH -> its kind (FILES_KINDS); text for another type file calls text; else other
    _fke=$(printf '%s' "${1##*/}" | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | tr 'A-Z' 'a-z')
    _fkk=$(printf '%s\n' "$FILES_KINDS" | awk -v e="$_fke" 'e != "" { for (i = 2; i <= NF; i++) if ($i == e) { print $1; exit } }')
    if [ -n "$_fkk" ]; then echo "$_fkk"
    elif command -v file >/dev/null 2>&1 && file -b --mime-type -- "$1" 2>/dev/null | grep -q '^text/'; then echo text
    else echo other; fi
}
files_tool() {   # files_tool CMD... -- CMD, stopped after FILES_TOOL_T seconds where timeout is; at an idle priority under FILES_IDLE
    if [ -n "${FILES_IDLE:-}" ]; then set -- nice -n 19 "$@"; ! command -v ionice >/dev/null 2>&1 || set -- ionice -c 3 "$@"; fi
    if command -v timeout >/dev/null 2>&1; then timeout "$FILES_TOOL_T" "$@"; else "$@"; fi
}
files_say() { jq -cn --arg s "$1" '{say: $s}' > "$TMP/page.json"; }   # files_say WORDS -- page.json: no preview, and why
provide_page() {   # provide_page SECTION ROW-ID -> the page of one row; false when no row is that one now
    case $1:$2 in
        apps:'apps:open '?*) app_page "${2#apps:open }" ;;
        notes:'notes:open '?*)
            _ppn=${2#notes:open }; case $_ppn in */*|.*) return 1 ;; esac
            _ppd=$(realpath "$NOTES_DIR" 2>/dev/null) || return 1
            _ppr=${PROOTS:-}; files_home_root > "$TMP/notes.roots"; PROOTS=$TMP/notes.roots   # a note shown as a file under your home
            files_page "$_ppd/$_ppn" 1 ''; _ppc=$?; PROOTS=$_ppr; return "$_ppc" ;;
        reminders:reminders:*) rem_page "$(printf '%s' "$2" | sed -n 's/.*:[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]://p')" ;;   # the uid follows the row's date
        window:'window:focus '?*) win_page "${2#window:focus }" ;;
        layout:'layout:open '?*) layout_page "${2#layout:open }" ;;
        wifi:wifi:*) wifi_page "$2" ;;
        bt:'bt:'*' '?*) bt_page "${2#bt:* }" ;;
        storage:'storage:'*' '?*) storage_page "${2#storage:* }" ;;
        tools:tools:package:?*) tools_package_page "${2#tools:package:}" ;;
        tools:tools:program:?*) tools_program_page "${2#tools:program:}" ;;
        tools:tools:space:caches) tools_space_view caches ;;
        tools:tools:folder:?*) tools_space_view "folder:${2#tools:folder:}" ;;
        about:about:license) scrub_text < "$REPO/LICENSE" | jq -Rn '{title: "license", lines: [inputs], bold: []}' ;;   # as they are, read only
        about:about:credits) scrub_text < "$REPO/CREDITS.md" | jq -Rn '[inputs] as $l | {title: "credits", lines: ($l | map(sub("^#+ *"; ""))), bold: [range($l | length) | select($l[.] | startswith("#"))]}' ;;
        *) return 1 ;;
    esac
}
page_of() {   # page_of TITLE WHAT -- stdin LABEL<tab>VALUE lines -> a page, the labels in one column
    scrub_text | awk -F '\t' '$2 != "" { n++; l[n] = $1; v[n] = $2; if (length($1) > w) w = length($1) } END { for (i = 1; i <= n; i++) printf "%-" (w + 3) "s%s\n", l[i], v[i] }' > "$TMP/page.pairs"
    jq -n --arg t "$(printf '%s' "$1" | scrub_text)" --arg w "$(printf '%s' "$2" | scrub_text)" --rawfile p "$TMP/page.pairs" \
        '{title: $t, lines: ([$t] + (if $w == "" or $w == $t then [] else [$w] end) + [""] + ($p | split("\n") | map(select(. != "")))), bold: [0]}'
}
app_page() {   # app_page NAME -> an app's page
    sbom_entries
    _apl=$(awk -F '\t' -v n="$1" '$1 == n { print; exit }' "$TMP/entries")
    if [ -z "$_apl" ]; then   # one of your allowed commands, with no desktop entry
        command -v "$1" >/dev/null 2>&1 || return 1
        printf 'runs in\ta terminal\ncommand\t%s\n' "$1" | page_of "$1" "a command on this computer"; return
    fi
    _apf=$(printf '%s' "$_apl" | cut -f2); _apw=$(printf '%s' "$_apl" | cut -f3); _apx=$(printf '%s' "$_apl" | cut -f6 | sed 's/ *%[a-zA-Z]//g')   # the command as typed: no field codes
    _apn=$(sed -n 's/^Name=//p' "$_apf" | head -1); [ -n "$_apn" ] || _apn=$1
    case $_apf in */flatpak/*) _api='as a Flatpak' ;; */snapd/*) _api='as a Snap' ;; "${XDG_DATA_HOME:-$HOME/.local/share}"/*) _api='in your own apps folder' ;; /usr/local/*) _api='by hand, in /usr/local' ;; *) _api="with the system's packages" ;; esac
    _apr='its own window'; [ "$(printf '%s' "$_apl" | cut -f4)" != yes ] || _apr='a terminal'
    printf 'group\t%s\nruns in\t%s\ncommand\t%s\ninstalled\t%s\n' "$(app_group "$(printf '%s' "$_apl" | cut -f5)")" "$_apr" "$_apx" "$_api" | page_of "$_apn" "$_apw"
}
rem_page() {   # rem_page UID -> a reminder's page
    [ -n "$1" ] || return 1
    _rpl=$(rem_list | awk -F '\t' -v u="$1" '$2 == u { print; exit }'); [ -n "$_rpl" ] || return 1
    _rps=$(printf '%s' "$_rpl" | cut -f1); _rpf=$(printf '%s' "$_rpl" | cut -f4)
    if rem_ours "$_rpl"; then _rpc='spark-shell'; else _rpc=${_rpf%/*}; _rpc=${_rpc##*/}; fi
    _rpw=$(rem_said "$_rps"); [ "$(rem_group "$_rps" "$(date +%Y%m%d%H%M)")" != due ] || _rpw="$_rpw, due now"
    printf 'when\t%s\ncalendar\t%s\n' "$_rpw" "$_rpc" | page_of "$(printf '%s' "$_rpl" | cut -f3)" 'a reminder'
}
win_page() {   # win_page ID -> an open window's page
    case $1 in ''|*[!0-9]*) return 1 ;; esac
    swaymsg -t get_tree 2>/dev/null | jq -r --argjson i "$1" --arg aside "$(win_aside)" '
        [.nodes[] | select(.type == "output") as $o | $o.nodes[] | select(.type == "workspace") as $w | $w | .. | objects | select(.id? == $i and (.type == "con" or .type == "floating_con")) | {o: $o.name, w: $w.name, n: .}] | .[0] // empty
        | (.n.app_id // .n.window_properties.class // "a window"), (.n.name // ""),
          "workspace\t" + (.w | split(":") | .[0] + (if (.[1] // "") != "" and .[1] != .[0] then " " + .[1] else "" end)), "screen\t" + .o, "size\t" + (.n.rect.width | tostring) + " by " + (.n.rect.height | tostring) + " pixels",
          "placed\t" + (if .n.fullscreen_mode == 1 or (.n.id | tostring) == $aside then "full screen" elif .n.type == "floating_con" then "floating" else "tiled" end)' > "$TMP/win.page" 2>/dev/null
    [ -s "$TMP/win.page" ] || return 1
    sed -n '3,$p' "$TMP/win.page" | page_of "$(sed -n 1p "$TMP/win.page")" "$(sed -n 2p "$TMP/win.page")"
}
layout_page() {   # layout_page NAME -> a layout's page
    _lpf=$(desk_kept_file "$1") || return 1
    desk_json_ok "$_lpf" || return 1
    jq -r '"in front\t" + .main.app + (if .main.fullscreen == true then ", full screen" elif (.main.width | type) == "number" then ", " + (.main.width | tostring) + "% wide" else "" end),
        (if ((.side // []) | length) > 0 then "beside\t" + ([.side[] | .app // empty] | join(", ")) else empty end),
        (if (.main.screen // "") != "" then "screen\t" + .main.screen else empty end)' "$_lpf" 2>/dev/null | page_of "$(desk_label "$_lpf")" "$(desk_why "$_lpf")"
}
wifi_page() {   # wifi_page ROW-ID -> a network's page
    case $1 in wifi:disconnect) _wpn=$(wifi_connected); _wpu=yes ;; 'wifi:connect '?*) _wpn=${1#wifi:connect }; _wpu='' ;; 'wifi:saved '?*) _wpn=${1#wifi:saved }; _wpu='' ;; *) return 1 ;; esac
    [ -n "$_wpn" ] || return 1
    _wps=$(wifi_scan | awk -F '\t' -v n="$_wpn" '$1 == n { print; exit }')
    _wpk=no; ! wifi_known | cut -f2 | grep -qxF -- "$_wpn" || _wpk=yes
    _wpa=''; [ -z "$_wpu" ] || ! command -v ip >/dev/null 2>&1 || _wpa=$(ip -4 -o addr show dev "$(wifi_if)" 2>/dev/null | awk '{ print $4; exit }')
    {   [ -z "$_wpu" ] || printf 'in use\tyes\n'
        if [ -n "$_wps" ]; then
            printf 'signal\t%s%%\n' "$(printf '%s' "$_wps" | cut -f2)"
            if [ "$(printf '%s' "$_wps" | cut -f3)" = 1 ]; then printf 'security\ta password\n'; else printf 'security\topen, no password\n'; fi
        elif [ -z "$_wpu" ]; then printf 'signal\tnot around now\n'; fi
        printf 'saved\t%s\naddress\t%s\n' "$_wpk" "$_wpa"
    } | page_of "$_wpn" 'a Wi-Fi network'
}
bt_page() {   # bt_page NAME -> a device's page
    _bpl=$(bt_list | awk -F '\t' -v n="$1" '$2 == n { print; exit }'); [ -n "$_bpl" ] || return 1
    _bpm=$(printf '%s' "$_bpl" | cut -f1)
    _bpb=''; ! command -v timeout >/dev/null 2>&1 || _bpb=$(timeout 3 bluetoothctl info "$_bpm" 2>/dev/null | sed -n 's/.*Battery Percentage: *0x[0-9a-fA-F]* *(\([0-9]*\)).*/\1/p' | head -1)
    _bpc=no; [ "$(printf '%s' "$_bpl" | cut -f4)" != 1 ] || _bpc=yes
    _bpp=no; [ "$(printf '%s' "$_bpl" | cut -f3)" != 1 ] || _bpp=yes
    printf 'connected\t%s\npaired\t%s\nbattery\t%s\naddress\t%s\n' "$_bpc" "$_bpp" "${_bpb:+$_bpb%}" "$_bpm" | page_of "$1" 'a Bluetooth device'
}
storage_page() {   # storage_page NAME -> a drive's page
    storage_list > "$TMP/storage.p"
    _spl=$(awk -F "$US" -v n="$1" '$1 == "fs" && $2 == n { print; exit }' "$TMP/storage.p"); [ -n "$_spl" ] || return 1
    _spm=$(printf '%s' "$_spl" | cut -d "$US" -f5)
    _spf=''; [ -z "$_spm" ] || _spf=$(storage_kb "$(storage_free "$_spm")")
    _spo='not mounted'; [ -z "$_spm" ] || _spo=$(files_home "$_spm")
    printf 'drive\t%s\nsize\t%s\nfree\t%s\nmounted at\t%s\nformat\t%s\n' "$(printf '%s' "$_spl" | cut -d "$US" -f6)" "$(files_size "$(printf '%s' "$_spl" | cut -d "$US" -f4)")" "$_spf" "$_spo" "$(printf '%s' "$_spl" | cut -d "$US" -f7)" | page_of "$1" 'a drive'
}
files_folder_page() {   # files_folder_page PATH -> a folder's page: its counts and its newest things
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -type d 2>/dev/null | wc -l | tr -d ' ' > "$TMP/fold.d"
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' ! -type d 2>/dev/null | wc -l | tr -d ' ' > "$TMP/fold.f"
    read -r _fpd < "$TMP/fold.d"; read -r _fpf < "$TMP/fold.f"
    _fph=''; [ "$_fpd" -eq 0 ] || { _fph="$(files_num "$_fpd") folder"; [ "$_fpd" = 1 ] || _fph="${_fph}s"; }
    [ "$_fpf" -eq 0 ] || { _fpx="$(files_num "$_fpf") file"; [ "$_fpf" = 1 ] || _fpx="${_fpx}s"; _fph="${_fph:+$_fph, }$_fpx"; }
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -print0 2>/dev/null | files_nul | files_stats | sort -t "$US" -k3,3nr | head -n 8 \
        | awk -F "$US" '{ p = substr($0, length($1 $2 $3 $4 $5) + 6); sub(/.*\//, "", p); print p }' | scrub_text > "$TMP/fold.new"
    jq -n --arg t "$(printf '%s' "${1##*/}" | scrub_text)" --arg h "${_fph:-empty}" --arg w "$(files_home "$1" | scrub_text)" --rawfile n "$TMP/fold.new" '
        ($n | split("\n") | map(select(. != ""))) as $new
        | {title: $t, lines: ([$t, $h] + (if ($new | length) > 0 then ["", "newest"] + ($new | map("   " + .)) else [] end)), bold: [0, 3], facts: [$w]}'
}
files_page() {   # files_page PATH PAGE [full] -> the preview's page of PATH (full: drawn larger, for a zoom); false when files_ok refuses it
    if _fp=$(files_ok "$1" dir); then files_folder_page "$_fp"; return; fi   # a folder: what it holds
    _fp=$(files_ok "$1" file) || return 1
    _fpg=${2:-1}; case $_fpg in ''|*[!0-9]*) _fpg=1 ;; esac; [ "$_fpg" -ge 1 ] || _fpg=1
    _fpx=$FILES_PAGE_PX; [ "${3:-}" != full ] || _fpx=$FILES_FULL_PX
    # shellcheck disable=SC2046   # two numbers, split on purpose
    set -- "$_fp" "$_fpg" $(files_stat "$_fp")
    mkdir -p "$TMP/pages" || return 1
    _fpb=$TMP/pages/$(printf '%s %s' "$1" "$4" | cksum | cut -d' ' -f1)   # this file at this time: its pages and its text, gone with the provider
    : > "$TMP/page.lead"; : > "$TMP/page.json"
    case $(files_kind "$1") in
        markdown) files_page_text "$1" markdown "$3" "$_fpb" ;;
        json) files_page_text "$1" json "$3" "$_fpb" ;;
        code) files_page_text "$1" code "$3" "$_fpb" ;;
        text) files_page_text "$1" text "$3" "$_fpb" ;;
        picture) files_page_picture "$1" "$_fpb-$_fpx" "$_fpx" ;;
        pdf) files_page_pdf "$1" "$2" "$_fpb-$_fpx" "$_fpx" ;;
        sound) files_page_media "$1" sound "$_fpb" ;;
        video) files_page_media "$1" video "$_fpb-$_fpx" "$_fpx" ;;
        office) files_page_office "$1" "$_fpb" ;;
        *) file -b -- "$1" 2>/dev/null | cut -d, -f1 | scrub_text | cut -c1-40 >> "$TMP/page.lead"
           files_say "this kind of file cannot be viewed: Enter opens it" ;;
    esac
    printf '%s\n%s\n' "$(files_size "$3")" "$(files_when "$4")" >> "$TMP/page.lead"
    jq -n --arg t "$(printf '%s' "${1##*/}" | scrub_text)" --rawfile f "$TMP/page.lead" --slurpfile k "$TMP/page.json" \
        '{title: $t, facts: ($f | split("\n") | map(select(. != "")))} + ($k[0] // {})'
}
files_page_text() {   # files_page_text PATH KIND SIZE BASE -- page.json: the text's lines; BASE.txt for spark
    head -c "$FILES_TEXT_MAX" "$1" > "$TMP/page.raw" 2>/dev/null || :
    [ "$(LC_ALL=C tr -d '\000' < "$TMP/page.raw" | wc -c | tr -d ' ')" = "$(wc -c < "$TMP/page.raw" | tr -d ' ')" ] || { files_say "cannot view: this file is not text, Enter opens it"; return 0; }
    if [ "$2" = json ] && [ "$3" -le "$FILES_TEXT_MAX" ] && jq . "$1" > "$TMP/page.pretty" 2>/dev/null; then mv "$TMP/page.pretty" "$TMP/page.raw"; fi
    cp "$TMP/page.raw" "$4.txt"
    expand -t 4 < "$TMP/page.raw" > "$TMP/page.txt" 2>/dev/null || cp "$TMP/page.raw" "$TMP/page.txt"
    [ "$3" -le "$FILES_TEXT_MAX" ] || printf '\n\nthe view ends here, at %s of %s: Enter opens the whole file\n' "$(files_size "$FILES_TEXT_MAX")" "$(files_size "$3")" >> "$TMP/page.txt"
    jq -Rn --arg k "$2" --arg a "$4.txt" '[inputs] as $l
        | (if $k == "markdown" then {lines: ($l | map(sub("^#{1,6}[ \t]+"; ""))), bold: [range(0; $l | length) as $i | select($l[$i] | test("^#{1,6}[ \t]")) | $i]}
           else {lines: $l, numbered: ($k == "code")} end) + {attach: $a}' < "$TMP/page.txt" > "$TMP/page.json"
}
files_page_picture() {   # files_page_picture PATH BASE PX -- page.json: the picture, PX on its long side at most, its size; full when that is the whole
    _fpd=$(png_size "$1")
    [ -n "$_fpd" ] || _fpd=$(file -b -- "$1" 2>/dev/null | sed -n 's/.*[ ,]\([0-9][0-9]*\) *x *\([0-9][0-9]*\).*/\1 \2/p' | head -1)
    case $1 in *.svg|*.SVG) ;; *) if [ -z "$_fpd" ] && command -v mpv >/dev/null 2>&1; then   # a TIFF's size: file(1) gives none, mpv reads it
        # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
        _fpd=$(files_tool mpv $MPV_SAFE --untimed --vo=null --ao=null --length=0.05 --msg-level=all=no,term-msg=info --term-playing-msg='${width:} ${height:}' -- "$1" </dev/null 2>/dev/null | head -1 | grep -x '[0-9][0-9]* [0-9][0-9]*' || :)
    fi ;; esac
    _fps=$3; _fpz=null; _fpw=false; [ "$3" != "$FILES_FULL_PX" ] || _fpw=true
    if [ -n "$_fpd" ]; then
        # shellcheck disable=SC2086   # two numbers, split on purpose
        set -- "$1" "$2" "$3" $_fpd
        printf '%s \303\227 %s\n' "$4" "$5" >> "$TMP/page.lead"; _fpz="[$4,$5]"
        [ "$4" -ge "$5" ] && _fpl=$4 || _fpl=$5; [ "$_fpl" -gt "$_fps" ] || { _fps=$_fpl; _fpw=true; }
    fi
    case $1 in
        *.svg|*.SVG) command -v rsvg-convert >/dev/null 2>&1 && files_tool rsvg-convert -a -w "$_fps" -h "$_fps" -o "$2.png" "$1" 2>/dev/null ;;
        *) pic_png "$1" "$2.png" "$_fps" ;;
    esac || { files_say "cannot view: nothing here draws this picture, Enter opens it"; return 0; }
    if [ "$_fpz" != null ]; then   # EXIF orientation: the size is the drawn one's way round
        # shellcheck disable=SC2046   # four numbers, split on purpose
        set -- "$1" "$2" "$3" $_fpd $(png_size "$2.png")
        if [ $# -eq 7 ] && { { [ "$4" -gt "$5" ] && [ "$7" -gt "$6" ]; } || { [ "$5" -gt "$4" ] && [ "$6" -gt "$7" ]; }; }; then
            printf '%s \303\227 %s\n' "$5" "$4" > "$TMP/page.lead"; _fpz="[$5,$4]"
        fi
    fi
    jq -cn --arg p "$2.png" --argjson z "$_fpz" --argjson f "$_fpw" '{picture: $p, full: $f} + (if $z == null then {} else {size: $z} end)' > "$TMP/page.json"
}
files_page_pdf() {   # files_page_pdf PATH PAGE BASE PX -- page.json: the page drawn PX tall at most, its size at 96 pixels an inch, its text for spark
    command -v pdftoppm >/dev/null 2>&1 || { files_say "cannot view: pdftoppm (poppler) is not installed, Enter opens it"; return 0; }
    _fpn=$(files_tool pdfinfo "$1" 2>"$TMP/pdf.err" | sed -n 's/^Pages: *\([0-9][0-9]*\).*/\1/p')
    if [ -z "$_fpn" ] && grep -qi 'password' "$TMP/pdf.err"; then files_say "cannot view: this PDF is locked by a password, Enter opens it"; return 0; fi
    [ -n "$_fpn" ] && [ "$_fpn" -gt 0 ] || { files_say "cannot view: this PDF could not be read, Enter opens it"; return 0; }
    [ "$2" -le "$_fpn" ] || set -- "$1" "$_fpn" "$3" "$4"
    _fpz=$(files_tool pdfinfo -f "$2" -l "$2" "$1" 2>/dev/null | awk '/^Page +[0-9]+ size:/ { printf "[%d,%d]", $4 * 96 / 72 + 0.5, $6 * 96 / 72 + 0.5; exit }')
    [ -f "$3-$2.png" ] || files_tool pdftoppm -f "$2" -l "$2" -png -scale-to "$4" -singlefile "$1" "$3-$2" >/dev/null 2>&1 \
        || { files_say "cannot view: this page could not be drawn, Enter opens it"; return 0; }
    [ -f "$3-$2.txt" ] || files_tool pdftotext -f "$2" -l "$2" -enc UTF-8 "$1" "$3-$2.txt" >/dev/null 2>&1 || rm -f "$3-$2.txt"
    _fpa=''; [ ! -s "$3-$2.txt" ] || _fpa=$3-$2.txt
    jq -cn --arg p "$3-$2.png" --argjson n "$2" --argjson m "$_fpn" --arg a "$_fpa" --argjson z "${_fpz:-null}" --argjson f "$([ "$4" = "$FILES_FULL_PX" ] && echo true || echo false)" \
        '{picture: $p, page: $n, pages: $m, full: $f} + (if $a == "" then {} else {attach: $a} end) + (if $z == null then {} else {size: $z} end)' > "$TMP/page.json"
}
audio_bits() {   # audio_bits FILE -> the sample bits from a FLAC, WAV or AIFF header (mpv decodes 24 bit to 32); nothing for another
    od -An -v -tu1 -N 65536 < "$1" 2>/dev/null | awk '
        { for (i = 1; i <= NF; i++) b[n++] = $i }
        function id(o,   r, j) { r = ""; for (j = 0; j < 4; j++) r = r sprintf("%c", b[o + j]); return r }
        function le(o, k,   r, j) { r = 0; for (j = k - 1; j >= 0; j--) r = r * 256 + b[o + j]; return r }
        function be(o, k,   r, j) { r = 0; for (j = 0; j < k; j++) r = r * 256 + b[o + j]; return r }
        END {
            if (id(0) == "fLaC") { print (b[20] % 2) * 16 + int(b[21] / 16) + 1; exit }
            if (id(0) == "RIFF" && id(8) == "WAVE")
                for (o = 12; o + 28 <= n; o += 8 + z + z % 2) { z = le(o + 4, 4)
                    if (id(o) == "fmt ") { f = le(o + 8, 2); v = le(o + 22, 2); if (f == 65534 && z >= 40) { f = le(o + 32, 2); if (le(o + 26, 2) > 0) v = le(o + 26, 2) } if (f == 1) print v; exit } }
            if (id(0) == "FORM" && (id(8) == "AIFF" || id(8) == "AIFC"))
                for (o = 12; o + 16 <= n; o += 8 + z + z % 2) { z = be(o + 4, 4)
                    if (id(o) == "COMM") { print be(o + 14, 2); exit } }
        }'
}
files_sound_draw() {   # files_sound_draw PATH BASE -- BASE-sound.png drawn aside by mpv, one at a time, waited for a moment
    if [ -f "$TMP/sound.job" ]; then
        read -r _fsj _fsb < "$TMP/sound.job"
        if [ "$_fsb" = "$2" ] && kill -0 "$_fsj" 2>/dev/null; then files_sound_wait "$2"; return 0; fi
        files_sound_stop
    fi
    (
        FILES_IDLE=1; FILES_TOOL_T=$FILES_SOUND_T; _fsd=$(mktemp -d) || exit 0; _fsp=$2-sound.pid
        trap 'rm -rf "$_fsd" "$_fsp"' EXIT; trap 'exit 143' TERM   # stopped before it is drawn: its folder goes too
        # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
        files_tool mpv $MPV_SAFE --untimed --really-quiet --ao=null --vo=image --vo-image-format=png --vo-image-outdir="$_fsd" \
            --lavfi-complex="[aid1]asplit[a][b];[a]showwavespic=s=1600x${FILES_WAVE_PX}:split_channels=0:colors=white:scale=sqrt[w];[b]showspectrumpic=s=1600x512:legend=0:fscale=log:scale=log[s];[w][s]vstack=inputs=2[vo]" \
            -- "$1" </dev/null >/dev/null 2>&1 &
        echo "$!" > "$2-sound.pid"; wait "$!"
        mv "$_fsd/00000001.png" "$2-sound.png.new" 2>/dev/null && mv "$2-sound.png.new" "$2-sound.png"   # whole or not there: the dialog reads it as it comes
    ) </dev/null >/dev/null 2>&1 &
    echo "$! $2" > "$TMP/sound.job"
    files_sound_wait "$2"
}
files_sound_wait() { _fsw=0; while [ "$_fsw" -lt 15 ] && [ ! -f "$1-sound.png" ]; do sleep 0.1; _fsw=$((_fsw + 1)); done; }   # files_sound_wait BASE -- 1.5 s at most for the picture
files_sound_stop() {   # the waveform being drawn aside, stopped
    [ -f "$TMP/sound.job" ] || return 0
    read -r _fsj _fsb < "$TMP/sound.job"
    [ ! -f "$_fsb-sound.pid" ] || kill "$(cat "$_fsb-sound.pid")" 2>/dev/null || :
    kill "$_fsj" 2>/dev/null || :; rm -f "$TMP/sound.job"
}
files_time() { awk -v s="$1" 'BEGIN { s = int(s + 0.5); h = int(s / 3600); m = int(s % 3600 / 60); if (h > 0) printf "%d:%02d:%02d", h, m, s % 60; else printf "%d:%02d", m, s % 60 }'; }   # files_time SECONDS -> 3:45, 1:02:03
files_page_media() {   # files_page_media PATH sound|video BASE [PX] -- page.json: a sound's tags, facts and waveform; a video's frame PX wide at most, its length and size
    command -v mpv >/dev/null 2>&1 || { files_say "cannot view: mpv is not installed, Enter opens it"; return 0; }
    # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
    _fmf=$(files_tool mpv $MPV_SAFE --untimed --vo=null --ao=null --length=0.05 --msg-level=all=no,term-msg=info \
        --term-playing-msg="\${=duration:0}$US\${width:}$US\${height:}$US\${audio-params/samplerate:}$US\${audio-params/channel-count:}$US\${audio-params/format:}$US\${audio-codec-name:}$US\${metadata/by-key/title:}$US\${metadata/by-key/artist:}$US\${metadata/by-key/album:}$US\${video-params/rotate:}" -- "$1" </dev/null 2>/dev/null | head -1)
    [ -n "$_fmf" ] || { files_say "cannot view: mpv could not read this file, Enter opens it"; return 0; }
    printf '%s\n' "$_fmf" | tr "$US" '\n' > "$TMP/page.media"
    { read -r _fms; read -r _fmw; read -r _fmh; read -r _fmr; read -r _fmc; read -r _fmb; read -r _fmk; } < "$TMP/page.media"
    _fma=$(jq -cn --arg p "$1" '{path: $p}')
    if [ "$2" = video ]; then
        files_time "${_fms:-0}" >> "$TMP/page.lead"; echo >> "$TMP/page.lead"
        _fmx=${4:-$FILES_PAGE_PX}; _fmz=null; _fmu=true
        # the frame fits PX on its stored long side; the size shown is turned by its rotation
        _fmv=''; _fmo=$(sed -n 11p "$TMP/page.media")
        if [ -n "$_fmw" ] && [ -n "$_fmh" ]; then
            if [ "$_fmw" -ge "$_fmh" ]; then _fml=$_fmw; [ "$_fmw" -le "$_fmx" ] || _fmv=--vf=scale=w=$_fmx:h=-2
            else _fml=$_fmh; [ "$_fmh" -le "$_fmx" ] || _fmv=--vf=scale=w=-2:h=$_fmx; fi
            case $_fmo in 90|270) set -- "$1" "$2" "$3" "${4:-}" "$_fmh" "$_fmw" ;; *) set -- "$1" "$2" "$3" "${4:-}" "$_fmw" "$_fmh" ;; esac
            printf '%s \303\227 %s\n' "$5" "$6" >> "$TMP/page.lead"; _fmz="[$5,$6]"
            [ "$_fml" -le "$_fmx" ] || _fmu=false; [ "$_fmx" != "$FILES_FULL_PX" ] || _fmu=true
        fi
        rm -rf "$TMP/frame"; mkdir -p "$TMP/frame"
        [ -f "$3.png" ] || {
            # shellcheck disable=SC2086
            files_tool mpv $MPV_SAFE --untimed --really-quiet --no-audio --vo=image --vo-image-format=png --vo-image-outdir="$TMP/frame" \
                --start=10% --frames=1 $_fmv -- "$1" </dev/null >/dev/null 2>&1
            mv "$TMP/frame/00000001.png" "$3.png" 2>/dev/null
        } || { files_say "cannot view: no frame of this video could be drawn, Enter opens it"; return 0; }
        # played over its frame under sway; else in its app
        _fmh=''; ! files_video_here || _fmh=1
        jq -cn --arg p "$3.png" --argjson a "$_fma" --argjson z "$_fmz" --argjson f "$_fmu" --arg h "$_fmh" --argjson n "${_fms:-0}" \
            '{picture: $p, full: $f} + (if $h != "" then {play: {name: "files_play", arguments: $a, said: "play"}, stop: {name: "files_stop", arguments: {}, said: "stop"}, seconds: $n}
               else {play: {name: "files_open", arguments: $a, said: "play"}} end) + (if $z == null then {} else {size: $z} end)' > "$TMP/page.json"
        return 0
    fi
    # the rate, the bits of a lossless one, the channels, the format, a lossy one's bitrate
    [ -z "$_fmr" ] || awk -v r="$_fmr" 'BEGIN { k = r / 1000; if (k == int(k)) printf "%d kHz\n", k; else printf "%.1f kHz\n", k }' >> "$TMP/page.lead"
    case $_fmk in mp3|mp2|aac|opus|vorbis|wmav2|ac3|eac3|dca) _fml=lossy ;; *) _fml='' ;; esac
    [ -n "$_fml" ] || case $_fmb in u8*) echo '8 bit' ;; s16*) echo '16 bit' ;; s24*) echo '24 bit' ;;
        s32*) _fmn=$(audio_bits "$1"); if [ -n "$_fmn" ]; then echo "$_fmn bit"; elif [ "$_fmk" != alac ]; then echo '32 bit'; fi ;; float*) echo '32-bit float' ;; double*) echo '64-bit float' ;; esac >> "$TMP/page.lead"
    case $_fmc in 1) echo mono ;; 2) echo stereo ;; ''|0) ;; *) echo "$_fmc channels" ;; esac >> "$TMP/page.lead"
    case $_fmk in pcm_*) echo PCM ;; '') ;; *) printf '%s\n' "$_fmk" | tr 'a-z' 'A-Z' ;; esac >> "$TMP/page.lead"
    [ -z "$_fml" ] || awk -v b="$(wc -c < "$1")" -v s="${_fms:-0}" 'BEGIN { if (s > 0) printf "%d kbps\n", b * 8 / s / 1000 + 0.5 }' >> "$TMP/page.lead"
    # drawn aside at an idle priority; the page answers at once, and the dialog draws the picture once it is there
    [ -f "$3-sound.png" ] || files_sound_draw "$1" "$3"
    _fmp=$3-sound.png
    sed -n '8p' "$TMP/page.media" > "$TMP/page.tags"; sed -n '9,10p' "$TMP/page.media" | awk 'NF { s = s (s == "" ? "" : " \302\267 ") $0 } END { if (s != "") print s }' >> "$TMP/page.tags"
    jq -Rn --argjson a "$_fma" --argjson n "${_fms:-0}" --arg p "$_fmp" --argjson h "$FILES_WAVE_PX" '[inputs | select(. != "")] as $l
        | {lines: $l, bold: (if ($l | length) > 0 then [0] else [] end), seconds: $n,
           play: {name: "files_play", arguments: $a, said: "play"}, stop: {name: "files_stop", arguments: {}, said: "stop"}}
          + (if $p == "" then {} else {sound: {picture: $p, wave: $h}} end)' < "$TMP/page.tags" > "$TMP/page.json"
}
files_page_office() {   # files_page_office PATH BASE -- page.json: an Office document's text; BASE.txt for spark
    command -v python3 >/dev/null 2>&1 || { files_say "cannot view: python3 is not installed, Enter opens it"; return 0; }
    files_tool python3 -I "$REPO/lib/office.py" "$1" > "$TMP/page.office" 2>/dev/null && jq -e '.lines | length > 0' "$TMP/page.office" >/dev/null 2>&1 \
        || { files_say "cannot view: this document could not be read, Enter opens it"; return 0; }
    jq -r '.lines[]' "$TMP/page.office" > "$2.txt"
    jq -c --arg a "$2.txt" '. + {attach: $a}' "$TMP/page.office" > "$TMP/page.json"
}
files_play() {   # files_play PATH [AT] -- a sound played from AT seconds through mpv; the one playing stops first
    files_stop
    # shellcheck disable=SC2086
    mpv $MPV_SAFE --no-video --no-terminal --really-quiet --start="+${2:-0}" -- "$1" </dev/null >/dev/null 2>&1 &
    echo "$!" > "$TMP/play.pid"
}
files_video_here() { [ -n "${SWAYSOCK:-}" ] && command -v swaymsg >/dev/null 2>&1 && swaymsg -t get_version >/dev/null 2>&1; }   # sway is here to lay the player over the dialog
files_play_video() {   # files_play_video PATH AT X Y W H -- a video played over its frame (X Y W H in the terminal's pixels from the dialog's grid); says why not and fails where it cannot
    _fvt=$(swaymsg -t get_tree 2>/dev/null) || { echo "sway does not answer"; return 1; }
    _fvd=$(printf '%s' "$_fvt" | jq -r 'first(.. | objects | select(.app_id? == "spark-dialog" and .focused? == true) | "\(.rect.x + .window_rect.x) \(.rect.y + .window_rect.y) \(.fullscreen_mode // 0)") // empty')
    [ -n "$_fvd" ] || { echo "the dialog's window is not found"; return 1; }
    _fvo=$(printf '%s' "$_fvt" | jq -r 'first(.nodes[] | select(.type == "output") | select(any(.. | objects; .app_id? == "spark-dialog" and .focused? == true)) | .name) // empty')
    _fvs=$(swaymsg -t get_outputs 2>/dev/null | jq -r --arg o "$_fvo" 'first(.[] | select(.name == $o) | .scale) // 1')
    # sway draws a full screen window over a floating one: for the play the dialog trades full screen for a floating
    # window on the same pixels, the bar out of sight, and takes it back when the play ends. One command each way
    _fvsw=''
    if [ -f "$TMP/play.swap" ]; then _fvsw=$(cat "$TMP/play.swap")   # an earlier play traded it already
    else
        case $_fvd in *' 0') ;; *)
            _fvsw=$(printf '%s' "$_fvt" | jq -r 'first(.. | objects | select(.app_id? == "spark-dialog" and .focused? == true) | "\(.id) \(.geometry.width // 0) \(.geometry.height // 0)") // empty')
            _fvr=$(swaymsg -t get_outputs 2>/dev/null | jq -r --arg o "$_fvo" 'first(.[] | select(.name == $o) | "\(.rect.width) \(.rect.height) \(.rect.x) \(.rect.y)") // empty')
            [ -n "$_fvsw" ] && [ -n "$_fvr" ] || { echo "the dialog's window is not found"; return 1; }
            # shellcheck disable=SC2086   # four numbers
            set -- "$1" "$2" "$3" "$4" "$5" "$6" $_fvr
            # the bar first; then the window in one command (a sway with no bar says no to the bar alone)
            swaymsg "bar mode invisible" >/dev/null 2>&1 || :
            swaymsg "[con_id=${_fvsw%% *}] fullscreen disable, resize set $7 $8, move absolute position $9 ${10}" >/dev/null 2>&1 \
                || { swaymsg "bar mode $(bar_mode)" >/dev/null 2>&1 || :; echo "full screen could not make room for the video"; return 1; }
            printf '%s\n' "$_fvsw" > "$TMP/play.swap" ;;
        esac
    fi
    _fvp=$(sed -n 's/^pad=\([0-9]*\)x\([0-9]*\).*/\1 \2/p' "$HOME/.config/foot/dialog.ini" 2>/dev/null | head -1)
    # the frame on the screen, in sway's units: the window's corner, foot's padding, the dialog's pixels by the screen's scale
    # shellcheck disable=SC2086   # numbers, split on purpose
    _fvg=$(printf '%s %s %s %s %s %s\n' "$3 $4 $5 $6" ${_fvd% *} ${_fvp:-0 0} | awk -v s="${_fvs:-1}" '{ if (s <= 0) s = 1; printf "%d %d %d %d", $5 + $7 + $1 / s, $6 + $8 + $2 / s, $3 / s, $4 / s }')
    files_stop
    # shellcheck disable=SC2086   # MPV_SAFE is options, split on purpose
    # its size set from the frame's: mpv left to itself fits the screen's width
    mpv $MPV_SAFE --wayland-app-id=spark-preview --no-border --osc=no --osd-level=0 --no-terminal --really-quiet --keep-open=no \
        --geometry="$(printf '%s' "$_fvg" | awk '{ printf "%dx%d", $3, $4 }')" --start="+$2" -- "$1" </dev/null >/dev/null 2>&1 &
    _fvm=$!; echo "$_fvm" > "$TMP/play.pid"
    # the full screen given back when this play ends, unless another play took the frame; a job, its fds closed,
    # never an and-or list in the background: under bash that keeps the step's answer pipe open while the video plays
    if [ -n "$_fvsw" ]; then
        ( while pid_running "$_fvm"; do sleep 0.2; done; sleep 0.3
          if [ -f "$TMP/play.pid" ] && pid_running "$(cat "$TMP/play.pid")"; then exit 0; fi
          rm -f "$TMP/play.swap"; files_full_back "$_fvsw" ) </dev/null >/dev/null 2>&1 3>&- 4<&- &
    fi
    # shellcheck disable=SC2086   # four numbers
    set -- $_fvg
    _fvi=0; while [ "$_fvi" -lt 30 ] && ! swaymsg -t get_tree 2>/dev/null | jq -e 'any(.. | objects; .app_id? == "spark-preview")' >/dev/null 2>&1; do sleep 0.1; _fvi=$((_fvi + 1)); done
    # it maps unseen (opacity 0) and is shown where it plays in one command: no frame at its own size
    swaymsg "[app_id=\"spark-preview\"] floating enable, border none, resize set $3 $4, move absolute position $1 $2, opacity 1" >/dev/null 2>&1 || :
}
pid_running() { kill -0 "$1" 2>/dev/null && ! grep -qs '^State:[[:space:]]*Z' "/proc/$1/status"; }   # pid_running PID -- it runs; a zombie no one reaps (a container's first process may never) has ended
files_full_back() {   # files_full_back "ID W H" -- the dialog full screen again after a play, its own size set first so leaving full screen later gives it back
    # shellcheck disable=SC2086   # three numbers
    set -- $1
    _ffb=''; [ "${2:-0}" -gt 0 ] && [ "${3:-0}" -gt 0 ] && _ffb="resize set $2 $3, move position center, "
    swaymsg "[con_id=$1] ${_ffb}fullscreen enable" >/dev/null 2>&1 || :
    swaymsg "bar mode $(bar_mode)" >/dev/null 2>&1 || :   # back behind full screen, unseen
}
files_stop() { [ ! -f "$TMP/play.pid" ] || { kill "$(cat "$TMP/play.pid")" 2>/dev/null || :; rm -f "$TMP/play.pid"; }; }   # the sound playing here, stopped; quiet when none plays
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
    if [ -n "${SWAYSOCK:-}" ]; then
        _ow=0; while [ "$(desk_windows_all)" -le "$2" ] && [ "$_ow" -lt 4 ]; do sleep 0.25; _ow=$((_ow + 1)); done
        rpc_result "$1" "$(jq -cn '{opened: true} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
    else rpc_result "$1" "$(jq -c '{content: [{type: "text", text: tojson}], structuredContent: ., isError: false}' "$3")"; fi
}
files_manager_ok() { [ "$OS" = Darwin ] || { command -v xdg-open >/dev/null 2>&1 && [ -n "$(xdg-mime query default inode/directory 2>/dev/null)" ]; }; }   # a system file manager is configured (Finder on macOS)
files_text() { [ -f "$1" ] && { [ ! -s "$1" ] || LC_ALL=C grep -qI . "$1" 2>/dev/null; }; }   # a text file: grep reads it as text; an empty file is one
files_open_text() {   # files_open_text ID PATH -- a text file in the editor in a terminal window (xdg-open would start a terminal editor with none); 1 on macOS, without sway or an editor, or a path sway would split
    [ "$OS" != Darwin ] && files_text "$2" && desk_in_sway && _fed=$(editor_pick) || return 1
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
    _before=''; [ -z "${SWAYSOCK:-}" ] || _before=$(desk_windows_all)
    if ! python3 "$REPO/lib/open_path.py" "$OS" "$2" ${3:-} > "$TMP/open.result" 2> "$TMP/open.error"; then provide_refuse "$1" "$(scrub_text < "$TMP/open.error")"; return 0; fi
    files_opened "$1" "$_before" "$TMP/open.result"
}
provide_files_call() {   # provide_files_call ID TOOL ARGUMENTS -- a step over a path files_ok allows; a write answers with its undo
    _fa=$(printf '%s' "$3" | jq -r '.path // ""'); _fto=$(printf '%s' "$3" | jq -r '.to // ""'); _fnm=$(printf '%s' "$3" | jq -r '.name // ""'); _fws=$(printf '%s' "$3" | jq -r '.words // ""')
    case $2 in
        files_stop) files_stop; files_result "$1" "stopped"; return 0 ;;
        files_empty) _fo=$(files_empty) || { provide_refuse "$1" "files: $_fo"; return 0; }; files_result "$1" "$_fo"; return 0 ;;   # for good: no undo
        files_find|files_say)
            _fk=${2#files_}; _fsw=$(printf '%s' "$_fws" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
            [ -n "$_fsw" ] || { provide_refuse "$1" "files: $_fk takes the words to look for"; return 0; }
            _fsu="spark-shell://files/rows/$_fk/$(files_b64 "$_fsw")"
            provide_files_rows "$_fsu" > "$TMP/files.search" || { provide_refuse "$1" "files: $_fk takes plain words, 256 characters at most"; return 0; }
            _fsc=$(jq '[.rows[] | select(.id != "files:total")] | length' "$TMP/files.search")
            if [ "$_fsc" -eq 0 ]; then if [ "$_fk" = find ]; then files_result "$1" "nothing under your home is named $_fsw"; else files_result "$1" "no text file under your home says $_fsw"; fi; return 0; fi
            if [ "$_fk" = find ]; then files_result "$1" "$_fsc named $_fsw" '' '' "open=$_fsu"; else files_result "$1" "$_fsc say $_fsw" '' '' "open=$_fsu"; fi
            return 0 ;;
        files_restore)
            _ff=$_fa; case $_ff in /*) ;; *) provide_refuse "$1" "files: that is not a path in the folders given"; return 0 ;; esac
            _ffd=$(files_ok "$(dirname "$_ff")" dir) || { provide_refuse "$1" "files: that is not a folder in the folders given"; return 0; }
            files_name_ok "${_ff##*/}" || { provide_refuse "$1" "files: that is not a name in the folders given"; return 0; }
            _fo=$(files_restore "$_ffd/${_ff##*/}" "$(printf '%s' "$3" | jq -r '.item // ""')") || { provide_refuse "$1" "files: $_fo"; return 0; }
            files_result "$1" "$_fo" files_trash "$(jq -cn --arg p "$_ffd/${_ff##*/}" '{path: $p}')"; return 0 ;;
        files_purge)   # for good: no undo
            _ff=$_fa; case $_ff in /*) ;; *) provide_refuse "$1" "files: that is not a path in the folders given"; return 0 ;; esac
            _ffd=$(files_ok "$(dirname "$_ff")" dir) || { provide_refuse "$1" "files: that is not a folder in the folders given"; return 0; }
            files_name_ok "${_ff##*/}" || { provide_refuse "$1" "files: that is not a name in the folders given"; return 0; }
            _fo=$(files_purge "$_ffd/${_ff##*/}" "$(printf '%s' "$3" | jq -r '.item // ""')") || { provide_refuse "$1" "files: $_fo"; return 0; }
            files_result "$1" "$_fo"; return 0 ;;
        files_new_folder|files_new_text)
            _fn=$(files_new_ok "$_fa" "$_fnm") || { provide_refuse "$1" "files: $_fn"; return 0; }
            if [ "$2" = files_new_folder ]; then mkdir "$_fn" 2>/dev/null || { provide_refuse "$1" "files: could not make $_fnm"; return 0; }
                files_result "$1" "folder $_fnm made in $(files_home "${_fn%/*}")" files_trash "$(jq -cn --arg p "$_fn" '{path: $p}')"; return 0; fi
            : > "$_fn" 2>/dev/null || { provide_refuse "$1" "files: could not make $_fnm"; return 0; }
            if desk_in_sway && editor_pick >/dev/null; then   # in the editor, in a terminal window: the window is the receipt
                case $_fn in *[,\;\'\"]*) ;; *)
                    if win_exec "$(editor_exec "$_fn")"; then rpc_result "$1" "$(jq -cn '{opened: true} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"; return 0; fi ;;
                esac
            fi
            files_result "$1" "$_fnm made in $(files_home "${_fn%/*}")" files_trash "$(jq -cn --arg p "$_fn" '{path: $p}')"; return 0 ;;
        files_browse) _ff=$(files_ok "$_fa" dir) || { provide_refuse "$1" "files: that is not a folder in the folders given"; return 0; } ;;
        files_open|files_show|files_attach|files_play) _ff=$(files_ok "$_fa" file) || { provide_refuse "$1" "files: that is not a file in the folders given"; return 0; } ;;
        *) _ff=$(files_ok "$_fa" any) || { provide_refuse "$1" "files: that is not a file or a folder in the folders given"; return 0; } ;;
    esac
    _fname=$(printf '%s' "${_ff##*/}" | scrub_text)
    case $2 in files_rename|files_move|files_copy|files_trash) ! files_is_root "$_ff" || { provide_refuse "$1" "files: your home and a drive stay as they are"; return 0; } ;; esac
    case $2 in
        files_open) files_open_text "$1" "$_ff" || files_open_with "$1" "$_ff" ;;
        files_play)
            _fat=$(printf '%s' "$3" | jq -r '.at // 0 | if type == "number" and . >= 0 and . < 86400 then (. * 10 | floor) / 10 else 0 end')
            if [ "$(files_kind "$_ff")" = video ] && command -v mpv >/dev/null 2>&1 && files_video_here; then   # over its frame
                _fbx=$(printf '%s' "$3" | jq -r '[.x, .y, .w, .h] | if all(type == "number" and . >= 0 and . <= 65535) then map(floor | tostring) | join(" ") else "" end')
                [ -n "$_fbx" ] || { provide_refuse "$1" "files: a video plays over its view: the dialog gives the box"; return 0; }
                # shellcheck disable=SC2086   # four numbers, split on purpose
                _fpv=$(files_play_video "$_ff" "$_fat" $_fbx) || { provide_refuse "$1" "files: ${_fpv:-$_fname could not be played here}"; return 0; }
                files_result "$1" "playing $_fname"; return 0
            fi
            [ "$(files_kind "$_ff")" = sound ] && command -v mpv >/dev/null 2>&1 || { provide_refuse "$1" "files: $_fname is no sound mpv plays here"; return 0; }
            files_play "$_ff" "$_fat"; files_result "$1" "playing $_fname" ;;
        files_browse) files_open_with "$1" "$_ff" ;;
        files_app)   # the app the system assigns; a terminal program gets a terminal
            if files_app_terminal "$_ff"; then files_open_text "$1" "$_ff" || files_open_with "$1" "$_ff"
            else files_open_with "$1" "$_ff"; fi ;;
        files_reveal) files_open_with "$1" "$_ff" --reveal ;;
        files_show|files_attach)
            set -- "$1" "$2" "$(files_stat "$_ff" | cut -d' ' -f1)"
            [ "$3" -le "$FILES_SHOW_MAX" ] || { provide_refuse "$1" "files: $_fname is larger than $((FILES_SHOW_MAX / 1024)) kB"; return 0; }
            [ "$(tr -d '\000' < "$_ff" | wc -c | tr -d ' ')" = "$3" ] || { provide_refuse "$1" "files: $_fname is not text"; return 0; }
            if [ "$2" = files_show ]; then
                rpc_result "$1" "$(head -n "$FILES_SHOW_LINES" "$_ff" | scrub_text | jq -Rs --arg n "$_fname" '{receipt: ($n + "\n" + (. | rtrimstr("\n")))} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
            else
                _fx=$(printf '%s' "${_ff##*/}" | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | tr 'A-Z' 'a-z')
                case " $DIALOG_ATTACH_TYPES " in *" ${_fx:-.} "*) ;; *) provide_refuse "$1" "files: $_fname is not a type plus attaches ($DIALOG_ATTACH_TYPES)"; return 0 ;; esac
                rpc_result "$1" "$(jq -cn --arg r "attached $_fname" --arg p "$_ff" '{receipt: $r, attach: $p} | {content: [{type: "text", text: tojson}], structuredContent: ., isError: false}')"
            fi ;;
        files_rename)
            _fn=$(files_new_ok "${_ff%/*}" "$_fnm") || { provide_refuse "$1" "files: $_fn"; return 0; }
            mv "$_ff" "$_fn" 2>/dev/null || { provide_refuse "$1" "files: could not rename $_fname"; return 0; }
            files_result "$1" "$_fname renamed to $_fnm" files_rename "$(jq -cn --arg p "$_fn" --arg n "${_ff##*/}" '{path: $p, name: $n}')" ;;
        files_move|files_copy)
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
            fi ;;
        files_trash)
            _fo=$(files_trash "$_ff") || { provide_refuse "$1" "files: $_fo"; return 0; }
            files_result "$1" "$_fo" files_restore "$(jq -cn --arg p "$_ff" '{path: $p}')" ;;
    esac
}
provide_roots() {   # provide_roots RESULT -- the host's roots kept in PROOTS, each a folder's realpath, never /
    printf '%s' "$1" | jq -r '.roots // [] | .[] | .uri // "" | select(startswith("file://")) | ltrimstr("file://")
        | [match("%[0-9A-Fa-f]{2}|[^%]+|%"; "g").string | if (startswith("%") and length == 3) then ([.[1:] | ascii_downcase | explode | map(if . >= 97 then . - 87 else . - 48 end) | .[0] * 16 + .[1]] | implode) else . end] | add // ""' 2>/dev/null \
        | while IFS= read -r _fr; do _fr=$(realpath "$_fr" 2>/dev/null) && [ "$_fr" != / ] && [ -d "$_fr" ] && printf '%s\n' "$_fr"; done > "$PROOTS.new" || :
    mv "$PROOTS.new" "$PROOTS"
    rpc_note notifications/resources/updated '{"uri":"spark-shell://files/rows"}'   # a read that came before the roots answered with none: the host reads again now
}

