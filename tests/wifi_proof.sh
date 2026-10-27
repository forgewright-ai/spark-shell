#!/bin/sh
# tests/wifi_proof.sh -- a new network's password on simulated radios (#62).
# Two mac80211_hwsim radios: an access point on one (hostapd, WPA2, in a
# network namespace of its own, with a DHCP server), and spark-shell's own
# `panel wifi connect` on the other, through each tool it speaks: wpa_cli,
# nmcli and iwctl. Each must join with a password that has spaces and
# quotes in it, and strace holds every program spark-shell starts to a
# command line without the password. spark-shell v0.100, which passed it as
# an argument, runs first through the same check: the check must catch it.
# For a throwaway machine (CI's VM), as root: it loads a kernel module, and
# starts and stops network services.
set -eu
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SH=$REPO/spark-shell
[ "${SPARK_SHELL_DISPOSABLE_VM:-}" = 1 ] && systemd-detect-virt --vm >/dev/null 2>&1 || { echo 'wifi_proof: only an explicitly disposable virtual machine'; exit 1; }
# Never choose a physical radio or stop services on a machine with one.
for radio in /sys/class/net/*/phy80211; do
    [ ! -e "$radio" ] || { echo 'wifi_proof: a radio already exists; refusing'; exit 1; }
done
umask 077
W=$(mktemp -d)
owned_services=''
for service in NetworkManager iwd wpa_supplicant; do
    systemctl is-active "$service" >/dev/null 2>&1 && owned_services="$owned_services $service" || :
done
cleanup() {
    for f in "$W/dnsmasq.pid" "$W/hostapd.pid" "$W/wpa.pid"; do
        [ ! -r "$f" ] || kill "$(cat "$f")" 2>/dev/null || :
    done
    systemctl stop NetworkManager iwd wpa_supplicant >/dev/null 2>&1 || :
    ip netns del spark-wifi-proof >/dev/null 2>&1 || :
    systemctl unmask --runtime iwd >/dev/null 2>&1 || :
    modprobe -r mac80211_hwsim >/dev/null 2>&1 || :
    for service in $owned_services; do systemctl start "$service" >/dev/null 2>&1 || :; done
    if [ "${SPARK_SHELL_PROOF_KEEP:-}" = 1 ]; then echo "wifi_proof: private logs kept in $W"; else rm -rf "$W"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
SSID='spark lab'
MARK=Zq7xW                                  # the password's own letters, which strace prints as they are
fails=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/      /'; fails=$((fails + 1)); }
for t in iw ip hostapd dnsmasq wpa_supplicant wpa_cli nmcli iwctl strace jq git; do
    command -v "$t" >/dev/null 2>&1 || { echo "wifi_proof: $t is missing"; exit 1; }
done
[ "$(id -u)" -eq 0 ] || { echo "wifi_proof: run as root"; exit 1; }

# the password: never on a command line here either, so it is read from a file into the environment
printf '%s\n' "$MARK \"x\" it's ok" > "$W/pass"
PANEL_PASS=$(cat "$W/pass"); export PANEL_PASS

# a home of its own: the config and the state go there, never root's own
export HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" XDG_STATE_HOME="$W/home/.local/state"
mkdir -p "$XDG_CONFIG_HOME/spark-shell"
printf 'DESKTOP=sway\n' > "$XDG_CONFIG_HOME/spark-shell/config"

# the radios: nothing else may take them
systemctl stop NetworkManager iwd wpa_supplicant >/dev/null 2>&1 || :
systemctl mask --runtime iwd >/dev/null
modprobe mac80211_hwsim radios=2
radios() { for d in /sys/class/net/*/phy80211; do [ -e "$d" ] || continue; d=${d%/phy80211}; printf '%s\n' "${d##*/}"; done; }
n=0; while [ "$(radios | wc -l)" -lt 2 ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
AP=$(radios | sed -n 1p); STA=$(radios | sed -n 2p)
[ -n "$AP" ] && [ -n "$STA" ] || { echo "wifi_proof: two simulated radios, found: $(radios | paste -sd ' ' -)"; exit 1; }
ip netns add spark-wifi-proof
iw phy "$(cat "/sys/class/net/$AP/phy80211/name")" set netns name spark-wifi-proof
ip netns exec spark-wifi-proof ip link set "$AP" up
ip netns exec spark-wifi-proof ip addr add 192.0.2.1/24 dev "$AP"
cat > "$W/hostapd.conf" <<EOF
interface=$AP
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=$PANEL_PASS
EOF
ip netns exec spark-wifi-proof hostapd -B -P "$W/hostapd.pid" "$W/hostapd.conf" >/dev/null
ip netns exec spark-wifi-proof dnsmasq --interface="$AP" --bind-interfaces --dhcp-range=192.0.2.10,192.0.2.50,1h --no-resolv --no-hosts --leasefile-ro --pid-file="$W/dnsmasq.pid"
echo "wifi_proof: the access point on $AP (namespace spark-wifi-proof), the station $STA"

# spark-shell's connect under strace: every program it starts, with its whole command line
connect() {   # connect SPARK_SHELL TRACE -> what it said; its status
    timeout 90 strace -f -qq -e trace=execve -s 4096 -o "$2" sh "$1" bar panel wifi connect "$SSID" 2>&1
}
leaked() { grep -F "$MARK" "$1" | head -3; }   # a command line that holds the password (strace prints the environment as a count, never its words)

# 1. wpa_supplicant and wpa_cli, the way the box runs them; v0.100 first, as the check's own test
printf 'ctrl_interface=/run/wpa_supplicant\nupdate_config=1\n' > "$W/wpa.conf"
wpa_supplicant -B -i "$STA" -c "$W/wpa.conf" -P "$W/wpa.pid" >/dev/null
wpa_cli -i "$STA" scan >/dev/null
n=0; until wpa_cli -i "$STA" scan_results | grep -q "$SSID" || [ "$n" -ge 50 ]; do sleep 0.2; n=$((n + 1)); done
mkdir -p "$W/old"
if [ -n "${SPARK_SHELL_WIFI_BASELINE:-}" ]; then cp -R "$SPARK_SHELL_WIFI_BASELINE/." "$W/old/"; else git -c safe.directory="$REPO" -C "$REPO" archive v0.100 | tar -x -C "$W/old"; fi   # the checkout is the runner's, and git refuses another owner's tree to root without this
out=$(connect "$W/old/spark-shell" "$W/trace.old") || :
if [ -n "$(leaked "$W/trace.old")" ]; then ok "the check sees a leak: v0.100 passed the password to wpa_cli as an argument"
else bad "the check saw nothing in v0.100's connect, so it proves nothing" "$out"; fi
systemctl stop iwd >/dev/null 2>&1 || :
wpa_cli -i "$STA" remove_network all >/dev/null; wpa_cli -i "$STA" save_config >/dev/null 2>&1 || :
wpa_cli -i "$STA" disconnect >/dev/null; rm -rf "$XDG_STATE_HOME/spark-shell/panel"
rc=0; out=$(connect "$SH" "$W/trace.wpa") || rc=$?
st=$(wpa_cli -i "$STA" status 2>/dev/null) || :
if [ "$rc" -eq 0 ] && printf '%s\n' "$st" | grep -qx 'wpa_state=COMPLETED' && printf '%s\n' "$st" | grep -qx "ssid=$SSID"; then ok "wpa_cli: joined $SSID ($out)"
else bad "wpa_cli: did not join" "$out
$st"; fi
l=$(leaked "$W/trace.wpa"); if [ -z "$l" ]; then ok "wpa_cli: no command line held the password"; else bad "wpa_cli: a command line held the password" "$l"; fi
grep -q 'wpa_cli' "$W/trace.wpa" && ok "wpa_cli: the trace saw wpa_cli run" || bad "wpa_cli: the trace never saw wpa_cli"
wpa_cli -i "$STA" terminate >/dev/null 2>&1 || :
sleep 1

# 2. NetworkManager and nmcli (its native backend may itself be iwd)
systemctl unmask --runtime iwd >/dev/null
rm -rf "$XDG_STATE_HOME/spark-shell/panel"
systemctl start wpa_supplicant NetworkManager
n=0; until nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -q "$(radios | sed -n 1p):disconnected$" || [ "$n" -ge 60 ]; do sleep 0.5; n=$((n + 1)); done
STA=$(radios | sed -n 1p)
nmcli con delete id "$SSID" >/dev/null 2>&1 || :
nmcli dev disconnect "$STA" >/dev/null 2>&1 || :
nmcli dev wifi rescan ifname "$STA" >/dev/null 2>&1 || :
n=0; until nmcli -t -f SSID dev wifi list ifname "$STA" 2>/dev/null | grep -qx "$SSID" || [ "$n" -ge 30 ]; do sleep 0.5; n=$((n + 1)); done
rc=0; out=$(connect "$SH" "$W/trace.nm") || rc=$?
if [ "$rc" -eq 0 ] && nmcli -t -f GENERAL.STATE dev show "$STA" 2>/dev/null | grep -q '^GENERAL.STATE:100'; then ok "nmcli: joined $SSID ($out)"
else bad "nmcli: did not join" "$out
$(nmcli -t dev 2>&1)"; fi
l=$(leaked "$W/trace.nm"); if [ -z "$l" ]; then ok "nmcli: no command line held the password"; else bad "nmcli: a command line held the password" "$l"; fi
grep -q -- '"--ask"' "$W/trace.nm" && ok "nmcli: --ask, the password at its own prompt" || bad "nmcli: the trace never saw nmcli --ask"
# Native profile fields and the live address, including exact guarded undo.
python3 - "$REPO" "$W" "$STA" <<'PYTHON'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("network", pathlib.Path(sys.argv[1]) / "lib/network.py")
network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network)
state = pathlib.Path(sys.argv[2]) / "network-undo"
dev = sys.argv[3]
before = network.run(state, "show", dev, [])
address = network.run(state, "address", dev, ["192.0.2.8/24", "192.0.2.1"])
import time
for _ in range(50):
    live = network.native("-g", "IP4.ADDRESS", "device", "show", dev)
    if live == "192.0.2.8/24": break
    time.sleep(0.1)
assert live == "192.0.2.8/24", live
dns = network.run(state, "dns", dev, ["192.0.2.53"])
for _ in range(50):
    live = network.native("-g", "IP4.DNS", "device", "show", dev)
    if live == "192.0.2.53": break
    time.sleep(0.1)
assert live == "192.0.2.53", live
network.run(state, "restore", dns["undo"], [])
network.run(state, "restore", address["undo"], [])
assert network.run(state, "show", dev, []) == before
print("ok    nmcli: native IPv4 address, DNS and exact profile undo")
PYTHON
nmcli con delete id "$SSID" >/dev/null 2>&1 || :
systemctl stop NetworkManager wpa_supplicant iwd || :
sleep 1

# 3. iwd and iwctl (iwd makes its own interface for the radio: found again)
rm -rf "$XDG_STATE_HOME/spark-shell/panel"
systemctl unmask --runtime iwd >/dev/null
systemctl start iwd
n=0
while :; do
    IW=$(radios | sed -n 1p)
    if [ -n "$IW" ] && iwctl station "$IW" show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q '^[[:space:]]*State[[:space:]]'; then break; fi
    [ "$n" -lt 60 ] || { bad 'iwd: no station became ready'; break; }
    sleep 0.5; n=$((n + 1))
done
iwctl known-networks "$SSID" forget >/dev/null 2>&1 || :
iwctl station "$IW" disconnect >/dev/null 2>&1 || :
iwctl station "$IW" scan >/dev/null 2>&1 || :
n=0; until iwctl station "$IW" get-networks 2>/dev/null | grep -q "$SSID" || [ "$n" -ge 50 ]; do sleep 0.2; n=$((n + 1)); done
iwctl station "$IW" get-networks > "$W/iwd-networks" 2>&1 || :
sh "$SH" panel wifi --list > "$W/iwd-panel" 2>&1 || :
rc=0; out=$(connect "$SH" "$W/trace.iw") || rc=$?
if [ "$rc" -eq 0 ] && iwctl station "$IW" show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Connected network *$SSID"; then ok "iwctl: joined $SSID ($out)"
else bad "iwctl: did not join" "$out
$(iwctl station "$IW" show 2>&1)"; fi
l=$(leaked "$W/trace.iw"); if [ -z "$l" ]; then ok "iwctl: no command line held the password"; else bad "iwctl: a command line held the password" "$l"; fi
grep -q 'iwctl' "$W/trace.iw" && ! grep -q -- '--passphrase' "$W/trace.iw" && ok "iwctl: no --passphrase, the password at its agent's prompt" || bad "iwctl: the trace never saw iwctl, or saw --passphrase"
systemctl stop iwd || :

if [ "$fails" -eq 0 ]; then echo "wifi_proof: all ok"; else echo "wifi_proof: $fails failed"; exit 1; fi
