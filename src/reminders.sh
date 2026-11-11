# shellcheck extended-analysis=false
# --- reminders
# sets: CAL_DIR REM_CHIME REM_DONE_DAYS REM_FIRED
# reads: REPO STATE_DIR TAB TMP US
CAL_DIR=$HOME/calendar
REM_FIRED=$STATE_DIR/reminders.fired
REM_CHIME=$REPO/asset/chime.wav
cut_chars() { jq -Rr --argjson n "$1" '.[0:$n]' 2>/dev/null || cut -c1-"$1"; }   # cut_chars N -> each line N characters at most, never half a character
rem_local() {   # rem_local ICS-TIME [TZID] -> YYYYMMDDHHMM in local time, or nothing
    _v=$1; _z=${2:-}
    case $_v in *Z) _z=UTC0; _v=${_v%Z} ;; esac
    case $_v in
        [0-9][0-9][0-9][0-9][0-1][0-9][0-3][0-9]T[0-2][0-9][0-5][0-9]*)
            _hm="$(printf '%s' "$_v" | cut -c1-8)$(printf '%s' "$_v" | cut -c10-13)"
            if [ -z "$_z" ]; then printf '%s\n' "$_hm"; return 0; fi
            _e=$(TZ=$_z date -d "$(printf '%s' "$_hm" | sed 's/^\(....\)\(..\)\(..\)\(..\)\(..\)$/\1-\2-\3 \4:\5/')" +%s 2>/dev/null || TZ=$_z date -j -f %Y%m%d%H%M "$_hm" +%s 2>/dev/null) || return 0
            when_of "$_e" %Y%m%d%H%M ;;
        [0-9][0-9][0-9][0-9][0-1][0-9][0-3][0-9]) printf '%s0000\n' "$_v" ;;
    esac
}
rem_all() {   # -> START<tab>UID<tab>SUMMARY<tab>FILE per event of ~/calendar, cached while the folder is unchanged
    [ -d "$CAL_DIR" ] || return 0
    _rc=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; _rc=${_rc:-$STATE_DIR}/reminders.list
    # the cache key: the day, and every file's name, size and mtime; a step here drops the cache too (rem_forget)
    _key="$(date +%Y%m%d) $({ stat -c '%n %s %Y' "$CAL_DIR"/*.ics 2>/dev/null || stat -f '%N %z %m' "$CAL_DIR"/*.ics 2>/dev/null || :; } | cksum)"
    if [ -f "$_rc" ] && [ "$(sed -n 1p "$_rc")" = "$_key" ]; then sed 1d "$_rc"; return 0; fi
    for _f in "$CAL_DIR"/*.ics; do
        [ -f "$_f" ] && [ ! -L "$_f" ] || continue
        # a folded line (a leading space or tab) joins the one before it; TEXT unescaped in one pass
        tr -d '\r' < "$_f" | awk -v f="$_f" -v US="$US" '
            function untext(s,   o, i, c, n) { o = ""; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == "\\" && i < length(s)) { n = substr(s, ++i, 1); o = o ((n == "n" || n == "N") ? " " : n) } else o = o c } return o }
            function line(l,   v, z) {
                if (l ~ /^BEGIN:VEVENT/) { ev = 1; s = ""; z0 = ""; u = ""; t = ""; r = 0; return }
                if (l ~ /^END:VEVENT/ && ev) { if (!r && s != "") print s US z0 US (u == "" ? "-" : u) US (t == "" ? "(no title)" : t) US f; ev = 0; return }
                if (!ev) return
                if (l ~ /^DTSTART/) { v = l; sub(/^[^:]*:/, "", v); s = v; z0 = ""; if (l ~ /^DTSTART;[^:]*TZID=/) { z = l; sub(/^DTSTART;.*TZID=/, "", z); sub(/[;:].*$/, "", z); gsub(/"/, "", z); z0 = z } }
                else if (l ~ /^UID:/) u = substr(l, 5)
                else if (l ~ /^SUMMARY[;:]/) { v = l; sub(/^[^:]*:/, "", v); t = untext(v) }
                else if (l ~ /^RRULE/) r = 1
            }
            /^[ \t]/ { cur = cur substr($0, 2); next }
            { if (have) line(cur); cur = $0; have = 1 }
            END { if (have) line(cur) }'
    done > "$TMP/rem.raw"
    while IFS="$US" read -r _s _z _u _t _f; do
        case $_z in *[!A-Za-z0-9/_+-]*) _z='' ;; esac   # a zone is a name: anything else is not handed to TZ
        _l=$(rem_local "$_s" "$_z"); [ -n "$_l" ] || continue
        printf '%s\t%s\t%s\t%s\n' "$_l" "$_u" "$_t" "$_f"
    done < "$TMP/rem.raw" | scrub_text | sort -t "$TAB" -k1,1 > "$TMP/rem.all"
    mkdir_private "$(dirname "$_rc")"; { echo "$_key"; cat "$TMP/rem.all"; } > "$_rc.new" && mv "$_rc.new" "$_rc"
    cat "$TMP/rem.all"
}
rem_list() { read_once rem.list rem_list_now; }   # -> the events from a day ago on, soonest first
rem_list_now() {
    _cut=$(when_of "$(( $(date +%s) - 86400 ))" %Y%m%d%H%M)
    rem_all | awk -F '\t' -v c="$_cut" '$1 >= c'
}
rem_rows() { read_once rem.rows rem_rows_now; }   # -> START<tab>UID<tab>SUMMARY<tab>FILE<tab>GROUP|COLUMN|DAY|UID<tab>OURS (1 or 0) per reminder
rem_rows_now() {
    _now=$(date +%Y%m%d%H%M); _d1=$(rem_day 1); _d6=$(rem_day 6)
    rem_list | while IFS="$TAB" read -r _s _u _t _f; do
        _g=$(rem_group "$_s" "$_now" "$_d1" "$_d6"); _o=0; ! rem_ours "$_s$TAB$_u$TAB$_t$TAB$_f" || _o=1
        _dy=${_s%????}; _md=${_dy#????}   # YYYYMMDD, MMDD
        printf '%s\t%s\t%s\t%s\t%s|%s|%s-%s-%s|%s\t%s\n' "$_s" "$_u" "$_t" "$_f" "$_g" "$(rem_column "$_s" "$_g")" "${_dy%????}" "${_md%??}" "${_md#??}" "$_u" "$_o"
    done
}
rem_day() { _x=$(date -d "+$1 days" +%Y%m%d 2>/dev/null || date -v+"$1"d +%Y%m%d 2>/dev/null); printf '%s' "$_x"; }   # rem_day N -> the date N days on
rem_group() {   # rem_group START NOW [TOMORROW SIXTH] -> due, today, tomorrow, this week or later
    if [ "$1" -le "$2" ]; then echo due
    elif [ "${1%????}" = "${2%????}" ]; then echo today
    elif [ "${1%????}" = "${3:-$(rem_day 1)}" ]; then echo tomorrow
    elif [ "${1%????}" -le "${4:-$(rem_day 6)}" ]; then echo 'this week'
    else echo later; fi
}
rem_hm() { _rhm=${1#????????}; printf '%s:%s' "${_rhm%??}" "${_rhm#??}"; }   # rem_hm START -> HH:MM
rem_column() {   # rem_column START GROUP -> the column: 17:00, Fri 20:00, Tue 27 10:00, Tue 3 Nov 16:30
    _d=${1%????}; _e=$(date -d "$_d" +%s 2>/dev/null || date -j -f %Y%m%d%H%M "${_d}1200" +%s 2>/dev/null) || { rem_hm "$1"; return; }
    case $2 in
        due|today|tomorrow) rem_hm "$1" ;;
        'this week') echo "$(LC_ALL=C when_of "$_e" %a) $(rem_hm "$1")" ;;
        *) if [ "${_d%??}" = "$(date +%Y%m)" ]; then echo "$(LC_ALL=C when_of "$_e" '%a %d' | sed 's/ 0/ /') $(rem_hm "$1")"
           else echo "$(LC_ALL=C when_of "$_e" '%a %d %b' | sed 's/ 0/ /') $(rem_hm "$1")"; fi ;;
    esac
}
rem_reorder() {   # rem_reorder WORDS -> "DAY TIME WORDS" when the day and the time come last ("gym at 6pm"); false when they do not
    printf '%s\n' "$1" | awk '
        function isday(w) { w = tolower(w); return w ~ /^(today|tomorrow|mon|monday|tue|tuesday|wed|wednesday|thu|thursday|fri|friday|sat|saturday|sun|sunday)$/ || w ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
        function istime(w) { w = tolower(w); return w ~ /^[0-9][0-9]?(:[0-5][0-9])?(am|pm)?$/ }
        { n = split($0, t, " "); day = ""; tm = ""; at = 0; e = n
          if (e > 0 && isday(t[e])) { day = t[e]; e-- }
          if (e > 0 && istime(t[e])) { tm = t[e]; e--; if (e > 0 && tolower(t[e]) == "at") { at = 1; e-- } }
          if (day == "" && e > 0 && isday(t[e])) { day = t[e]; e--; if (e > 0 && tolower(t[e]) == "on") e-- }
          if (tm == "" || e < 1) exit 1
          if (tm ~ /^[0-9]+$/) { if (!at) exit 1; tm = tm ":00" }   # a bare number is a time only after "at"
          w = t[1]; for (i = 2; i <= e; i++) w = w " " t[i]
          print (day == "" ? "" : day " ") tm " " w }'
}
rem_in() {   # rem_in N UNIT -> the minutes "in N UNIT" says (minutes or hours, an or a for one), or false
    case $1 in a|an) _n=1 ;; [1-9]|[1-9][0-9]|[1-9][0-9][0-9]) _n=$1 ;; *) return 1 ;; esac
    case $(printf '%s' "$2" | tr 'A-Z' 'a-z') in min|mins|minute|minutes|m) echo "$_n" ;; h|hr|hrs|hour|hours) echo $((_n * 60)) ;; *) return 1 ;; esac
}
rem_parse() {   # rem_parse WORDS -> START<tab>TEXT from a day, a time and the words in either order, or "in N minutes|hours"; false with no time
    set -f
    # shellcheck disable=SC2046   # the words, split on purpose; no glob
    set -- $1
    set +f
    case $(printf '%s %s' "${1:-}" "${2:-}" | tr 'A-Z' 'a-z') in 'remind me') shift 2 ;; esac
    _mins=''
    if [ "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" = in ] && [ $# -ge 4 ] && _mins=$(rem_in "$2" "$3"); then shift 3
    else   # the words, then "in N UNIT" at their end
        _tl=$(printf '%s' "$*" | sed -n 's/^\(.*[^ ]\)  *[Ii][Nn]  *\([^ ]*\)  *\([^ ]*\)$/\2 \3	\1/p')
        if [ -n "$_tl" ] && _mins=$(rem_in "${_tl%% *}" "$(printf '%s' "${_tl%%"$TAB"*}" | cut -d' ' -f2)"); then
            set -f
            # shellcheck disable=SC2046   # the words before "in N UNIT", split on purpose; no glob
            set -- $(printf '%s' "${_tl#*"$TAB"}")
            set +f
        fi
    fi
    if [ -n "$_mins" ]; then   # from now, rounded up to the minute
        [ "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" != to ] || shift
        [ $# -gt 0 ] || return 1
        _e=$(( $(date +%s) + _mins * 60 + 59 )); _e=$((_e - _e % 60))
        printf '%s	%s
' "$(when_of "$_e" %Y%m%d%H%M)" "$*"; return 0
    fi
    # the day and the time said last: put first
    case $(printf '%s' "${1:-}" | tr 'A-Z' 'a-z') in
        today|tomorrow|mon|monday|tue|tuesday|wed|wednesday|thu|thursday|fri|friday|sat|saturday|sun|sunday|[0-9]*) ;;
        *) if _ro=$(rem_reorder "$*"); then
               set -f
               # shellcheck disable=SC2046   # the reordered words, split on purpose; no glob
               set -- $(printf '%s' "$_ro")
               set +f
           fi ;;
    esac
    printf '%s' "$*" > "$TMP/rem.w"
    set -f
    # shellcheck disable=SC2046   # the words, split on purpose; no glob
    set -- $(cat "$TMP/rem.w")
    set +f
    _off=0; _date=''; _wd=''; _dayless=1   # no day said: today, or tomorrow once today's time has passed
    _w1=$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')
    case $_w1 in
        today) shift; _dayless='' ;;
        tomorrow) _off=1; shift; _dayless='' ;;
        mon|monday|tue|tuesday|wed|wednesday|thu|thursday|fri|friday|sat|saturday|sun|sunday)
            _wd=$(printf '%s' "$_w1" | cut -c1-3 | awk '{print toupper(substr($0,1,1)) substr($0,2)}'); _i=0
            while [ "$_i" -le 6 ]; do [ "$(LC_ALL=C date -d "+$_i days" +%a 2>/dev/null || LC_ALL=C date -v+"$_i"d +%a 2>/dev/null)" != "$_wd" ] || break; _i=$((_i + 1)); done
            _off=$_i; shift; _dayless='' ;;
        [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9])
            _date=$(printf '%s' "$_w1" | tr -d -)
            [ "$(date -d "$_w1" +%Y%m%d 2>/dev/null || date -j -f %Y%m%d%H%M "${_date}1200" +%Y%m%d 2>/dev/null)" = "$_date" ] || return 1   # a day the calendar has
            shift; _dayless='' ;;
    esac
    [ "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" != at ] || shift
    _t=$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z'); _h=''; _m=00
    case $_t in
        [0-9]:[0-5][0-9]|[0-2][0-9]:[0-5][0-9]) _h=${_t%%:*}; _m=${_t#*:} ;;
        [0-9]pm|1[0-2]pm|[0-9]am|1[0-2]am) _h=${_t%??}; [ "${_t#"$_h"}" = am ] || [ "$_h" = 12 ] || _h=$((_h + 12)); [ "${_t#"$_h"}" != am ] || [ "$_h" != 12 ] || _h=0 ;;
        [0-9]:[0-5][0-9]pm|1[0-2]:[0-5][0-9]pm|[0-9]:[0-5][0-9]am|1[0-2]:[0-5][0-9]am)
            _h=${_t%%:*}; _m=$(printf '%s' "${_t#*:}" | cut -c1-2); case $_t in *pm) [ "$_h" = 12 ] || _h=$((_h + 12)) ;; *am) [ "$_h" != 12 ] || _h=0 ;; esac ;;
    esac
    _h=$(printf '%s' "$_h" | sed 's/^0\([0-9]\)$/\1/')   # 09 is no octal: nine
    [ -n "$_h" ] && [ "$_h" -le 23 ] 2>/dev/null || return 1
    shift
    [ "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" != to ] || shift
    [ $# -gt 0 ] || return 1
    [ -n "$_date" ] || _date=$(rem_day "$_off")
    _st=$(printf '%s%02d%s' "$_date" "$_h" "$_m")
    if [ -n "$_dayless" ] && [ "$_st" -le "$(date +%Y%m%d%H%M)" ]; then _st=$(printf '%s%02d%s' "$(rem_day 1)" "$_h" "$_m"); fi   # a time gone today: tomorrow
    if [ -n "$_wd" ] && [ "$_st" -le "$(date +%Y%m%d%H%M)" ]; then _st=$(printf '%s%02d%s' "$(rem_day $((_off + 7)))" "$_h" "$_m"); fi   # the weekday's time gone: next week
    printf '%s\t%s\n' "$_st" "$*"
}
ics_text() { printf '%s' "$1" | awk '{ o = ""; for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); o = o ((c == "\\" || c == "," || c == ";") ? "\\" c : c) } printf "%s", o }'; }   # ics_text WORDS -> a TEXT value (RFC 5545 3.3.11): backslash, comma and semicolon escaped; awk, as BSD sed drops the backslash before ;
rem_forget() { _rfc=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; rm -f "${_rfc:-$STATE_DIR}/reminders.list"; }
rem_write() {   # rem_write FILE UID START SUMMARY -- one event with its alarm at its time, CRLF lines
    _st="$(printf '%s' "$3" | cut -c1-8)T$(printf '%s' "$3" | cut -c9-12)00"
    printf 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//forgewright-ai//spark-shell//EN\r\nBEGIN:VEVENT\r\nUID:%s\r\nDTSTAMP:%s\r\nDTSTART:%s\r\nDURATION:PT10M\r\nSUMMARY:%s\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:%s\r\nTRIGGER:PT0M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' \
        "$2" "$(TZ=UTC0 date +%Y%m%dT%H%M%SZ)" "$_st" "$(ics_text "$4")" "$(ics_text "$4")" > "$1.new" && mv "$1.new" "$1" || return 1
    rem_forget   # resolution by UID may have cached the old event in this same second
}
rem_match() {   # rem_match ID -> the line by UID or unique title
    awk -F '\t' -v n="$(panel_lower "$1")" -v id="$1" '
        { if ($2 == id) { exact=$0; ne++ }; if (tolower($3) == n) { title=$0; nt++ } }
        END { if (ne == 1) print exact; else if (ne > 1) exit 2;
              else if (id ~ /^spark-shell-/ || index(id,"@")) exit 1;
              else if (nt == 1) print title; else if (nt > 1) exit 2; else exit 1 }'
}
rem_find() { rem_list | rem_match "$1"; }   # rem_find NAME|UID -> one line
rem_time_check() {   # rem_time_check START [TEXT] -> 0 when the local time is unambiguous
    command -v python3 >/dev/null 2>&1 || { echo 'Reminders need Python 3 to verify the local time before saving.'; return 1; }
    if _rtc=$(python3 "$REPO/lib/reminders.py" "$1" "${2:-}" 2>/dev/null) && [ "$_rtc" = ok ]; then return 0; fi
    printf '%s\n' "${_rtc:-The local time could not be verified; check the time settings before saving.}"
    return 1
}
rem_said() {   # rem_said START -> today 18:30, tomorrow 09:00, Fri 20:00, Tue 3 Nov 16:30
    _g=$(rem_group "$1" "$(date +%Y%m%d%H%M)")
    case $_g in due|today) echo "today $(rem_hm "$1")" ;; tomorrow) echo "tomorrow $(rem_hm "$1")" ;; *) rem_column "$1" "$_g" ;; esac
}
rem_ours() {   # rem_ours LINE -> 0 when spark-shell wrote that event (its uid, alone in its file)
    _rof=${1#*"$TAB"}; case ${_rof%%"$TAB"*} in spark-shell-*) ;; *) return 1 ;; esac
    _rof=${_rof#*"$TAB"}; _rof=${_rof#*"$TAB"}
    [ "$(grep -c '^BEGIN:VEVENT' "${_rof%%"$TAB"*}")" = 1 ]
}
REM_DONE_DAYS=30   # a reminder done is kept this long in ~/calendar/done for undo
rem_restore() {   # rem_restore NAME|UID -> the reminder back from done, or from the provider's keep of deletes (REM_DELETED)
    _rrd=''; [ -z "${REM_DELETED:-}" ] || [ ! -d "$REM_DELETED" ] || _rrd=$( ( CAL_DIR=$REM_DELETED; rem_all ) | rem_match "$1" 2>/dev/null) || :
    [ -n "$_rrd" ] || [ -d "$CAL_DIR/done" ] || { echo "no reminder done to bring back"; return 1; }
    _rr=$_rrd; [ -n "$_rr" ] || _rr=$( ( CAL_DIR=$CAL_DIR/done; rem_all ) | rem_match "$1") || { echo "no unique reminder done named $1; use its UID"; return 1; }
    rem_ours "$_rr" || { echo 'another calendar owns that event'; return 1; }
    _rp=$(printf '%s' "$_rr" | cut -f4); _rf=${_rp##*/}; _rt=$(printf '%s' "$_rr" | cut -f3)
    [ ! -e "$CAL_DIR/$_rf" ] && [ ! -L "$CAL_DIR/$_rf" ] || { echo "$_rt is in your reminders already"; return 1; }
    mv "$_rp" "$CAL_DIR/$_rf" || { echo "could not bring $_rt back"; return 1; }
    rem_effect "$(printf '%s' "$_rr" | cut -f2)" restored
    bar_redraw; echo "$_rt is back"
}
rem_act() {   # rem_act add|done|snooze|restore ARG
    rem_forget
    case $1 in
        add) _p=$(rem_parse "$2") || { echo "a reminder takes a day and a time, then the words (tomorrow 09:00 call the dentist), a time alone for today or else tomorrow (5pm gym), or a while from now (gym in 10 minutes)"; return 1; }
            _s=${_p%%"$TAB"*}; _t=${_p#*"$TAB"}
            rem_time_check "$_s" "$_t" || return 1
            [ "$_s" -gt "$(date +%Y%m%d%H%M)" ] || { echo "$(rem_said "$_s") has passed: say a time to come"; return 1; }
            _rd=$(rem_list | awk -F '\t' -v s="$_s" -v t="$(panel_lower "$_t")" '$1 == s && tolower($3) == t { print $3; exit }'); [ -z "$_rd" ] || { echo "$(rem_said "$_s") $_rd is a reminder already"; return 1; }   # the same words at the same minute: once
            _u=$(python3 "$REPO/lib/reminders.py" --uid 2>/dev/null) || { echo 'could not create a private reminder identity; nothing saved'; return 1; }
            [ "${#_u}" = 48 ] && printf '%s\n' "$_u" | LC_ALL=C grep -Eq '^spark-shell-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' || { echo 'could not create a private reminder identity; nothing saved'; return 1; }
            mkdir_private "$CAL_DIR"
            _rb=$CAL_DIR/$(date +%s)-$$; _f=$_rb.ics; _rn=2
            while [ -e "$_f" ] || [ -L "$_f" ]; do _f=$_rb-$_rn.ics; _rn=$((_rn + 1)); done
            rem_write "$_f" "$_u" "$_s" "$_t" || { rm -f "$_f.new"; echo "could not write the reminder in ${CAL_DIR#"$HOME"/}"; return 1; }
            rem_effect "$_u"
            bar_redraw; echo "reminder $(rem_said "$_s") $_t" ;;
        done|snooze|delete) _l=$(rem_find "$2") || { echo "no unique reminder named $2; select it in Calendar"; return 1; }
            _t=$(printf '%s' "$_l" | cut -f3)
            rem_ours "$_l" || { echo "$_t is an event another calendar wrote: change it there"; return 1; }
            if [ "$1" = delete ]; then   # REM_DELETED: the provider's keep, so undo brings it back
                _f=$(printf '%s' "$_l" | cut -f4)
                if [ -n "${REM_DELETED:-}" ]; then mkdir -p "$REM_DELETED" && mv "$_f" "$REM_DELETED/${_f##*/}" || { echo "could not delete $_t"; return 1; }
                else rm -f "$_f" || { echo "could not delete $_t"; return 1; }; fi
                rem_effect "$(printf '%s' "$_l" | cut -f2)" deleted "${REM_DELETED:-}"
                bar_redraw; echo "deleted: $_t"; return 0
            fi
            if [ "$1" = 'done' ]; then   # put aside for REM_DONE_DAYS
                mkdir -p "$CAL_DIR/done"; _f=$(printf '%s' "$_l" | cut -f4)
                [ ! -e "$CAL_DIR/done/${_f##*/}" ] && [ ! -L "$CAL_DIR/done/${_f##*/}" ] || { echo "could not mark $_t done: that saved filename is already in use"; return 1; }
                mv "$_f" "$CAL_DIR/done/" && touch "$CAL_DIR/done/${_f##*/}" || { echo "could not mark $_t done"; return 1; }
                find "$CAL_DIR/done" -name '*.ics' -mtime +"$REM_DONE_DAYS" -exec rm -f {} + 2>/dev/null || :
                rem_effect "$(printf '%s' "$_l" | cut -f2)" 'done' "$CAL_DIR/done"
                bar_redraw; echo "done: $_t"; return 0
            fi
            _e=$(( $(date +%s) + 600 )); _s=$(when_of "$_e" %Y%m%d%H%M)
            rem_time_check "$_s" || return 1
            rem_write "$(printf '%s' "$_l" | cut -f4)" "$(printf '%s' "$_l" | cut -f2)" "$_s" "$_t" || { echo "could not move the reminder; check its time before trying again"; return 1; }
            rem_effect "$(printf '%s' "$_l" | cut -f2)" rescheduled
            bar_redraw; echo "$_t again at $(rem_hm "$_s")" ;;
        restore) rem_restore "$2" ;;
        *) echo "$1 is not something reminders does"; return 1 ;;
    esac
}
rem_effect() {   # rem_effect UID [OPERATION [DIR]] -- the effect record for the provider, from the event as saved
    [ -n "${PROVIDE_EFFECT:-}" ] || return 0
    if [ "${2:-}" = deleted ] && [ -z "${3:-}" ]; then jq -cn --arg id "$1" '{kind: "reminder", operation: "deleted", id: $id, title: ""}' > "$TMP/action.effect"; return 0; fi
    ( [ -z "${3:-}" ] || CAL_DIR=$3; rem_all ) | jq -Rsc --arg id "$1" --arg operation "${2:-created}" 'split("\n") | map(split("\t")) | map(select(.[1] == $id)) | first |
        if . == null then empty else {kind: "reminder", operation: $operation, id: .[1], title: .[2],
        localTime: (.[0] | "\(.[0:4])-\(.[4:6])-\(.[6:8]) \(.[8:10]):\(.[10:12])")} end' > "$TMP/action.effect"
}
rem_due() {   # -> UID<tab>SUMMARY of the latest reminder due, and one chime when any is due for the first time
    _now=$(date +%Y%m%d%H%M)
    rem_list | awk -F '\t' -v n="$_now" '$1 <= n' > "$TMP/rem.due"
    mkdir_private "$STATE_DIR"; touch "$REM_FIRED"
    awk -F '\t' '{print $2 " " $1}' "$TMP/rem.due" > "$TMP/rem.keys"
    [ -z "$(find "$REM_FIRED.lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] || lock_drop "$REM_FIRED.lock"   # a lock left by a pass that was killed
    # REM_LOOK: a look (check, status) rings nothing and marks nothing
    if [ -z "${REM_LOOK:-}" ] && lock_take "$REM_FIRED.lock"; then   # the bar and the tmux line both ask: one at a time, so the chime plays once
        _new=$(grep -vxF -f "$REM_FIRED" "$TMP/rem.keys" | grep -c . || :)
        cp "$TMP/rem.keys" "$REM_FIRED"   # the ones due now, and no more: the file never grows
        lock_drop "$REM_FIRED.lock"
        [ "${_new:-0}" -eq 0 ] || [ -n "${SPARK_SHELL_NO_CHIME:-}" ] || rem_chime
        [ "${_new:-0}" -eq 0 ] || notify_send x-spark-shell.reminder "$(tail -1 "$TMP/rem.due" | cut -f3)" "due now"
    fi
    [ -s "$TMP/rem.due" ] || return 0
    tail -1 "$TMP/rem.due" | cut -f2,3
}
rem_chime() {   # the short sound once, not waited for: PipeWire, else ALSA, else afplay (macOS)
    [ -r "$REM_CHIME" ] || return 0
    if command -v pw-play >/dev/null 2>&1; then ( pw-play --volume 0.6 "$REM_CHIME" >/dev/null 2>&1 & ) 3>&- 4<&- 5>&-
    elif command -v aplay >/dev/null 2>&1; then ( aplay -q "$REM_CHIME" >/dev/null 2>&1 & ) 3>&- 4<&- 5>&-
    elif command -v afplay >/dev/null 2>&1; then ( afplay -v 0.6 "$REM_CHIME" >/dev/null 2>&1 & ) 3>&- 4<&- 5>&-; fi
}
rem_due_line() {   # -> "due: WORDS  " for tmux's status line while a reminder is due, else nothing
    _dl=$(rem_due 2>/dev/null || :); [ -n "$_dl" ] || return 0
    printf 'due: %s  ' "$(printf '%s' "${_dl#*"$TAB"}" | tr -d '#' | cut_chars 28)"   # no # for tmux to read as a format
}

# --- printers
printer_status_now() { python3 "$REPO/lib/printers.py" status; }
printer_status() { panel_cache printers.status 10 printer_status_now; }   # ten seconds: CUPS is slow to ask, and a step forgets it
