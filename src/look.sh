# shellcheck extended-analysis=false
# ------------------------------------------------------------- the slots
# sets: HEX_KEYS PANEL_KEYS POINTER_DIR POINTER_KEYS POINTER_THEMES SCENE_MAKE SCENE_READY SLOT_KEYS THUMB_DIR VGA_HEX WALL_GROUND_SAID WALL_KEYS WALL_NAMES WALL_SCENES WALL_SHIPPED WALL_TYPES WIN_KEYS
# reads: MODE PATH_REFUSED PM POINTER_SEEN REPO STATE_DIR TERM_HEX THEME_ENV THEME_KEYS TMP WALL_CACHE
# slots (0-15), not hex: one file serves the console and an emulator;
# spark reads SPARK_*_SGR at a tty
SLOT_KEYS="ACCENT_SLOT MUTED_SLOT ACCENT_STAR MUTED_STAR ACCENT_SGR MUTED_SGR"
hex_rgb() {   # hex_rgb #rrggbb -> "r g b", or false
    case $1 in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;; *) return 1 ;; esac
    _h=${1#\#}; _m=${_h#??}
    printf '%d %d %d' "$((0x${_h%????}))" "$((0x${_m%??}))" "$((0x${_h#????}))"
}
rgb_of() {   # rgb_of #rrggbb -> _R _G _B, no subshell; else false
    case $1 in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;; *) return 1 ;; esac
    _h=${1#\#}; _m=${_h#??}
    _R=$((0x${_h%????})); _G=$((0x${_m%??})); _B=$((0x${_h#????}))
}
slot_of() {   # slot_of COLOR -> 0..15
    case $1 in
        black) echo 0; return ;; red) echo 1; return ;; green) echo 2; return ;;
        yellow) echo 3; return ;; blue) echo 4; return ;; magenta) echo 5; return ;;
        cyan) echo 6; return ;; white) echo 7; return ;;
    esac
    rgb_of "$1" || { echo 7; return; }
    _wr=$_R; _wg=$_G; _wb=$_B
    best=; slot=7; i=0
    while [ "$i" -le 15 ]; do
        eval "c=\$THEME_ANSI_$i"
        # shellcheck disable=SC2154   # c is set by the eval above
        if rgb_of "$c"; then
            d=$(( (_wr-_R)*(_wr-_R) + (_wg-_G)*(_wg-_G) + (_wb-_B)*(_wb-_B) ))
            if [ -z "$best" ] || [ "$d" -lt "$best" ]; then best=$d; slot=$i; fi
        fi
        i=$((i + 1))
    done
    echo "$slot"
}
sgr_of() {   # sgr_of N -> the SGR foreground (30-37, 90-97)
    if [ "$1" -lt 8 ]; then echo $((30 + $1)); else echo $((82 + $1)); fi
}
slot_name() {   # slot_name N -> starship's word for slot N
    _n=$1
    set -- black red green yellow blue purple cyan white
    if [ "$_n" -ge 8 ]; then shift $((_n - 8)); echo "bright-$1"; else shift "$_n"; echo "$1"; fi
}

# theme.env is what spark theme NAME writes
theme_load() {
    if [ -f "$THEME_ENV" ]; then
        load_env "$THEME_ENV" || return 1
    fi
    : "${THEME_BG:=default}" "${THEME_FG:=default}" "${THEME_ACCENT:=blue}" "${THEME_MUTED:=white}"
    : "${THEME_ANSI_0:=black}" "${THEME_ANSI_1:=red}" "${THEME_ANSI_2:=green}" "${THEME_ANSI_3:=yellow}"
    : "${THEME_ANSI_4:=blue}" "${THEME_ANSI_5:=magenta}" "${THEME_ANSI_6:=cyan}" "${THEME_ANSI_7:=white}"
    : "${THEME_ANSI_8:=black}" "${THEME_ANSI_9:=red}" "${THEME_ANSI_10:=green}" "${THEME_ANSI_11:=yellow}"
    : "${THEME_ANSI_12:=blue}" "${THEME_ANSI_13:=magenta}" "${THEME_ANSI_14:=cyan}" "${THEME_ANSI_15:=white}"
    for k in $THEME_KEYS; do export "${k?}"; done
    ACCENT_SLOT=$(slot_of "$THEME_ACCENT"); MUTED_SLOT=$(slot_of "$THEME_MUTED")
    ACCENT_STAR=$(slot_name "$ACCENT_SLOT"); MUTED_STAR=$(slot_name "$MUTED_SLOT")
    ACCENT_SGR=$(sgr_of "$ACCENT_SLOT"); MUTED_SGR=$(sgr_of "$MUTED_SLOT")
    export ACCENT_SLOT MUTED_SLOT ACCENT_STAR MUTED_STAR ACCENT_SGR MUTED_SGR
    hex_load
    wall_load
    pointer_load
    panel_load; win_load
}

# foot and sway's borders take rrggbb: foot gives the slots their colors
HEX_KEYS="HEX_BG HEX_FG HEX_ACCENT HEX_MUTED HEX_ANSI_0 HEX_ANSI_1 HEX_ANSI_2 HEX_ANSI_3 HEX_ANSI_4 HEX_ANSI_5 HEX_ANSI_6 HEX_ANSI_7 HEX_ANSI_8 HEX_ANSI_9 HEX_ANSI_10 HEX_ANSI_11 HEX_ANSI_12 HEX_ANSI_13 HEX_ANSI_14 HEX_ANSI_15"
VGA_HEX="000000 aa0000 00aa00 aa5500 0000aa aa00aa 00aaaa aaaaaa 555555 ff5555 55ff55 ffff55 5555ff ff55ff 55ffff ffffff"
hex_put() {   # hex_put VAR COLOR FALLBACK -> VAR as rrggbb; no subshell when lowercase
    case $2 in
        \#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) _hp=${2#\#} ;;
        \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) _hp=$(printf '%s' "${2#\#}" | tr 'A-F' 'a-f') ;;
        *) _hp=$3 ;;
    esac
    eval "$1=\$_hp"
}
hex_load() {
    i=0
    for h in $TERM_HEX; do
        eval "c=\$THEME_ANSI_$i"
        hex_put "HEX_ANSI_$i" "$c" "$h"
        i=$((i + 1))
    done
    hex_put HEX_BG "$THEME_BG" 242424
    hex_put HEX_FG "$THEME_FG" ffffff
    eval "hex_put HEX_ACCENT \"\$THEME_ACCENT\" \"\$HEX_ANSI_$ACCENT_SLOT\""
    eval "hex_put HEX_MUTED \"\$THEME_MUTED\" \"\$HEX_ANSI_$MUTED_SLOT\""
    for k in $HEX_KEYS; do export "${k?}"; done
}

# a missing picture shows the ground, never a black screen
WALL_KEYS="WALL_BG GAPS_INNER GAPS_OUTER FOOT_ALPHA BAR_ALPHA BORDER BAND_GLYPHS BAND_TITLE BAND_TERM_TITLE DROP_HEX"   # BAR_ALPHA: two hex digits; DROP_HEX: rrggbbaa
WALL_NAMES="black white gray silver navy blue teal green olive maroon red purple brown orange"   # grey reads as gray
# NAME:PALETTE:SAMPLE, SAMPLE the drawing's main color
WALL_SHIPPED="skyline:tokyonight-night:7aa2f7 fjord:nord:88c0d0 forest:everforest-dark:a7c080 sunset:gruvbox-dark:fe8019 hills:catppuccin-mocha:f5c2e7 dunes:dracula:ff79c6 orbit:dracula:bd93f9 ripples:rose-pine:ebbcba contours:selenized-dark:41c7b9 morning:solarized-light:b58900 meadow:catppuccin-latte:ea76cb kites:tokyonight-day:2e7de9 fields:gruvbox-light:d79921 grove:everforest-light:8da101 arches:rose-pine-dawn:d7827e shore:selenized-light:009c8f flight:one-light:4078f2 embers:any:d24a2a"
# lib/wallpaper.py's scenes; their palette word is every
WALL_SCENES="onsen duck reef campfire ufo pigeons garoa horizon watch problem continue crossing"
SCENE_MAKE=$REPO/lib/wallpaper.py
wall_scene() { case " $WALL_SCENES " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac; }   # wall_scene NAME -> 0 for a scene
wall_shipped() { for _e in $WALL_SHIPPED; do [ "${_e%%:*}" != "$1" ] || return 0; done; wall_scene "$1"; }   # wall_shipped NAME -> 0 for a drawing or scene
wall_shipped_names() { for _e in $WALL_SHIPPED; do printf '%s\n' "${_e%%:*}"; done; for _e in $WALL_SCENES; do printf '%s\n' "$_e"; done; }
SCENE_READY=''
scene_ready() {   # python3 with numpy is here, asked once
    [ -n "$SCENE_READY" ] || { if command -v python3 >/dev/null 2>&1 && python3 -I -c 'import numpy' >/dev/null 2>&1; then SCENE_READY=yes; else SCENE_READY=no; fi; }
    [ "$SCENE_READY" = yes ]
}
scene_still() {   # scene_still SCENE PALETTE_FILE WxH OUT.png -> the still, or false
    scene_ready || return 1
    _stn=${4%.png}.new.png   # not _ssn: scene_screens's
    if python3 -I "$SCENE_MAKE" --scene "$1" --still poster --size "$3" --png "$_stn" "$2" >/dev/null 2>&1 && [ -s "$_stn" ]; then mv "$_stn" "$4"; else rm -f "$_stn"; return 1; fi
}
wall_for_palette() { for _e in $WALL_SHIPPED; do _r=${_e#*:}; [ "${_r%%:*}" != "$1" ] || { printf '%s' "${_e%%:*}"; return 0; }; done; return 1; }   # wall_for_palette PALETTE -> its drawing, or false
wall_palette_of() { for _e in $WALL_SHIPPED; do [ "${_e%%:*}" != "$1" ] || { _r=${_e#*:}; printf '%s' "${_r%%:*}"; return 0; }; done; ! wall_scene "$1" || { printf 'every'; return 0; }; return 1; }   # wall_palette_of DRAWING -> its palette (every for a scene)
wall_path() {   # -> the picture's path
    wall_shipped "$WALLPAPER" || { printf '%s' "$WALLPAPER"; return; }
    _td=$(theme_dir "${THEME:-}")
    if [ -n "$_td" ] && [ -f "$_td/wallpaper.png" ] && [ "$(look_get "$_td" DRAWING)" = "$WALLPAPER" ]; then printf '%s' "$_td/wallpaper.png"
    elif [ -n "${THEME:-}" ] && [ "$THEME" != none ] && [ "$(wall_palette_of "$WALLPAPER")" != "$THEME" ] && [ -f "$WALL_CACHE/$WALLPAPER-$THEME.png" ]; then printf '%s' "$WALL_CACHE/$WALLPAPER-$THEME.png"
    elif wall_scene "$WALLPAPER"; then printf '%s' "$WALL_CACHE/$WALLPAPER-${THEME:-none}.png"   # no shipped still
    else printf '%s' "$REPO/gallery/wallpaper/$WALLPAPER.png"; fi
}
wall_own() { [ "$(wall_palette_of "$1")" = "${THEME:-}" ]; }   # wall_own DRAWING -> 0 when drawn for THEME
wall_role_hex() {   # wall_role_hex ROLE PALETTE_FILE -> rrggbb; ROLE: bg, fg, accent, muted, ansi_N, black, white or A+B:PCT
    case $1 in
        *+*) _wa=${1%%+*}; _wr=${1#*+}; hex_mix "$(wall_role_hex "$_wa" "$2")" "$(wall_role_hex "${_wr%%:*}" "$2")" "${_wr#*:}" ;;
        black) printf '000000' ;; white) printf 'ffffff' ;;
        *) palette_get "$2" "THEME_$(printf '%s' "$1" | tr 'a-z' 'A-Z')" | tr -d '#' | tr 'A-F' 'a-f' ;;
    esac
}
wall_recolor_sed() {   # wall_recolor_sed SVG PALETTE_FILE -> sed from the roles line, the SVG's second
    sed -n '2s/^<!-- roles: \(.*\) -->$/\1/p' "$1" | tr ';' '\n' | sed 's/^ *//' | while read -r _c _r; do
        [ -n "$_c" ] || continue
        printf 's/%s/#%s/g\n' "$_c" "$(wall_role_hex "$_r" "$2")"
    done
}
wall_recolor() { wall_recolor_sed "$1" "$2" > "$TMP/recolor.sed"; sed -f "$TMP/recolor.sed" "$1"; }   # wall_recolor SVG PALETTE_FILE -> the drawing recolored
# gdk-pixbuf's thumbnailer stands in where a distro still ships it
svg_tool() {   # -> the SVG tool here, or nothing (SPARK_SHELL_NO_SVG: none)
    [ -z "${SPARK_SHELL_NO_SVG:-}" ] || return 0
    if command -v rsvg-convert >/dev/null 2>&1; then echo rsvg-convert; elif command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1; then echo gdk-pixbuf-thumbnailer; fi
}
svg_pkg() {   # -> the package with rsvg-convert here
    case $PM in apt) echo librsvg2-bin ;; pacman) echo librsvg ;; xbps) echo librsvg-utils ;; dnf) echo librsvg2-tools ;; zypper) echo rsvg-convert ;; brew) echo librsvg ;; *) echo librsvg ;; esac
}
svg_png() {   # svg_png SVG OUT WIDTH -> a PNG WIDTH wide, whole or not there
    case $(svg_tool) in
        rsvg-convert) rsvg-convert -w "$3" -o "$2.new" "$1" 2>/dev/null ;;
        gdk-pixbuf-thumbnailer) gdk-pixbuf-thumbnailer -s "$3" "$1" "$2.new" 2>/dev/null ;;
        *) false ;;
    esac && mv "$2.new" "$2" || { rm -f "$2.new"; return 1; }
}
pic_magic() {   # pic_magic FILE -> 0 for PNG, JPEG, GIF or WebP magic
    case $(od -An -tx1 -N12 < "$1" 2>/dev/null | tr -d ' \n') in 89504e470d0a1a0a*|ffd8ff*|47494638*|52494646????????57454250) return 0 ;; *) return 1 ;; esac
}
png_size() {   # png_size FILE -> "W H" from the PNG header, else nothing
    [ "$(od -An -tx1 -N8 < "$1" 2>/dev/null | tr -d ' \n')" = 89504e470d0a1a0a ] || return 0
    od -An -tu1 -j16 -N8 < "$1" 2>/dev/null | awk 'NF == 8 { print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4, $5 * 16777216 + $6 * 65536 + $7 * 256 + $8 }'
}
pic_small() { pic_png "$1" "$2" 256; }   # pic_small PICTURE OUT -> a PNG 256 wide at most
pic_png() {   # pic_png PICTURE OUT SIZE -> a PNG within SIZE square; else false (SPARK_SHELL_NO_THUMB, SPARK_SHELL_NO_SVG)
    if [ -z "${SPARK_SHELL_NO_THUMB:-}" ] && command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1 && files_tool gdk-pixbuf-thumbnailer -s "$3" "$1" "$2.new" 2>/dev/null; then mv "$2.new" "$2"; return 0; fi
    rm -f "$2.new"
    [ -z "${SPARK_SHELL_NO_SVG:-}" ] && command -v rsvg-convert >/dev/null 2>&1 || return 1
    _pe=$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z'); case $_pe in jpg|jpeg|png|webp|gif) ;; *) return 1 ;; esac
    pic_magic "$1" || return 1   # rsvg draws an empty square for bad bytes
    _pd=$TMP/pic; rm -rf "$_pd"; mkdir -p "$_pd"; cp "$1" "$_pd/picture.$_pe" || return 1
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s"><image href="picture.%s" width="%s" height="%s" preserveAspectRatio="xMidYMid meet"/></svg>\n' "$3" "$3" "$_pe" "$3" "$3" > "$_pd/wrap.svg"
    files_tool rsvg-convert -w "$3" -h "$3" -o "$2.new" "$_pd/wrap.svg" 2>/dev/null && mv "$2.new" "$2" || { rm -f "$2.new"; return 1; }
}
wall_render() {   # wall_render DRAWING PALETTE_FILE OUT_BASE -> OUT_BASE.svg, OUT_BASE.png (3840 by 2160), or false
    mkdir_state "$(dirname "$3")"
    if wall_scene "$1"; then scene_still "$1" "$2" 3840x2160 "$3.png"; return; fi
    wall_recolor "$REPO/gallery/wallpaper/$1.svg" "$2" > "$3.svg.new" && mv "$3.svg.new" "$3.svg"
    svg_png "$3.svg" "$3.png" 3840 || { rm -f "$3.png"; return 1; }
}
wall_follow() {   # draws the wallpaper in the palette in use when missing; a row when it cannot
    wall_shipped "$WALLPAPER" || return 0
    [ -n "${THEME:-}" ] && [ "$THEME" != none ] || return 0
    _td=$(theme_dir "$THEME")
    if [ -n "$_td" ]; then [ "$(look_get "$_td" DRAWING)" = "$WALLPAPER" ] && [ -f "$_td/wallpaper.png" ] && return 0; _wb=$_td/wallpaper
    else wall_own "$WALLPAPER" && return 0; _wb=$WALL_CACHE/$WALLPAPER-$THEME; fi
    [ ! -f "$_wb.png" ] || return 0
    [ "$MODE" != dry ] || { row would wallpaper "$WALLPAPER drawn in $THEME ($_wb.png)"; return 0; }
    _pf=$(palette_file "$THEME") || return 0
    if wall_render "$WALLPAPER" "$_pf" "$_wb"; then
        [ -z "$_td" ] || look_set "$_td" DRAWING "$WALLPAPER"
        wall_load; EXPR=$(render_expr)   # later renders name the new picture
        row render wallpaper "$WALLPAPER drawn in $THEME ($_wb.png)"
    elif wall_scene "$WALLPAPER"; then row todo wallpaper "$WALLPAPER: python3 with numpy draws its picture, and it is not here (spark-shell on desktop installs it)"
    else row todo wallpaper "$WALLPAPER as drawn for $(wall_palette_of "$WALLPAPER"): rsvg-convert is not installed to draw it in $THEME (the $(svg_pkg) package)"; fi
}
wall_color() { hex_rgb "$WALLPAPER" >/dev/null; }   # WALLPAPER is #rrggbb
wall_yours() { case ${WALLPAPER:-} in ''|none|default) return 1 ;; esac; ! wall_color && ! wall_shipped "$WALLPAPER"; }   # WALLPAPER is a path; false before the config is read
wall_name() {   # -> default, a name or hex; nothing for a path
    case $WALLPAPER in default|none) echo default; return ;; esac
    if wall_shipped "$WALLPAPER"; then echo "$WALLPAPER"; return; fi
    wall_color || return 0
    for w in $WALL_NAMES; do [ "$(wall_hex "$w")" != "$(panel_lower "$WALLPAPER")" ] || { echo "$w"; return; }; done
    echo "$WALLPAPER"
}
wall_picture_ok() {   # wall_picture_ok PATH -> its real path (no link, under home, nothing hidden) or one line and exit 1
    _rp=$(realpath "$1" 2>/dev/null) && [ ! -L "$1" ] || { echo "wallpaper: $1 is not a file of yours"; return 1; }
    _hr=$(realpath "$HOME" 2>/dev/null) || _hr=$HOME
    case $_rp in "$_hr"/*) ;; *) echo "wallpaper: a picture comes from under your home"; return 1 ;; esac
    case ${_rp#"$_hr"/} in .*|*/.*) echo "wallpaper: a hidden file is not offered"; return 1 ;; esac
    [ -f "$_rp" ] && [ -r "$_rp" ] || { echo "wallpaper: $1 is not a file that can be read"; return 1; }
    case " $WALL_TYPES " in *" $(printf '%s' "${_rp##*.}" | tr 'A-Z' 'a-z') "*) ;; *) echo "wallpaper: a picture is $WALL_TYPES"; return 1 ;; esac
    path_ok "$_rp" || { echo "wallpaper: $PATH_REFUSED"; return 1; }   # the config's shape, before any write
    printf '%s\n' "$_rp"
}
WALL_TYPES='jpg jpeg png webp'   # the picker's types
WALL_GROUND_SAID="the palette's own, darker"   # the ground's column
THUMB_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/thumbs   # DRAWING-PALETTE.png for the list
thumb_palette() { if [ -n "${THEME:-}" ] && [ "$THEME" != none ] && palette_file "$THEME" >/dev/null; then printf '%s' "$THEME"; else printf none; fi; }   # -> THEME when it has a palette file, else none
wall_thumbs() {   # draws the small pictures missing or stale; quiet
    [ -n "$(svg_tool)" ] || return 0
    mkdir_state "$THUMB_DIR"; _tp=$(thumb_palette); _pf=''; [ "$_tp" = none ] || _pf=$(palette_file "$_tp")
    for _w in $(wall_shipped_names); do
        _t=$THUMB_DIR/$_w-$_tp.png
        if wall_scene "$_w"; then
            [ -n "$_pf" ] || continue
            [ ! -f "$_t" ] || [ -n "$(find "$SCENE_MAKE" -newer "$_t" 2>/dev/null)" ] || continue
            scene_still "$_w" "$_pf" 480x270 "$_t" || :; continue
        fi
        [ ! -f "$_t" ] || [ -n "$(find "$REPO/gallery/wallpaper/$_w.svg" -newer "$_t" 2>/dev/null)" ] || continue   # find -newer: -nt is not POSIX
        if [ -z "$_pf" ] || [ "$(wall_palette_of "$_w")" = "$_tp" ]; then _src=$REPO/gallery/wallpaper/$_w.svg
        else wall_recolor "$REPO/gallery/wallpaper/$_w.svg" "$_pf" > "$TMP/thumb.svg" || continue; _src=$TMP/thumb.svg; fi
        if svg_png "$_src" "$TMP/thumb.png" 480; then cp "$TMP/thumb.png" "$_t.${TMP##*/}" && mv "$_t.${TMP##*/}" "$_t"; fi   # whole or none: the dialog may be reading
    done
}
wall_there() { [ "$WALLPAPER" != none ] && [ "$WALLPAPER" != default ] && ! wall_color && [ -f "$(wall_path)" ] && [ -r "$(wall_path)" ]; }
wall_ground() {   # -> #rrggbb: HEX_BG 30% to black when dark, 8% when light
    # shellcheck disable=SC2046   # three numbers, split on purpose
    set -- $(hex_rgb "#$HEX_BG")
    if [ $(($1 + $2 + $3)) -gt 384 ]; then printf '#%s' "$(hex_mix "$HEX_BG" 000000 8)"; else printf '#%s' "$(hex_mix "$HEX_BG" 000000 30)"; fi
}
wall_hex() {   # wall_hex WORD -> #rrggbb for hex or WALL_NAMES (CSS), else false
    case $(printf '%s' "$1" | tr 'A-Z' 'a-z') in
        black) echo '#000000' ;; white) echo '#ffffff' ;; gray|grey) echo '#808080' ;;
        silver) echo '#c0c0c0' ;; navy) echo '#000080' ;; blue) echo '#0000ff' ;;
        teal) echo '#008080' ;; green) echo '#008000' ;; olive) echo '#808000' ;;
        maroon) echo '#800000' ;; red) echo '#ff0000' ;; purple) echo '#800080' ;;
        brown) echo '#a52a2a' ;; orange) echo '#ffa500' ;;
        *) hex_rgb "$1" >/dev/null || return 1; printf '%s\n' "$1" | tr 'A-F' 'a-f' ;;
    esac
}
wall_word() {   # wall_word WORD -> default, a shipped name, #rrggbb or a readable file's full path; else nothing
    case $1 in '') return 0 ;; none|default|ground) printf 'default'; return 0 ;; esac
    if wall_shipped "$1"; then printf '%s' "$1"; return 0; fi
    wall_hex "$1" && return 0
    _w=$1; _t='~'   # a quoted ~ is HOME
    case $_w in "$_t") _w=$HOME ;; "$_t/"*) _w=$HOME/${_w#"$_t/"} ;; esac
    [ -f "$_w" ] && [ -r "$_w" ] || return 0
    case $_w in /*) ;; *) _w=$(CDPATH='' cd -- "$(dirname -- "$_w")" && pwd)/$(basename -- "$_w") ;; esac
    printf '%s' "$_w"
}
alpha_hex() { awk -v a="$1" 'BEGIN { printf "%02x", int(a * 255 + 0.5) }'; }   # alpha_hex 0.85 -> d9
hex_mix() {   # hex_mix RRGGBB RRGGBB PERCENT -> rrggbb, the first PERCENT towards the second
    # shellcheck disable=SC2046   # three numbers each, split on purpose
    set -- $(hex_rgb "#$1") $(hex_rgb "#$2") "$3"
    printf '%02x%02x%02x' $(( $1 + ($4 - $1) * $7 / 100 )) $(( $2 + ($5 - $2) * $7 / 100 )) $(( $3 + ($6 - $3) * $7 / 100 ))
}
drop_hex() {   # drop_hex RRGGBB -> rrggbbaa, channels halved, alpha 80: sway halves them again, premultiplied
    rgb_of "#$1" || { printf '%s' "$1"; return 0; }
    printf '%02x%02x%02x80' $(((_R + 1) / 2)) $(((_G + 1) / 2)) $(((_B + 1) / 2))
}
wall_load() {   # WALL_KEYS from WALLPAPER and ALPHA
    # shellcheck disable=SC2034   # read by render_expr through WALL_KEYS
    if wall_there; then WALL_BG="\"$(wall_path)\" fill"
    elif wall_color; then WALL_BG="$(wall_hex "$WALLPAPER") solid_color"
    else WALL_BG="$(wall_ground) solid_color"; fi   # default, none or a missing picture
    # shellcheck disable=SC2034
    GAPS_INNER=8; GAPS_OUTER=8; FOOT_ALPHA=$ALPHA; BAR_ALPHA=$(alpha_hex "$ALPHA"); BORDER="normal 1"   # a title band and a one-pixel frame; windows 8 px apart
    BAND_GLYPHS=' &#x2715;  &#x25BD;  &#x25A1; '   # close, minimize, fill as pango character references, so the render stays ASCII: the start of every title, drawn by the compositor (the pad's GLYPH_REFS)
    BAND_TITLE='  %title'; BAND_TERM_TITLE='  terminal   %title'   # what follows the buttons, two spaces on: a window's title; the terminal's name, then the folder
    DROP_HEX=$(drop_hex "$HEX_ACCENT")   # the drop area
    for k in $WALL_KEYS; do export "${k?}"; done
}

# sway sets XCURSOR_THEME and XCURSOR_SIZE for every program
POINTER_KEYS="POINTER_NAME POINTER_SIZE"
POINTER_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icons
POINTER_THEMES="spark-white spark-black"
theme_is_dark() {   # -> 0 when HEX_BG's luminance is under half
    # shellcheck disable=SC2046   # three numbers, split on purpose
    set -- $(hex_rgb "#$HEX_BG")
    [ $(( ($1 * 299 + $2 * 587 + $3 * 114) / 1000 )) -lt 128 ]
}
pointer_load() {
    # shellcheck disable=SC2034   # read by render_expr through POINTER_KEYS
    if [ -n "$POINTER" ]; then
        POINTER_NAME=${POINTER%% *}; POINTER_SIZE=${POINTER#* }; [ "$POINTER_SIZE" != "$POINTER" ] || POINTER_SIZE=24
    elif theme_is_dark; then POINTER_NAME="spark-white"; POINTER_SIZE=$(pointer_size_for "$(look_font_size)")
    else POINTER_NAME="spark-black"; POINTER_SIZE=$(pointer_size_for "$(look_font_size)"); fi
    export POINTER_NAME POINTER_SIZE
}
pointer_size_for() { case ${1:-12} in ''|[0-9]|1[0-3]) echo 24 ;; 1[4-9]) echo 32 ;; *) echo 48 ;; esac; }   # pointer_size_for TEXT_SIZE -> 24 to 13 points, 32 to 19, 48 above
pointer_version() { sed -n 's/^VERSION = "\(.*\)".*/\1/p' "$REPO/lib/pointer.py"; }   # the version, without python3
pointer_drawn() { for _t in $POINTER_THEMES; do [ "$(cat "$POINTER_DIR/$_t/version" 2>/dev/null)" = "$(pointer_version)" ] || return 1; done; }
pointer_can() { [ "$(python3 "$REPO/lib/pointer.py" --version 2>/dev/null)" = "$(pointer_version)" ]; }   # python3 runs the generator
pointer_fresh() {   # -> "seat * xcursor_theme NAME SIZE+1; " for a drawing newer than sway's: sway reloads only for a new name or size
    _pv=$(cat "$POINTER_DIR/$POINTER_NAME/version" 2>/dev/null || :)
    [ -z "$_pv" ] || [ "$_pv" = "$(cat "$POINTER_SEEN" 2>/dev/null || :)" ] || printf 'seat * xcursor_theme %s %s; ' "$POINTER_NAME" $((POINTER_SIZE + 1))
}
pointer_seen() { _pv=$(cat "$POINTER_DIR/$POINTER_NAME/version" 2>/dev/null || :); [ -z "$_pv" ] || { mkdir_private "$STATE_DIR" && printf '%s\n' "$_pv" > "$POINTER_SEEN"; }; }   # the version sway got; a theme of yours has none

# WINDOWS as sway's workspace_layout
WIN_KEYS="WS_LAYOUT"
win_load() {
    # shellcheck disable=SC2034   # read by render_expr through WIN_KEYS
    case ${WINDOWS:-split} in tabs) WS_LAYOUT=tabbed ;; stacked) WS_LAYOUT=stacking ;; *) WS_LAYOUT=default ;; esac
    export WS_LAYOUT
}
win_words() { case ${1:-split} in split) echo 'side by side' ;; *) echo "$1" ;; esac; }   # win_words WINDOWS -> the row's words
win_said() { case ${1:-split} in tabs) echo 'in tabs' ;; *) win_words "$1" ;; esac; }   # win_said WINDOWS -> the words after "windows"
transparency_of() { awk -v a="${1:-1}" 'BEGIN { printf "%d", (1 - a) * 100 + 0.5 }'; }   # transparency_of ALPHA -> a percent

# PANEL_PAD 0x0: the dialog draws the margins
PANEL_KEYS="PANEL_SIZE PANEL_PAD PANEL_LOW PANEL_BG PANEL_HI PANEL_BAND PANEL_MUTED NOTIFY_PAD NOTIFY_WIDTH NOTIFY_HEIGHT"   # NOTIFY_*: mako's air, width and most height, pixels
panel_load() {
    # shellcheck disable=SC2034   # read by render_expr through PANEL_KEYS
    PANEL_LOW=$(hex_mix "$HEX_BG" "$HEX_FG" 4); PANEL_BG=$(hex_mix "$HEX_BG" "$HEX_FG" 9); PANEL_HI=$(hex_mix "$HEX_BG" "$HEX_FG" 18); PANEL_BAND=$(hex_mix "$PANEL_BG" "$HEX_ACCENT" 25); PANEL_PAD=0x0
    _ns=$(look_font_size); : "${_ns:=12}"
    # shellcheck disable=SC2034   # read by render_expr through PANEL_KEYS
    { NOTIFY_PAD="$_ns,$((_ns * 3 / 2))"; NOTIFY_WIDTH=$((_ns * 30)); NOTIFY_HEIGHT=$((_ns * 8)); }   # half the dialog's air, thirty cells, four lines
    # muted lifted until it reads at 4.5 to 1
    _pl=35; PANEL_MUTED=$(hex_mix "$HEX_MUTED" "$HEX_FG" "$_pl")
    while [ "$_pl" -lt 100 ] && [ "$(hex_contrast "$PANEL_MUTED" "$PANEL_BG")" -lt 450 ]; do _pl=$((_pl + 5)); PANEL_MUTED=$(hex_mix "$HEX_MUTED" "$HEX_FG" "$_pl"); done
    for k in $PANEL_KEYS; do export "${k?}"; done
}
hex_contrast() {   # hex_contrast RRGGBB RRGGBB -> WCAG contrast times 100
    awk -v a="$1" -v b="$2" 'function h(c, i) { return index("0123456789abcdef", substr(tolower(c), i, 1)) - 1 }
        function ch(c, i,   v) { v = (h(c, i) * 16 + h(c, i + 1)) / 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(c) { return 0.2126 * ch(c, 1) + 0.7152 * ch(c, 3) + 0.0722 * ch(c, 5) }
        BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }; printf "%d", (x + 0.05) / (y + 0.05) * 100 }'
}
hex_bg_sgr() {   # hex_bg_sgr rrggbb -> an SGR ground
    # shellcheck disable=SC2046   # three numbers, split on purpose
    set -- $(hex_rgb "#$1"); printf '48;2;%s;%s;%s' "$1" "$2" "$3"
}
hex_sgr() {   # hex_sgr rrggbb -> an SGR foreground
    # shellcheck disable=SC2046   # three numbers, split on purpose
    set -- $(hex_rgb "#$1"); printf '38;2;%s;%s;%s' "$1" "$2" "$3"
}

