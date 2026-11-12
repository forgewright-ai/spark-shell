# shellcheck extended-analysis=false
# --- the storage
# sets: STORAGE_RULE STORAGE_SEEN
# reads: BAR_SYS REPO ROOT STATE_DIR TAB TMP US
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
    wm_up || { echo "$2 is at $1"; return 0; }
    case $1 in *[,\;\'\"]*) echo "$2 is at $1 (a comma, a quote or a semicolon in it, which sway would split)"; return 0 ;; esac
    _so=$(term_in_dir "$1")
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

