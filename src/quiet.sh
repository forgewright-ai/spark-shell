# shellcheck extended-analysis=false
# --------------------------------------------------------- a quiet login
# A bare `login:`: /etc/motd empty, update-motd.d/10-uname not executable,
# /etc/issue the cursor-on escape alone (a console that lost its cursor
# gets it back). The first copies are FILE.spark-shell-orig and 10-uname's
# mark UNAME_OFF; off acts on those alone, and not at all while spark
# core's own /etc/issue.orig is there.
UNAME_OFF=$STATE_DIR/uname.off
login_quiet() {   # is the login quiet now?
    [ ! -s "$ROOT/etc/motd" ] && [ ! -x "$ROOT/etc/update-motd.d/10-uname" ] && [ "$(cat "$ROOT/etc/issue" 2>/dev/null)" = "$CURSOR_ON" ]
}
login_traces() {   # spark-shell's own records of a quiet login, and no spark core copy beside them
    [ ! -e "$ROOT/etc/issue.orig" ] && { [ -e "$ROOT/etc/motd.spark-shell-orig" ] || [ -e "$ROOT/etc/issue.spark-shell-orig" ] || [ -e "$UNAME_OFF" ]; }
}
login_apply() {
    [ "$OS" != Darwin ] || return 0
    if [ "$QUIET_LOGIN" != yes ]; then login_off; return 0; fi
    if login_quiet; then ok quiet "login: a bare login prompt, no notice, no kernel line"; return 0; fi
    changes=$((changes + 1))
    need quiet "login: empty /etc/motd and /etc/issue (the cursor escape only), 10-uname off (sudo)" || return 0
    root_ready quiet || return 0
    _mo=$ROOT/etc/motd; _is=$ROOT/etc/issue; _un=$ROOT/etc/update-motd.d/10-uname
    if [ -s "$_mo" ] && [ ! -e "$_mo.spark-shell-orig" ]; then root_do cp "$_mo" "$_mo.spark-shell-orig"; fi
    [ ! -s "$_mo" ] || { : > "$TMP/empty"; root_put "$TMP/empty" "$_mo"; }
    if [ -x "$_un" ]; then root_do chmod -x "$_un"; mkdir_private "$STATE_DIR"; : > "$UNAME_OFF"; fi
    if [ "$(cat "$_is" 2>/dev/null)" != "$CURSOR_ON" ]; then   # an issue that is the escape already is not taken over
        if [ -e "$_is.spark-shell-orig" ]; then :
        elif [ -e "$_is" ]; then root_do cp "$_is" "$_is.spark-shell-orig"
        else : > "$TMP/empty"; root_put "$TMP/empty" "$_is.spark-shell-orig"; fi
        printf '%s' "$CURSOR_ON" > "$TMP/issue"; root_put "$TMP/issue" "$_is"
    fi
    ok quiet "login: a bare login prompt, no notice, no kernel line (the originals: *.spark-shell-orig)"
}
login_off() {   # motd, issue and 10-uname back by spark-shell's own records; a stale copy of yours only goes
    [ "$OS" != Darwin ] || return 0
    login_traces || return 0
    if [ "$MODE" = dry ]; then row would quiet "login: the notice, the kernel line and the login banner back (sudo)"; return 0; fi
    root_ready quiet || return 0
    _mo=$ROOT/etc/motd; _is=$ROOT/etc/issue; _un=$ROOT/etc/update-motd.d/10-uname
    back=''
    if [ -e "$_mo.spark-shell-orig" ]; then
        if [ ! -s "$_mo" ]; then root_do cp "$_mo.spark-shell-orig" "$_mo"; back="$back motd"; fi
        root_do rm -f "$_mo.spark-shell-orig"
    fi
    if [ -e "$_is.spark-shell-orig" ]; then
        case $(cat "$_is" 2>/dev/null) in ''|"$CURSOR_ON") root_do cp "$_is.spark-shell-orig" "$_is"; back="$back issue" ;; esac
        root_do rm -f "$_is.spark-shell-orig"
    fi
    if [ -e "$UNAME_OFF" ]; then
        if [ -f "$_un" ] && [ ! -x "$_un" ]; then root_do chmod +x "$_un"; back="$back 10-uname"; fi
        rm -f "$UNAME_OFF"
    fi
    if [ -n "$back" ]; then row ok quiet "login: the login screen is as it was ($(printf '%s' "${back# }" | sed 's/ /, /g'))"
    else row ok quiet "login: spark-shell's stale copies are gone, yours stay as they are"; fi
}

# ---------------------------------------------------------- a quiet boot
# Past the boot menu, a quiet kernel line, and on Void runit's lines off:
#   grub  (Debian) the drop-in /etc/default/grub.d/zz-spark-shell-quiet.cfg;
#         update-grub
#   void  marked lines at the end of /etc/default/grub, /etc/rc.conf and
#         the tty1 getty's conf; update-grub
#   uki   (Arch) /etc/cmdline.d/zz-spark-shell-quiet.conf, the preset's
#         --splash marked off, loader.conf timeout 0 (its first copy kept);
#         mkinitcpio -P
# The rebuild is marked pending before a file changes and unmarked when it
# held, so a failed rebuild runs again next time.
GRUB_DROPIN=etc/default/grub.d/zz-spark-shell-quiet.cfg
CMDLINE_DROPIN=etc/cmdline.d/zz-spark-shell-quiet.conf
LOADER_CONF=boot/loader/loader.conf
BOOT_LOUD='"${SPARK_SHELL_BOOT_LOUD:-/run/spark-shell-boot-loud}"'
grub_want() {
    printf '%s\n' 'GRUB_TIMEOUT=0' 'GRUB_TIMEOUT_STYLE=hidden' "GRUB_CMDLINE_LINUX_DEFAULT=\"\$GRUB_CMDLINE_LINUX_DEFAULT $QUIET_WORDS\""
}
rc_want() {
    printf '%s\n' '# spark-shell quiet boot on wrote these lines, spark-shell quiet boot off removes them' \
        'case $0 in */runit/1)' \
        'msg() { :; }' \
        "msg_warn() { { : >$BOOT_LOUD; } 2>/dev/null; printf \"\\033[1m\\033[33mWARNING: \$@\\033[m\\n\"; }" \
        "msg_error() { { : >$BOOT_LOUD; } 2>/dev/null; printf \"\\033[1m\\033[31mERROR: \$@\\033[m\\n\"; }" \
        "fsck() { _ss_out=\$(command fsck \"\$@\" 2>&1); _ss_rc=\$?; [ \"\$_ss_rc\" = 0 ] || { printf '%s\\n' \"\$_ss_out\"; { : >$BOOT_LOUD; } 2>/dev/null; }; return \"\$_ss_rc\"; }" \
        'sysctl() { if [ "$1" = -p ]; then command sysctl "$@" >/dev/null; else command sysctl "$@"; fi; }' \
        'seedrng() { command seedrng "$@" >/dev/null; }' \
        "alias modules-load='modules-load >/dev/null'" \
        'esac'
}
getty_want() {
    printf '%s\n' '# spark-shell quiet boot on wrote these lines, spark-shell quiet boot off removes them' \
        "[ -e $BOOT_LOUD ] || [ -n \"\$(dmesg -l emerg,alert,crit 2>/dev/null)\" ] || GETTY_ARGS=\$(printf '%s' \"\$GETTY_ARGS\" | sed 's/--noclear//')"
}
GETTY_CONF=etc/sv/agetty-tty1/conf
have_update_grub() { command -v update-grub >/dev/null 2>&1 || [ -x "$ROOT/usr/sbin/update-grub" ]; }
uki_here() { grep -qs '^[a-z_]*_uki=' "$ROOT"/etc/mkinitcpio.d/*.preset; }
splash_live() { grep -qs '^[a-z_]*_options=.*--splash' "$ROOT"/etc/mkinitcpio.d/*.preset; }
have_grub2_mkconfig() { command -v grub2-mkconfig >/dev/null 2>&1 || [ -x "$ROOT/usr/sbin/grub2-mkconfig" ]; }   # Fedora's and openSUSE's GRUB 2, whose boot entries are not update-grub's
boot_shape() {   # -> grub | void | uki, or a refusal word: mac | wsl | arch | grub2 | nogrub
    if [ "$OS" = Darwin ]; then echo mac
    elif is_wsl; then echo wsl
    elif uki_here; then echo uki
    elif [ "$DISTRO" = arch ]; then echo arch
    elif [ -f "$ROOT/etc/default/grub" ] && have_update_grub; then
        if [ "$DISTRO" = void ]; then echo void; else echo grub; fi
    elif [ -f "$ROOT/etc/default/grub" ] && have_grub2_mkconfig; then echo grub2
    else echo nogrub; fi
}
boot_refusal() {   # boot_refusal SHAPE -> the one sentence, or nothing when spark-shell may quiet it
    case $1 in
        mac) echo "macOS has no boot menu or kernel line to quiet." ;;
        wsl) echo "WSL has no boot of its own: Windows boots it." ;;
        arch) echo "This Arch has no unified kernel image, so its kernel line is the boot loader's and stays as it is." ;;
        grub2) echo "This Linux boots through grub2-mkconfig, whose boot entries spark-shell does not edit, so the boot stays as it is (Fedora and openSUSE boot quiet already)." ;;
        nogrub) echo "There is no GRUB with update-grub here, so the boot loader stays as it is." ;;
    esac
}
pending_has() { grep -qx "$1" "$REBUILD" 2>/dev/null; }
pending_add() { pending_has "$1" && return 0; mkdir_private "$STATE_DIR"; printf '%s\n' "$1" >> "$REBUILD"; }
pending_drop() { [ -f "$REBUILD" ] || return 0; grep -vx "$1" "$REBUILD" > "$TMP/pending" || true; if [ -s "$TMP/pending" ]; then cp "$TMP/pending" "$REBUILD"; else rm -f "$REBUILD"; fi; }
boot_rebuild() {   # boot_rebuild grub|uki -- update-grub or mkinitcpio -P as root; the pending mark goes when it held
    case $1 in grub) set -- grub update-grub ;; *) set -- uki mkinitcpio -P ;; esac
    _kind=$1; shift
    if root_do "$@" >/dev/null 2>&1; then pending_drop "$_kind"; return 0; fi
    row todo quiet "boot: $* failed -- spark-shell on runs it again"; acting=0; return 1
}
boot_quiet() {   # boot_quiet SHAPE -- is every trace of a quiet boot in place?
    case $1 in
        grub) grub_want > "$TMP/want"; cmp -s "$TMP/want" "$ROOT/$GRUB_DROPIN" ;;
        void) [ "$(marked "$ROOT/etc/default/grub" "$QUIET_MARK")" = "$(grub_want)" ] \
                && [ "$(marked "$ROOT/etc/rc.conf" "$QUIET_MARK")" = "$(rc_want)" ] \
                && [ "$(marked "$ROOT/$GETTY_CONF" "$QUIET_MARK")" = "$(getty_want)" ] ;;
        uki) [ "$(cat "$ROOT/$CMDLINE_DROPIN" 2>/dev/null)" = "$QUIET_WORDS" ] && ! splash_live ;;
        *) return 1 ;;
    esac
}
boot_kind() { if [ "$1" = uki ]; then echo uki; else echo grub; fi; }
loader_timeout() {   # loader_timeout N -- systemd-boot's menu wait, the file's first copy kept (root reads under /boot)
    _lc=$ROOT/$LOADER_CONF
    [ -d "$ROOT/boot/loader" ] || root_do test -d "$ROOT/boot/loader" 2>/dev/null || return 0
    if ! root_exists "$_lc"; then : > "$TMP/loader"   # none yet: the copy says so, empty
    elif ! root_read "$_lc" > "$TMP/loader"; then
        row todo quiet "boot: root could not read /$LOADER_CONF, so its timeout stays -- spark-shell on again"; acting=0; return 0
    fi
    root_exists "$_lc.spark-shell-orig" || root_put "$TMP/loader" "$_lc.spark-shell-orig"
    font_text "$TMP/loader" "timeout $1" ' ' > "$TMP/loader.new"
    root_put "$TMP/loader.new" "$_lc"
}
boot_apply() {
    [ "$OS" != Darwin ] || return 0
    if [ "$QUIET_BOOT" != yes ]; then boot_off; return 0; fi
    shape=$(boot_shape); why=$(boot_refusal "$shape")
    if [ -n "$why" ]; then skip quiet "boot: $why"; return 0; fi
    kind=$(boot_kind "$shape")
    if boot_quiet "$shape"; then
        if ! pending_has "$kind"; then ok quiet "boot: menu hidden, a quiet kernel line$( [ "$shape" != void ] || printf ", runit's lines off")"; return 0; fi
        need quiet "boot: the last rebuild failed, run it again (sudo)" && root_ready quiet && boot_rebuilt "$kind" && ok quiet "boot: quiet after a reboot"
        return 0
    fi
    changes=$((changes + 1))
    case $shape in
        grub) need quiet "boot: GRUB drop-in /$GRUB_DROPIN; update-grub (sudo)" || return 0 ;;
        void) need quiet "boot: lines added at the end of /etc/default/grub, /etc/rc.conf and /$GETTY_CONF; update-grub (sudo)" || return 0 ;;
        uki) need quiet "boot: /$CMDLINE_DROPIN, the preset's --splash turned off, loader.conf timeout 0; mkinitcpio -P (sudo)" || return 0 ;;
    esac
    root_ready quiet || return 0
    pending_add "$kind"   # before a file changes
    case $shape in
        grub) grub_want > "$TMP/dropin"; root_put "$TMP/dropin" "$ROOT/$GRUB_DROPIN" ;;
        void)
            grub_want > "$TMP/l"; marked_text "$ROOT/etc/default/grub" "$QUIET_MARK" "$TMP/l" > "$TMP/f"; root_put "$TMP/f" "$ROOT/etc/default/grub"
            rc_want > "$TMP/l"; marked_text "$ROOT/etc/rc.conf" "$QUIET_MARK" "$TMP/l" > "$TMP/f"; root_put "$TMP/f" "$ROOT/etc/rc.conf"
            getty_want > "$TMP/l"; marked_text "$ROOT/$GETTY_CONF" "$QUIET_MARK" "$TMP/l" > "$TMP/f"; root_put "$TMP/f" "$ROOT/$GETTY_CONF" ;;
        uki)
            printf '%s\n' "$QUIET_WORDS" > "$TMP/dropin"; root_put "$TMP/dropin" "$ROOT/$CMDLINE_DROPIN"
            for p in "$ROOT"/etc/mkinitcpio.d/*.preset; do
                grep -qs '^[a-z_]*_options=.*--splash' "$p" || continue
                LC_ALL=C sed "s/^\([a-z_]*_options=.*--splash\)/$SPLASH_MARK\1/" "$p" > "$TMP/preset"; root_put "$TMP/preset" "$p"
            done
            loader_timeout 0 ;;
    esac
    boot_rebuilt "$kind" || return 0
    ok quiet "boot: quiet after a reboot (hold Shift or Space at boot for the menu)"
}
boot_rebuilt() {   # boot_rebuilt grub|uki -- the rebuild, and for GRUB its artifact read back: grub.cfg carries the line
    boot_rebuild "$1" || return 1
    [ "$1" = grub ] || return 0
    root_do grep -q 'loglevel=3' "$ROOT/boot/grub/grub.cfg" 2>/dev/null && return 0
    pending_add grub   # the rebuild did not hold
    row todo quiet "boot: grub.cfg does not carry the quiet line -- spark-shell on runs update-grub again"; acting=0; return 1
}
boot_off() {   # spark-shell's boot traces out, per shape found, then the rebuild; a failed one stays pending
    [ "$OS" != Darwin ] || return 0
    _g=0; _u=0; _m=''
    [ ! -e "$ROOT/$GRUB_DROPIN" ] || _g=1
    for f in "$ROOT/etc/default/grub" "$ROOT/etc/rc.conf" "$ROOT/$GETTY_CONF"; do [ -z "$(marked "$f" "$QUIET_MARK")" ] || _m="$_m $f"; done
    case $_m in *"$ROOT/etc/default/grub"*) _g=1 ;; esac
    { [ -e "$ROOT/$CMDLINE_DROPIN" ] || grep -qs "^$SPLASH_MARK" "$ROOT"/etc/mkinitcpio.d/*.preset; } && _u=1
    [ "$_g$_u" != 00 ] || [ -n "$_m" ] || pending_has grub || pending_has uki || return 0
    if [ "$MODE" = dry ]; then row would quiet "boot: the boot menu and the kernel's messages back, spark-shell's boot lines removed (sudo)"; return 0; fi
    root_ready quiet || return 0
    [ "$_g" = 0 ] || pending_add grub
    [ "$_u" = 0 ] || pending_add uki
    [ ! -e "$ROOT/$GRUB_DROPIN" ] || root_do rm -f "$ROOT/$GRUB_DROPIN"
    for f in $_m; do marked_text "$f" "$QUIET_MARK" > "$TMP/f"; root_put "$TMP/f" "$f"; done
    if [ "$_u" = 1 ]; then
        root_do rm -f "$ROOT/$CMDLINE_DROPIN"
        for p in "$ROOT"/etc/mkinitcpio.d/*.preset; do
            grep -qs "^$SPLASH_MARK" "$p" || continue
            LC_ALL=C sed "s/^$SPLASH_MARK//" "$p" > "$TMP/preset"; root_put "$TMP/preset" "$p"
        done
        _lc=$ROOT/$LOADER_CONF
        if root_exists "$_lc.spark-shell-orig"; then
            : > "$TMP/loader"
            if root_read "$_lc.spark-shell-orig" > "$TMP/loader.orig" && { ! root_exists "$_lc" || root_read "$_lc" > "$TMP/loader"; }; then
                font_restored "$TMP/loader" "$TMP/loader.orig" timeout ' ' > "$TMP/loader.new"
                root_put "$TMP/loader.new" "$_lc" && root_do rm -f "$_lc.spark-shell-orig"
            else
                row todo quiet "boot: root could not read /$LOADER_CONF, so its timeout stays -- spark-shell off again"; acting=0
            fi
        fi
    fi
    _held=1
    if pending_has grub; then boot_rebuild grub || _held=0; fi
    if pending_has uki; then boot_rebuild uki || _held=0; fi
    [ "$_held" = 0 ] || row ok quiet "boot: after a reboot, the boot menu and the kernel's messages are back"
}

console_apply() {   # after the renders: the palette at boot, the font, a quiet login and boot; macOS: the profile
    palette_boot
    terminal_apply
    font_apply
    login_apply
    boot_apply
}
console_off() {   # off: every one handed back
    palette_off ours
    terminal_off
    font_off
    login_off
    boot_off
}

