# shellcheck extended-analysis=false
cmd_font() {   # font [FACE SIZE|list|none]
    config_load
    pm_detect
    case ${1:-show} in
        show) [ $# -le 1 ] || refuse_in font "show takes no word"; font_show; return ;;
        list) [ $# -le 1 ] || refuse_in font "list takes no word"; font_list; return ;;
        none)
            [ $# -eq 1 ] || refuse_in font "none takes no word"
            [ "$MODE" = dry ] || [ -z "$CONSOLE_FONT" ] || config_set CONSOLE_FONT ''
            CONSOLE_FONT=''
            if [ "$OS" = Darwin ]; then terminal_apply; else font_off; fi
            verb_close "The console keeps its own font."; return ;;
    esac
    [ $# -eq 2 ] || refuse_in font "a face and a size: spark-shell font FACE SIZE (spark-shell font list shows them)"
    face=$1; size=$2
    printf '%s' "$face" | grep -qE '^[A-Za-z0-9._-]+$' || refuse_in font "$face is not a font name (spark-shell font list shows them)"
    if [ "$OS" = Darwin ]; then
        printf '%s' "$size" | grep -qE '^[0-9]{1,2}(\.[0-9])?$' && [ "${size%%.*}" -ge 6 ] && [ "${size%%.*}" -le 72 ] \
            || refuse_in font "$size is not a size: points on macOS, 6 to 72 (13)"
        mac_face_here "$face" || refuse_in font "no font named $face is installed here (spark-shell font list shows them)"
    else
        is_wsl && refuse_in font "WSL has no console: the font is Windows Terminal's."
        [ -n "$(console_shape)" ] || refuse_in font "this Linux has no console-setup, vconsole.conf or rc.conf."
        printf '%s' "$size" | grep -qE '^[0-9]+x[0-9]+$' || refuse_in font "$size is not a size: WxH on the console (16x32)"
        console_fonts > "$TMP/fonts"
        if [ -s "$TMP/fonts" ]; then
            grep -q "^$face " "$TMP/fonts" || refuse_in font "no console font named $face here (spark-shell font list shows them)"
            grep -qx "$face $size" "$TMP/fonts" || refuse_in font "$face comes in $(sed -n "s/^$face //p" "$TMP/fonts" | paste -sd' ' -), not $size"
        fi
    fi
    [ "$MODE" = dry ] || [ "$CONSOLE_FONT" = "$face $size" ] || config_set CONSOLE_FONT "$face $size"
    CONSOLE_FONT="$face $size"; export CONSOLE_FONT
    if [ "$OS" = Darwin ]; then
        [ -f "$THEME_ENV" ] && [ -n "$THEME" ] && [ "$THEME" != none ] \
            || { verb_close "On a Mac the font is part of the Terminal.app profile, which spark-shell theme NAME makes."; return 0; }
        terminal_apply
    else
        font_apply
    fi
    verb_close "The console's font is $face $size."
}
font_show() {
    if [ "$OS" = Darwin ]; then
        echo "font  $(term_font): Terminal.app's profile$([ -n "$CONSOLE_FONT" ] || printf ' (the default)')"
    elif is_wsl; then echo "font  WSL has no console: the font is Windows Terminal's"
    elif [ -z "$(console_shape)" ]; then echo "font  there is no console-setup, vconsole.conf or rc.conf here"
    elif [ -z "$CONSOLE_FONT" ]; then echo "font  unset: the console keeps its font (spark-shell font list shows the faces)"
    else echo "font  $CONSOLE_FONT ($(font_file "$(console_shape)"))"; fi
}
font_list() {
    if [ "$OS" = Darwin ]; then
        echo "The monospace faces here, by PostScript name (the size is points, 13):"
        for f in $MAC_FACES; do mac_face_here "$f" && printf '  %s\n' "$f"; done
        echo "Font Book shows any other font's PostScript name."
        return 0
    fi
    is_wsl && { echo "WSL has no console: the font is Windows Terminal's."; return 0; }
    shape=$(console_shape)
    [ -n "$shape" ] || { echo "There is no console-setup, vconsole.conf or rc.conf here."; return 0; }
    console_fonts > "$TMP/fonts"
    if [ ! -s "$TMP/fonts" ]; then echo "No console fonts under /usr/share/kbd/consolefonts or /usr/share/consolefonts."; return 0; fi
    echo "The console fonts in $(consolefonts_dir), as spark-shell font takes them:"
    awk '{ s[$1] = s[$1] " " $2 } END { for (f in s) printf "  %-24s%s\n", f, s[f] }' "$TMP/fonts" | sort
    echo "spark-shell font FACE SIZE puts one in $(font_file "$shape")."
}

cmd_quiet() {   # quiet [login|boot [on|off]]
    config_load
    pm_detect
    case ${1:-} in
        '') quiet_show login; quiet_show boot; return ;;
        login|boot) ;;
        *) refuse_in quiet "$1 is not known here (login or boot)" ;;
    esac
    what=$1
    case ${2:-} in
        '') quiet_show "$what"; return ;;
        on|off) [ $# -eq 2 ] || refuse_in quiet "one switch at a time: spark-shell quiet $what on|off" ;;
        *) refuse_in quiet "$2 is not known here (on or off)" ;;
    esac
    [ "$OS" != Darwin ] || refuse_in quiet "macOS has no login notice or boot menu to quiet."
    if [ "$what" = boot ] && [ "$2" = on ]; then
        why=$(boot_refusal "$(boot_shape)"); [ -z "$why" ] || refuse_in quiet "$why"
        boot_warning "$(boot_shape)"
    fi
    if [ "$2" = on ]; then val=yes; else val=no; fi
    if [ "$what" = login ]; then
        [ "$MODE" = dry ] || [ "$QUIET_LOGIN" = "$val" ] || config_set QUIET_LOGIN "$val"
        QUIET_LOGIN=$val; export QUIET_LOGIN; login_apply
    else
        [ "$MODE" = dry ] || [ "$QUIET_BOOT" = "$val" ] || config_set QUIET_BOOT "$val"
        QUIET_BOOT=$val; export QUIET_BOOT; boot_apply
    fi
    case $what$val in
        loginyes) verb_close "The login is quiet: a bare login prompt from the next login." ;;
        loginno) verb_close "The login is as the distro made it from the next login." ;;
        bootyes) verb_close "The boot is quiet from the next boot." ;;
        *) verb_close "The boot is as the distro made it from the next boot." ;;
    esac
}
quiet_show() {   # quiet_show login|boot -- one row
    if [ "$OS" = Darwin ]; then printf '%-6s na: macOS has no login notice or boot menu to quiet\n' "$1"; return 0; fi
    if [ "$1" = login ]; then
        if [ "$QUIET_LOGIN" = yes ]; then echo "login  on: a bare login prompt, no notice, no kernel line"
        else echo "login  off: the distro's notice and the kernel line (spark-shell quiet login on)"; fi
        return 0
    fi
    why=$(boot_refusal "$(boot_shape)")
    if [ -n "$why" ]; then echo "boot   na: $why"
    elif [ "$QUIET_BOOT" = yes ]; then echo "boot   on: no boot menu, no kernel messages"
    else echo "boot   off: the boot menu and the kernel's messages (spark-shell quiet boot on)"; fi
}

# check and status
check_theme() {
    if [ -z "$THEME" ]; then chk theme ok "na (THEME unset: the palette stays as it is -- spark-shell theme NAME)"; return; fi
    if [ "$THEME" = none ]; then
        if [ -f "$THEME_ENV" ]; then chk theme fail "THEME=none, but theme.env is here" "spark-shell on"
        elif console_linux && { [ -e "$ROOT/$CONSOLE_UNIT" ] || [ -n "$(marked "$ROOT/etc/rc.local" "$PALETTE_MARK")" ]; }; then
            chk theme fail "THEME=none, but a palette is still set at boot" "spark-shell on"
        else chk theme ok "none: the console's and the terminal's default colors"; fi
        return
    fi
    if ! palette_render "$THEME"; then chk theme fail "THEME=$THEME: $(cat "$TMP/palette.why")" "spark-shell theme list"; return; fi
    cmp -s "$TMP/theme.env" "$THEME_ENV" || { chk theme fail "$THEME: theme.env is not the palette's" "spark-shell on"; return; }
    if [ "$OS" = Darwin ]; then
        if [ "$(cat "$TERMINAL_SEEN" 2>/dev/null)" != "$(cksum < "$THEME_ENV" | cut -d' ' -f1) $(term_font)" ]; then
            chk theme warn "$THEME: Terminal.app's profile is not the palette's yet" "spark-shell on"; return
        fi
        terminal_has || { chk theme warn "$THEME: Terminal.app has no spark-shell profile" "spark-shell on"; return; }
        chk theme ok "$THEME: theme.env and Terminal.app's profile are current"; return
    fi
    if console_linux; then
        { cmp -s "$TMP/console-colors" "$CONSOLE_COLORS" && cmp -s "$TMP/console-colors.rgb" "$CONSOLE_RGB"; } \
            || { chk theme fail "$THEME: console-colors is not the palette's" "spark-shell on"; return; }
        case $(init_shape) in
            systemd) unit_render
                { cmp -s "$TMP/unit" "$ROOT/$CONSOLE_UNIT" && unit_enabled spark-shell-console.service; } \
                    || { chk theme fail "$THEME: spark-shell-console.service does not set it at boot" "spark-shell on (sudo once)"; return; } ;;
            runit) [ "$(marked "$ROOT/etc/rc.local" "$PALETTE_MARK")" = "$(palette_line)" ] \
                    || { chk theme fail "$THEME: no line in /etc/rc.local sets it at boot" "spark-shell on (sudo once)"; return; } ;;
        esac
        if vt_here && [ "$(vt_live)" != "$(head -1 "$CONSOLE_RGB")" ]; then
            chk theme warn "$THEME: the console uses another palette until the next boot" "spark-shell on"; return
        fi
    fi
    chk theme ok "$THEME: theme.env and the console's palette are current"
}
check_font() {
    if [ -z "$CONSOLE_FONT" ]; then chk font ok "na (CONSOLE_FONT unset: the console keeps its font)"; return; fi
    if [ "$OS" = Darwin ]; then chk font ok "$CONSOLE_FONT in Terminal.app's profile"; return; fi
    if is_wsl; then chk font ok "na (WSL has no console)"; return; fi
    shape=$(console_shape)
    if [ -z "$shape" ]; then chk font warn "no console-setup, vconsole.conf or rc.conf here" "spark-shell font none"; return; fi
    if [ "$(font_now "$shape")" = "$(font_want "$shape")" ]; then chk font ok "$CONSOLE_FONT ($(font_file "$shape"))"
    else chk font fail "$(font_file "$shape") says $(font_now "$shape")" "spark-shell on (sudo once)"; fi
}
check_quiet() {
    if [ "$OS" = Darwin ]; then chk quiet ok "na (macOS)"; return; fi
    st=ok; say=''
    if [ "$QUIET_LOGIN" = yes ]; then
        if login_quiet; then say="login quiet"; else say="login loud"; st=fail; fi
    elif login_traces; then say="login still quiet (QUIET_LOGIN=no)"; st=fail
    else say="login loud"; fi
    shape=$(boot_shape); kind=$(boot_kind "$shape")
    if [ "$QUIET_BOOT" = yes ]; then
        case $shape in
            wsl) say="$say, boot na (WSL)" ;;
            arch) say="$say, boot na (no unified kernel image)" ;;
            grub2) say="$say, boot na (grub2-mkconfig)" ;;
            nogrub) say="$say, boot na (no GRUB)" ;;
            *)
                if ! boot_quiet "$shape"; then say="$say, boot loud"; st=fail
                elif pending_has "$kind"; then say="$say, boot quiet but its rebuild failed"; st=fail
                elif [ "$kind" = grub ] && [ -r "$ROOT/boot/grub/grub.cfg" ] && ! grep -q 'loglevel=3' "$ROOT/boot/grub/grub.cfg"; then say="$say, boot loud (grub.cfg lacks the quiet line)"; st=fail
                elif [ -r "$ROOT/proc/cmdline" ] && ! grep -q 'loglevel=3' "$ROOT/proc/cmdline"; then
                    say="$say, boot quiet after a reboot"; [ "$st" = fail ] || st=warn
                else say="$say, boot quiet"; fi ;;
        esac
    elif [ -e "$ROOT/$GRUB_DROPIN" ] || [ -e "$ROOT/$CMDLINE_DROPIN" ] || pending_has grub || pending_has uki \
         || [ -n "$(marked "$ROOT/etc/default/grub" "$QUIET_MARK")$(marked "$ROOT/etc/rc.conf" "$QUIET_MARK")" ]; then
        say="$say, boot still quiet (QUIET_BOOT=no)"; st=fail
    else say="$say, boot loud"; fi
    case $st in
        ok) chk quiet ok "$say" ;;
        warn) chk quiet warn "$say" "reboot: the next boot is quiet" ;;
        *) chk quiet fail "$say" "spark-shell on (sudo once)" ;;
    esac
}
status_console() {   # the font and quiet rows of status
    if [ "$OS" = Darwin ]; then printf '  font  %-16s %s\n' "$(term_font)" "Terminal.app's profile (spark-shell font FACE SIZE)"
    elif is_wsl; then printf '  font  %-16s %s\n' na "WSL has no console"
    elif [ -z "$CONSOLE_FONT" ]; then printf '  font  %-16s %s\n' unset "the console keeps its font (spark-shell font list)"
    else printf '  font  %-16s %s\n' "$CONSOLE_FONT" "$(font_file "$(console_shape)")"; fi
    if [ "$OS" = Darwin ]; then printf '  quiet %-16s %s\n' na "macOS has no login notice or boot menu"; return 0; fi
    l=off; [ "$QUIET_LOGIN" != yes ] || l=on
    b=off; [ "$QUIET_BOOT" != yes ] || b=on
    [ -z "$(boot_refusal "$(boot_shape)")" ] || b=na
    printf '  quiet %-16s %s\n' "login $l" "boot $b (spark-shell quiet login|boot on|off)"
}

