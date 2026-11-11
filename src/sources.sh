# shellcheck extended-analysis=false
# --- the sources
# a row is MARK<tab>TEXT<tab>ACTION [ARG]: the mark a sign or -, a
# look-only row carries `show`
panel_title() {   # panel_title SECTION -> the lines that say what opened the panel; glance: the date, the facts, an alarm line
    case $1 in
        printers) if _ps=$(printer_status); then echo "$(panel_col printers)$(printf '%s' "$_ps" | jq '.queues | length') native print queues"
            else echo "$(panel_col printers)native print service unavailable"; fi ;;
        lan) _l=$(bar_lan); case $_l in up*) echo "$(panel_col lan)up $PANEL_SEP ${_l#up }" ;; down) echo "$(panel_col lan)$PANEL_WARN down: no carrier on the wire" ;; *) echo "$(panel_col lan)no wire" ;; esac ;;
        wifi) _t=$(wifi_tool); _c=$(wifi_connected); _w=$(bar_wifi)
            if [ -z "$_t" ]; then echo "$(panel_col wifi)no tool answers (nmcli, iwctl or wpa_cli)"
            elif [ -z "$_c" ]; then echo "$(panel_col wifi)not connected"
            else case $_w in *' '*) _a=${_w#* } ;; *) _a='' ;; esac; echo "$(panel_col wifi)$(panel_bars "${_w%% *}") $_c${_a:+ $PANEL_SEP $_a}"; fi ;;
        bt) _b=$(bar_bt); case $_b in name*) echo "$(panel_col bt)$PANEL_DOT ${_b#name }" ;; on) echo "$(panel_col bt)on $PANEL_SEP nothing connected" ;; off) echo "$(panel_col bt)off" ;; *) echo "$(panel_col bt)no controller" ;; esac ;;
        out|mic) if [ "$1" = out ]; then _o=$(snd_out); else _o=$(snd_mic); fi
            [ -n "$_o" ] || { echo "$(panel_col "$1")nothing found"; return 0; }
            _n=$(printf '%s\n' "$_o" | sed -n 1p); _lv=$(printf '%s\n' "$_o" | sed -n 2p); _m=$(printf '%s\n' "$_o" | sed -n 3p); _live=0
            if [ "$1" = mic ]; then _lv=$(printf '%s\n' "$_o" | sed -n 4p); _live=$(printf '%s\n' "$_o" | sed -n 2p); fi
            _s="$(panel_col "$1")$_n"; [ "$_lv" = - ] || [ -z "$_lv" ] || _s="$_s $PANEL_SEP $_lv%"; [ "$_m" != 1 ] || _s="$_s $PANEL_SEP muted"; [ "${_live:-0}" != 1 ] || _s="$_s $PANEL_SEP $PANEL_DOT recording"
            echo "$_s" ;;
        bat) _b=$(bar_power); [ -n "$_b" ] || { echo "$(panel_col bat)no battery"; return 0; }
            _cap=${_b%% *}; _st=$(panel_lower "${_b#* }"); _w=''; [ "$_cap" -ge 15 ] 2>/dev/null || [ "$_st" = charging ] || _w="$PANEL_WARN "
            _s="$(panel_col bat)$_w$_cap% $PANEL_SEP $_st"; _left=$(bat_left); [ -z "$_left" ] || _s="$_s $PANEL_SEP $_left"; echo "$_s" ;;
        clock) date '+%A %d %B %Y' ;;   # the time and the month are drawn under it (clock_view)
        theme) echo "$(panel_col theme)$(theme_words_of "${THEME:-none}")" ;;   # the palette or the theme alone
        window) echo "$(panel_col window)$(win_words "$WINDOWS")" ;;
        notes) _n=$(notes_list | grep -c . || :); echo "$(panel_col notes)${_n:-0} in ~/notes" ;;
        reminders) _now=$(date +%Y%m%d%H%M); rem_list > "$TMP/rem.t"; _d=$(awk -F '\t' -v n="$_now" '$1 <= n {t = $3} END {print t}' "$TMP/rem.t")
            if [ -n "$_d" ]; then echo "$(panel_col reminders)due now: $_d"
            else _td=$(awk -F '\t' -v n="$_now" -v d="$(date +%Y%m%d)" '$1 > n && substr($1, 1, 8) == d' "$TMP/rem.t" | grep -c . || :); _all=$(grep -c . "$TMP/rem.t" || :)
                if [ "${_all:-0}" -eq 0 ]; then echo "$(panel_col reminders)none ahead"; else echo "$(panel_col reminders)${_td:-0} today, $((_all - ${_td:-0})) after"; fi; fi ;;
        display) _b=$(light_get); if [ -n "$_b" ]; then echo "$(panel_col display)brightness $_b%"; else echo "$(panel_col display)idle $(idle_words "$DISPLAY_IDLE")"; fi ;;   # short: the rows say the minutes
        pointer) echo "$(panel_col pointer)tap $POINTER_TAP $PANEL_SEP scroll $POINTER_SCROLL $PANEL_SEP speed $POINTER_SPEED" ;;
        keyboard) _k=$(kb_active); if [ -n "$_k" ]; then echo "$(panel_col keyboard)$_k $PANEL_SEP $(printf '%s\n' $KEYBOARD | grep -c .) layouts"; elif [ -n "$KEYBOARD" ]; then echo "$(panel_col keyboard)$KEYBOARD"; else echo "$(panel_col keyboard)sway's own layout"; fi ;;
        bar) if [ "$DESKTOP_BAR" = yes ]; then echo "$(panel_col bar)shown $(bar_place_words "$BAR_POSITION")"; else echo "$(panel_col bar)hidden $PANEL_SEP $(panel_keys "$(desk_keys | awk '$2 == "home.open." {print $1; exit}')") opens the dialog"; fi ;;
        notifications) if ! mako_here; then echo "$(panel_col notifications)mako is not installed"
            elif ! notify_up; then echo "$(panel_col notifications)not running yet"
            elif notify_dnd; then echo "$(panel_col notifications)do not disturb"
            else _nn=$(notify_list list | grep -c . || :); if [ "${_nn:-0}" -gt 0 ]; then echo "$(panel_col notifications)$_nn on the screen"; else echo "$(panel_col notifications)on"; fi; fi ;;   # short
        storage) _sn=$(storage_drives | grep -c . || :)   # the drives alone: free space is a row
            case ${_sn:-0} in 0) echo "$(panel_col storage)no drive plugged in" ;; 1) echo "$(panel_col storage)1 drive" ;; *) echo "$(panel_col storage)$_sn drives" ;; esac ;;
        power) _pu=$(power_up); echo "$(panel_col power)${_pu:-lock, suspend, restart}" ;;
        about) echo "$(panel_col about)spark-shell $(panel_version) $PANEL_SEP the project, the license, the credits" ;;
        tools) echo "$(panel_col tools)$(tools_check_state)" ;;
        layout) _n=$(ls -A "$LAYOUTS_DIR" 2>/dev/null | wc -l | tr -d ' '); _last=''; [ ! -f "$DESK_LAST" ] || _last=$(desk_words "$DESK_LAST")
            if [ "$_n" -eq 0 ]; then echo "$(panel_col layout)none saved yet"
            else echo "$(panel_col layout)$_n saved${_last:+ $PANEL_SEP last: $_last}"; fi ;;
        apps) if apps_marked; then echo "$(panel_col apps)$(grep -c '^[A-Za-z0-9]' "$APPS") allowed $PANEL_SEP Enter opens one"; else echo "$(panel_col apps)every app allowed $PANEL_SEP Enter opens one"; fi ;;
        spark) echo "$(panel_col spark)a conversation, in this window" ;;
        undo) echo "$(panel_col undo)the last thing done, taken back" ;;
        glance) panel_glance_line
            _f=$(panel_facts_short); [ -z "$_f" ] || echo "$_f"
            _a=$(panel_alarms); [ -z "$_a" ] || echo "$_a" ;;
    esac
}
panel_glance_line() { echo "$(date '+%A %d %B') $PANEL_SEP $(clock_text)"; }   # -> the date and the time on a pipe (the window draws the clock instead)
panel_glance() {   # panel_glance WIDTH -> the lines over the list: the date, the clock, an alarm in red when there is one
    date '+%A %d %B'; echo
    clock_view "$PANEL_MARK" "$PANEL_UNMARK"
    _a=$(panel_alarms); [ -z "$_a" ] || { echo; printf '%s\n' "$_a" | fold -s -w "$1" | sed "s/.*/$PANEL_RED&$PANEL_UNMARK/"; }
}
panel_facts_short() {   # -> the bar's facts in a few words each, one line
    _s=''
    for p in $(panel_blocks_here); do
        case $p in
            lan) _l=$(bar_lan); case $_l in up*) continue ;; down) _w="lan down" ;; *) continue ;; esac ;;   # a wire that is up says nothing
            wifi) _c=$(wifi_connected); [ -n "$_c" ] || continue; _w="wifi $_c" ;;
            bt) _b=$(bar_bt); case $_b in name*) _w="bt $PANEL_DOT ${_b#name }" ;; on|off) _w="bt $_b" ;; *) continue ;; esac ;;
            out|mic) if [ "$p" = out ]; then _o=$(snd_out); _lv=$(printf '%s\n' "$_o" | sed -n 2p); else _o=$(snd_mic); _lv=$(printf '%s\n' "$_o" | sed -n 4p); fi
                [ -n "$_o" ] || continue
                if [ "$(printf '%s\n' "$_o" | sed -n 3p)" = 1 ]; then _w="$p muted"; elif [ "$_lv" = - ] || [ -z "$_lv" ]; then _w="$p on"; else _w="$p $_lv%"; fi ;;
            bat) _b=$(bar_power); _w="bat ${_b%% *}%" ;;
            clock) continue ;;
            theme) _w="theme ${THEME:-none}" ;;
        esac
        _s="${_s:+$_s $PANEL_SEP }$_w"
    done
    printf '%s\n' "$_s"
}
panel_alarms() {   # -> the alarms the bar shows in red, on one line with the warning sign; nothing when all is well
    _a=''
    for p in $(panel_blocks_here); do
        case $p in
            lan) case $(bar_lan) in down) _a="${_a:+$_a $PANEL_SEP }$PANEL_WARN lan down" ;; esac ;;
            bat) _b=$(bar_power); [ "${_b%% *}" -ge 15 ] 2>/dev/null || [ "$(panel_lower "${_b#* }")" = charging ] || _a="${_a:+$_a $PANEL_SEP }$PANEL_WARN battery ${_b%% *}%" ;;
            mic) [ "$(snd_mic | sed -n 2p)" != 1 ] || _a="${_a:+$_a $PANEL_SEP }$PANEL_DOT mic recording" ;;
        esac
    done
    printf '%s\n' "$_a"
}
panel_facts() {   # -> what the bar shows now, one title per block, for a question at the prompt
    for p in $(panel_blocks_here); do [ "$p" = clock ] || printf '%s; ' "$(panel_title "$p")"; done | sed 's/; $//' | tr -s ' '
}
panel_rows() {   # panel_rows SECTION [full] -> the rows; without `full` a long section shows what matters and a `more` row
    case $1 in
        printers)
            if printer_status > "$TMP/printers.json" 2> "$TMP/printers.error"; then
                jq -r 'if (.queues | length) == 0 then ["-", "no printers configured in CUPS", "show"] | @tsv else
                    .default as $default | (.queues[] | . as $q |
                        (["-", ($q.name + ": " + $q.state), "show"] | @tsv),
                        (["-", (if $q.name == $default then "default printer " else "use as default " end) + $q.name, (if $q.name == $default then "show" else "default " + $q.name end)] | @tsv),
                        (["-", (if $q.enabled then "pause " else "resume " end) + $q.name, (if $q.enabled then "pause " else "resume " end) + $q.name] | @tsv)),
                    (.jobs[] | ["-", ("cancel job " + .id), ("cancel " + .id)] | @tsv) end' "$TMP/printers.json"
            else printf -- '-\t%s\tshow\n' "$(cat "$TMP/printers.error" | scrub_text)"; fi ;;
        lan) for i in $(bar_wired); do
                printf -- '-\tsettings for %s\tnetwork-settings %s\n' "$i" "$i"
                [ "$(cat "$BAR_SYS/class/net/$i/carrier" 2>/dev/null)" = 1 ] || { printf -- '-\twire %s: no carrier\tshow\n' "$i"; continue; }
                printf -- '-\taddress %s\tshow\n' "$(bar_addr "$i")"
                _sp=$(cat "$BAR_SYS/class/net/$i/speed" 2>/dev/null); [ -z "$_sp" ] || [ "$_sp" -le 0 ] 2>/dev/null || printf -- '-\tspeed %s Mb/s\tshow\n' "$_sp"
                _gw=$(ip -4 route show default dev "$i" 2>/dev/null | awk '{print $3; exit}'); [ -z "$_gw" ] || printf -- '-\tgateway %s\tshow\n' "$_gw"
                _ns=$(awk '$1 == "nameserver" {print $2; exit}' /etc/resolv.conf 2>/dev/null); [ -z "$_ns" ] || printf -- '-\tname server %s\tshow\n' "$_ns"
                break
            done ;;
        wifi) [ -n "$(wifi_tool)" ] || {
                if _package=$(wifi_offer); then printf -- '-\tinstall the native network manager\tsetup\n'
                else printf -- '-\tno tool answers for wifi (nmcli, iwctl or wpa_cli)\tshow\n'; fi
                return 0
            }
            printf -- '-\tjoin a hidden network\thidden network\n'
            [ -z "$(wifi_if)" ] || printf -- '-\tconnection settings\tnetwork-settings %s\n' "$(wifi_if)"
            _c=$(wifi_connected); wifi_known | cut -f2 > "$TMP/wifi.known"
            [ -z "$_c" ] || printf '%s\t%s\tdisconnect\n' "$PANEL_DOT" "$_c"
            # around: the saved ones and, unless full, the strongest three; the rest counts in a `more` row
            wifi_scan | awk -F '\t' -v c="$_c" '$1 != c' > "$TMP/wifi.around"
            _n=0; _left=0
            while IFS="$TAB" read -r n l sec; do
                if grep -qxF -- "$n" "$TMP/wifi.known"; then _k=" $PANEL_TICK saved"; else _k=''; fi
                if [ "${2:-}" != full ] && [ -z "$_k" ] && [ "$_n" -ge 3 ]; then _left=$((_left + 1)); continue; fi
                printf '%s\t%s %s%s\tconnect %s\n' "$PANEL_RING" "$n" "$(panel_bars "$l")" "$_k" "$n"
                [ -n "$_k" ] || _n=$((_n + 1))
            done < "$TMP/wifi.around"
            [ "$_left" -eq 0 ] || printf -- '-\t%s more\tmore\n' "$_left"
            while IFS= read -r n; do [ -n "$n" ] && [ "$n" != "$_c" ] && printf -- '-\tforget %s\tforget %s\n' "$n" "$n"; done < "$TMP/wifi.known" ;;
        bt) command -v bluetoothctl >/dev/null 2>&1 || { printf -- '-\tbluetoothctl is not installed\tshow\n'; return 0; }
            bt_running || { printf -- '-\tbluetoothd is not running (spark-shell on desktop)\tshow\n'; return 0; }
            if bt_powered; then
                bt_list | while IFS="$TAB" read -r mac n p c; do
                    if [ "$c" = 1 ]; then printf '%s\t%s\tdisconnect %s\n' "$PANEL_DOT" "$n" "$n"
                    elif [ "$p" = 1 ]; then printf '%s\t%s\tconnect %s\n' "$PANEL_RING" "$n" "$n"
                    else printf '%s\t%s %s new\tpair %s\n' "$PANEL_RING" "$n" "$PANEL_SEP" "$n"; fi
                    [ "$p" != 1 ] || printf -- '-\tremove %s\tremove %s\n' "$n" "$n"
                done
                printf -- '-\tfind new devices\tscan\n-\tturn off\tpower off\n'
            else printf -- '-\tturn on\tpower on\n'; fi ;;
        out|mic) [ -n "${SND:-}" ] || { printf -- '-\tno audio system found\tshow\n'; return 0; }
            _tf=''; [ "$SND" != alsa ] || _tf=$(al_theirs) || _tf=''
            if [ -n "$_tf" ]; then   # your own file picks the device: shown, no pick, the file named
                snd_devices "$1" | while IFS="$TAB" read -r n d; do if [ "$d" = 1 ]; then printf '%s\t%s\tshow\n' "$PANEL_DOT" "$n"; else printf '%s\t%s\tshow\n' "$PANEL_RING" "$n"; fi; done
                printf -- '-\t%s\tshow\n' "$(al_theirs_said "$_tf")"
            else
                snd_devices "$1" | while IFS="$TAB" read -r n d; do if [ "$d" = 1 ]; then printf '%s\t%s\tshow\n' "$PANEL_DOT" "$n"; else printf '%s\t%s\tuse %s\n' "$PANEL_RING" "$n" "$n"; fi; done
            fi
            if [ "$1" = out ]; then _o=$(snd_out); _m=$(printf '%s\n' "$_o" | sed -n 3p); _lv=$(printf '%s\n' "$_o" | sed -n 2p)
            else _o=$(snd_mic); _m=$(printf '%s\n' "$_o" | sed -n 3p); _lv=$(printf '%s\n' "$_o" | sed -n 4p); fi
            [ "$_lv" = - ] || [ -z "$_lv" ] || { if [ "$_m" = 1 ]; then printf -- '-\tunmute\tunmute\n'; else printf -- '-\tmute\tmute\n'; fi; } ;;
        bat) if [ "$OS" = Darwin ]; then
                _b=$(bar_power); [ -n "$_b" ] || { printf -- '-\tno battery reported by macOS\tshow\n'; return 0; }
                printf -- '-\tcharge %s%% %s %s\tshow\n' "${_b%% *}" "$PANEL_SEP" "${_b#* }"
                _left=$(bat_left); [ -z "$_left" ] || printf -- '-\t%s\tshow\n' "$_left"
                return 0
            fi
            _d=$(bat_dir); [ -n "$_d" ] || { printf -- '-\tno battery\tshow\n'; return 0; }
            printf -- '-\tcharge %s%% %s %s\tshow\n' "$(bat_num capacity)" "$PANEL_SEP" "$(panel_lower "$(bat_num status)")"
            _left=$(bat_left); [ -z "$_left" ] || printf -- '-\t%s\tshow\n' "$_left"
            _f=$(bat_num energy_full); _fd=$(bat_num energy_full_design); [ -n "$_f" ] || { _f=$(bat_num charge_full); _fd=$(bat_num charge_full_design); }
            [ -z "$_f" ] || [ -z "$_fd" ] || [ "$_fd" -le 0 ] 2>/dev/null || printf -- '-\thealth %s%% of new\tshow\n' $(( _f * 100 / _fd ))
            _cy=$(bat_num cycle_count); [ -z "$_cy" ] || printf -- '-\tcycles %s\tshow\n' "$_cy"
            _r=$(bat_num power_now); [ -z "$_r" ] || [ "$_r" -le 0 ] 2>/dev/null || printf -- '-\tpower %s W\tshow\n' "$(awk -v r="$_r" 'BEGIN { printf "%.1f", r / 1000000 }')" ;;
        clock) printf -- '-\tzone %s\tshow\n-\t%s\tshow\n' "$(time_zone)" "$(time_sync)"
            for _v in 12 24; do printf -- '-\t%s hour clock\tformat %s\n' "$_v" "$_v"; done
            for _v in sunday monday; do printf -- '-\tweek starts on %s\tweek %s\n' "$_v" "$_v"; done
            [ "$OS" = Darwin ] || printf -- '-\tchange time zone\tzone\n' ;;
        theme) _sz=$(look_font_size)   # the look: the palettes, the saved themes, the custom rows, then the settings
            [ "${2:-}" = full ] || { printf -- '-\t%s %s more\tmore\n' "$(panel_title theme | sed "s/^theme *//")" "$PANEL_SEP"; return 0; }   # one row in the list; typing finds every row below
            # the palettes first, dark beside light, each its own step, the one in use too
            palette_names > "$TMP/pal.names"; _darks=" $(palette_darks | tr '\n' ' ') "   # the dark ones, a word each: no process a palette
            for _g in dark light; do
                while IFS= read -r n; do
                    case $_darks in *" $n "*) [ "$_g" = dark ] || continue ;; *) [ "$_g" = light ] || continue ;; esac
                    if [ "$n" = "${THEME:-}" ]; then printf '%s\t%s\t%s\t%s\n' "$PANEL_TICK" "$n" "$n" "$_g"; else printf -- '-\t%s\t%s\t%s\n' "$n" "$n" "$_g"; fi
                done < "$TMP/pal.names"
            done
            for n in $(theme_saved_names); do   # custom: the themes kept as folders, the one in use a check
                _td=$PALETTE_DIR/$n; _wl=$(look_get "$_td" WALLPAPER); [ "$_wl" != picture ] || _wl=$(look_get "$_td" PICTURE)
                if [ "$n" = "${THEME:-}" ]; then printf '%s\t%s\tshow\tcustom|%s %s %s\n' "$PANEL_TICK" "$n" "$(theme_source_of "$_td")" "$PANEL_SEP" "${_wl:-default}"
                else printf -- '-\t%s\t%s\tcustom|%s %s %s\n' "$n" "$n" "$(theme_source_of "$_td")" "$PANEL_SEP" "${_wl:-default}"; fi
            done
            [ "$(theme_kind "${THEME:-}")" != look ] || printf '%s\t%s\tshow\tcustom|not saved\n' "$PANEL_TICK" "$(theme_words_of "$THEME")"   # a look from words or a picture stays here until it is saved
            printf -- '-\tsave this look as\tsave\tcustom\n'
            [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || printf -- '-\ta theme from a picture\tpicture\tcustom\n'   # the files, to pick a picture from (the dialog's)
            if [ "${THEME:-none}" = none ]; then printf '%s\t%s\tshow\tcustom\n' "$PANEL_TICK" "$PALETTE_NONE"; else printf -- '-\t%s\tnone\tcustom\n' "$PALETTE_NONE"; fi
            # then the settings, in three groups: the screen, the text and the bar, the dialog
            _de=''; [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || _de=1
            [ -z "$_de" ] || printf -- '-\tWallpaper\twallpaper\tscreen|%s\n' "$(wall_now)"   # opens the wallpaper list
            [ -z "$_de" ] || printf -- '-\tMoving wallpaper\tshow\tscreen\n'   # a switch
            printf -- '-\tTransparency\tshow\tscreen\n'   # a value left and right change
            [ -z "$_sz" ] || printf -- '-\tText size\tshow\ttext and bar\n'
            [ -z "$_de" ] || printf -- '-\tWords on the bar\tshow\ttext and bar\n'   # a switch
            printf -- '-\tGlyph family\tshow\ttext and bar\n'   # a value left and right change: the dialog's signs, and the bar's on the desktop
            [ "$OS" = Darwin ] || printf -- '-\tText face\tshow\ttext and bar\n'   # a value left and right change: Monaspace's five; a Mac's text is Terminal.app's
            [ -z "$_de" ] || printf -- '-\tAnimation\tshow\tdialog\n-\tApp icons\tshow\tdialog\n-\tApp spacing\tshow\tdialog\n' ;;   # the dialog's transitions, opening their list; the apps' icons a switch; their space a value
        wallpapers) _cur=$(wall_name)   # the theme's wallpaper list: the drawings, each with its palette; then custom: a picture, a color, the ground
            for w in $(wall_shipped_names); do
                _pw=$(wall_palette_of "$w"); case $_pw in any) _pw='for any dark palette' ;; every) _pw='moves, in any palette' ;; *) _pw="for $_pw" ;; esac   # the caption under its picture: 24 cells
                if [ "$w" = "$_cur" ]; then printf '%s\t%s\twallpaper %s\tdrawings|%s\n' "$PANEL_TICK" "$w" "$w" "$_pw"; else printf -- '-\t%s\twallpaper %s\tdrawings|%s\n' "$w" "$w" "$_pw"; fi
            done
            [ -n "$_cur" ] || printf '%s\tpicture %s\tshow\tcustom\n' "$PANEL_TICK" "$(basename "$(wall_path)")"
            printf -- '-\ta picture\twallpaper-picture\tcustom\n'   # the files, to pick a picture from (the dialog's)
            ! wall_color || printf '%s\t%s\tshow\tcustom|a color\n' "$PANEL_TICK" "$_cur"
            printf -- '-\ta color\twallpaper-color\tcustom|a name or #rrggbb\n'   # it asks for one (provide_wall_rows)
            if [ "$_cur" = default ]; then _gm=$PANEL_TICK; else _gm=-; fi
            printf '%s\tthe ground\twallpaper default\tcustom|%s\n' "$_gm" "$WALL_GROUND_SAID" ;;   # in use or not, its own step: the check moves in place
        about) printf '%s\tspark-shell %s\topen\n' "$PANEL_GO" "$(panel_version)" ;;   # the splash, in this window
        tools) tools_menu | while IFS="$TAB" read -r _tmn _tms _tml; do printf -- '-\t%s  %s\tshow\n' "$_tmn" "$_tms"; done ;;   # the six, as text: the dialog opens their pages
        window) for _w in split tabs stacked; do
                if [ "$_w" = "${WINDOWS:-split}" ]; then printf '%s\t%s\tshow\n' "$PANEL_TICK" "$(win_words "$_w")"; else printf -- '-\t%s\t%s\n' "$(win_words "$_w")" "$_w"; fi
            done
            printf '%s\tcapture the screen\tcapture screen\n%s\tcapture an area\tcapture area\n%s\tcapture a window\tcapture window\n' "$PANEL_GO" "$PANEL_GO" "$PANEL_GO"   # a picture, the dialog closed first; the keys beside them
            # one row a window: the app, its title a column; the close row is for spark's list and --list
            [ "${2:-}" != full ] || win_read | win_rows | while IFS="$TAB" read -r _l _i _g _t; do printf '%s\t%s\tfocus %s\t%s|%s\n-\tclose %s\tclose %s\n' "$PANEL_GO" "$_l" "$_i" "$_g" "$_t" "$_l" "$_i"; done ;;
        display) for _k in idle lock; do   # the minutes now, then the other picks in a full list
                if [ "$_k" = idle ]; then _v=$DISPLAY_IDLE; _w='idle screen'; else _v=$DISPLAY_LOCK; _w=lock; fi
                printf '%s\t%s %s\tshow\n' "$PANEL_TICK" "$_w" "$(idle_words "$_v")"
                [ "${2:-}" = full ] || continue
                for _m in 5 10 15 30 60 0; do [ "$_m" = "$_v" ] || printf -- '-\t%s %s\t%s %s\n' "$_w" "$(idle_words "$_m")" "$_k" "$_m"; done
            done
            if saver_can; then   # the saver rows where python3 runs one: the one in use, then the others in a full list
                printf '%s\tsaver %s\tshow\n' "$PANEL_TICK" "$DISPLAY_SAVER"
                if [ "${2:-}" = full ]; then for _n in clock $SAVER_NAMES; do [ "$_n" = "$DISPLAY_SAVER" ] || printf -- '-\tsaver %s\tsaver %s\n' "$_n" "$_n"; done; fi
            fi
            _b=$(light_get); [ -z "$_b" ] || printf -- '-\tbrightness %s%%\tshow\n-\tbrighter\tbrightness up\n-\tdimmer\tbrightness down\n' "$_b"
            [ -z "${SWAYSOCK:-}" ] || screen_rows | while IFS="$TAB" read -r _n _id _on _md _sc _x _y _w _h _mo _tr; do   # short, for the dialog's width: the port, the model, the mode, the scale
                if [ "$_on" = on ]; then printf -- '-\tscreen %s %s %s%s %s scale %s\tshow\n' "$_n" "$PANEL_SEP" "${_mo:+$_mo $PANEL_SEP }" "$_md" "$PANEL_SEP" "$_sc"; else printf -- '-\tscreen %s %s off\tshow\n' "$_n" "$PANEL_SEP"; fi
            done ;;
        keyboard) if [ -z "$KEYBOARD" ]; then printf -- "-\tsway's own layout: spark-shell desktop keyboard us br sets some\tshow\n"
            else
                _a=$(kb_active)
                for _x in $KEYBOARD; do if [ "$_x" = "$_a" ] || [ -z "$_a" ]; then printf '%s\t%s\tshow\n' "$PANEL_TICK" "$_x"; else printf -- '-\t%s\tuse %s\n' "$_x" "$_x"; fi; done
                [ -z "$_a" ] || printf '%s\tthe next layout\tnext\n' "$PANEL_GO"
            fi
            printf -- '-\trepeat delay %s ms\tshow\n-\trepeat rate %s per second\tshow\n-\tcaps key %s\tshow\n' "$KEY_REPEAT_DELAY" "$KEY_REPEAT_RATE" "$KEY_CAPS"
            for _v in 250 400 600 1000; do printf -- '-\trepeat after %s ms\trepeat-delay %s\n' "$_v" "$_v"; done
            for _v in 0 15 25 40; do printf -- '-\trepeat %s per second\trepeat-rate %s\n' "$_v" "$_v"; done
            for _v in caps control escape; do printf -- '-\tcaps key as %s\tcaps %s\n' "$_v" "$_v"; done ;;
        pointer)
            for _v in on off; do printf -- '-\ttap to click %s\ttap %s\n-\tnatural scroll %s\tscroll %s\n' "$_v" "$_v" "$_v" "$_v"; done
            for _v in -1 -0.5 0 0.5 1; do printf -- '-\tpointer speed %s\tspeed %s\n' "$_v" "$_v"; done ;;
        notifications) if ! notify_up; then printf -- '-\t%s\tshow\n' "$(notify_why)"; return 0; fi
            if notify_dnd; then printf '%s\tturn off do not disturb\tdo-not-disturb off\n' "$PANEL_DOT"; else printf -- '-\tturn on do not disturb\tdo-not-disturb on\n'; fi
            _nn=$(notify_list list | grep -c . || :)
            case ${_nn:-0} in 0) ;; 1) printf -- '-\tdismiss the one on the screen\tdismiss\n' ;; *) printf -- '-\tdismiss the %s on the screen\tdismiss\n' "$_nn" ;; esac
            notify_list history > "$TMP/notify.rows"
            [ ! -s "$TMP/notify.rows" ] || printf -- '-\tshow the last one again\trestore\n'
            _n=0
            while IFS="$US" read -r _ni _na _ns; do   # the history, newest first: what each said, its app a column; five unless full
                _n=$((_n + 1)); if [ "${2:-}" != full ] && [ "$_n" -gt 5 ]; then continue; fi
                printf -- '-\t%s\tshow\tearlier|%s||%s\n' "$(printf '%s' "${_ns:-$_na}" | cut_chars 44)" "$(printf '%s' "$_na" | cut_chars 14)" "$_ni"
            done < "$TMP/notify.rows"
            [ "${2:-}" = full ] || [ "$_n" -le 5 ] || printf -- '-\t%s more\tmore\tearlier||\n' $((_n - 5)) ;;
        storage) udisks_here || printf -- '-\tudisksctl is not installed (spark-shell on desktop)\tshow\n'
            storage_list > "$TMP/storage.l"
            [ -s "$TMP/storage.l" ] || printf -- '-\tno drive plugged in\tshow\n'
            awk -F '\037' '$1 == "drive" { print $2 }' "$TMP/storage.l" > "$TMP/storage.d"
            while IFS= read -r _sdn; do   # a drive is a group: its filesystems, mounted or not, then eject
                awk -F '\037' -v d="$_sdn" '$1 == "fs" && $6 == d' "$TMP/storage.l" | while IFS="$US" read -r _sk _sn _sd _ss _sm _sdr _sf; do
                    if [ "$_sf" = crypto_LUKS ]; then printf -- '-\t%s is encrypted: udisksctl unlock -b %s\tshow\t%s|%s|\n' "$_sn" "$_sd" "$_sdr" "$(files_size "$_ss")"
                    elif [ -n "$_sm" ]; then printf '%s\t%s\topen %s\t%s|%s free|\n-\tunmount %s\tunmount %s\t%s||\n' "$PANEL_DOT" "$_sn" "$_sn" "$_sdr" "$(storage_kb "$(read_once "free.${_sd##*/}" storage_free "$_sm")")" "$_sn" "$_sn" "$_sdr"
                    else printf '%s\t%s\tmount %s\t%s|%s|\n' "$PANEL_RING" "$_sn" "$_sn" "$_sdr" "$(files_size "$_ss")"; fi
                done
                printf -- '-\teject %s\teject %s\t%s||\n' "$_sdn" "$_sdn" "$_sdn"
            done < "$TMP/storage.d"
            _sh=$(storage_here); [ -z "$_sh" ] || printf -- '-\t%s\tshow\tthis computer||\n' "$_sh" ;;
        power) _pt=$(power_tool)   # one word a row, what it does as its wide column; the uptime a fact under them
            [ -z "${WAYLAND_DISPLAY:-}" ] || printf -- '-\tlock\tlock\t|the screen %s Super+Escape\n' "$PANEL_SEP"
            [ -z "$_pt" ] || ! power_sleeps || printf -- '-\tsuspend\tsuspend\t|the screen locks first\n'
            [ -z "${SWAYSOCK:-}" ] || printf -- '-\tlogout\tlogout\t|every window closes\n'
            if [ -n "$_pt" ]; then printf -- '-\trestart\trestart\t|asks first\n-\tshutdown\tshutdown\t|asks first\n'; else printf -- '-\t%s\tshow\n' "$(power_why)"; fi   # what the machine's buttons do is no step here
            _pu=$(power_up); [ -z "$_pu" ] || printf -- '-\t%s\tshow\n' "$_pu" ;;
        notes) printf '%s\tnew note\tnew\n' "$PANEL_GO"   # the newest five and a more row; full, all of them
            notes_list > "$TMP/notes.l"; _n=0
            while IFS="$TAB" read -r _e _nm _f; do
                [ -z "${NOTES_WORDS:-}" ] || note_says "$_f" "$NOTES_WORDS" || continue   # a search from Home: the notes that say every word
                _n=$((_n + 1)); if [ "${2:-}" != full ] && [ "$_n" -gt 5 ]; then continue; fi
                printf -- '-\t%s\topen %s\trecent|%s|\n' "$_nm" "${_f##*/}" "$(read_once "when.$_e" note_when "$_e")"   # its day once a read
            done < "$TMP/notes.l"
            [ "${2:-}" = full ] || [ "$_n" -le 5 ] || printf -- '-\t%s more\tmore\trecent||\n' $((_n - 5)) ;;
        reminders) printf '%s\tnew reminder\tadd\n' "$PANEL_GO"   # the ones due, the first with done and a snooze; then the ones ahead
            _first=1; _next=1
            rem_rows > "$TMP/rem.rows"
            while IFS="$TAB" read -r _s _u _t _f _x _o; do
                if [ "${_x%%|*}" = due ]; then
                    if [ "$_o" = 1 ]; then
                        printf '%s\t%s\tdone %s\t%s\n' "$PANEL_DOT" "$_t" "$_u" "$_x"
                        [ -z "$_first" ] || printf -- '-\tdone\tdone %s\tdue||\n-\tagain in 10 minutes\tsnooze %s\tdue||\n' "$_u" "$_u"
                        _first=''
                    else printf '%s\t%s\tshow\t%s\n' "$PANEL_DOT" "$_t" "$_x"; fi
                elif [ "${2:-}" = full ]; then   # one ahead: done on Enter when spark-shell wrote it; another calendar's is shown alone
                    if [ "$_o" = 1 ]; then printf '%s\t%s\tdone %s\t%s\n' "$PANEL_RING" "$_t" "$_u" "$_x"; else printf '%s\t%s\tshow\t%s\n' "$PANEL_RING" "$_t" "$_x"; fi
                elif [ -n "$_next" ]; then printf '%s\t%s\tmore\t|%s|\n' "$PANEL_RING" "$_t" "$(rem_said "$_s")"; _next=''; fi   # short: the next one ahead; Enter opens the rest
            done < "$TMP/rem.rows" ;;
        bar) _bpn=$(bar_place)   # the place, a check; then the text size and the tray
            for _bp in top bottom hidden; do
                _bpa=$_bp; [ "$_bp" != hidden ] || _bpa=off
                if [ "$_bp" = "$_bpn" ]; then printf '%s\t%s\tshow\tplace\n' "$PANEL_TICK" "$(bar_place_words "$_bp")"; else printf -- '-\t%s\t%s\tplace\n' "$(bar_place_words "$_bp")" "$_bpa"; fi
            done
            printf -- '-\tText size\tshow\tlook\n-\tApp icons (the tray)\tshow\tlook\n' ;;
        layout) if [ -d "$LAYOUTS_DIR" ] && [ -n "$(ls -A "$LAYOUTS_DIR" 2>/dev/null)" ]; then
                for f in "$LAYOUTS_DIR"/*; do _w=$(desk_label "$f"); printf '%s\t%s\topen %s\tlayouts\n-\trename %s\trename %s\n' "$PANEL_GO" "$_w" "${f##*/}" "$_w" "${f##*/}"; done   # by the name it was saved under, and a new name for it
            else printf -- '-\tnone saved: ask at the prompt or save this workspace\tshow\n'; fi
            [ ! -f "$DESK_LAST" ] || jq -r '.suggested // [] | .[]' "$DESK_LAST" 2>/dev/null | while IFS= read -r a; do printf '%s\talso open %s\tadd %s\n' "$PANEL_GO" "$a" "$a"; done   # what spark also suggested for the last layout, one Enter away
            # recent: the layouts opened lately and not saved, five at most
            kept_history layout | while IFS="$TAB" read -r _e _n; do
                [ ! -f "$LAYOUTS_DIR/$_n" ] || continue
                case $_n in layout-delete*|layout-rename*|layout-save*|layout-back*|layout-help*|-*|help) continue ;; esac
                _f=$(desk_kept_file "$_n") || continue
                printf '%s\t%s\topen %s\trecent|%s||%s\n' "$PANEL_GO" "$(desk_label "$_f")" "$_n" "$(kept_when "$_e")" "$_e"
            done | head -5
            [ -z "${SWAYSOCK:-}" ] || printf '%s\tsave this workspace\tsave\n' "$PANEL_GO" ;;
        apps) printf '%s\tterminal\tterminal\n' "$PANEL_GO"   # a terminal window, as Super+Return
            # the apps a layout may open, under their desktop entry's group; three unless full
            panel_apps_known > "$TMP/apps.known"
            while IFS= read -r a; do
                _ag=$(app_group "$(awk -F '\t' -v n="$a" '$1 == n { print $5; exit }' "$TMP/entries" 2>/dev/null)")
                printf '%s\t%s\t%s\n' "$(app_group_order "$_ag")" "$_ag" "$a"
            done < "$TMP/apps.known" | sort -t "$TAB" -k1,1n -k3,3 | { _n=0; while IFS="$TAB" read -r _ao o a; do
                    _n=$((_n + 1)); if [ "${2:-}" != full ] && [ "$_n" -gt 3 ]; then continue; fi
                    printf '%s\t%s\topen %s\t%s\n' "$PANEL_GO" "$a" "$a" "$o"
                done; [ "${2:-}" = full ] || [ "$_n" -le 3 ] || printf -- '-\t%s more\tmore\n' $((_n - 3)); }
            printf '%s\tchoose the allowed apps\tpick\n' "$PANEL_GO" ;;
        spark) printf '%s\tchat\tchat\n' "$PANEL_GO" ;;
        undo) [ -s "$PANEL_CACHE/undo" ] || return 0
            printf -- '-\t%s\tall\n' "$(cut -f3 "$PANEL_CACHE/undo" | paste -sd '|' - | sed "s/|/ $PANEL_SEP /g")" ;;
    esac
}
