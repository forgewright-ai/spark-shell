# shellcheck extended-analysis=false
# --- the store: a file or a folder replaced in one step, and one writer at a time
# reads: NL TMP
# What is new is written beside what is there, every write checked, and moved onto it: a reader, a full disk or a kill
# at any moment meets the old one or the new one, whole. A write takes the command that prints the lines, never a pipe:
# a pipe's status is its last command's, and the lines of one that failed would be kept.
store_said() { _ssw=$(tail -n 1 "$TMP/store.why" 2>/dev/null | sed 's/.*: //'); printf '%s' "${_ssw:+: $_ssw}"; }   # -> ": No space left on device", the last words of what failed here; nothing when it had none

# --- a file
stage_of() {   # stage_of FILE -> _sgf the file FILE is (a link stays one: the file it ends at is replaced) and _sgn where its next version waits
    _sgf=$1; _sgl=0
    while [ -L "$_sgf" ] && [ "$_sgl" -lt 16 ]; do
        _sgt=$(readlink "$_sgf"); _sgl=$((_sgl + 1))
        case $_sgt in /*) _sgf=$_sgt ;; *) _sgf=${_sgf%/*}/$_sgt ;; esac
    done
    _sgn=${_sgf%/*}/.${_sgf##*/}.new.$$
}
stage_clear() {   # stage_clear FILE -- stage_of FILE, and what a killed writer left there gone: where a tool that writes a file itself puts FILE's next version, for file_commit
    stage_of "$1"
    for _fsl in "${_sgn%."$$"}".*; do [ ! -e "$_fsl" ] || kill -0 "${_fsl##*.}" 2>/dev/null || rm -f "$_fsl"; done
}
file_stage() {   # file_stage FILE CMD ARG... -- what CMD prints waits beside FILE, with FILE's mode, for file_commit; 1 when CMD or a write fails, and nothing waits
    stage_clear "$1"; shift
    if [ -d "$_sgf" ]; then echo "it is a folder" > "$TMP/store.why"; return 1; fi
    if [ -e "$_sgf" ] && [ ! -w "$_sgf" ]; then echo "it is read only" > "$TMP/store.why"; return 1; fi
    { { [ ! -f "$_sgf" ] || cp "$_sgf" "$_sgn"; } && "$@" > "$_sgn"; } 2>"$TMP/store.why" && return 0
    rm -f "$_sgn"; return 1
}
file_commit() { stage_of "$1"; mv -f "$_sgn" "$_sgf" 2>"$TMP/store.why" || { rm -f "$_sgn"; return 1; }; }   # file_commit FILE -- its next version in place
file_unstage() { stage_of "$1"; rm -f "$_sgn"; }   # file_unstage FILE -- its next version dropped
write_whole() { file_stage "$@" && file_commit "$1"; }   # write_whole FILE CMD ARG... -- what CMD prints becomes FILE in one step; 1 with FILE as it was when CMD or a write fails
env_with() {   # env_with FILE KEY VALUE... -> FILE's lines, each KEY's replaced, one it lacks at the end; 1 when FILE cannot be read: lines not seen are never written over
    _ewf=$1; shift; _ewl=''
    while [ $# -ge 2 ]; do _ewl="$_ewl${_ewl:+$NL}$1=$2"; shift 2; done
    [ -e "$_ewf" ] || { printf '%s\n' "$_ewl"; return; }
    [ -f "$_ewf" ] && [ -r "$_ewf" ] || { echo "$_ewf cannot be read" >&2; return 1; }
    EW=$_ewl LC_ALL=C awk 'function key(s) { sub(/=.*/, "", s); return s }
        BEGIN { n = split(ENVIRON["EW"], line, "\n"); for (i = 1; i <= n; i++) at[key(line[i])] = i }
        index($0, "=") && ((k = key($0)) in at) { print line[at[k]]; put[at[k]] = 1; next }
        { print }
        END { for (i = 1; i <= n; i++) if (!(i in put)) print line[i] }' "$_ewf"
}
env_put() { write_whole "$1" env_with "$@"; }   # env_put FILE KEY VALUE... -- those lines of a KEY=value file, the rest as it is, in one step

# --- a folder: its next version, the one before and one on its way out stand beside it under hidden names that no list
# shows, so what a kill left is told apart: .NAME.new, .NAME.old, .NAME.gone. Their caller holds the folder's lock
dir_stage() {   # dir_stage DIR -- _dsn, an empty folder where its next version is made
    _dsn=${1%/*}/.${1##*/}.new
    { mkdir_private "${1%/*}" && rm -rf "$_dsn" && mkdir "$_dsn"; } 2>"$TMP/store.why"
}
dir_unstage() { rm -rf "${1%/*}/.${1##*/}.new"; }   # dir_unstage DIR -- its next version dropped
dir_there() { [ -e "$1" ] || [ -L "$1" ]; }   # dir_there PATH -> something is there, a link to nothing too
dir_swap() {   # dir_swap DIR -- its next version in place; the one before waits beside it, for dir_settle or dir_unswap
    _dwb=${1%/*}/.${1##*/}
    if rm -rf "$_dwb.old" 2>"$TMP/store.why"; then
        # in one step where mv and the disk can exchange two names (coreutils 9.5): DIR is never out of its place
        if dir_there "$1" && mv --exchange -T "$_dwb.new" "$1" 2>/dev/null; then
            mv "$_dwb.new" "$_dwb.old" 2>"$TMP/store.why" && return 0
            mv --exchange -T "$_dwb.new" "$1"
        elif ! dir_there "$1" || mv "$1" "$_dwb.old" 2>"$TMP/store.why"; then
            mv "$_dwb.new" "$1" 2>"$TMP/store.why" && return 0
            ! dir_there "$_dwb.old" || mv "$_dwb.old" "$1"
        fi
    fi
    rm -rf "$_dwb.new"; return 1
}
dir_settle() { rm -rf "${1%/*}/.${1##*/}.old"; }   # dir_settle DIR -- after dir_swap: the one before dropped
dir_unswap() {   # dir_unswap DIR -- after dir_swap: the one before back in place, or nothing where there was none
    _dub=${1%/*}/.${1##*/}
    dir_there "$_dub.old" || { dir_drop "$1"; return; }
    rm -rf "$_dub.gone"; mv "$1" "$_dub.gone" && mv "$_dub.old" "$1" && rm -rf "$_dub.gone"
}
dir_drop() {   # dir_drop DIR -- gone in one step, then its files
    _ddg=${1%/*}/.${1##*/}.gone
    _ddw=$({ rm -rf "$_ddg" && mv "$1" "$_ddg"; } 2>&1) || { printf '%s\n' "$_ddw" > "$TMP/store.why"; return 1; }   # only its own failure is said: it also clears up after another's
    rm -rf "$_ddg"
}
dirs_recover() {   # dirs_recover PARENT FILE -- what a killed change left among PARENT's folders, each whole when it holds FILE: one not in its place is put back, one that is has the version before dropped; the only copy is never dropped
    for _drp in "$1"/.*.old; do
        _drn=${_drp##*/.}; _drn=$1/${_drn%.old}
        if [ -e "$_drn/$2" ]; then rm -rf "$_drp"
        elif [ -e "$_drp/$2" ] && ! dir_there "$_drn"; then mv "$_drp" "$_drn"; fi
    done
    for _drp in "$1"/.*.new "$1"/.*.gone; do ! dir_there "$_drp" || rm -rf "$_drp"; done
}

# --- a lock: a file made with O_EXCL (set -C; console.sh says why not mkdir) that holds its holder's pid and, on its
# second line, when that process began. A writer that finds it held tries again for a while, then refuses in one line.
# The next writer clears a lock whose holder is gone (kill -9, a crash, a restart)
proc_born() {   # proc_born PID -> when the process began, as the system says it; nothing when it cannot tell
    if [ -r "/proc/$1/stat" ]; then
        { IFS= read -r _pbs < "/proc/$1/stat"; } 2>/dev/null || return 0
        # shellcheck disable=SC2086   # the fields past the name, split on purpose
        set -- ${_pbs##*) }; printf '%s' "${20:-}"
    else ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' || :; fi
}
lock_make() {   # lock_make LOCK PID -- LOCK made with PID in it; 1 when it is there, 2 when it cannot hold the pid (a full disk)
    lock_take "$1" || return 1
    { printf '%s\n%s\n' "$2" "$(proc_born "$2")" > "$1"; } 2>/dev/null || { lock_drop "$1"; return 2; }
}
lock_state() {   # lock_state LOCK -> free, held, blank (no pid in it: its maker is about to write it, or never will) or gone: no process has its pid, or the one that has began at another time (with no time in it: the lock is over a minute old)
    _lsp=''; _lsa=''; { { IFS= read -r _lsp && IFS= read -r _lsa; } < "$1"; } 2>/dev/null || :
    case $_lsp in ''|*[!0-9]*) if dir_there "$1"; then echo blank; else echo free; fi; return ;; esac
    if ! kill -0 "$_lsp" 2>/dev/null; then echo gone
    elif [ -n "$_lsa" ]; then if [ "$(proc_born "$_lsp")" = "$_lsa" ]; then echo held; else echo gone; fi
    elif [ -n "$(find "$1" -prune -mmin +1 2>/dev/null)" ]; then echo gone
    else echo held; fi
}
lock_clear() (   # lock_clear LOCK STATE PID -- LOCK dropped while it is STATE; one writer clears at a time (.clear), and looks again after a moment: a lock taken meanwhile is never removed
    trap '' HUP INT TERM PIPE
    case $(lock_state "$1.clear") in gone) lock_drop "$1.clear" ;; blank) [ -z "$(find "$1.clear" -prune -mmin +1 2>/dev/null)" ] || lock_drop "$1.clear" ;; esac   # a clearer that died left .clear behind
    lock_make "$1.clear" "$3" || exit 1
    sleep 0.1
    [ "$(lock_state "$1")" != "$2" ] || lock_drop "$1"
    lock_drop "$1.clear"
    ! dir_there "$1"
)
locked() (   # locked LOCK WHAT SECONDS CMD ARG... -- CMD run while holding LOCK; 1 and one line when it is not free within SECONDS. A subshell: its own traps release the lock on every exit, a signal included, and the caller's traps stay as they are
    _lkf=$1; _lkw=$2; _lkn=$(($3 * 20)); _lkb=0; _lkd=''; shift 3
    _lkp=$(exec sh -c 'echo "$PPID"')   # the subshell's pid, not $$: the caller can die while this one still writes
    trap '{ IFS= read -r _lkd < "$_lkf"; } 2>/dev/null || :; [ "$_lkd" != "$_lkp" ] || rm -f "$_lkf"' EXIT   # release only a lock that holds this pid
    trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 141' PIPE
    while :; do
        _lkr=0; lock_make "$_lkf" "$_lkp" || _lkr=$?
        case $_lkr in
            0) break ;;
            2) printf "spark-shell: the %s's lock could not be written, so nothing was (%s)\n" "$_lkw" "$_lkf" >&2; exit 1 ;;
        esac
        [ -z "${SPARK_SHELL_CONFIG_HOLD:-}" ] || : > "$SPARK_SHELL_CONFIG_HOLD.waits"   # tests only: this writer waits for a lock
        _lks=$(lock_state "$_lkf")
        if [ "$_lks" = blank ]; then _lkb=$((_lkb + 1)); else _lkb=0; fi
        if [ "$_lks" = gone ] || [ "$_lkb" -ge 10 ]; then   # blank for half a second: its maker never wrote it
            ! lock_clear "$_lkf" "$_lks" "$_lkp" || continue
        fi
        if [ "$_lkn" -le 0 ]; then
            if dir_there "$_lkf"; then printf 'spark-shell: another change holds the %s, so nothing was written. Try again (%s)\n' "$_lkw" "$_lkf" >&2
            else printf "spark-shell: the %s's lock could not be made, so nothing was written (%s)\n" "$_lkw" "$_lkf" >&2; fi
            exit 1
        fi
        _lkn=$((_lkn - 1)); sleep 0.05
    done
    "$@"
)
