# shellcheck extended-analysis=false
# --- facts: what the desktop knows, for the model
# sets: MACHINE_AT_NOW MACHINE_FACTS_EVERY MACHINE_NAME MACHINE_NOW_EVERY MACHINE_NOW_SOON MACHINE_NO_TOOL MACHINE_READS
# reads: BAR_SYS LAYOUTS_DIR NOTES_DIR OS PANEL_APP PANEL_CACHE SAVER_NAMES TAB TMP WALL_SCENES WALL_SHIPPED WM_NAME
# spark reads two files there. NAME.facts: what holds while the machine
# stays as it is, every name as its tool takes it, written only when it
# changed (spark keeps it in the cached part of its prompt). NAME.now:
# what is in use now, its mtime its freshness. Each 0600, written to a
# temp file in the folder and renamed over; the folder 0700. Never in
# either: a window's title, a notification, a note's or a reminder's
# words, a file's contents, a Wi-Fi network that is not saved, a
# password, a token, an address on the LAN.
MACHINE_NAME='spark-shell'   # NAME.facts and NAME.now: the writer's name in the folder
MACHINE_NOW_EVERY=30      # seconds between two.now writes from the bar's loop
MACHINE_NOW_SOON=3        # after a click or a key (the bar drawn again at once), this soon
MACHINE_FACTS_EVERY=300   # seconds between two looks at.facts; the first a minute after the bar starts
MACHINE_AT_NOW=0; MACHINE_AT_FACTS=0
machine_dir() { printf '%s\n' "${SPARK_MACHINE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spark/machine}"; }   # SPARK_MACHINE_DIR: the whole path, for the tests (spark reads the default alone)
machine_live() { [ "$OS" != Darwin ] && wm_live && { [ -n "${SPARK_MACHINE_DIR:-}" ] || [ -n "$(spark_bin)" ]; }; }   # a running sway, and a spark here to read the files
machine_q() { case $1 in ''|*[!A-Za-z0-9._+-]*) printf '"%s"' "$(printf '%s' "$1" | tr -d '"')" ;; *) printf '%s' "$1" ;; esac; }   # machine_q NAME -> NAME, in quotes when it holds more than a word's characters
machine_join() { awk -v s="${1:-, }" '{ o = o (NR > 1 ? s : "") $0 } END { if (NR) print o }'; }   # machine_join [SEP] -- the lines as one, parted by SEP (", ")
machine_names() { while IFS= read -r _mqn; do [ -z "$_mqn" ] || { machine_q "$_mqn"; echo; }; done | machine_join; }   # a name a line -> one line, each name quoted when it must be
machine_clean() { tr '\t' ' ' | scrub_text | awk -v max="$1" 'NF { n += length($0) + 1; if (n > max) exit; print }'; }   # machine_clean MAX -- no tab, no control character, no empty line, MAX characters at most, cut at a line's end
machine_keys() {   # -> the key table's sentences a request asks about, each to its first clause, one line
    layout_keys | awk '$1 ~ /^(Super[+]Return|Super[+]Shift[+]q|Super[+]Escape|Print|Super[+]Ctrl[+]space|Super[+]1[.][.]0)$/ || /^The (volume|brightness) / { if ($1 !~ /^Super[+]1/) sub(/(; |, and ).*/, "."); print }' | machine_join ' '   # the workspaces' second clause says where Shift sends the window
}
# the commands that read and list, named to spark; a change goes through a setting's MCP tool
MACHINE_READS='theme:font list:layout:notes:reminders:desktop keys:desktop display'   # a colon between (awk -v takes no new line)
MACHINE_NO_TOOL='font FACE:dialog:desktop idle'   # the changes no MCP tool makes: the console's font, the dialog opened, the idle screen now
machine_usage() {   # -> SYNOPSIS<tab>WORDS per command of the help; the words on the next line when the synopsis fills its own
    usage | awk '
        function out() { if (syn != "") print syn "\t" desc; syn = "" }
        /^ *spark-shell / { out(); l = $0; sub(/^ */, "", l); if (match(l, /  +/)) { syn = substr(l, 1, RSTART - 1); desc = substr(l, RSTART + RLENGTH) } else { syn = l; desc = "" }; next }
        syn != "" && desc == "" && /^ +[^ ]/ { desc = $0; sub(/^ +/, "", desc); next }
        { out() }
        END { out() }'
}
machine_ways() {   # -> MACHINE_READS as the help writes them, one line
    machine_usage | awk -F '\t' -v reads="$MACHINE_READS" '
        BEGIN { n = split(reads, r, ":"); for (i = 1; i <= n; i++) want["spark-shell " r[i]] = i }
        { syn = $1; desc = $2; base = syn; opt = ""
          if (substr(syn, length(syn)) == "]" && (p = index(syn, " [")) > 0) { base = substr(syn, 1, p - 1); opt = substr(syn, p + 2, length(syn) - p - 2) }
          if (!(base in want) || (base in got)) next
          got[base] = 1; form = base; if (opt ~ /^[a-z]+$/) form = base " " opt
          g = ""; if (desc ~ /^list / && form !~ / list$/) { g = substr(desc, 6); sub(/, .*/, "", g) }
          w[want[base]] = form (g == "" ? "" : " (" g ")") }
        END { s = ""; for (i = 1; i <= n; i++) if (i in w) s = s (s == "" ? "" : ", ") w[i]; if (s != "") print s }'
}
machine_no_tool() {   # -> MACHINE_NO_TOOL as the help writes them, one line
    machine_usage | awk -F '\t' -v forms="$MACHINE_NO_TOOL" '
        BEGIN { n = split(forms, f, ":") }
        { for (i = 1; i <= n; i++) if (!(i in w) && ($1 == "spark-shell " f[i] || index($1, "spark-shell " f[i] " ") == 1)) w[i] = $1 ($2 == "" ? "" : " (" $2 ")") }
        END { s = ""; for (i = 1; i <= n; i++) if (i in w) s = s (s == "" ? "" : "; ") w[i]; if (s != "") print s }'
}
machine_cmds() {   # -> spark-shell's commands as the help says them, a line a verb; the keys and idle left out
    usage | sed -n 's/^ *\(spark-shell [^ ].*\)$/\1/p' | sed 's/   *.*$//' \
        | grep -E '^spark-shell (theme|font|layout|notes|reminders|desktop [a-z]+|bar|dialog)( |$)' | grep -vxE 'spark-shell desktop (portals|keys|idle .*)' \
        | awk '
            { n = split($0, w, " "); key = w[2]; s = 3; if (key == "desktop") { key = key " " w[3]; s = 4 }
              alt = ""; for (i = s; i <= n; i++) alt = alt (alt == "" ? "" : " ") w[i]
              if (!(key in na)) { na[key] = 0; order[++k] = key; top[key] = w[2] }
              if (substr(alt, 1, 1) == "[" && substr(alt, length(alt)) == "]" && index(substr(alt, 2), "[") == 0) { alt = substr(alt, 2, length(alt) - 2); bare[key] = 1 }   # [list]: the verb alone, or with it
              if (alt == "") { bare[key] = 1; next }
              for (j = 1; j <= na[key]; j++) if (index(alt, a[key, j] " ") == 1) { a[key, j] = a[key, j] " [" substr(alt, length(a[key, j]) + 2) "]"; next }   # on|off --desktop: on|off [--desktop]
              a[key, ++na[key]] = alt }
            END { for (i = 1; i <= k; i++) { key = order[i]; s = ""; for (j = 1; j <= na[key]; j++) s = s (j > 1 ? "|" : "") a[key, j]
                      if (s == "") s = key; else if (bare[key]) s = key " [" s "]"; else s = key " " s
                      t = top[key]; if (key ~ /^desktop (time|pointer|notifications|storage)$/) t = "desktop+"
                      if (t in line) line[t] = line[t] "; " substr(s, index(s, " ") + 1); else { line[t] = "spark-shell " s; to[++m] = t } }
                  for (i = 1; i <= m; i++) if (to[i] != "desktop+" && to[i] != "font") print "- " line[to[i]]
                  if ("font" in line) print "+ " line["font"]
                  if ("desktop+" in line) print "+ " line["desktop+"] }'   # + marks the lines that go last
}
machine_bt_kind() {   # machine_bt_kind ADDRESS -> the device's kind from bluez's icon, or nothing
    case $(bar_timeout bluetoothctl info "$1" 2>/dev/null | sed -n 's/^[[:space:]]*Icon: *//p' | sed -n 1p) in
        audio-card|audio-speakers) echo speaker ;; audio-headphones) echo headphones ;; audio-headset) echo headset ;;
        input-keyboard) echo keyboard ;; input-mouse) echo mouse ;; input-tablet) echo tablet ;; input-gaming) echo gamepad ;;
        phone) echo phone ;; computer) echo computer ;; camera*) echo camera ;; printer) echo printer ;; multimedia-player) echo 'media player' ;;
    esac
}
machine_snd_kind() {   # machine_snd_kind NAME -> a paired Bluetooth device's kind ($TMP/machine.bt), HDMI, USB, or nothing
    _msk=$(awk -F '\t' -v n="$1" '$1 == n { print ($2 == "" ? "Bluetooth" : "Bluetooth " $2); exit }' "$TMP/machine.bt" 2>/dev/null)
    if [ -n "$_msk" ]; then printf '%s' "$_msk"; return 0; fi
    case $1 in *HDMI*|*DisplayPort*) printf 'HDMI' ;; *USB*) printf 'USB' ;; esac
}
machine_snd_list() { snd_devices "$1" | LC_ALL=C sort -t "$TAB" -k1,1 | while IFS="$TAB" read -r _msn _msd; do _msw=$(machine_snd_kind "$_msn"); printf '%s%s\n' "$(machine_q "$_msn")" "${_msw:+ ($_msw)}"; done | machine_join; }   # machine_snd_list out|mic -> the devices by name, sorted, each with its kind
machine_screens() {   # -> the screens: port, make and model (never the serial), place, turn and mode
    screens_json | jq -r --arg main "$(screen_main || :)" '
        [.[] | select(.name != null)] as $all | [$all[] | select(.active)] as $on
        | ($on | map(.rect.x // 0)) as $xs | ($on | map(.rect.y // 0)) as $ys
        | [$all[] | ([.make, .model] | map(select(. != null and . != "" and . != "Unknown")) | join(" ")) as $mm
            | ([.make, .model, .serial] | map(if . == null or . == "" then "Unknown" else . end) | join(" ")) as $id
            | (.rect.x // 0) as $x | (.rect.y // 0) as $y
            | [.name + (if $mm == "" then "" else " = " + $mm end)]
              + (if (.name | test("^(eDP|LVDS|DSI)")) then ["the laptop screen"] else [] end)
              + (if .active then
                    (if ($on | length) < 2 then []
                     elif ($xs | min) != ($xs | max) then [if $x == ($xs | min) then "on the left" elif $x == ($xs | max) then "on the right" else "in the middle" end]
                     elif ($ys | min) != ($ys | max) then [if $y == ($ys | min) then "on top" elif $y == ($ys | max) then "below" else "in the middle" end]
                     else [] end)
                    + (if .transform == "90" or .transform == "270" then ["turned " + .transform + ", portrait"] elif .transform == "180" then ["turned 180"] elif ((.transform // "") | startswith("flipped")) then ["flipped"] else [] end)
                    + (if (.current_mode.width // 0) > 0 then ["\(.current_mode.width)x\(.current_mode.height)"] else [] end)
                    + (if (.scale // 1) != 1 then ["scale \(.scale)"] else [] end)
                    + (if $main != "" and ($main == .name or $main == $id) then ["workspace 1 starts there"] else [] end)
                 else ["off"] end)
            | join(", ")] | join("; ")' 2>/dev/null
}
machine_facts() {   # -> the .facts lines
    : > "$TMP/machine.bt"; _mbt=''   # the paired Bluetooth devices, NAME<tab>KIND
    if ls -d "$BAR_SYS"/class/bluetooth/hci* >/dev/null 2>&1 && command -v bluetoothctl >/dev/null 2>&1 && bt_running; then
        _mbt=1
        bt_list_now | awk -F '\t' '$3 == 1' | LC_ALL=C sort -t "$TAB" -k2,2 | head -8 | while IFS="$TAB" read -r _mba _mbn _mbp _mbc; do printf '%s\t%s\n' "$_mbn" "$(machine_bt_kind "$_mba")"; done > "$TMP/machine.bt"
    fi
    # the session
    _msv=$(wm_version | jq -r 'if (.major // null) != null then "\(.major).\(.minor)" + (if (.patch // 0) > 0 then ".\(.patch)" else "" end) else "" end' 2>/dev/null || :)
    _mpv=$(panel_version); _mwl=$(wm_tools_said)
    ! command -v notify-send >/dev/null 2>&1 || _mwl="${_mwl:+$_mwl, }notifications notify-send"
    printf -- "- Session: %s%s on Wayland (X11 apps run through Xwayland), set up by spark-shell%s; %s.\n" "$WM_NAME" "${_msv:+ $_msv}" "${_mpv:+ v$_mpv}" "${_mwl:+$_mwl, }$(wm_client)"
    _mkd=$(layout_keys | awk '$2 == "home.open." { print $1; exit }')
    printf -- '- spark-shell is this desktop: the bar at the top; home%s holds native actions and optional conversation.\n' "${_mkd:+ ($_mkd)}"
    _msc=$(machine_screens); [ -z "$_msc" ] || printf -- '- Screens: %s.\n' "$_msc"
    echo "- Workspaces: the bar names each N:GLYPH; $(wm_workspace_said)."
    if [ -n "${SND:-}" ]; then printf -- '- Sound outputs: %s. Inputs: %s.\n' "$(machine_snd_list out | grep . || echo none)" "$(machine_snd_list mic | grep . || echo none)"
    else echo '- Sound: no audio system answers.'; fi
    if [ -n "$_mbt" ]; then
        if [ -s "$TMP/machine.bt" ]; then printf -- '- Bluetooth, paired: %s.\n' "$(while IFS="$TAB" read -r _mbn _mbk; do printf '%s%s\n' "$(machine_q "$_mbn")" "${_mbk:+ ($_mbk)}"; done < "$TMP/machine.bt" | machine_join)"
        else echo '- Bluetooth: nothing paired.'; fi
    fi
    # the network: saved networks only, never one around
    _mnl=$(bar_wired | sed 's/^/wired /' | machine_join)
    _mwi=$(wifi_if)
    if [ -n "$_mwi" ]; then
        _mwt=$(wifi_tool)
        if [ -n "$_mwt" ]; then _mnl="${_mnl:+$_mnl; }Wi-Fi $_mwi through $_mwt, saved networks: $(wifi_known | cut -f2 | head -8 | machine_names | grep . || echo none)"
        else _mnl="${_mnl:+$_mnl; }Wi-Fi $_mwi, with no tool that answers for it (nmcli, iwctl or wpa_cli)"; fi
    fi
    [ -z "$_mnl" ] || printf -- '- Network: %s.\n' "$_mnl"
    if [ -n "$KEYBOARD" ]; then
        kb_names | cut -f2- | tr '\t' '\n' > "$TMP/machine.kb"   # sway's long names, in KEYBOARD's order
        _mkl=$(_mki=0; for _mkx in $KEYBOARD; do _mki=$((_mki + 1)); _mkn=$(sed -n "${_mki}p" "$TMP/machine.kb"); printf '%s%s\n' "$_mkx" "${_mkn:+ ($_mkn)}"; done | machine_join)
        _mkl="Keyboard layouts: $_mkl"
    else _mkl="Keyboard: sway's own layout (spark-shell desktop keyboard us br sets some)"; fi
    printf -- '- %s; caps key %s, repeat %s ms, %s a second. Pointer: tap to click %s, natural scroll %s, speed %s.\n' "$_mkl" "$KEY_CAPS" "$KEY_REPEAT_DELAY" "$KEY_REPEAT_RATE" "$POINTER_TAP" "$POINTER_SCROLL" "$POINTER_SPEED"
    # the names: the notes by file, never a word of one
    _mly=$(ls -A "$LAYOUTS_DIR" 2>/dev/null | head -8 | machine_names)
    _mnt=''; _mnn=0
    if [ -d "$NOTES_DIR" ]; then
        ls -t -- "$NOTES_DIR"/*.md 2>/dev/null | while IFS= read -r _mnf; do [ ! -f "$_mnf" ] || [ -L "$_mnf" ] || printf '%s\n' "${_mnf##*/}"; done > "$TMP/machine.notes"
        _mnn=$(grep -c . "$TMP/machine.notes" || :); _mnt=$(head -8 "$TMP/machine.notes" | LC_ALL=C sort | machine_names)   # the newest eight, by name: a note edited is no new fact
        [ "${_mnn:-0}" -le 8 ] || _mnt="$_mnt and $((_mnn - 8)) more"
    fi
    printf -- '- Saved layouts: %s. Notes in ~/notes, by file: %s.\n' "${_mly:-none}" "${_mnt:-none}"
    palette_names > "$TMP/machine.pal"; palette_darks > "$TMP/machine.dark"
    _mst=$(theme_saved_names | head -8 | machine_names)
    printf -- "- Palettes, dark: %s; light: %s; none is terminal default colors.%s\n" \
        "$(grep -xFf "$TMP/machine.dark" "$TMP/machine.pal" | machine_join)" "$(grep -vxFf "$TMP/machine.dark" "$TMP/machine.pal" | machine_join)" "${_mst:+ Saved themes: $_mst.}"
    _msa=clock; ! saver_can || _msa="clock $SAVER_NAMES"
    printf -- "- Wallpapers: %s, $(set -- $WALL_SCENES; echo $#) scenes that move, or default. Savers: %s.\n" "$(for _e in $WALL_SHIPPED; do printf '%s\n' "${_e%%:*}"; done | machine_join)" "$(printf '%s\n' $_msa | machine_join)"
    # the printers from the section's cache: the facts never ask CUPS
    if [ -s "$PANEL_CACHE/printers.status" ] && sed 1d "$PANEL_CACHE/printers.status" > "$TMP/machine.pr" 2>/dev/null && [ -s "$TMP/machine.pr" ]; then
        _mpr=$(jq -r '.default as $d | [.queues[]? | .name + (if .name == $d then " (the default)" else "" end)] | join(", ")' "$TMP/machine.pr" 2>/dev/null || :)
        printf -- '- Printers: %s.\n' "${_mpr:-none}"
    fi
    # how to read the state
    _mrs=''; [ -z "$(mcp_mine)" ] || _mrs="spark mcp read SERVER spark-shell://SERVER/rows (SERVER is the first word of a tool line below); "
    _mrt=$(wm_queries_said)
    case ${SND:-} in wpctl) _mrt="$_mrt, wpctl status" ;; pactl) _mrt="$_mrt, pactl list sinks" ;; alsa) _mrt="$_mrt, amixer" ;; esac
    [ -z "$_mbt" ] || _mrt="$_mrt, bluetoothctl show"
    printf -- '- Reading state: %s%s.\n' "$_mrs" "$_mrt"
    _mwy=$(machine_ways); [ -z "$_mwy" ] || printf -- '- To read or list with spark-shell: %s.\n' "$_mwy"
    if [ -n "$(mcp_mine)" ]; then   # the tools are on spark's list
        _mnt=$(machine_no_tool)
        printf -- '- A change to a desktop setting goes through its MCP tool below (spark mcp call SERVER TOOL KEY=VALUE, SERVER the first word of its tool line), not a spark-shell command%s.\n' "${_mnt:+; with no tool for it: $_mnt}"
        printf -- '- Keys: %s\n' "$(machine_keys)"
    else   # no tool on spark's list: the commands are the ways to change
        printf -- '- Keys: %s\n' "$(machine_keys)"
        machine_cmds | sed 's/^+ /- /'   # last: past 3,000 characters the end is cut first
    fi
}
machine_awake() { screens_json | jq -e '[.[] | select(.active) | if .power != null then .power elif .dpms != null then .dpms else true end] | length == 0 or any' >/dev/null 2>&1; }   # -> 0 when a screen is on (none told: on)
machine_now() {   # -> the .now lines
    wm_tree | jq -r --arg me "$PANEL_APP" '
        [.nodes[]? | select(.type == "output") | .nodes[]? | select(.type == "workspace") | . as $w
         | .. | objects | select(.pid? != null and (.type? == "con" or .type? == "floating_con") and (.app_id // "") != $me)
         | "\(.id) \(.app_id // .window_properties.class // "unknown")" + (if $w.name == "__i3_scratch" then " in the scratchpad" else " on \($w.num)" end) + (if .focused then ", focused" else "" end)]
        | if length == 0 then "- No window is open." else "- Windows open (sway con id, app_id, workspace): " + join("; ") + "." end' 2>/dev/null   # never a title
    wm_workspaces | jq -r '[.[] | select(.name != "__i3_scratch") | .name + " on " + .output + (if .focused then " (focused)" elif .visible then " (shown)" else "" end)]
        | if length == 0 then empty else "- Workspaces: " + join(", ") + "." end' 2>/dev/null
    screens_json | jq -r '[.[] | select(.active and (if .power != null then .power elif .dpms != null then .dpms else true end) == false) | .name] | if length == 0 then empty else "- Screens off now (the lock turns them off): " + join(", ") + "." end' 2>/dev/null
    if [ -n "${SND:-}" ]; then
        snd_out > "$TMP/machine.out"; snd_mic > "$TMP/machine.mic"
        if [ -s "$TMP/machine.out" ]; then
            _mol=$(sed -n 2p "$TMP/machine.out"); _mos="output $(machine_q "$(sed -n 1p "$TMP/machine.out")") in use"
            [ "$_mol" = - ] || [ -z "$_mol" ] || _mos="$_mos, volume $_mol%"
            if [ "$(sed -n 3p "$TMP/machine.out")" = 1 ]; then _mos="$_mos, muted"; else _mos="$_mos, not muted"; fi
        else _mos='no output'; fi
        if [ -s "$TMP/machine.mic" ]; then
            _mil=$(sed -n 4p "$TMP/machine.mic"); _mos="$_mos; microphone $(machine_q "$(sed -n 1p "$TMP/machine.mic")") connected"
            if [ "$(sed -n 3p "$TMP/machine.mic")" = 1 ]; then _mos="$_mos, muted"; else _mos="$_mos, not muted"; fi
            [ "$_mil" = - ] || [ -z "$_mil" ] || _mos="$_mos, level $_mil%"
            [ "$(sed -n 2p "$TMP/machine.mic")" != 1 ] || _mos="$_mos, recording now"
        else _mos="$_mos; no microphone connected"; fi
        printf -- '- Sound: %s.\n' "$_mos"
    fi
    if ls -d "$BAR_SYS"/class/bluetooth/hci* >/dev/null 2>&1 && command -v bluetoothctl >/dev/null 2>&1 && bt_running; then
        if ! bt_powered; then echo '- Bluetooth off.'
        else
            _mbc=$(bt_list_now | awk -F '\t' '$4 == 1 { print $2 }' | machine_names)
            if [ -n "$_mbc" ]; then printf -- '- Bluetooth on; connected now: %s.\n' "$_mbc"; else echo '- Bluetooth on, nothing connected.'; fi
        fi
    fi
    _mnl=''   # never an address
    for _mni in $(bar_wired); do
        if [ "$(cat "$BAR_SYS/class/net/$_mni/carrier" 2>/dev/null)" != 1 ]; then _mns=down
        elif [ -n "$(bar_addr "$_mni")" ]; then _mns='up with an address'; else _mns='up, no address yet'; fi
        _mnl="${_mnl:+$_mnl; }wired $_mni $_mns"
    done
    _mwi=$(wifi_if)
    if [ -n "$_mwi" ]; then
        _mwc=$(wifi_connected)
        if [ -n "$_mwc" ]; then
            _mws="connected to $(machine_q "$_mwc")"; _mwp=$(bar_wifi_pct)
            [ -z "$_mwp" ] || _mws="$_mws, signal ${_mwp%% *}%"
            case ${_mwp#* } in ''|"$_mwp") ;; *) _mws="$_mws, with an address" ;; esac
        elif [ "$(cat "$BAR_SYS/class/net/$_mwi/operstate" 2>/dev/null)" = up ]; then _mws='up, not connected'
        else _mws=down; fi
        _mnl="${_mnl:+$_mnl; }Wi-Fi $_mwi $_mws"
    fi
    [ -z "$_mnl" ] || printf -- '- Network: %s.\n' "$_mnl"
    _mka=$(kb_active); [ -n "$_mka" ] || _mka=${KEYBOARD%% *}; [ -n "$_mka" ] || _mka="sway's own"
    case ${THEME:-none} in none) _mpa="none (terminal default colors)" ;; *) _mpa=$THEME ;; esac
    _mwa=$(wall_name); [ -n "$_mwa" ] || _mwa='a picture of yours'
    _mla=''; [ -n "${MACHINE_START:-}" ] || _mla=$(light_get)   # not at the start: DDC/CI is slow, the bar's loop brings it
    _mss=''; [ "$DISPLAY_SAVER" = clock ] || _mss=" (saver $DISPLAY_SAVER)"
    printf -- "- Keyboard layout in use: %s. Palette %s, wallpaper %s.%s Idle screen %s%s, lock %s.\n" "$_mka" "$_mpa" "$_mwa" "${_mla:+ Brightness $_mla%.}" "$(idle_words "$DISPLAY_IDLE")" "$_mss" "$(idle_words "$DISPLAY_LOCK")"
    if command -v lsblk >/dev/null 2>&1; then
        _mdr=$(storage_drives | cut -f3 | machine_names)
        if [ -n "$_mdr" ]; then printf -- '- Drives plugged in: %s.\n' "$_mdr"; else echo '- No drive is plugged in.'; fi
    fi
    if notify_up; then if notify_dnd; then _mdd=on; else _mdd=off; fi
    elif [ "$DO_NOT_DISTURB" = yes ]; then _mdd=on; else _mdd=off; fi
    if [ "$DESKTOP_BAR" = yes ]; then _mbs="shown $(bar_place_words "$BAR_POSITION")"; else _mbs=hidden; fi
    printf -- '- The bar is %s; do not disturb is %s.\n' "$_mbs" "$_mdd"
}
machine_put() {   # machine_put now|facts FILE -- FILE as NAME.KIND in _md, 0600, renamed over; the same content is left, .now until it is 3 minutes old
    _mpf=$_md/$MACHINE_NAME.$1
    [ -s "$2" ] || return 0
    if [ -f "$_mpf" ] && [ ! -L "$_mpf" ] && cmp -s "$2" "$_mpf"; then
        [ "$1" = now ] && [ -n "$(find "$_mpf" -mmin +3 2>/dev/null)" ] || return 0
    fi
    _mpt=$(mktemp "$_md/.$MACHINE_NAME.$1.XXXXXX") || return 0
    if cat "$2" > "$_mpt" && chmod 600 "$_mpt" && mv -f "$_mpt" "$_mpf"; then return 0; fi
    rm -f "$_mpt"
}
machine_write() (   # machine_write now|all|tick -- .now, and .facts with all (tick: while a screen is on); a second writer gives way
    config_load
    [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && grep -qs 'rendered by spark-shell' "$(wm_config_file)" && wm_up || exit 0
    [ -n "${SPARK_MACHINE_DIR:-}" ] || [ -n "$(spark_bin)" ] || exit 0
    _md=$(machine_dir)
    [ -d "$_md" ] || (umask 077 && mkdir -p "$_md") || exit 0
    [ -d "$_md" ] && [ ! -L "$_md" ] || exit 0
    _mlk=$_md/.$MACHINE_NAME.lock   # a lock left by a dead writer is taken after 2 minutes
    lock_take "$_mlk" || { [ -n "$(find "$_mlk" -prune -mmin +2 2>/dev/null)" ] && lock_drop "$_mlk" && lock_take "$_mlk"; } || exit 0
    TMP=$(mktemp -d) || { lock_drop "$_mlk"; exit 0; }
    trap 'rm -rf "$TMP"; lock_drop "$_mlk"' EXIT
    trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 141' PIPE
    SND=$(snd_tool)
    { machine_now || :; } | machine_clean 1200 > "$TMP/now"
    machine_put now "$TMP/now"
    case ${1:-} in all) ;; tick) machine_awake || exit 0 ;; *) exit 0 ;; esac   # screens asleep: .facts keeps what it said while they were on
    { machine_facts || :; } | machine_clean 3000 > "$TMP/facts"
    machine_put facts "$TMP/facts"
)
machine_tick() {   # machine_tick SIGNALED -- .now every MACHINE_NOW_EVERY s (MACHINE_NOW_SOON after a click), .facts every MACHINE_FACTS_EVERY; in the background
    machine_live || return 0
    _mtk=$(date +%s)
    [ $((_mtk - MACHINE_AT_NOW)) -ge "$MACHINE_NOW_EVERY" ] || { [ "$1" = 1 ] && [ $((_mtk - MACHINE_AT_NOW)) -ge "$MACHINE_NOW_SOON" ]; } || return 0
    MACHINE_AT_NOW=$_mtk; _mtw=now
    [ $((_mtk - MACHINE_AT_FACTS)) -lt "$MACHINE_FACTS_EVERY" ] || { MACHINE_AT_FACTS=$_mtk; _mtw=tick; }
    machine_write "$_mtw" </dev/null >/dev/null 2>&1 &
}
machine_start() (   # at the desktop's start: both files, then spark mcp once when spark-shell's providers are on its list
    MACHINE_START=1
    machine_write all
    [ -n "$(mcp_mine)" ] || exit 0
    _msp=$(spark_bin); [ -n "$_msp" ] || exit 0
    "$_msp" mcp </dev/null >/dev/null 2>&1 || :
)
machine_rm() { _mrd=$(machine_dir); for _mrk in "$@"; do rm -f "$_mrd/$MACHINE_NAME.$_mrk" "$_mrd/.$MACHINE_NAME.$_mrk".*; done; }   # machine_rm KIND... -- the files and their temp files removed
machine_there() { _mtd=$(machine_dir); for _mtf in facts now; do [ ! -e "$_mtd/$MACHINE_NAME.$_mtf" ] && [ ! -L "$_mtd/$MACHINE_NAME.$_mtf" ] || return 0; done; return 1; }   # -> 0 when one is there
machine_off() {   # the two files and the lock removed; a row when there were any
    _mof=''; ! machine_there || _mof=1
    machine_rm facts now; rmdir "$(machine_dir)/.$MACHINE_NAME.lock" 2>/dev/null || :
    [ -z "$_mof" ] || row ok machine "what the desktop told spark's prompt line is gone ($(files_home "$(machine_dir)"))"
}

# ================================================================ the panel
# `spark-shell panel [SECTION] --list` prints the list as text, and
# `panel SECTION ACTION [ARG]` does one step by hand: the tests' doors.

