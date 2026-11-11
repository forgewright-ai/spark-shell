# shellcheck extended-analysis=false
# --- the notifications
# sets: APP_GROUPS NOTIFY_MODE NOTIFY_SEEN POWER_SUDOERS STORAGE_RULE STORAGE_SEEN
# reads: BAR_PROC BAR_SYS DESK_LAST DESK_WAIT LAYOUTS_DIR MODE OS PANEL_APP PANEL_CACHE PANEL_CROSS PANEL_SEP PANEL_TICK REPO ROOT STATE_DIR TAB THEME_KEYS TMP US WALL_NAMES
NOTIFY_MODE=do-not-disturb
mako_here() { [ -z "${SPARK_SHELL_NO_MAKO:-}" ] && command -v mako >/dev/null 2>&1; }   # SPARK_SHELL_NO_MAKO: for the tests
notify_mode() { read_once notify.mode makoctl mode; }   # -> the modes on
notify_up() { command -v makoctl >/dev/null 2>&1 && notify_mode >/dev/null 2>&1; }
notify_reload() { ! notify_up || makoctl reload >/dev/null 2>&1 || :; }
notify_dnd() { read_once notify.dnd notify_dnd_now; }
notify_dnd_now() { notify_mode 2>/dev/null | grep -qx "$NOTIFY_MODE"; }
notify_anchor() { if [ "$DESKTOP_BAR" = yes ] && [ "$BAR_POSITION" = bottom ]; then echo bottom-right; else echo top-right; fi; }
# the ids looked at; mako's ids restart with the session
NOTIFY_SEEN=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; NOTIFY_SEEN=${NOTIFY_SEEN:-$STATE_DIR}/notify-seen
notify_ids() { { notify_list list; notify_list history; } | cut -d "$US" -f1 | grep -x '[0-9][0-9]*' | sort -un || :; }   # -> mako's ids, one a line
notify_unseen() {   # -> how many nobody looked at
    notify_ids > "$TMP/notify.ids"
    if [ -s "$NOTIFY_SEEN" ]; then grep -cvxFf "$NOTIFY_SEEN" "$TMP/notify.ids" || :; else grep -c . "$TMP/notify.ids" || :; fi
}
notify_seen() {   # notify_seen [ID...] -- looked at, all by default
    notify_up || return 0
    mkdir -p "$(dirname "$NOTIFY_SEEN")" 2>/dev/null || return 0
    notify_ids > "$TMP/notify.ids"
    if [ $# -eq 0 ]; then cp "$TMP/notify.ids" "$NOTIFY_SEEN.new"
    else { cat "$NOTIFY_SEEN" 2>/dev/null || :; printf '%s\n' "$@"; } | grep -xFf "$TMP/notify.ids" | sort -un > "$NOTIFY_SEEN.new" || :; fi
    mv -f "$NOTIFY_SEEN.new" "$NOTIFY_SEEN"; bar_redraw
}
notify_bus() { [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; }   # its own bus, or logind's
notify_keep() {   # do not disturb as configured, once mako answers
    [ "$DO_NOT_DISTURB" = yes ] && command -v makoctl >/dev/null 2>&1 || return 0
    _nk=0; while [ "$_nk" -lt 20 ] && ! makoctl mode >/dev/null 2>&1; do sleep 0.25; _nk=$((_nk + 1)); done
    makoctl mode -a "$NOTIFY_MODE" >/dev/null 2>&1 || :
}
notify_start() {   # on desktop's notify row
    [ "$MODE" = apply ] && mako_here && notify_bus && desk_in_sway || return 0
    ! notify_up || return 0
    swaymsg -- exec mako >/dev/null 2>&1 || return 0
    ok notify "the notifications show now"
}
notify_list() { read_once "notify.$1" notify_list_now "$1"; }   # notify_list list|history -> ID US APP US SUMMARY, newest first; mako 1.7 and 1.8: JSON
notify_list_now() {
    _nlo=$(makoctl "$1" 2>/dev/null) || return 0
    case $_nlo in
        '{'*) printf '%s\n' "$_nlo" | jq -r '.data[0][]? | [(.id.data // 0 | tostring), (."app-name".data // ""), (.summary.data // "")] | @tsv' 2>/dev/null || : ;;
        *)
        awk '/^Notification [0-9]+:/ { if (id != "") print id "\t" app "\t" sum; id = $2; sub(/:$/, "", id); sum = $0; sub(/^Notification [0-9]+: ?/, "", sum); gsub(/\t/, " ", sum); app = ""; next }
            /^  App name: / { app = $0; sub(/^  App name: /, "", app); gsub(/\t/, " ", app) }
            END { if (id != "") print id "\t" app "\t" sum }' <<NOTIFY
$_nlo
NOTIFY
        ;;
    esac | scrub_text | awk -F '\t' -v OFS='\037' '{ $1 = $1; print }'   # scrubbed first: the scrubber drops US
}
notify_send() {   # notify_send CATEGORY SUMMARY [BODY] -- mako's config reads the category
    [ -n "${WAYLAND_DISPLAY:-}" ] && command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a spark-shell -c "$1" -- "$2" "${3:-}" >/dev/null 2>&1 </dev/null || :
}
notify_why() {
    if ! mako_here; then echo "mako is not installed (spark-shell on desktop)"
    elif ! notify_bus; then echo "no session bus yet: notifications start at your next login"
    else echo "the notifications are not running: they start at your next login"; fi
}
notify_act() {   # notify_act do-not-disturb on|off | dismiss | restore -> one line
    notify_up || { notify_why; return 1; }
    case $1 in
        do-not-disturb) case ${2:-} in
                on) makoctl mode -a "$NOTIFY_MODE" >/dev/null 2>&1 || { echo "mako did not take do not disturb"; return 1; }; config_set DO_NOT_DISTURB yes >/dev/null; DO_NOT_DISTURB=yes
                    echo "do not disturb on: notifications wait out of sight" ;;
                off) makoctl mode -r "$NOTIFY_MODE" >/dev/null 2>&1 || { echo "mako did not take do not disturb"; return 1; }; config_set DO_NOT_DISTURB no >/dev/null; DO_NOT_DISTURB=no
                    echo "do not disturb off" ;;
                *) echo "do-not-disturb takes on or off"; return 1 ;;
            esac
            bar_redraw ;;
        dismiss) makoctl dismiss -a >/dev/null 2>&1 || { echo "nothing to dismiss"; return 1; }; notify_seen; echo "dismissed" ;;
        restore) [ -n "$(notify_list history)" ] || { echo "nothing in the history"; return 1; }
            makoctl restore >/dev/null 2>&1 || { echo "mako did not show it again"; return 1; }; echo "the last one is on the screen again" ;;
        *) echo "$1 is not something notifications does"; return 1 ;;
    esac
}

# --- the storage
STORAGE_SEEN=$STATE_DIR/storage.seen   # a new drive is said once
STORAGE_RULE=etc/polkit-1/rules.d/50-spark-shell-storage.rules
storage_list() { read_once storage.list storage_list_now; }   # -> "drive NAME DEV SIZE" and "fs NAME DEV SIZE MOUNT DRIVE FSTYPE" lines, by US
storage_list_now() {
    command -v lsblk >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    lsblk -J -b -o NAME,PATH,TYPE,RM,HOTPLUG,SIZE,MODEL,VENDOR,LABEL,FSTYPE,MOUNTPOINT 2>/dev/null | jq -r --arg media "${SPARK_SHELL_MEDIA:-/nowhere/}" '
        def yes: . == true or . == "1" or . == 1;
        def system: [.. | objects | .mountpoint? // empty | select(. != "" and ((startswith("/run/media/") or startswith("/media/") or startswith($media)) | not))] | length > 0;
        .blockdevices[]? | select(.type == "disk" and ((.rm | yes) or (.hotplug | yes)) and (system | not))
        | . as $d | ([(.vendor // ""), (.model // "")] | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")) | join(" ")) as $m
        | ["drive", (if $m == "" then "drive" else $m end), .path, (.size | tostring)],
          ([$d] + ($d.children // []) | .[] | select((.fstype // "") != "") | ["fs", (.label // ""), .path, (.size | tostring), (.mountpoint // ""), "", .fstype])
        | @tsv' 2>/dev/null | scrub_text | awk -F '\t' -v OFS='\037' '
        function hs(n) { if (n < 1024) return sprintf("%d B", n); if (n < 1048576) return sprintf("%d KB", n / 1024); if (n < 1073741824) return sprintf("%.1f MB", n / 1048576); return sprintf("%.1f GB", n / 1073741824) }   # files_size, so a name and its size column agree
        { gsub(/\|/, "/", $2) }   # a name is a column of a row, where | parts the extras
        $1 == "drive" { n = $2; if (dn[$2]++) n = n " " dn[$2]; $2 = n; cur = n; print; next }
        { n = $2; if (n == "") n = cur " " hs($4); if (fn[n]++) n = n " " fn[n]; $2 = n; $6 = cur; print }'
}
udisks_here() { [ -z "${SPARK_SHELL_NO_UDISKS:-}" ] && command -v udisksctl >/dev/null 2>&1; }   # SPARK_SHELL_NO_UDISKS: for the tests
storage_free() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 { printf "%s", $4 }'; }   # storage_free MOUNT -> KB free
storage_kb() { files_size $(( ${1:-0} * 1024 )); }   # storage_kb KB -> 3.1 GB
storage_here() { read_once storage.here storage_here_now; }   # -> "476.9 GB, 120.3 GB free"
storage_here_now() {
    df -Pk / 2>/dev/null | awk 'NR == 2 { print $2, $4 }' > "$TMP/df.here"
    read -r _st _sf < "$TMP/df.here" 2>/dev/null && [ -n "${_sf:-}" ] || return 0
    printf '%s, %s free\n' "$(storage_kb "$_st")" "$(storage_kb "$_sf")"
}
storage_said() { sed 's/.*: //' | grep -v '^$' | tail -1 | scrub_text; }   # udisksctl's error -> its last clause
storage_find() { awk -F '\037' -v k="$1" -v n="$(panel_lower "$2")" '$1 == k && tolower($2) == n { print; exit }' "$TMP/storage.l"; }   # storage_find drive|fs NAME -> its line
storage_act() {   # storage_act mount|unmount|open|eject NAME -> one line
    udisks_here || { echo "udisksctl is not installed (spark-shell on desktop)"; return 1; }
    storage_list > "$TMP/storage.l"
    if [ "$1" = eject ]; then _sl=$(storage_find drive "$2"); else _sl=$(storage_find fs "$2"); fi
    [ -n "$_sl" ] || { echo "no drive named $2 is plugged in"; return 1; }
    _sd=$(printf '%s\n' "$_sl" | cut -d "$US" -f3); _sm=$(printf '%s\n' "$_sl" | cut -d "$US" -f5)
    case $1 in
        mount|open) if [ -z "$_sm" ]; then
                [ "$(printf '%s\n' "$_sl" | cut -d "$US" -f7)" != crypto_LUKS ] || { echo "$2 is encrypted: udisksctl unlock -b $_sd opens it"; return 1; }
                _so=$(udisksctl mount -b "$_sd" --no-user-interaction 2>&1) || { echo "could not mount $2: $(printf '%s\n' "$_so" | storage_said)"; return 1; }
                _sm=$(printf '%s\n' "$_so" | sed -n 's/^Mounted [^ ]* at \(.*\)$/\1/p' | sed 's/\.$//' | head -1)
                [ "$1" = open ] || { echo "$2 mounted at $_sm"; return 0; }
            elif [ "$1" = mount ]; then echo "$2 is mounted at $_sm"; return 0; fi
            storage_open "$_sm" "$2" ;;
        unmount) [ -n "$_sm" ] || { echo "$2 is not mounted"; return 0; }
            _so=$(udisksctl unmount -b "$_sd" --no-user-interaction 2>&1) || { echo "could not unmount $2: $(printf '%s\n' "$_so" | storage_said)"; return 1; }
            echo "$2 unmounted" ;;
        eject) _sn=$(printf '%s\n' "$_sl" | cut -d "$US" -f2)
            awk -F '\037' -v d="$_sn" '$1 == "fs" && $6 == d && $5 != "" { print $3 "\t" $2 }' "$TMP/storage.l" | while IFS="$TAB" read -r _fd _fn; do
                udisksctl unmount -b "$_fd" --no-user-interaction > "$TMP/storage.out" 2>&1 || { echo "could not unmount $_fn: $(storage_said < "$TMP/storage.out")"; exit 1; }
            done || return 1   # the subshell's exit: one held on
            if udisksctl power-off -b "$_sd" --no-user-interaction > "$TMP/storage.out" 2>&1; then echo "$2 can be taken out"
            else echo "$2 is unmounted and can be taken out"; fi ;;   # a reader cannot power off
        *) echo "$1 is not something storage does"; return 1 ;;
    esac
}
storage_open() {   # storage_open DIR NAME -> a file manager or terminal
    desk_in_sway || { echo "$2 is at $1"; return 0; }
    case $1 in *[,\;\'\"]*) echo "$2 is at $1 (a comma, a quote or a semicolon in it, which sway would split)"; return 0 ;; esac
    _so="foot --working-directory='$1'"
    if command -v xdg-open >/dev/null 2>&1 && [ -n "$(xdg-mime query default inode/directory 2>/dev/null)" ]; then _so="xdg-open '$1'"; fi
    _wr=0; win_exec "$_so" || _wr=$?
    [ "$_wr" -ne 2 ] || { echo "could not open $2"; return 1; }
    [ "$_wr" -eq 0 ] || { echo "$2 is at $1"; return 0; }
    : > "$TMP/opened"; echo "opened $2"
}
storage_drives() { storage_list | awk -F '\037' '$1 == "drive" { print $3 "\t" $4 "\t" $2 }'; }   # -> DEV<tab>SIZE<tab>NAME per drive
storage_sig() { _bsg=''; for _b in "$BAR_SYS"/block/sd* "$BAR_SYS"/block/mmcblk* "$BAR_SYS"/block/nvme*; do [ ! -e "$_b" ] || _bsg="$_bsg ${_b##*/}"; done; }   # _bsg: the disks; no process, the bar asks every second
storage_notice() {   # a new drive, said once
    command -v lsblk >/dev/null 2>&1 || return 0
    storage_drives > "$TMP/drives.now"
    if [ -n "${_storage_seen:-}" ] && [ -f "$STORAGE_SEEN" ]; then
        grep -vxF -f "$STORAGE_SEEN" "$TMP/drives.now" | while IFS="$TAB" read -r _d _s _n; do
            notify_send device.added "$_n plugged in" "$(files_size "$_s"), not mounted"   # a click opens Storage in the dialog
        done || :
    fi
    _storage_seen=1
    mkdir_private "$STATE_DIR" && cp "$TMP/drives.now" "$STORAGE_SEEN"
}
storage_rule() { render_sed "s|@USER@|$(esc "$(id -un)")|g" "$REPO/template/etc/polkit-1/rules.d/50-spark-shell-storage.rules"; }
storage_apply() {   # on desktop's storage row: the polkit rule
    [ "$(init_shape)" = runit ] || return 0
    storage_rule > "$TMP/storage.rules"; _rs=$(cksum < "$TMP/storage.rules")
    if [ "$(cat "$STATE_DIR/storage.polkit" 2>/dev/null)" = "$_rs" ]; then ok storage "you mount and eject drives (/$STORAGE_RULE)"; return 0; fi
    need storage "let $(id -un) mount and eject USB drives: /$STORAGE_RULE (polkit, sudo)" && seat_root on "the drives" || return 0
    if root_do mkdir -p "$ROOT/${STORAGE_RULE%/*}" && root_put "$TMP/storage.rules" "$ROOT/$STORAGE_RULE" 0644; then
        mkdir_private "$STATE_DIR"; printf '%s\n' "$_rs" > "$STATE_DIR/storage.polkit"
        ok storage "you mount and eject drives (/$STORAGE_RULE)"
    else row todo storage "the polkit rule could not be written -- spark-shell on desktop again"; acting=0; fi
}
storage_off() {   # by the record only
    [ -e "$STATE_DIR/storage.polkit" ] || return 0
    need storage "the polkit rule for your drives removed, as spark-shell wrote it (sudo)" || return 0
    seat_root off "the drives" || return 0
    if root_do rm -f "$ROOT/$STORAGE_RULE"; then rm -f "$STATE_DIR/storage.polkit"; row ok storage "the polkit rule for your drives is gone"
    else row todo storage "/$STORAGE_RULE stays -- spark-shell off desktop again"; fi
}

# --- the power
POWER_SUDOERS=etc/sudoers.d/spark-shell-power
about_site() {
    _as=https://github.com/forgewright-ai/spark-shell
    if [ "$OS" = Darwin ]; then open "$_as" >/dev/null 2>&1 || { echo "the browser did not open"; return 1; }
    else command -v xdg-open >/dev/null 2>&1 || { echo "xdg-open is not installed, so nothing opens the page"; return 1; }
        ( xdg-open "$_as" >/dev/null 2>&1 </dev/null 3>&- 4<&- 5>&- & ); fi
    : > "$TMP/opened"; echo "opened in the browser"
}
power_tool() {   # -> systemd | sudo | nothing
    if [ "$(init_shape)" = systemd ] && command -v systemctl >/dev/null 2>&1; then echo systemd
    elif [ -s "$STATE_DIR/power.sudoers" ] && command -v sudo >/dev/null 2>&1; then echo sudo; fi
}
power_sleeps() { grep -qwE 'mem|freeze' "$BAR_SYS/power/state" 2>/dev/null; }
power_why() { if [ "$(init_shape)" = runit ]; then echo "restart and shut down: spark-shell on desktop at a terminal sets them up (sudo once)"; else echo "restart and shut down: no logind or sudo rule here"; fi; }
power_up() {   # -> "up 3 days", "up 12 minutes"
    awk '{ s = int($1); if (s >= 172800) printf "up %d days\n", s / 86400; else if (s >= 86400) print "up 1 day"; else if (s >= 7200) printf "up %d hours\n", s / 3600; else if (s >= 3600) print "up 1 hour"; else printf "up %d minutes\n", s / 60 }' "$BAR_PROC/uptime" 2>/dev/null
}
power_logind() {   # power_logind KEY DEFAULT -> logind's setting, last drop-in wins
    _pv=$2
    for _pf in "$ROOT/etc/systemd/logind.conf" "$ROOT/usr/lib/systemd/logind.conf.d"/*.conf "$ROOT/run/systemd/logind.conf.d"/*.conf "$ROOT/etc/systemd/logind.conf.d"/*.conf; do
        [ -f "$_pf" ] || continue
        _px=$(sed -n "s/^[[:space:]]*$1=[[:space:]]*\([a-z-]*\).*/\1/p" "$_pf" | tail -1); [ -z "$_px" ] || _pv=$_px
    done
    printf '%s' "$_pv"
}
power_words() { case $1 in poweroff|halt) echo "shuts down" ;; reboot|kexec) echo restarts ;; suspend|sleep|hybrid-sleep|suspend-then-hibernate) echo suspends ;; hibernate) echo hibernates ;; lock) echo "locks the screen" ;; ignore) echo "does nothing" ;; *) echo "does $1" ;; esac; }   # power_words ACTION -> "shuts down"
power_keys() {   # -> what the power button and lid do
    if [ "$(init_shape)" = systemd ]; then
        echo "the power button $(power_words "$(power_logind HandlePowerKey poweroff)")"
        ! ls "$BAR_PROC"/acpi/button/lid/*/state >/dev/null 2>&1 || echo "closing the lid $(power_words "$(power_logind HandleLidSwitch suspend)")"
    elif pgrep -x acpid >/dev/null 2>&1; then echo "the power button and the lid: acpid decides (/etc/acpi/handler.sh)"; fi
}
power_lock_first() {   # from outside (ssh): through sway's socket
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then "$REPO/spark-shell" desktop lock >/dev/null 2>&1; return; fi
    _pp=$(pgrep -u "$(id -u)" -x sway 2>/dev/null | head -1 || :); [ -n "$_pp" ] || return 0   # no desktop: nothing to lock
    _pk=${XDG_RUNTIME_DIR:-/nonexistent}/sway-ipc.$(id -u).$_pp.sock; [ -S "$_pk" ] || return 1
    SWAYSOCK=$_pk swaymsg -- exec "$REPO/spark-shell desktop lock" >/dev/null 2>&1 || return 1
    _pl=0; while [ "$_pl" -lt 12 ]; do pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1 && return 0; sleep 0.25; _pl=$((_pl + 1)); done
    return 1
}
power_now() {   # power_now lock|suspend|logout|restart|shutdown -> one line
    case $1 in
        lock) "$REPO/spark-shell" desktop lock || return 1; echo "locked" ;;
        suspend) power_sleeps || { echo "this machine cannot suspend"; return 1; }
            _pt=$(power_tool); [ -n "$_pt" ] || { power_why; return 1; }
            power_lock_first || { echo "the desktop could not be locked, so the machine did not suspend"; return 1; }   # locked on waking, or no suspend
            echo "suspending"
            if [ "$_pt" = systemd ]; then systemctl suspend >/dev/null 2>&1; else sudo -n /usr/bin/zzz >/dev/null 2>&1; fi || { echo "the machine did not suspend"; return 1; } ;;
        logout) desk_in_sway || { echo "log out is the desktop's: Super+Shift+e, or exit in its first window"; return 1; }
            echo "logging out"; swaymsg exit >/dev/null 2>&1 || { echo "sway did not exit"; return 1; } ;;
        restart|shutdown) _pt=$(power_tool); [ -n "$_pt" ] || { power_why; return 1; }
            _pc=reboot; _pw=restarting; [ "$1" = restart ] || { _pc=poweroff; _pw="shutting down"; }
            if [ "$_pt" = systemd ]; then _po=$(systemctl "$_pc" 2>&1) || { echo "could not: $(printf '%s\n' "$_po" | grep . | tail -1 | scrub_text)"; return 1; }   # logind refuses while another login is open
            else _po=$(sudo -n "/usr/bin/$_pc" 2>&1) || { echo "could not: $(printf '%s\n' "$_po" | grep . | tail -1 | scrub_text)"; return 1; }; fi
            echo "$_pw" ;;
        *) echo "$1 is not something power does"; return 1 ;;
    esac
}
power_act() {   # power_act ACTION -> one line; lock once the dialog closes
    case $1 in
        lock) desk_in_sway || { power_now lock; return; }
            swaymsg -- exec "$REPO/spark-shell desktop power lock" >/dev/null 2>&1 || { echo "could not lock"; return 1; }
            : > "$TMP/opened"; echo "locked" ;;
        suspend) power_now suspend > "$TMP/suspend.out" 2>&1 || { cat "$TMP/suspend.out"; return 1; }
            echo "back from suspend" ;;
        *) power_now "$1" ;;
    esac
}
power_rule() { render_sed "s|@USER@|$(esc "$(id -un)")|g" "$REPO/template/etc/sudoers.d/spark-shell-power"; }
power_apply() {   # on desktop's power row: the sudo rule
    [ "$(init_shape)" = runit ] || return 0
    [ -x "$ROOT/usr/bin/zzz" ] && [ -x "$ROOT/usr/bin/reboot" ] && command -v sudo >/dev/null 2>&1 || { skip power "no zzz, reboot or sudo here: the dialog cannot restart or shut down"; return 0; }
    power_rule > "$TMP/power.sudoers"; _ps=$(cksum < "$TMP/power.sudoers")
    if [ "$(cat "$STATE_DIR/power.sudoers" 2>/dev/null)" = "$_ps" ]; then ok power "you suspend, restart and shut down from the dialog (/$POWER_SUDOERS)"; return 0; fi
    need power "let $(id -un) suspend, restart and shut down with no password, nothing else: /$POWER_SUDOERS (sudo)" && seat_root on "the power" || return 0
    root_do visudo -cf "$TMP/power.sudoers" >/dev/null 2>&1 || { row todo power "visudo refused the sudoers file -- nothing written"; acting=0; return 0; }
    if root_put "$TMP/power.sudoers" "$ROOT/$POWER_SUDOERS" 0440; then
        mkdir_private "$STATE_DIR"; printf '%s\n' "$_ps" > "$STATE_DIR/power.sudoers"
        ok power "you suspend, restart and shut down from the dialog (/$POWER_SUDOERS)"
    else row todo power "the sudoers file could not be written -- spark-shell on desktop again"; acting=0; fi
}
power_off() {   # by the record only
    [ -e "$STATE_DIR/power.sudoers" ] || return 0
    need power "the sudo rule for suspend, restart and shut down removed, as spark-shell wrote it (sudo)" || return 0
    seat_root off "the power" || return 0
    if root_do rm -f "$ROOT/$POWER_SUDOERS"; then rm -f "$STATE_DIR/power.sudoers"; row ok power "the sudo rule for suspend, restart and shut down is gone"
    else row todo power "/$POWER_SUDOERS stays -- spark-shell off desktop again"; fi
}

# an app's group: the first of these in Categories
APP_GROUPS='Network:internet Office:office Graphics:graphics AudioVideo:sound-and-video Audio:sound-and-video Video:sound-and-video Development:development Education:education Science:education Game:games System:system Settings:system Utility:utilities'
app_group() {   # app_group CATEGORIES -> the group's words
    for _apg in $APP_GROUPS; do
        case ";$1;" in *";${_apg%%:*};"*) _apw=${_apg#*:}; while case $_apw in *-*) true ;; *) false ;; esac; do _apw=${_apw%%-*}\ ${_apw#*-}; done; printf '%s\n' "$_apw"; return 0 ;; esac   # dashes as spaces
    done
    echo others
}
app_group_order() {   # app_group_order GROUP -> 1 to 10
    case $1 in internet) echo 1 ;; office) echo 2 ;; graphics) echo 3 ;; 'sound and video') echo 4 ;; development) echo 5 ;;
        education) echo 6 ;; games) echo 7 ;; system) echo 8 ;; utilities) echo 9 ;; *) echo 10 ;; esac
}
panel_apps_known() {   # -> the apps a layout may open
    ( [ "$OS" = Darwin ] || pm_detect; desk_apps '' ) 2>/dev/null | panel_apps_names
}
panel_apps_names() { sed -n 's/^\([A-Za-z0-9][^:]*\): .*/\1/p' | grep -vx shell; }   # desk_apps's lines -> the names
panel_apps_read() { ( [ "$OS" = Darwin ] || pm_detect; desk_apps '' ) > "$1" 2>/dev/null; }   # panel_apps_read FILE -- desk_apps's lines there
panel_section_rows() {   # panel_section_rows SECTION FIRST -> "MARK SECTION  TEXT<tab>SECTION ACTION [ARG]"
    _full=''; [ "$1" != "$2" ] || _full=full
    panel_rows "$1" $_full | while IFS="$TAB" read -r m t a _x; do
        [ "$1" = "$2" ] || [ "$a" != show ] || continue
        [ "$m" != - ] || m=' '
        printf '%s %s%s%s%s\t%s %s\n' "$(panel_sign "$m")" "${PANEL_DIM:-}" "$(panel_col "$1")" "${PANEL_UNMARK:-}" "$t" "$1" "$a"
    done
}
panel_stream() {   # panel_stream FIRST -> FIRST, recent picks, quick sections, then slow
    if [ "$1" != glance ]; then panel_section_rows "$1" "$1"; return; fi
    _slow=''; : > "$TMP/quick.rows"
    for s in $(panel_sections "$1"); do
        if [ "$s" != "$1" ] && [ "$(panel_cost "$s")" = slow ]; then _slow="$_slow $s"; continue; fi
        if [ "$s" = "$1" ] || [ "$s" = undo ]; then panel_section_rows "$s" "$1"; else panel_section_rows "$s" "$1" >> "$TMP/quick.rows"; fi
    done
    panel_recent_first "$TMP/quick.rows"
    for s in $_slow; do panel_section_rows "$s" "$1"; done
}
panel_recent_first() {   # panel_recent_first ROWS -- the recent picks first
    if [ -s "$PANEL_CACHE/recent" ]; then
        awk -F '\t' 'NR == FNR { want[$1 " " $2] = NR; next } { k = $2; sub(/ +$/, "", k); if (k in want) { picked[want[k]] = $0; next } print > "/dev/stderr" } END { for (i = 1; i <= 5; i++) if (i in picked) print picked[i] }' "$PANEL_CACHE/recent" "$1" 2>"$TMP/rest.rows"
        cat "$TMP/rest.rows"
    else cat "$1"; fi
}
sway_file_apply() {   # sway's config rendered, nothing redrawn
    for _k in $THEME_KEYS; do unset "$_k"; done; theme_load; EXPR=$(render_expr)
    render_one "$REPO/template/.config/sway/config" "$HOME/.config/sway/config" >/dev/null 2>&1 || :
}
look_apply() {   # a look change, on the screen now
    for _k in $THEME_KEYS; do unset "$_k"; done; theme_load; EXPR=$(render_expr)
    wall_missing >/dev/null
    wall_follow >/dev/null
    look_burst
    desktop_files >/dev/null 2>&1 || :
}
panel_act() {   # panel_act SECTION ACTION [ARG] -> one line; exit 1 when not done
    _p=$1; _a=$2; shift 2; _arg=$*
    case $_a in show) return 0 ;; esac
    case $_p:$_a in lan:address|lan:auto|lan:dns|lan:restore|wifi:address|wifi:auto|wifi:dns|wifi:restore) network_action "$_a" "$_arg"; return ;; esac
    case $_p in
        wifi) case $_a in
                setup) wifi_setup ;;
                hidden) _pw=${PANEL_PASS:-}; [ -n "$_pw" ] || _pw=$(panel_secret "password for $_arg (empty for an open network): "); wifi_connect "$_arg" "$_pw" hidden ;;
                connect) _sec=$(wifi_scan | awk -F '\t' -v n="$(panel_lower "$_arg")" 'tolower($1) == n && !done {print $3; done = 1}')
                    if [ -n "$(wifi_known_id "$_arg")" ] || [ "${_sec:-0}" = 0 ]; then wifi_connect "$_arg"
                    else _pw=${PANEL_PASS:-}; [ -n "$_pw" ] || _pw=$(panel_secret "password for $_arg: "); [ -n "$_pw" ] || { echo "no password given, so not connected"; return 1; }; wifi_connect "$_arg" "$_pw"; fi ;;
                disconnect) wifi_disconnect ;;
                forget) wifi_forget "$_arg" ;;
                *) echo "$_a is not something wifi does"; return 1 ;;
            esac ;;
        bt) bt_act "$_a" "$_arg" ;;
        printers) panel_forget printers.status
            if python3 "$REPO/lib/printers.py" "$_a" "$_arg" > "$TMP/printers.result" 2> "$TMP/printers.error"; then jq -r .receipt "$TMP/printers.result"
            else cat "$TMP/printers.error"; return 1; fi ;;
        out|mic) case $_a in
                use) snd_use "$_p" "$_arg" ;;
                level) snd_apply "$_p" "$_arg" ;;
                adjust) snd_adjust "$_p" "$_arg" ;;
                mute) snd_apply "$_p" muted ;;
                unmute) snd_apply "$_p" unmuted ;;
                *) echo "$_a is not something $_p does"; return 1 ;;
            esac ;;
        theme) case $_a in
                text|font) text_step "$_arg" ;;   # font: synonym
                wallpaper) _r=$(cmd_theme wallpaper "$_arg" 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; echo "the wallpaper is $_arg" ;;
                wallpaper-color) _h=$(wall_hex "$_arg") || { echo "a color is a name ($(printf '%s' "$WALL_NAMES" | sed 's/ /, /g')) or #rrggbb"; return 1; }
                    _r=$(cmd_theme wallpaper "$_h" 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; echo "the wallpaper is $_arg" ;;
                wallpaper-picture) _pp=$(wall_picture_ok "$_arg") || { echo "$_pp"; return 1; }
                    _r=$(cmd_theme wallpaper "$_pp" 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; echo "the wallpaper is ${_pp##*/}" ;;
                save) _r=$(cmd_theme save "$_arg" 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; echo "saved $(desk_name_of "$_arg") $PANEL_SEP spark-shell theme $(desk_name_of "$_arg") brings it back" ;;
                delete) _r=$(cmd_theme delete "$_arg" 2>&1 </dev/null) || { printf '%s\n' "$_r" | tail -1; return 1; }; echo "deleted $_arg" ;;
                back) _r=$(cmd_theme back 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; printf '%s\n' "$_r" | sed -n 1p ;;
                picture) _r=$(cmd_theme picture "$_arg" 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; printf '%s\n' "$_r" | sed -n 1p ;;
                words) theme_words_step "$_arg" ;;
                alpha) case $_arg in 1|1.0|0|0.[0-9]|0.[0-9][0-9]) ;; *) echo "alpha is 0 to 1, as 0.85"; return 1 ;; esac
                    config_set ALPHA "$_arg" >/dev/null; ALPHA=$_arg; export ALPHA; look_apply
                    echo "alpha at $_arg" ;;
                transparency|see-through) case ${_arg%\%} in more|less|[0-9]|[1-4][0-9]|50) alpha_step "${_arg%\%}" ;; *) echo "transparency takes more or less, or a percent from 0 to 50"; return 1 ;; esac ;;   # see-through: synonym
                preview) theme_preview "$_arg" ;;
                animation) anim_step "$_arg" ;;
                glyphs) glyphs_step "$_arg" ;;
                icons) icons_step "$_arg" ;;
                spacing) spacing_step "$_arg" ;;
                family) family_step "$_arg" ;;
                face) face_step "$_arg" ;;
                motion) motion_step "$_arg" ;;
                theme) _r=$(cmd_theme "$_arg" 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; echo "$_arg is on" ;;   # an older spelling
                *) _r=$(cmd_theme "$_a" 2>&1) || { printf '%s\n' "$_r" | tail -1; return 1; }; echo "$_a is on" ;;   # a palette's name
            esac ;;
        layout) case $_a in
                open) desk_kept_file "$_arg" >/dev/null || { echo "no saved layout named $_arg"; return 1; }
                    ( [ "$OS" = Darwin ] || pm_detect; REFUSE_AS=layout; KEPT_ALSO=1 desk_need "$_arg" ) ;;
                delete) ( REFUSE_AS=layout; desk_delete "$_arg" ) </dev/null ;;
                restore) [ -n "${LAYOUT_DELETED:-}" ] && [ -f "$LAYOUT_DELETED/$_arg" ] || { echo "$_arg can no longer come back"; return 1; }
                    mkdir -p "$LAYOUTS_DIR" && mv "$LAYOUT_DELETED/$_arg" "$LAYOUTS_DIR/$_arg" || { echo "could not bring $_arg back"; return 1; }
                    echo "$_arg is back" ;;
                rename) _rn=''; case $_arg in *' to='*) _rn=${_arg#* to=} ;; esac
                    ( REFUSE_AS=layout; desk_rename "${_arg%% *}" "$_rn" ) </dev/null ;;
                back) ( [ "$OS" = Darwin ] || pm_detect; REFUSE_AS=layout; desk_back ) ;;
                new) [ -n "$_arg" ] || { echo "say what you want to do"; return 1; }
                    ( [ "$OS" = Darwin ] || pm_detect; REFUSE_AS=layout; desk_need "$_arg" ) ;;
                save) panel_layout_save "$_arg" ;;
                add) panel_app_open "$_arg" || return 1
                    jq --arg a "$_arg" '.suggested = ((.suggested // []) - [$a])' "$DESK_LAST" > "$DESK_LAST.new" && mv "$DESK_LAST.new" "$DESK_LAST" ;;
                *) echo "$_a is not something layout does"; return 1 ;;
            esac ;;
        apps) case $_a in
                close|focus) panel_act window "$_a" "$_arg" ;;   # done to its window
                pick) ( cmd_apps_verb ) ;;
                open) panel_app_open "$_arg" ;;
                terminal) desk_in_sway || { echo "a terminal window needs the desktop"; return 1; }
                    _wr=0; win_exec foot || _wr=$?
                    [ "$_wr" -ne 2 ] || { echo "could not open a terminal"; return 1; }
                    [ "$_wr" -eq 0 ] || { echo "the terminal opened no window"; return 1; }
                    : > "$TMP/opened"; echo "opened a terminal" ;;
                *) echo "$_a is not something apps does"; return 1 ;;
            esac ;;
        spark) case $_a in chat) panel_chat ;; *) echo "$_a is not something spark does here"; return 1 ;; esac ;;
        window) case $_a in
                split|tabs|stacked) config_set WINDOWS "$_a" >/dev/null; WINDOWS=$_a; export WINDOWS; sway_file_apply
                    win_arrange "$_a" || { echo "could not arrange this workspace: new workspaces will use $(win_words "$_a")"; return 1; }
                    echo "windows $(win_said "$_a")" ;;
                restore) _rd=${_arg%% *}; _rw=${_arg##* now=}   # undo: the default and this workspace
                    config_set WINDOWS "$_rd" >/dev/null; WINDOWS=$_rd; export WINDOWS; sway_file_apply
                    win_arrange "$_rw" || { echo "could not arrange this workspace: new workspaces will use $(win_words "$_rd")"; return 1; }
                    echo "windows $(win_said "$_rw")" ;;
                move) win_move "${_arg%% *}" "${_arg##* to=}" ;;
                place) win_place "${_arg%% *}" "${_arg##* how=}" ;;
                close) win_change close "$_arg" ;;
                capture) _cw=${_arg%% *}; _ci=''; case $_arg in *' name='*) _ci=${_arg##* name=} ;; esac
                    case $_cw in screen|area|window) ;; *) echo "capture takes screen, area or window"; return 1 ;; esac
                    desk_in_sway || { echo "capture needs the desktop: run spark-shell on desktop"; return 1; }
                    win_capture "$_cw" "$_ci" ;;
                focus) win_change focus "$_arg" ;;
                *) echo "$_a is not something window does"; return 1 ;;
            esac ;;
        notes) notes_act "$_a" "$_arg" ;;
        reminders) rem_act "$_a" "$_arg" ;;
        notifications) notify_act "$_a" "$_arg" ;;
        storage) storage_act "$_a" "$_arg" ;;
        power) power_act "$_a" ;;
        display) case $_a in
                idle|lock) case $_arg in 0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;; *) echo "$_a takes minutes, 0 to 999 (0: never)"; return 1 ;; esac
                    _k=DISPLAY_IDLE; [ "$_a" = idle ] || _k=DISPLAY_LOCK
                    config_set "$_k" "$_arg" >/dev/null; eval "$_k=\$_arg"; export "${_k?}"; sway_file_apply; idle_restart
                    if [ "$_a" = idle ]; then echo "idle screen $(idle_words "$_arg")"; else echo "lock and display off $(idle_words "$_arg")"; fi ;;
                saver) _p=$(saver_problem "$_arg"); [ -z "$_p" ] || { echo "$_p"; return 1; }
                    config_set DISPLAY_SAVER "$_arg" >/dev/null; DISPLAY_SAVER=$_arg; export DISPLAY_SAVER
                    echo "idle screen shows $(saver_words "$_arg")" ;;
                brightness) light_set "$_arg" ;;
                scale|mode|position|place|transform|screen-on|screen-off|main) screen_action "$_a" "$_arg" ;;
                *) echo "$_a is not something display does"; return 1 ;;
            esac ;;
        clock) time_setting "$_a" "$_arg" ;;
        pointer) input_setting pointer "$_a" "$_arg" ;;
        keyboard) case $_a in
                repeat-delay|repeat-rate|caps) input_setting keyboard "$_a" "$_arg" ;;
                next) desk_in_sway || { echo "a layout switch needs the desktop"; return 1; }
                    swaymsg -- input type:keyboard xkb_switch_layout next >/dev/null 2>&1 || { echo "sway took no layout switch"; return 1; }
                    bar_redraw; echo "the keyboard is $(kb_active)" ;;
                use) desk_in_sway || { echo "a layout switch needs the desktop"; return 1; }
                    _i=$(printf '%s\n' $KEYBOARD | awk -v n="$(panel_lower "$_arg")" 'tolower($0) == n {print NR - 1; exit}'); [ -n "$_i" ] || { echo "no layout $_arg in KEYBOARD ($KEYBOARD)"; return 1; }
                    swaymsg -- input type:keyboard xkb_switch_layout "$_i" >/dev/null 2>&1 || { echo "sway took no layout switch"; return 1; }
                    bar_redraw; echo "the keyboard is $_arg" ;;
                *) echo "$_a is not something keyboard does"; return 1 ;;
            esac ;;
        about) case $_a in open) panel_about 72 ;; site) about_site ;; *) echo "$_a is not something about does"; return 1 ;; esac ;;
        tools) tools_act "$_a" "$_arg" ;;
        bar) case $_a in
                off) bar_desktop off desktop >/dev/null; echo "bar hidden $PANEL_SEP $(panel_keys "$(desk_keys | awk '$2 == "home.open." {print $1; exit}')") opens the dialog" ;;
                on) bar_desktop on desktop >/dev/null; echo "bar shown" ;;
                top|bottom) bar_where "$_a" >/dev/null; echo "bar $(bar_place_words "$_a")" ;;
                text) bar_text_step "$_arg" ;;
                tray) case $_arg in on|off) bar_tray_step "$_arg" ;; *) echo "tray takes on or off"; return 1 ;; esac ;;
                *) echo "$_a is not something bar does"; return 1 ;;
            esac ;;
        undo) case $_a in all) panel_undo ;; *) echo "$_a is not something undo does"; return 1 ;; esac ;;
        *) echo "$_p takes no action"; return 1 ;;
    esac
}
panel_app_open() {   # panel_app_open NAME -> the app opens here
    desk_in_sway || { echo "opening an app needs the desktop"; return 1; }
    mv -f "$TMP/apps.gate" "$TMP/apps" 2>/dev/null || panel_apps_read "$TMP/apps"   # the gate's list, if any
    _n=$(sed -n "s/^\($(printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g')\): .*/\1/Ip" "$TMP/apps" | head -1); [ -n "$_n" ] || { echo "no app named $1 here"; return 1; }
    _l=$(desk_launch "$_n" ''); ! desk_app_term "$_n" || _l="foot -e $_l"
    _wr=0; win_exec "$_l" || _wr=$?
    [ "$_wr" -ne 2 ] || { echo "could not open $_n"; return 1; }
    # maybe a tab in an open app: not refused
    [ "$_wr" -eq 0 ] || { echo "asked $_n to open; no new window came"; return 0; }
    : > "$TMP/opened"; echo "opened $_n"   # the dialog's mark: it closes
}
win_exec() {   # win_exec COMMAND -> 0 a new window, 1 none in DESK_WAIT seconds, 2 no exec
    _wr=1; [ ! -p "$TMP/win.events" ] || rm -f "$TMP/win.events"
    if ! command -v timeout >/dev/null 2>&1 || ! mkfifo "$TMP/win.events" 2>/dev/null; then
        swaymsg -- exec "$1" > /dev/null 2>&1 < /dev/null || _wr=2
        return "$_wr"
    fi
    timeout "$DESK_WAIT" swaymsg -r -t subscribe -m '["tick","window"]' > "$TMP/win.events" 2>/dev/null < /dev/null & _wx=$!
    {
        IFS= read -r _we || :   # the subscribe tick: no window missed from here
        if swaymsg -- exec "$1" > /dev/null 2>&1 < /dev/null; then
            while IFS= read -r _we; do case $_we in '{ "change": "new"'*|'{"change":"new"'*) _wr=0; break ;; esac; done   # -r: one event a line; sway spaces its JSON
        else _wr=2; fi
    } < "$TMP/win.events"
    kill "$_wx" 2>/dev/null || :; wait "$_wx" 2>/dev/null || :; rm -f "$TMP/win.events"
    return "$_wr"
}
win_open() {   # -> APP<tab>TITLE<tab>ID per window
    swaymsg -t get_tree 2>/dev/null | jq -r --arg me "$PANEL_APP" '.. | objects | select(.pid? != null and (.type? == "con" or .type? == "floating_con")) | select(((.app_id // .window_properties.class // "") != "") and .app_id != $me) | "\(.app_id // .window_properties.class)\t\(.name // "" | gsub("\t"; " "))\t\(.id)"' 2>/dev/null | scrub_text || :   # any program's words: scrubbed
}
win_label() { win_open | awk -F '\t' '{ n = split($1, p, "."); a = tolower(p[n]); if (a == "footclient") a = "foot"; l = a; if ($2 != "" && tolower($2) != a) l = l ": " $2; print l "\t" $3 }'; }   # -> LABEL<tab>ID
win_facts() {   # -> JSON: .windows, .here (this workspace), .spaces
    swaymsg -t get_tree 2>/dev/null | jq -c --arg me "$PANEL_APP" --arg sep "$PANEL_SEP" --arg def "${WINDOWS:-split}" --arg aside "$(win_aside)" '
        def kids: (.nodes // []) + (.floating_nodes // []);
        def leaves: if (kids | length) == 0 then . else kids[] | leaves end;
        def app: (.app_id // .window_properties.class // "") | split(".") | last | ascii_downcase | if . == "footclient" then "foot" else . end;
        def arrangement: if ((.nodes // []) | length) == 1 and .nodes[0].pid == null then .nodes[0] | arrangement else .layout end;   # sway wraps a workspace'"'"'s windows in one container when they go to tabs
        def front: ([.focus[]? as $i | kids[] | select(.id == $i and .app_id != $me)] | first) as $c | if $c == null then . else $c | front end;
        def named: (.name // "") as $n | ((.num // 0) | tostring) as $u | ($n | sub("^[0-9]+"; "")) as $r
            | if ($r | startswith(":")) then ($r[1:] | split(" ")) as $p | {mark: (if $p[0] == $u then "" else ($p[0] // "") end), label: ($p[1:] | join(" "))}
              else {mark: "", label: ($r | ltrimstr(" "))} end;
        [.nodes[]? | select(.type == "output" and .name != "__i3") | .name as $o | .nodes[]? | select(.type == "workspace") | . + {screen: $o}] as $all
        | ($all | map(.screen) | unique | length) as $many
        | ($all | map(select(any(.. | objects; .focused? == true))) | first) as $here
        | (if $here == null then null else ($here | front | .id) end) as $in_front
        | def place: if (.num // 0) < 0 then .name else (.num | tostring) end;   # a name and no number: sway says -1
        def heading: named as $m | "workspace " + place + (if (.num // 0) < 0 then "" else (if $m.mark != "" then " " + $m.mark else "" end)
            + (if $m.label != "" then " \($sep) " + $m.label else "" end) end)
            + (if .id == $here.id then " \($sep) this one" else "" end)
            + (if $many > 1 then " \($sep) " + .screen else "" end) | gsub("[|]"; "/");
        def windows: [leaves | select(.pid? != null and (.app_id // .window_properties.class // "") != "" and .app_id != $me)];
        ($all | sort_by([(.num // 0) < 0, .num])) as $sorted
        | {windows: [$sorted[] | heading as $g | .num as $w | place as $p | windows[]
              | app as $a | ((.name // "") | gsub("\t"; " ")) as $t
              | {label: (if $t == "" or ($t | ascii_downcase) == $a then $a else $a + ": " + $t end), id, ws: $w, place: $p, group: $g,
                 placed: (if .fullscreen_mode == 1 or (.id | tostring) == $aside then "full screen" elif .type == "floating_con" then "floating" else "tiled" end), floating: (.type == "floating_con"), front: (.id == $in_front)}],
           here: (if $here == null then null else {ws: $here.num, group: ($here | heading), empty: (($here | windows | length) == 0),
                 arrange: (if ($here | windows | length) == 0 then $def else ($here | arrangement) as $l | if $l == "tabbed" then "tabs" elif $l == "stacked" then "stacked" else "split" end end)} end),
           spaces: [$sorted[] | select((.num // 0) > 0) | named as $m | {num, mark: $m.mark, label: $m.label, apps: ([windows[] | app] | unique)}]}'
}
win_aside() { [ -z "${SPARK_SHELL_ASIDE:-}" ] || cat "$SPARK_SHELL_ASIDE" 2>/dev/null || :; }   # -> the window that stepped aside
win_read() { { if [ -n "${WIN_FACTS_READ:-}" ]; then cat "$TMP/win.facts"; else win_facts; fi; } | jq -r '.windows[]? | [.label, (.id | tostring), .group] | @tsv'; }   # -> LABEL<tab>ID<tab>HEADING per window
win_now() { win_facts | jq -r '.here.arrange // "split"'; }   # -> split, tabs or stacked
win_arrange() {   # win_arrange split|tabs|stacked -- this workspace; true with none
    [ -n "${SWAYSOCK:-}" ] || return 0
    case $1 in tabs) _wal=tabbed ;; stacked) _wal=stacking ;; *) _wal=splith ;; esac
    _wao=$(swaymsg -- "[workspace=__focused__ tiling] layout $_wal" 2>&1) && return 0
    case $_wao in *[Nn]o\ matching*) return 0 ;; esac   # nothing tiled: not a failure
    return 1
}
win_move() {   # win_move ID N -- to workspace N, as Super+Shift+N
    _wmn=$(win_name_of "$1"); [ -n "$_wmn" ] || { echo 'that window is no longer open'; return 1; }
    swaymsg -- "[con_id=$1] move container to workspace number $2" >/dev/null 2>&1 || { echo "$_wmn did not move: look at its window, then try again"; return 1; }
    echo "$_wmn moved to workspace $2"
}
win_place() {   # win_place ID tiled|floating|full|left|right|up|down
    _wpn=$(win_name_of "$1"); [ -n "$_wpn" ] || { echo 'that window is no longer open'; return 1; }
    _wpw=$(win_facts | jq -r --argjson i "$1" '.windows[] | select(.id == $i) | .floating')
    case $2 in
        tiled) swaymsg -- "[con_id=$1] fullscreen disable, floating disable" >/dev/null 2>&1 || { echo "$_wpn did not move: look at its window, then try again"; return 1; }
            echo "$_wpn tiled" ;;
        floating) if [ "$_wpw" = true ]; then swaymsg -- "[con_id=$1] fullscreen disable" >/dev/null 2>&1 || :
            else _wpr=$( REFUSE_AS=window; desk_window float "$1" ) || { echo "${_wpr#spark-shell window: }"; return 1; }; fi
            echo "$_wpn floating" ;;
        full) swaymsg -- "[con_id=$1] focus, fullscreen enable" >/dev/null 2>&1 || { echo "$_wpn did not go full screen: look at its window, then try again"; return 1; }
            : > "$TMP/opened"; echo "$_wpn full screen" ;;   # drawn over the dialog: it closes
        left|right|up|down) _wpr=$( REFUSE_AS=window; desk_window "$2" "$1" ) || { echo "${_wpr#spark-shell window: }"; return 1; }
            case $2 in up) _wpw=top ;; down) _wpw=bottom ;; *) _wpw=$2 ;; esac
            echo "$_wpn on the $_wpw half" ;;
    esac
    [ "$2" = full ] || [ "$(win_aside)" != "$1" ] || : > "$SPARK_SHELL_ASIDE"   # placed: it stays so
}
win_capture() {   # win_capture WHAT [ID] -> the picture's name
    swaymsg -- "[app_id=\"$PANEL_APP\"] move scratchpad" >/dev/null 2>&1 || :
    _wcb=''
    if [ -n "${2:-}" ]; then
        _wcb=$(swaymsg -t get_workspaces 2>/dev/null | jq -r '.[] | select(.focused) | if .num > 0 then "number \(.num)" else "\"\(.name)\"" end')
        swaymsg -- "[con_id=$2] focus" >/dev/null 2>&1 || :
    fi
    _wcr=0; _wco=$(desk_capture "$1" --wait 1 2>&1) || _wcr=$?
    [ -z "$_wcb" ] || swaymsg -- "workspace $_wcb" >/dev/null 2>&1 || :
    swaymsg -- "[app_id=\"$PANEL_APP\"] scratchpad show" >/dev/null 2>&1 || :
    [ "$_wcr" -eq 0 ] || { printf '%s\n' "${_wco#spark-shell *: }"; return 1; }
    _wcn=${_wco%%,*}; _wcn=${_wcn##*/}
    case $_wco in *clipboard*) echo "$_wcn $PANEL_SEP on the clipboard" ;; *) echo "$_wcn" ;; esac
}
win_labels() { if [ -n "${WIN_LABELS_READ:-}" ]; then cat "$TMP/win.labels"; else win_label; fi; }   # -> win_label's lines, read once
win_named() {   # win_named ID|WORDS -> its ID
    win_labels | awk -F '\t' -v w="$(panel_lower "$1")" '
        $2 == w { exact=$2; ne++ }
        w != "" && index(tolower($1),w) { matchid=$2; nm++ }
        END { if (ne == 1) print exact; else if (w ~ /^[0-9]+$/) exit 1; else if (nm == 1) print matchid; else exit 1 }'
}
win_rows() {   # LABEL<tab>ID lines -> APP<tab>ID<tab>TITLE
    awk -F '\t' 'BEGIN { OFS = "\t" } {
        l = $1; a = l; t = ""
        n = split(": | - | \342\200\224 ", seps, "|")
        best = 0; for (k = 1; k <= n; k++) { p = index(l, seps[k]); if (p > 0 && (best == 0 || p < best)) { best = p; s = seps[k] } }
        if (best > 0) { a = substr(l, 1, best - 1); t = substr(l, best + length(s)) }
        for (k = 1; k <= n; k++) { p = 0; r = t; while ((q = index(r, seps[k])) > 0) { p += q + length(seps[k]) - 1; r = substr(r, q + length(seps[k])) }
            if (p > 0 && index(tolower(r), tolower(a)) > 0) t = substr(t, 1, p - length(seps[k])) }
        gsub(/\|/, "/", t); if (NF > 2) print a, $2, $3, t; else print a, $2, t }'
}
win_name_of() { win_labels | win_rows | awk -F '\t' -v i="$1" '$2 == i { print $1; exit }'; }   # win_name_of ID -> its app's name
win_change() {   # win_change focus|close ID -> one line
    _wc_name=$(win_name_of "$2"); [ -n "$_wc_name" ] || { echo 'that window is no longer open'; return 1; }
    _wc_cmd=focus; [ "$1" != close ] || _wc_cmd='kill'
    swaymsg -- "[con_id=$2] $_wc_cmd" >/dev/null 2>&1 || { echo "$_wc_name did not $1"; return 1; }
    # a close is the app's: 50 ms a try, 2 s at most
    _wc_tries=0; _wc_ok=''
    while :; do
        _wc_rc=0; swaymsg -t get_tree 2>/dev/null | jq -e --argjson id "$2" --arg action "$1" '
            if type != "object" or .type != "root" or (.nodes | type) != "array" then error("no tree")
            else [.. | objects | select(.id? == $id)] | if $action == "close" then length == 0 else any(.[]; .focused == true) end end' >/dev/null 2>&1 || _wc_rc=$?
        [ "$_wc_rc" -ne 0 ] || { _wc_ok=1; break; }
        [ "$_wc_rc" -eq 1 ] && [ "$1" = close ] && [ "$_wc_tries" -lt 40 ] || break   # only a close reads again
        sleep 0.05; _wc_tries=$((_wc_tries + 1))
    done
    [ -n "$_wc_ok" ] || { if [ "$1" = close ]; then echo "$_wc_name did not close: it may be asking something, look at its window"; else echo "$1 was requested, but the window state did not confirm it; check the window before trying again"; fi; return 1; }
    if [ "$1" = close ]; then echo "$_wc_name closed"; else : > "$TMP/opened"; echo "$_wc_name in front"; fi
    [ -z "${PROVIDE_EFFECT:-}" ] || jq -cn --arg id "$2" --arg title "$_wc_name" --arg operation "$1" \
        '{kind:"window", id:$id, title:$title, operation:$operation}' > "$TMP/action.effect"
}
desk_windows_all() { swaymsg -t get_tree 2>/dev/null | jq '[.. | objects | select(.pid? != null)] | length' 2>/dev/null || echo 0; }   # -> how many windows
panel_layout_save() {   # panel_layout_save NAME -> this workspace, as a layout
    desk_in_sway || { echo "saving what is open needs the desktop"; return 1; }
    [ -n "$1" ] || { echo "a name for it"; return 1; }
    swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select(.type? == "workspace" and (.. | objects | select(.focused? == true)) != null) | .. | objects | select(.app_id? != null or .window_properties? != null) | "\(.app_id // .window_properties.class)\t\(.pid // 0)"' > "$TMP/open" 2>/dev/null
    [ -s "$TMP/open" ] || { echo "nothing is open on this workspace"; return 1; }
    panel_apps_known > "$TMP/known"
    ps -eo pid=,ppid=,comm= > "$TMP/ps" 2>/dev/null || : > "$TMP/ps"
    # a terminal's app: its first child, else shell
    awk -v me="$PANEL_APP" -v tab="$TAB" '
        FILENAME == ARGV[1] { c = $0; sub(/^ *[0-9]+ +[0-9]+ +/, "", c); sub(/.*\//, "", c); if (!($2 in kid)) kid[$2] = c; next }
        FILENAME == ARGV[2] { w = tolower($0); if (!(w in known)) known[w] = $0; next }
        { split($0, f, tab); if (f[1] == me) next
          a = f[1]; if (a == "foot") { a = (f[2] in kid) ? kid[f[2]] : ""; if (a ~ /^(sh|bash|zsh|dash|fish)?$/) a = "shell" }
          w = tolower(a); if (w in known) a = known[w]
          if (a != "") print a }' "$TMP/ps" "$TMP/known" "$TMP/open" > "$TMP/open.apps"
    [ -s "$TMP/open.apps" ] || { echo "nothing is open on this workspace"; return 1; }
    _name=$(desk_name_of "$1"); [ -n "$_name" ] || { echo "a name for it, in letters"; return 1; }
    [ ! -e "$LAYOUTS_DIR/$_name" ] || { echo "$_name is a layout already: rename it, or delete it first"; return 1; }   # never over a layout: no yes needed
    mkdir -p "$LAYOUTS_DIR"
    jq -R -s --arg w "$1" --arg why "saved $(date '+%e %b %Y' | sed 's/^ *//')" --arg ar "$(win_now)" 'split("\n") | map(select(. != "")) | {words: $w, why: $why, main: {app: .[0]}, side: [.[1:][] | {app: .}]} + (if $ar == "split" then {} else {arrange: $ar} end)' "$TMP/open.apps" > "$LAYOUTS_DIR/$_name"
    echo "saved $_name: $(paste -sd, "$TMP/open.apps" | sed 's/,/, /g')"
}
panel_undo() {   # the last group's inverse steps
    [ -s "$PANEL_CACHE/undo" ] || { echo "nothing to undo"; return 1; }
    cp "$PANEL_CACHE/undo" "$TMP/undo"; rm -f "$PANEL_CACHE/undo"
    while IFS="$TAB" read -r pg step _; do
        # shellcheck disable=SC2086   # the inverse's ACTION ARG, split on purpose, never a glob (the step itself keeps its own)
        set -f; set -- $step; set +f
        if _l=$(panel_act "$pg" "$@" 2>&1); then printf '%s %s\n' "$PANEL_TICK" "$_l"; else printf '%s %s\n' "$PANEL_CROSS" "$_l"; fi
    done < "$TMP/undo"
}

