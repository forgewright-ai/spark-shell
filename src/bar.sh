# shellcheck extended-analysis=false
# ---------------------------------------------------------------- the bar
# swaybar reads `spark-shell bar status`: i3bar JSON, a line every 15 s
# and at once on SIGUSR1 to the pid in STATE_DIR/bar.pid.
# The glyphs are built from their bytes: this file stays ASCII.
BAR_SYS=${SPARK_SHELL_SYS:-/sys}      # tests: a fixture tree in place of /sys and /proc
BAR_PROC=${SPARK_SHELL_PROC:-/proc}
BAR_DEV=${SPARK_SHELL_DEV:-/dev}      # tests: the i2c devices a DDC/CI screen is reached through
BAR_PID=$STATE_DIR/bar.pid            # the running `bar status`, for the redraw signal
BAR_ASOUNDRC=$HOME/.config/alsa/asoundrc   # ALSA reads it after ~/.asoundrc; ours only with the marker line
BAR_GAP=14                            # px between blocks of a group
BAR_GROUP_GAP=28                      # px between groups: air, no divider
BAR_FULL=$(printf '\342\226\210')     # U+2588 full block: the glance's level
BAR_SHADE=$(printf '\342\226\221')    # U+2591 light shade: the glance's rest
BAR_LAN=$(printf '\342\207\205')      # U+21C5 up and down arrows: the wire
BAR_WIFI=$(printf '\342\227\240')     # U+25E0 upper half circle: wifi, the top of a radio wave
BAR_BT=$(printf '\342\234\246')       # U+2726 black four-pointed star: bluetooth on
BAR_BT_OFF=$(printf '\342\234\247')   # U+2727 white four-pointed star: bluetooth off
BAR_OUT=$(printf '\342\227\200')      # U+25C0 black left-pointing triangle: sound out
BAR_OUT_OFF=$(printf '\342\227\201')  # U+25C1 white left-pointing triangle: sound out, muted
BAR_MIC=$(printf '\342\227\211')      # U+25C9 fisheye: the mic, open
BAR_MIC_OFF=$(printf '\342\227\213')  # U+25CB white circle: the mic, muted (recording: PANEL_DOT in red)
BAR_LIGHT=$(printf '\342\230\274')    # U+263C white sun with rays: brightness
BAR_KB=$(printf '\342\214\227')       # U+2317 viewdata square: the keyboard's layout
BAR_DUE=$(printf '\342\247\227')      # U+29D7 black hourglass: a reminder due, its time come
BAR_DND=$(printf '\342\217\276')      # U+23FE power sleep symbol: do not disturb
BAR_NOTE=$(printf '\342\232\221')     # U+2691 black flag: notifications that came while nobody looked
BAR_PAD=$(printf '\342\212\237')      # U+229F squared minus: windows on the pad
# the glyph families: every glyph one cell wide (test/glyph_check.py holds the build to that)
GLYPH_FAMILIES='stone star banner'
family_set() {   # family_set FAMILY -- sets FAM_NOW (stone for any other word), FAM_ON FAM_OFF (the gauge pair), FAM_THINK, FAM_DOT, FAM_WS_OPEN FAM_WS_CLOSE (empty for banner)
    case $1 in star|banner) ;; *) set -- stone ;; esac
    [ "${FAM_NOW:-}" != "$1" ] || return 0
    case $1 in   # gauge on, off; thinking's sign; the workspace's frame, left and right; the dots
        star) _fe='\342\224\201 \342\224\200 \342\234\246 \342\227\202 \342\226\270' ;;   # U+2501 U+2500 heavy and light horizontals; U+2726 four pointed star; U+25C2 U+25B8 small triangles
        banner) _fe='\342\226\256 \342\226\257 \342\236\244 - -' ;;   # U+25AE U+25AF vertical rectangles; U+27A4 arrowhead; Roman numbers, unframed
        *) _fe='\342\226\260 \342\226\261 \342\226\260 \342\237\250 \342\237\251' ;;   # U+25B0 U+25B1 parallelograms; U+27E8 U+27E9 angle brackets
    esac
    # shellcheck disable=SC2059   # the escapes are the format
    _fb=$(printf "$_fe \302\267")   # U+00B7 middle dot: the track, every family's
    FAM_ON=${_fb%% *}; _fb=${_fb#* }; FAM_OFF=${_fb%% *}; _fb=${_fb#* }; FAM_THINK=${_fb%% *}; _fb=${_fb#* }
    FAM_WS_OPEN=${_fb%% *}; _fb=${_fb#* }; FAM_WS_CLOSE=${_fb%% *}; FAM_DOT=${_fb#* }
    [ "$FAM_WS_OPEN" != - ] || { FAM_WS_OPEN=''; FAM_WS_CLOSE=''; }
    FAM_NOW=$1
}
roman() {   # roman N -> N in Roman numerals (1 to 3999); N as it is past that
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 3999 ] || { printf '%s' "$1"; return 0; }
    _rn=$1; _ro=''
    for _rp in 1000:M 900:CM 500:D 400:CD 100:C 90:XC 50:L 40:XL 10:X 9:IX 5:V 4:IV 1:I; do
        while [ "$_rn" -ge "${_rp%%:*}" ]; do _ro=$_ro${_rp#*:}; _rn=$((_rn - ${_rp%%:*})); done
    done
    printf '%s' "$_ro"
}
# BAR_WS_ORDER: the symbols an older bar named the workspaces with; renamed as ours until a new login
BAR_WS_ORDER=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; BAR_WS_ORDER=${BAR_WS_ORDER:-$STATE_DIR}/ws-order
BAR_STEPS='\342\226\202 \342\226\204 \342\226\206 \342\226\210'   # U+2582 2584 2586 2588: the wifi bars

bar_esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/\\/\\\\/g; s/"/\\"/g'; }   # a name: pango, then JSON
bar_span() { printf "<span foreground='#%s'>%s</span>" "$1" "$2"; }   # bar_span RRGGBB MARKUP
bar_block() {   # bar_block NAME INSTANCE MARKUP [GAP] -> one block; swaybar's own separator off (the dividers are blocks)
    printf '{"name":"%s","instance":"%s","full_text":"%s","markup":"pango","separator":false,"separator_block_width":%s}' "$1" "$2" "$3" "${4:-$BAR_GAP}"
}
bar_short() {   # bar_short NAME -> lowercase, whole words up to 12 characters
    printf '%s' "$1" | tr 'A-Z' 'a-z' | awk '{ s = ""; for (i = 1; i <= NF; i++) { t = (s == "" ? $i : s " " $i); if (length(t) > 12 && s != "") break; s = t } print s }' | cut -c1-12
}
bar_gauge() {   # bar_gauge LEVEL MUTED [CELLS] [COLOR] -> CELLS cells (5), the level lit in COLOR (the accent; muted when MUTED=1)
    cells=${3:-5}; n=$(( ($1 * cells + 50) / 100 )); [ "$1" -le 0 ] || [ "$n" -gt 0 ] || n=1; [ "$n" -le "$cells" ] || n=$cells
    [ -n "${FAM_NOW:-}" ] || family_set stone
    full=''; i=0; while [ "$i" -lt "$n" ]; do full="$full$FAM_ON"; i=$((i + 1)); done
    rest=''; while [ "$i" -lt "$cells" ]; do rest="$rest$FAM_OFF"; i=$((i + 1)); done
    c=${4:-$HEX_ACCENT}; [ "$2" != 1 ] || c=$HEX_MUTED
    printf '%s%s' "$(bar_span "$c" "$full")" "$(bar_span "$HEX_MUTED" "$rest")"
}
bar_ws_label() {   # bar_ws_label N -> workspace N's label in the family set: N framed, or Roman numerals (banner)
    [ "$1" -ge 1 ] 2>/dev/null || return 1
    if [ "${FAM_NOW:-}" = banner ]; then roman "$1"; else printf '%s%s%s' "${FAM_WS_OPEN:-}" "$1" "${FAM_WS_CLOSE:-}"; fi
}
bar_ws_ours() {   # bar_ws_ours N MARK -> 0 when MARK is a name spark-shell gave workspace N
    [ "$2" != "$1" ] || return 0
    for _wf in $GLYPH_FAMILIES; do [ "$2" != "$(family_set "$_wf"; bar_ws_label "$1")" ] || return 0; done
    [ -s "$BAR_WS_ORDER" ] || return 1
    _wg=$(sed -n "${1}p" "$BAR_WS_ORDER" 2>/dev/null); [ -n "$_wg" ] || return 1
    # shellcheck disable=SC2059   # the line is the octal escapes
    [ "$2" = "$(printf "$_wg")" ]
}
bar_ws_names() {   # renames each workspace "3" or "3 writing" to "3:LABEL" or "3:LABEL writing"; a name the user gave is kept
    command -v jq >/dev/null 2>&1 || return 0
    family_set "$(bar_style GLYPH_FAMILY stone)"
    swaymsg -t get_workspaces 2>/dev/null | jq -r '.[] | select(.name | test("^[0-9]+([: ]|$)")) | "\(.num)\t\(.name)"' 2>/dev/null |
        while IFS="$TAB" read -r n name; do
            g=$(bar_ws_label "$n") || continue
            _wr=${name#"$n"}
            case $_wr in
                :*) _wr=${_wr#:}; _wx=${_wr%% *}; case $_wr in *' '*) _wr=" ${_wr#* }" ;; *) _wr='' ;; esac
                    [ "$_wx" = "$g" ] || bar_ws_ours "$n" "$_wx" || continue ;;   # a name of ours only, never one the user gave
            esac
            [ "$name" = "$n:$g$_wr" ] || swaymsg -- "rename workspace \"$name\" to \"$n:$g$_wr\"" >/dev/null 2>&1 || :
        done
}
bar_ws_watch() {   # sway's workspace events: a rename pass; its output events: a refit of the placed windows
    bar_ws_names
    swaymsg -r -t subscribe -m '["workspace","output"]' 2>/dev/null | while IFS= read -r _e; do   # -r: one event a line
        case $_e in *'"change": "init"'*|*'"change":"init"'*|*'"change": "rename"'*|*'"change":"rename"'*) bar_ws_names ;; esac   # sway spaces its JSON; a layout's rename to "3 writing" takes the label back
        case $_e in *'"change": "unspecified"'*|*'"change":"unspecified"'*) desk_refit_soon ;; esac   # sway's output event, the one change it names
    done
}
bar_timeout() { if command -v timeout >/dev/null 2>&1; then timeout 3 "$@"; else "$@"; fi; }

# --- the hardware
bar_addr() { ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1; }   # bar_addr IFACE -> a.b.c.d or nothing
bar_wired() {   # -> the wired interfaces: a real device (not lo, not a bridge), ethernet, not wireless
    for d in "$BAR_SYS"/class/net/*; do
        [ -e "$d/device" ] && [ ! -d "$d/wireless" ] && [ "$(cat "$d/type" 2>/dev/null)" = 1 ] || continue
        basename "$d"
    done
    return 0
}
bar_wireless() { for d in "$BAR_SYS"/class/net/*/wireless; do [ -d "$d" ] && basename "$(dirname "$d")"; done; return 0; }
bar_lan() {   # -> "up ADDR", "down", or nothing (no wired interface)
    any=''; up=''
    for i in $(bar_wired); do
        any=1
        [ "$(cat "$BAR_SYS/class/net/$i/carrier" 2>/dev/null)" = 1 ] || continue
        up="up $(bar_addr "$i")"; break
    done
    [ -n "$any" ] || return 0
    if [ -n "$up" ]; then printf '%s\n' "$up"; else echo down; fi
}
bar_wifi_pct() {   # -> "PERCENT ADDR" (0-100) for the first wireless interface that is up, else nothing
    for i in $(bar_wireless); do
        [ "$(cat "$BAR_SYS/class/net/$i/operstate" 2>/dev/null)" = up ] || continue
        lvl=''
        if command -v iw >/dev/null 2>&1; then   # -100 dBm is 0, -50 dBm is 100
            dbm=$(iw dev "$i" link 2>/dev/null | awk '/signal:/ {print $2; exit}')
            [ -z "$dbm" ] || lvl=$(( (dbm + 100) * 2 ))
        fi
        if [ -z "$lvl" ]; then   # the kernel's link quality, out of 70
            q=$(awk -v i="$i:" '$1 == i {gsub(/\./, "", $3); print $3; exit}' "$BAR_PROC/net/wireless" 2>/dev/null)
            [ -z "$q" ] || lvl=$(( q * 100 / 70 ))
        fi
        [ -n "$lvl" ] || lvl=0; [ "$lvl" -ge 0 ] || lvl=0; [ "$lvl" -le 100 ] || lvl=100
        printf '%s %s\n' "$lvl" "$(bar_addr "$i")"
        return
    done
    return 0
}
bar_wifi() { _wp=$(bar_wifi_pct); [ -z "$_wp" ] || printf '%s %s\n' "$(( (${_wp%% *} + 12) / 25 ))" "${_wp#* }"; }   # -> "LEVEL ADDR" (0-4), the panel's bars, else nothing
bar_bt() {   # -> "name NAME", "on", "off", or nothing (no controller)
    ls -d "$BAR_SYS"/class/bluetooth/hci* >/dev/null 2>&1 || return 0
    command -v bluetoothctl >/dev/null 2>&1 || { echo on; return; }
    bt_powered || { echo off; return; }
    dev=$(bt_connected | awk '$1 == "Device" { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }')
    if [ -n "$dev" ]; then printf 'name %s\n' "$dev"; else echo on; fi
}
mac_battery() {   # -> CAPACITY<tab>STATE<tab>LEFT from pmset (macOS)
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
bar_power() {   # -> "CAPACITY STATUS" of the first battery, or nothing
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
# wpctl status: a section's rows are "N. Description [vol:...]", the default starred
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
al_cards() { awk '/^ *[0-9]+ \[/ { n = $1; id = $0; sub(/^[^[]*\[/, "", id); sub(/ *\].*$/, "", id); long = $0; sub(/^[^:]*: [^ ]* - /, "", long); print n "\t" id "\t" long }' "$BAR_PROC/asound/cards" 2>/dev/null; }   # -> N<tab>ID<tab>LONG NAME (past "DRIVER - ": a driver's own hyphen, as USB-Audio, is not the dash)
al_name() { al_cards | awk -F '\t' -v n="$1" '$1 == n { if ($2 ~ /^(Device|USB|Generic|PCH|Intel|SB|NVidia|Audio)$/) print $3; else print $2; exit }'; }   # al_name N -> its name for the bar
al_with() { for c in $(al_cards | cut -f1); do ls -d "$BAR_PROC/asound/card$c/pcm"*"$1" >/dev/null 2>&1 && echo "$c"; done 2>/dev/null; return 0; }   # al_with p|c -> the cards that play | capture
al_first() { al_with "$1" | sed -n 1p; }   # al_first p|c -> the first card that plays | captures (sed reads the whole pipe: no broken pipe)
al_running() { for c in $(al_with "$1"); do grep -qs 'state: RUNNING' "$BAR_PROC/asound/card$c/pcm"*"$1"/sub*/status && { echo "$c"; return 0; }; done; return 0; }   # al_running p|c -> the card in use now
al_default() {   # -> the card ALSA's default resolves to: the ctl device's card, else spark-shell's file, else the first that plays
    d=$(amixer -D default info 2>/dev/null | sed -n "s/^Card default '\([^']*\)'.*/\1/p" | head -1)
    [ -z "$d" ] || { al_cards | awk -F '\t' -v id="$d" '$2 == id {print $1; exit}'; return; }
    [ ! -f "$BAR_ASOUNDRC" ] || { d=$(sed -n 's/^defaults\.pcm\.!*card //p' "$BAR_ASOUNDRC" | head -1); [ -z "$d" ] || { al_cards | awk -F '\t' -v id="$d" '$2 == id || $1 == id {print $1; exit}'; return; }; }
    al_first p
}
al_out() { c=$(al_running p); [ -n "$c" ] || c=$(al_default); [ -n "$c" ] && al_with p | grep -qx "$c" || c=$(al_first p); printf '%s' "$c"; }   # -> the card the out block is about
al_mic() { c=$(al_running c); [ -n "$c" ] || { c=$(al_default); al_with c | grep -qx "${c:-x}" || c=$(al_first c); }; printf '%s' "$c"; }
al_control() {   # al_control N p|c -> the mixer control to read and set: Master, PCM, Speaker, Headphone (Capture, Mic), else none
    want='Master PCM Speaker Headphone'; [ "$2" = p ] || want='Capture Mic'
    have=$(amixer -c "$1" scontrols 2>/dev/null | sed -n "s/^Simple mixer control '\([^']*\)',0$/\1/p")
    for w in $want; do printf '%s\n' "$have" | grep -qx "$w" && { echo "$w"; return; }; done
    return 1
}
al_level() { amixer -c "$1" sget "$2" 2>/dev/null | grep -o '\[[0-9]*%\]' | head -1 | tr -d '[]%'; }   # al_level N CONTROL -> 0..100 or nothing
al_muted() { amixer -c "$1" sget "$2" 2>/dev/null | grep -o '\[\(on\|off\)\]' | head -1 | grep -q off && echo 1 || echo 0; }
al_set_default() { al_write "$1" "$(al_bt_routed p)" "$(al_bt_routed c)"; }   # al_set_default N -- card N for programs started from now; a Bluetooth way picked stays
al_write() {   # al_write N [PLAYDEV] [CAPDEV] -- spark-shell's own asoundrc: card N, and a Bluetooth device when picked; refused when the file is yours
    id=$(al_cards | awk -F '\t' -v n="$1" '$1 == n {print $2; exit}')
    if [ -f "$BAR_ASOUNDRC" ] && ! grep -q 'rendered by spark-shell' "$BAR_ASOUNDRC"; then echo "asoundrc is yours"; return 1; fi
    if _tf=$(al_theirs); then echo "$(al_theirs_said "$_tf"): spark-shell leaves it to that file"; return 1; fi
    mkdir -p "$(dirname "$BAR_ASOUNDRC")"
    # !card: only the ! form lets a name replace alsa.conf's number; the plain form makes ALSA drop its whole configuration
    {   printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.!card %s\ndefaults.ctl.!card %s\n' "$id" "$id"
        if [ -n "${2:-}${3:-}" ]; then   # a Bluetooth way: bluez-alsa's PCM; the other way sysdefault, which follows defaults.pcm.card
            [ -z "${2:-}" ] || printf '# bluetooth out: %s\n' "$(al_bt_name p "$2")"
            [ -z "${3:-}" ] || printf '# bluetooth mic: %s\n' "$(al_bt_name c "$3")"
            printf 'pcm.!default {\n    type asym\n'
            if [ -n "${2:-}" ]; then printf '    playback.pcm { type plug slave.pcm "bluealsa:DEV=%s,PROFILE=a2dp" }\n' "$2"; else printf '    playback.pcm "sysdefault"\n'; fi
            if [ -n "${3:-}" ]; then printf '    capture.pcm { type plug slave.pcm "bluealsa:DEV=%s,PROFILE=sco" }\n' "$3"; else printf '    capture.pcm "sysdefault"\n'; fi
            printf '}\n'
        fi
    } > "$BAR_ASOUNDRC"
    amixer -c "$1" scontrols >/dev/null 2>&1 || { rm -f "$BAR_ASOUNDRC"; echo "ALSA refused the file"; return 1; }   # ALSA reads every file at each start: a refused one would take every program's sound
}
al_theirs() {   # -> the user's ~/.asoundrc, or a file it includes, that sets the default device; exit 1 when none
    [ -f "$HOME/.asoundrc" ] || return 1
    { echo "$HOME/.asoundrc"; sed -n 's/^ *<\([~/][^>]*\)>.*$/\1/p' "$HOME/.asoundrc" | sed "s|^~/|$HOME/|"; } | while IFS= read -r f; do if grep -qs '^ *pcm\.!default' "$f"; then printf '%s\n' "$f"; exit 0; fi; done | grep .   # grep: no such file is exit 1 (a loop that ends finding none says 0)
}
al_theirs_said() {   # al_theirs_said FILE -> who picks the sound device, in a few words, the home as ~
    case $1 in "$HOME/.asoundrc") echo "your ~/.asoundrc picks the sound device" ;; *) echo "${1#"$HOME/"} picks the sound device, read by your ~/.asoundrc" | sed 's|^\([^/~]\)|~/\1|' ;; esac
}
# bluez-alsa: a headset plays on A2DP and listens on SCO; its mixer is
# NAME - A2DP and NAME - SCO under amixer -D bluealsa
al_bt() {   # al_bt p|c -> NAME<tab>DEV per Bluetooth device bluez-alsa offers now that plays (A2DP) | listens (SCO)
    command -v bluealsa-aplay >/dev/null 2>&1 || return 0
    _pr=a2dp; _dir=playback; [ "$1" = p ] || { _pr=sco; _dir=capture; }
    bar_timeout bluealsa-aplay -L 2>/dev/null | awk -v pr="PROFILE=$_pr" -v dir="$_dir" '
        /^bluealsa:/ { dev = ""; if (index($0, pr)) { d = $0; sub(/.*DEV=/, "", d); sub(/,.*$/, "", d); if (d ~ /^[0-9A-F][0-9A-F](:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])(:[0-9A-F][0-9A-F])$/) dev = d }; next }
        dev != "" { l = $0; sub(/^[ \t]+/, "", l); n = split(l, f, ", "); if (f[n] == dir) { name = l; sub(/, .*$/, "", name); gsub(/[^ -~]/, "", name); if (name != "" && !seen[dev]++) print name "\t" dev }; dev = "" }'
}
al_bt_name() { al_bt "$1" | awk -F '\t' -v d="$2" '$2 == d {print $1; exit}'; }   # al_bt_name p|c DEV -> its name while bluez-alsa offers it
al_bt_routed() {   # al_bt_routed p|c -> the DEV spark-shell's file sends playing | listening to, or nothing
    [ -f "$BAR_ASOUNDRC" ] && grep -q 'rendered by spark-shell' "$BAR_ASOUNDRC" || return 0
    _w=playback; _pr=a2dp; [ "$1" = p ] || { _w=capture; _pr=sco; }
    sed -n "s/^ *$_w\.pcm { type plug slave\.pcm \"bluealsa:DEV=\([0-9A-F:]*\),PROFILE=$_pr\" }\$/\1/p" "$BAR_ASOUNDRC" | head -1
}
al_bt_said() {   # al_bt_said p|c -> the routed device's name as the file wrote it
    _w=out; [ "$1" = p ] || _w=mic
    [ -n "$(al_bt_routed "$1")" ] && sed -n "s/^# bluetooth $_w: //p" "$BAR_ASOUNDRC" | head -1
}
al_bt_ctl() {   # al_bt_ctl p|c -> bluez-alsa's mixer control for the routed device, while it is there
    _d=$(al_bt_routed "$1"); [ -n "$_d" ] || return 1
    _n=$(al_bt_name "$1" "$_d"); [ -n "$_n" ] || return 1
    if [ "$1" = p ]; then echo "$_n - A2DP"; else echo "$_n - SCO"; fi
}
al_bt_level() { if [ "$1" = p ]; then amixer -D bluealsa sget "$2" 2>/dev/null | sed -n 's/.*Playback [0-9]* \[\([0-9]*\)%\].*/\1/p' | head -1; else amixer -D bluealsa sget "$2" 2>/dev/null | sed -n 's/.*Capture [0-9]* \[\([0-9]*\)%\].*/\1/p' | head -1; fi; }   # al_bt_level p|c CONTROL
al_bt_muted() { if [ "$1" = p ]; then _s=$(amixer -D bluealsa sget "$2" 2>/dev/null | grep 'Playback [0-9]' | grep -o '\[o[nf]*\]' | head -1); else _s=$(amixer -D bluealsa sget "$2" 2>/dev/null | sed -n 's/.*Capture [0-9]//p' | grep -o '\[o[nf]*\]' | head -1); fi; [ "$_s" = '[off]' ] && echo 1 || echo 0; }   # al_bt_muted p|c CONTROL -> 1 when its switch is off
al_mend_file() {   # a file of ours that says `defaults.pcm.card NAME` (which ALSA refuses) takes the ! form
    [ -f "$BAR_ASOUNDRC" ] && grep -q 'rendered by spark-shell' "$BAR_ASOUNDRC" && grep -q '^defaults\.pcm\.card ' "$BAR_ASOUNDRC" || return 0
    t=$(sed -e 's/^defaults\.pcm\.card /defaults.pcm.!card /' -e 's/^defaults\.ctl\.card /defaults.ctl.!card /' "$BAR_ASOUNDRC") && printf '%s\n' "$t" > "$BAR_ASOUNDRC"
}
snd_out() { read_once snd.out snd_out_now; }   # -> NAME, LEVEL (or -), MUTED on three lines; nothing without an output
snd_out_now() {
    case $SND in
        wpctl) n=$(wp_default Sinks); [ -n "$n" ] || return 0; printf '%s\n%s\n%s\n' "$n" "$(wp_level @DEFAULT_AUDIO_SINK@)" "$(wp_muted @DEFAULT_AUDIO_SINK@)" ;;
        pactl) s=$(pactl get-default-sink 2>/dev/null); [ -n "$s" ] || return 0; n=$(pa_desc sinks "$s"); printf '%s\n%s\n%s\n' "${n:-$s}" "$(pa_level sink @DEFAULT_SINK@)" "$(pa_muted sink @DEFAULT_SINK@)" ;;
        alsa) if [ -n "$(al_bt_routed p)" ]; then   # a Bluetooth output: its mixer while it is there, its name from the file when it is gone
                if ctl=$(al_bt_ctl p); then printf '%s\n%s\n%s\n' "${ctl% - A2DP}" "$(al_bt_level p "$ctl")" "$(al_bt_muted p "$ctl")"; else printf '%s\n-\n0\n' "$(al_bt_said p)"; fi; return 0
            fi
            c=$(al_out); [ -n "$c" ] || return 0
            if ctl=$(al_control "$c" p); then printf '%s\n%s\n%s\n' "$(al_name "$c")" "$(al_level "$c" "$ctl")" "$(al_muted "$c" "$ctl")"; else printf '%s\n-\n0\n' "$(al_name "$c")"; fi ;;
    esac
}
snd_mic() { read_once snd.mic snd_mic_now; }   # -> NAME, LIVE, MUTED, LEVEL (or -) on four lines; nothing without a microphone
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
            if [ -n "$(al_bt_routed "$k")" ]; then   # a Bluetooth way: bluez-alsa's mixer
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
            off=mute; on=unmute; [ "$k" = p ] || { off=nocap; on=cap; }   # a capture switch: amixer's words are cap and nocap (mute is refused)
            case $1 in
                mute) amixer -q -c "$c" sset "$ctl" toggle ;; muted) amixer -q -c "$c" sset "$ctl" "$off" ;; unmuted) amixer -q -c "$c" sset "$ctl" "$on" ;;
                +*|-*) amixer -q -c "$c" sset "$ctl" "${1#[+-]}%${1%"${1#?}"}" ;;
                *) amixer -q -c "$c" sset "$ctl" "$1%" ;;
            esac ;;
        *) return 1 ;;
    esac >/dev/null 2>&1
}
snd_settable() {   # snd_settable out|mic -> exit 0 when its level and mute can be set; else one line saying why, exit 1
    SND=${SND:-$(snd_tool)}
    [ -n "$SND" ] || { echo "$1: no audio system found"; return 1; }
    if [ "$1" = out ]; then _so=$(snd_out); _sl=$(printf '%s\n' "$_so" | sed -n 2p); else _so=$(snd_mic); _sl=$(printf '%s\n' "$_so" | sed -n 4p); fi
    [ -n "$_so" ] || { if [ "$1" = out ]; then echo "out: no output found"; else echo "mic: no microphone found"; fi; return 1; }
    [ "$_sl" = - ] || [ -z "$_sl" ] || return 0
    echo "$1: $(printf '%s\n' "$_so" | sed -n 1p) has no volume control here, so it cannot be muted or set"; return 1
}
snd_said() {   # snd_said out|mic muted|unmuted -> the state read back, one line; exit 1 when the audio system did not take it
    if [ "$1" = out ]; then _m=$(snd_out | sed -n 3p); else _m=$(snd_mic | sed -n 3p); fi
    case $2:$_m in muted:1|unmuted:0) echo "$1 $2" ;; *) echo "$1 is not $2: the audio system did not take it"; return 1 ;; esac
}
snd_apply() {   # snd_apply out|mic LEVEL|muted|unmuted -> the state read back, or exit 1
    snd_set "$1" "$2" || { echo "$1 could not be changed; check its current state"; return 1; }
    if [ "$1" = out ]; then _sa=$(snd_out); _sl=$(printf '%s\n' "$_sa" | sed -n 2p)
    else _sa=$(snd_mic); _sl=$(printf '%s\n' "$_sa" | sed -n 4p); fi
    _sn=$(printf '%s\n' "$_sa" | sed -n 1p); _sm=$(printf '%s\n' "$_sa" | sed -n 3p)
    case $_sl:$_sm in *:0|*:1) ;; *) echo "$1 changed, but its current state could not be verified"; return 1 ;; esac
    case $_sl in ''|*[!0-9]*) echo "$1 changed, but its level could not be read back"; return 1 ;; esac
    case $2:$_sm in muted:0|unmuted:1) echo "$1 is not $2: the audio system did not take it"; return 1 ;; esac
    case $2 in muted|unmuted) ;; *)
        # mixers quantize levels: one percentage point of slack
        _sd=$((_sl - $2)); [ "$_sd" -ge -1 ] && [ "$_sd" -le 1 ] || {
            echo "$1 is at $_sl%, not the requested $2%; the audio system did not take that level"; return 1;
        } ;;
    esac
    case $2 in muted|unmuted) echo "$1 $2" ;; *) echo "$1 at $_sl%" ;; esac
    [ -z "${PROVIDE_EFFECT:-}" ] || jq -cn --arg id "$1" --arg title "$_sn" --arg operation "$2" --argjson level "$_sl" --argjson muted "$_sm" \
        '{kind:"sound", id:$id, title:$title, operation:$operation, level:$level, muted:($muted == 1)}' > "$TMP/action.effect"
}
snd_adjust() {   # snd_adjust out|mic DELTA -- the level moved by DELTA points, kept in 0..100
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
light_ddc() {   # light_ddc ARGS... -- ddcutil on the screen's bus, one at a time (a held key would race the bus)
    _b=$(light_ddc_bus); [ -n "$_b" ] || return 1
    if command -v flock >/dev/null 2>&1; then mkdir_private "$STATE_DIR"; flock -w 3 "$STATE_DIR/ddc.lock" ddcutil --bus "$_b" "$@"; else ddcutil --bus "$_b" "$@"; fi
}
light_ddc_bus() {   # -> the i2c bus of the first screen ddcutil drives; nothing when none answers
    _rw=''; for _d in "$BAR_DEV"/i2c-*; do [ ! -r "$_d" ] || [ ! -w "$_d" ] || { _rw=1; break; }; done
    [ -n "$_rw" ] || return 0   # no i2c device open to you: nothing asked, nothing kept
    # in the runtime directory: kept 10 minutes, 1 when a screen sleeps (DPMS)
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
light_get() { read_once light light_get_now; }   # -> PERCENT, or nothing without a brightness to set
light_get_now() {
    case $(light_tool) in
        backlight) brightnessctl -m -c backlight info 2>/dev/null | awk -F, '{gsub(/%/, "", $4); print $4; exit}' ;;
        ddc) _f=$STATE_DIR/light
            if [ -f "$_f" ] && [ $(( $(date +%s) - $(stat -c %Y "$_f" 2>/dev/null || stat -f %m "$_f" 2>/dev/null || echo 0) )) -lt 60 ]; then cat "$_f"; return 0; fi
            light_ddc getvcp 10 --terse 2>/dev/null | awk '$1 == "VCP" && $2 == "10" && $5 > 0 {printf "%d\n", $4 * 100 / $5 + 0.5}' > "$_f.new" && [ -s "$_f.new" ] && mv "$_f.new" "$_f" || rm -f "$_f.new"
            cat "$_f" 2>/dev/null || : ;;
    esac
}
light_set() {   # light_set N|up|down|+5|-5 -> one line; exit 1 when nothing took it
    _t=$(light_tool); [ -n "$_t" ] || { echo "no brightness to set here (a laptop's backlight, or a screen that speaks DDC/CI)"; return 1; }
    _now=$(light_get); [ -n "$_now" ] || _now=50
    case ${1:-} in
        up|+5) _to=$((_now + 5)) ;; down|-5) _to=$((_now - 5)) ;;
        [0-9]|[0-9][0-9]|100) _to=$1 ;;
        *) echo "brightness takes 1 to 100, up or down"; return 1 ;;
    esac
    [ "$_to" -le 100 ] || _to=100; [ "$_to" -ge 1 ] || _to=1   # never black: a screen at 0 looks off
    case $_t in
        backlight) brightnessctl -q -c backlight set "$_to%" >/dev/null 2>&1 || { echo "brightnessctl could not set it (the video group, a login again)"; return 1; } ;;
        ddc) light_ddc setvcp 10 "$_to" --noverify >/dev/null 2>&1 || { echo "the screen took no brightness over DDC/CI"; return 1; }
            mkdir_private "$STATE_DIR"; echo "$_to" > "$STATE_DIR/light" ;;
    esac
    bar_redraw
    echo "brightness at $_to%"
}
kb_active() { read_once kb.active kb_active_now; }   # -> the layout in use, by its KEYBOARD word; nothing with one layout or none
kb_active_now() {
    [ "$(printf '%s\n' $KEYBOARD | grep -c .)" -gt 1 ] || return 0
    _i=$(kb_names | cut -f1); [ -n "$_i" ] || _i=0
    printf '%s\n' $KEYBOARD | sed -n "$((_i + 1))p"
}

# --- the line
bar_line() {   # -> one JSON array of the blocks present now
    line=''; group=''
    bar_add() { group="${group:+$group,}$1"; }
    bar_group() { [ -z "$group" ] || { line="${line:+$line,}${group%\"separator_block_width\":*}\"separator_block_width\":$BAR_GROUP_GAP}"; group=''; }; }   # the group's last block takes the wider air
    SND=$(snd_tool)
    # signs or words, read at each line so a change in Settings shows at once
    _bw=''; [ "$(bar_style BAR_GLYPHS signs)" != words ] || _bw=1
    family_set "$(bar_style GLYPH_FAMILY stone)"   # read at each line too
    if [ -n "$_bw" ]; then
        k_lan=lan k_bt=bt k_bt_off='bt off' k_wifi=wifi k_out=out k_out_off=out k_mic=mic k_mic_off=mic k_light=light k_kb=kb k_due=due k_dnd='do not disturb' k_note=new k_pad=pad
    else
        k_lan=$BAR_LAN k_bt=$BAR_BT k_bt_off=$BAR_BT_OFF k_wifi=$BAR_WIFI k_out=$BAR_OUT k_out_off=$BAR_OUT_OFF k_mic=$BAR_MIC k_mic_off=$BAR_MIC_OFF k_light=$BAR_LIGHT k_kb=$BAR_KB k_due=$BAR_DUE k_dnd=$BAR_DND k_note=$BAR_NOTE k_pad=$BAR_PAD
    fi
    # the pad first: its sign and the count, muted while the pad is in sight, the accent while hidden
    _pdn=$(pad_count)
    if [ "${_pdn:-0}" -gt 0 ] 2>/dev/null; then
        _pdc=$HEX_MUTED; ! pad_hidden || _pdc=$HEX_ACCENT
        bar_add "$(bar_block pad '' "$(bar_span "$_pdc" "$k_pad") $_pdn")"; bar_group
    fi
    # connections
    lan=$(bar_lan)
    case $lan in
        up*) bar_add "$(bar_block lan '' "$(bar_span "$HEX_ACCENT" "$k_lan")")" ;;   # connected: the accent, as bluetooth's
        down) bar_add "$(bar_block lan '' "$(bar_span "$HEX_ANSI_1" "$k_lan $PANEL_WARN")")" ;;
    esac
    bt=$(bar_bt)
    case $bt in
        name*) bar_add "$(bar_block bt '' "$(bar_span "$HEX_ACCENT" "$k_bt")")" ;;   # connected: the device's name is the panel's
        on) bar_add "$(bar_block bt '' "$(bar_span "$HEX_MUTED" "$k_bt")")" ;;
        off) bar_add "$(bar_block bt '' "$(bar_span "$HEX_MUTED" "$k_bt_off")")" ;;
    esac
    wifi=$(bar_wifi_pct)
    if [ -n "$wifi" ]; then   # connected: the sign in the accent, and the signal, a gauge as sound's
        bar_add "$(bar_block wifi name "$(bar_span "$HEX_ACCENT" "$k_wifi")" 6)"
        bar_add "$(bar_block wifi gauge "$(bar_gauge "${wifi%% *}" 0)")"
    elif [ -n "$(bar_wireless)" ]; then bar_add "$(bar_block wifi name "$(bar_span "$HEX_MUTED" "$k_wifi")")"; fi   # off, or no network: the sign alone
    bar_group
    # sound
    out=$(snd_out)
    if [ -n "$out" ]; then
        lvl=$(printf '%s\n' "$out" | sed -n 2p); m=$(printf '%s\n' "$out" | sed -n 3p)
        k=$k_out; c=$HEX_ACCENT; [ "$m" != 1 ] || { k=$k_out_off; c=$HEX_MUTED; }   # on: filled, in the accent; muted: hollow, muted
        gap=$BAR_GAP; [ "$lvl" = - ] || [ -z "$lvl" ] || gap=6   # the gauge sits close to its sign
        bar_add "$(bar_block out name "$(bar_span "$c" "$k")" "$gap")"
        [ "$lvl" = - ] || [ -z "$lvl" ] || bar_add "$(bar_block out gauge "$(bar_gauge "$lvl" "$m")")"
    fi
    mic=$(snd_mic)
    if [ -n "$mic" ]; then
        live=$(printf '%s\n' "$mic" | sed -n 2p); m=$(printf '%s\n' "$mic" | sed -n 3p); lvl=$(printf '%s\n' "$mic" | sed -n 4p)
        c=$HEX_ACCENT; k=$k_mic; [ "$m" != 1 ] || { k=$k_mic_off; c=$HEX_MUTED; }   # open: the accent; muted: hollow, muted
        [ "$live" != 1 ] || { c=$HEX_ANSI_1; k=$PANEL_DOT; [ -z "$_bw" ] || k="mic $PANEL_DOT"; }   # red, a dot, while a program records
        if [ "$lvl" = - ] || [ -z "$lvl" ]; then bar_add "$(bar_block mic name "$(bar_span "$c" "$k")")"
        else
            bar_add "$(bar_block mic name "$(bar_span "$c" "$k")" 6)"
            bar_add "$(bar_block mic gauge "$(bar_gauge "$lvl" "$m")")"
        fi
    fi
    bar_group
    # a reminder due: its own group
    due=$(rem_due 2>/dev/null || :)
    [ -z "$due" ] || { bar_add "$(bar_block due '' "$(bar_span "$HEX_ACCENT" "$k_due") $(bar_esc "$(printf '%s' "${due#*"$TAB"}" | cut_chars 28)")")"; bar_group; }
    # notifications: do not disturb while on, and the unseen ones with their count
    if command -v makoctl >/dev/null 2>&1 && _nm=$(makoctl mode 2>/dev/null); then
        _nu=$(notify_unseen); [ "${_nu:-0}" -le 9 ] || _nu='9+'
        if printf '%s\n' "$_nm" | grep -qx "$NOTIFY_MODE"; then
            if [ "${_nu:-0}" = 0 ]; then bar_add "$(bar_block notifications dnd "$(bar_span "$HEX_MUTED" "$k_dnd")")"
            else bar_add "$(bar_block notifications dnd "$(bar_span "$HEX_MUTED" "$k_dnd")" 6)"; fi
        fi
        [ "${_nu:-0}" = 0 ] || bar_add "$(bar_block notifications count "$(bar_span "$HEX_ACCENT" "$k_note $_nu")")"
        bar_group
    fi
    # the seat: the brightness, the keyboard's layout
    lt=$(light_get)
    if [ -n "$lt" ]; then
        bar_add "$(bar_block light name "$(bar_span "$HEX_ACCENT" "$k_light")" 6)"   # a screen it sets: the accent, as a gauge's sign
        bar_add "$(bar_block light gauge "$(bar_gauge "$lt" 0)")"
    fi
    kb=$(kb_active)
    [ -z "$kb" ] || bar_add "$(bar_block kb '' "$(bar_span "$HEX_MUTED" "$k_kb") $(bar_esc "$kb")")"
    bar_group
    # power: four cells and the number
    bat=$(bar_power)
    if [ -n "$bat" ]; then
        cap=${bat%% *}; stt=${bat#* }; plus=''; c=$HEX_FG
        [ "$stt" != Charging ] || plus=$(bar_span "$HEX_ACCENT" +)
        [ "$cap" -ge 15 ] || [ "$stt" = Charging ] || c=$HEX_ANSI_1
        if [ -n "$_bw" ]; then bar_add "$(bar_block bat '' "$(bar_span "$HEX_MUTED" bat) $(bar_span "$c" "$cap")$plus")"   # words: the kind word and the number
        else bar_add "$(bar_block bat '' "$(bar_gauge "$cap" 0 4 "$c") $(bar_span "$c" "$cap")$plus")"; fi
    fi
    bar_group
    # time
    bar_add "$(bar_block clock '' "$(bar_span "$HEX_MUTED" "$(date '+%a %d %b')") $(clock_text)")"
    bar_add "$(bar_block logo '' "$(bar_span "$HEX_ANSI_3" "$PANEL_PROMPT")")"   # spark-shell's own sign, last; a click opens the panel as Super+d does
    bar_group   # the palette has no block: it is picked in the panel
    printf '[%s],\n' "$line"
}
bar_click() {   # bar_click NAME INSTANCE BUTTON RELX WIDTH X -- one click or wheel step on a block
    case $1:$2:$3 in
        div:*) ;;
        out:gauge:1|mic:gauge:1) [ "$5" -gt 0 ] 2>/dev/null || return 0; l=$(( ($4 * 100 / $5 + 2) / 5 * 5 )); [ "$l" -le 100 ] || l=100; [ "$l" -ge 0 ] || l=0; snd_set "$1" "$l" ;;
        light:gauge:1) [ "$5" -gt 0 ] 2>/dev/null || return 0; l=$(( ($4 * 100 / $5 + 2) / 5 * 5 )); [ "$l" -le 100 ] || l=100; light_set "$l" >/dev/null || : ;;
        light:*:4) light_set up >/dev/null || : ;;
        light:*:5) light_set down >/dev/null || : ;;
        light:name:1) bar_panel_open display ;;   # the word opens the display's section
        due:*:1) bar_panel_open reminders ;;
        notifications:*:1) notify_seen; bar_panel_open notifications ;;   # opened: what came is looked at
        kb:*:1) swaymsg -- input type:keyboard xkb_switch_layout next >/dev/null 2>&1 || : ;;   # the next layout, as Super+Ctrl+space
        out:*:4|mic:*:4) snd_set "$1" +5 ;;
        out:*:5|mic:*:5) snd_set "$1" -5 ;;
        out:*:2|out:*:3|mic:*:2|mic:*:3) snd_set "$1" mute ;;
        pad:*:1) sh "$REPO/spark-shell" desktop pad toggle >/dev/null 2>&1 || : ;;   # the pad hidden or back in sight
        logo:*:1) bar_panel_open '' ;;   # the dialog at its prompt, as Super+d does
        *:*:1) bar_panel_open "$1" ;;   # the panel, that block first
    esac
}
bar_clicks() {   # swaybar's clicks on stdin: `[` then one `,{...}` a line; each acted on, then the bar redrawn
    while IFS= read -r c; do
        c=${c#,}; [ -n "$c" ] && [ "$c" != '[' ] || continue
        # shellcheck disable=SC2046   # the six fields, split on purpose
        set -- $(printf '%s' "$c" | jq -r 'def w: if . == null or . == "" then "-" else . end; [(.name | w), (.instance | w), .button // 0, .relative_x // 0, .width // 0, .x // 0] | @tsv' 2>/dev/null) || continue
        [ $# -ge 6 ] || continue
        bar_click "$1" "$2" "$3" "$4" "$5" "$6"
        kill -USR1 "$$" 2>/dev/null || :
    done
}
bar_status() {   # bar_status [--once] -- the bar's program: the header, then a line every 15 s and at once on a click or SIGUSR1
    [ "$OS" != Darwin ] || refuse_in bar "not on macOS, which has its own desktop"
    theme_load; al_mend_file
    if [ "${1:-}" = --once ]; then bar_line | sed 's/,$//'; return 0; fi
    command -v jq >/dev/null 2>&1 || echo "spark-shell bar status: jq is not installed, so the bar takes no clicks (spark-shell on)" >&2
    mkdir_private "$STATE_DIR"; printf '%s\n' "$$" > "$BAR_PID"
    # the traps first: the reader's first SIGUSR1 may come before it is read here
    reader=''; sleeper=''; watcher=''
    trap 'kill ${reader:-} ${sleeper:-} ${watcher:-} 2>/dev/null || :; rm -f "$BAR_PID"; exit 0' INT TERM HUP PIPE   # || : -- a failing kill inside a trap would end the shell under set -e
    trap 'redraw=1; kill ${sleeper:-} 2>/dev/null || :' USR1   # redraw: a click while a line is drawn draws again at once
    printf '{"version":1,"click_events":true}\n[\n'
    exec 3<&0; bar_clicks <&3 &   # an explicit stdin: a background job's own would be /dev/null in dash (POSIX)
    reader=$!
    [ -z "${SWAYSOCK:-}" ] || { bar_ws_watch </dev/null & watcher=$!; }   # the workspaces' glyphs
    _ts=$(theme_sum); _bp=$({ cksum < "$BAR_PALETTE"; } 2>/dev/null || :); _line=''
    storage_sig; _bseen=$_bsg
    MACHINE_AT_FACTS=$(( $(date +%s) - MACHINE_FACTS_EVERY + 60 ))   # the machine folder's.facts a minute in: the sound and the devices are up by then
    while :; do
        _mts=${redraw:-0}   # this pass came at once, after a click, a key or a drive
        redraw=0
        storage_notice   # a drive plugged in since the last look: one notification
        if [ -n "$_line" ] && [ "$({ cksum < "$BAR_PALETTE"; } 2>/dev/null || :)" != "$_bp" ]; then   # a new look: the last line in its colors at once
            _bp=$({ cksum < "$BAR_PALETTE"; } 2>/dev/null || :); _old="$HEX_FG $HEX_ACCENT $HEX_MUTED $HEX_ANSI_1 $HEX_ANSI_3"
            if load_env "$BAR_PALETTE" 2>/dev/null; then bar_recolor "$_line"; fi
        fi
        [ "$(theme_sum)" = "$_ts" ] || { _ts=$(theme_sum); config_load; for _k in $THEME_KEYS; do unset "$_k"; done; theme_load; }   # a palette changed outside a look change (spark theme): read again
        _line=$(bar_line) || break
        printf '%s\n' "$_line"
        bar_font_follow
        machine_tick "$_mts"   # what is in use now, for spark's prompt line, aside
        t=0   # 15 one-second sleeps: a signal ends the current one, and a click that fell between two is seen within 1 s
        while [ "$t" -lt 15 ] && [ "$redraw" = 0 ]; do
            sleep 1 & sleeper=$!
            wait "$sleeper" 2>/dev/null || :
            t=$((t + 1))
            storage_sig; [ "$_bsg" = "$_bseen" ] || { _bseen=$_bsg; redraw=1; }   # a disk came or went: a look now, not in 15 s
        done
    done
    kill ${reader:-} ${watcher:-} 2>/dev/null || :; rm -f "$BAR_PID"
}
bar_font_follow() {   # BAR_TEXT=auto: the bar's font follows the screens' size, sent to sway when it changed; _bff is the font sent last
    [ -S "${SWAYSOCK:-}" ] && command -v swaymsg >/dev/null 2>&1 || return 0
    BAR_TEXT=$(bar_style BAR_TEXT auto); [ "$BAR_TEXT" = auto ] || { _bff=''; return 0; }   # a size of its own: the render and the verb gave it
    FONT=$(bar_style FONT "$FONT"); case $FONT in \"*\") FONT=${FONT#\"}; FONT=${FONT%\"} ;; esac   # quoted as load_env takes it
    _bfn=$(bar_line_font "$(font_spec)")
    [ "$_bfn" != "${_bff:-}" ] || return 0
    _bfb=$(swaymsg -t get_bar_config 2>/dev/null | tr -d '[]" \n' | cut -d, -f1); [ -n "$_bfb" ] || return 0
    if [ -z "${_bff:-}" ] && [ "$(swaymsg -t get_bar_config "$_bfb" 2>/dev/null | jq -r '.font // empty' 2>/dev/null)" = "pango:$_bfn" ]; then _bff=$_bfn; return 0; fi   # the first pass: the font it has already
    swaymsg -- "bar $_bfb font pango:$_bfn" >/dev/null 2>&1 && { _bff=$_bfn; desk_refit_soon; } || :   # a new height: the placed windows follow
}
bar_style() { _bv=$(sed -n "s/^$1=//p" "$CONFIG" 2>/dev/null | tail -1); printf '%s' "${_bv:-$2}"; }   # bar_style KEY DEFAULT -> the config's value now: the running bar reads it at each line
bar_redraw() { [ -f "$BAR_PID" ] && read -r p < "$BAR_PID" && kill -USR1 "$p" 2>/dev/null || :; }   # the running bar draws again now
bar_stale() { [ -f "$BAR_PID" ] && [ -n "$(find "$REPO/spark-shell" -newer "$BAR_PID" 2>/dev/null)" ] && read -r _bsp < "$BAR_PID" && kill -0 "$_bsp" 2>/dev/null; }   # -> 0 when the running bar started before spark-shell last changed
BAR_PALETTE=$STATE_DIR/bar.palette   # the colors of the bar's line, written by a look change for the bar to take at once
bar_palette() { mkdir_private "$STATE_DIR" && printf 'HEX_FG=%s\nHEX_ACCENT=%s\nHEX_MUTED=%s\nHEX_ANSI_1=%s\nHEX_ANSI_3=%s\n' "$HEX_FG" "$HEX_ACCENT" "$HEX_MUTED" "$HEX_ANSI_1" "$HEX_ANSI_3" > "$BAR_PALETTE"; }
bar_recolor() {   # bar_recolor LINE -> the line with the new palette's colors in place of _old's (BAR_PALETTE's order)
    _e=''; _i=0
    for _h in $_old; do _e="${_e}s/#$_h'/#@$_i@'/g;"; _i=$((_i + 1)); done
    _i=0
    for _h in "$HEX_FG" "$HEX_ACCENT" "$HEX_MUTED" "$HEX_ANSI_1" "$HEX_ANSI_3"; do _e="${_e}s/#@$_i@'/#$_h'/g;"; _i=$((_i + 1)); done
    printf '%s\n' "$1" | sed -e "$_e"
}
bar_volume_key() {   # bar_volume_key up|down|mute|mic -- the keyboard's volume keys
    case $1 in up) snd_set out +5 ;; down) snd_set out -5 ;; mute) snd_set out mute ;; mic) snd_set mic mute ;;
        *) refuse_in bar "volume takes up, down, mute or mic" ;; esac
    bar_redraw
}
bar_names() { REM_LOOK=1 bar_status --once 2>/dev/null | jq -r '[.[] | select(.name != "div" and .name != "logo") | .name] | unique | join(", ")' 2>/dev/null || :; }   # the blocks present now (the sign is no fact)
bar_tmux() {   # bar_tmux [on|off] WHICH -- tmux's status line, live
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
bar_desktop() {   # bar_desktop [on|off] WHICH -- the bar at the top: the config key, the render, a running sway
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
bar_where() {   # bar_where top|bottom -- the bar shown there: the config keys, the render, a running sway reloaded
    bar_desktop_here
    config_set BAR_POSITION "$1"; BAR_POSITION=$1; config_set DESKTOP_BAR yes; DESKTOP_BAR=yes; export BAR_POSITION DESKTOP_BAR
    theme_load; EXPR=$(render_expr); desktop_look_apply
    echo "bar: shown $(bar_place_words "$1") (spark-shell bar off --desktop hides it)"
}
bar_text() {   # bar_text [auto|N|bigger|smaller] -- the bar's own text size; bare, the size it has now
    bar_desktop_here
    _bts=$(bar_line_font "$(font_spec)"); _bts=${_bts##* }
    if [ -z "${1:-}" ]; then
        if [ "$BAR_TEXT" = auto ]; then echo "bar text auto, $_bts now $PANEL_SEP the text size, larger on a screen of many pixels"; else echo "bar text $BAR_TEXT $PANEL_SEP auto follows the screen"; fi
        return 0
    fi
    bar_text_step "$1" || exit 1
}
bar_text_step() {   # bar_text_step auto|N|bigger|smaller -> the receipt, or the refusal and exit 1 (the verb and the panel's step share it)
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
    _btb=$(swaymsg -t get_bar_config 2>/dev/null | tr -d '[]" \n' | cut -d, -f1) || _btb=''
    [ -z "$_btb" ] || [ -z "${SWAYSOCK:-}" ] || swaymsg -- "bar $_btb font pango:$(bar_line_font "$(font_spec)")" >/dev/null 2>&1 || :
    pad_again   # the pad's text is the bar's size
    desk_refit_soon   # the bar's height is the text's: the windows the keys placed take their places on the new area
    _bts=$(bar_line_font "$(font_spec)"); _bts=${_bts##* }
    if [ "$_btn" = auto ]; then echo "bar text auto, $_bts now $PANEL_SEP it follows the screen"; else echo "bar text $_btn"; fi
}
bar_tray() {   # bar_tray [on|off] -- the apps' own icons (the tray) at the bar's end; bare, whether they show
    bar_desktop_here
    case ${1:-} in
        '') if [ "$BAR_TRAY" = yes ]; then echo "tray: the apps' icons show at the bar's end (spark-shell bar tray off hides them)"; else echo "tray: off, the bar wears its own glyphs alone (spark-shell bar tray on shows the apps' icons)"; fi ;;
        on|off) bar_tray_step "$1" ;;
        *) refuse_in bar "tray takes on or off" ;;
    esac
}
bar_tray_step() {   # bar_tray_step on|off -> the receipt: the config, the render, a running sway reloaded
    _btw=no; [ "$1" != on ] || _btw=yes
    config_set BAR_TRAY "$_btw" >/dev/null; BAR_TRAY=$_btw; export BAR_TRAY
    theme_load; EXPR=$(render_expr); desktop_look_apply >/dev/null
    if [ "$_btw" = yes ]; then echo "tray on $PANEL_SEP the apps' icons show at the bar's end"; else echo "tray off $PANEL_SEP the apps keep running; their icons stay off the bar"; fi
}
cmd_bar() {   # cmd_bar [on|off] [--terminal|--desktop] | top|bottom | text [auto|N|bigger|smaller] | tray [on|off] | seen [ID...] | status [--once] | due | volume up|down|mute|mic | panel [PAGE] [--list|ACTION [ARG]] | WORDS
    config_load
    case ${1:-} in
        status) shift; bar_status "$@"; return ;;
        due) rem_due_line; return ;;   # tmux's status line, every 15 s
        volume) shift; bar_volume_key "${1:-}"; return ;;
        light) shift; case ${1:-} in up|down) light_set "$1" >/dev/null || :; return ;; *) refuse_in bar "light takes up or down" ;; esac ;;
        panel) shift; cmd_panel "$@"; return ;;   # an alias of spark-shell panel
        top|bottom) bar_where "$1"; return ;;
        text) shift; bar_text "$@"; return ;;
        tray) shift; bar_tray "$@"; return ;;
        seen) shift; notify_seen "$@"; return ;;   # mako's clicks: what was dismissed is looked at
        on|off|'') ;;
        -*) refuse_in bar "$1 is not a bar command: on, off, top, bottom, text, tray, status, volume, panel, or words for what you want" ;;
        *) [ "$OS" != Darwin ] || refuse_in bar "not on macOS, which has its own desktop"; bar_want "$*"; return ;;
    esac
    which=both; case ${PLAYER:-} in rooms) which=rooms ;; windows) which=windows ;; esac
    [ "$which" = windows ] || bar_tmux "${1:-}" "$which"
    [ "$which" = rooms ] || bar_desktop "${1:-}" "$which"
}

