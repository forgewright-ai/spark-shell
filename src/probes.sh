# shellcheck extended-analysis=false
# --- the probes
panel_lower() { printf '%s' "$*" | tr 'A-Z' 'a-z'; }
panel_bars() { bar_bars_plain "$1"; }
bar_bars_plain() {   # bar_bars_plain LEVEL (0-4) -> the four rising bars as text, the unlit ones as a light shade
    i=1; out=''
    for s in $BAR_STEPS; do
        if [ "$i" -gt "$1" ]; then out="$out$BAR_SHADE"; else out="$out$(printf "$s")"; fi
        i=$((i + 1))
    done
    printf '%s' "$out"
}
panel_secret() {   # panel_secret PROMPT -> what was typed, unseen; nothing when there is no terminal
    [ -t 0 ] || return 0
    printf '%s' "$1" > /dev/tty
    stty -echo 2>/dev/null; IFS= read -r _s </dev/tty || _s=''; stty echo 2>/dev/null; echo >/dev/tty
    printf '%s' "$_s"
}

# --- wifi
wifi_if() { bar_wireless | sed -n 1p; }
wifi_iwd_running() {   # iwctl itself can activate iwd and take the radio
    if command -v dbus-send >/dev/null 2>&1; then
        dbus-send --system --print-reply --reply-timeout=2000 --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:net.connman.iwd 2>/dev/null | grep -q 'boolean true'
    else pgrep -x iwd >/dev/null 2>&1; fi
}
wifi_tool() {   # -> nmcli | iwctl | wpa_cli | nothing; asked once a rows read
    [ -z "${WIFI_TOOL_READ:-}" ] || { [ -z "$WIFI_TOOL_NOW" ] || echo "$WIFI_TOOL_NOW"; return 0; }
    _i=$(wifi_if); [ -n "$_i" ] || return 0
    if command -v nmcli >/dev/null 2>&1 && nmcli -t -f RUNNING general 2>/dev/null | grep -qx running && [ "$(nmcli -g GENERAL.NM-MANAGED device show "$_i" 2>/dev/null)" = yes ]; then echo nmcli
    elif command -v iwctl >/dev/null 2>&1 && wifi_iwd_running && iwctl station "$_i" show 2>/dev/null | wifi_strip | grep -q '^State[[:space:]]'; then echo iwctl
    elif command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$_i" status >/dev/null 2>&1; then echo wpa_cli
    fi
}
wifi_owner() {   # -> the network manager here, or nothing
    for _cmd in nmcli iwctl wpa_cli NetworkManager iwd wpa_supplicant dhcpcd connmand wicked; do
        if command -v "$_cmd" >/dev/null 2>&1; then echo "$_cmd"; return; fi
    done
    for _file in "$ROOT"/etc/systemd/network/*.network "$ROOT"/usr/lib/systemd/network/*.network; do
        [ ! -f "$_file" ] || { echo systemd-networkd; return; }
    done
    if grep -Eq '^iface[[:space:]]+[^[:space:]]+[[:space:]]+inet[[:space:]]+(dhcp|static)' "$ROOT/etc/network/interfaces" 2>/dev/null; then echo ifupdown; fi
}
wifi_offer() {
    [ "$OS" != Darwin ] && [ -z "$(wifi_owner)" ] || return 1
    case $DISTRO in
        debian) echo network-manager ;; arch) echo networkmanager ;;
        void|fedora|opensuse) echo NetworkManager ;; *) return 1 ;;
    esac
}
wifi_setup() {
    _package=$(wifi_offer) || { echo 'an existing native network manager keeps control; no replacement is installed'; return 1; }
    if [ "$MODE" = dry ]; then echo "would install $_package and enable its native service"; return; fi
    root_can || { echo 'network setup needs system permission: run spark-shell desktop network setup at a terminal'; return 1; }
    pkg_install "$_package" || { echo 'the native network package could not be installed'; return 1; }
    case $(init_shape) in
        systemd) root_do systemctl enable --now NetworkManager || return 1 ;;
        runit)
            for _service in dbus NetworkManager; do
                [ -d "$ROOT/etc/sv/$_service" ] || { echo "native $_service service is missing"; return 1; }
                root_do mkdir -p "$ROOT/var/service" || return 1
                [ -e "$ROOT/var/service/$_service" ] || root_do ln -s "$ROOT/etc/sv/$_service" "$ROOT/var/service/$_service" || return 1
                root_do sv up "$ROOT/var/service/$_service" || return 1
            done
            if grep -q '^network:' "$ROOT/etc/group" 2>/dev/null && ! in_group network "$(id -un)"; then
                root_do usermod -aG network "$(id -un)" || return 1
                echo 'network group membership takes effect at the next login'
            fi ;;
        *) echo 'installed; enable NetworkManager with the native service manager'; return 1 ;;
    esac
    echo 'the native network manager is installed and running'
}
wifi_level() { _l=$(( ($1 + 100) * 2 )); [ "$_l" -ge 0 ] || _l=0; [ "$_l" -le 100 ] || _l=100; echo $(( (_l + 12) / 25 )); }   # wifi_level DBM -> 0..4
wifi_strip() { sed 's/\x1b\[[0-9;]*m//g; s/^[ >]*//; s/ *$//'; }   # iwctl's colors and marks off
wifi_connected() {   # -> the network in use, or nothing
    case $(wifi_tool) in
        nmcli) nmcli -t -e yes -f IN-USE,SSID dev wifi list 2>/dev/null | awk -F: '$1 == "*" { sub(/^[^:]*:/, ""); gsub(/\\:/, ":"); print; exit }' ;;
        iwctl) iwctl station "$(wifi_if)" show 2>/dev/null | wifi_strip | awk '$1 == "Connected" && $2 == "network" { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }' ;;
        wpa_cli) wpa_cli -i "$(wifi_if)" status 2>/dev/null | sed -n 's/^ssid=//p' | sed -n 1p ;;
    esac | scrub_text   # a network's name is anyone's words: no escape reaches a screen
}
wifi_known() {   # -> ID<tab>NAME per saved network (ID is the tool's handle: a name for nmcli and iwctl, a number for wpa_cli)
    case $(wifi_tool) in
        nmcli) nmcli -t -e yes -f NAME,TYPE con show 2>/dev/null | awk -F: -v OFS=: '$NF ~ /wireless/ { $NF = ""; sub(/:$/, ""); gsub(/\\:/, ":"); print $0 "\t" $0 }' ;;   # OFS=:: a field set rebuilds the line with it (a space would end every name in one)
        iwctl) iwctl known-networks list 2>/dev/null | wifi_strip | awk 'NR > 4 && NF >= 3 { n = ""; for (i = 1; i <= NF - 3; i++) n = n (n == "" ? "" : " ") $i; if (n != "") print n "\t" n }' ;;
        wpa_cli) wpa_cli -i "$(wifi_if)" list_networks 2>/dev/null | awk -F '\t' 'NR > 1 && $2 != "" { print $1 "\t" $2 }' ;;
    esac | scrub_text
}
wifi_scan() {   # -> NAME<tab>LEVEL<tab>SECURED per network around, strongest first; kept for a minute, a thin scan for ten seconds
    panel_cache wifi.scan 60 wifi_scan_now | tee "$TMP/wifi.last"
    [ "$(grep -c '' "$TMP/wifi.last")" -ge 2 ] || panel_age wifi.scan 50
}
wifi_scan_now() {
    case $(wifi_tool) in
        nmcli) nmcli -t -e yes -f SIGNAL,SECURITY,SSID dev wifi list --rescan auto 2>/dev/null \
            | awk -F: -v OFS=: '{ sig = $1; sec = ($2 == "" || $2 == "--") ? 0 : 1; $1 = ""; $2 = ""; sub(/^::/, ""); gsub(/\\:/, ":"); if ($0 != "") print $0 "\t" int((sig + 12) / 25) "\t" sec }' ;;   # OFS=:: the two fields cleared leave::NAME, never two spaces before it
        iwctl) iwctl station "$(wifi_if)" scan >/dev/null 2>&1; sleep 2
            iwctl station "$(wifi_if)" get-networks 2>/dev/null | wifi_strip | awk 'NR > 4 && NF >= 3 { s = $NF; l = gsub(/\*/, "*", s); sec = ($(NF - 1) == "open") ? 0 : 1; n = ""; for (i = 1; i <= NF - 2; i++) n = n (n == "" ? "" : " ") $i; if (n != "") print n "\t" l "\t" sec }' ;;
        wpa_cli) wpa_cli -i "$(wifi_if)" scan >/dev/null 2>&1; sleep 2
            wpa_cli -i "$(wifi_if)" scan_results 2>/dev/null | awk -F '\t' 'NR > 1 && $5 != "" { sec = ($4 ~ /WPA|WEP|PSK|SAE/) ? 1 : 0; print $5 "\t" $3 "\t" sec }' \
            | while IFS="$TAB" read -r n dbm sec; do printf '%s\t%s\t%s\n' "$n" "$(wifi_level "$dbm")" "$sec"; done ;;
    esac | awk -F '\t' '!seen[$1]++ || $2 > best[$1] { best[$1] = $2; sec[$1] = $3 } END { for (n in best) print n "\t" best[n] "\t" sec[n] }' | scrub_text | sort -t "$TAB" -k2,2nr -k1,1
}
wifi_known_id() { wifi_known | awk -F '\t' -v n="$(panel_lower "$1")" 'tolower($2) == n && !done { print $1; done = 1 }'; }   # wifi_known_id NAME -> its handle, or nothing
wifi_said() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/^[ >]*//; s/^Password[^:]*: *//; s/^Passphrase[^:]*: *//; s/ *$//' | grep -v -e '^$' -e '^Type the network passphrase' | tail -1 | scrub_text; }   # a tool's answer -> its last line that says something: no escapes, no prompt of its own
# a password reaches the tool on stdin, never as an argument: a command line is anyone's to
# read in /proc. nmcli takes it at its --ask prompt, iwctl at its agent's, wpa_cli on stdin
wifi_connect() {   # wifi_connect NAME [PASSWORD] [hidden] -> one line
    _i=$(wifi_if); _id=$(wifi_known_id "$1"); _r=''; _hidden=${3:-}
    _join=connect; [ "$_hidden" != hidden ] || _join=connect-hidden
    [ "$(printf '%s' "${2:-}" | tr -d '\001-\037\177')" = "${2:-}" ] || { echo "a password holds no control character, so not connected"; return 1; }   # a new line would be a second command to wpa_cli
    case $(wifi_tool) in
        nmcli) if [ -n "$_id" ]; then _o=$(nmcli con up id "$_id" 2>&1 </dev/null) || { echo "could not connect to $1: $(printf '%s\n' "$_o" | wifi_said)"; return 1; }
               elif [ -n "${2:-}" ]; then _o=$(printf '%s\n' "$2" | nmcli --ask dev wifi connect "$1" ifname "$_i" hidden "$(if [ "$_hidden" = hidden ]; then echo yes; else echo no; fi)" 2>&1) || { echo "could not connect to $1: $(printf '%s\n' "$_o" | wifi_said)"; return 1; }
               else _o=$(nmcli dev wifi connect "$1" ifname "$_i" hidden "$(if [ "$_hidden" = hidden ]; then echo yes; else echo no; fi)" 2>&1 </dev/null) || { echo "could not connect to $1: $(printf '%s\n' "$_o" | wifi_said)"; return 1; }; fi ;;
        iwctl) if [ -n "${2:-}" ]; then _o=$(printf '%s\n' "$2" | python3 "$REPO/lib/wifi_connect.py" "$_i" "$1" ${_hidden:+--hidden} 2>&1) || { echo "could not connect to $1: $(printf '%s\n' "$_o" | wifi_said)"; return 1; }
               else _o=$(iwctl station "$_i" "$_join" "$1" 2>&1 </dev/null) || { echo "could not connect to $1: $(printf '%s\n' "$_o" | wifi_said)"; return 1; }; fi ;;
        wpa_cli) if [ -z "$_id" ]; then
                _psk=''
                if [ -n "${2:-}" ]; then
                    if [ "${#2}" = 64 ] && case $2 in *[!a-fA-F0-9]*) false ;; *) true ;; esac; then _psk=$2
                    else _psk=$(printf '%s\n' "$2" | wpa_passphrase "$1" 2>/dev/null | sed -n 's/^[[:space:]]*psk=\([a-f0-9]\{64\}\)$/\1/p'); fi
                    [ -n "$_psk" ] || { echo 'the native WPA tool could not derive a key (use an 8 to 63 character password)'; return 1; }
                fi
                _id=$(wpa_cli -i "$_i" add_network 2>/dev/null | tail -1)
                case $_id in ''|*[!0-9]*) echo "could not connect to $1: wpa_cli did not add it"; return 1 ;; esac
                _ssid=$(printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n')
                if ! wpa_cli -i "$_i" set_network "$_id" ssid "$_ssid" 2>/dev/null | grep -q '^OK$'; then wpa_cli -i "$_i" remove_network "$_id" >/dev/null 2>&1; echo 'the native tool refused the network name'; return 1; fi
                if [ -n "$_psk" ]; then
                    if ! printf 'set_network %s psk %s\n' "$_id" "$_psk" | env -u HOME wpa_cli -i "$_i" 2>/dev/null | grep -q 'OK'; then wpa_cli -i "$_i" remove_network "$_id" >/dev/null 2>&1; echo 'the native tool refused the network key'; return 1; fi
                    _psk=''
                else wpa_cli -i "$_i" set_network "$_id" key_mgmt NONE >/dev/null 2>&1; fi
                wpa_cli -i "$_i" enable_network "$_id" >/dev/null 2>&1
                wpa_cli -i "$_i" save_config 2>/dev/null | grep -q OK || _r="(kept until the next boot: wpa_supplicant.conf is not writable from here)"
            fi
            if [ "$_hidden" = hidden ]; then
                wpa_cli -i "$_i" set_network "$_id" scan_ssid 1 2>/dev/null | grep -q OK || { echo "could not mark $1 as hidden"; return 1; }
                wpa_cli -i "$_i" save_config >/dev/null 2>&1 || :
            fi
            wpa_cli -i "$_i" select_network "$_id" >/dev/null 2>&1
            wpa_cli -i "$_i" enable_network all >/dev/null 2>&1   # select_network puts the other saved networks aside
            wpa_cli -i "$_i" reconnect >/dev/null 2>&1
            _t=0; while [ "$_t" -lt 15 ]; do [ "$(wifi_connected)" = "$1" ] && break; sleep 1; _t=$((_t + 1)); done
            [ "$(wifi_connected)" = "$1" ] || { echo "could not connect to $1 (wrong password, or out of reach)"; return 1; } ;;
        *) echo "no tool answers for wifi (nmcli, iwctl or wpa_cli)"; return 1 ;;
    esac
    panel_forget wifi.scan
    echo "connected to $1${_r:+ $_r}"
}
wifi_disconnect() {   # -> one line
    _i=$(wifi_if); _c=$(wifi_connected)
    case $(wifi_tool) in
        nmcli) nmcli dev disconnect "$_i" >/dev/null 2>&1 ;;
        iwctl) iwctl station "$_i" disconnect >/dev/null 2>&1 ;;
        wpa_cli) wpa_cli -i "$_i" disconnect >/dev/null 2>&1 ;;
        *) echo "no tool answers for wifi (nmcli, iwctl or wpa_cli)"; return 1 ;;
    esac || { echo "could not disconnect"; return 1; }
    echo "disconnected${_c:+ from $_c}"
}
wifi_forget() {   # wifi_forget NAME -> one line
    _i=$(wifi_if); _id=$(wifi_known_id "$1"); [ -n "$_id" ] || { echo "$1 is not a saved network"; return 1; }
    case $(wifi_tool) in
        nmcli) nmcli con delete id "$_id" >/dev/null 2>&1 ;;
        iwctl) iwctl known-networks "$_id" forget >/dev/null 2>&1 ;;
        wpa_cli) wpa_cli -i "$_i" remove_network "$_id" >/dev/null 2>&1 && wpa_cli -i "$_i" save_config >/dev/null 2>&1 ;;
    esac || { echo "could not forget $1"; return 1; }
    echo "forgot $1"
}

# --- the network settings
network_action() (   # ACTION "DEVICE key=value..." [check]
    _action=$1; _value=$2; _check=${3:-}
    set -f
    # shellcheck disable=SC2086   # validated tokens; never evaluated as shell
    set -- $_value
    [ "$#" -ge 1 ] || { echo 'choose a native network interface'; return 1; }
    _device=$1; shift
    case $_action in
        address) [ "$#" = 2 ] && case $1:$2 in address=*:gateway=*) true ;; *) false ;; esac || { echo 'address takes a prefix and gateway'; return 1; }; set -- "${1#address=}" "${2#gateway=}" ;;
        dns) [ "$#" = 1 ] && case $1 in servers=*) true ;; *) false ;; esac || { echo 'dns takes servers'; return 1; }; set -- "${1#servers=}" ;;
        auto|restore) [ "$#" = 0 ] || return 1 ;;
        *) return 1 ;;
    esac
    if [ "$_check" = check ]; then python3 "$REPO/lib/network.py" --state "$STATE_DIR/network" --check "$_action" "$_device" "$@"; return; fi
    if [ "$MODE" = dry ]; then echo "would change native network settings for $_device"; return; fi
    python3 "$REPO/lib/network.py" --state "$STATE_DIR/network" "$_action" "$_device" "$@" > "$TMP/network.result" 2> "$TMP/network.error" || { cat "$TMP/network.error"; return 1; }
    jq -r .receipt "$TMP/network.result"
    jq -r '.undo // empty' "$TMP/network.result" > "$TMP/network.undo"
)
provide_network_rows() {   # SECTION DEVICE -> one connection's settings, JSON
    _ns=$1; _ni=$2
    case $_ns in lan) _interfaces=$(bar_wired) ;; wifi) _interfaces=$(bar_wireless) ;; *) return 1 ;; esac
    printf '%s\n' "$_interfaces" | grep -qxF -- "$_ni" || return 1
    if python3 "$REPO/lib/network.py" --state "$STATE_DIR/network" show "$_ni" > "$TMP/network.show" 2> "$TMP/network.error"; then
        jq -c --arg s "$_ns" --arg i "$_ni" '
            .settings as $v | {title: ("network " + $i), state: "native connection settings", rows: [
                {id: "method", text: ("IPv4 " + $v["ipv4.method"])},
                {id: "address", text: ("address " + $v["ipv4.addresses"])},
                {id: "gateway", text: ("gateway " + $v["ipv4.gateway"])},
                {id: "dns", text: ("DNS " + (if $v["ipv4.ignore-auto-dns"] == "yes" then $v["ipv4.dns"] else "automatic " + $v["ipv4.dns"] end))},
                {id: "set-address", text: "set a fixed IPv4 address", tool: {name: ($s + "_address"), arguments: {device: $i, address: "", gateway: "none"}, ask: ["address", "gateway"]}},
                {id: "automatic", text: "use automatic IPv4 address", tool: {name: ($s + "_auto"), arguments: {device: $i}}},
                {id: "set-dns", text: "set DNS servers", tool: {name: ($s + "_dns"), arguments: {device: $i, servers: "auto"}, ask: ["servers"]}}]} | .short = [.rows[].id]' "$TMP/network.show"
    else jq -cn --arg i "$_ni" --arg text "$(cat "$TMP/network.error" | scrub_text)" '{title: ("network " + $i), state: $text, rows: [], short: []}'; fi
}
desk_network() {
    [ "$OS" != Darwin ] || refuse 'macOS owns its network settings'
    case ${1:-} in
        setup)
            if [ "$MODE" != dry ] && [ "$YES" != 1 ]; then step_yes "install the native network manager" || refuse 'network setup unchanged (use --yes to confirm)'; fi
            wifi_setup; return ;;
        show) [ "$#" = 2 ] || refuse 'network show takes an interface'; python3 "$REPO/lib/network.py" --state "$STATE_DIR/network" show "$2"; return ;;
        address) [ "$#" = 4 ] || refuse 'network address takes an interface, address with prefix and gateway (or none)'; _nv="$2 address=$3 gateway=$4" ;;
        dns) [ "$#" = 3 ] || refuse 'network dns takes an interface and servers (comma separated, or auto)'; _nv="$2 servers=$3" ;;
        auto|restore) [ "$#" = 2 ] || refuse "network $1 takes one value"; _nv=$2 ;;
        *) refuse 'network takes setup, show, address, auto, dns or restore' ;;
    esac
    network_action "$1" "$_nv" check || return 1
    if [ "$MODE" != dry ] && [ "$YES" != 1 ]; then step_yes "change native network settings (the connection may drop)" || refuse 'network settings unchanged (use --yes to confirm)'; fi
    panel_group_begin; panel_step lan "$1" "$_nv"; _rc=$?; panel_group_end; return "$_rc"
}

# --- bluetooth
bt_running() { read_once bt.running bt_running_now; }   # bluez answers on the system bus
bt_running_now() {
    if command -v dbus-send >/dev/null 2>&1; then
        dbus-send --system --print-reply --reply-timeout=2000 --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:org.bluez 2>/dev/null | grep -q 'boolean true'
    else pgrep -x bluetoothd >/dev/null 2>&1; fi
}
bt_check() {
    if ! command -v bluetoothctl >/dev/null 2>&1; then chk bluetooth warn "bluez is not installed" "spark-shell on desktop"
    elif ! bt_running; then chk bluetooth warn "bluetoothd is not running" "spark-shell on desktop"
    elif ! python3 -c 'import dbus; from gi.repository import GLib' >/dev/null 2>&1; then chk bluetooth warn "pairing needs the native Python D-Bus bindings" "spark-shell on desktop"
    else chk bluetooth ok "bluetoothd runs; native pairing questions are available"; fi
}
bt_apply() {   # the distribution's bluetooth service enabled and started
    command -v bluetoothctl >/dev/null 2>&1 || { skip bluetooth "bluez is not installed yet"; return; }
    if [ "$(init_shape)" = systemd ]; then
        if systemctl is-enabled bluetooth >/dev/null 2>&1 && systemctl is-active bluetooth >/dev/null 2>&1; then ok bluetooth "the native service is enabled and running"; return; fi
        need bluetooth "enable and start the native bluetooth service (sudo)" && seat_root on bluetooth || return 0
        root_do systemctl enable --now bluetooth || { row todo bluetooth "the native service could not start"; acting=0; return; }
    elif [ "$(init_shape)" = runit ]; then
        for _svc in dbus bluetoothd; do
            [ -d "$ROOT/etc/sv/$_svc" ] || { row todo bluetooth "the native $_svc service is missing"; continue; }
            if [ ! -e "$ROOT/var/service/$_svc" ]; then
                need bluetooth "enable the native $_svc service (sudo)" && seat_root on bluetooth || continue
                root_do mkdir -p "$ROOT/var/service" && root_do ln -s "$ROOT/etc/sv/$_svc" "$ROOT/var/service/$_svc" || return 1
            fi
            [ "$MODE" = dry ] || root_do sv up "$ROOT/var/service/$_svc" || return 1
        done
        if grep -q '^bluetooth:' "$ROOT/etc/group" 2>/dev/null && ! in_group bluetooth "$(id -un)"; then
            need bluetooth "add $(id -un) to the native bluetooth group (sudo; next login)" && seat_root on bluetooth || return 0
            root_do usermod -aG bluetooth "$(id -un)" || return 1
        fi
    else skip bluetooth "enable bluetoothd with the system service manager"; return; fi
    ok bluetooth "the native services are enabled; shared services stay when the desktop is off"
}

bt_powered() { read_once bt.powered bt_powered_now; }
bt_powered_now() { bar_timeout bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; }
bt_connected() { read_once bt.connected bar_timeout bluetoothctl devices Connected 2>/dev/null; }   # -> bluetoothctl's lines of the devices connected now
bt_list() { read_once bt.list panel_cache bt.list 30 bt_list_now; }   # -> MAC<tab>NAME<tab>PAIRED<tab>CONNECTED per device bluez knows; kept 30 s
bt_list_now() {
    _p=$(bar_timeout bluetoothctl devices Paired 2>/dev/null | awk '$1 == "Device" {print $2}')
    _c=$(bt_connected | awk '$1 == "Device" {print $2}')
    bar_timeout bluetoothctl devices 2>/dev/null | scrub_text | awk '$1 == "Device" { mac = $2; $1 = ""; $2 = ""; sub(/^ +/, ""); print mac "\t" $0 }' | while IFS="$TAB" read -r mac name; do
        p=0; c=0
        printf '%s\n' "$_p" | grep -qx "$mac" && p=1
        printf '%s\n' "$_c" | grep -qx "$mac" && c=1
        printf '%s\t%s\t%s\t%s\n' "$mac" "$name" "$p" "$c"
    done
}
bt_mac() { bt_list | awk -F '\t' -v n="$(panel_lower "$1")" 'tolower($2) == n && !done { print $1; done = 1 }'; }   # bt_mac NAME -> its address, or nothing (the whole list read: no broken pipe)
bt_act() {   # bt_act connect|disconnect|pair|remove NAME | scan | power on|off -> one line
    panel_forget bt.list
    bt_running || { echo "bluetoothd is not running (spark-shell on desktop)"; return 1; }
    case $1 in
        connect|disconnect|pair|remove)
            _m=$(bt_mac "$2"); [ -n "$_m" ] || { echo "no device named $2"; return 1; }
            case $1 in
                connect) bar_timeout bluetoothctl connect "$_m" 2>&1 | grep -q 'successful' && echo "connected $2" || { echo "could not connect $2 (is it on, and near?)"; return 1; } ;;
                disconnect) bar_timeout bluetoothctl disconnect "$_m" 2>&1 | grep -q 'Successful' && echo "disconnected $2" || { echo "could not disconnect $2"; return 1; } ;;
                remove) bar_timeout bluetoothctl remove "$_m" 2>&1 | grep -q 'removed' && echo "removed $2" || { echo "could not remove $2"; return 1; } ;;
                pair) if [ -n "${BT_BRIDGE:-}" ]; then python3 "$REPO/lib/bt_agent.py" "$_m" --bridge "$BT_BRIDGE" || return 1
                      else python3 "$REPO/lib/bt_agent.py" "$_m" || return 1; fi
                      bar_timeout bluetoothctl trust "$_m" >/dev/null 2>&1
                      bar_timeout bluetoothctl connect "$_m" >/dev/null 2>&1 && echo "paired and connected $2" || echo "paired $2" ;;
            esac ;;
        scan) timeout 10 bluetoothctl --timeout 8 scan on >/dev/null 2>&1 || :
              _n=$(bt_list | awk -F '\t' '$3 == 0 {print $2}' | paste -sd, - | sed 's/,/, /g')
              if [ -n "$_n" ]; then echo "new: $_n (Enter on one pairs it)"; else echo "nothing new near (put the device in pairing mode)"; fi ;;
        power) bar_timeout bluetoothctl power "$2" >/dev/null 2>&1 && echo "bluetooth $2" || { echo "could not turn bluetooth $2"; return 1; } ;;
        *) echo "$1 is not something bt does"; return 1 ;;
    esac
}

# --- sound
snd_devices() { read_once "snd.devices.$1" snd_devices_now "$1"; }   # snd_devices out|mic -> NAME<tab>DEFAULT(1/0) per device
snd_devices_now() {
    case $SND in
        wpctl) _s=Sinks; [ "$1" = out ] || _s=Sources; wp_rows "$_s" | awk -F '\t' '{print $3 "\t" $1}' ;;
        pactl) _k=sinks; _d=$(pactl get-default-sink 2>/dev/null); [ "$1" = out ] || { _k=sources; _d=$(pactl get-default-source 2>/dev/null); }
            pactl list short "$_k" 2>/dev/null | cut -f2 | while IFS= read -r s; do
                case $s in *.monitor) continue ;; esac
                n=$(pa_desc "$_k" "$s"); d=0; [ "$s" != "$_d" ] || d=1; printf '%s\t%s\n' "${n:-$s}" "$d"
            done ;;
        alsa) if [ "$1" = out ]; then _k=p; _d=$(al_out); else _k=c; _d=$(al_mic); fi
            _b=$(al_bt_routed "$_k"); [ -z "$_b" ] || _d=''   # a Bluetooth way picked: no card is in use
            for c in $(al_with "$_k"); do d=0; [ "$c" != "$_d" ] || d=1; printf '%s\t%s\n' "$(al_name "$c")" "$d"; done
            al_bt "$_k" | while IFS="$TAB" read -r n v; do d=0; [ "$v" != "$_b" ] || d=1; printf '%s\t%s\n' "$n" "$d"; done ;;
    esac
}
snd_use() {   # snd_use out|mic NAME -> one line; on plain ALSA the output's card holds for programs started from now
    _n=$(panel_lower "$2")
    case $SND in
        wpctl) _s=Sinks; [ "$1" = out ] || _s=Sources
            _id=$(wp_rows "$_s" | awk -F '\t' -v n="$_n" 'tolower($3) == n && !done {print $2; done = 1}'); [ -n "$_id" ] || { echo "no $1 named $2"; return 1; }
            wpctl set-default "$_id" >/dev/null 2>&1 && echo "$1 $2" || { echo "could not switch $1 to $2"; return 1; } ;;
        pactl) _k=sinks; _v=set-default-sink; [ "$1" = out ] || { _k=sources; _v=set-default-source; }
            _id=$(pactl list short "$_k" 2>/dev/null | cut -f2 | while IFS= read -r s; do d=$(pa_desc "$_k" "$s"); [ "$(panel_lower "${d:-$s}")" != "$_n" ] || { echo "$s"; break; }; done)
            [ -n "$_id" ] || { echo "no $1 named $2"; return 1; }
            pactl "$_v" "$_id" >/dev/null 2>&1 && echo "$1 $2" || { echo "could not switch $1 to $2"; return 1; } ;;
        alsa) _k=p; [ "$1" = out ] || _k=c
            _v=$(al_bt "$_k" | awk -F '\t' -v n="$_n" 'tolower($1) == n && !d {print $2; d = 1}')
            if [ -n "$_v" ]; then   # a Bluetooth device: this way through bluez-alsa, the other way as it was
                _c=$(al_default); [ -n "$_c" ] || _c=$(al_first p)
                if [ "$_k" = p ]; then _r=$(al_write "$_c" "$_v" "$(al_bt_routed c)"); else _r=$(al_write "$_c" "$(al_bt_routed p)" "$_v"); fi || { echo "$_r"; return 1; }
                echo "$1 $2 for programs started from now"; return 0
            fi
            if [ "$_k" = c ]; then   # on plain ALSA the mic follows the output's card; a Bluetooth mic picked goes back to it
                [ -n "$(al_bt_routed c)" ] || { echo "on plain ALSA the mic follows the output's card"; return 0; }
                _r=$(al_write "$(al_default)" "$(al_bt_routed p)" '') || { echo "$_r"; return 1; }
                echo "mic back on the output's card for programs started from now"; return 0
            fi
            _c=''; for c in $(al_with p); do [ "$(panel_lower "$(al_name "$c")")" != "$_n" ] || { _c=$c; break; }; done
            [ -n "$_c" ] || { echo "no output named $2"; return 1; }
            _r=$(al_write "$_c" '' "$(al_bt_routed c)") || { echo "$_r"; return 1; }
            echo "out $2 for programs started from now" ;;
        *) echo "no audio system answers"; return 1 ;;
    esac
}

