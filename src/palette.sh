# shellcheck extended-analysis=false
# ------------------------------------------------------------ the palette
# sets: CONSOLE_NOW KEPT_LAYOUTS KEPT_MAX LOOKS_DIR LOOK_FORMAT PALETTE_DIR PTS_DIR VT_SYSFS WALL_CACHE WALL_COVER
# reads: ANIMATION_NAMES CONFIG_DIR CONSOLE_COLORS CONSOLE_RGB CONSOLE_UNIT FONT_FACES GLYPH_FAMILIES MODE OS PALETTE_MARK PATH_SAID REPO ROOT STATE_DIR TAB TERMINAL_SEEN TERM_NAME THEME_ENV THEME_KEYS TMP VGA_HEX WALL_TYPES
PALETTE_DIR=$CONFIG_DIR/themes
# theme.env, rendered from the palette, is what spark and every render read
palette_file() {   # palette_file NAME -> the palette's file; false when none
    case $1 in ''|.*|*[!A-Za-z0-9._-]*) return 1 ;; esac
    for _p in "$PALETTE_DIR/$1/palette.env" "$LOOKS_DIR/$1/palette.env" "$PALETTE_DIR/$1.env" "$REPO/gallery/theme/$1.env"; do
        [ -f "$_p" ] && { printf '%s' "$_p"; return 0; }
    done
    return 1
}
# look.env format 1 (no FORMAT line) has FONT for FACE and TEXT_SIZE
LOOK_FORMAT=2   # a newer format is refused, not half read
theme_dir() {   # theme_dir NAME -> its folder, or nothing
    case $1 in ''|.*|*[!A-Za-z0-9._-]*) return 0 ;; esac
    for _d in "$PALETTE_DIR/$1" "$LOOKS_DIR/$1"; do [ -f "$_d/palette.env" ] && { printf '%s' "$_d"; return 0; }; done
    return 0
}
theme_kind() {   # theme_kind NAME -> saved | look | yours | shipped | none
    case $1 in none) echo none; return ;; ''|.*|*[!A-Za-z0-9._-]*) return 0 ;; esac
    if [ -f "$PALETTE_DIR/$1/palette.env" ]; then echo saved
    elif [ -f "$LOOKS_DIR/$1/palette.env" ]; then echo look
    elif [ -f "$PALETTE_DIR/$1.env" ]; then echo yours
    elif [ -f "$REPO/gallery/theme/$1.env" ]; then echo shipped; fi
}
theme_saved_names() { for _d in "$PALETTE_DIR"/*/; do [ -f "${_d}palette.env" ] || continue; _d=${_d%/}; printf '%s\n' "${_d##*/}"; done | sort; }
theme_enum() { dirs_cached theme.enum "$(THEME_DIRS)" theme_enum_now; }   # -> the schema's enum, a|b|c
theme_enum_now() { { palette_names; theme_saved_names; echo none; } | LC_ALL=C grep -E '^[A-Za-z0-9._-]+$' | sort -u | paste -sd'|' -; }
look_get() { sed -n "s/^$2=//p" "$1/look.env" 2>/dev/null | head -1 | tr -d '\001-\037\177'; }   # look_get DIR KEY -> the value, control characters dropped
look_set() {   # look_set DIR KEY VALUE
    mkdir -p "$1"; { [ ! -f "$1/look.env" ] || grep -v "^$2=" "$1/look.env"; printf '%s=%s\n' "$2" "$3"; } > "$1/look.env.new" && mv "$1/look.env.new" "$1/look.env"
}
# a saved theme may come from another machine
look_ok() {   # look_ok DIR -> 0, or why and 1
    _lf=$1/look.env
    [ -f "$_lf" ] || return 0
    _lb=$(grep -nEv '^[[:space:]]*(#|$)|^[A-Z_0-9]+=[^;`$()|&<>]*$' "$_lf" | head -1 | cut -d: -f1)
    [ -z "$_lb" ] || { echo "line $_lb of its look.env is not KEY=value"; return 1; }
    ! LC_ALL=C grep -q '[[:cntrl:]]' "$_lf" || { echo "its look.env holds a control character"; return 1; }
    _lv=$(look_get "$1" FORMAT); case $_lv in ''|1|2) ;; [1-9]|[1-9][0-9]) echo "it was made by a newer spark-shell (format $_lv, this one reads $LOOK_FORMAT) -- spark-shell update"; return 1 ;; *) echo "its FORMAT is not a number"; return 1 ;; esac
    _lv=$(look_get "$1" FONT); [ -z "$_lv" ] || font_ok "$_lv" || { echo "its FONT is not a face and a size (letters, digits, spaces and : = . + _ -)"; return 1; }
    _lv=$(look_get "$1" FACE); case $_lv in *[!a-z]*) _lv=-- ;; esac; case " $FONT_FACES " in *" ${_lv:-neon} "*) ;; *) echo "its FACE is not neon, argon, xenon, radon or krypton"; return 1 ;; esac
    _lv=$(look_get "$1" TEXT_SIZE); case $_lv in ''|[6-9]|[1-3][0-9]|40) ;; *) echo "its TEXT_SIZE is not 6 to 40"; return 1 ;; esac
    _lv=$(look_get "$1" ANIMATION); case $_lv in *[!a-z]*) _lv=-- ;; esac; case " none $ANIMATION_NAMES " in *" ${_lv:-none} "*) ;; *) echo "its ANIMATION is not none or one of $(printf '%s' "$ANIMATION_NAMES" | sed 's/ /, /g')"; return 1 ;; esac
    _lv=$(look_get "$1" GALLERY); [ -z "$_lv" ] || gallery_num "$_lv" >/dev/null || { echo "its GALLERY is not a gallery release (gallery-v1, gallery-v2...)"; return 1; }
    _lv=$(look_get "$1" ALPHA); [ -z "$_lv" ] || alpha_ok "$_lv" || { echo "its ALPHA is not 0 to 1"; return 1; }
    _lv=$(look_get "$1" POINTER); pointer_ok "$_lv" || { echo "its POINTER is not a cursor theme's NAME and SIZE"; return 1; }
    _lv=$(look_get "$1" DRAWING); [ -z "$_lv" ] || wall_shipped "$_lv" || { echo "its DRAWING is not one of the drawings"; return 1; }
    _lv=$(look_get "$1" PALETTE); case $_lv in .*|*[!A-Za-z0-9._-]*) echo "its PALETTE is not a palette's name"; return 1 ;; esac
    _lv=$(look_get "$1" BAR_GLYPHS); case $_lv in ''|signs|words) ;; *) echo "its BAR_GLYPHS is not signs or words"; return 1 ;; esac
    _lv=$(look_get "$1" GLYPH_FAMILY); case $_lv in *[!a-z]*) _lv=-- ;; esac; case " $GLYPH_FAMILIES " in *" ${_lv:-stone} "*) ;; *) echo "its GLYPH_FAMILY is not stone, star or banner"; return 1 ;; esac   # BAR_WORKSPACES: any value, never read
    _lv=$(look_get "$1" WALLPAPER_MOTION); case $_lv in ''|on|off) ;; *) echo "its WALLPAPER_MOTION is not on or off"; return 1 ;; esac
    _lv=$(look_get "$1" DIALOG_ICONS); case $_lv in ''|on|off) ;; *) echo "its DIALOG_ICONS is not on or off"; return 1 ;; esac
    _lv=$(look_get "$1" DIALOG_SPACING); case $_lv in ''|none|groups|rows) ;; *) echo "its DIALOG_SPACING is not none, groups or rows"; return 1 ;; esac
    _lv=$(look_get "$1" WALLPAPER)
    case $_lv in
        '') ;;
        picture) _lp=$(look_get "$1" PICTURE)
            case $_lp in ''|.*|*/*) echo "its PICTURE is not a file name in the folder"; return 1 ;; esac
            path_ok "$1/$_lp" && [ -f "$1/$_lp" ] && [ ! -L "$1/$_lp" ] || { echo "its PICTURE is not a file of the folder's own"; return 1; }
            case " $WALL_TYPES " in *" $(printf '%s' "${_lp##*.}" | tr 'A-Z' 'a-z') "*) ;; *) echo "its PICTURE is not a picture ($WALL_TYPES)"; return 1 ;; esac ;;
        *) wall_value_ok "$_lv" || { echo "its WALLPAPER is not default, a drawing's name, #rrggbb or a picture's full path with $PATH_SAID"; return 1; } ;;
    esac
}
theme_source_of() {   # theme_source_of DIR -> palette name, words or picture
    _ps=$(look_get "$1" PALETTE)
    case $_ps in words) _ps=$(look_get "$1" WORDS) ;; picture) _ps=$(look_get "$1" PICTURE) ;; esac
    printf '%s' "${_ps:-palette}"
}
theme_words_of() {   # theme_words_of NAME -> its words, else NAME
    _td=$(theme_dir "$1"); _tw=''
    case $_td in "$LOOKS_DIR"/*) _tw=$(look_get "$_td" WORDS) ;; esac
    printf '%s' "${_tw:-$1}"
}
# a kept kind: the last ten applied, in KIND.history
LOOKS_DIR=$STATE_DIR/looks            # looks not saved
KEPT_LAYOUTS=$STATE_DIR/layouts       # layouts not saved
WALL_CACHE=$STATE_DIR/wallpapers      # DRAWING-PALETTE.svg and .png
KEPT_MAX=10
kept_hist() { printf '%s/%s.history' "$STATE_DIR" "$1"; }   # kept_hist KIND -> its file
kept_history() { [ ! -f "$(kept_hist "$1")" ] || cat "$(kept_hist "$1")"; }   # kept_history KIND -> "EPOCH<tab>NAME" lines, newest first
kept_names() { kept_history "$1" | cut -f2; }
kept_note() {   # kept_note KIND NAME -- NAME newest; the back cursor reset
    _kh=$(kept_hist "$1"); mkdir_private "$STATE_DIR"
    { printf '%s\t%s\n' "$(date +%s)" "$2"; [ ! -f "$_kh" ] || awk -F '\t' -v n="$2" '$2 != n' "$_kh"; } | head -n "$KEPT_MAX" > "$_kh.new" && mv "$_kh.new" "$_kh"
    rm -f "$_kh.back"
    kept_prune "$1"
}
kept_prune() {   # kept_prune KIND -- the theme in use stays
    if [ "$1" = theme ]; then _kd=$LOOKS_DIR; else _kd=$KEPT_LAYOUTS; fi
    [ -d "$_kd" ] || return 0
    kept_names "$1" > "$TMP/kept.names"
    for _f in "$_kd"/*; do
        [ -e "$_f" ] || continue
        _n=${_f##*/}
        grep -qxF -- "$_n" "$TMP/kept.names" && continue
        [ "$1" = theme ] && [ "$_n" = "${THEME:-}" ] && continue
        rm -rf "$_f"
    done
}
kept_back() {   # kept_back KIND [CURRENT] -> the previous name, one further each call
    _kh=$(kept_hist "$1"); [ -f "$_kh" ] || return 1
    if [ -f "$_kh.back" ]; then _i=$(cat "$_kh.back")
    elif [ $# -ge 2 ] && [ "$(sed -n 1p "$_kh" | cut -f2)" != "$2" ]; then _i=0
    else _i=1; fi
    _i=$((_i + 1))
    _n=$(sed -n "${_i}p" "$_kh" | cut -f2); [ -n "$_n" ] || return 1
    printf '%s' "$_i" > "$_kh.back"; printf '%s' "$_n"
}
kept_when() {   # kept_when EPOCH -> today 10:12, yesterday 18:40, monday 09:15, else 3 oct
    _kd=$(when_of "$1" %Y%m%d); _kt=$(when_of "$1" %H:%M); _now=$(date +%s)
    if [ "$_kd" = "$(date +%Y%m%d)" ]; then printf 'today %s' "$_kt"
    elif [ "$_kd" = "$(when_of $((_now - 86400)) %Y%m%d)" ]; then printf 'yesterday %s' "$_kt"
    elif [ $((_now - $1)) -lt $((6 * 86400)) ]; then printf '%s %s' "$(when_of "$1" %A | tr 'A-Z' 'a-z')" "$_kt"
    else printf '%s' "$(when_of "$1" '%e %b' | sed 's/^ *//' | tr 'A-Z' 'a-z')"; fi
}
kept_delete_ok() {   # kept_delete_ok KIND NAME -> 0 to go on; a terminal asks
    [ -t 0 ] && { : < /dev/tty; } 2>/dev/null || return 0
    printf 'delete the %s %s? [y/N] ' "$1" "$2" > /dev/tty; IFS= read -r _y < /dev/tty || _y=''
    case $_y in y|Y|yes) return 0 ;; *) echo "kept"; return 1 ;; esac
}
palette_names() { for _p in "$REPO"/gallery/theme/*.env "$PALETTE_DIR"/*.env; do [ -f "$_p" ] || continue; _n=${_p##*/}; printf '%s\n' "${_n%.env}"; done | sort -u; }
palette_get() { sed -n "s/^$2=//p" "$1" | tail -1 | tr -d '"\r'; }   # palette_get FILE KEY
PALETTE_NONE="terminal default colors"   # palette none's row
palette_darks() { dirs_cached theme.darks "$(THEME_DIRS)" palette_darks_now; }   # -> the dark palettes
palette_darks_now() {   # the background's luminance under half
    palette_names | while IFS= read -r _n; do _f=$(palette_file "$_n") && printf '%s\t%s\n' "$_n" "$(palette_get "$_f" THEME_BG)"; done \
        | awk -F '\t' 'function hx(s, i) { return (index("0123456789abcdef", substr(s, i, 1)) - 1) * 16 + index("0123456789abcdef", substr(s, i + 1, 1)) - 1 }
            { c = tolower($2); sub(/^#/, "", c); if ((hx(c, 1) * 299 + hx(c, 3) * 587 + hx(c, 5) * 114) / 1000 < 128) print $1 }'
}
palette_chip() {   # palette_chip NAME -> bg, fg, accent, ANSI 1 to 6; false when none
    _f=$(palette_file "$1") || return 1
    awk -F= '{ v[$1] = $2; gsub(/["\r]/, "", v[$1]) } END { printf "%s %s %s %s %s %s %s %s %s\n", v["THEME_BG"], v["THEME_FG"], v["THEME_ACCENT"], v["THEME_ANSI_1"], v["THEME_ANSI_2"], v["THEME_ANSI_3"], v["THEME_ANSI_4"], v["THEME_ANSI_5"], v["THEME_ANSI_6"] }' "$_f"
}
console_render() {   # console_render RRGGBB... (16) -> $TMP/console-colors and $TMP/console-colors.rgb
    _i=0; _esc=''; _r=''; _g=''; _b=''
    for _h in "$@"; do
        _esc="$_esc$(printf '\033]P%x%s' "$_i" "$_h")"
        rgb_of "#$_h"
        _r="$_r,$_R"; _g="$_g,$_G"; _b="$_b,$_B"
        _i=$((_i + 1))
    done
    printf '%s' "$_esc" > "$TMP/console-colors"
    printf '%s\n%s\n%s\n' "${_r#,}" "${_g#,}" "${_b#,}" > "$TMP/console-colors.rgb"
}
palette_render() {   # palette_render NAME -> $TMP's three files, or why not in $TMP/palette.why
    if ! _f=$(palette_file "$1"); then echo "no palette named $1 (spark-shell theme list)" > "$TMP/palette.why"; return 1; fi
    printf '# rendered by spark-shell from the palette %s -- spark-shell theme NAME changes it\n' "$1" > "$TMP/theme.env"
    awk -F= '{ k = $1; sub(/^[^=]*=/, ""); gsub(/["\r]/, ""); v[k] = $0 } END { for (k in v) print k "=" v[k] }' "$_f" > "$TMP/palette.kv"   # the last line of a key wins
    _hexes=''
    for _k in $THEME_KEYS; do
        _v=$(sed -n "s/^$_k=//p" "$TMP/palette.kv")
        hex_rgb "$_v" >/dev/null || { echo "$_f: $_k is not #rrggbb" > "$TMP/palette.why"; return 1; }
        printf '%s=%s\n' "$_k" "$_v" >> "$TMP/theme.env"
        # shellcheck disable=SC2154   # _hv is set by hex_put
        case $_k in THEME_ANSI_*) hex_put _hv "$_v" ''; _hexes="$_hexes $_hv" ;; esac
    done
    _v=$(sed -n 's/^THEME_LOGO=//p' "$TMP/palette.kv")
    case $_v in '') ;; *[!A-Za-z0-9\ _.#-]*) echo "$_f: THEME_LOGO holds more than names and colors" > "$TMP/palette.why"; return 1 ;;
        *) printf 'THEME_LOGO=%s\n' "$_v" >> "$TMP/theme.env" ;; esac
    # shellcheck disable=SC2086   # sixteen words, split on purpose
    console_render $_hexes
}
theme_ours() { [ -f "$THEME_ENV" ] && grep -q 'rendered by spark-shell' "$THEME_ENV"; }
console_send() {   # console_send FILE -- a tty console only
    [ "${TERM:-}" = linux ] && [ -t 1 ] && console_linux || return 0
    [ "$MODE" != dry ] || return 0
    cat "$1" 2>/dev/null || return 0
    [ "$todos" -gt 0 ] || printf '\033[2J\033[H'   # a todo row stays
}
# a framebuffer console paints a new palette only into cells drawn
# after it: so the escapes go last
CONSOLE_NOW=''
console_now() { [ -z "$CONSOLE_NOW" ] || console_send "$CONSOLE_NOW"; }
root_path_ok() { case $1 in *[!A-Za-z0-9/._-]*) return 1 ;; *) return 0 ;; esac; }
unit_render() { sed -e "s|@CONSOLE_RGB@|$(esc "$CONSOLE_RGB")|g" "$REPO/template/$CONSOLE_UNIT" > "$TMP/unit"; }
palette_line() { printf "[ -r '%s' ] && setvtrgb '%s'" "$CONSOLE_RGB" "$CONSOLE_RGB"; }   # the rc.local line (runit)
VT_SYSFS=$ROOT/sys/module/vt/parameters/default_red
vt_here() { [ -r "$VT_SYSFS" ]; }                              # not a container
vt_live() { head -1 "$VT_SYSFS" 2>/dev/null || true; }         # the kernel's reds now
vt_vga_rgb() {   # -> $TMP/vga.rgb, VGA for setvtrgb
    # shellcheck disable=SC2086
    console_render $VGA_HEX; cp "$TMP/console-colors.rgb" "$TMP/vga.rgb"
}

theme_files() {   # the three files, as THEME says
    [ -n "$THEME" ] || { skip theme "THEME unset: the palette stays as it is (spark-shell theme NAME)"; return 0; }
    if [ "$THEME" = none ]; then
        if [ -f "$THEME_ENV" ] && need theme "remove $THEME_ENV (THEME=none)"; then
            rm -f "$THEME_ENV"; ok theme "none: theme.env removed, terminal default colors"
        fi
        return 0
    fi
    if [ "${PALETTE_RENDERED:-}" != "$THEME" ] && ! palette_render "$THEME"; then row todo theme "THEME=$THEME: $(cat "$TMP/palette.why")"; return 0; fi
    for _f in theme.env console-colors console-colors.rgb; do
        case $_f in theme.env) _d=$THEME_ENV ;; *) _d=$CONFIG_DIR/$_f ;; esac
        if [ -f "$_d" ] && cmp -s "$TMP/$_f" "$_d"; then ok theme "$THEME ($_d)"; continue; fi
        changes=$((changes + 1))
        need theme "$THEME: write $_d" || continue
        mkdir -p "$(dirname "$_d")"; cp "$TMP/$_f" "$_d"
        [ "$_f" != console-colors ] || CONSOLE_NOW=$_d
        ok theme "$THEME: $_d written"
    done
}

palette_boot() {   # the boot palette, root's; the kernel's now
    [ -n "$THEME" ] && [ "$THEME" != none ] && [ -f "$CONSOLE_RGB" ] || return 0
    if ! console_linux; then
        if [ "$OS" = Darwin ]; then skip palette "macOS has no Linux console: Terminal.app takes the palette"
        else skip palette "WSL has no console: the palette is Windows Terminal's"; fi
        return 0
    fi
    shape=$(init_shape)
    if [ "$shape" = none ]; then skip palette "no systemd or runit here: nothing sets the palette at boot"; return 0; fi
    command -v setvtrgb >/dev/null 2>&1 || { row todo palette "setvtrgb is missing: the kbd package has it (spark-shell on)"; return 0; }
    root_path_ok "$CONSOLE_RGB" || { row todo palette "$CONSOLE_RGB holds a character a root file cannot carry: the palette at boot is left alone"; return 0; }
    if [ "$shape" = systemd ]; then
        unit_render
        if cmp -s "$TMP/unit" "$ROOT/$CONSOLE_UNIT" && unit_enabled spark-shell-console.service; then
            ok palette "spark-shell-console.service sets it at boot"
        elif need palette "write /$CONSOLE_UNIT and enable it (sudo)" && root_ready palette; then
            root_put "$TMP/unit" "$ROOT/$CONSOLE_UNIT"
            root_do systemctl daemon-reload >/dev/null 2>&1 || true
            root_do systemctl enable spark-shell-console.service >/dev/null 2>&1 || true
            ok palette "spark-shell-console.service sets it at boot"
        fi
    else
        palette_line > "$TMP/line"; echo >> "$TMP/line"
        if [ "$(marked "$ROOT/etc/rc.local" "$PALETTE_MARK")" = "$(palette_line)" ]; then
            ok palette "a line in /etc/rc.local sets it at boot"
        elif need palette "add one line at the end of /etc/rc.local, before any exit 0 (sudo)" && root_ready palette; then
            { [ -f "$ROOT/etc/rc.local" ] || printf '#!/bin/sh\n'; marked_text "$ROOT/etc/rc.local" "$PALETTE_MARK" "$TMP/line" exit; } > "$TMP/rc.local"
            root_put "$TMP/rc.local" "$ROOT/etc/rc.local" 0755
            ok palette "a line in /etc/rc.local sets it at boot"
        fi
    fi
    vt_here && [ "$(vt_live)" != "$(head -1 "$CONSOLE_RGB")" ] || return 0
    need palette "setvtrgb: every console uses the palette now (sudo)" || return 0
    root_ready palette || return 0
    if root_do setvtrgb "$CONSOLE_RGB" >/dev/null 2>&1; then ok palette "every console uses the palette now"
    else row todo palette "setvtrgb failed -- the next boot sets the palette"; acting=0; fi
}

palette_off() {   # palette_off all|ours -- VGA again, the files gone
    _unit=0; [ -e "$ROOT/$CONSOLE_UNIT" ] && _unit=1
    _line=$(marked "$ROOT/etc/rc.local" "$PALETTE_MARK")
    _files=0; [ -e "$CONSOLE_COLORS" ] || [ -e "$CONSOLE_RGB" ] && _files=1
    _env=0; if [ -f "$THEME_ENV" ] && { [ "$1" = all ] || theme_ours; }; then _env=1; fi
    [ "$_unit$_files$_env" != 000 ] || [ -n "$_line" ] || return 0
    held=1
    if console_linux && { [ "$_unit" = 1 ] || [ -n "$_line" ] || [ "$_files" = 1 ]; }; then
        vt_vga_rgb
        if [ "$_unit" = 0 ] && [ -z "$_line" ]; then
            # no root file: escapes alone
            cp "$TMP/console-colors" "$TMP/vga-colors"; CONSOLE_NOW=$TMP/vga-colors
        elif [ "$MODE" = dry ]; then
            row would palette "the console's default colors again, nothing sets a palette at boot (sudo)"
        elif root_ready palette; then
            cp "$TMP/console-colors" "$TMP/vga-colors"; CONSOLE_NOW=$TMP/vga-colors
            if [ "$_unit" = 1 ]; then
                root_do systemctl disable spark-shell-console.service >/dev/null 2>&1 || true
                root_do rm -f "$ROOT/$CONSOLE_UNIT" && root_do systemctl daemon-reload >/dev/null 2>&1 || true
                [ ! -e "$ROOT/$CONSOLE_UNIT" ] || held=0
            fi
            if [ -n "$_line" ]; then
                marked_text "$ROOT/etc/rc.local" "$PALETTE_MARK" > "$TMP/rc.local"
                if [ "$(cat "$TMP/rc.local")" = '#!/bin/sh' ]; then root_do rm -f "$ROOT/etc/rc.local" || held=0   # the one spark-shell made
                else root_put "$TMP/rc.local" "$ROOT/etc/rc.local" || held=0; fi
            fi
            if command -v setvtrgb >/dev/null 2>&1 && vt_here && [ "$(vt_live)" != "$(head -1 "$TMP/vga.rgb")" ]; then
                root_do setvtrgb vga >/dev/null 2>&1 || held=0
            fi
            [ "$held" = 0 ] || row ok palette "the console's default colors are back, nothing sets a palette at boot"
        else
            held=0
        fi
    fi
    if [ "$MODE" = dry ]; then
        [ "$_env$_files" = 00 ] || row would theme "remove the palette files from ~/.config (theme.env, console-colors)"
    elif [ "$held" = 1 ]; then
        [ "$_env" = 0 ] || rm -f "$THEME_ENV"
        rm -f "$CONSOLE_COLORS" "$CONSOLE_RGB"
        [ "$_env$_files" = 00 ] || row ok theme "the palette files are removed from ~/.config (theme.env, console-colors)"
    else
        row todo theme "the palette files stay until sudo resets the console colors -- spark-shell off at a terminal"
    fi
    return 0
}

# macOS: the stamp says what Terminal.app got; imported again on change
terminal_has() { python3 "$REPO/lib/terminal.py" has-profile >/dev/null 2>&1; }
terminal_apply() {
    [ "$OS" = Darwin ] || return 0
    [ -f "$THEME_ENV" ] && [ -n "$THEME" ] && [ "$THEME" != none ] || return 0
    # shellcheck disable=SC2046   # FACE SIZE, split on purpose
    set -- $(term_font)
    _face=$1; _size=$2
    _want="$(cksum < "$THEME_ENV" | cut -d' ' -f1) $_face $_size"
    _why="Terminal.app's profile from the palette, in $_face $_size"
    if [ "$(cat "$TERMINAL_SEEN" 2>/dev/null)" = "$_want" ]; then
        if terminal_has; then ok terminal "Terminal.app's profile is the palette, in $_face $_size"; return 0; fi
        _why="Terminal.app lost the spark-shell profile: import it again, in $_face $_size"
    fi
    need terminal "$_why" || return 0
    if python3 "$REPO/lib/terminal.py" apply "$THEME_ENV" "$_face" "$_size"; then
        mkdir_private "$STATE_DIR"; printf '%s\n' "$_want" > "$TERMINAL_SEEN"
        ok terminal "Terminal.app's profile is the palette, in $_face $_size"
    else
        row todo terminal "the helper could not write Terminal.app's profile -- spark-shell on again"; acting=0
    fi
}
terminal_off() {
    [ "$OS" = Darwin ] && [ -f "$TERMINAL_SEEN" ] || return 0
    if [ "$MODE" = dry ]; then row would terminal "Terminal.app's spark-shell profile removed"; return 0; fi
    if python3 "$REPO/lib/terminal.py" remove; then
        rm -f "$TERMINAL_SEEN"; row ok terminal "Terminal.app's spark-shell profile removed, open windows keep their look"
    else
        row todo terminal "Terminal.app kept the profile: Terminal > Settings > Profiles removes it"
    fi
}

# a tmux pane is left out: tmux would keep the codes to that pane;
# tests set SPARK_SHELL_PTS_DIR
PTS_DIR=${SPARK_SHELL_PTS_DIR:-/dev/pts}
osc_render() {   # osc_render plain|foot|dialog -> $TMP/osc.KIND: OSC 4, 10, 11 and 12
    _o=$TMP/osc.$1; : > "$_o"
    _i=0
    while [ "$_i" -le 15 ]; do
        eval "_h=\$HEX_ANSI_$_i"
        printf '\033]4;%d;#%s\033\\' "$_i" "$_h" >> "$_o"
        _i=$((_i + 1))
    done
    [ "$1" = plain ] || printf '\033]4;16;#%s\033\\\033]4;17;#%s\033\\\033]4;18;#%s\033\\\033]4;19;#%s\033\\\033]4;20;#%s\033\\\033]4;21;#%s\033\\' "$HEX_ACCENT" "$HEX_MUTED" "$PANEL_BG" "$PANEL_HI" "$PANEL_MUTED" "$PANEL_BAND" >> "$_o"
    case $1 in
        "$TERM_NAME") _bg=$(term_osc_bg "$FOOT_ALPHA" "$HEX_BG") ;;   # foot's form: opacity in percent, then the color
        dialog) _bg="#$PANEL_BG" ;;
        *) _bg="#$HEX_BG" ;;
    esac
    printf '\033]10;#%s\033\\\033]11;%s\033\\' "$HEX_FG" "$_bg" >> "$_o"
    _c=''; if [ -n "${THEME:-}" ] && [ "$THEME" != none ] && _pf=$(palette_file "$THEME"); then _c=$(palette_get "$_pf" THEME_CURSOR); fi
    if hex_rgb "$_c" >/dev/null; then printf '\033]12;%s\033\\' "$(printf '%s' "$_c" | tr 'A-F' 'a-f')" >> "$_o"
    else printf '\033]112\033\\' >> "$_o"; fi   # 112: the terminal's own cursor color
}
pts_mine() {   # -> yours, writable, not a tmux pane
    _me=$(id -u)
    _panes=''
    if command -v tmux >/dev/null 2>&1; then _panes=$(tmux list-panes -a -F '#{pane_tty}' 2>/dev/null || true); fi
    for _p in "$PTS_DIR"/*; do
        case ${_p##*/} in ''|*[!0-9]*) continue ;; esac   # N only: never ptmx
        [ -w "$_p" ] || continue
        [ "$(ls -lLdn "$_p" 2>/dev/null | awk '{print $3}')" = "$_me" ] || continue
        if printf '%s\n' "$_panes" | grep -qxF -- "$_p"; then continue; fi
        printf '%s\n' "$_p"
    done
}
pts_write() {   # pts_write PTY FILE -- 2 seconds: a stopped terminal cannot hang it
    if command -v timeout >/dev/null 2>&1; then timeout 2 sh -c 'cat "$1" > "$2"' sh "$2" "$1" 2>/dev/null
    else cat "$2" > "$1" 2>/dev/null; fi
}
pts_kinds() {   # -> "PTY<tab>KIND" lines; KIND dialog, foot or plain
    pts_mine > "$TMP/pts"
    [ -s "$TMP/pts" ] || return 0
    _fk=plain; ! desktop_wanted || _fk=$TERM_NAME
    ps -eo pid=,ppid=,tty=,comm= > "$TMP/ps" 2>/dev/null || : > "$TMP/ps"
    awk -v d="$PTS_DIR" -v fk="$_fk" -v tn="$TERM_NAME" 'NR == FNR { pp[$1] = $2; cm[$1] = $4; next }
        $3 ~ /^pts\/[0-9]+$/ { t = d "/" substr($3, 5)
            if ($4 == "spark-dialog") { k[t] = "dialog"; next }
            if (t in k) next
            p = $2; n = 0   # up the parents: a process under foot is in a window of the desktop, however deep (a shell in a shell, sudo)
            while (p != "" && p > 1 && n < 16) { if (cm[p] == tn) { k[t] = fk; break }; p = pp[p]; n++ } }
        END { while ((getline l < pts) > 0) printf "%s\t%s\n", l, (l in k) ? k[l] : "plain" }' pts="$TMP/pts" "$TMP/ps" "$TMP/ps"
}
look_terms() {   # look_terms prepare|send -- send writes all at once; _painted counts the takers
    case $1 in
        prepare)
            : > "$TMP/pts.todo"
            [ "$MODE" = apply ] && [ "$OS" != Darwin ] && [ -d "$PTS_DIR" ] || return 0
            pts_kinds > "$TMP/pts.todo"
            for _k in plain $TERM_NAME dialog; do ! grep -q "$TAB$_k\$" "$TMP/pts.todo" || osc_render "$_k"; done ;;
        send)
            _painted=0; _pids=''
            [ -s "$TMP/pts.todo" ] || return 0
            while IFS="$TAB" read -r _p _k; do
                pts_write "$_p" "$TMP/osc.$_k" & _pids="$_pids $!"   # a terminal that hangs holds no other
            done < "$TMP/pts.todo"
            for _lw in $_pids; do if wait "$_lw"; then _painted=$((_painted + 1)); fi; done ;;   # not _w: the caller's _w is in use
    esac
}
# the compositor stops its background before the new one draws, 100 ms of black;
# ours covers that and goes once sway's own has drawn
WALL_COVER=''
wall_cover() {   # WALL_BG on top, now
    WALL_COVER=''
    [ "$MODE" = apply ] && wm_session && [ -n "${WAYLAND_DISPLAY:-}" ] && wm_background_here || return 0
    case $WALL_BG in
        *' solid_color') set -- -c "${WALL_BG% solid_color}" ;;
        *) _wp=${WALL_BG% fill}; _wp=${_wp#\"}; _wp=${_wp%\"}; set -- -i "$_wp" -m fill ;;
    esac
    wm_background "$@" >/dev/null 2>&1 </dev/null & WALL_COVER=$!   # it draws in 100 to 200 ms
}
wall_uncover() {   # wall_uncover [WALL_BG] -- sway's under ours, then ours goes
    [ -n "$WALL_COVER" ] || return 0
    ( sleep 0.25; [ -z "${1:-}" ] || wm_send "output * bg $1" >/dev/null 2>&1; sleep 0.6; kill "$WALL_COVER" 2>/dev/null ) >/dev/null 2>&1 </dev/null &
    WALL_COVER=''
}
wall_shown() { sed -n 's/^output \* bg //p' "$(wm_config_file)" 2>/dev/null | head -1; }   # -> the config's wallpaper
desktop_live_cmd() {   # -> one compositor command; not the wallpaper
    wm_session && wm_here || return 0
    _c="client.focused #$PANEL_BG #$PANEL_BG #$HEX_FG #$DROP_HEX #$PANEL_BG; client.focused_inactive #$PANEL_LOW #$PANEL_LOW #$HEX_MUTED #$PANEL_LOW #$PANEL_LOW"   # the indicator: the accent at a quarter
    _c="$_c; client.unfocused #$PANEL_LOW #$PANEL_LOW #$HEX_MUTED #$PANEL_LOW #$PANEL_LOW; client.urgent #$HEX_ANSI_1 #$HEX_ANSI_1 #$HEX_BG #$HEX_ANSI_1 #$HEX_ANSI_1"
    _c="$_c; font pango:$(bar_line_font "$(font_spec)"); $(pointer_fresh)seat * xcursor_theme $POINTER_NAME $POINTER_SIZE; gaps inner all set $GAPS_INNER; gaps outer all set $GAPS_OUTER; [tiling] border $BORDER"
    _b=$(wm_bar_id)   # the bar's id, bar-0
    [ -z "$_b" ] || _c="$_c; bar $_b mode $(bar_mode); bar $_b font pango:$(bar_line_font "$(font_spec)"); bar $_b colors background #$HEX_BG$BAR_ALPHA; bar $_b colors statusline #$HEX_FG; bar $_b colors separator #$HEX_MUTED; bar $_b colors focused_workspace #$HEX_ACCENT #$HEX_ACCENT #$HEX_BG; bar $_b colors active_workspace #$HEX_MUTED #$HEX_MUTED #$HEX_BG; bar $_b colors inactive_workspace #$HEX_BG$BAR_ALPHA #$HEX_BG$BAR_ALPHA #$HEX_MUTED; bar $_b colors urgent_workspace #$HEX_ANSI_1 #$HEX_ANSI_1 #$HEX_BG; bar $_b colors binding_mode #$HEX_ACCENT #$HEX_ACCENT #$HEX_BG"
    printf '%s' "$_c"
}
theme_preview() (   # theme_preview NAME|off -- nothing written; a subshell: the caller's palette stays
    case ${1:-} in '') echo "preview takes a palette's name, or off"; exit 1 ;; esac
    MODE=apply; LOOK_PREVIEW=1
    if [ "$1" = off ]; then config_load; theme_load
    else
        [ "$1" != none ] || { echo "none has no colors to show"; exit 1; }
        palette_render "$1" || { cat "$TMP/palette.why"; exit 1; }
        [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || wall_yours || ! _pw=$(wall_for_palette "$1") || WALLPAPER=$_pw   # its own drawing, unless your picture is on
        for _k in $THEME_KEYS; do unset "$_k"; done
        THEME=$1; THEME_ENV=$TMP/theme.env; theme_load
    fi
    wall_follow >/dev/null 2>&1 || :
    look_burst
    # for the dialog to wear
    [ "$1" = off ] || { panel_load; jq -cn --arg f "$HEX_FG" --arg a "$HEX_ACCENT" --arg m "$PANEL_MUTED" --arg b "$PANEL_BG" --arg h "$PANEL_HI" --arg r "${HEX_ANSI_1:-}" --arg g "${HEX_ANSI_2:-}" \
        '{HEX_FG: $f, HEX_ACCENT: $a, PANEL_MUTED: $m, PANEL_BG: $b, PANEL_HI: $h, HEX_ANSI_1: $r, HEX_ANSI_2: $g}' > "$TMP/preview.palette" 2>/dev/null || :; }
    if [ "$1" = off ]; then echo "the look in use is on the screen again"; else echo "$1 on the screen"; fi
)
look_burst() {   # one frame: all made ready, then sent while the wallpaper draws
    _painted=0
    [ "$MODE" = apply ] && [ "$OS" != Darwin ] || return 0
    [ -n "${LOOK_PREVIEW:-}" ] || portal_look   # a preview leaves the apps' mode alone
    _wn=''; ! desktop_wanted || ! wm_session || [ "$WALL_BG" = "$(wall_shown)" ] || _wn=1
    look_terms prepare
    ! desktop_wanted || bar_palette
    _sc=''; ! desktop_wanted || _sc=$(desktop_live_cmd)   # the wallpaper goes under the cover
    [ -z "$_wn" ] || wall_cover
    if [ -n "$WALL_COVER" ]; then sleep 0.09   # the new picture draws meanwhile
    elif [ -n "$_wn" ]; then _sc="$_sc; output * bg $WALL_BG"; fi   # no cover: sway's own way, black frame
    _sw=''
    if [ -n "$_sc" ]; then wm_send "$_sc" >/dev/null 2>&1 & _sw=$!; bar_redraw; fi
    look_terms send
    [ -z "$_sw" ] || wait "$_sw" 2>/dev/null || :   # the cover's background process is a child too
    [ -z "$_sc" ] || pointer_seen
    wall_uncover "$WALL_BG"
    [ -n "${LOOK_PREVIEW:-}" ] || ! desktop_wanted || motion_follow   # a preview leaves the motion alone
    [ -n "${LOOK_PREVIEW:-}" ] || ! desktop_wanted || pad_again
}

