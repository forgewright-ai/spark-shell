# shellcheck extended-analysis=false
# --- undo: the step and its journal
# reads: ANIMATION_NAMES BAR_FULL BAR_SYS CONFIG FONT_FACES GLYPH_FAMILIES KEPT_LAYOUTS LAYOUTS_DIR LAYOUT_LAST MODE OS ROOT TAB TMP US WALL_NAMES WORDS_TAKE YES
panel_inverse() {   # panel_inverse SECTION ACTION [ARG] -> "ACTION ARG<tab>WORDS" that takes the step back, or nothing
    _p=$1; _a=$2; shift 2; _arg=$*
    case $_p:$_a in
        display:scale|display:mode|display:position|display:place|display:transform|display:screen-on|display:screen-off)
            _name=${_arg%% *}; _row=$(screen_find "$_name"); [ -n "$_row" ] || return 0
            _name=$(printf '%s' "$_row" | cut -f1)
            case $_a in
                scale) _back="scale $_name scale=$(printf '%s' "$_row" | cut -f5)" ;;
                transform) _back="transform $_name transform=$(printf '%s' "$_row" | cut -f11)"; [ -n "${_back##* transform=}" ] || _back="transform $_name transform=normal" ;;
                mode) _mode=$(printf '%s' "$_row" | cut -f4); [ -n "$_mode" ] || return 0; _back="mode $_name mode=$_mode" ;;
                position|place) _back="position $_name x=$(printf '%s' "$_row" | cut -f6) y=$(printf '%s' "$_row" | cut -f7)" ;;
                *) _back="screen-$(printf '%s' "$_row" | cut -f3) $_name" ;;
            esac
            printf '%s\t%s restored\n' "$_back" "$_name" ;;
        layout:save) _n=$(layout_name_of "$_arg"); [ -z "$_n" ] || [ -e "$LAYOUTS_DIR/$_n" ] || printf 'delete %s\t%s deleted again\n' "$_n" "$_n" ;;
        layout:delete) [ ! -f "$LAYOUTS_DIR/$_arg" ] || printf 'restore %s\t%s is back\n' "$_arg" "$_arg" ;;
        layout:rename) _n=$(layout_name_of "${_arg#* to=}"); [ -z "$_n" ] || printf 'rename %s to=%s\t%s has its name again\n' "$_n" "${_arg%% *}" "${_arg%% *}" ;;
        clock:format) printf 'format %s\tclock format restored\n' "$(time_pref CLOCK_FORMAT 24)" ;;
        clock:week) printf 'week %s\tfirst weekday restored\n' "$(time_pref WEEK_START sunday)" ;;
        clock:zone) _z=$(time_zone); time_zone_valid "$_z" && printf 'zone %s\ttime zone restored\n' "$_z" ;;
        pointer:*|keyboard:repeat-delay|keyboard:repeat-rate|keyboard:caps)
            input_spec "$_p" "$_a" || return 0
            eval "_old=\$$input_key"
            printf '%s %s\t%s %s %s\n' "$_a" "$_old" "$_p" "$_a" "$_old" ;;
        out:mute|mic:mute|out:unmute|mic:unmute) SND=${SND:-$(snd_tool)}; if [ "$_p" = out ]; then _mu=$(snd_out | sed -n 3p); else _mu=$(snd_mic | sed -n 3p); fi
            case $_a:$_mu in mute:0) printf 'unmute\t%s unmute\n' "$_p" ;; unmute:1) printf 'mute\t%s mute\n' "$_p" ;; esac ;;   # already as asked: no inverse, so the undo before it stays
        out:level|mic:level|out:adjust|mic:adjust) if [ "$_p" = out ]; then _lv=$(snd_out | sed -n 2p); else _lv=$(snd_mic | sed -n 4p); fi
            case $_lv in ''|-) ;; *) printf 'level %s\t%s at %s%%\n' "$_lv" "$_p" "$_lv" ;; esac ;;
        out:use|mic:use) _cur=$(snd_devices "$_p" | awk -F '\t' '$2 == 1 && !d {print $1; d = 1}'); [ -z "$_cur" ] || printf 'use %s\t%s %s\n' "$_cur" "$_p" "$_cur" ;;   # the whole list read: no broken pipe
        theme:text|theme:font) case $_arg in bigger) printf 'text smaller\ttext smaller\n' ;; smaller) printf 'text bigger\ttext bigger\n' ;; *) printf 'text %s\ttext %s\n' "$(look_font_size)" "$(look_font_size)" ;; esac ;;
        theme:alpha|theme:transparency|theme:see-through) printf 'alpha %s\ttransparency %s%%\n' "$ALPHA" "$(transparency_of "$ALPHA")" ;;
        theme:animation) printf 'animation %s\tanimation %s\n' "$(anim_now)" "$(anim_now)" ;;
        theme:glyphs) printf 'glyphs %s\tthe bar in %s\n' "$BAR_GLYPHS" "$BAR_GLYPHS" ;;
        theme:icons) printf 'icons %s\tapp icons %s\n' "$DIALOG_ICONS" "$DIALOG_ICONS" ;;
        theme:spacing) printf 'spacing %s\tapp spacing %s\n' "$DIALOG_SPACING" "$DIALOG_SPACING" ;;
        theme:family) printf 'family %s\tglyph family %s\n' "$GLYPH_FAMILY" "$GLYPH_FAMILY" ;;
        theme:face) _fw=$(face_word "${FONT%%:*}") && printf 'face %s\ttext in %s\n' "$_fw" "$_fw" ;;   # a face of your own: no inverse
        theme:motion) printf 'motion %s\tmoving wallpaper %s\n' "$WALLPAPER_MOTION" "$WALLPAPER_MOTION" ;;
        window:close|window:focus|window:capture|window:restore) ;;   # no inverse
        window:move) _n=$(win_facts | jq -r --argjson i "${_arg%% *}" '.windows[] | select(.id == $i) | .ws'); [ -z "$_n" ] || [ "$_n" -lt 1 ] || printf 'move %s to=%s\tback on workspace %s\n' "${_arg%% *}" "$_n" "$_n" ;;
        window:place) _n=$(win_facts | jq -r --argjson i "${_arg%% *}" '.windows[] | select(.id == $i) | .placed | if . == "full screen" then "full" else . end'); [ -z "$_n" ] || printf 'place %s how=%s\tas it was\n' "${_arg%% *}" "$_n" ;;
        window:*) _n=$(win_now); printf 'restore %s now=%s\twindows %s\n' "${WINDOWS:-split}" "$_n" "$(win_said "$_n")" ;;
        bar:off) printf 'on\tbar shown\n' ;;
        bar:on) printf 'off\tbar hidden\n' ;;
        bar:top|bar:bottom) case $(bar_place) in hidden) printf 'off\tbar hidden\n' ;; *) printf '%s\tbar %s\n' "$BAR_POSITION" "$(bar_place_words "$BAR_POSITION")" ;; esac ;;
        bar:text) printf 'text %s\tbar text %s\n' "$BAR_TEXT" "$BAR_TEXT" ;;
        bar:tray) if [ "$BAR_TRAY" = yes ]; then printf 'tray on\ttray on\n'; else printf 'tray off\ttray off\n'; fi ;;
        theme:wallpaper|theme:wallpaper-picture|theme:wallpaper-color) _cur=$(wall_name); if [ -n "$_cur" ]; then printf 'wallpaper %s\twallpaper %s\n' "$_cur" "$_cur"; else printf 'wallpaper-picture %s\twallpaper %s\n' "$WALLPAPER" "${WALLPAPER##*/}"; fi ;;
        theme:theme) printf '%s\ttheme %s\n' "${THEME:-none}" "${THEME:-none}" ;;
        theme:delete) ;;   # no inverse
        theme:*) printf '%s\ttheme %s\n' "${THEME:-none}" "${THEME:-none}" ;;
        wifi:connect|wifi:hidden) _c=$(wifi_connected); if [ -n "$_c" ]; then printf 'connect %s\twifi %s\n' "$_c" "$_c"; else printf 'disconnect\twifi off\n'; fi ;;
        wifi:disconnect) _c=$(wifi_connected); [ -z "$_c" ] || printf 'connect %s\twifi %s\n' "$_c" "$_c" ;;
        printers:default) _pd=$(printer_status_now | jq -r '.default // empty'); [ -z "$_pd" ] || [ "$_pd" = "$_arg" ] || printf 'default %s\tprevious default printer restored\n' "$_pd" ;;
        printers:pause|printers:resume)
            _pe=$(printer_status_now | jq -r --arg n "$_arg" '.queues[] | select(.name == $n) | .enabled')
            case $_a:$_pe in pause:true) printf 'resume %s\tprinter enabled\n' "$_arg" ;; resume:false) printf 'pause %s\tprinter paused\n' "$_arg" ;; esac ;;
        bt:connect) bt_list | awk -F '\t' -v d="$_arg" '($1 == d || $2 == d) && $4 == 1 { f = 1 } END { exit !f }' \
            || printf 'disconnect %s\tbt %s off\n' "$_arg" "$_arg" ;;   # connected already: no inverse
        bt:disconnect) printf 'connect %s\tbt %s\n' "$_arg" "$_arg" ;;
        bt:power) if [ "$_arg" = off ]; then printf 'power on\tbt on\n'; else printf 'power off\tbt off\n'; fi ;;
        notifications:do-not-disturb) _nd=off; ! notify_dnd || _nd=on; [ "$_nd" = "$_arg" ] || printf 'do-not-disturb %s\tdo not disturb %s\n' "$_nd" "$_nd" ;;   # already as asked: no inverse
        storage:mount|storage:unmount) storage_list > "$TMP/storage.l"; _im=$(storage_find fs "$_arg" | cut -d "$US" -f5)
            case $_a:$_im in mount:) printf 'unmount %s\t%s unmounted\n' "$_arg" "$_arg" ;; unmount:?*) printf 'mount %s\t%s mounted\n' "$_arg" "$_arg" ;; esac ;;
        reminders:done|reminders:delete) _rl=$(rem_find "$_arg"); [ -z "$_rl" ] || printf 'restore %s\treminder %s\n' "$(printf '%s' "$_rl" | cut -f2)" "$(printf '%s' "$_rl" | cut -f3)" ;;   # by its uid, not by name
    esac
}
panel_step() {   # panel_step SECTION ACTION [ARG] -> panel_act's line; a step done is remembered as recent, its inverse kept for undo
    if [ -n "${PANEL_INV_READ:-}" ]; then _inv=$PANEL_INV; else _inv=$(panel_inverse "$@"); fi   # read once by a host's call
    rm -f "$TMP/network.undo" "$TMP/sound.undo"
    if panel_act "$@"; then
        if [ -s "$TMP/network.undo" ]; then _inv="restore $(cat "$TMP/network.undo")$TAB network settings restored"; fi
        if [ -s "$TMP/sound.undo" ]; then _snd_old=$(cat "$TMP/sound.undo"); _inv="level $_snd_old$TAB$1 at $_snd_old%"; fi
        [ "${PANEL_JOURNAL:-}" != off ] || return 0   # a host's step: no recent pick, no journal
        case $2 in show|all|pick|chat|more|save|close|focus) ;; *) panel_recent_add "$1" "$(printf '%s' "$2${3:+ $3}${4:+ $4}${5:+ $5}" | sed 's/ *$//')" ;; esac
        [ -z "$_inv" ] || printf '%s\t%s\n' "$1" "$_inv" >> "$TMP/group"
        return 0
    fi
    return 1
}
bat_dir() { for b in "$BAR_SYS"/class/power_supply/*; do [ -f "$b/capacity" ] && { [ ! -f "$b/type" ] || [ "$(cat "$b/type")" = Battery ]; } && { echo "$b"; return; }; done; }
bat_num() { cat "$(bat_dir)/$1" 2>/dev/null || :; }
bat_left() {   # -> "H:MM left" or "H:MM to full"; nothing when it cannot tell
    if [ "$OS" = Darwin ]; then
        mac_battery | awk -F '\t' '$3 != "" {if ($2 == "charging") print $3 " to full"; else if ($2 == "discharging") print $3 " left"}'
        return
    fi
    _d=$(bat_dir); [ -n "$_d" ] || return 0
    _now=$(bat_num energy_now); _full=$(bat_num energy_full); _rate=$(bat_num power_now)
    [ -n "$_now" ] || { _now=$(bat_num charge_now); _full=$(bat_num charge_full); _rate=$(bat_num current_now); }
    [ -n "$_now" ] && [ -n "$_rate" ] && [ "$_rate" -gt 0 ] 2>/dev/null || return 0
    case $(bat_num status) in
        Discharging) _m=$(( _now * 60 / _rate )); printf '%d:%02d left\n' $((_m / 60)) $((_m % 60)) ;;
        Charging) [ -n "$_full" ] && [ "$_full" -gt "$_now" ] || return 0; _m=$(( (_full - _now) * 60 / _rate )); printf '%d:%02d to full\n' $((_m / 60)) $((_m % 60)) ;;
    esac
}
time_pref() {   # KEY DEFAULT -> the config value, never sourced
    _pref=$(awk -F= -v k="$1" '$1 == k {v=substr($0,index($0,"=")+1)} END {print v}' "$CONFIG" 2>/dev/null) || _pref=''
    case $1:$_pref in CLOCK_FORMAT:12|CLOCK_FORMAT:24|WEEK_START:sunday|WEEK_START:monday) printf '%s' "$_pref" ;; *) printf '%s' "$2" ;; esac
}
clock_text() { if [ "$(time_pref CLOCK_FORMAT "${CLOCK_FORMAT:-24}")" = 12 ]; then date '+%I:%M %p' | sed 's/^0//'; else date '+%H:%M'; fi; }
time_zone() {
    _zone=$(readlink "$ROOT/etc/localtime" 2>/dev/null || :)
    case $_zone in */zoneinfo/*) printf '%s\n' "${_zone#*/zoneinfo/}" ;; *) if command -v timedatectl >/dev/null 2>&1; then timedatectl show -p Timezone --value 2>/dev/null || date +%Z; else date +%Z; fi ;; esac
}
time_zone_valid() {
    case $1 in ''|/*|*..*|*[!A-Za-z0-9_+/-]*) return 1 ;; esac
    [ -f "$ROOT/usr/share/zoneinfo/$1" ] && [ "$(head -c 4 "$ROOT/usr/share/zoneinfo/$1")" = TZif ]
}
time_valid() {
    case $1:$2 in format:12|format:24|week:sunday|week:monday) return 0 ;; zone:*) [ "$OS" != Darwin ] && time_zone_valid "$2" ;; *) return 1 ;; esac
}
time_sync() { panel_cache time_sync 60 time_sync_probe; }   # once a minute: a probe can wait on the network
time_sync_probe() {
    if command -v timedatectl >/dev/null 2>&1; then
        _sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || :)
        case $_sync in yes) echo 'clock synced'; return ;; no) echo 'clock not synced'; return ;; esac
    fi
    if command -v chronyc >/dev/null 2>&1; then
        _sync=$(LC_ALL=C chronyc -n tracking 2>/dev/null || :)   # -n: no name lookup of the reference server, which can hang 5 s
        if printf '%s\n' "$_sync" | grep -q '^Leap status'; then
            if printf '%s\n' "$_sync" | grep -qE '^Leap status *: Normal'; then echo 'clock synced by chrony'; else echo 'clock not synced by chrony'; fi; return
        fi
    fi
    if command -v ntpctl >/dev/null 2>&1; then
        _sync=$(LC_ALL=C ntpctl -s status 2>/dev/null || :)
        case $_sync in *'clock synced'*) echo 'clock synced by ntpd'; return ;; *'clock unsynced'*) echo 'clock not synced by ntpd'; return ;; esac
    fi
    if command -v ntpq >/dev/null 2>&1; then
        _sync=$(LC_ALL=C ntpq -pn 2>/dev/null || :)
        if printf '%s\n' "$_sync" | grep -q '^\*'; then echo 'clock synced by ntpd'; return; fi
        [ -z "$_sync" ] || { echo 'clock not synced by ntpd'; return; }
    fi
    echo 'clock sync is not reported'
}
time_setting() {
    time_valid "$1" "$2" || { echo "invalid time $1: $2"; return 1; }
    if [ "$MODE" = dry ]; then echo "would set time $1 $2"; return; fi
    case $1 in
        format) config_set CLOCK_FORMAT "$2" ;;
        week) config_set WEEK_START "$2" ;;
        zone)
            root_can || { echo 'changing the time zone needs system permission: run spark-shell desktop time zone at a terminal'; return 1; }
            if [ "$(init_shape)" = systemd ] && command -v timedatectl >/dev/null 2>&1; then
                root_do timedatectl set-timezone "$2" || return 1
            else root_do ln -sfn "$ROOT/usr/share/zoneinfo/$2" "$ROOT/etc/localtime" || return 1; fi ;;
    esac
    bar_redraw
    echo "time $1 $2"
}
layout_time() {
    case ${1:-} in
        '') printf 'zone %s\nformat %s\nweek %s\n%s\n' "$(time_zone)" "$(time_pref CLOCK_FORMAT 24)" "$(time_pref WEEK_START sunday)" "$(time_sync)" ;;
        format|week|zone)
            [ "$#" = 2 ] || refuse "time $1 takes one value"
            time_valid "$1" "$2" || refuse "invalid time $1: $2"
            if [ "$1" = zone ] && [ "$MODE" != dry ] && [ "$YES" != 1 ]; then
                step_yes "change the system time zone to $2" || refuse "time zone unchanged (use --yes to confirm)"
            fi
            time_setting "$1" "$2" ;;
        *) refuse "time takes format, week or zone" ;;
    esac
}

cal_rows() {   # cal_rows [MARK UNMARK] -> this month, 28 cells wide, today between MARK and UNMARK (awk: no cal, no GNU date needed)
    date '+%Y %m %d' | awk -v start="$(time_pref WEEK_START sunday)" -v mark="${1:-}" -v unmark="${2:-}" '{
        y = $1; m = $2 + 0; d = $3 + 0
        split("31 28 31 30 31 30 31 31 30 31 30 31", dim, " "); if ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) dim[2] = 29
        mm = m; yy = y; if (mm < 3) { mm += 12; yy-- }; k = yy % 100; j = int(yy / 100)
        h = (1 + int(13 * (mm + 1) / 5) + k + int(k / 4) + int(j / 4) + 5 * j) % 7; w = (h + 6) % 7
        split("January February March April May June July August September October November December", mon, " ")
        title = mon[m] " " y; pad = ""; for (i = 0; i < int((28 - length(title)) / 2); i++) pad = pad " "
        print pad title; if (start == "monday") {print " Mo  Tu  We  Th  Fr  Sa  Su"; w = (w + 6) % 7} else print " Su  Mo  Tu  We  Th  Fr  Sa"
        line = ""; for (i = 0; i < w; i++) line = line "    "
        for (day = 1; day <= dim[m]; day++) {
            cell = sprintf(" %2d ", day); if (day == d) cell = mark cell unmark
            line = line cell; w++; if (w == 7) { print line; line = ""; w = 0 } }
        if (line != "") print line }'
}
clock_digit() {   # clock_digit D -> five rows of a figure six cells wide in full blocks (D is 0-9; : is two cells wide)
    case $1 in
        0) printf '%s\n' '###' '# #' '# #' '# #' '###' ;;
        1) printf '%s\n' '  #' ' ##' '  #' '  #' '  #' ;;
        2) printf '%s\n' '###' '  #' '###' '#  ' '###' ;;
        3) printf '%s\n' '###' '  #' '###' '  #' '###' ;;
        4) printf '%s\n' '# #' '# #' '###' '  #' '  #' ;;
        5) printf '%s\n' '###' '#  ' '###' '  #' '###' ;;
        6) printf '%s\n' '###' '#  ' '###' '# #' '###' ;;
        7) printf '%s\n' '###' '  #' '  #' '  #' '  #' ;;
        8) printf '%s\n' '###' '# #' '###' '# #' '###' ;;
        9) printf '%s\n' '###' '# #' '###' '  #' '###' ;;
        :) printf '%s\n' ' ' '#' ' ' '#' ' ' ;;
    esac | sed "s/ /  /g; s/#/$BAR_FULL$BAR_FULL/g"
}
clock_rows() {   # -> the time, five rows tall and 34 cells wide, the figures two cells apart
    _t=$(clock_text | cut -d' ' -f1)
    for _r in 1 2 3 4 5; do
        _line=''; _k=0
        while [ "$_k" -lt ${#_t} ]; do
            _c=$(printf '%s' "$_t" | cut -c$((_k + 1))); _line="$_line${_line:+  }$(clock_digit "$_c" | sed -n "${_r}p")"; _k=$((_k + 1))
        done
        [ "$_r" != 5 ] || [ "$(time_pref CLOCK_FORMAT 24)" != 12 ] || _line="$_line $(date +%p)"
        printf '%s\n' "$_line"
    done
}
clock_view() {   # clock_view [MARK UNMARK] -> the time large on the left, this month on the right: one block, as tall as the month
    clock_rows > "$TMP/clock.time"; cal_rows "${1:-}${1:+$(printf '\033[7m')}" "${2:-}" > "$TMP/clock.month"
    _i=0
    while IFS= read -r _m; do
        _i=$((_i + 1)); _l=''
        [ "$_i" -lt 2 ] || [ "$_i" -gt 6 ] || _l=$(sed -n "$((_i - 1))p" "$TMP/clock.time")   # the time beside the week's names and the first four weeks
        if [ -n "$_l" ]; then printf '%s%s%s      %s\n' "${1:-}" "$_l" "${2:-}" "$_m"; else printf '%34s      %s\n' '' "$_m"; fi
    done < "$TMP/clock.month"
}
look_font_size() { case $FONT in *size=[0-9]*) _lfs=${FONT##*size=}; printf '%s' "${_lfs%%[!0-9]*}" ;; esac; }   # -> the size in FONT

# --- the gate
panel_gate() {   # panel_gate SECTION ACTION [ARG] -> the row's own ARG (exit 0), or why not (exit 1)
    [ "$1:$2" != theme:see-through ] || set -- theme transparency "${3:-}"   # synonym
    case $1:$2 in out:use|mic:use) SND=${SND:-$(snd_tool)}; if [ "$SND" = alsa ] && _tf=$(al_theirs); then echo "$(al_theirs_said "$_tf"): spark-shell leaves it to that file"; return 1; fi ;; esac   # your own ALSA file picks the device
    if ! panel_section_ok "$1" || [ "$1" = glance ] || [ "$1" = chat ]; then if [ -n "$1" ]; then echo "no $1 here"; else echo "a step with no section"; fi; return 1; fi
    case $1:$2 in
        display:scale|display:mode|display:position|display:place|display:transform|display:screen-on|display:screen-off|display:main)
            screen_action "$2" "${3:-}" check || return 1
            printf '%s\n' "$3"; return 0 ;;
        clock:format|clock:week|clock:zone)
            time_valid "$2" "${3:-}" || { echo "invalid time $2"; return 1; }
            echo "$3"; return 0 ;;
        pointer:*|keyboard:repeat-delay|keyboard:repeat-rate|keyboard:caps)
            if input_spec "$1" "$2" && input_valid "$input_key" "${3:-}"; then echo "$3"; return 0; fi
            echo "$1: invalid $2 value"; return 1 ;;
        lan:address|lan:auto|lan:dns|lan:restore|wifi:address|wifi:auto|wifi:dns|wifi:restore)
            if [ "$2" != restore ]; then
                case $1 in lan) _ifs=$(bar_wired) ;; wifi) _ifs=$(bar_wireless) ;; esac
                printf '%s\n' "$_ifs" | grep -qxF -- "${3%% *}" || { echo 'that interface is not here'; return 1; }
            fi
            network_action "$2" "${3:-}" check || return 1
            echo "$3"; return 0 ;;
        wifi:hidden)
            [ -n "${3:-}" ] && [ "$(printf '%s' "$3" | wc -c)" -le 32 ] && [ "$(printf '%s' "$3" | tr -d '\001-\037\177')" = "$3" ] || { echo 'a network name is 1 to 32 bytes, without control characters'; return 1; }
            echo "$3"; return 0 ;;
        spark:chat|undo:all|about:open|about:site) echo ''; return 0 ;;
        tools:*) tools_gate "$2" "${3:-}"; return ;;
        layout:save) [ -n "$3" ] && { echo "$3"; return 0; }; echo "layout: save takes a name"; return 1 ;;
        layout:add) _n=$(jq -r '.suggested // [] | .[]' "$LAYOUT_LAST" 2>/dev/null | awk -v w="$(panel_lower "$3")" 'tolower($0) == w && !d {print; d = 1}'); [ -n "$_n" ] && { echo "$_n"; return 0; }; echo "layout: $3 was not suggested for the last layout"; return 1 ;;
        apps:open) panel_apps_read "$TMP/apps.gate"   # the step opens from this list too: one read
            _n=$(panel_apps_names < "$TMP/apps.gate" | awk -v w="$(panel_lower "$3")" 'tolower($0) == w && !d {print; d = 1}'); [ -n "$_n" ] && { echo "$_n"; return 0; }
            rm -f "$TMP/apps.gate"; echo "apps: no app named $3 here"; return 1 ;;
        layout:open) _n=$(layout_name_of "$3"); if [ -n "$_n" ] && layout_kept_file "$_n" >/dev/null; then echo "$_n"; return 0; fi; echo "layout: no saved layout named $3"; return 1 ;;
        layout:new) [ -n "$3" ] && { echo "$3"; return 0; }; echo "layout: new takes the words for it"; return 1 ;;
        apps:pick|apps:terminal) echo ''; return 0 ;;
        window:move) _n=$(win_named "${3%% *}") || { echo 'that window is no longer open'; return 1; }; case ${3##* to=} in [1-9]|[1-9][0-9]) ;; *) echo 'a workspace is a number, 1 to 99'; return 1 ;; esac; echo "$_n to=${3##* to=}"; return 0 ;;
        window:place) _n=$(win_named "${3%% *}") || { echo 'that window is no longer open'; return 1; }; case ${3##* how=} in tiled|floating|full|left|right|up|down|min) ;; *) echo 'place takes tiled, floating, full, left, right, up, down or min'; return 1 ;; esac; echo "$_n how=${3##* how=}"; return 0 ;;
        window:restore) case ${3%% *}:${3##* now=} in split:split|split:tabs|split:stacked|tabs:split|tabs:tabs|tabs:stacked|stacked:split|stacked:tabs|stacked:stacked) echo "$3"; return 0 ;; esac; echo 'restore takes split, tabs or stacked'; return 1 ;;
        window:capture) case ${3%% *} in screen|area|window) ;; *) echo 'capture takes screen, area or window'; return 1 ;; esac
            case $3 in *' name='*) _n=$(win_named "${3##* name=}") || { echo 'that window is no longer open'; return 1; }; echo "${3%% *} name=$_n" ;; *) echo "${3%% *}" ;; esac; return 0 ;;
        layout:restore) [ -n "${3:-}" ] && { echo "$3"; return 0; }; echo 'layout: restore takes the name'; return 1 ;;
        window:close|window:focus|apps:close|apps:focus) if _n=$(win_named "${3:-}"); then echo "$_n"; return 0; fi; echo "window: no unique window named ${3:-?} is open; select it in Workspace"; return 1 ;;
        out:level|mic:level) case $3 in [0-9]|[1-9][0-9]|100) snd_settable "$1" || return 1; echo "$3"; return 0 ;; *) echo "$1: level takes 0 to 100"; return 1 ;; esac ;;
        out:adjust|mic:adjust) case $3 in [0-9]|[1-9][0-9]|100|-[0-9]|-[1-9][0-9]|-100) snd_settable "$1" || return 1; echo "$3"; return 0 ;; *) echo "$1: adjust takes a whole number of percentage points, -100 to 100"; return 1 ;; esac ;;
        out:mute|out:unmute|mic:mute|mic:unmute) snd_settable "$1" || return 1; echo ''; return 0 ;;   # the step sets, never toggles: mute when muted is a receipt
        theme:picture) _lpy=$(look_picks "${3:-}") || { echo "theme: $_lpy"; return 1; }; look_picks "${3:-}"   # the picture's path, then the picks the words asked for
            _pp=$(wall_picture_ok "$_lpr") || { echo "$_pp"; return 1; }
            echo "$_pp${_lp_face:+ face=$_lp_face}${_lp_family:+ family=$_lp_family}${_lp_animation:+ animation=$_lp_animation}"; return 0 ;;
        theme:wallpaper-picture) _pp=$(wall_picture_ok "${3:-}") && { echo "$_pp"; return 0; }; echo "$_pp"; return 1 ;;
        theme:wallpaper) case ${3:-} in default) echo default; return 0 ;; esac; ! wall_shipped "${3:-}" || { echo "$3"; return 0; } ;;   # else the wallpaper list below
        theme:wallpaper-color) wall_hex "${3:-}" >/dev/null && { echo "$3"; return 0; }; echo "theme: a color is a name ($(printf '%s' "$WALL_NAMES" | sed 's/ /, /g')) or #rrggbb"; return 1 ;;
        theme:text|theme:font) case ${3:-} in bigger|smaller|[6-9]|[1-3][0-9]|40) echo "$3"; return 0 ;; *) echo "theme: text takes bigger or smaller, or a size from 6 to 40"; return 1 ;; esac ;;
        theme:transparency) case ${3%\%} in more|less|[0-9]|[1-4][0-9]|50) echo "${3%\%}"; return 0 ;; *) echo "theme: transparency takes more or less, or a percent from 0 to 50"; return 1 ;; esac ;;
        theme:preview) case "|$(theme_enum)|off|" in *"|${3:-}|"*) echo "$3"; return 0 ;; esac; echo "theme: preview takes a palette's name, or off"; return 1 ;;
        theme:glyphs) case ${3:-} in signs|words) echo "$3"; return 0 ;; *) echo "theme: glyphs takes signs or words"; return 1 ;; esac ;;
        theme:icons) case ${3:-} in on|off) echo "$3"; return 0 ;; *) echo "theme: icons takes on or off"; return 1 ;; esac ;;
        theme:spacing) case ${3:-} in none|groups|rows) echo "$3"; return 0 ;; *) echo "theme: spacing takes none, groups or rows"; return 1 ;; esac ;;
        theme:family) case " $GLYPH_FAMILIES " in *" ${3:-none} "*) echo "$3"; return 0 ;; *) echo "theme: family takes stone, star or banner"; return 1 ;; esac ;;
        theme:face) case " $FONT_FACES " in *" ${3:-none} "*) echo "$3"; return 0 ;; *) echo "theme: face takes neon, argon, xenon, radon or krypton"; return 1 ;; esac ;;
        theme:motion) case ${3:-} in on|off) echo "$3"; return 0 ;; *) echo "theme: motion takes on or off"; return 1 ;; esac ;;
        theme:animation) case " next back none $ANIMATION_NAMES " in *" ${3:-} "*) echo "$3"; return 0 ;; *) echo "theme: animation takes none, $(printf '%s' "$ANIMATION_NAMES" | sed 's/ /, /g'), next or back"; return 1 ;; esac ;;
        theme:save) [ -n "$3" ] && { echo "$3"; return 0; }; echo "theme: save takes a name"; return 1 ;;
        theme:delete) case $(theme_kind "${3:-}") in saved|look) [ "$3" != "${THEME:-}" ] && { echo "$3"; return 0; }; echo "theme: $3 is the theme in use"; return 1 ;; *) echo "theme: no saved theme named ${3:-?}"; return 1 ;; esac ;;
        theme:back) [ -s "$(kept_hist theme)" ] && { echo ''; return 0; }; echo "theme: no look before this one"; return 1 ;;
        theme:words) case $3 in *[!a-z0-9=\ -]*) echo "$WORDS_TAKE"; return 1 ;; [a-z]*' accent='[a-z]*' warmth='[a-z]*' contrast='[a-z]*' light='[a-z]*|[a-z]*' accent='[a-z]*' warmth='[a-z]*' contrast='[a-z]*' light='[a-z]*' name='*) echo "$3"; return 0 ;; *) echo "theme: words take a hue, then accent, warmth, contrast and light"; return 1 ;; esac ;;
        layout:delete) { [ -f "$LAYOUTS_DIR/${3:-}" ] || kept_names layout | grep -qxF -- "${3:-}"; } && { echo "$3"; return 0; }; echo "layout: no saved or recent layout named ${3:-?}"; return 1 ;;
        layout:rename) _ro=${3%% *}; [ -n "$_ro" ] && { [ -f "$LAYOUTS_DIR/$_ro" ] || [ -f "$KEPT_LAYOUTS/$_ro" ]; } && { echo "$3"; return 0; }; echo "layout: no saved or recent layout named ${_ro:-?}"; return 1 ;;
        layout:back) [ -s "$(kept_hist layout)" ] && { echo ''; return 0; }; echo "layout: no layout before this one"; return 1 ;;
        theme:alpha) case $3 in 1|1.0|0|0.[0-9]|0.[0-9][0-9]) echo "$3"; return 0 ;; *) echo "theme: alpha takes 0 to 1"; return 1 ;; esac ;;
        notes:new) echo ''; return 0 ;;
        notes:open) _n=$(note_file "${3:-}") && { echo "${_n##*/}"; return 0; }; echo "notes: no unique note named ${3:-?}; select its file in Notes"; return 1 ;;
        reminders:done|reminders:snooze|reminders:delete) _n=$(rem_find "${3:-}" | cut -f2); [ -n "$_n" ] && { echo "$_n"; return 0; }; echo "reminders: no unique reminder named ${3:-?}; select it in Calendar"; return 1 ;;
        reminders:restore) [ -n "${3:-}" ] && { echo "$3"; return 0; }; echo "reminders: restore takes the reminder's name"; return 1 ;;
        notes:add|notes:find|reminders:add) [ -n "${3:-}" ] && { echo "$3"; return 0; }; echo "$1: $2 takes the words"; return 1 ;;
        display:brightness) case $3 in up|down|[1-9]|[1-9][0-9]|100) echo "$3"; return 0 ;; *) echo "display: brightness takes 1 to 100, up or down"; return 1 ;; esac ;;
        bar:on|bar:off|bar:top|bar:bottom) echo ''; return 0 ;;   # set, never toggled
        bar:text) case ${3:-} in auto|bigger|smaller|[6-9]|[1-3][0-9]|40) echo "$3"; return 0 ;; *) echo "bar: text takes auto, a size from 6 to 40, bigger or smaller"; return 1 ;; esac ;;
        bar:tray) case ${3:-} in on|off) echo "$3"; return 0 ;; *) echo "bar: tray takes on or off"; return 1 ;; esac ;;
        notifications:do-not-disturb) case ${3:-} in on|off) echo "$3"; return 0 ;; *) echo "notifications: do-not-disturb takes on or off"; return 1 ;; esac ;;
        storage:open) storage_list > "$TMP/storage.l"; [ -n "$(storage_find fs "${3:-}")" ] && { echo "$3"; return 0; }; echo "storage: no drive named ${3:-?} is plugged in"; return 1 ;;   # an unmounted drive mounts first
        display:idle|display:lock) case $3 in 0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) echo "$3"; return 0 ;; *) echo "display: $2 takes minutes, 0 to 999"; return 1 ;; esac ;;
    esac
    if [ "$1" = theme ] && [ -z "${3:-}" ]; then   # a palette's step is its name alone
        case $(theme_kind "$2") in shipped|yours|saved|none) echo ''; return 0 ;; look) [ "$2" != "${THEME:-}" ] || { echo ''; return 0; } ;; esac
    fi
    [ -z "${PANEL_ROW_MATCHED:-}" ] || { printf '%s\n' "${3:-}"; return 0; }   # a host's call matched a row it was sent, exactly
    _want=$(panel_lower "$2 $3" | sed 's/ *$//')
    _m=$(panel_rows "$1" full | cut -f3 | awk -v w="$_want" 'tolower($0) == w { print; exit }')
    [ "$1" != theme ] || [ -n "$_m" ] || _m=$(panel_rows wallpapers full | cut -f3 | awk -v w="$_want" 'tolower($0) == w { print; exit }')   # the wallpaper list is the theme's too
    if [ -z "$_m" ]; then   # a step naming what is in use (a show row) is a receipt, not a refusal
        _tx=$(panel_lower "${3:-$2}")
        { panel_rows "$1" full; [ "$1" != theme ] || panel_rows wallpapers full; } | awk -F '\t' -v t="$_tx" '$3 == "show" && tolower($2) == t { f = 1; exit } END { exit !f }' && { echo "${3:-}"; return 0; }
    fi
    [ -n "$_m" ] && [ "$_m" != show ] || { echo "${3:-$2} is not in the list now"; return 1; }
    printf '%s\n' "${_m#* }" | awk -v a="$2" '$0 == a { print ""; exit } { print }'
}
panel_list() {   # panel_list [SECTION] -> the glance, then the one list as text
    SND=${SND:-$(snd_tool)}
    panel_title "$1"
    [ "$1" != clock ] || { echo; clock_view; }
    panel_stream "$1"
}

