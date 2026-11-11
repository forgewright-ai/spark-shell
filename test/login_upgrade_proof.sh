#!/bin/sh
# Native v0.41 hand-back, including the next boot, in a disposable VM.
# prepare OLD_CHECKOUT: seed its four owned files over the package config.
# apply: current `on` migrates that state without stopping the live greeter.
# Reboot the VM, then verify: getty owns tty1 and greetd did not start.
# This exercises real files and systemd. It does not install the old desktop
# or claim an interactive graphical login. The old checkout must be v0.41.
set -eu
[ "${SPARK_SHELL_DISPOSABLE_VM:-}" = 1 ] && systemd-detect-virt --vm >/dev/null 2>&1 || { echo 'only an explicitly disposable VM'; exit 1; }
[ "$(id -u)" = 0 ] || { echo 'run as root in the disposable VM'; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
case $ID in debian|arch) ;; *) echo 'this proof requires Debian or Arch'; exit 1 ;; esac
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
STATE=/var/lib/spark-shell-greetd-proof
FILES='etc/greetd/config.toml etc/greetd/spark-shell/desktop.desktop etc/greetd/spark-shell/console.desktop etc/systemd/system/greetd.service.d/spark-shell.conf'
case ${1:-} in
    prepare)
        [ "$#" = 2 ] && [ -d "$2/templates/etc/greetd" ] || { echo 'prepare needs the v0.41 checkout'; exit 1; }
        [ ! -e "$STATE" ] || { echo 'this VM has a proof state already'; exit 1; }
        [ -f /etc/greetd/config.toml ] && [ ! -e /etc/greetd/config.toml.spark-orig ] || { echo 'a fresh native greetd package config is required'; exit 1; }
        systemctl is-active greetd >/dev/null || { echo 'start the native packaged greeter first'; exit 1; }
        umask 077
        mkdir -p "$STATE/home/.config/spark-shell"
        cp /etc/greetd/config.toml "$STATE/package.toml"
        cp /etc/greetd/config.toml /etc/greetd/config.toml.spark-orig
        systemctl show -p MainPID --value greetd > "$STATE/greeter.pid"
        cat /proc/sys/kernel/random/boot_id > "$STATE/boot.id"
        # The old render markers and file names are byte-for-byte from v0.41.
        # Native service state is changed without restarting the loaded greeter,
        # just as that installer enabled its new config for the next boot.
        for rel in $FILES; do
            mkdir -p "/$(dirname "$rel")"
            sed -e "s|@REPO@|$REPO|g" -e 's/@NAME@/proof/g' \
                -e 's/@GREET_BG@//g' -e 's/@ACCENT_TUI@/blue/g' \
                -e 's/@FG_TUI@/white/g' -e 's/@MUTED_TUI@/gray/g' \
                -e 's/@BG_TUI@/black/g' "$2/templates/$rel" > "/$rel"
            chmod 644 "/$rel"
        done
        systemctl daemon-reload
        systemctl enable greetd.service
        systemctl disable getty@tty1.service
        systemctl is-enabled greetd >/dev/null
        ! systemctl is-enabled getty@tty1 >/dev/null
        echo 'ok: v0.41 owned files and next-boot service state prepared'
        ;;
    apply)
        [ -f "$STATE/boot.id" ] || { echo 'prepare first'; exit 1; }
        [ "$(cat "$STATE/boot.id")" = "$(cat /proc/sys/kernel/random/boot_id)" ] || { echo 'apply before reboot'; exit 1; }
        printf 'DESKTOP=none\nPROMPT=plain\nTHEME=none\n' > "$STATE/home/.config/spark-shell/config"
        HOME="$STATE/home" XDG_CONFIG_HOME="$STATE/home/.config" \
            XDG_STATE_HOME="$STATE/home/.local/state" \
            XDG_DATA_HOME="$STATE/home/.local/share" \
            SPARK_SHELL_DIALOG_URL=none SPARK_SHELL_FONT_URL=none \
            sh "$REPO/spark-shell" on --yes > "$STATE/on.log" 2>&1
        grep -q 'normal console login is back on tty1 from the next boot' "$STATE/on.log"
        systemctl is-enabled getty@tty1 >/dev/null
        ! systemctl is-enabled greetd >/dev/null
        [ "$(systemctl show -p MainPID --value greetd)" = "$(cat "$STATE/greeter.pid")" ]
        cmp /etc/greetd/config.toml "$STATE/package.toml"
        for rel in $FILES; do
            [ "$rel" = etc/greetd/config.toml ] || [ ! -e "/$rel" ]
        done
        touch "$STATE/applied"
        echo 'ok: native config restored, live greeter untouched; reboot this VM'
        ;;
    verify)
        [ -f "$STATE/applied" ] || { echo 'apply first'; exit 1; }
        [ "$(cat "$STATE/boot.id")" != "$(cat /proc/sys/kernel/random/boot_id)" ] || { echo 'reboot this VM before verify'; exit 1; }
        systemctl is-active getty@tty1 >/dev/null
        systemctl is-enabled getty@tty1 >/dev/null
        ! systemctl is-active greetd >/dev/null
        ! systemctl is-enabled greetd >/dev/null
        cmp /etc/greetd/config.toml "$STATE/package.toml"
        echo 'ok: after reboot, native getty owns tty1; greetd is disabled and inactive'
        ;;
    *) echo 'use prepare OLD_CHECKOUT, apply, then verify after reboot'; exit 1 ;;
esac
