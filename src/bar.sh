# shellcheck extended-analysis=false
# ---------------------------------------------------------------- the bar
# sets: BAR_BT BAR_BT_OFF BAR_DEV BAR_DND BAR_DND_PLAIN BAR_DUE BAR_DUE_PLAIN BAR_FULL BAR_GAP BAR_GROUP_GAP BAR_KB BAR_KB_PLAIN BAR_LAN BAR_LIGHT BAR_MIC BAR_MIC_OFF BAR_NOTE BAR_OUT BAR_OUT_OFF BAR_PAD BAR_PALETTE BAR_PID BAR_PROC BAR_SHADE BAR_STEPS BAR_SYS BAR_WIFI BAR_WS_ORDER
# reads: BAR_ASOUNDRC BAR_LEVELS BAR_MODULES CONFIG GLYPH_FAMILIES LAYOUT_ON NOTIFY_MODE OS PANEL_DOT PANEL_PROMPT PANEL_SEP PANEL_WARN REPO STATE_DIR TAB THEME_KEYS TMP
# spark's bar, or sway's own where it cannot run, reads `spark-shell bar status`:
# i3bar JSON every 15 s and on SIGUSR1 to the pid in STATE_DIR/bar.pid
BAR_SYS=${SPARK_SHELL_SYS:-/sys}      # tests: a fixture /sys and /proc
BAR_PROC=${SPARK_SHELL_PROC:-/proc}
BAR_DEV=${SPARK_SHELL_DEV:-/dev}      # tests: the i2c devices
BAR_PID=$STATE_DIR/bar.pid
BAR_GAP=14                            # px between blocks
BAR_GROUP_GAP=28                      # px between groups
BAR_FULL=$(printf '\342\226\210')     # U+2588 full block
BAR_SHADE=$(printf '\342\226\221')    # U+2591 light shade
BAR_LAN=$(printf '\342\207\205')      # U+21C5 up and down arrows
BAR_WIFI=$(printf '\342\227\240')     # U+25E0 upper half circle
BAR_BT=$(printf '\342\234\246')       # U+2726 black four-pointed star
BAR_BT_OFF=$(printf '\342\234\247')   # U+2727 white four-pointed star
BAR_OUT=$(printf '\342\227\200')      # U+25C0 black left-pointing triangle
BAR_OUT_OFF=$(printf '\342\227\201')  # U+25C1 white left-pointing triangle
BAR_MIC=$(printf '\342\227\211')      # U+25C9 fisheye
BAR_MIC_OFF=$(printf '\342\227\213')  # U+25CB white circle
BAR_LIGHT=$(printf '\342\230\274')    # U+263C white sun with rays
BAR_KB=$(printf '\342\214\227')       # U+2317 viewdata square
BAR_DUE=$(printf '\342\247\227')      # U+29D7 black hourglass
BAR_DND=$(printf '\342\217\276')      # U+23FE power sleep symbol
BAR_NOTE=$(printf '\342\232\221')     # U+2691 black flag
BAR_PAD=$(printf '\342\212\237')      # U+229F squared minus
# the three signs above that only the Monaspace faces draw (keyboard, reminder, do not disturb), as every family's DejaVu Sans Mono has them
BAR_KB_PLAIN=$(printf '\342\214\250')    # U+2328 keyboard
BAR_DUE_PLAIN=$(printf '\342\227\267')   # U+25F7 white circle with upper right quadrant
BAR_DND_PLAIN=$(printf '\342\230\276')   # U+263E last quarter moon
bar_signs() { case $(font_spec) in 'Monaspace '*) ;; *) BAR_KB=$BAR_KB_PLAIN; BAR_DUE=$BAR_DUE_PLAIN; BAR_DND=$BAR_DND_PLAIN ;; esac; }   # a bar whose face is no Monaspace takes them; a line runs in a subshell, so the next one starts from Monaspace's again
# a test holds every glyph to one cell
family_set() {   # family_set FAMILY -- sets FAM_NOW and the FAM_ glyphs
    case $1 in star|banner) ;; *) set -- stone ;; esac
    [ "${FAM_NOW:-}" != "$1" ] || return 0
    case $1 in   # on, off, think, key open, key close
        star) _fe='\342\224\201 \342\224\200 \342\234\246 { }' ;;   # U+2501 U+2500 horizontals; U+2726 star; braces
        banner) _fe='\342\226\256 \342\226\257 \342\236\244 [ ]' ;;   # U+25AE U+25AF rectangles; U+27A4 arrowhead; square brackets
        *) _fe='\342\226\260 \342\226\261 \342\226\260 \342\237\250 \342\237\251' ;;   # U+25B0 U+25B1 parallelograms; U+27E8 U+27E9 angle brackets
    esac
    # shellcheck disable=SC2059   # the escapes are the format
    _fb=$(printf "$_fe \302\267")   # U+00B7 middle dot
    FAM_ON=${_fb%% *}; _fb=${_fb#* }; FAM_OFF=${_fb%% *}; _fb=${_fb#* }; FAM_THINK=${_fb%% *}; _fb=${_fb#* }
    FAM_KEY_OPEN=${_fb%% *}; _fb=${_fb#* }; FAM_KEY_CLOSE=${_fb%% *}; FAM_DOT=${_fb#* }
    FAM_NOW=$1
}
family_key() { printf '%s%s%s' "${FAM_KEY_OPEN:-}" "$1" "${FAM_KEY_CLOSE:-}"; }   # family_key TEXT -> TEXT in the family's key frame: a workspace's number
roman() {   # roman N -> Roman numerals; N itself past 3999: banner's workspace labels through v0.146
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 3999 ] || { printf '%s' "$1"; return 0; }
    _rn=$1; _ro=''
    for _rp in 1000:M 900:CM 500:D 400:CD 100:C 90:XC 50:L 40:XL 10:X 9:IX 5:V 4:IV 1:I; do
        while [ "$_rn" -ge "${_rp%%:*}" ]; do _ro=$_ro${_rp#*:}; _rn=$((_rn - ${_rp%%:*})); done
    done
    printf '%s' "$_ro"
}
# an earlier bar's workspace glyphs; still ours
BAR_WS_ORDER=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; BAR_WS_ORDER=${BAR_WS_ORDER:-$STATE_DIR}/ws-order
BAR_STEPS='\342\226\202 \342\226\204 \342\226\206 \342\226\210'   # U+2582 2584 2586 2588

bar_esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/\\/\\\\/g; s/"/\\"/g'; }   # pango, then JSON
bar_span() { printf "<span foreground='#%s'>%s</span>" "$1" "$2"; }   # bar_span RRGGBB MARKUP
bar_json() { printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }   # bar_json TEXT -> TEXT as it goes inside a JSON string
bar_str() { _bs=$1; case $_bs in *[\\\"]*|*[[:cntrl:]]*) _bs=$(bar_json "$_bs") ;; esac; }   # bar_str TEXT -> _bs, the same as bar_json; a plain TEXT costs no other program
bar_cells() { _bc=$(printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c); _bc=$((_bc)); }   # bar_cells TEXT -> _bc, its characters, a cell each
# a block of sway's bar, which draws full_text. CELLS is the widest the block gets, in cells of the bar's font; LABEL names
# the control and its state in plain text; MORE is words: control=toggle|level (open when none), state=unavailable (ok
# when none)
bar_block() {   # bar_block NAME INSTANCE MARKUP CELLS LABEL [GAP] [MORE]
    bar_str "$5"; _bbc=open; _bbs=ok
    for _bbw in ${7:-}; do
        case $_bbw in
            control=*) _bbc=${_bbw#control=} ;;
            state=*) _bbs=${_bbw#state=} ;;
        esac
    done
    printf '{"name":"%s","instance":"%s","full_text":"%s","cells":%s,"label":"%s","control":"%s","state":"%s","markup":"pango","separator":false,"separator_block_width":%s}' \
        "$1" "$2" "$3" "$4" "$_bs" "$_bbc" "$_bbs" "${6:-$BAR_GAP}"
}
bar_gauge() {   # bar_gauge LEVEL MUTED [CELLS] [COLOR] -> CELLS (5) cells
    cells=${3:-5}; n=$(( ($1 * cells + 50) / 100 )); [ "$1" -le 0 ] || [ "$n" -gt 0 ] || n=1; [ "$n" -le "$cells" ] || n=$cells
    [ -n "${FAM_NOW:-}" ] || family_set stone
    full=''; i=0; while [ "$i" -lt "$n" ]; do full="$full$FAM_ON"; i=$((i + 1)); done
    rest=''; while [ "$i" -lt "$cells" ]; do rest="$rest$FAM_OFF"; i=$((i + 1)); done
    c=${4:-$HEX_ACCENT}; [ "$2" != 1 ] || c=$HEX_MUTED
    printf '%s%s' "$(bar_span "$c" "$full")" "$(bar_span "$HEX_MUTED" "$rest")"
}
bar_ws_label() {   # bar_ws_label N -> the label in the family set
    [ "$1" -ge 1 ] 2>/dev/null || return 1
    family_key "$1"
}
bar_ws_ours() {   # bar_ws_ours N MARK -> 0 when MARK is ours for N
    [ "$2" != "$1" ] || return 0
    for _wf in $GLYPH_FAMILIES; do [ "$2" != "$(family_set "$_wf"; bar_ws_label "$1")" ] || return 0; done
    [ "$2" != "$(printf '\342\227\202%s\342\226\270' "$1")" ] && [ "$2" != "$(roman "$1")" ] || return 0   # through v0.146: star's U+25C2 U+25B8 triangles, banner's Roman number
    [ -s "$BAR_WS_ORDER" ] || return 1
    _wg=$(sed -n "${1}p" "$BAR_WS_ORDER" 2>/dev/null); [ -n "$_wg" ] || return 1
    # shellcheck disable=SC2059   # the line is the octal escapes
    [ "$2" = "$(printf "$_wg")" ]
}
bar_ws_names() {   # renames "3" or "3 writing" to "3:LABEL" or "3:LABEL writing"
    command -v jq >/dev/null 2>&1 || return 0
    family_set "$(bar_style GLYPH_FAMILY stone)"
    wm_workspaces | jq -r '.[] | select(.name | test("^[0-9]+([: ]|$)")) | "\(.num)\t\(.name)"' 2>/dev/null |
        while IFS="$TAB" read -r n name; do
            g=$(bar_ws_label "$n") || continue
            _wr=${name#"$n"}
            case $_wr in
                :*) _wr=${_wr#:}; _wx=${_wr%% *}; case $_wr in *' '*) _wr=" ${_wr#* }" ;; *) _wr='' ;; esac
                    [ "$_wx" = "$g" ] || bar_ws_ours "$n" "$_wx" || continue ;;   # never a name the user gave
            esac
            [ "$name" = "$n:$g$_wr" ] || wm_send "rename workspace \"$name\" to \"$n:$g$_wr\"" >/dev/null 2>&1 || :
        done
}
bar_ws_watch() {   # on sway's workspace events: the labels again
    bar_ws_names
    wm_events '["workspace"]' | while IFS= read -r _e; do   # -r: one event a line
        kill -0 "$$" 2>/dev/null || break   # the loop that started this is gone, its group not ended (its bar crashed): the reader leaves, and the subscriber ends at its next write
        case $_e in *'"change": "init"'*|*'"change":"init"'*|*'"change": "rename"'*|*'"change":"rename"'*) bar_ws_names ;; esac   # sway spaces its JSON; a rename drops the label
    done
}
bar_timeout() { if command -v timeout >/dev/null 2>&1; then timeout 3 "$@"; else "$@"; fi; }

# --- the hardware
bar_addr() { ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1; }   # bar_addr IFACE -> a.b.c.d or nothing
bar_wired() {   # -> the wired interfaces; type 1 is ethernet
    for d in "$BAR_SYS"/class/net/*; do
        [ -e "$d/device" ] && [ ! -d "$d/wireless" ] && [ "$(cat "$d/type" 2>/dev/null)" = 1 ] || continue
        basename "$d"
    done
    return 0
}
bar_wireless() { for d in "$BAR_SYS"/class/net/*/wireless; do [ -d "$d" ] && basename "$(dirname "$d")"; done; return 0; }
bar_lan() {   # -> "up ADDR", "down", or nothing
    any=''; up=''
    for i in $(bar_wired); do
        any=1
        [ "$(cat "$BAR_SYS/class/net/$i/carrier" 2>/dev/null)" = 1 ] || continue
        up="up $(bar_addr "$i")"; break
    done
    [ -n "$any" ] || return 0
    if [ -n "$up" ]; then printf '%s\n' "$up"; else echo down; fi
}
bar_wifi_pct() {   # -> "PERCENT ADDR", else nothing
    for i in $(bar_wireless); do
        [ "$(cat "$BAR_SYS/class/net/$i/operstate" 2>/dev/null)" = up ] || continue
        lvl=''
        if command -v iw >/dev/null 2>&1; then   # -100 dBm 0, -50 dBm 100
            dbm=$(iw dev "$i" link 2>/dev/null | awk '/signal:/ {print $2; exit}')
            [ -z "$dbm" ] || lvl=$(( (dbm + 100) * 2 ))
        fi
        if [ -z "$lvl" ]; then   # link quality, out of 70
            q=$(awk -v i="$i:" '$1 == i {gsub(/\./, "", $3); print $3; exit}' "$BAR_PROC/net/wireless" 2>/dev/null)
            [ -z "$q" ] || lvl=$(( q * 100 / 70 ))
        fi
        [ -n "$lvl" ] || lvl=0; [ "$lvl" -ge 0 ] || lvl=0; [ "$lvl" -le 100 ] || lvl=100
        printf '%s %s\n' "$lvl" "$(bar_addr "$i")"
        return
    done
    return 0
}
bar_wifi() { _wp=$(bar_wifi_pct); [ -z "$_wp" ] || printf '%s %s\n' "$(( (${_wp%% *} + 12) / 25 ))" "${_wp#* }"; }   # -> "LEVEL ADDR" (0-4), else nothing
bar_bt() {   # -> "name NAME", "on", "off", or nothing
    ls -d "$BAR_SYS"/class/bluetooth/hci* >/dev/null 2>&1 || return 0
    command -v bluetoothctl >/dev/null 2>&1 || { echo on; return; }
    bt_powered || { echo off; return; }
    dev=$(bt_connected | awk '$1 == "Device" { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }')
    if [ -n "$dev" ]; then printf 'name %s\n' "$dev"; else echo on; fi
}
mac_battery() {   # -> CAPACITY<tab>STATE<tab>LEFT from pmset
    LC_ALL=C pmset -g batt 2>/dev/null | awk -F ';' '
        /[0-9]+%/ {
            n=$1; sub(/^.*[[:space:]]/, "", n); sub(/%$/, "", n)
            if (n !~ /^[0-9]+$/ || (n + 0) > 100) next
            state=$2; sub(/^[[:space:]]*/, "", state); sub(/[[:space:]]*$/, "", state)
            left=$3; sub(/^[[:space:]]*/, "", left); sub(/ remaining.*$/, "", left)
            if (left !~ /^[0-9]+:[0-9][0-9]$/ || left == "0:00") left=""
            printf "%s\t%s\t%s\n", n, state, left; exit
        }'
}
bar_power() {   # -> "CAPACITY STATUS", or nothing
    if [ "$OS" = Darwin ]; then mac_battery | awk -F '\t' '{print $1 " " $2}'; return; fi
    for b in "$BAR_SYS"/class/power_supply/*; do
        [ -f "$b/capacity" ] || continue
        [ ! -f "$b/type" ] || [ "$(cat "$b/type")" = Battery ] || continue
        printf '%s %s\n' "$(cat "$b/capacity")" "$(cat "$b/status" 2>/dev/null || echo Unknown)"; return
    done
    return 0
}

# --- sound
snd_tool() {   # -> wpctl | pactl | alsa | nothing
    if command -v wpctl >/dev/null 2>&1 && wpctl status >/dev/null 2>&1; then echo wpctl
    elif command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then echo pactl
    elif command -v amixer >/dev/null 2>&1 && grep -q '^ *[0-9]' "$BAR_PROC/asound/cards" 2>/dev/null; then echo alsa
    fi
}
# wpctl status rows: "N. Description [vol:...]", the default starred
wp_rows() { read_once wpctl.status wpctl status 2>/dev/null | awk -v sec="$1:" 'index($0, sec) {on = 1; next} on && !/[0-9]+\. / {exit} on { star = index($0, "*") ? 1 : 0; id = $0; sub(/^[^0-9]*/, "", id); sub(/\..*$/, "", id); d = $0; sub(/^.*[0-9]+\. /, "", d); sub(/[ \t]+\[vol:.*$/, "", d); sub(/[ \t]+$/, "", d); print star "\t" id "\t" d }'; }   # wp_rows Sinks|Sources -> STAR<tab>ID<tab>DESCRIPTION
wp_default() { wp_rows "$1" | awk -F '\t' '$1 == 1 {print $3; exit}'; }
wp_level() { read_once "wpctl.volume$1" wpctl get-volume "$1" 2>/dev/null | awk '{printf "%d", $2 * 100 + 0.5}'; }   # wp_level @DEFAULT_AUDIO_SINK@|SOURCE@
wp_muted() { _wm=$(read_once "wpctl.volume$1" wpctl get-volume "$1" 2>/dev/null) || return 1; case $_wm in 'Volume: '*) case $_wm in *MUTED*) echo 1 ;; *) echo 0 ;; esac ;; *) return 1 ;; esac; }
wp_live() { command -v pw-dump >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && pw-dump 2>/dev/null | jq -e 'any(.[]; .info.props["media.class"]? == "Stream/Input/Audio" and .info.state? == "running")' >/dev/null 2>&1 && echo 1 || echo 0; }
# pactl
pa_desc() { pactl list "$1" 2>/dev/null | awk -v n="$2" '/^\tName: / {cur = $2} /^\tDescription: / && cur == n {sub(/^\tDescription: /, ""); print; exit}'; }   # pa_desc sinks|sources NAME
pa_level() { pactl "get-$1-volume" "$2" 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d %; }   # pa_level sink|source @DEFAULT_SINK@|@DEFAULT_SOURCE@
pa_muted() { _pm=$(pactl "get-$1-mute" "$2" 2>/dev/null) || return 1; case $_pm in 'Mute: yes') echo 1 ;; 'Mute: no') echo 0 ;; *) return 1 ;; esac; }
pa_live() { [ -n "$(pactl list short source-outputs 2>/dev/null)" ] && echo 1 || echo 0; }
# plain ALSA
al_cards() { awk '/^ *[0-9]+ \[/ { n = $1; id = $0; sub(/^[^[]*\[/, "", id); sub(/ *\].*$/, "", id); long = $0; sub(/^[^:]*: [^ ]* - /, "", long); print n "\t" id "\t" long }' "$BAR_PROC/asound/cards" 2>/dev/null; }   # -> N<tab>ID<tab>LONG NAME; USB-Audio's hyphen is not the dash
al_name() { al_cards | awk -F '\t' -v n="$1" '$1 == n { if ($2 ~ /^(Device|USB|Generic|PCH|Intel|SB|NVidia|Audio)$/) print $3; else print $2; exit }'; }   # al_name N -> a name
al_with() { for c in $(al_cards | cut -f1); do ls -d "$BAR_PROC/asound/card$c/pcm"*"$1" >/dev/null 2>&1 && echo "$c"; done 2>/dev/null; return 0; }   # al_with p|c -> the cards that play | capture
al_first() { al_with "$1" | sed -n 1p; }   # al_first p|c; sed, not head: no broken pipe
al_running() { for c in $(al_with "$1"); do grep -qs 'state: RUNNING' "$BAR_PROC/asound/card$c/pcm"*"$1"/sub*/status && { echo "$c"; return 0; }; done; return 0; }   # al_running p|c -> the card in use
al_default() {   # -> the card ALSA's default resolves to
    d=$(amixer -D default info 2>/dev/null | sed -n "s/^Card default '\([^']*\)'.*/\1/p" | head -1)
    [ -z "$d" ] || { al_cards | awk -F '\t' -v id="$d" '$2 == id {print $1; exit}'; return; }
    [ ! -f "$BAR_ASOUNDRC" ] || { d=$(sed -n 's/^defaults\.pcm\.!*card //p' "$BAR_ASOUNDRC" | head -1); [ -z "$d" ] || { al_cards | awk -F '\t' -v id="$d" '$2 == id || $1 == id {print $1; exit}'; return; }; }
    al_first p
}
al_out() { c=$(al_running p); [ -n "$c" ] || c=$(al_default); [ -n "$c" ] && al_with p | grep -qx "$c" || c=$(al_first p); printf '%s' "$c"; }
al_mic() { c=$(al_running c); [ -n "$c" ] || { c=$(al_default); al_with c | grep -qx "${c:-x}" || c=$(al_first c); }; printf '%s' "$c"; }
al_control() {   # al_control N p|c -> the mixer control
    want='Master PCM Speaker Headphone'; [ "$2" = p ] || want='Capture Mic'
    have=$(amixer -c "$1" scontrols 2>/dev/null | sed -n "s/^Simple mixer control '\([^']*\)',0$/\1/p")
    for w in $want; do printf '%s\n' "$have" | grep -qx "$w" && { echo "$w"; return; }; done
    return 1
}
al_level() { amixer -c "$1" sget "$2" 2>/dev/null | grep -o '\[[0-9]*%\]' | head -1 | tr -d '[]%'; }   # al_level N CONTROL -> 0..100 or nothing
al_muted() { amixer -c "$1" sget "$2" 2>/dev/null | grep -o '\[\(on\|off\)\]' | head -1 | grep -q off && echo 1 || echo 0; }
al_write() {   # al_write N [PLAYDEV] [CAPDEV] -- our asoundrc
    id=$(al_cards | awk -F '\t' -v n="$1" '$1 == n {print $2; exit}')
    if [ -f "$BAR_ASOUNDRC" ] && ! grep -q 'rendered by spark-shell' "$BAR_ASOUNDRC"; then echo "asoundrc is yours"; return 1; fi
    if _tf=$(al_theirs); then echo "$(al_theirs_said "$_tf"): spark-shell leaves it to that file"; return 1; fi
    mkdir -p "$(dirname "$BAR_ASOUNDRC")"
    # without the ! ALSA drops its whole configuration
    {   printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.!card %s\ndefaults.ctl.!card %s\n' "$id" "$id"
        if [ -n "${2:-}${3:-}" ]; then   # sysdefault: it follows defaults.pcm.card
            [ -z "${2:-}" ] || printf '# bluetooth out: %s\n' "$(al_bt_name p "$2")"
            [ -z "${3:-}" ] || printf '# bluetooth mic: %s\n' "$(al_bt_name c "$3")"
            printf 'pcm.!default {\n    type asym\n'
            if [ -n "${2:-}" ]; then printf '    playback.pcm { type plug slave.pcm "bluealsa:DEV=%s,PROFILE=a2dp" }\n' "$2"; else printf '    playback.pcm "sysdefault"\n'; fi
            if [ -n "${3:-}" ]; then printf '    capture.pcm { type plug slave.pcm "bluealsa:DEV=%s,PROFILE=sco" }\n' "$3"; else printf '    capture.pcm "sysdefault"\n'; fi
            printf '}\n'
        fi
    } > "$BAR_ASOUNDRC"
    amixer -c "$1" scontrols >/dev/null 2>&1 || { rm -f "$BAR_ASOUNDRC"; echo "ALSA refused the file"; return 1; }   # a refused file would take every program's sound
}
al_theirs() {   # -> the user's file that sets pcm.!default
    [ -f "$HOME/.asoundrc" ] || return 1
    { echo "$HOME/.asoundrc"; sed -n 's/^ *<\([~/][^>]*\)>.*$/\1/p' "$HOME/.asoundrc" | sed "s|^~/|$HOME/|"; } | while IFS= read -r f; do if grep -qs '^ *pcm\.!default' "$f"; then printf '%s\n' "$f"; exit 0; fi; done | grep .   # grep .: the loop alone exits 0 when none
}
al_theirs_said() {   # al_theirs_said FILE -> the sentence naming it
    case $1 in "$HOME/.asoundrc") echo "your ~/.asoundrc picks the sound device" ;; *) echo "${1#"$HOME/"} picks the sound device, read by your ~/.asoundrc" | sed 's|^\([^/~]\)|~/\1|' ;; esac
}
# bluez-alsa: A2DP plays, SCO listens
al_bt() {   # al_bt p|c -> NAME<tab>DEV per device that plays | listens
    command -v bluealsa-aplay >/dev/null 2>&1 || return 0
    _pr=a2dp; _dir=playback; [ "$1" = p ] || { _pr=sco; _dir=capture; }
    bar_timeout bluealsa-aplay -L 2>/dev/null | awk -v pr="PROFILE=$_pr" -v dir="$_dir" '
        /^bluealsa:/ { dev = ""; if (index($0, pr)) { d = $0; sub(/.*DEV=/, "", d); sub(/,.*$/, "", d); if (d ~ /^[0-9A-F][0-9A-F](:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])$/) dev = d }; next }
        dev != "" { l = $0; sub(/^[ \t]+/, "", l); n = split(l, f, ", "); if (f[n] == dir) { name = l; sub(/, .*$/, "", name); gsub(/[^ -~]/, "", name); if (name != "" && !seen[dev]++) print name "\t" dev }; dev = "" }'
}
al_bt_name() { al_bt "$1" | awk -F '\t' -v d="$2" '$2 == d {print $1; exit}'; }   # al_bt_name p|c DEV -> its name while offered
al_bt_routed() {   # al_bt_routed p|c -> the DEV the file routes to
    [ -f "$BAR_ASOUNDRC" ] && grep -q 'rendered by spark-shell' "$BAR_ASOUNDRC" || return 0
    _w=playback; _pr=a2dp; [ "$1" = p ] || { _w=capture; _pr=sco; }
    sed -n "s/^ *$_w\.pcm { type plug slave\.pcm \"bluealsa:DEV=\([0-9A-F:]*\),PROFILE=$_pr\" }\$/\1/p" "$BAR_ASOUNDRC" | head -1
}
al_bt_said() {   # al_bt_said p|c -> the name the file wrote
    _w=out; [ "$1" = p ] || _w=mic
    [ -n "$(al_bt_routed "$1")" ] && sed -n "s/^# bluetooth $_w: //p" "$BAR_ASOUNDRC" | head -1
}
al_bt_ctl() {   # al_bt_ctl p|c -> the routed device's mixer control
    _d=$(al_bt_routed "$1"); [ -n "$_d" ] || return 1
    _n=$(al_bt_name "$1" "$_d"); [ -n "$_n" ] || return 1
    if [ "$1" = p ]; then echo "$_n - A2DP"; else echo "$_n - SCO"; fi
}
al_bt_level() { if [ "$1" = p ]; then amixer -D bluealsa sget "$2" 2>/dev/null | sed -n 's/.*Playback [0-9]* \[\([0-9]*\)%\].*/\1/p' | head -1; else amixer -D bluealsa sget "$2" 2>/dev/null | sed -n 's/.*Capture [0-9]* \[\([0-9]*\)%\].*/\1/p' | head -1; fi; }   # al_bt_level p|c CONTROL
al_bt_muted() { if [ "$1" = p ]; then _s=$(amixer -D bluealsa sget "$2" 2>/dev/null | grep 'Playback [0-9]' | grep -o '\[o[nf]*\]' | head -1); else _s=$(amixer -D bluealsa sget "$2" 2>/dev/null | sed -n 's/.*Capture [0-9]//p' | grep -o '\[o[nf]*\]' | head -1); fi; [ "$_s" = '[off]' ] && echo 1 || echo 0; }   # al_bt_muted p|c CONTROL -> 1 when off
al_mend_file() {   # our file's `defaults.pcm.card` takes the ! form
    [ -f "$BAR_ASOUNDRC" ] && grep -q 'rendered by spark-shell' "$BAR_ASOUNDRC" && grep -q '^defaults\.pcm\.card ' "$BAR_ASOUNDRC" || return 0
    t=$(sed -e 's/^defaults\.pcm\.card /defaults.pcm.!card /' -e 's/^defaults\.ctl\.card /defaults.ctl.!card /' "$BAR_ASOUNDRC") && printf '%s\n' "$t" > "$BAR_ASOUNDRC"
}
snd_out() { read_once snd.out snd_out_now; }   # -> three lines: NAME, LEVEL (or -), MUTED; or nothing
snd_out_now() {
    case $SND in
        wpctl) n=$(wp_default Sinks); [ -n "$n" ] || return 0; printf '%s\n%s\n%s\n' "$n" "$(wp_level @DEFAULT_AUDIO_SINK@)" "$(wp_muted @DEFAULT_AUDIO_SINK@)" ;;
        pactl) s=$(pactl get-default-sink 2>/dev/null); [ -n "$s" ] || return 0; n=$(pa_desc sinks "$s"); printf '%s\n%s\n%s\n' "${n:-$s}" "$(pa_level sink @DEFAULT_SINK@)" "$(pa_muted sink @DEFAULT_SINK@)" ;;
        alsa) if [ -n "$(al_bt_routed p)" ]; then
                if ctl=$(al_bt_ctl p); then printf '%s\n%s\n%s\n' "${ctl% - A2DP}" "$(al_bt_level p "$ctl")" "$(al_bt_muted p "$ctl")"; else printf '%s\n-\n0\n' "$(al_bt_said p)"; fi; return 0
            fi
            c=$(al_out); [ -n "$c" ] || return 0
            if ctl=$(al_control "$c" p); then printf '%s\n%s\n%s\n' "$(al_name "$c")" "$(al_level "$c" "$ctl")" "$(al_muted "$c" "$ctl")"; else printf '%s\n-\n0\n' "$(al_name "$c")"; fi ;;
    esac
}
snd_mic() { read_once snd.mic snd_mic_now; }   # -> four lines: NAME, LIVE, MUTED, LEVEL (or -); or nothing
snd_mic_now() {
    case $SND in
        wpctl) n=$(wp_default Sources); [ -n "$n" ] || return 0; printf '%s\n%s\n%s\n%s\n' "$n" "$(wp_live)" "$(wp_muted @DEFAULT_AUDIO_SOURCE@)" "$(wp_level @DEFAULT_AUDIO_SOURCE@)" ;;
        pactl) s=$(pactl get-default-source 2>/dev/null); [ -n "$s" ] || return 0; case $s in *.monitor) return 0 ;; esac
            n=$(pa_desc sources "$s"); printf '%s\n%s\n%s\n%s\n' "${n:-$s}" "$(pa_live)" "$(pa_muted source @DEFAULT_SOURCE@)" "$(pa_level source @DEFAULT_SOURCE@)" ;;
        alsa) if [ -n "$(al_bt_routed c)" ]; then
                if ctl=$(al_bt_ctl c); then printf '%s\n0\n%s\n%s\n' "${ctl% - SCO}" "$(al_bt_muted c "$ctl")" "$(al_bt_level c "$ctl")"; else printf '%s\n0\n0\n-\n' "$(al_bt_said c)"; fi; return 0
            fi
            c=$(al_mic); [ -n "$c" ] || return 0; live=0; [ -z "$(al_running c)" ] || live=1
            if ctl=$(al_control "$c" c); then printf '%s\n%s\n%s\n%s\n' "$(al_name "$c")" "$live" "$(al_muted "$c" "$ctl")" "$(al_level "$c" "$ctl")"; else printf '%s\n%s\n0\n-\n' "$(al_name "$c")" "$live"; fi ;;
    esac
}
snd_set() {   # snd_set out|mic LEVEL|+5|-5|mute|muted|unmuted (mute toggles)
    SND=${SND:-$(snd_tool)}
    t=$1; shift
    case $SND in
        wpctl) n=@DEFAULT_AUDIO_SINK@; [ "$t" = out ] || n=@DEFAULT_AUDIO_SOURCE@
            case $1 in
                mute) wpctl set-mute "$n" toggle ;; muted) wpctl set-mute "$n" 1 ;; unmuted) wpctl set-mute "$n" 0 ;;
                +*|-*) wpctl set-volume -l 1.0 "$n" "${1#[+-]}%${1%"${1#?}"}" ;;
                *) wpctl set-volume -l 1.0 "$n" "$1%" ;;
            esac ;;
        pactl) k=sink; n=@DEFAULT_SINK@; [ "$t" = out ] || { k=source; n=@DEFAULT_SOURCE@; }
            case $1 in
                mute) pactl "set-$k-mute" "$n" toggle ;; muted) pactl "set-$k-mute" "$n" 1 ;; unmuted) pactl "set-$k-mute" "$n" 0 ;;
                +*|-*) pactl "set-$k-volume" "$n" "${1#[+-]}%${1%"${1#?}"}" ;;   # 5%+ / 5%-
                *) pactl "set-$k-volume" "$n" "$1%" ;;
            esac ;;
        alsa) k=p; [ "$t" = out ] || k=c
            if [ -n "$(al_bt_routed "$k")" ]; then
                ctl=$(al_bt_ctl "$k") || return 1
                off=mute; on=unmute; [ "$k" = p ] || { off=nocap; on=cap; }
                case $1 in
                    mute) amixer -q -D bluealsa sset "$ctl" toggle ;; muted) amixer -q -D bluealsa sset "$ctl" "$off" ;; unmuted) amixer -q -D bluealsa sset "$ctl" "$on" ;;
                    +*|-*) amixer -q -D bluealsa sset "$ctl" "${1#[+-]}%${1%"${1#?}"}" ;;
                    *) amixer -q -D bluealsa sset "$ctl" "$1%" ;;
                esac
                return $?
            fi
            if [ "$t" = out ]; then c=$(al_out); else c=$(al_mic); fi
            [ -n "$c" ] && ctl=$(al_control "$c" "$k") || return 1
            off=mute; on=unmute; [ "$k" = p ] || { off=nocap; on=cap; }   # capture: amixer says cap and nocap, not mute
            case $1 in
                mute) amixer -q -c "$c" sset "$ctl" toggle ;; muted) amixer -q -c "$c" sset "$ctl" "$off" ;; unmuted) amixer -q -c "$c" sset "$ctl" "$on" ;;
                +*|-*) amixer -q -c "$c" sset "$ctl" "${1#[+-]}%${1%"${1#?}"}" ;;
                *) amixer -q -c "$c" sset "$ctl" "$1%" ;;
            esac ;;
        *) return 1 ;;
    esac >/dev/null 2>&1
}
snd_why() {   # snd_why out|mic LINES -> why it cannot be muted or set, from snd_out's or snd_mic's LINES; nothing when it can
    [ -n "${SND:-}" ] || { echo "no audio system found"; return 0; }
    [ -n "$2" ] || { if [ "$1" = out ]; then echo "no output found"; else echo "no microphone found"; fi; return 0; }
    if [ "$1" = out ]; then _sl=$(printf '%s\n' "$2" | sed -n 2p); else _sl=$(printf '%s\n' "$2" | sed -n 4p); fi
    [ "$_sl" != - ] && [ -n "$_sl" ] || echo "$(printf '%s\n' "$2" | sed -n 1p) has no volume control here, so it cannot be muted or set"
}
snd_settable() {   # snd_settable out|mic -> 0, or why not and exit 1
    SND=${SND:-$(snd_tool)}
    if [ "$1" = out ]; then _so=$(snd_out); else _so=$(snd_mic); fi
    _sw=$(snd_why "$1" "$_so"); [ -n "$_sw" ] || return 0
    echo "$1: $_sw"; return 1
}
snd_apply() {   # snd_apply out|mic LEVEL|muted|unmuted -> the state read back
    snd_set "$1" "$2" || { echo "$1 could not be changed; check its current state"; return 1; }
    if [ "$1" = out ]; then _sa=$(snd_out); _sl=$(printf '%s\n' "$_sa" | sed -n 2p)
    else _sa=$(snd_mic); _sl=$(printf '%s\n' "$_sa" | sed -n 4p); fi
    _sn=$(printf '%s\n' "$_sa" | sed -n 1p); _sm=$(printf '%s\n' "$_sa" | sed -n 3p)
    case $_sl:$_sm in *:0|*:1) ;; *) echo "$1 changed, but its current state could not be verified"; return 1 ;; esac
    case $_sl in ''|*[!0-9]*) echo "$1 changed, but its level could not be read back"; return 1 ;; esac
    case $2:$_sm in muted:0|unmuted:1) echo "$1 is not $2: the audio system did not take it"; return 1 ;; esac
    case $2 in muted|unmuted) ;; *)
        # mixers quantize: one point of slack
        _sd=$((_sl - $2)); [ "$_sd" -ge -1 ] && [ "$_sd" -le 1 ] || {
            echo "$1 is at $_sl%, not the requested $2%; the audio system did not take that level"; return 1;
        } ;;
    esac
    case $2 in muted|unmuted) echo "$1 $2" ;; *) echo "$1 at $_sl%" ;; esac
    [ -z "${PROVIDE_EFFECT:-}" ] || jq -cn --arg id "$1" --arg title "$_sn" --arg operation "$2" --argjson level "$_sl" --argjson muted "$_sm" \
        '{kind:"sound", id:$id, title:$title, operation:$operation, level:$level, muted:($muted == 1)}' > "$TMP/action.effect"
}
snd_adjust() {   # snd_adjust out|mic DELTA -- the level moved by DELTA
    if [ "$1" = out ]; then _sad_now=$(snd_out | sed -n 2p); else _sad_now=$(snd_mic | sed -n 4p); fi
    case $_sad_now in ''|*[!0-9]*) echo "$1: the current level could not be read; nothing changed"; return 1 ;; esac
    _sad_target=$((_sad_now + $2))
    [ "$_sad_target" -ge 0 ] || _sad_target=0
    [ "$_sad_target" -le 100 ] || _sad_target=100
    snd_apply "$1" "$_sad_target" || return 1
    printf '%s\n' "$_sad_now" > "$TMP/sound.undo"
}

# --- brightness
light_tool() {   # -> backlight | ddc | nothing
    if ls "$BAR_SYS"/class/backlight/* >/dev/null 2>&1 && command -v brightnessctl >/dev/null 2>&1; then echo backlight
    elif command -v ddcutil >/dev/null 2>&1 && [ -n "$(light_ddc_bus)" ]; then echo ddc; fi
}
light_ddc() {   # light_ddc ARGS... -- ddcutil, locked: a held key would race
    _b=$(light_ddc_bus); [ -n "$_b" ] || return 1
    if command -v flock >/dev/null 2>&1; then mkdir_private "$STATE_DIR"; flock -w 3 "$STATE_DIR/ddc.lock" ddcutil --bus "$_b" "$@"; else ddcutil --bus "$_b" "$@"; fi
}
light_ddc_bus() {   # -> the first screen's i2c bus, or nothing
    _rw=''; for _d in "$BAR_DEV"/i2c-*; do [ ! -r "$_d" ] || [ ! -w "$_d" ] || { _rw=1; break; }; done
    [ -n "$_rw" ] || return 0   # no i2c access: nothing asked
    # cached 10 minutes, 1 while a screen sleeps (DPMS)
    _cd=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; _cd=${_cd:-$STATE_DIR}; _f=$_cd/ddc.bus
    _ttl=600; ! grep -qx asleep "$_f" 2>/dev/null || _ttl=60
    if [ -f "$_f" ] && [ $(( $(date +%s) - $(stat -c %Y "$_f" 2>/dev/null || stat -f %m "$_f" 2>/dev/null || echo 0) )) -lt "$_ttl" ]; then grep -vx 'none\|asleep' "$_f" || :; return 0; fi
    mkdir -p "$_cd"
    { if command -v timeout >/dev/null 2>&1; then timeout 10 ddcutil detect --terse; else ddcutil detect --terse; fi; } > "$_f.out" 2>/dev/null || :
    awk '/^Display [0-9]+/ {on = 1; next} /^[A-Z]/ {on = 0} on && /I2C bus:/ {sub(/.*i2c-/, ""); print; exit}' "$_f.out" > "$_f.new"
    if [ ! -s "$_f.new" ]; then if grep -q DPMS "$_f.out"; then echo asleep; else echo none; fi > "$_f.new"; fi
    rm -f "$_f.out"; mv "$_f.new" "$_f"
    grep -vx 'none\|asleep' "$_f" || :
}
light_get() { read_once light light_get_now; }   # -> PERCENT, or nothing
light_get_now() {
    case $(light_tool) in
        backlight) brightnessctl -m -c backlight info 2>/dev/null | awk -F, '{gsub(/%/, "", $4); print $4; exit}' ;;
        ddc) _f=$STATE_DIR/light
            if [ -f "$_f" ] && [ $(( $(date +%s) - $(stat -c %Y "$_f" 2>/dev/null || stat -f %m "$_f" 2>/dev/null || echo 0) )) -lt 60 ]; then cat "$_f"; return 0; fi
            light_ddc getvcp 10 --terse 2>/dev/null | awk '$1 == "VCP" && $2 == "10" && $5 > 0 {printf "%d\n", $4 * 100 / $5 + 0.5}' > "$_f.new" && [ -s "$_f.new" ] && mv "$_f.new" "$_f" || rm -f "$_f.new"
            cat "$_f" 2>/dev/null || : ;;
    esac
}
light_set() {   # light_set N|up|down|+5|-5 -> one line
    _t=$(light_tool); [ -n "$_t" ] || { echo "no brightness to set here (a laptop's backlight, or a screen that speaks DDC/CI)"; return 1; }
    _now=$(light_get); [ -n "$_now" ] || _now=50
    case ${1:-} in
        up|+5) _to=$((_now + 5)) ;; down|-5) _to=$((_now - 5)) ;;
        [0-9]|[0-9][0-9]|100) _to=$1 ;;
        *) echo "brightness takes 1 to 100, up or down"; return 1 ;;
    esac
    [ "$_to" -le 100 ] || _to=100; [ "$_to" -ge 1 ] || _to=1   # a screen at 0 looks off
    case $_t in
        backlight) brightnessctl -q -c backlight set "$_to%" >/dev/null 2>&1 || { echo "brightnessctl could not set it (the video group, a login again)"; return 1; } ;;
        ddc) light_ddc setvcp 10 "$_to" --noverify >/dev/null 2>&1 || { echo "the screen took no brightness over DDC/CI"; return 1; }
            mkdir_private "$STATE_DIR"; echo "$_to" > "$STATE_DIR/light" ;;
    esac
    bar_redraw
    echo "brightness at $_to%"
}
kb_active() { read_once kb.active kb_active_now; }   # -> the layout in use, by its KEYBOARD word
kb_active_now() {
    [ "$(printf '%s\n' $KEYBOARD | grep -c .)" -gt 1 ] || return 0
    _i=$(kb_names | cut -f1); [ -n "$_i" ] || _i=0
    printf '%s\n' $KEYBOARD | sed -n "$((_i + 1))p"
}

# --- the line
bar_kw() { _kw=1; [ -z "$_bw" ] || _kw=${#1}; }   # bar_kw SIGN -> _kw, its cells: one for a sign, its letters for a word
bar_failed() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-bar.failed.$1"; }   # bar_failed out|mic -> the mark that its last direct change failed; the next line says so, on spark's bar
bar_snd() { if snd_set "$@"; then rm -f "$(bar_failed "$1")"; else mkdir_private "${XDG_RUNTIME_DIR:-$STATE_DIR}"; : > "$(bar_failed "$1")"; fi; }   # bar_snd out|mic CHANGE -- a click's or a key's change; one that failed is marked, the next that works clears it
# sound, read for either bar: _au its lines (nothing: no device), _aul the level (nothing: none to read), m 1 when
# muted, live 1 while something records, _auy why it cannot be muted or set (nothing: it can), _aut its label
bar_audio_read() {   # bar_audio_read out|mic
    if [ "$1" = out ]; then _aun=output; _au=$(snd_out); _aul=$(printf '%s\n' "$_au" | sed -n 2p); m=$(printf '%s\n' "$_au" | sed -n 3p); live=0
    else _aun=microphone; _au=$(snd_mic); live=$(printf '%s\n' "$_au" | sed -n 2p); m=$(printf '%s\n' "$_au" | sed -n 3p); _aul=$(printf '%s\n' "$_au" | sed -n 4p); fi
    case $_aul in ''|-|*[!0-9]*) _aul='' ;; esac
    _aut="$_aun $_aul%"; [ "$m" != 1 ] || _aut="$_aun muted"
    _auy=$(snd_why "$1" "$_au"); [ -z "$_auy" ] || _aut="$_aun not available: $_auy"
    [ "$live" != 1 ] || _aut="$_aut, recording"
}
bar_audio() {   # bar_audio out|mic -- its blocks on sway's bar: the sign when there is a device, the gauge when it has a level
    bar_audio_read "$1"; [ -n "$_au" ] || return 0
    if [ "$1" = out ]; then k=$k_out; _auo=$k_out_off; else k=$k_mic; _auo=$k_mic_off; fi
    bar_kw "$k"; _auw=$_kw; [ "$1" != mic ] || [ -z "$_bw" ] || _auw=$((_kw + 2))   # mic in words: the dot beside it while it records
    c=$HEX_ACCENT; [ "$m" != 1 ] || { k=$_auo; c=$HEX_MUTED; }
    _aus=ok; [ -z "$_auy" ] || _aus=unavailable
    [ "$live" != 1 ] || { c=$HEX_ANSI_1; k=$PANEL_DOT; [ -z "$_bw" ] || k="mic $PANEL_DOT"; }   # recording: a red dot
    gap=$BAR_GAP; [ -z "$_aul" ] || gap=6   # the gauge close to its sign
    bar_add "$(bar_block "$1" name "$(bar_span "$c" "$k")" "$_auw" "$_aut" "$gap" "state=$_aus")"
    [ -z "$_aul" ] || bar_add "$(bar_block "$1" gauge "$(bar_gauge "$_aul" "$m")" 5 "$_aut" '' "control=level state=$_aus")"
}

# --- the facts: the line for spark's bar (SPARK_BAR), no markup and no color in it: what each module is, for the bar to
# draw in its own look. Sway's bar, where spark's cannot run, has bar_line's blocks as before

# what the config says of the modules, now: BAR_PINS, the levels whose control, a gauge and a number, is on the bar (out
# where no line says, none for no one), and BAR_HIDE, the modules off it. A BAR_PINS that names a module with no level
# is v0.147's, the modules it showed: what it leaves out is hidden, and out is pinned
bar_shown() {   # -> _pinned and _hidden, a list of names each
    _pinned=$(bar_style BAR_PINS out | tr -d '"'); _hidden=$(bar_style BAR_HIDE '' | tr -d '"')
    [ "$_pinned" != none ] || _pinned=''
    ! words_in "$_pinned" "$BAR_LEVELS" || return 0
    for _bsm in ${BAR_MODULES#workspaces }; do case " $_pinned " in *" $_bsm "*) ;; *) _hidden="$_hidden $_bsm" ;; esac; done
    _pinned=out
}
# the look, the line's first object: the colors as they are now, so a theme change and a preview show with no start, the
# glyph family's gauge pair and the motion. Each value a string, a color its six hex digits; the muted is the palette's
# own, the dim tone, and the alert its red
bar_look() {
    _blm=yes; [ "$(bar_style BAR_MOTION yes | tr -d '"')" != no ] || _blm=no
    printf '{"name":"look","fg":"%s","accent":"%s","muted":"%s","ground":"%s","lit":"%s","attention":"%s","alert":"%s","alpha":"%s","full":"%s","light":"%s","motion":"%s","ink":"%s"}' \
        "$HEX_FG" "$HEX_ACCENT" "$HEX_MUTED" "$HEX_BG" "$PANEL_HI" "${PANEL_ATTENTION:-$HEX_ANSI_3}" "$HEX_ANSI_1" "$ALPHA" "$FAM_ON" "$FAM_OFF" "$_blm" "${PANEL_INK:-$HEX_BG}"
}
# bar_sign GLYPH WORD [ICON] -> _bg, a module's sign: its glyph, or its word where the bar is in words; and _bi, its
# icon's name, which spark's bar draws in the glyph's place (component/bar/icons.py has the drawings); none in words
bar_sign() { _bg=$1; _bi=${3:-}; [ -z "$_bw" ] || { _bg=$2; _bi=''; }; }
# a fact, one module's object: SIGN and the icon bar_sign named last, then TEXT in the CELLS kept for it, its widest;
# STATE is ok, muted, off, missing, wrong, asks or records; LEVEL, 0 to 100, where the module has one, and SET, true where the bar can set it; LABEL is
# the module and its state in words. Pinned is the config's word: the level's gauge and number are on the bar. Toggle
# is true where a click on the sign or the text changes the module in place and opens nothing (bar_click): out's
# mute, the keyboard's next layout, the pad shown or hidden
bar_fact() {   # bar_fact NAME GROUP SIGN TEXT CELLS STATE LABEL [LEVEL [SET]] -- added to the line, unless the module is hidden
    _bfi=${_bi:-}; _bi=''   # the icon is this fact's alone: the next one names its own, or has none
    case " $_hidden " in *" $1 "*) return 0 ;; esac
    _bfl=''; [ -z "${8:-}" ] || { _bfl=$8; [ "$_bfl" -le 100 ] || _bfl=100; _bfl=",\"level\":$_bfl"; }
    _bfb=false; [ "$1" != clock ] || _bfb=true   # the time alone is bold
    _bfp=false; case " $_pinned " in *" $1 "*) _bfp=true ;; esac
    _bfg=false; case $1 in out|kb|pad) _bfg=true ;; esac
    bar_str "$3"; _bfs=$_bs; bar_str "$4"; _bft=$_bs; bar_str "$7"
    line="$line,{\"name\":\"$1\",\"group\":\"$2\",\"sign\":\"$_bfs\",\"icon\":\"$_bfi\",\"text\":\"$_bft\",\"cells\":$5,\"bold\":$_bfb,\"state\":\"$6\"$_bfl,\"set\":${9:-false},\"pinned\":$_bfp,\"label\":\"$_bs\",\"toggle\":$_bfg}"
}
bar_fact_pad() {   # the windows that wait on the pad, and how many; off while the pad is hidden
    _pdn=$(winpad_count); [ "${_pdn:-0}" -gt 0 ] 2>/dev/null || return 0
    bar_sign "$BAR_PAD" pad pad; _pdw=2; [ "${#_pdn}" -le 2 ] || _pdw=${#_pdn}
    if winpad_hidden; then bar_fact pad windows "$_bg" "$_pdn" "$_pdw" off "pad hidden, $_pdn windows"
    else bar_fact pad windows "$_bg" "$_pdn" "$_pdw" ok "pad, $_pdn windows"; fi
}
bar_fact_lan() {   # the wire: wrong when it is down
    bar_sign "$BAR_LAN" lan lan
    case $(bar_lan) in
        up*) bar_fact lan connections "$_bg" '' 0 ok 'lan connected' ;;
        down) bar_fact lan connections "$_bg" '' 0 wrong 'lan not connected' ;;
    esac
}
# bluetooth: ok with a device connected, its icon with a dot at each side; on with none, the same sign and the icon with
# no dots, missing; off, the hollow star and the icon drawn thin
bar_fact_bt() {
    bt=$(bar_bt)
    case $bt in
        name*) bar_sign "$BAR_BT" bt bt; bar_fact bt connections "$_bg" '' 0 ok "bluetooth ${bt#name } connected" ;;
        on) bar_sign "$BAR_BT" bt bt-idle; bar_fact bt connections "$_bg" '' 0 missing 'bluetooth on' ;;
        off) bar_sign "$BAR_BT_OFF" bt bt-off; bar_fact bt connections "$_bg" '' 0 off 'bluetooth off' ;;
    esac
}
bar_fact_wifi() {   # wifi: its signal a level the bar reads and cannot set, and its icon's bands lit by it; off, with no level, while it is not connected
    wifi=$(bar_wifi_pct)
    if [ -n "$wifi" ]; then
        _wfi=wifi; [ "${wifi%% *}" -ge 67 ] 2>/dev/null || _wfi=wifi-fair; [ "${wifi%% *}" -ge 34 ] 2>/dev/null || _wfi=wifi-weak
        bar_sign "$BAR_WIFI" wifi "$_wfi"; bar_fact wifi connections "$_bg" '' 0 ok "wifi ${wifi%% *}%" "${wifi%% *}"
    elif [ -n "$(bar_wireless)" ]; then bar_sign "$BAR_WIFI" wifi wifi-off; bar_fact wifi connections "$_bg" '' 0 off 'wifi not connected'; fi
}
# sound's two are always on the line, with a level, 0 where none is read, so a pinned control keeps its cells: the hollow
# sign while muted, and in words, where no word is hollow, off, so the tone says it; missing with no device or no level
# to set; the dot while something records; wrong after a change that failed
bar_fact_audio() {   # bar_fact_audio out|mic
    bar_audio_read "$1"
    if [ "$1" = out ]; then _aug=$BAR_OUT; _auo=$BAR_OUT_OFF; else _aug=$BAR_MIC; _auo=$BAR_MIC_OFF; fi
    _aus=ok; _auc=true; _aui=$1
    [ "$m" != 1 ] || { _aus=muted; _aug=$_auo; _aui=$1-muted; [ -z "$_bw" ] || _aus=off; }
    [ -z "$_auy" ] || { _aus=missing; _aug=$_auo; _aui=$1-muted; _auc=false; }
    [ "$live" != 1 ] || { _aus=records; _aug=$PANEL_DOT; _aui=$1; }   # the icon stays the microphone, in red
    [ ! -e "$(bar_failed "$1")" ] || { _aus=wrong; _aut="$_aun could not be changed"; }
    bar_sign "$_aug" "$1" "$_aui"
    bar_fact "$1" sound "$_bg" '' 0 "$_aus" "$_aut" "${_aul:-0}" "$_auc"
}
bar_fact_due() {   # a reminder due: its sign alone, asking
    due=$(rem_due 2>/dev/null || :); [ -n "$due" ] || return 0
    bar_sign "$BAR_DUE" due due
    bar_fact due tasks "$_bg" '' 0 asks "reminder due: $(printf '%s' "${due#*"$TAB"}" | cut_chars 28)"
}
bar_fact_light() {   # the screen's brightness, a level the bar sets
    lt=$(light_get); case $lt in ''|*[!0-9]*) return 0 ;; esac
    bar_sign "$BAR_LIGHT" light light
    bar_fact light seat "$_bg" '' 0 ok "brightness $lt%" "$lt" true
}
bar_fact_kb() {   # the keyboard's layout in use, where there is more than one
    kb=$(kb_active); [ -n "$kb" ] || return 0
    bar_sign "$BAR_KB" kb kb; _kbw=0; for _kbl in $KEYBOARD; do [ "${#_kbl}" -le "$_kbw" ] || _kbw=${#_kbl}; done   # the widest layout's name
    bar_fact kb seat "$_bg" "$kb" "$_kbw" ok "keyboard $kb"
}
# the battery: its icon, full from 75, low under 15, a bolt while it charges, and its number; wrong when low. In words
# no icon says it charges: a plus after the number does
bar_fact_bat() {
    bat=$(bar_power); [ -n "$bat" ] || return 0
    cap=${bat%% *}; stt=${bat#* }; _bts=ok; _btt="$cap%"; _btl="battery $cap%"; _btc=4; _bti=battery-half
    [ "$cap" -lt 75 ] || _bti=battery-full
    [ "$stt" != Charging ] || { _bti=battery-charging; _btl="$_btl charging"; }
    [ "$cap" -ge 15 ] || [ "$stt" = Charging ] || { _bts=wrong; _bti=battery-low; _btl="$_btl low"; }
    [ -z "$_bw" ] || { _btc=5; [ "$stt" != Charging ] || _btt="$_btt+"; }
    bar_sign '' bat "$_bti"
    bar_fact bat seat "$_bg" "$_btt" "$_btc" "$_bts" "$_btl"
}
bar_fact_clock() {   # the time alone: 21:41 in five cells, 12:41 PM in eight
    _ct=$(clock_text); bar_cells "$_ct"; [ "$_bc" -ge 5 ] || _bc=5; [ "$_bc" -le 5 ] || [ "$_bc" -ge 8 ] || _bc=8
    bar_fact clock time '' "$_ct" "$_bc" ok "time $_ct"
}
# always there where mako is: the flag, solid while some wait and hollow with none, or the sign of do not disturb, and
# how many nobody looked at
bar_fact_notifications() {
    command -v makoctl >/dev/null 2>&1 && _nm=$(makoctl mode 2>/dev/null) || return 0
    _nu=$(notify_unseen); [ "${_nu:-0}" -le 9 ] || _nu='9+'; [ "${_nu:-0}" != 0 ] || _nu=''
    if printf '%s\n' "$_nm" | grep -qx "$NOTIFY_MODE"; then bar_sign "$BAR_DND" quiet quiet; _nl='do not disturb'
    else _nfi=flag-none; [ -z "$_nu" ] || _nfi=flag; bar_sign "$BAR_NOTE" notes "$_nfi"; _nl=notifications; fi
    bar_fact notifications time "$_bg" "$_nu" 2 ok "$_nl${_nu:+, $_nu not seen}"
}
bar_facts() {   # -> the line for spark's bar: the look, then a fact a module, in the bar's order
    SND=$(snd_tool)
    # read each line: a change in Settings, a pin or a hide shows at the next
    _bw=''; [ "$(bar_style BAR_GLYPHS signs)" != words ] || _bw=1
    family_set "$(bar_style GLYPH_FAMILY stone)"
    bar_signs
    bar_shown
    line=$(bar_look)
    bar_fact_pad; bar_fact_lan; bar_fact_bt; bar_fact_wifi; bar_fact_audio out; bar_fact_audio mic; bar_fact_due
    bar_fact_light; bar_fact_kb; bar_fact_bat; bar_fact_clock; bar_fact_notifications
    printf '[%s],\n' "$line"
}
bar_line() {   # -> a refresh's JSON array: the facts for spark's bar, the blocks sway's bar draws otherwise. Run in a subshell: what it sets ends with it
    [ -z "${SPARK_BAR:-}" ] || { bar_facts; return; }
    line=''; group=''
    bar_add() { group="${group:+$group,}$1"; }
    bar_group() { [ -z "$group" ] || { line="${line:+$line,}${group%\"separator_block_width\":*}\"separator_block_width\":$BAR_GROUP_GAP}"; group=''; }; }   # the last block takes BAR_GROUP_GAP
    SND=$(snd_tool)
    # read each line: a Settings change shows at once
    _bw=''; [ "$(bar_style BAR_GLYPHS signs)" != words ] || _bw=1
    family_set "$(bar_style GLYPH_FAMILY stone)"
    bar_signs
    if [ -n "$_bw" ]; then
        k_lan=lan k_bt=bt k_bt_off='bt off' k_wifi=wifi k_out=out k_out_off=out k_mic=mic k_mic_off=mic k_light=light k_kb=kb k_due=due k_dnd='do not disturb' k_note=new k_pad=pad
    else
        k_lan=$BAR_LAN k_bt=$BAR_BT k_bt_off=$BAR_BT_OFF k_wifi=$BAR_WIFI k_out=$BAR_OUT k_out_off=$BAR_OUT_OFF k_mic=$BAR_MIC k_mic_off=$BAR_MIC_OFF k_light=$BAR_LIGHT k_kb=$BAR_KB k_due=$BAR_DUE k_dnd=$BAR_DND k_note=$BAR_NOTE k_pad=$BAR_PAD
    fi
    # the pad
    _pdn=$(winpad_count)
    if [ "${_pdn:-0}" -gt 0 ] 2>/dev/null; then
        _pdc=$HEX_MUTED; _pdl="pad, $_pdn windows"; ! winpad_hidden || { _pdc=$HEX_ACCENT; _pdl="pad hidden, $_pdn windows"; }
        bar_kw "$k_pad"; _pdw=2; [ "${#_pdn}" -le 2 ] || _pdw=${#_pdn}
        bar_add "$(bar_block pad '' "$(bar_span "$_pdc" "$k_pad") $_pdn" "$((_kw + 1 + _pdw))" "$_pdl" '' control=toggle)"; bar_group
    fi
    # connections
    lan=$(bar_lan); bar_kw "$k_lan"
    case $lan in
        up*) bar_add "$(bar_block lan '' "$(bar_span "$HEX_ACCENT" "$k_lan")" "$((_kw + 2))" 'lan connected')" ;;
        down) bar_add "$(bar_block lan '' "$(bar_span "$HEX_ANSI_1" "$k_lan $PANEL_WARN")" "$((_kw + 2))" 'lan not connected')" ;;
    esac
    bt=$(bar_bt); bar_kw "$k_bt_off"
    case $bt in
        name*) bar_add "$(bar_block bt '' "$(bar_span "$HEX_ACCENT" "$k_bt")" "$_kw" "bluetooth ${bt#name } connected")" ;;
        on) bar_add "$(bar_block bt '' "$(bar_span "$HEX_MUTED" "$k_bt")" "$_kw" 'bluetooth on')" ;;
        off) bar_add "$(bar_block bt '' "$(bar_span "$HEX_MUTED" "$k_bt_off")" "$_kw" 'bluetooth off')" ;;
    esac
    wifi=$(bar_wifi_pct); bar_kw "$k_wifi"
    if [ -n "$wifi" ]; then
        bar_add "$(bar_block wifi name "$(bar_span "$HEX_ACCENT" "$k_wifi")" "$_kw" "wifi ${wifi%% *}%" 6)"
        bar_add "$(bar_block wifi gauge "$(bar_gauge "${wifi%% *}" 0)" 5 "wifi ${wifi%% *}%")"
    elif [ -n "$(bar_wireless)" ]; then bar_add "$(bar_block wifi name "$(bar_span "$HEX_MUTED" "$k_wifi")" "$_kw" 'wifi not connected')"; fi
    bar_group
    # sound
    bar_audio out
    bar_audio mic
    bar_group
    # a reminder due
    due=$(rem_due 2>/dev/null || :)
    if [ -n "$due" ]; then
        due=$(printf '%s' "${due#*"$TAB"}" | cut_chars 28); bar_kw "$k_due"
        bar_add "$(bar_block due '' "$(bar_span "$HEX_ACCENT" "$k_due") $(bar_esc "$due")" "$((_kw + 29))" "reminder due: $due")"; bar_group
    fi
    # notifications
    if command -v makoctl >/dev/null 2>&1 && _nm=$(makoctl mode 2>/dev/null); then
        _nu=$(notify_unseen); [ "${_nu:-0}" -le 9 ] || _nu='9+'
        if printf '%s\n' "$_nm" | grep -qx "$NOTIFY_MODE"; then
            bar_kw "$k_dnd"
            if [ "${_nu:-0}" = 0 ]; then bar_add "$(bar_block notifications dnd "$(bar_span "$HEX_MUTED" "$k_dnd")" "$_kw" 'do not disturb')"
            else bar_add "$(bar_block notifications dnd "$(bar_span "$HEX_MUTED" "$k_dnd")" "$_kw" 'do not disturb' 6)"; fi
        fi
        bar_kw "$k_note"
        [ "${_nu:-0}" = 0 ] || bar_add "$(bar_block notifications count "$(bar_span "$HEX_ACCENT" "$k_note $_nu")" "$((_kw + 3))" "notifications, $_nu not seen")"
        bar_group
    fi
    # the seat
    lt=$(light_get)
    if [ -n "$lt" ]; then
        bar_kw "$k_light"
        bar_add "$(bar_block light name "$(bar_span "$HEX_ACCENT" "$k_light")" "$_kw" "brightness $lt%" 6)"
        bar_add "$(bar_block light gauge "$(bar_gauge "$lt" 0)" 5 "brightness $lt%" '' control=level)"
    fi
    kb=$(kb_active)
    if [ -n "$kb" ]; then
        bar_kw "$k_kb"; _kbw=0; for _kbl in $KEYBOARD; do [ "${#_kbl}" -le "$_kbw" ] || _kbw=${#_kbl}; done   # the widest layout's name
        bar_add "$(bar_block kb '' "$(bar_span "$HEX_MUTED" "$k_kb") $(bar_esc "$kb")" "$((_kw + 1 + _kbw))" "keyboard $kb" '' control=toggle)"
    fi
    bar_group
    # power
    bat=$(bar_power)
    if [ -n "$bat" ]; then
        cap=${bat%% *}; stt=${bat#* }; plus=''; c=$HEX_FG; _btl="battery $cap%"
        [ "$stt" != Charging ] || { plus=$(bar_span "$HEX_ACCENT" +); _btl="$_btl charging"; }
        [ "$cap" -ge 15 ] || [ "$stt" = Charging ] || { c=$HEX_ANSI_1; _btl="$_btl low"; }
        if [ -n "$_bw" ]; then bar_add "$(bar_block bat '' "$(bar_span "$HEX_MUTED" bat) $(bar_span "$c" "$cap")$plus" 8 "$_btl")"
        else bar_add "$(bar_block bat '' "$(bar_gauge "$cap" 0 4 "$c") $(bar_span "$c" "$cap")$plus" 9 "$_btl")"; fi
    fi
    bar_group
    # the date and the time, one block
    _cd=$(date '+%a %d %b'); _ct=$(clock_text); bar_cells "$_cd $_ct"
    bar_add "$(bar_block clock '' "$(bar_span "$HEX_MUTED" "$_cd") $_ct" "$_bc" "date $_cd, time $_ct")"
    bar_add "$(bar_block logo '' "$(bar_span "$HEX_ANSI_3" "$PANEL_PROMPT")" 1 home)"
    bar_group
    printf '[%s],\n' "$line"
}
# a click, from either bar. INSTANCE is the part: on spark's bar name (the sign), gauge, pct (the number) or text
bar_click() {   # bar_click NAME INSTANCE BUTTON RELX WIDTH X; 4 and 5 are the wheel
    case $1:$2:$3 in
        div:*) ;;
        out:gauge:1|mic:gauge:1) [ "$5" -gt 0 ] 2>/dev/null || return 0; l=$(( ($4 * 100 / $5 + 2) / 5 * 5 )); [ "$l" -le 100 ] || l=100; [ "$l" -ge 0 ] || l=0; bar_snd "$1" "$l" ;;
        out:name:1) if [ -n "${SPARK_BAR:-}" ]; then bar_snd out mute; else bar_panel_open out; fi ;;   # on spark's bar the sign mutes and the number opens the section
        light:gauge:1) [ "$5" -gt 0 ] 2>/dev/null || return 0; l=$(( ($4 * 100 / $5 + 2) / 5 * 5 )); [ "$l" -le 100 ] || l=100; light_set "$l" >/dev/null || : ;;
        light:*:4) light_set up >/dev/null || : ;;
        light:*:5) light_set down >/dev/null || : ;;
        light:*:1) bar_panel_open display ;;   # its sign and its number
        due:*:1) bar_panel_open reminders ;;
        notifications:*:1) notify_seen; bar_panel_open notifications ;;
        kb:*:1) wm_kb_layout next >/dev/null 2>&1 || : ;;
        out:*:4|mic:*:4) bar_snd "$1" +5 ;;
        out:*:5|mic:*:5) bar_snd "$1" -5 ;;
        out:*:2|out:*:3|mic:*:2|mic:*:3) bar_snd "$1" mute ;;
        pad:*:1) sh "$REPO/spark-shell" desktop pad toggle >/dev/null 2>&1 || : ;;
        logo:*:1) bar_panel_open '' ;;
        *:*:1) bar_panel_open "$1" ;;
    esac
}
bar_clicks() {   # the bar's clicks on stdin, as sway's bar writes them: `[` then one `,{...}` a line
    while IFS= read -r c; do
        c=${c#,}; [ -n "$c" ] && [ "$c" != '[' ] || continue
        # shellcheck disable=SC2046   # the six fields, split on purpose
        set -- $(printf '%s' "$c" | jq -r 'def w: if . == null or . == "" then "-" else . end; [(.name | w), (.instance | w), .button // 0, .relative_x // 0, .width // 0, .x // 0] | @tsv' 2>/dev/null) || continue
        [ $# -ge 6 ] || continue
        bar_click "$1" "$2" "$3" "$4" "$5" "$6"
        kill -USR1 "$$" 2>/dev/null || :
    done
}
bar_status() {   # bar_status [--once]
    [ "$OS" != Darwin ] || refuse_in bar "not on macOS, which has its own desktop"
    # spark-bar's word stays this loop's, a variable not exported: what the loop starts (home at a click, the pad, bar
    # again) is no bar's line. Nor does it carry the pins and the hidden as this loop started with them: each line reads
    # the config's, and so does what it starts
    _bsb=${SPARK_BAR:-}; unset SPARK_BAR BAR_PINS BAR_HIDE; SPARK_BAR=$_bsb
    theme_load; al_mend_file
    if [ "${1:-}" = --once ]; then bar_line | sed 's/,$//'; return 0; fi
    command -v jq >/dev/null 2>&1 || echo "spark-shell bar status: jq is not installed, so the bar takes no clicks (spark-shell on)" >&2
    mkdir_private "$STATE_DIR"; printf '%s\n' "$$" > "$BAR_PID"
    # traps first: a SIGUSR1 may come at once
    reader=''; sleeper=''; watcher=''
    trap 'kill ${reader:-} ${sleeper:-} ${watcher:-} 2>/dev/null || :; bar_pid_drop; exit 0' INT TERM HUP PIPE   # set -e: a failed kill in a trap ends the shell
    trap 'redraw=1; kill ${sleeper:-} 2>/dev/null || :' USR1   # a click mid-draw: draw again
    printf '{"version":1,"click_events":true}\n[\n' || { bar_pid_drop; return 0; }   # no bar reads: a write that fails ends the loop here, as the trap does where the broken pipe is a signal
    exec 3<&0; bar_clicks <&3 &   # a background job's stdin is /dev/null in dash
    reader=$!
    ! wm_session || { bar_ws_watch </dev/null & watcher=$!; }
    _ts=$(theme_sum); _bp=$({ cksum < "$BAR_PALETTE"; } 2>/dev/null || :); _line=''
    storage_sig; _bseen=$_bsg
    MACHINE_AT_FACTS=$(( $(date +%s) - MACHINE_FACTS_EVERY + 60 ))   # .facts a minute in: the devices are up
    while :; do
        _mts=${redraw:-0}   # 1 after a click, a key, a drive
        redraw=0
        storage_notice
        if [ -n "$_line" ] && [ "$({ cksum < "$BAR_PALETTE"; } 2>/dev/null || :)" != "$_bp" ]; then   # a new look: the last line recolored; on spark's bar the line that follows at once says it
            _bp=$({ cksum < "$BAR_PALETTE"; } 2>/dev/null || :); _old="$HEX_FG $HEX_ACCENT $HEX_MUTED $HEX_ANSI_1 $HEX_ANSI_3"
            if load_env "$BAR_PALETTE" 2>/dev/null && [ -z "${SPARK_BAR:-}" ]; then bar_recolor "$_line" || break; fi
        fi
        [ "$(theme_sum)" = "$_ts" ] || { _ts=$(theme_sum); config_load; for _k in $THEME_KEYS; do unset "$_k"; done; theme_load; }   # the theme changed elsewhere: read again
        [ "$_mts" = 1 ] || rm -f "$(bar_failed out)" "$(bar_failed mic)"   # a failed change is said until the next timed line
        _line=$(bar_line) || break
        printf '%s\n' "$_line" || break
        bar_font_follow
        [ -z "${SPARK_BAR:-}" ] || sparkbar_tray_follow
        machine_tick "$_mts"   # for spark's prompt line
        t=0   # one-second sleeps: a signal ends one
        while [ "$t" -lt 15 ] && [ "$redraw" = 0 ]; do
            sleep 1 & sleeper=$!
            wait "$sleeper" 2>/dev/null || :
            t=$((t + 1))
            storage_sig; [ "$_bsg" = "$_bseen" ] || { _bseen=$_bsg; redraw=1; }   # a disk came or went
        done
    done
    kill ${reader:-} ${sleeper:-} ${watcher:-} 2>/dev/null || :; bar_pid_drop
}
bar_pid_drop() { [ "$(cat "$BAR_PID" 2>/dev/null)" != "$$" ] || rm -f "$BAR_PID"; }   # the pid file goes with the loop that wrote it: a loop started since has its own pid in it
bar_font_follow() {   # BAR_TEXT=auto: the font follows the screen; _bff is the last sent
    wm_live && wm_here || return 0
    BAR_TEXT=$(bar_style BAR_TEXT auto); [ "$BAR_TEXT" = auto ] || { _bff=''; return 0; }   # a fixed size: already rendered
    FONT=$(bar_style FONT "$FONT"); case $FONT in \"*\") FONT=${FONT#\"}; FONT=${FONT%\"} ;; esac   # quoted as load_env takes it
    _bfn=$(bar_line_font "$(font_spec)")
    if [ -n "${SPARK_BAR:-}" ]; then [ "$_bfn" = "${BAR_FONT:-}" ] || sparkbar_font_again "$_bfn"; return 0; fi   # spark's bar reads its font at its start
    [ "$_bfn" != "${_bff:-}" ] || return 0
    _bfb=$(wm_bar_id); [ -n "$_bfb" ] || return 0
    if [ -z "${_bff:-}" ] && [ "$(wm_bar_config "$_bfb" | jq -r '.font // empty' 2>/dev/null)" = "pango:$_bfn" ]; then _bff=$_bfn; return 0; fi   # the first pass: the font sway has
    wm_send "bar $_bfb font pango:$_bfn" >/dev/null 2>&1 && { _bff=$_bfn; layout_refit_soon; } || :
}
bar_style() { _bv=$(sed -n "s/^$1=//p" "$CONFIG" 2>/dev/null | tail -1); printf '%s' "${_bv:-$2}"; }   # bar_style KEY DEFAULT -> the config's value now
bar_redraw() { [ -f "$BAR_PID" ] && read -r p < "$BAR_PID" && kill -USR1 "$p" 2>/dev/null || :; }
bar_stale() { [ -f "$BAR_PID" ] && [ -n "$(find "$REPO/spark-shell" -newer "$BAR_PID" 2>/dev/null)" ] && read -r _bsp < "$BAR_PID" && kill -0 "$_bsp" 2>/dev/null; }   # -> 0 when the bar predates spark-shell's change
BAR_PALETTE=$STATE_DIR/bar.palette   # written by a look change, a preview too: the five colors a line is drawn in, then what spark's bar wears beyond them, the ground, the lit shade and the alpha
bar_palette() { mkdir_private "$STATE_DIR" && printf 'HEX_FG=%s\nHEX_ACCENT=%s\nHEX_MUTED=%s\nHEX_ANSI_1=%s\nHEX_ANSI_3=%s\nHEX_BG=%s\nPANEL_HI=%s\nALPHA=%s\nPANEL_INK=%s\nPANEL_ATTENTION=%s\n' "$HEX_FG" "$HEX_ACCENT" "$HEX_MUTED" "$HEX_ANSI_1" "$HEX_ANSI_3" "$HEX_BG" "$PANEL_HI" "$ALPHA" "$PANEL_INK" "$PANEL_ATTENTION" > "$BAR_PALETTE"; }
bar_recolor() {   # bar_recolor LINE -> _old's colors swapped for the palette's
    _e=''; _i=0
    for _h in $_old; do _e="${_e}s/#$_h'/#@$_i@'/g;"; _i=$((_i + 1)); done
    _i=0
    for _h in "$HEX_FG" "$HEX_ACCENT" "$HEX_MUTED" "$HEX_ANSI_1" "$HEX_ANSI_3"; do _e="${_e}s/#@$_i@'/#$_h'/g;"; _i=$((_i + 1)); done
    printf '%s\n' "$1" | sed -e "$_e"
}
bar_volume_key() {   # bar_volume_key up|down|mute|mic
    case $1 in up) bar_snd out +5 ;; down) bar_snd out -5 ;; mute) bar_snd out mute ;; mic) bar_snd mic mute ;;
        *) refuse_in bar "volume takes up, down, mute or mic" ;; esac
    bar_redraw
}
bar_names() { REM_LOOK=1 bar_status --once 2>/dev/null | jq -r '[.[] | select(.name != "div" and .name != "logo") | .name] | unique | join(", ")' 2>/dev/null || :; }   # -> the block names present
bar_tmux() {   # bar_tmux [on|off] WHICH
    if ! command -v tmux >/dev/null 2>&1; then [ "$2" = both ] || refuse_in bar "no tmux here (spark-shell on installs it)"; return 0; fi
    if ! tmux list-sessions >/dev/null 2>&1; then
        if [ "$2" = both ]; then echo "status line: tmux is not running (it shows inside tmux)"; else refuse_in bar "tmux is not running -- start tmux first"; fi; return 0
    fi
    case $1 in
        on) tmux set -g status on; echo "status line: shown in tmux (spark-shell bar off --terminal hides it)" ;;
        off) tmux set -g status off; echo "status line: hidden in tmux (spark-shell bar on --terminal brings it back)" ;;
        *) s=$(tmux show -gv status 2>/dev/null || echo on)
           if [ "$s" != off ]; then echo "status line: shown in tmux (spark-shell bar off --terminal hides it)"; else echo "status line: hidden in tmux (spark-shell bar on --terminal brings it back)"; fi ;;
    esac
}
bar_desktop() {   # bar_desktop [on|off] WHICH
    if [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ]; then [ "$2" = both ] || refuse_in bar "no desktop here (spark-shell on desktop)"; return 0; fi
    case $1 in
        on|off) want=yes; [ "$1" = on ] || want=no
            config_set DESKTOP_BAR "$want"; DESKTOP_BAR=$want; export DESKTOP_BAR
            theme_load; EXPR=$(render_expr); desktop_look_apply
            if [ "$want" = yes ]; then echo "bar: shown $(bar_place_words "$BAR_POSITION") (spark-shell bar off --desktop hides it)"; else echo "bar: hidden (spark-shell bar on --desktop shows it)"; fi ;;
        *) if [ "$DESKTOP_BAR" = yes ]; then echo "bar: shown $(bar_place_words "$BAR_POSITION") -- $(bar_names) (spark-shell bar off --desktop hides it)"; else echo "bar: hidden (spark-shell bar on --desktop shows it)"; fi ;;
    esac
}
bar_desktop_here() { [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] || refuse_in bar "no desktop here (spark-shell on desktop)"; }
bar_where() {   # bar_where top|bottom
    bar_desktop_here; _bwo=$(bar_place)
    config_set BAR_POSITION "$1"; BAR_POSITION=$1; config_set DESKTOP_BAR yes; DESKTOP_BAR=yes; export BAR_POSITION DESKTOP_BAR
    [ "$_bwo" = "$1" ] || sparkbar_again   # spark's bar takes its place at its start; before the look, whose last step starts the pad: the pad after the bar
    theme_load; EXPR=$(render_expr); desktop_look_apply
    echo "bar: shown $(bar_place_words "$1") (spark-shell bar off --desktop hides it)"
}
bar_text() {   # bar_text [auto|N|bigger|smaller]
    bar_desktop_here
    _bts=$(bar_line_font "$(font_spec)"); _bts=${_bts##* }
    if [ -z "${1:-}" ]; then
        if [ "$BAR_TEXT" = auto ]; then echo "bar text auto, $_bts now $PANEL_SEP the text size, larger on a screen of many pixels"; else echo "bar text $BAR_TEXT $PANEL_SEP auto follows the screen"; fi
        return 0
    fi
    bar_text_step "$1" || exit 1
}
bar_text_step() {   # bar_text_step auto|N|bigger|smaller -> the receipt, or exit 1
    _bts=$(bar_line_font "$(font_spec)"); _bts=${_bts##* }; _bts=${_bts%px}; _bts=${_bts%%.*}
    case $1 in
        auto) _btn=auto ;;
        bigger) _btn=$((_bts + 1)) ;;
        smaller) _btn=$((_bts - 1)) ;;
        [6-9]|[1-3][0-9]|40) _btn=$1 ;;
        *) echo "bar text takes auto, a size from 6 to 40, bigger or smaller"; return 1 ;;
    esac
    [ "$_btn" = auto ] || { [ "$_btn" -ge 6 ] && [ "$_btn" -le 40 ]; } || { echo "bar text $_bts stays (6 to 40)"; return 1; }
    config_set BAR_TEXT "$_btn" >/dev/null; BAR_TEXT=$_btn; export BAR_TEXT
    theme_load; EXPR=$(render_expr); desktop_files >/dev/null
    _btb=$(wm_bar_id) || _btb=''
    [ -z "$_btb" ] || ! wm_session || wm_send "bar $_btb font pango:$(bar_line_font "$(font_spec)")" >/dev/null 2>&1 || :
    sparkbar_again   # spark's bar takes its text at its start
    winpad_again   # the pad's text follows
    layout_refit_soon   # the bar's height changed
    _bts=$(bar_line_font "$(font_spec)"); _bts=${_bts##* }
    if [ "$_btn" = auto ]; then echo "bar text auto, $_bts now $PANEL_SEP it follows the screen"; else echo "bar text $_btn"; fi
}
bar_tray() {   # bar_tray [on|off]
    bar_desktop_here
    case ${1:-} in
        '') if [ "$BAR_TRAY" = yes ]; then echo "tray: the apps' icons show at the bar's end (spark-shell bar tray off hides them)"; else echo "tray: off, the bar wears its own glyphs alone (spark-shell bar tray on shows the apps' icons)"; fi ;;
        on|off) bar_tray_step "$1" ;;
        --place) sparkbar_tray_place ;;   # sway's, at login and at each reload
        *) refuse_in bar "tray takes on or off" ;;
    esac
}
bar_tray_step() {   # bar_tray_step on|off -> the receipt
    _btw=no; [ "$1" != on ] || _btw=yes
    config_set BAR_TRAY "$_btw" >/dev/null; BAR_TRAY=$_btw; export BAR_TRAY
    theme_load; EXPR=$(render_expr); desktop_look_apply >/dev/null
    if [ "$_btw" = yes ]; then echo "tray on $PANEL_SEP the apps' icons show at the bar's end"; else echo "tray off $PANEL_SEP the apps keep running; their icons stay off the bar"; fi
}
bar_module_words() {   # bar_module_words NAME -> what the module shows
    case $1 in
        workspaces) echo "the workspaces: ten places, and a plate with the number where you are" ;; pad) echo 'the windows that wait on the pad' ;;
        lan) echo 'the wired network' ;; bt) echo 'bluetooth' ;; wifi) echo 'wifi; pinned, its signal as a gauge and a number' ;;
        out) echo 'the sound, its sign mutes; pinned, a gauge and a number set the level' ;; mic) echo 'the microphone, a red dot while something records; pinned, its level' ;;
        due) echo 'a reminder that is due' ;; light) echo "the screen's brightness; pinned, a gauge and a number set it" ;;
        kb) echo 'the keyboard layout in use' ;; bat) echo 'the battery' ;; clock) echo 'the time' ;; notifications) echo 'the notifications not seen; a moon in do not disturb' ;;
    esac
}
bar_list() { printf '%s' "$1" | sed 's/ /, /g'; }   # bar_list NAMES -> the names, a comma between
# the four verbs of what the bar shows. A pin puts a level's control, a gauge and a number, beside its sign, and an unpin
# takes it off; a hide takes a module off the bar, and a show brings it back. Both of the config's keys are written, in
# the bar's order, so a BAR_PINS of v0.147 becomes the two; no bar starts again: its next line says it
bar_pin() {   # bar_pin pin|unpin|hide|show [MODULE...] -- pin alone lists the modules, a line each: shown, pinned or hidden
    _bpv=$1; shift; _bpy=$(sparkbar_no_pins "$_bpv")   # sway's bar shows every module: nothing to pin or to hide there
    bar_shown
    if [ "$#" = 0 ]; then
        [ "$_bpv" = pin ] || refuse_in bar "$_bpv takes a module's name: ${BAR_MODULES#workspaces }"
        for _bpm in $BAR_MODULES; do
            _bps=shown; case " $_pinned " in *" $_bpm "*) _bps=pinned ;; esac; case " $_hidden " in *" $_bpm "*) _bps=hidden ;; esac
            printf '%-13s %-6s %s %s\n' "$_bpm" "$_bps" "$PANEL_SEP" "$(bar_module_words "$_bpm")"
        done
        [ -z "$_bpy" ] || echo "$_bpy"
        return 0
    fi
    [ -z "$_bpy" ] || refuse_in bar "$_bpy"
    for _bpm in "$@"; do
        case $_bpv in
            pin|unpin) case " $BAR_LEVELS " in *" $_bpm "*) ;; *) refuse_in bar "$_bpm has no level to pin: a pin is for $BAR_LEVELS" ;; esac ;;
            *) [ "$_bpm" != workspaces ] || refuse_in bar "the workspaces stay on the bar (spark-shell bar off --desktop hides the bar)" ;;
        esac
        [ "$_bpv" != pin ] || case " $_hidden " in *" $_bpm "*) refuse_in bar "$_bpm is hidden (spark-shell bar show $_bpm)" ;; esac
    done
    _bpp=''; _bph=''; _bpc=''; _bpd=''   # the two lists as they become, in the bar's order; what changed; a sound device named
    for _bpm in ${BAR_MODULES#workspaces }; do
        case " $_pinned " in *" $_bpm "*) _bp1=1 ;; *) _bp1='' ;; esac
        case " $_hidden " in *" $_bpm "*) _bh1=1 ;; *) _bh1='' ;; esac
        case " $* " in *" $_bpm "*)
            case $_bpm in out|mic) _bpd=1 ;; esac
            case $_bpv:$_bp1:$_bh1 in pin::*) _bp1=1; _bpc=1 ;; unpin:1:*) _bp1=''; _bpc=1 ;; hide:*:) _bh1=1; _bpc=1 ;; show:*:1) _bh1=''; _bpc=1 ;; esac ;;
        esac
        [ -z "$_bp1" ] || _bpp="${_bpp:+$_bpp }$_bpm"
        [ -z "$_bh1" ] || _bph="${_bph:+$_bph }$_bpm"
    done
    [ -n "$_bpc" ] || case $_bpv in
        pin) refuse_in bar "$* pinned already" ;; unpin) refuse_in bar "$* not pinned" ;;
        hide) refuse_in bar "$* hidden already" ;; show) refuse_in bar "$* not hidden" ;;
    esac
    config_set BAR_PINS "${_bpp:-none}" >/dev/null; config_set BAR_HIDE "$_bph" >/dev/null
    bar_redraw   # the bar's next line says it
    _bps=''; _bpg=''   # the modules on the bar, and the levels among them with their gauge
    for _bpm in $BAR_MODULES; do
        case " $_bph " in *" $_bpm "*) continue ;; esac
        _bps="${_bps:+$_bps }$_bpm"; case " $_bpp " in *" $_bpm "*) _bpg="${_bpg:+$_bpg }$_bpm" ;; esac
    done
    case $_bpv in
        pin|unpin) if [ -n "$_bpg" ]; then echo "${_bpv}ned $* $PANEL_SEP the bar shows a gauge and a number for $(bar_list "$_bpg")"; else echo "${_bpv}ned $* $PANEL_SEP the bar shows no gauge now"; fi ;;
        hide) _bpn=''; [ -z "$_bpd" ] || _bpn="the shortcut is off the bar, not the device $PANEL_SEP "
            echo "hidden $* $PANEL_SEP ${_bpn}the bar shows $(bar_list "$_bps")" ;;
        show) echo "shown $* $PANEL_SEP the bar shows $(bar_list "$_bps")" ;;
    esac
}
bar_modules_only() { for _bmo in "$@"; do case " $BAR_MODULES " in *" $_bmo "*) ;; *) return 1 ;; esac; done; }   # bar_modules_only WORD... -> 0 when each is a module's name, and with no word at all
cmd_bar() {   # cmd_bar [on|off] [--terminal|--desktop] | top|bottom | text [auto|N|bigger|smaller] | tray [on|off] | pin [MODULE...] | unpin|hide|show MODULE... | keys | start | again | seen [ID...] | status [--once] | due | volume up|down|mute|mic | panel [PAGE] ... | WORDS
    config_load
    # pin, unpin, hide and show are verbs before modules' names alone; a sentence that begins with one (show the clock) is words, below
    case ${1:-} in pin|unpin|hide|show) _cbv=$1; shift; if bar_modules_only "$@"; then bar_desktop_here; bar_pin "$_cbv" "$@"; return; fi; set -- "$_cbv" "$@" ;; esac
    case ${1:-} in
        status) shift; bar_status "$@"; return ;;
        due) rem_due_line; return ;;   # tmux's status line
        volume) shift; bar_volume_key "${1:-}"; return ;;
        light) shift; case ${1:-} in up|down) light_set "$1" >/dev/null || :; return ;; *) refuse_in bar "light takes up or down" ;; esac ;;
        panel) shift; cmd_panel "$@"; return ;;
        top|bottom) bar_where "$1"; return ;;
        text) shift; bar_text "$@"; return ;;
        tray) shift; bar_tray "$@"; return ;;
        keys) bar_desktop_here; sparkbar_keys; return ;;   # Super+equal
        start) [ "$OS" = Darwin ] || sparkbar_wake; return ;;   # sway's, at login: resident
        again) [ "$OS" = Darwin ] || { sparkbar_again; layout_refit_soon; }; return ;;   # the status loop's, apart from it: a new font
        seen) shift; notify_seen "$@"; return ;;   # mako's clicks
        on|off|'') ;;
        -*) refuse_in bar "$1 is not a bar command: on, off, top, bottom, text, tray, pin, unpin, hide, show, keys, status, volume, panel, or words for what you want" ;;
        *) [ "$OS" != Darwin ] || refuse_in bar "not on macOS, which has its own desktop"; bar_want "$*"; return ;;
    esac
    which=both; case ${LAYOUT_ON:-} in terminal) which=rooms ;; desktop) which=windows ;; esac
    [ "$which" = windows ] || bar_tmux "${1:-}" "$which"
    [ "$which" = rooms ] || bar_desktop "${1:-}" "$which"
}

