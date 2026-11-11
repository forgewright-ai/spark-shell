# shellcheck extended-analysis=false
# ------------------------------------------------------------- the slots
# the rendered look names colors by palette slot (0-15), never by hex, so
# one file is right on the console and plain in an emulator. ACCENT and
# MUTED, hex in theme.env, become the nearest slot by RGB distance (the
# lowest on a tie); a color word is its own slot. ACCENT_SGR and MUTED_SGR
# are those slots as SGR parameters (30-37, 90-97), what spark reads from
# the SPARK_*_SGR exports to color its prompt at a tty
SLOT_KEYS="ACCENT_SLOT MUTED_SLOT ACCENT_STAR MUTED_STAR ACCENT_SGR MUTED_SGR"
hex_rgb() {   # hex_rgb #rrggbb -> "r g b" (decimal), or false
    case $1 in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;; *) return 1 ;; esac
    _h=${1#\#}; _m=${_h#??}
    printf '%d %d %d' "$((0x${_h%????}))" "$((0x${_m%??}))" "$((0x${_h#????}))"
}
rgb_of() {   # rgb_of #rrggbb -- _R _G _B its three numbers, with no subshell; false for anything else
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
sgr_of() {   # sgr_of N -> the SGR foreground parameter for slot N (30-37, 90-97)
    if [ "$1" -lt 8 ]; then echo $((30 + $1)); else echo $((82 + $1)); fi
}
slot_name() {   # slot_name N -> starship's word for slot N (black.. bright-white)
    _n=$1
    set -- black red green yellow blue purple cyan white
    if [ "$_n" -ge 8 ]; then shift $((_n - 8)); echo "bright-$1"; else shift "$_n"; echo "$1"; fi
}

# theme_load -- theme.env, as `spark theme NAME` writes it (BG, FG, ACCENT,
# MUTED and the sixteen ANSI slots); absent, color words; then the slots
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

# the desktop's hex: foot gives the slots their colors on the desktop, so
# it and sway's borders take the palette's own rrggbb; a color word is
# foot's own sixteen, so `theme none` is the terminal's colors there too
HEX_KEYS="HEX_BG HEX_FG HEX_ACCENT HEX_MUTED HEX_ANSI_0 HEX_ANSI_1 HEX_ANSI_2 HEX_ANSI_3 HEX_ANSI_4 HEX_ANSI_5 HEX_ANSI_6 HEX_ANSI_7 HEX_ANSI_8 HEX_ANSI_9 HEX_ANSI_10 HEX_ANSI_11 HEX_ANSI_12 HEX_ANSI_13 HEX_ANSI_14 HEX_ANSI_15"
VGA_HEX="000000 aa0000 00aa00 aa5500 0000aa aa00aa 00aaaa aaaaaa 555555 ff5555 55ff55 ffff55 5555ff ff55ff 55ffff ffffff"
FOOT_HEX="242424 f62b5a 47b413 e3c401 24acd4 f2affd 13c299 e6e6e6 616161 ff4d51 35d450 e9e836 5dc5f8 feabf2 24dfc4 ffffff"   # foot's defaults (the starlight theme, foot.ini(5)); its text ffffff on its ground 242424"
hex_or() {   # hex_or COLOR FALLBACK -> rrggbb, lowercase
    case $1 in
        \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) printf '%s' "${1#\#}" | tr 'A-F' 'a-f' ;;
        *) printf '%s' "$2" ;;
    esac
}
hex_put() {   # hex_put VAR COLOR FALLBACK -- VAR is what hex_or says, with no subshell for a color already in lowercase (the palettes' own)
    case $2 in
        \#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) _hp=${2#\#} ;;
        \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) _hp=$(printf '%s' "${2#\#}" | tr 'A-F' 'a-f') ;;
        *) _hp=$3 ;;
    esac
    eval "$1=\$_hp"
}
hex_load() {
    i=0
    for h in $FOOT_HEX; do
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

# the wallpaper: the ground (the palette's background a shade darker), a
# drawing, a picture of yours or a plain color. Over any the windows stand
# apart, foot as transparent as ALPHA says, each with a two-pixel clear
# edge the mouse can grab. A path that is not there falls back to the
# palette's color, never to a black screen
WALL_KEYS="WALL_BG GAPS_INNER GAPS_OUTER FOOT_ALPHA BAR_ALPHA BORDER BORDER_HEX DROP_HEX"   # BAR_ALPHA: two hex digits after the bar background over a picture, else nothing; BORDER_HEX: the edge's color, rrggbbaa; DROP_HEX: sway's focused indicator, the drop area (drop_hex)
WALL_NAMES="black white gray silver navy blue teal green olive maroon red purple brown orange"   # one name a color: grey is still read as gray, never listed twice
# the wallpapers in gallery/wallpaper/, each NAME:PALETTE:SAMPLE: the palette it was drawn for and
# its main color, the sample on its row
WALL_SHIPPED="skyline:tokyonight-night:7aa2f7 fjord:nord:88c0d0 forest:everforest-dark:a7c080 sunset:gruvbox-dark:fe8019 hills:catppuccin-mocha:f5c2e7 dunes:dracula:ff79c6 orbit:dracula:bd93f9 ripples:rose-pine:ebbcba contours:selenized-dark:41c7b9 morning:solarized-light:b58900 meadow:catppuccin-latte:ea76cb kites:tokyonight-day:2e7de9 fields:gruvbox-light:d79921 grove:everforest-light:8da101 arches:rose-pine-dawn:d7827e shore:selenized-light:009c8f flight:one-light:4078f2 embers:any:d24a2a"
# the moving scenes lib/wallpaper.py draws in any palette (palette word: every); their picture is
# the scene's still in the palette in use
WALL_SCENES="onsen duck reef campfire ufo pigeons garoa horizon watch problem continue crossing"
SCENE_MAKE=$REPO/lib/wallpaper.py
wall_scene() { case " $WALL_SCENES " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac; }   # wall_scene NAME -> 0 for a moving scene
wall_shipped() { for _e in $WALL_SHIPPED; do [ "${_e%%:*}" != "$1" ] || return 0; done; wall_scene "$1"; }   # wall_shipped NAME -> 0 for a wallpaper spark-shell ships: a drawing or a scene
wall_shipped_names() { for _e in $WALL_SHIPPED; do printf '%s\n' "${_e%%:*}"; done; for _e in $WALL_SCENES; do printf '%s\n' "$_e"; done; }
SCENE_READY=''
scene_ready() {   # -> 0 when make.py can draw here: python3 with numpy (asked once a run)
    [ -n "$SCENE_READY" ] || { if command -v python3 >/dev/null 2>&1 && python3 -I -c 'import numpy' >/dev/null 2>&1; then SCENE_READY=yes; else SCENE_READY=no; fi; }
    [ "$SCENE_READY" = yes ]
}
scene_still() {   # scene_still SCENE PALETTE_FILE WxH OUT.png -- the scene's still in that palette at that size; silent, false with no PNG
    scene_ready || return 1
    _stn=${4%.png}.new.png   # its own prefix: scene_screens holds the screen's name in _ssn
    if python3 -I "$SCENE_MAKE" --scene "$1" --still poster --size "$3" --png "$_stn" "$2" >/dev/null 2>&1 && [ -s "$_stn" ]; then mv "$_stn" "$4"; else rm -f "$_stn"; return 1; fi
}
wall_for_palette() { for _e in $WALL_SHIPPED; do _r=${_e#*:}; [ "${_r%%:*}" != "$1" ] || { printf '%s' "${_e%%:*}"; return 0; }; done; return 1; }   # wall_for_palette PALETTE -> the drawing drawn for it; false for a palette with none
wall_palette_of() { for _e in $WALL_SHIPPED; do [ "${_e%%:*}" != "$1" ] || { _r=${_e#*:}; printf '%s' "${_r%%:*}"; return 0; }; done; ! wall_scene "$1" || { printf 'every'; return 0; }; return 1; }   # wall_palette_of DRAWING -> the palette it was drawn for (any: embers, every: a scene)
wall_path() {   # -> the picture's path: the theme folder's render, the cache's when the palette is not the drawing's own, else the shipped one; a picture of yours as it is
    wall_shipped "$WALLPAPER" || { printf '%s' "$WALLPAPER"; return; }
    _td=$(theme_dir "${THEME:-}")
    if [ -n "$_td" ] && [ -f "$_td/wallpaper.png" ] && [ "$(look_get "$_td" DRAWING)" = "$WALLPAPER" ]; then printf '%s' "$_td/wallpaper.png"
    elif [ -n "${THEME:-}" ] && [ "$THEME" != none ] && [ "$(wall_palette_of "$WALLPAPER")" != "$THEME" ] && [ -f "$WALL_CACHE/$WALLPAPER-$THEME.png" ]; then printf '%s' "$WALL_CACHE/$WALLPAPER-$THEME.png"
    elif wall_scene "$WALLPAPER"; then printf '%s' "$WALL_CACHE/$WALLPAPER-${THEME:-none}.png"   # a scene's still is always drawn: there is no shipped one
    else printf '%s' "$REPO/gallery/wallpaper/$WALLPAPER.png"; fi
}
wall_own() { [ "$(wall_palette_of "$1")" = "${THEME:-}" ]; }   # wall_own DRAWING -> 0 when the palette in use is the one it was drawn for
wall_role_hex() {   # wall_role_hex ROLE PALETTE_FILE -> rrggbb: bg, fg, accent, muted, ansi_N, black, white, or A+B:PCT, the first moved PCT of the way to the second
    case $1 in
        *+*) _wa=${1%%+*}; _wr=${1#*+}; hex_mix "$(wall_role_hex "$_wa" "$2")" "$(wall_role_hex "${_wr%%:*}" "$2")" "${_wr#*:}" ;;
        black) printf '000000' ;; white) printf 'ffffff' ;;
        *) palette_get "$2" "THEME_$(printf '%s' "$1" | tr 'a-z' 'A-Z')" | tr -d '#' | tr 'A-F' 'a-f' ;;
    esac
}
wall_recolor_sed() {   # wall_recolor_sed SVG PALETTE_FILE -> the sed script that recolors the drawing: each color of its roles line (the SVG's second line) by its role
    sed -n '2s/^<!-- roles: \(.*\) -->$/\1/p' "$1" | tr ';' '\n' | sed 's/^ *//' | while read -r _c _r; do
        [ -n "$_c" ] || continue
        printf 's/%s/#%s/g\n' "$_c" "$(wall_role_hex "$_r" "$2")"
    done
}
wall_recolor() { wall_recolor_sed "$1" "$2" > "$TMP/recolor.sed"; sed -f "$TMP/recolor.sed" "$1"; }   # wall_recolor SVG PALETTE_FILE -> the drawing on stdout in that palette
# rsvg-convert draws the drawings; gdk-pixbuf's thumbnailer stands in
# where a distro still ships it (gdk-pixbuf 2.44 dropped it)
svg_tool() {   # -> the tool that draws an SVG here, or nothing (SPARK_SHELL_NO_SVG, tests: none)
    [ -z "${SPARK_SHELL_NO_SVG:-}" ] || return 0
    if command -v rsvg-convert >/dev/null 2>&1; then echo rsvg-convert; elif command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1; then echo gdk-pixbuf-thumbnailer; fi
}
svg_pkg() {   # -> the package that brings rsvg-convert on this family: what a todo row names
    case $PM in apt) echo librsvg2-bin ;; pacman) echo librsvg ;; xbps) echo librsvg-utils ;; dnf) echo librsvg2-tools ;; zypper) echo rsvg-convert ;; brew) echo librsvg ;; *) echo librsvg ;; esac
}
svg_png() {   # svg_png SVG OUT WIDTH -- OUT, a PNG WIDTH wide (the drawing's own ratio), whole or not there; false when no tool is here or it failed
    case $(svg_tool) in
        rsvg-convert) rsvg-convert -w "$3" -o "$2.new" "$1" 2>/dev/null ;;
        gdk-pixbuf-thumbnailer) gdk-pixbuf-thumbnailer -s "$3" "$1" "$2.new" 2>/dev/null ;;
        *) false ;;
    esac && mv "$2.new" "$2" || { rm -f "$2.new"; return 1; }
}
pic_magic() {   # pic_magic FILE -> 0 when its first bytes are a PNG's, a JPEG's, a GIF's or a WebP's
    case $(od -An -tx1 -N12 < "$1" 2>/dev/null | tr -d ' \n') in 89504e470d0a1a0a*|ffd8ff*|47494638*|52494646????????57454250) return 0 ;; *) return 1 ;; esac
}
png_size() {   # png_size FILE -- "W H" from a PNG's own header (no file(1) needed); nothing for another file
    [ "$(od -An -tx1 -N8 < "$1" 2>/dev/null | tr -d ' \n')" = 89504e470d0a1a0a ] || return 0
    od -An -tu1 -j16 -N8 < "$1" 2>/dev/null | awk 'NF == 8 { print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4, $5 * 16777216 + $6 * 65536 + $7 * 256 + $8 }'
}
pic_small() { pic_png "$1" "$2" 256; }   # pic_small PICTURE OUT -- OUT, a PNG of PICTURE 256 wide at most (pic_png)
pic_png() {   # pic_png PICTURE OUT SIZE -- OUT, a PNG of PICTURE SIZE on its long side at most; false when nothing here can read it (SPARK_SHELL_NO_THUMB, SPARK_SHELL_NO_SVG: tests)
    if [ -z "${SPARK_SHELL_NO_THUMB:-}" ] && command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1 && files_tool gdk-pixbuf-thumbnailer -s "$3" "$1" "$2.new" 2>/dev/null; then mv "$2.new" "$2"; return 0; fi
    rm -f "$2.new"
    [ -z "${SPARK_SHELL_NO_SVG:-}" ] && command -v rsvg-convert >/dev/null 2>&1 || return 1
    _pe=$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z'); case $_pe in jpg|jpeg|png|webp|gif) ;; *) return 1 ;; esac
    pic_magic "$1" || return 1   # rsvg draws an empty square for bytes it cannot read
    _pd=$TMP/pic; rm -rf "$_pd"; mkdir -p "$_pd"; cp "$1" "$_pd/picture.$_pe" || return 1
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s"><image href="picture.%s" width="%s" height="%s" preserveAspectRatio="xMidYMid meet"/></svg>\n' "$3" "$3" "$_pe" "$3" "$3" > "$_pd/wrap.svg"
    files_tool rsvg-convert -w "$3" -h "$3" -o "$2.new" "$_pd/wrap.svg" 2>/dev/null && mv "$2.new" "$2" || { rm -f "$2.new"; return 1; }
}
wall_render() {   # wall_render DRAWING PALETTE_FILE OUT_BASE -- OUT_BASE.svg in that palette and, where a tool draws it, OUT_BASE.png at 3840 by 2160; silent, exit 1 with no PNG
    mkdir_state "$(dirname "$3")"
    if wall_scene "$1"; then scene_still "$1" "$2" 3840x2160 "$3.png"; return; fi   # a scene's still, from make.py
    wall_recolor "$REPO/gallery/wallpaper/$1.svg" "$2" > "$3.svg.new" && mv "$3.svg.new" "$3.svg"
    svg_png "$3.svg" "$3.png" 3840 || { rm -f "$3.png"; return 1; }
}
wall_follow() {   # the drawing in use rendered in the palette in use when that is not its own and the picture is missing; a row when it cannot be
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
        wall_load; EXPR=$(render_expr)   # the renders after this name the picture just drawn
        row render wallpaper "$WALLPAPER drawn in $THEME ($_wb.png)"
    elif wall_scene "$WALLPAPER"; then row todo wallpaper "$WALLPAPER: python3 with numpy draws its picture, and it is not here (spark-shell on desktop installs it)"
    else row todo wallpaper "$WALLPAPER as drawn for $(wall_palette_of "$WALLPAPER"): rsvg-convert is not installed to draw it in $THEME (the $(svg_pkg) package)"; fi
}
wall_color() { hex_rgb "$WALLPAPER" >/dev/null; }   # WALLPAPER is a plain color, #rrggbb
wall_yours() { case ${WALLPAPER:-} in ''|none|default) return 1 ;; esac; ! wall_color && ! wall_shipped "$WALLPAPER"; }   # WALLPAPER is a picture of yours (a path, there or not); false before the config is read
wall_name() {   # -> default (the ground), a shipped wallpaper's name, a color's name from WALL_NAMES (or its hex), or nothing for a picture of yours
    case $WALLPAPER in default|none) echo default; return ;; esac
    if wall_shipped "$WALLPAPER"; then echo "$WALLPAPER"; return; fi
    wall_color || return 0
    for w in $WALL_NAMES; do [ "$(wall_hex "$w")" != "$(panel_lower "$WALLPAPER")" ] || { echo "$w"; return; }; done
    echo "$WALLPAPER"
}
wall_picture_ok() {   # wall_picture_ok PATH -> its real path when it is a picture of yours: no link, under your home, nothing hidden on the way, a regular file of a type a wallpaper takes; else one line, exit 1
    _rp=$(realpath "$1" 2>/dev/null) && [ ! -L "$1" ] || { echo "wallpaper: $1 is not a file of yours"; return 1; }
    _hr=$(realpath "$HOME" 2>/dev/null) || _hr=$HOME
    case $_rp in "$_hr"/*) ;; *) echo "wallpaper: a picture comes from under your home"; return 1 ;; esac
    case ${_rp#"$_hr"/} in .*|*/.*) echo "wallpaper: a hidden file is not offered"; return 1 ;; esac
    [ -f "$_rp" ] && [ -r "$_rp" ] || { echo "wallpaper: $1 is not a file that can be read"; return 1; }
    case " $WALL_TYPES " in *" $(printf '%s' "${_rp##*.}" | tr 'A-Z' 'a-z') "*) ;; *) echo "wallpaper: a picture is $WALL_TYPES"; return 1 ;; esac
    path_ok "$_rp" || { echo "wallpaper: $PATH_REFUSED"; return 1; }   # the config's shape for a wallpaper: said now, nothing written
    printf '%s\n' "$_rp"
}
WALL_TYPES='jpg jpeg png webp'   # the pictures the wallpaper picker offers and takes
WALL_GROUND_SAID="the palette's own, darker"   # the ground's column in the wallpaper list
THUMB_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/thumbs   # the drawings' small pictures in a palette, DRAWING-PALETTE.png, for the wallpaper list
thumb_palette() { if [ -n "${THEME:-}" ] && [ "$THEME" != none ] && palette_file "$THEME" >/dev/null; then printf '%s' "$THEME"; else printf none; fi; }   # -> the palette the small pictures are drawn in: the one in use, else none (the drawings' own colors)
wall_thumbs() {   # the drawings' small pictures in the palette in use, each drawn when missing or older than its drawing; quiet
    [ -n "$(svg_tool)" ] || return 0
    mkdir_state "$THUMB_DIR"; _tp=$(thumb_palette); _pf=''; [ "$_tp" = none ] || _pf=$(palette_file "$_tp")
    for _w in $(wall_shipped_names); do
        _t=$THUMB_DIR/$_w-$_tp.png
        if wall_scene "$_w"; then   # a scene's small picture is its still, drawn by make.py in the palette in use
            [ -n "$_pf" ] || continue
            [ ! -f "$_t" ] || [ -n "$(find "$SCENE_MAKE" -newer "$_t" 2>/dev/null)" ] || continue
            scene_still "$_w" "$_pf" 480x270 "$_t" || :; continue
        fi
        [ ! -f "$_t" ] || [ -n "$(find "$REPO/gallery/wallpaper/$_w.svg" -newer "$_t" 2>/dev/null)" ] || continue   # find -newer: test's -nt is not in every POSIX sh
        if [ -z "$_pf" ] || [ "$(wall_palette_of "$_w")" = "$_tp" ]; then _src=$REPO/gallery/wallpaper/$_w.svg   # its own palette, or none: the drawing as shipped
        else wall_recolor "$REPO/gallery/wallpaper/$_w.svg" "$_pf" > "$TMP/thumb.svg" || continue; _src=$TMP/thumb.svg; fi
        if svg_png "$_src" "$TMP/thumb.png" 480; then cp "$TMP/thumb.png" "$_t.${TMP##*/}" && mv "$_t.${TMP##*/}" "$_t"; fi   # a whole file or none: the dialog may read it meanwhile
    done
}
wall_there() { [ "$WALLPAPER" != none ] && [ "$WALLPAPER" != default ] && ! wall_color && [ -f "$(wall_path)" ] && [ -r "$(wall_path)" ]; }
wall_ground() {   # -> #rrggbb: the palette's background a shade darker, 30% of the way to black when it is dark, 8% when it is light
    # shellcheck disable=SC2046   # three numbers, split on purpose
    set -- $(hex_rgb "#$HEX_BG")
    if [ $(($1 + $2 + $3)) -gt 384 ]; then printf '#%s' "$(hex_mix "$HEX_BG" 000000 8)"; else printf '#%s' "$(hex_mix "$HEX_BG" 000000 30)"; fi
}
wall_hex() {   # wall_hex WORD -> #rrggbb, lowercase, for #rrggbb or one of WALL_NAMES (the CSS hex); false for anything else
    case $(printf '%s' "$1" | tr 'A-Z' 'a-z') in
        black) echo '#000000' ;; white) echo '#ffffff' ;; gray|grey) echo '#808080' ;;
        silver) echo '#c0c0c0' ;; navy) echo '#000080' ;; blue) echo '#0000ff' ;;
        teal) echo '#008080' ;; green) echo '#008000' ;; olive) echo '#808000' ;;
        maroon) echo '#800000' ;; red) echo '#ff0000' ;; purple) echo '#800080' ;;
        brown) echo '#a52a2a' ;; orange) echo '#ffa500' ;;
        *) hex_rgb "$1" >/dev/null || return 1; printf '%s\n' "$1" | tr 'A-F' 'a-f' ;;
    esac
}
wall_word() {   # wall_word WORD -> what WALLPAPER stores: default (none says the same), a shipped wallpaper's name, #rrggbb, or a readable file's full path; nothing for anything else
    case $1 in '') return 0 ;; none|default|ground) printf 'default'; return 0 ;; esac
    if wall_shipped "$1"; then printf '%s' "$1"; return 0; fi
    wall_hex "$1" && return 0
    _w=$1; _t='~'   # a quoted ~ is HOME, as the shell would have it
    case $_w in "$_t") _w=$HOME ;; "$_t/"*) _w=$HOME/${_w#"$_t/"} ;; esac
    [ -f "$_w" ] && [ -r "$_w" ] || return 0
    case $_w in /*) ;; *) _w=$(CDPATH='' cd -- "$(dirname -- "$_w")" && pwd)/$(basename -- "$_w") ;; esac
    printf '%s' "$_w"
}
alpha_hex() { awk -v a="$1" 'BEGIN { printf "%02x", int(a * 255 + 0.5) }'; }   # alpha_hex 0.85 -> d9
hex_mix() {   # hex_mix RRGGBB RRGGBB PERCENT -> rrggbb: the first color moved PERCENT of the way to the second
    # shellcheck disable=SC2046   # three numbers each, split on purpose
    set -- $(hex_rgb "#$1") $(hex_rgb "#$2") "$3"
    printf '%02x%02x%02x' $(( $1 + ($4 - $1) * $7 / 100 )) $(( $2 + ($5 - $2) * $7 / 100 )) $(( $3 + ($6 - $3) * $7 / 100 ))
}
drop_hex() {   # drop_hex RRGGBB -> rrggbbaa: the color at a quarter as sway's focused indicator takes it: sway halves all four channels and draws them premultiplied, so each goes in halved, alpha 80
    rgb_of "#$1" || { printf '%s' "$1"; return 0; }
    printf '%02x%02x%02x80' $(((_R + 1) / 2)) $(((_G + 1) / 2)) $(((_B + 1) / 2))
}
wall_load() {   # every wallpaper alike: the windows stand apart over it, as transparent as ALPHA says
    # shellcheck disable=SC2034   # read by render_expr through WALL_KEYS
    if wall_there; then WALL_BG="\"$(wall_path)\" fill"
    elif wall_color; then WALL_BG="$(wall_hex "$WALLPAPER") solid_color"   # a plain color is a wallpaper too
    else WALL_BG="$(wall_ground) solid_color"; fi   # the ground: default, none, or a picture that is not there
    # shellcheck disable=SC2034
    GAPS_INNER=0; GAPS_OUTER=8; FOOT_ALPHA=$ALPHA; BAR_ALPHA=$(alpha_hex "$ALPHA"); BORDER="pixel 2"; BORDER_HEX=00000000   # half the air: two windows 4 px apart, a window 10 px from the screen's edge
    DROP_HEX=$(drop_hex "$HEX_ACCENT")   # where a moving window would land: a soft tint of the accent, not a block
    for k in $WALL_KEYS; do export "${k?}"; done
}

# the pointer: the two themes lib/pointer.py draws (spark-white for a
# dark palette, spark-black for a light one) or any theme POINTER names;
# sway hands name and size to every program (XCURSOR_THEME, XCURSOR_SIZE)
POINTER_KEYS="POINTER_NAME POINTER_SIZE"
POINTER_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icons
POINTER_THEMES="spark-white spark-black"
theme_is_dark() {   # the palette's background is dark (its luminance under half)
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
pointer_size_for() { case ${1:-12} in ''|[0-9]|1[0-3]) echo 24 ;; 1[4-9]) echo 32 ;; *) echo 48 ;; esac; }   # pointer_size_for TEXT_SIZE -> the pointer's pixels: 24 up to 13 points, 32 up to 19, 48 above (the text size sizes the pointer)
pointer_version() { sed -n 's/^VERSION = "\(.*\)".*/\1/p' "$REPO/lib/pointer.py"; }   # the geometry's version, read without python3
pointer_drawn() { for _t in $POINTER_THEMES; do [ "$(cat "$POINTER_DIR/$_t/version" 2>/dev/null)" = "$(pointer_version)" ] || return 1; done; }
pointer_can() { [ "$(python3 "$REPO/lib/pointer.py" --version 2>/dev/null)" = "$(pointer_version)" ]; }   # a python3 that runs the generator (not a stub, not missing)
pointer_fresh() {   # -> "seat * xcursor_theme NAME SIZE+1; " when the drawing on disk is newer than the one a running sway loaded: sway loads a cursor theme again only for a new name or size, so one pixel up, then back
    _pv=$(cat "$POINTER_DIR/$POINTER_NAME/version" 2>/dev/null || :)
    [ -z "$_pv" ] || [ "$_pv" = "$(cat "$POINTER_SEEN" 2>/dev/null || :)" ] || printf 'seat * xcursor_theme %s %s; ' "$POINTER_NAME" $((POINTER_SIZE + 1))
}
pointer_seen() { _pv=$(cat "$POINTER_DIR/$POINTER_NAME/version" 2>/dev/null || :); [ -z "$_pv" ] || { mkdir_private "$STATE_DIR" && printf '%s\n' "$_pv" > "$POINTER_SEEN"; }; }   # the drawing a running sway was just given (a theme of yours has no version: nothing kept)

# how new windows sit: WINDOWS, as sway's workspace_layout
WIN_KEYS="WS_LAYOUT"
win_load() {
    # shellcheck disable=SC2034   # read by render_expr through WIN_KEYS
    case ${WINDOWS:-split} in tabs) WS_LAYOUT=tabbed ;; stacked) WS_LAYOUT=stacking ;; *) WS_LAYOUT=default ;; esac
    export WS_LAYOUT
}
win_words() { case ${1:-split} in split) echo 'side by side' ;; *) echo "$1" ;; esac; }   # win_words WINDOWS -> the words of the row
win_said() { case ${1:-split} in tabs) echo 'in tabs' ;; *) win_words "$1" ;; esac; }   # win_said WINDOWS -> those words after "windows", as a receipt says them
transparency_of() { awk -v a="${1:-1}" 'BEGIN { printf "%d", (1 - a) * 100 + 0.5 }'; }   # transparency_of ALPHA -> the windows' transparency, a percent

# the panel's surface: the window a shade of the background towards the
# text, the picked row a shade more, the header's band the accent at a
# quarter over it; no air of foot's own, the dialog draws its margins
PANEL_KEYS="PANEL_SIZE PANEL_PAD PANEL_BG PANEL_HI PANEL_BAND PANEL_MUTED NOTIFY_PAD NOTIFY_WIDTH NOTIFY_HEIGHT"   # NOTIFY_*: a notification's air, width and most height in pixels, from the text size (mako's config)
panel_load() {
    # shellcheck disable=SC2034   # read by render_expr through PANEL_KEYS
    PANEL_BG=$(hex_mix "$HEX_BG" "$HEX_FG" 9); PANEL_HI=$(hex_mix "$HEX_BG" "$HEX_FG" 18); PANEL_BAND=$(hex_mix "$PANEL_BG" "$HEX_ACCENT" 25); PANEL_PAD=0x0
    _ns=$(look_font_size); : "${_ns:=12}"
    # shellcheck disable=SC2034   # read by render_expr through PANEL_KEYS
    { NOTIFY_PAD="$_ns,$((_ns * 3 / 2))"; NOTIFY_WIDTH=$((_ns * 30)); NOTIFY_HEIGHT=$((_ns * 8)); }   # a small card: half the dialog's air, about thirty cells, four lines at most
    # the palette's muted lifted towards the text, 5% at a time from 35, until it reads at 4.5 to 1 on the surface
    _pl=35; PANEL_MUTED=$(hex_mix "$HEX_MUTED" "$HEX_FG" "$_pl")
    while [ "$_pl" -lt 100 ] && [ "$(hex_contrast "$PANEL_MUTED" "$PANEL_BG")" -lt 450 ]; do _pl=$((_pl + 5)); PANEL_MUTED=$(hex_mix "$HEX_MUTED" "$HEX_FG" "$_pl"); done
    for k in $PANEL_KEYS; do export "${k?}"; done
}
hex_contrast() {   # hex_contrast RRGGBB RRGGBB -> the WCAG contrast of the two colors, times 100 (450 is 4.5 to 1)
    awk -v a="$1" -v b="$2" 'function h(c, i) { return index("0123456789abcdef", substr(tolower(c), i, 1)) - 1 }
        function ch(c, i,   v) { v = (h(c, i) * 16 + h(c, i + 1)) / 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(c) { return 0.2126 * ch(c, 1) + 0.7152 * ch(c, 3) + 0.0722 * ch(c, 5) }
        BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }; printf "%d", (x + 0.05) / (y + 0.05) * 100 }'
}
hex_bg_sgr() {   # hex_bg_sgr rrggbb -> the SGR of that color as a ground
    # shellcheck disable=SC2046   # three numbers, split on purpose
    set -- $(hex_rgb "#$1"); printf '48;2;%s;%s;%s' "$1" "$2" "$3"
}
hex_sgr() {   # hex_sgr rrggbb -> the SGR of that color as text
    # shellcheck disable=SC2046   # three numbers, split on purpose
    set -- $(hex_rgb "#$1"); printf '38;2;%s;%s;%s' "$1" "$2" "$3"
}
panel_foot() {   # panel_foot ARGS... -- the desktop window as Super+d opens it: foot with dialog.ini running spark-shell dialog ARGS (PANEL_LEAD before it); before dialog.ini is rendered, the same from options
    if [ -f "$HOME/.config/foot/dialog.ini" ]; then
        # shellcheck disable=SC2086   # the leader, or nothing
        ${PANEL_LEAD:-} foot --config "$HOME/.config/foot/dialog.ini" --app-id "$PANEL_APP" -e "$REPO/spark-shell" dialog "$@"
    else
        _fc=$(foot_colors)
        # shellcheck disable=SC2086   # the leader, or nothing
        ${PANEL_LEAD:-} foot --app-id "$PANEL_APP" -T spark -W "$PANEL_SIZE" -o "pad=$PANEL_PAD" -o "$_fc.background=$PANEL_BG" -o "$_fc.alpha=1.0" -e "$REPO/spark-shell" dialog "$@"
    fi
}

