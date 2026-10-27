#!/bin/sh
# Native Linux dhcpcd proof in private mount, network and PID namespaces.
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
if [ "${1:-}" != inside ]; then
    [ "$(id -u)" = 0 ] || { echo 'run as root for isolated namespaces' >&2; exit 1; }
    SPARK_DHCPCD_PROOF_HOST_NET=$(readlink /proc/self/ns/net)
    SPARK_DHCPCD_PROOF_HOST_MNT=$(readlink /proc/self/ns/mnt)
    export SPARK_DHCPCD_PROOF_HOST_NET SPARK_DHCPCD_PROOF_HOST_MNT
    exec unshare --mount --net --pid --fork --mount-proc "$0" inside
fi
# A direct "inside" invocation must never touch a host namespace.
[ "$$" = 1 ] || { echo 'the proof needs its own PID namespace' >&2; exit 1; }
[ "$(readlink /proc/self/ns/net)" != "${SPARK_DHCPCD_PROOF_HOST_NET:?}" ]
[ "$(readlink /proc/self/ns/mnt)" != "${SPARK_DHCPCD_PROOF_HOST_MNT:?}" ]
mount --make-rprivate /
mount -t sysfs -o ro sysfs /sys
work=$(mktemp -d)
chmod 755 "$work"
cleanup() {
    result=$?
    # Stop every child before exposing the host filesystem during cleanup.
    # PID 1 is excluded; the outer guard proves this is our PID namespace.
    kill -KILL -1 2>/dev/null || :
    wait 2>/dev/null || :
    [ "$result" = 0 ] || cat "$work/native.log" 2>/dev/null || :
    umount /etc || :
    umount "$work/native-etc" || :
    rm -rf "$work"
    exit "$result"
}
trap cleanup EXIT
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /var/lib
[ ! -d /var/db ] || mount -t tmpfs tmpfs /var/db
printf '%s\n' 'allowinterfaces proof0' 'nodev' 'noipv6' 'noipv4ll' \
    'nohook ntp.conf,hostname' 'option domain_name_servers' > "$work/config"
chmod 644 "$work/config"
# The helper atomically replaces the config: give it a private /etc directory
# with the native hook files, without copying private native configuration.
mkdir "$work/etc"
for path in /etc/*; do
    name=${path##*/}
    [ "$name" = dhcpcd.conf ] && continue
    [ "$name" = resolv.conf ] && continue
    ln -s "$path" "$work/etc/$name"
done
# Bind the original directory at a stable, private path for those links.
mkdir "$work/native-etc"
mount --bind /etc "$work/native-etc"
mount -o remount,bind,ro "$work/native-etc"
for path in "$work/etc"/*; do
    name=${path##*/}
    rm "$path"
    ln -s "$work/native-etc/$name" "$path"
done
cp "$work/config" "$work/etc/dhcpcd.conf"
: > "$work/etc/resolv.conf"
mount --bind "$work/etc" /etc
ip link set lo up
ip link add proof0 type veth peer name server0
ip addr add 192.0.2.1/24 dev server0
ip link set server0 up
ip link set proof0 up
python3 "$repo/tests/dhcpcd_server.py" &
dhcpcd -B -d -M proof0 > "$work/native.log" 2>&1 &
python3 -I "$repo/tests/dhcpcd_native.py"
