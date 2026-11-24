# shellcheck extended-analysis=false
# ---------------------------------------------- verbs: theme, font, quiet
# sets: MOTION_DIR MOTION_NOW THEME_COLOR_WORDS THEME_WORDS WORDS_TAKE
# reads: ANIMATION_NAMES CONFIG CONSOLE_AGAIN CONSOLE_COLORS CONSOLE_RGB CONSOLE_UNIT FONT_FACES GALLERY_KEYS GLYPH_FAMILIES LOOKS_DIR LOOK_FORMAT MODE NEON NEON_OLD NL OS PALETTE_DIR PALETTE_MARK PANEL_SEP PATH_REFUSED PM RENDERED REPO ROOT SCENE_MAKE STATE_DIR TAB TERMINAL_SEEN TERM_PALETTE_FORMATS THEME_ENV THEME_FILE_PICTURE_MAX THEME_KEYS TMP WALL_NAMES WALL_SCENES WALL_SHIPPED
refuse_in() { echo "spark-shell $1: $2"; exit 1; }   # refuse_in VERB SENTENCE
seat_on() { _r=$(rc_files); _r=${_r%% *}; [ -L "$HOME/$_r" ] && [ "$(readlink "$HOME/$_r")" = "$(rc_tree)/$_r" ]; }
look_now() {   # after a palette change
    for _k in $THEME_KEYS; do unset "$_k"; done; theme_load   # never the palette loaded before
    wall_follow
    look_burst
    EXPR=$(render_expr)
    seat_on || return 0
    for rel in $RENDERED; do render_one "$REPO/template/$rel" "$HOME/$rel"; done
    prompt_render
    ! desktop_wanted || { wall_missing; desktop_files; }
    [ "$MODE" = dry ] || { tmux_reload; theme_seen; }
}
prompt_render() {   # starship's config and its foot twin (16, 17: accent, muted)
    [ "$PROMPT" = starship ] || return 0
    render_one "$REPO/template/.config/starship.toml.$PROMPT_STYLE" "$HOME/.config/starship.toml"
    desktop_wanted || return 0
    _ex=$EXPR; EXPR="s|@ACCENT_STAR@|16|g${NL}s|@MUTED_STAR@|17|g${NL}$EXPR"
    render_one "$REPO/template/.config/starship.toml.$PROMPT_STYLE" "$HOME/.config/starship-foot.toml"
    EXPR=$_ex
}
verb_close() {   # verb_close SENTENCE -> a verb's last line
    if [ "$MODE" = dry ]; then dry_close
    elif [ "$todos" -gt 0 ]; then echo "Not all of it is done: the todo rows above say what is left."
    else echo "$1"; fi
}

THEME_WORDS='none show list save delete back wallpaper text transparency animation glyphs icons spacing family face workspaces motion picture gallery install preview variant screens rename duplicate restore color colors pointer clock pair portrait panel loop reel export'   # no theme may be named one
cmd_theme() {   # cmd_theme [NAME|none|show|list|WORD ARG...|"WORDS"]
    config_load
    case ${1:-show} in
        show) [ $# -le 1 ] || refuse_in theme "show takes no word"; theme_show; return ;;
        list) [ $# -le 1 ] || refuse_in theme "list takes no word"; theme_list; return ;;
        export) if [ $# -gt 1 ] || [ -z "$(theme_kind export)" ]; then
                if [ $# -lt 2 ] || [ $# -gt 3 ]; then echo "usage: spark-shell theme export NAME [$TERM_PALETTE_FORMATS|spark-theme]" >&2; return 1; fi
                if [ "${3:-}" = spark-theme ]; then theme_export_file "$2"; return; fi   # the theme itself, as a file to share
                palette_export "$2" "${3:-env}"; return
            fi ;;
        save) shift; theme_save "$@"; return ;;
        delete) shift; theme_delete "$@"; return ;;
        rename) shift; [ $# -ge 2 ] || refuse_in theme "rename NAME NEW -- which theme, and its new name?"; theme_rename "$@"; return ;;
        duplicate) shift; [ $# -ge 2 ] || refuse_in theme "duplicate NAME NEW -- which theme, and the new one's name?"; theme_duplicate "$@"; return ;;
        restore) shift; theme_restore "$@"; return ;;
        color) shift; theme_color "$@"; return ;;
        colors) shift; theme_colors "$@"; return ;;
        pointer) shift; theme_pointer "$@"; return ;;
        clock) shift; theme_clock "$@"; return ;;
        pair) shift; theme_pair "$@"; return ;;
        portrait) shift; theme_portrait "$@"; return ;;
        panel) shift; theme_panel "$@"; return ;;
        loop) shift; theme_loop "$@"; return ;;
        reel) shift; theme_reel "$@"; return ;;
        back) [ $# -le 1 ] || refuse_in theme "back takes no word"; theme_back; return ;;
        wallpaper) shift; theme_wallpaper "$@"; return ;;
        text) shift; theme_text "$@"; return ;;
        transparency) shift; theme_transparency "$@"; return ;;
        animation) shift; theme_animation "$@"; return ;;
        glyphs) shift; theme_glyphs "$@"; return ;;
        icons) shift; theme_icons "$@"; return ;;
        spacing) shift; theme_spacing "$@"; return ;;
        family) shift; theme_family "$@"; return ;;
        face) shift; theme_face "$@"; return ;;
        workspaces) refuse_in theme "the glyph family names the workspaces now -- spark-shell theme family stone, star or banner" ;;   # not a theme name
        motion) shift; theme_motion "$@"; return ;;
        picture) shift; theme_picture "$@"; return ;;
        gallery) shift; theme_gallery "$@"; return ;;
        install) shift; theme_install "$@"; return ;;
        variant) shift; theme_variant "$@"; return ;;
        screens) shift; theme_screens "$@"; return ;;
    esac
    case "$*" in *' '*) theme_from_words "$*"; return ;; esac
    [ -n "$(theme_kind "$1")" ] || refuse_in theme "no palette named $1 -- spark-shell theme list shows them"
    theme_apply "$1"
}
anim_follow() {   # anim_follow PIECE -- the dialog's animation
    [ "${DIALOG_ANIMATION:-}" != none ] && [ "${DIALOG_ANIMATION:-}" != "$1" ] || return 0
    [ "$MODE" = dry ] || config_set DIALOG_ANIMATION "$1" >/dev/null
    DIALOG_ANIMATION=$1; export DIALOG_ANIMATION
}
theme_animation_for() {   # NAME DIRECTORY -> the transition the theme requests
    if [ -n "$2" ]; then
        _taf=$(look_get "$2" ANIMATION)
        [ -z "$_taf" ] || { printf '%s' "$_taf"; return; }
        anim_for_palette "$(look_get "$2" PALETTE)"
    else anim_for_palette "$1"; fi
}
theme_apply() {   # theme_apply NAME|none [back] -- back keeps the history
    name=$1; _w=''
    _td=$(theme_dir "$name")
    if [ -n "$_td" ]; then _lw=$(look_ok "$_td") || refuse_in theme "$name cannot be used: $_lw. Nothing was changed"; fi
    [ "$name" = none ] || palette_render "$name" || refuse_in theme "$(cat "$TMP/palette.why")"
    PALETTE_RENDERED=$name   # for theme_files
    pm_detect
    _td=$(theme_dir "$name")
    if [ -n "$_td" ]; then
        _lfc=$(look_get "$_td" FACE); _lsz=$(look_get "$_td" TEXT_SIZE)
        for _k in WALLPAPER FONT ALPHA POINTER; do
            _v=$(look_get "$_td" "$_k")
            [ "$_k:$_v" != WALLPAPER:picture ] || _v=$_td/$(look_get "$_td" PICTURE)
            [ "$_k" != FONT ] || [ -z "$_lfc$_lsz" ] || _v=$(font_with "$_lfc" "$_lsz")   # format 2: face and size
            [ "$_k" != FONT ] || case $_v:$FONT in "$NEON_OLD"*:"$NEON"*) _v="$NEON${_v#"$NEON_OLD"}" ;; esac   # the old face renamed, its size kept
            [ "$_k" != FONT ] || [ -z "$_v" ] || face_word "${_v%%:*}" >/dev/null || _v="${FONT%%:*}${_v#"${_v%%:*}"}"   # a curated face only; the size always
            [ -n "$_v" ] || [ "$_k" = POINTER ] || continue
            [ "$_k" != POINTER ] || grep -q '^POINTER=' "$_td/look.env" || continue   # no POINTER line: yours stays
            eval "_cur=\$$_k"
            # shellcheck disable=SC2154   # _cur is set by the eval above
            [ "$MODE" = dry ] || [ "$_cur" = "$_v" ] || config_set "$_k" "$_v" >/dev/null
            eval "$_k=\$_v"; export "${_k?}"
        done
        bar_look_follow "$(look_get "$_td" BAR_GLYPHS)" "$(look_get "$_td" GLYPH_FAMILY)"
        case $(look_get "$_td" DIALOG_ICONS) in on|off) _li=$(look_get "$_td" DIALOG_ICONS); [ "$_li" = "$DIALOG_ICONS" ] || { [ "$MODE" = dry ] || config_set DIALOG_ICONS "$_li" >/dev/null; DIALOG_ICONS=$_li; export DIALOG_ICONS; } ;; esac
        case $(look_get "$_td" DIALOG_SPACING) in none|groups|rows) _ls=$(look_get "$_td" DIALOG_SPACING); [ "$_ls" = "$DIALOG_SPACING" ] || { [ "$MODE" = dry ] || config_set DIALOG_SPACING "$_ls" >/dev/null; DIALOG_SPACING=$_ls; export DIALOG_SPACING; } ;; esac
        case $(look_get "$_td" WALLPAPER_MOTION) in on|off) _lm=$(look_get "$_td" WALLPAPER_MOTION); [ "$_lm" = "$WALLPAPER_MOTION" ] || { [ "$MODE" = dry ] || config_set WALLPAPER_MOTION "$_lm" >/dev/null; WALLPAPER_MOTION=$_lm; export WALLPAPER_MOTION; } ;; esac
    elif [ "$name" != none ] && [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && ! wall_yours && _w=$(wall_for_palette "$name") && [ "$_w" != "$WALLPAPER" ]; then   # the palette's drawing, unless a picture of yours
        [ "$MODE" = dry ] || config_set WALLPAPER "$_w" >/dev/null
        WALLPAPER=$_w; export WALLPAPER
    else _w=''; fi
    [ "$name" = none ] || anim_follow "$(theme_animation_for "$name" "$_td")"
    [ "$MODE" = dry ] || [ "$THEME" = "$name" ] || config_set THEME "$name"
    THEME=$name; export THEME
    theme_files
    _painted=0
    look_now
    if [ "$name" = none ]; then palette_off all; terminal_off
    else palette_boot; terminal_apply; fi
    login_follow
    console_now
    if [ "$_painted" -eq 1 ]; then echo "Repainted 1 open terminal."
    elif [ "$_painted" -gt 1 ]; then echo "Repainted $_painted open terminals."; fi
    [ "${2:-}" = back ] || [ "$MODE" = dry ] || [ "$name" = none ] || kept_note theme "$name"   # none: nothing to come back to
    if [ "$name" = none ]; then verb_close "No palette: the console and the terminal use their default colors."
    elif [ -n "$_td" ]; then verb_close "The theme is $(theme_words_of "$name"): $(theme_look_words). A program that is already running, such as btop, takes it when it starts again."
    else verb_close "The palette is $name${_w:+, with $_w}. A program that is already running, such as btop, takes it when it starts again."; fi
}
wall_now() {   # -> the wallpaper's word, a theme's own picture by its role (Landscape 1), or the picture's name
    _wn=$(wall_name)
    if [ -z "$_wn" ] && wall_of_theme "${WALLPAPER:-}"; then _wnd=${WALLPAPER%/*}; _wn=$(art_named "$WALLPAPER" "${_wnd##*/}"); fi
    printf '%s' "${_wn:-$(basename "$(wall_path)")}"
}
theme_look_words() { printf '%s, text %s, transparency %s%%' "$(wall_now)" "$(look_font_size)" "$(transparency_of "$ALPHA")"; }   # -> "skyline, text 12, transparency 15%"
theme_show() {
    if [ -z "$THEME" ]; then echo "theme  unset: the palette stays as it is (spark-shell theme list shows them)"
    else echo "theme  $THEME ($CONFIG)"; fi
    if [ -f "$THEME_ENV" ]; then src=$THEME_ENV
    elif [ -n "$THEME" ] && [ "$THEME" != none ]; then src=$(palette_file "$THEME") || src=''
    else src=''; fi
    if [ -z "$src" ]; then echo "  none: the console's and the terminal's default colors"; return 0; fi
    for k in BG FG ACCENT MUTED; do printf '  %-8s %s\n' "$(printf '%s' "$k" | tr 'A-Z' 'a-z')" "$(palette_get "$src" "THEME_$k")"; done
    row8() { _l=''; for n in "$@"; do _l="$_l $(palette_get "$src" "THEME_ANSI_$n")"; done; printf '%s' "${_l# }"; }
    printf '  %-8s %s\n' ansi "$(row8 0 1 2 3 4 5 6 7)" bright "$(row8 8 9 10 11 12 13 14 15)"
    [ "$src" != "$THEME_ENV" ] || printf '  %-8s %s\n' files "theme.env and console-colors, written from the palette"
    [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || printf '  %-8s %s\n' look "$(theme_look_words)"
    _td=$(theme_dir "$THEME"); [ -z "$_td" ] || { _ws=$(look_get "$_td" WORDS); printf '  %-8s %s\n' folder "$_td (from $(look_get "$_td" PALETTE)${_ws:+: \"$_ws\"})"; }
    ! command -v jq >/dev/null 2>&1 || printf '  %-8s %s\n' art "$(art_words "$THEME")"
}
theme_list() {
    _saved=$(theme_saved_names)
    if [ -n "$_saved" ]; then
        echo "Saved themes (folders in $PALETTE_DIR):"
        for n in $_saved; do
            _td=$PALETTE_DIR/$n; _wl=$(look_get "$_td" WALLPAPER); [ "$_wl" != picture ] || _wl=$(look_get "$_td" PICTURE)
            note="$(theme_source_of "$_td") $PANEL_SEP ${_wl:-default}"; [ "$n" != "${THEME:-}" ] || note="$note, current"
            printf '  %-20s %s\n' "$n" "$note"
        done
    fi
    echo "Bundled themes:"
    core_theme_ids | while IFS= read -r n; do
        [ "$(theme_kind "$n")" = bundled ] || continue
        printf '  %-20s %s\n' "$n" "$(look_get "$(theme_dir "$n")" WALLPAPER)"
    done
    echo "The palettes (yours in $PALETTE_DIR come first):"
    { echo none; palette_names; } | while IFS= read -r n; do
        note=''
        case $n in none) note="the console's and the terminal's default colors" ;; esac
        [ ! -f "$PALETTE_DIR/$n.env" ] || note=yours
        [ -n "$note" ] || wall_yours || note=$(wall_for_palette "$n") || note=''
        [ "$n" != "${THEME:-}" ] || note="${note:+$note, }current"
        printf '  %-20s %s\n' "$n" "$note"
    done
    if [ -s "$(kept_hist theme)" ]; then
        echo "The last looks (spark-shell theme back steps through them):"
        kept_history theme | while IFS="$TAB" read -r _e _n; do [ "$_n" = none ] || printf '  %-20s %s\n' "$(theme_words_of "$_n")" "$(kept_when "$_e")"; done
    fi
    echo "spark-shell theme NAME uses one everywhere; theme save NAME keeps the look in use."
}
theme_save() {   # theme_save [NAME...]
    [ -n "${THEME:-}" ] && [ "$THEME" != none ] || refuse_in theme "no palette is in use -- spark-shell theme NAME first"
    name=$(layout_name_of "$*")
    if [ -z "$name" ]; then case $(theme_kind "$THEME") in look) name=$THEME ;; *) refuse_in theme "save NAME -- a name for this look" ;; esac; fi
    case $(theme_kind "$name") in shipped|yours) refuse_in theme "$name is a palette's name -- give the theme another" ;; esac
    _pf=$(palette_file "$THEME") || refuse_in theme "no palette named $THEME -- spark-shell theme list shows them"
    _d=${THEME_SAVE_DIR:-$PALETTE_DIR}/$name
    if [ -d "$_d" ] && [ "$name" != "$THEME" ] && [ -z "${THEME_SAVE_OVER:-}" ]; then
        if [ -t 0 ] && { : < /dev/tty; } 2>/dev/null; then
            printf 'write over the saved theme %s? [y/N] ' "$name" > /dev/tty; IFS= read -r _y < /dev/tty || _y=''
            case $_y in y|Y|yes) ;; *) refuse_in theme "$name kept as it was" ;; esac
        else refuse_in theme "$name is saved already -- spark-shell theme delete $name first, or another name"; fi
    fi
    theme_load
    _src=$(theme_dir "$THEME")
    mkdir_private "${THEME_SAVE_DIR:-$PALETTE_DIR}"; rm -rf "$_d.new"
    if [ -n "$_src" ]; then theme_folder_copy "$_src" "$_d.new" "$name" || { rm -rf "$_d.new" "$_d.new.new"; refuse_in theme "could not keep the look"; }   # its pictures, loops, reels and family come along
    else mkdir -p "$_d.new"; fi
    cp "$_pf" "$_d.new/palette.env"
    _origin=$THEME; [ -z "$_src" ] || _origin=$(look_get "$_src" PALETTE)
    _tsp=''
    {
        printf 'FORMAT=%s\nPALETTE=%s\n' "$LOOK_FORMAT" "${_origin:-$THEME}"
        _ws=''; [ -z "$_src" ] || _ws=$(look_get "$_src" WORDS); [ -z "$_ws" ] || printf 'WORDS=%s\n' "$_ws"
        if wall_shipped "$WALLPAPER"; then
            printf 'WALLPAPER=%s\nDRAWING=%s\n' "$WALLPAPER" "$WALLPAPER"
            _wp=$(wall_path); cp "$_wp" "$_d.new/wallpaper.png"; [ ! -f "${_wp%.png}.svg" ] || cp "${_wp%.png}.svg" "$_d.new/wallpaper.svg"
        elif wall_there; then
            _tsp=${WALLPAPER##*/}
            case ${_src:+$WALLPAPER} in "$_src"/*) _tso=${_src##*/}; case $_tsp in "$_tso"-*) _tsp=$name-${_tsp#"$_tso"-} ;; esac ;; *) cp "$WALLPAPER" "$_d.new/$_tsp" ;; esac   # the theme's own: copied with its folder
            printf 'WALLPAPER=picture\nPICTURE=%s\n' "$_tsp"
        else printf 'WALLPAPER=%s\n' "$WALLPAPER"; fi
        _fc=$(face_word "${FONT%%:*}") || _fc=''; [ -z "$_fc" ] || printf 'FACE=%s\n' "$_fc"   # your own face stays out
        _fs=$(look_font_size); case $_fs in [6-9]|[1-3][0-9]|40) printf 'TEXT_SIZE=%s\n' "$_fs" ;; esac   # only a size theme text sets
        printf 'ALPHA=%s\nPOINTER=%s\nANIMATION=%s\nBAR_GLYPHS=%s\nGLYPH_FAMILY=%s\nWALLPAPER_MOTION=%s\nDIALOG_ICONS=%s\nDIALOG_SPACING=%s\n' "$ALPHA" "${POINTER:-}" "$(anim_now)" "$BAR_GLYPHS" "$GLYPH_FAMILY" "$WALLPAPER_MOTION" "$DIALOG_ICONS" "$DIALOG_SPACING"
    } > "$_d.new/look.env"
    rm -rf "$_d"; mv "$_d.new" "$_d"
    echo "saved $name ($_d) -- spark-shell theme $name brings the look back"
    # nothing is drawn again
    [ "$THEME" = "$name" ] || config_set THEME "$name" >/dev/null
    THEME=$name; export THEME
    if [ -n "$_tsp" ] && [ "$WALLPAPER" != "$_d/$_tsp" ]; then   # the folder's copy from now on
        config_set WALLPAPER "$_d/$_tsp" >/dev/null; WALLPAPER=$_d/$_tsp; export WALLPAPER
        ! desktop_wanted || desktop_file_apply   # sway's file names the copy
    fi
    kept_note theme "$name"
}
theme_delete() {   # theme_delete NAME... -- its folder and history lines
    name=$(layout_name_of "$*"); [ -n "$name" ] || refuse_in theme "delete NAME -- which theme?"
    case $(theme_kind "$name") in
        saved|look) ;;
        shipped) refuse_in theme "$name is a palette spark-shell ships, not a saved theme" ;;
        bundled) refuse_in theme "$name belongs to the bundled gallery" ;;
        yours) refuse_in theme "$name is a palette file of yours ($PALETTE_DIR/$name.env): remove the file to drop it" ;;
        *) refuse_in theme "no saved theme named $name -- spark-shell theme list shows them" ;;
    esac
    [ "$name" != "${THEME:-}" ] || refuse_in theme "$name is the theme in use -- spark-shell theme NAME another first"
    kept_delete_ok theme "$name" || return 0
    if [ -n "${THEME_DELETED:-}" ]; then   # the dialog's undo brings it back
        mkdir -p "$THEME_DELETED" && rm -rf "${THEME_DELETED:?}/$name" && mv "$(theme_dir "$name")" "$THEME_DELETED/$name" || refuse_in theme "could not delete $name"
    else rm -rf "$(theme_dir "$name")"; fi
    _kh=$(kept_hist theme); [ ! -f "$_kh" ] || { awk -F '\t' -v n="$name" '$2 != n' "$_kh" > "$_kh.new" && mv "$_kh.new" "$_kh"; }
    echo "deleted $name"
}
theme_restore() {   # theme_restore NAME -- a theme deleted from the dialog, back: its undo
    _trn=$(layout_name_of "$*")
    [ -n "$_trn" ] && [ -n "${THEME_DELETED:-}" ] && [ -d "$THEME_DELETED/$_trn" ] && [ -z "$(theme_kind "$_trn")" ] || refuse_in theme "${_trn:-it} can no longer come back"
    mkdir_private "$PALETTE_DIR" && mv "$THEME_DELETED/$_trn" "$PALETTE_DIR/$_trn" || refuse_in theme "could not bring $_trn back"
    echo "$_trn is back"
}
theme_export_file() {   # theme_export_file NAME -- the theme as NAME.spark-theme in the downloads folder: its look as a shared theme sets it, its colors, its pictures with no metadata, its loops, reels and family
    _txd=$(theme_dir "$1"); [ -n "$_txd" ] || refuse_in theme "$1 is a palette, with no folder -- spark-shell theme export $1 kitty gives it for a terminal"
    case $1 in [a-z]*) ;; *) refuse_in theme "a theme file takes a name of a to z, 0 to 9 and - -- spark-shell theme duplicate $1 NEW first" ;; esac
    case $1 in *[!a-z0-9-]*) refuse_in theme "a theme file takes a name of a to z, 0 to 9 and - -- spark-shell theme duplicate $1 NEW first" ;; esac
    [ ${#1} -le 40 ] || refuse_in theme "a theme file takes a name of 40 letters at most -- spark-shell theme duplicate $1 NEW first"
    command -v python3 >/dev/null 2>&1 || refuse_in theme "python3 is not installed, and it writes a theme file"
    _txs=$TMP/theme.export/$1; rm -rf "$TMP/theme.export"; mkdir -p "$_txs"
    _txf=$(palette_file "$1") || refuse_in theme "no palette named $1"; cp "$_txf" "$_txs/palette.env"
    _txw=$(look_get "$_txd" WALLPAPER); _txp=''; [ "$_txw" != picture ] || _txp=$(look_get "$_txd" PICTURE)
    {   printf 'FORMAT=%s\n' "$LOOK_FORMAT"
        for _txk in $GALLERY_KEYS; do
            case $_txk in FORMAT) continue ;; PICTURE) _txv=$_txp ;; *) _txv=$(look_get "$_txd" "$_txk") ;; esac
            [ "$_txk" != FACE ] || [ -n "$_txv" ] || _txv=$(face_word "$(look_get "$_txd" FONT | sed 's/:.*//')") || _txv=''
            [ -z "$_txv" ] || printf '%s=%s\n' "$_txk" "$_txv"
        done
    } > "$_txs/look.env"
    for _txf in "$_txd"/*; do
        _txb=${_txf##*/}; [ -f "$_txf" ] && [ ! -L "$_txf" ] || continue
        case $_txb in
            look.env|palette.env) ;;
            family.json|"$1"-landscape-[1-9].mp4|"$1"-portrait.mp4|"$1"-dialog-open.webp|"$1"-dialog-close.webp) cp "$_txf" "$_txs/$_txb" ;;
            "$1"-landscape-[1-9].jpg|"$1"-landscape-[1-9].png|"$1"-portrait.jpg|"$1"-portrait.png|"$_txp")
                python3 -I "$REPO/lib/look.py" bare "$_txf" "$_txs/$_txb" 2>"$TMP/theme.why" || refuse_in theme "$1 cannot be shared: its $_txb is $(head -1 "$TMP/theme.why" | cut -c1-80)" ;;
            *) ;;   # a drawing's copy: the other side draws its own
        esac
    done
    if [ -f "$_txs/family.json" ]; then   # the variants every spark-shell has, and itself; a theme of the sender's own stays behind
        jq -r '.variants[].theme' "$_txs/family.json" 2>/dev/null | while IFS= read -r _txt; do
            [ "$_txt" != "$1" ] || continue; case $(theme_kind "$_txt") in shipped|bundled) ;; *) printf '%s\n' "$_txt" ;; esac; done > "$TMP/theme.gone"
        [ ! -s "$TMP/theme.gone" ] || { jq --rawfile gone "$TMP/theme.gone" '.variants |= with_entries(select(.value.theme as $t | ($gone | split("\n") | index([$t])) | not))' "$_txs/family.json" > "$TMP/theme.family" && mv "$TMP/theme.family" "$_txs/family.json"; }
    fi
    gallery_theme_ok "$_txs" "$1" > "$TMP/theme.why" || refuse_in theme "$1 cannot be shared: $(cat "$TMP/theme.why")"
    python3 -I "$REPO/lib/look.py" pack "$_txs" "$TMP/theme.export.tar" 2>"$TMP/theme.why" || refuse_in theme "$1 cannot be shared: $(head -1 "$TMP/theme.why")"
    downloads_keep "$TMP/theme.export.tar" "$1" spark-theme || refuse_in theme "the downloads folder cannot take $1.spark-theme"
    rm -rf "$TMP/theme.export" "$TMP/theme.export.tar"
}
theme_new_name() {   # theme_new_name WORDS... -- _tnn the name a theme of yours takes, free and no palette's; else one line and exit
    _tnn=$(layout_name_of "$*"); [ -n "$_tnn" ] || refuse_in theme "a theme's name is letters and digits"
    case " $THEME_WORDS " in *" $_tnn "*) refuse_in theme "$_tnn is a word of spark-shell theme, so no theme can go by it" ;; esac
    [ -z "$(theme_kind "$_tnn")" ] || refuse_in theme "$_tnn is taken -- another name"
}
theme_folder_copy() {   # theme_folder_copy DIR NEWDIR NEW -- a theme's folder as another's: plain files alone, its own (DIR's name-*) named NEW-*, its look and family saying so
    _tco=${1##*/}; rm -rf "$2.new"; mkdir -p "$2.new" || return 1
    for _tcf in "$1"/*; do
        [ -f "$_tcf" ] && [ ! -L "$_tcf" ] || continue
        _tcb=${_tcf##*/}; case $_tcb in "$_tco"-*) _tcb=$3-${_tcb#"$_tco"-} ;; esac
        cp "$_tcf" "$2.new/$_tcb" || return 1
    done
    if [ -f "$2.new/look.env" ]; then sed "s|^PICTURE=$_tco-|PICTURE=$3-|" "$2.new/look.env" > "$2.new/look.new" && mv "$2.new/look.new" "$2.new/look.env" || return 1; fi
    if [ -f "$2.new/family.json" ]; then   # the family names the new theme and its files; a variant that is another theme stays
        # its files' names alone: a new name that begins with the old one (NAME-changed) is renamed once
        jq --arg o "$_tco" --arg l "$(theme_label "$_tco")" --arg n "$3" 'def ren: if type == "string" and startswith($o + "-") then $n + "-" + ltrimstr($o + "-") else . end;
            .variants |= map_values((if has("portrait") then .portrait |= ren else . end) | (if has("panels") then .panels |= map_values(map(map_values(ren))) else . end)
                                     | (if .theme == $o or .theme == $l then .theme = $n else . end))
            | .id = $n | .title = $n' "$2.new/family.json" > "$2.new/family.new" \
            && mv "$2.new/family.new" "$2.new/family.json" || return 1
    fi
    mv "$2.new" "$2"
}
theme_editable() {   # -- _ted the folder of the theme in use to change: one of yours as it is; a bundled theme or a palette kept first as a look of its own, NAME-changed, until it is saved
    case $(theme_kind "${THEME:-none}") in
        saved|look) _ted=$(theme_dir "$THEME"); return 0 ;;
        ''|none) refuse_in theme "no theme is in use -- spark-shell theme NAME first" ;;
    esac
    _tek=$(theme_label "$THEME")-changed
    THEME_SAVE_DIR=$LOOKS_DIR; THEME_SAVE_OVER=1; theme_save "$_tek" >/dev/null; THEME_SAVE_DIR=''; THEME_SAVE_OVER=''
    _ted=$LOOKS_DIR/$_tek
}
THEME_COLOR_WORDS='background:BG text:FG accent:ACCENT muted:MUTED black:ANSI_0 red:ANSI_1 green:ANSI_2 yellow:ANSI_3 blue:ANSI_4 magenta:ANSI_5 cyan:ANSI_6 white:ANSI_7 bright-black:ANSI_8 bright-red:ANSI_9 bright-green:ANSI_10 bright-yellow:ANSI_11 bright-blue:ANSI_12 bright-magenta:ANSI_13 bright-cyan:ANSI_14 bright-white:ANSI_15'   # the 20 colors by their words, in the palette's order
theme_color() {   # theme_color WORD COLOR -- one of the 20 colors of the theme in use; its contrast on the ground said when it reads poorly
    _tck=''; for _e in $THEME_COLOR_WORDS; do [ "${_e%%:*}" != "${1:-}" ] || _tck=THEME_${_e#*:}; done
    [ -n "$_tck" ] || refuse_in theme "color takes a color's word ($(printf '%s' "$THEME_COLOR_WORDS" | sed 's/:[A-Z_0-9]*//g; s/ /, /g')), then #rrggbb"
    _tcv=$(wall_hex "${2:-}") || refuse_in theme "$1 takes #rrggbb or a color's name"
    theme_editable
    { grep -v "^$_tck=" "$_ted/palette.env"; printf '%s=%s\n' "$_tck" "$_tcv"; } > "$_ted/palette.env.new" && mv "$_ted/palette.env.new" "$_ted/palette.env" || refuse_in theme "could not keep $1"
    theme_apply "$THEME" >/dev/null
    echo "$1 $_tcv$(color_contrast_said "$_ted/palette.env" "$_tck")"
}
color_contrast_said() {   # color_contrast_said PALETTE KEY -> ", 3.2:1 on the ground, hard to read" when text in that color, or on it, reads poorly; else nothing
    _ccb=$(palette_get "$1" THEME_BG)
    case $2 in THEME_ANSI_0|THEME_ANSI_8) return 0 ;; THEME_BG) _ccv=$(palette_get "$1" THEME_FG) ;; *) _ccv=$(palette_get "$1" "$2") ;; esac
    _ccr=$(hex_contrast "${_ccv#\#}" "${_ccb#\#}" 2>/dev/null) || return 0
    case $_ccr in ''|*[!0-9]*) return 0 ;; esac
    [ "$_ccr" -lt 450 ] || return 0
    printf ', %s.%s:1 on the ground, hard to read' "$((_ccr / 100))" "$(( (_ccr % 100) / 10 ))"
}
theme_colors() {   # theme_colors NAME -- the theme in use in another theme's colors, the rest as it is
    _tcp=$(palette_file "${1:-}") || refuse_in theme "no theme named ${1:-?} -- spark-shell theme list shows them"
    theme_editable
    [ "$_tcp" = "$_ted/palette.env" ] || cp "$_tcp" "$_ted/palette.env" || refuse_in theme "could not take the colors of $1"
    look_set "$_ted" PALETTE "$1"
    theme_apply "$THEME" >/dev/null
    echo "the colors of $(theme_label "$1")"
}
theme_pointer() {   # theme_pointer NAME [SIZE]|default -- the pointer of the look in use: a cursor theme and its size, or spark's own
    case ${1:-} in '') echo "pointer ${POINTER:-default} $PANEL_SEP default, or a cursor theme and its size"; return ;; default) _tpv='' ;; *) _tpv=$1${2:+ $2} ;; esac
    pointer_ok "$_tpv" || refuse_in theme "pointer takes default, or a cursor theme's name and its size in pixels (Adwaita 32)"
    config_locked config_edit POINTER "$_tpv"; POINTER=$_tpv; export POINTER
    case $(theme_kind "${THEME:-none}") in saved|look) look_set "$(theme_dir "$THEME")" POINTER "$_tpv" ;; esac
    [ "$MODE" = dry ] || look_apply >/dev/null 2>&1 || :
    echo "pointer ${_tpv:-default}"
}
theme_family_edit() {   # theme_family_edit JQ [JQ ARGS...] -- the theme in use's own family file changed by JQ ($me its name, $v its variant), made first with the theme its one variant; refused whole when it is no family this spark-shell reads
    theme_editable; _tff=$_ted/family.json; _tfn=${_ted##*/}
    if [ -f "$_tff" ]; then cp "$_tff" "$TMP/family.was"
    else
        rm -f "$TMP/family.was"; _tfa=$(art_of "$THEME")
        jq -n --arg n "$_tfn" --arg v "$(printf '%s' "$_tfa" | jq -r .variant)" --arg m "$(printf '%s' "$_tfa" | jq -r .media)" \
            '{format: 1, id: $n, title: $n, media: $m, variants: {($v): {theme: $n}}}' > "$_tff" || refuse_in theme "could not make the theme's family"
    fi
    _tfj=$1; shift
    if ! jq "$@" --arg me "$_tfn" --arg v "$(art_of "$THEME" | jq -r .variant)" "$_tfj" "$_tff" > "$_tff.new" || ! mv "$_tff.new" "$_tff"; then theme_family_back; refuse_in theme "could not change the theme's family"; fi
    _tfw=$(family_why "$_tff") || { theme_family_back; refuse_in theme "not changed: $_tfw"; }
}
theme_family_back() { if [ -f "$TMP/family.was" ]; then mv "$TMP/family.was" "$_tff"; else rm -f "$_tff"; fi; rm -f "$_tff.new"; }   # the family as it was
theme_clock() {   # theme_clock on|off -- the clock over the art on the idle screen and the lock
    case ${1:-} in on|off) ;; *) refuse_in theme "clock takes on or off" ;; esac
    theme_family_edit '.clock = ($c == "on")' --arg c "$1"
    echo "the clock over the art $1"
}
theme_pair() {   # theme_pair NAME|none -- the theme in use's other variant: a theme here in the other light, or none
    case ${1:-} in '') refuse_in theme "pair takes a theme in the other light, or none" ;; none) _tpo=''; _tpw='' ;; *) _tpo=$1
        case $(theme_kind "$_tpo") in ''|none) refuse_in theme "no theme named $_tpo -- spark-shell theme list shows them" ;; esac
        _tpw=$(art_variant "$_tpo")
        [ "$_tpw" != "$(art_of "${THEME:-none}" | jq -r .variant)" ] || refuse_in theme "$_tpo is $_tpw too: a pair is one dark and one light" ;;
    esac
    theme_family_edit '.variants |= with_entries(select(.value.theme == $me)) | if $o == "" then . else .variants[$w] = {theme: $o} end' --arg o "$_tpo" --arg w "$_tpw"
    if [ -n "$_tpo" ]; then echo "its $_tpw variant is $_tpo -- spark-shell theme variant $_tpw"; else echo "no other variant"; fi
}
theme_take() {   # theme_take FILE ROLE picture|loop|reel -- FILE checked, copied into the theme's folder as NAME-ROLE.EXT (the role's older file of that kind gone); _tkf its name
    case $3 in picture) _tkw=$(gallery_picture_ok "$1" "$THEME_FILE_PICTURE_MAX" 2>&1) ;; loop) _tkw=$(media_ok "$1" mp4) ;; reel) _tkw=$(media_ok "$1" webp) ;; esac || refuse_in theme "${1##*/} not taken: ${_tkw#its picture is }"   # a picture is the theme's own 4K still, as a theme file holds it
    _tke=$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z'); [ "$_tke" != jpeg ] || _tke=jpg
    _tkn=${_ted##*/}
    case $3 in picture) for _e in jpg png; do rm -f "$_ted/$_tkn-$2.$_e"; done ;; esac
    _tkf=$_tkn-$2.$_tke; cp "$1" "$_ted/$_tkf" || refuse_in theme "could not copy ${1##*/}"
}
theme_portrait() {   # theme_portrait PICTURE|none -- the picture a turned screen shows, copied into the theme as NAME-portrait
    theme_editable
    if [ "${1:-}" = none ]; then for _e in jpg png; do rm -f "$_ted/${_ted##*/}-portrait.$_e"; done; _tkf=''
    else [ -n "${1:-}" ] || refuse_in theme "portrait takes a picture, or none"; theme_take "$1" portrait picture; fi
    theme_family_edit 'if $f == "" then del(.variants[$v].portrait) else .variants[$v].portrait = $f end' --arg f "$_tkf"
    theme_apply "$THEME" >/dev/null
    if [ -n "$_tkf" ]; then echo "a turned screen shows $_tkf"; else echo "a turned screen shows the art fitted"; fi
}
theme_panel() {   # theme_panel 2|3 PICTURE|none -- the picture the second or third screen from the left shows, copied in as NAME-landscape-N; the theme's picture leads
    case ${1:-} in 2|3) ;; *) refuse_in theme "panel takes 2 or 3, then a picture or none" ;; esac
    theme_editable; _tpl=$(look_get "$_ted" PICTURE); _tpn=${_ted##*/}
    [ "$(look_get "$_ted" WALLPAPER)" = picture ] && [ -n "$_tpl" ] || refuse_in theme "panels follow a picture of the theme's own -- spark-shell theme wallpaper PICTURE first"
    if [ "${2:-}" = none ]; then for _e in jpg png; do rm -f "$_ted/$_tpn-landscape-$1.$_e"; done
    else [ -n "${2:-}" ] || refuse_in theme "panel $1 takes a picture, or none"; theme_take "$2" "landscape-$1" picture; fi
    _tp2=''; _tp3=''; for _e in jpg png; do [ ! -f "$_ted/$_tpn-landscape-2.$_e" ] || _tp2=$_tpn-landscape-2.$_e; [ ! -f "$_ted/$_tpn-landscape-3.$_e" ] || _tp3=$_tpn-landscape-3.$_e; done
    theme_family_edit '.variants[$v].panels = ((if $p2 == "" then {} else {"2": [{landscape: $l}, {landscape: $p2}]} end)
            + (if $p2 == "" or $p3 == "" then {} else {"3": [{landscape: $l}, {landscape: $p2}, {landscape: $p3}]} end))
        | if .variants[$v].panels == {} then del(.variants[$v].panels) else . end' --arg l "$_tpl" --arg p2 "$_tp2" --arg p3 "$_tp3"
    theme_apply "$THEME" >/dev/null
    if [ -z "$_tp2" ]; then echo "no panels: each screen shows the art"; elif [ -z "$_tp3" ]; then echo "panels for 2 screens"; else echo "panels for 2 and 3 screens"; fi
}
theme_loop() {   # theme_loop ROLE LOOP|none -- a loop for one of the theme's own pictures (landscape-1, portrait), copied in beside it
    theme_editable; _tlp=''
    for _tlf in "$_ted"/*.jpg "$_ted"/*.png; do [ -f "$_tlf" ] || continue; _tlb=${_tlf##*/}; _tlb=${_tlb%.*}; case ${1:-} in "$_tlb"|"${_tlb#"${_ted##*/}"-}") _tlp=$_tlf ;; esac; done
    [ -n "$_tlp" ] || refuse_in theme "no picture of the theme's own is ${1:-?} -- spark-shell theme screens shows them"
    if [ "${2:-}" = none ]; then rm -f "${_tlp%.*}.mp4"; _tld='still'
    else _tlw=$(media_ok "${2:-}" mp4) || refuse_in theme "${2##*/} not taken: $_tlw"; cp "$2" "${_tlp%.*}.mp4" || refuse_in theme "could not copy ${2##*/}"; _tld='a loop'; fi
    theme_apply "$THEME" >/dev/null
    echo "${_tlp##*/}: $_tld"
}
theme_reel() {   # theme_reel open|close REEL|none -- the dialog's own opening or closing for the theme, an animated WebP copied in as NAME-dialog-open; with both, it plays its own
    case ${1:-} in open|close) ;; *) refuse_in theme "reel takes open or close, then an animated WebP or none" ;; esac
    theme_editable; _trn=${_ted##*/}
    if [ "${2:-}" = none ]; then rm -f "$_ted/$_trn-dialog-$1.webp"
    else [ -n "${2:-}" ] || refuse_in theme "reel $1 takes an animated WebP, or none"; theme_take "$2" "dialog-$1" reel; fi
    if [ -f "$_ted/$_trn-dialog-open.webp" ] && [ -f "$_ted/$_trn-dialog-close.webp" ]; then
        look_set "$_ted" ANIMATION own; config_locked config_edit DIALOG_ANIMATION own; DIALOG_ANIMATION=own; export DIALOG_ANIMATION
        echo "the theme plays its own opening and closing"
    else
        if [ "$(look_get "$_ted" ANIMATION)" = own ]; then
            _tra=$(anim_for_palette "$(look_get "$_ted" PALETTE)"); look_set "$_ted" ANIMATION "$_tra"
            config_locked config_edit DIALOG_ANIMATION "$_tra"; DIALOG_ANIMATION=$_tra; export DIALOG_ANIMATION
        fi
        echo "the $1 reel ${2:+set}; the theme plays its own once both are there"
    fi
}
theme_duplicate() {   # theme_duplicate NAME NEW... -- any theme as a new one of yours, to change: its folder copied, or a palette's look written
    _dpf=$1; shift
    _dpk=$(theme_kind "$_dpf"); [ -n "$_dpk" ] && [ "$_dpk" != none ] || refuse_in theme "no theme named $_dpf -- spark-shell theme list shows them"
    theme_new_name "$@"; _dpt=$_tnn; mkdir_private "$PALETTE_DIR"
    _dpd=$(theme_dir "$_dpf")
    if [ -n "$_dpd" ]; then theme_folder_copy "$_dpd" "$PALETTE_DIR/$_dpt" "$_dpt" || { rm -rf "$PALETTE_DIR/$_dpt.new"; refuse_in theme "could not copy $_dpf"; }
    else
        _dpp=$(palette_file "$_dpf") || refuse_in theme "no palette named $_dpf"
        _dpn=$PALETTE_DIR/$_dpt; rm -rf "$_dpn.new"; mkdir -p "$_dpn.new" && cp "$_dpp" "$_dpn.new/palette.env" || refuse_in theme "could not copy $_dpf"
        { printf 'FORMAT=%s\nPALETTE=%s\n' "$LOOK_FORMAT" "$_dpf"; _dpw=$(wall_for_palette "$_dpf" 2>/dev/null) && printf 'WALLPAPER=%s\nDRAWING=%s\n' "$_dpw" "$_dpw"; } > "$_dpn.new/look.env"
        mv "$_dpn.new" "$_dpn" || refuse_in theme "could not copy $_dpf"
    fi
    echo "$_dpt is a copy of $(theme_label "$_dpf") -- spark-shell theme $_dpt uses it"
}
theme_rename() {   # theme_rename NAME NEW... -- a theme of yours by a new name: its folder and its own files, its history lines, the config when in use
    _rnf=$1; shift
    case $(theme_kind "$_rnf") in
        saved) ;;
        look) refuse_in theme "$_rnf is not saved yet -- spark-shell theme save NAME keeps it" ;;
        shipped|bundled) refuse_in theme "$_rnf comes with spark-shell -- spark-shell theme duplicate $_rnf NEW makes it yours" ;;
        *) refuse_in theme "no theme of yours named $_rnf" ;;
    esac
    theme_new_name "$@"; _rnt=$_tnn; _rnd=$(theme_dir "$_rnf")
    theme_folder_copy "$_rnd" "$PALETTE_DIR/$_rnt" "$_rnt" || { rm -rf "$PALETTE_DIR/$_rnt.new"; refuse_in theme "could not rename $_rnf"; }
    rm -rf "$_rnd"
    _kh=$(kept_hist theme); [ ! -f "$_kh" ] || { awk -F '\t' -v o="$_rnf" -v n="$_rnt" 'BEGIN { OFS = FS } $2 == o { $2 = n } 1' "$_kh" > "$_kh.new" && mv "$_kh.new" "$_kh"; }
    if [ "$_rnf" = "${THEME:-}" ]; then   # in use: the config names it, and its picture by the new name
        config_locked config_edit THEME "$_rnt"; THEME=$_rnt; export THEME
        case $WALLPAPER in "$_rnd"/*) _rnw=${WALLPAPER#"$_rnd"/}; case $_rnw in "$_rnf"-*) _rnw=$_rnt-${_rnw#"$_rnf"-} ;; esac
            WALLPAPER=$PALETTE_DIR/$_rnt/$_rnw; export WALLPAPER; config_locked config_edit WALLPAPER "$WALLPAPER" ;; esac
        [ "$MODE" = dry ] || look_apply >/dev/null 2>&1 || :
    fi
    echo "renamed $_rnf to $_rnt"
}
theme_back() {   # one look further back each call
    while :; do
        _n=$(kept_back theme "${THEME:-}") || refuse_in theme "no look before this one in the last ten"
        [ "$_n" != none ] && palette_file "$_n" >/dev/null && break   # gone looks and none skipped
    done
    echo "back to $(theme_words_of "$_n")"
    theme_apply "$_n" back
}
theme_wallpaper() {   # theme_wallpaper [PATH|DRAWING|COLOR|default]
    [ "$OS" != Darwin ] || refuse_in theme "not on macOS, which has its own desktop"
    theme_load   # for the ground's hex
    if [ -z "${1:-}" ]; then
        if [ "$WALLPAPER" = default ] || [ "$WALLPAPER" = none ]; then echo "wallpaper default -- the ground, the palette's background a shade darker ($(wall_ground)); it follows the palette"
        elif wall_color; then echo "wallpaper $WALLPAPER -- a plain color; a palette with a drawing of its own replaces it"
        elif wall_there; then case $(wall_path) in "$REPO"/*|"$WALLPAPER") echo "wallpaper $WALLPAPER" ;; *) echo "wallpaper $WALLPAPER -- drawn in $THEME" ;; esac
        else echo "wallpaper $(wall_path) -- missing, the ground instead"; fi
        return
    fi
    [ $# -eq 1 ] || refuse_in theme "one wallpaper at a time: spark-shell theme wallpaper X"
    want=$(wall_word "$1")
    [ -n "$want" ] || refuse_in theme "$1 is not a readable file or a color. Give a picture's path, default (the ground), one of the drawings ($(wall_shipped_names | paste -sd ' ' - | sed 's/ /, /g')), #rrggbb or one of these colors: $(printf '%s' "$WALL_NAMES" | sed 's/ /, /g')"
    [ "$DESKTOP" = sway ] || refuse_in theme "DESKTOP=$DESKTOP -- spark-shell on desktop first"
    wall_value_ok "$want" || refuse_in theme "$PATH_REFUSED"   # the config would refuse it later
    config_set WALLPAPER "$want"
    WALLPAPER=$want; export WALLPAPER
    wall_follow
    look_apply
    login_follow
    _tr="the windows keep their transparency, $(transparency_of "$ALPHA")%"; [ "$(transparency_of "$ALPHA")" -ne 0 ] || _tr="the windows are solid (spark-shell theme transparency N)"
    if [ "$1" = none ]; then echo "the ground is back: none is the ground now, and $_tr"
    elif [ "$want" = default ]; then echo "the ground is back -- the palette's background a shade darker, and it follows the palette"
    elif wall_color; then echo "a running sway shows $want now, and $_tr; a palette with a drawing of its own replaces it"
    elif wall_shipped "$want"; then case $(wall_path) in "$REPO"/*) _dr='' ;; *) _dr=", drawn in $THEME" ;; esac; echo "a running sway shows $want now$_dr -- it follows the palette: a palette with a drawing of its own brings that one"
    else echo "a running sway shows it now, and $_tr"; fi
}
theme_text() {   # theme_text [N|bigger|smaller] -- the pointer follows
    _sz=$(look_font_size); [ -n "$_sz" ] || refuse_in theme "FONT=$FONT has no size to change (the config)"
    [ -n "${1:-}" ] || { echo "text $_sz $PANEL_SEP the pointer $(pointer_size_for "$_sz") pixels"; return; }
    case $1 in bigger|smaller) ;; [6-9]|[1-3][0-9]|40) ;; *) refuse_in theme "text takes a size, 6 to 40, or bigger or smaller" ;; esac
    text_step "$1" || exit 1
}
text_step() {   # text_step N|bigger|smaller -> the receipt; 1 when refused
    _sz=$(look_font_size); [ -n "$_sz" ] || { echo "FONT=$FONT has no size to change (the config)"; return 1; }
    case $1 in bigger) _new=$((_sz + 1)) ;; smaller) _new=$((_sz - 1)) ;; *) _new=$1 ;; esac
    [ "$_new" -ge 6 ] && [ "$_new" -le 40 ] || { echo "text size $_sz stays (6 to 40)"; return 1; }
    _f=$(printf '%s' "$FONT" | sed "s/size=$_sz/size=$_new/")
    config_set FONT "$_f" >/dev/null; FONT=$_f; export FONT; look_apply; login_follow >/dev/null 2>&1 || :
    echo "text at $_new $PANEL_SEP new windows and the bar take it; the pointer $(pointer_size_for "$_new") pixels"
}
theme_face() {   # theme_face [neon|argon|xenon|radon|krypton]
    [ -n "${1:-}" ] || { echo "face $(face_word "${FONT%%:*}" || printf '%s' "${FONT%%:*}") $PANEL_SEP neon, argon, xenon, radon or krypton"; return; }
    [ $# -eq 1 ] || refuse_in theme "face takes one word: neon, argon, xenon, radon or krypton"
    face_step "$1" || exit 1
}
face_step() {   # face_step NAME -> the receipt; 1 when refused
    case " $FONT_FACES " in *" $1 "*) ;; *) echo "face takes neon, argon, xenon, radon or krypton"; return 1 ;; esac
    [ "$OS" != Darwin ] || { echo "on a Mac the text is Terminal.app's: spark-shell font FACE SIZE"; return 1; }
    _fn=$(face_name "$1")
    [ "${FONT%%:*}" != "$_fn" ] || { echo "the text is in $1 already"; return 1; }
    _f="$_fn${FONT#"${FONT%%:*}"}"   # the face swapped, the rest kept
    config_set FONT "$_f" >/dev/null; FONT=$_f; export FONT; look_apply; login_follow >/dev/null 2>&1 || :
    if [ "$1" = neon ] || face_ours "$1"; then echo "text in $1 $PANEL_SEP new windows and the bar take it"
    else echo "text in $1 $PANEL_SEP from spark-shell on, which installs it; neon until then"; fi
}
theme_animation() {   # theme_animation [NAME|none|next|back] -- the dialog's transitions
    [ -n "${1:-}" ] || { echo "animation $(anim_now) $PANEL_SEP none, $(printf '%s' "$ANIMATION_NAMES" | sed 's/ /, /g')"; return; }
    [ $# -eq 1 ] || refuse_in theme "animation takes one word"
    anim_step "$1" || exit 1
}
anim_step() {   # anim_step NAME|none|next|back -> the receipt; 1 when refused
    # shellcheck disable=SC2086   # the names, a word each, on purpose
    case $1 in
        next|back) _an=$(printf '%s\n' none $ANIMATION_NAMES | awk -v c="$(anim_now)" -v d="$1" '{ n[NR] = $0; if ($0 == c) i = NR } END { if (!i) i = 1; print n[d == "next" ? i % NR + 1 : (i + NR - 2) % NR + 1] }') ;;
        own) anim_folder own '' >/dev/null || { echo "the theme has no opening and closing of its own -- spark-shell theme reel open|close FILE"; return 1; }; _an=own ;;
        *) case " none $ANIMATION_NAMES " in *" $1 "*) _an=$1 ;; *) echo "animation takes none, $(printf '%s' "$ANIMATION_NAMES" | sed 's/ /, /g'), next or back"; return 1 ;; esac ;;
    esac
    config_set DIALOG_ANIMATION "$_an" >/dev/null; DIALOG_ANIMATION=$_an; export DIALOG_ANIMATION
    if [ "$_an" = none ]; then echo "animation none $PANEL_SEP the dialog opens and closes with no motion"; else echo "animation $_an $PANEL_SEP from the dialog's next opening"; fi
}
bar_look_follow() {   # bar_look_follow GLYPHS FAMILY -- each when named
    _bc=''
    case ${1:-} in signs|words) [ "$1" = "$BAR_GLYPHS" ] || { [ "$MODE" = dry ] || config_set BAR_GLYPHS "$1" >/dev/null; BAR_GLYPHS=$1; export BAR_GLYPHS; _bc=1; } ;; esac
    case " $GLYPH_FAMILIES " in *" ${2:-none} "*) [ "$2" = "$GLYPH_FAMILY" ] || { [ "$MODE" = dry ] || config_set GLYPH_FAMILY "$2" >/dev/null; GLYPH_FAMILY=$2; export GLYPH_FAMILY; _bc=1; } ;; esac
    [ -n "$_bc" ] && [ "$MODE" != dry ] || return 0
    bar_redraw; ! wm_session || bar_ws_names
}
theme_family() {   # theme_family [stone|star|banner]
    [ -n "${1:-}" ] || { echo "glyph family $GLYPH_FAMILY $PANEL_SEP stone, star or banner"; return; }
    [ $# -eq 1 ] || refuse_in theme "family takes one word: stone, star or banner"
    family_step "$1" || exit 1
}
family_step() {   # family_step stone|star|banner -> the receipt; 1 when refused
    case " $GLYPH_FAMILIES " in *" $1 "*) ;; *) echo "family takes stone, star or banner"; return 1 ;; esac
    [ "$1" != "$GLYPH_FAMILY" ] || { echo "the glyph family is $1 already"; return 1; }
    config_set GLYPH_FAMILY "$1" >/dev/null; GLYPH_FAMILY=$1; export GLYPH_FAMILY
    bar_redraw; ! wm_session || bar_ws_names
    echo "glyph family $1"
}
theme_glyphs() {   # theme_glyphs [signs|words] -- the bar's
    [ -n "${1:-}" ] || { echo "the bar in $BAR_GLYPHS $PANEL_SEP signs or words"; return; }
    [ $# -eq 1 ] || refuse_in theme "glyphs takes one word: signs or words"
    glyphs_step "$1" || exit 1
}
theme_icons() {   # theme_icons [on|off] -- home's app icons
    [ -n "${1:-}" ] || { echo "app icons $DIALOG_ICONS $PANEL_SEP on or off"; return; }
    [ $# -eq 1 ] || refuse_in theme "icons takes one word: on or off"
    icons_step "$1" || exit 1
}
icons_step() {   # icons_step on|off -> the receipt; 1 when refused
    case $1 in on|off) ;; *) echo "icons takes on or off"; return 1 ;; esac
    [ "$1" != "$DIALOG_ICONS" ] || { echo "app icons are $1 already"; return 1; }
    config_set DIALOG_ICONS "$1" >/dev/null; DIALOG_ICONS=$1; export DIALOG_ICONS
    echo "app icons $1"
}
theme_spacing() {   # theme_spacing [none|groups|rows] -- home's apps
    [ -n "${1:-}" ] || { echo "app spacing $DIALOG_SPACING $PANEL_SEP none, groups or rows"; return; }
    [ $# -eq 1 ] || refuse_in theme "spacing takes one word: none, groups or rows"
    spacing_step "$1" || exit 1
}
spacing_step() {   # spacing_step none|groups|rows -> the receipt; 1 when refused
    case $1 in none|groups|rows) ;; *) echo "spacing takes none, groups or rows"; return 1 ;; esac
    [ "$1" != "$DIALOG_SPACING" ] || { echo "app spacing is $1 already"; return 1; }
    config_set DIALOG_SPACING "$1" >/dev/null; DIALOG_SPACING=$1; export DIALOG_SPACING
    echo "app spacing $1"
}
glyphs_step() {   # glyphs_step signs|words -> the receipt; 1 when refused
    case $1 in signs|words) ;; *) echo "glyphs takes signs or words"; return 1 ;; esac
    [ "$1" != "$BAR_GLYPHS" ] || { echo "the bar is in $1 already"; return 1; }
    config_set BAR_GLYPHS "$1" >/dev/null; BAR_GLYPHS=$1; export BAR_GLYPHS; bar_redraw
    echo "the bar in $1"
}
# the loop cache; a player of yours is never stopped
MOTION_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/spark-shell/motion
motion_names() { for _ms in "$REPO"/lib/motion_*.py; do [ -f "$_ms" ] || continue; _ms=${_ms##*/motion_}; printf '%s\n' "${_ms%.py}"; done; printf '%s\n' $WALL_SCENES; }   # -> the moving wallpapers, one a line
motion_has() { wall_scene "$1" || { wall_shipped "$1" && [ -f "$REPO/lib/motion_$1.py" ]; } || art_loop_of "$1" >/dev/null; }   # motion_has WALLPAPER -> 0 when it moves
motion_missing() {   # -> the missing tools, or nothing
    _mm=''
    command -v mpv >/dev/null 2>&1 || _mm="$_mm mpv"
    if wall_scene "${WALLPAPER:-}"; then scene_ready || _mm="$_mm numpy"
    elif art_loop_of "${WALLPAPER:-}" >/dev/null; then :   # a loop of the theme's own: nothing to make
    else for _mt in python3 rsvg-convert; do command -v "$_mt" >/dev/null 2>&1 || _mm="$_mm $_mt"; done; fi
    wallpaper_cmd >/dev/null || _mm="$_mm spark-wallpaper"
    printf '%s' "${_mm# }"
}
motion_why() {   # -> why it cannot play, or nothing (after pm_detect)
    [ "$OS" != Darwin ] || { echo "the moving wallpaper is the Linux desktop's: macOS has its own"; return; }
    [ "$DESKTOP" = sway ] || { echo "the moving wallpaper is the desktop's: spark-shell on desktop first"; return; }
    _mw=$(motion_missing); [ -n "$_mw" ] || return 0
    echo "the moving wallpaper needs $_mw: spark-shell on desktop installs it"
}
motion_want() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-motion.want"; }   # -> the loop's words file
motion_ours() {   # -> pids of players on our loops
    if command -v pgrep >/dev/null 2>&1; then { pgrep -u "$(id -u)" -f "spark-wallpaper .*$MOTION_DIR/"; pgrep -u "$(id -u)" -f "mpvpaper .*$MOTION_DIR/"; } 2>/dev/null || :; return 0; fi
    # no pgrep (a bare container): /proc
    _muid=$(id -u)
    grep -l -s -F "$MOTION_DIR/" /proc/[0-9]*/cmdline 2>/dev/null | while IFS= read -r _mc; do
        _mpid=${_mc#/proc/}; _mpid=${_mpid%/cmdline}
        { tr '\0' ' ' < "$_mc"; } 2>/dev/null | grep -Eq '(^|/)(spark-wallpaper|mpvpaper) -' || continue   # gone meanwhile: no file
        [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/$_mpid/status" 2>/dev/null)" != "$_muid" ] || echo "$_mpid"
    done || :
}
motion_stop() {
    rm -f "$(motion_want)"
    for _mp in $(motion_ours); do kill "$_mp" 2>/dev/null || :; done
}
motion_play() {   # motion_play ARGS... -- in its own session
    _mpc=$(wallpaper_cmd) || return 0
    for _mp in $(motion_ours); do kill "$_mp" 2>/dev/null || :; done
    if command -v setsid >/dev/null 2>&1; then setsid "$_mpc" "$@" </dev/null >/dev/null 2>&1 &
    else ( trap '' HUP; exec "$_mpc" "$@" ) </dev/null >/dev/null 2>&1 & fi
}
motion_make() {   # motion_make DRAWING SEDFILE OUT -- SEDFILE empty: as drawn
    _md=$(mktemp -d "${TMPDIR:-/tmp}/spark-shell-motion.XXXXXX") || return 1
    if python3 -I "$REPO/lib/motion_$1.py" "$_md" >/dev/null 2>&1 && [ -f "$_md/f0000.svg" ] \
        && printf '%s\n' "$_md"/f*.svg | xargs -P "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" -n 32 sh -c 's=$1; shift; for f; do if [ -s "$s" ]; then sed -f "$s" "$f"; else cat "$f"; fi | rsvg-convert -o "${f%.svg}.png" || exit 1; done' _ "$2" \
        && mpv --no-config --really-quiet "mf://$_md/f*.png" --mf-fps=30 --vf=format=yuv420p --ovc=libx264 --ovcopts=crf=20,preset=medium --of=mp4 --o="$3.part" </dev/null >/dev/null 2>&1 \
        && [ -s "$3.part" ] && mv "$3.part" "$3"; then _mk=0; else _mk=1; rm -f "$3.part"; fi
    rm -rf "${_md:?}"
    return "$_mk"
}
scene_info() {   # scene_info SCENE WxH -> info JSON, cached
    _sik=$MOTION_DIR/info-$1-$2-$(cksum < "$SCENE_MAKE" | cut -d' ' -f1).json
    [ -s "$_sik" ] || { mkdir -p "$MOTION_DIR" && python3 -I "$SCENE_MAKE" --info --scene "$1" --size "$2" > "$_sik.new" 2>/dev/null && mv "$_sik.new" "$_sik"; } || { rm -f "$_sik.new"; return 1; }
    cat "$_sik"
}
scene_loop_size() {   # scene_loop_size SCENE WxH -> a pixel scene's grid, else WxH made even
    _sls=$(scene_info "$1" "$2" | jq -r 'if .kind == "pixel" and .grid != null then (.grid | if type == "array" then "\(.[0])x\(.[1])" else tostring end) else empty end' 2>/dev/null) || return 1
    [ -n "$_sls" ] || { _slw=${2%x*}; _slh=${2#*x}; _sls="$((_slw - _slw % 2))x$((_slh - _slh % 2))"; }
    printf '%s' "$_sls"
}
motion_make_scene() {   # motion_make_scene SCENE PALETTE_FILE WxH OUT -- a pixel scene lossless 4:4:4
    _msf=$(scene_info "$1" "$3" | jq -r '.fps // empty' 2>/dev/null); [ -n "$_msf" ] || return 1
    if [ "$(scene_info "$1" "$3" | jq -r '.kind // empty' 2>/dev/null)" = pixel ]; then _msv='--vf=format=yuv444p --ovcopts=crf=0,preset=medium'; else _msv='--vf=format=yuv420p --ovcopts=crf=18,preset=medium'; fi
    _msd=$(mktemp -d "${TMPDIR:-/tmp}/spark-shell-motion.XXXXXX") || return 1
    # shellcheck disable=SC2086   # the encoder's words, split on purpose
    { python3 -I "$SCENE_MAKE" --raw --scene "$1" --size "$3" --jobs "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" "$2" 2>/dev/null || : > "$_msd/failed"; } \
        | mpv --no-config --really-quiet --demuxer=rawvideo --demuxer-rawvideo-w="${3%x*}" --demuxer-rawvideo-h="${3#*x}" --demuxer-rawvideo-mp-format=rgb24 --demuxer-rawvideo-fps="$_msf" - $_msv --ovc=libx264 --of=mp4 --o="$4.part" >/dev/null 2>&1 || : > "$_msd/failed"
    if [ ! -e "$_msd/failed" ] && [ -s "$4.part" ]; then mv "$4.part" "$4"; _mk=0; else rm -f "$4.part"; _mk=1; fi
    rm -rf "${_msd:?}"
    return "$_mk"
}
motion_screens() {   # -> NAME<tab>WxH per screen on, in pixels
    wm_outputs | jq -r '.[] | select(.active) | [.name, (((.rect.width * (.scale // 1)) | floor | tostring) + "x" + ((.rect.height * (.scale // 1)) | floor | tostring))] | @tsv' 2>/dev/null || :
}
MOTION_NOW=''   # from motion_follow: playing, making or nothing
motion_follow() {   # the look's loops playing or made; else ours stopped
    MOTION_NOW=''
    [ "$OS" != Darwin ] && wm_up || return 0
    art_screens_follow
    if [ "${WALLPAPER_MOTION:-off}" != on ] || ! motion_has "${WALLPAPER:-}" || [ -n "$(motion_missing)" ]; then motion_stop; return 0; fi
    _mj=$(mktemp -d "${TMPDIR:-/tmp}/spark-shell-motion.XXXXXX") || return 0
    mkdir -p "$MOTION_DIR"
    if _mlp=$(art_loops); then   # the theme's own loops, linked into the cache so they are ours to stop: a loop a screen, none to make
        printf '%s\n' "$_mlp" | while IFS="$TAB" read -r _mls _mln; do
            _mll=$MOTION_DIR/given-$(printf '%s' "$_mls" | cksum | cut -d' ' -f1).mp4
            ln -sf "$_mls" "$_mll" && printf '%s\tgiven\t%s\n' "$_mll" "$_mln"
        done > "$_mj/plan"
        awk -F '\t' '{ print "--screen"; print $3 "=" $1 }' "$_mj/plan" > "$_mj/args"
    elif wall_scene "$WALLPAPER"; then   # the plan: LOOP<tab>SIZE<tab>SCREEN a line
        _mpf=$(palette_file "${THEME:-}" 2>/dev/null) || { rm -rf "${_mj:?}"; motion_stop; return 0; }   # no palette: the still alone
        cp "$_mpf" "$_mj/palette.env"
        _msum=$(cat "$SCENE_MAKE" "$_mpf" | cksum | cut -d' ' -f1)
        motion_screens | while IFS="$TAB" read -r _mn _ms; do
            _msz=$(scene_loop_size "$WALLPAPER" "$_ms") || continue
            printf '%s\t%s\t%s\n' "$MOTION_DIR/$WALLPAPER-$_msum-$_msz.mp4" "$_msz" "$_mn"
        done > "$_mj/plan"
        [ -s "$_mj/plan" ] || { rm -rf "${_mj:?}"; motion_stop; return 0; }
        _mscale=smooth; [ "$(scene_info "$WALLPAPER" "$(motion_screens | awk -F '\t' 'NR == 1 { print $2 }')" | jq -r '.kind // empty' 2>/dev/null)" != pixel ] || _mscale=nearest
        { printf -- '--scale\n%s\n' "$_mscale"; awk -F '\t' '{ print "--screen"; print $3 "=" $1 }' "$_mj/plan"; } > "$_mj/args"
    else   # a drawing: one loop, every screen
        : > "$_mj/palette.sed"   # empty: the frames as drawn
        if [ -n "${THEME:-}" ] && [ "$THEME" != none ] && ! wall_own "$WALLPAPER" && _mpf=$(palette_file "$THEME"); then wall_recolor_sed "$REPO/gallery/wallpaper/$WALLPAPER.svg" "$_mpf" > "$_mj/palette.sed"; fi
        _msum=$(cat "$REPO/lib/motion_$WALLPAPER.py" "$_mj/palette.sed" | cksum | cut -d' ' -f1)
        printf '%s\tdrawing\t*\n' "$MOTION_DIR/$WALLPAPER-$_msum.mp4" > "$_mj/plan"
        printf -- '--all\n%s\n' "$MOTION_DIR/$WALLPAPER-$_msum.mp4" > "$_mj/args"
    fi
    if cmp -s "$_mj/args" "$(motion_want)" && [ -n "$(motion_ours)" ]; then rm -rf "${_mj:?}"; MOTION_NOW=playing; return 0; fi   # playing already
    mkdir -p "$(dirname "$(motion_want)")" && cp "$_mj/args" "$(motion_want)"
    if awk -F '\t' '{ print $1 }' "$_mj/plan" | while IFS= read -r _mf; do [ -f "$_mf" ] || exit 1; done; then
        motion_play_want; rm -rf "${_mj:?}"; MOTION_NOW=playing; return 0
    fi
    MOTION_NOW=making
    [ ! -f "$MOTION_DIR/making" ] || ! pid_running "$(cat "$MOTION_DIR/making" 2>/dev/null)" || { rm -rf "${_mj:?}"; return 0; }   # the maker plays the newest want
    for _mp in $(motion_ours); do kill "$_mp" 2>/dev/null || :; done   # the old look's loops
    ( trap '' HUP; sh -c 'echo "$PPID"' > "$MOTION_DIR/making"
      _mok=1
      while IFS="$TAB" read -r _mf _msz _mn; do
          [ ! -f "$_mf" ] || continue
          if [ "$_msz" = drawing ]; then motion_make "$WALLPAPER" "$_mj/palette.sed" "$_mf" || _mok=0
          else motion_make_scene "$WALLPAPER" "$_mj/palette.env" "$_msz" "$_mf" || _mok=0; fi
      done < "$_mj/plan"
      if [ "$_mok" = 1 ] && cmp -s "$_mj/args" "$(motion_want)"; then
          motion_play_want
          for _mo in "$MOTION_DIR/$WALLPAPER"-*.mp4; do grep -qF "$_mo" "$_mj/plan" || rm -f "$_mo"; done   # loops of another palette or size
      fi
      rm -f "$MOTION_DIR/making"; rm -rf "${_mj:?}" ) </dev/null >/dev/null 2>&1 3>&- 4<&- &
}
motion_raise() {   # our loops back on top: the background drawer started anew (a screen's still, a reload) covers a player, which pauses
    _mrb=$(wm_background_pid) && _mrt=$(proc_ticks "$_mrb") || return 0
    _mrh=$(getconf CLK_TCK 2>/dev/null) || _mrh=100; _mrt=$((_mrt + 3 * _mrh))   # it draws once its pictures are read: 3 s on
    while [ "$(awk -v h="$_mrh" '{ printf "%d", $1 * h }' /proc/uptime)" -lt "$_mrt" ]; do sleep 0.5; done
    for _mp in $(motion_ours); do
        [ "$(proc_ticks "$_mp" || echo 0)" -lt "$_mrt" ] || continue   # a player that started before the drawer drew
        motion_play_want; return 0
    done
}
proc_ticks() { [ -r "/proc/$1/stat" ] && sed 's/.*) //' "/proc/$1/stat" | awk '{ print $20 }'; }   # proc_ticks PID -> when it started, in clock ticks since boot
motion_play_want() {
    [ -f "$(motion_want)" ] || return 0
    set --; while IFS= read -r _ma; do set -- "$@" "$_ma"; done < "$(motion_want)"
    motion_play "$@"
}
motion_row() {   # only when on
    [ "${WALLPAPER_MOTION:-off}" = on ] || return 0
    _mw=$(motion_why); if [ -z "$_mw" ]; then ok motion "the moving wallpaper is on: $(motion_names | grep -c '') wallpapers move"; else skip motion "$_mw"; fi
}
theme_motion() {   # theme_motion [on|off] -- the moving wallpaper
    [ -n "${1:-}" ] || { echo "moving wallpaper $WALLPAPER_MOTION $PANEL_SEP on or off; $(motion_names | grep -c '') wallpapers move"; return; }
    [ $# -eq 1 ] || refuse_in theme "motion takes one word: on or off"
    motion_step "$1" || exit 1
}
motion_step() {   # motion_step on|off -> the receipt; 1 when refused
    case $1 in on|off) ;; *) echo "motion takes on or off"; return 1 ;; esac
    [ "$1" != "$WALLPAPER_MOTION" ] || { echo "the moving wallpaper is $1 already"; return 1; }
    if [ "$1" = on ]; then [ -n "${PM:-}" ] || pm_detect; _mw=$(motion_why); [ -z "$_mw" ] || { echo "$_mw"; return 1; }; fi
    config_set WALLPAPER_MOTION "$1" >/dev/null; WALLPAPER_MOTION=$1; export WALLPAPER_MOTION
    motion_follow
    if [ "$1" = off ]; then echo "moving wallpaper off"
    elif motion_has "$WALLPAPER"; then case $MOTION_NOW in making) echo "moving wallpaper on $PANEL_SEP $WALLPAPER moves once its loop is made" ;; playing) echo "moving wallpaper on $PANEL_SEP $WALLPAPER moves" ;; *) echo "moving wallpaper on $PANEL_SEP $WALLPAPER moves on the desktop" ;; esac
    else echo "moving wallpaper on $PANEL_SEP $WALLPAPER is still; $(motion_names | grep -c '') wallpapers move"; fi
}
theme_transparency() {   # theme_transparency [N|more|less] -- 0 to 50, steps of 10
    _st=$(transparency_of "$ALPHA")
    [ -n "${1:-}" ] || { if [ "$_st" -eq 0 ]; then echo "transparency off"; else echo "transparency $_st%"; fi; return; }
    case ${1%\%} in more|less) ;; [0-9]|[1-4][0-9]|50) ;; *) refuse_in theme "transparency takes a percent, 0 to 50, or more or less" ;; esac
    alpha_step "${1%\%}" || exit 1
}
alpha_step() {   # alpha_step N|more|less -> the receipt; 1 when refused
    case $1 in
        more) _d=-0.1 ;; less) _d=0.1 ;;
        *) _d=$(awk -v n="$1" 'BEGIN { printf "%.2f", 1 - n / 100 }'); _d=$(awk -v a="$ALPHA" -v v="$_d" 'BEGIN { printf "%.2f", v - a }') ;;
    esac
    _new=$(awk -v a="$ALPHA" -v d="$_d" 'BEGIN { v = a + d; if (v > 1) v = 1; if (v < 0.5) v = 0.5; s = sprintf("%.2f", v); sub(/0$/, "", s); print s }')
    [ "$_new" != "$ALPHA" ] || { if [ "$1" = less ]; then echo "transparency is off already"; elif [ "$1" = more ]; then echo "transparency stops at 50%"; else echo "transparency is $(transparency_of "$ALPHA")% already"; fi; return 1; }
    config_set ALPHA "$_new" >/dev/null; ALPHA=$_new; export ALPHA; look_apply
    _st=$(transparency_of "$_new"); if [ "$_st" -eq 0 ]; then echo "transparency off"; else echo "transparency at $_st%"; fi
}
look_small() {   # look_small PICTURE -> a small PNG, or the PNG itself
    if pic_small "$1" "$TMP/small.png"; then printf '%s' "$TMP/small.png"; return 0; fi
    case $(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z') in png) printf '%s' "$1"; return 0 ;; esac
    echo "a picture is read through rsvg-convert (the $(svg_pkg) package), which is not installed; a PNG is read without it"; return 1
}
look_name() {   # look_name WORDS -> a name not taken
    _ln=$(layout_name_of "$1"); [ -n "$_ln" ] || _ln=look
    case $(theme_kind "$_ln") in ''|look) ;; *) _ln=$_ln-look ;; esac
    printf '%s' "$_ln"
}
# the picks are checked against the tool schema's lists
look_pick_ok() {   # look_pick_ok KIND VALUE -> 0 when listed or empty
    case $1:$2 in
        *:) return 0 ;;
        face:*) case " $FONT_FACES " in *" $2 "*) return 0 ;; esac ;;
        family:*) case " $GLYPH_FAMILIES " in *" $2 "*) return 0 ;; esac ;;
        animation:*) case " $ANIMATION_NAMES " in *" $2 "*) return 0 ;; esac ;;
        drawing:*) for _e in $WALL_SHIPPED; do [ "${_e%%:*}" != "$2" ] || return 0; done ;;
    esac
    return 1
}
look_pick_list() {   # look_pick_list KIND -> the list as a|b|c
    case $1 in face) _lpl=$FONT_FACES ;; family) _lpl=$GLYPH_FAMILIES ;; animation) _lpl=$ANIMATION_NAMES ;; drawing) _lpl=''; for _e in $WALL_SHIPPED; do _lpl="$_lpl ${_e%%:*}"; done ;; *) _lpl='' ;; esac
    _lpo=''; for _e in $_lpl; do _lpo="$_lpo|$_e"; done; printf '%s' "${_lpo#|}"
}
look_pick_why() { echo "$1 takes $(look_pick_list "$1" | sed 's/|/, /g; s/, \([a-z]*\)$/ or \1/')"; }   # look_pick_why KIND -> "face takes neon, argon,... or krypton"
look_picks() {   # look_picks 'WORDS [KIND=V]...' -> _lpr the words, _lp_KIND each pick
    _lpr=$1; _lp_face=''; _lp_family=''; _lp_animation=''; _lp_drawing=''
    while :; do
        _lpw=${_lpr##* }; [ "$_lpw" != "$_lpr" ] || break
        case $_lpw in face=*|family=*|animation=*|drawing=*) ;; *) break ;; esac
        _lpk=${_lpw%%=*}; _lpv=${_lpw#*=}
        look_pick_ok "$_lpk" "$_lpv" || { look_pick_why "$_lpk"; return 1; }
        eval "_lp_$_lpk=\$_lpv"
        _lpr=${_lpr% *}
    done
}
anim_for_colors() {   # anim_for_colors PALETTE_FILE -> a piece by hue and ground
    awk -F= '{ v[$1] = $2; gsub(/["\r]/, "", v[$1]) }
        function hx(s, i) { return (index("0123456789abcdef", substr(s, i, 1)) - 1) * 16 + index("0123456789abcdef", substr(s, i + 1, 1)) - 1 }
        END { a = tolower(v["THEME_ACCENT"]); b = tolower(v["THEME_BG"]); sub(/^#/, "", a); sub(/^#/, "", b)
            dark = (hx(b, 1) * 299 + hx(b, 3) * 587 + hx(b, 5) * 114) / 1000 < 128
            r = hx(a, 1) / 255; g = hx(a, 3) / 255; bl = hx(a, 5) / 255
            mx = r; if (g > mx) mx = g; if (bl > mx) mx = bl; mn = r; if (g < mn) mn = g; if (bl < mn) mn = bl
            if (mx - mn < 0.12) { print (dark ? "moon" : "flight"); exit }
            if (mx == r) h = 60 * (g - bl) / (mx - mn); else if (mx == g) h = 60 * (2 + (bl - r) / (mx - mn)); else h = 60 * (4 + (r - g) / (mx - mn))
            if (h < 0) h += 360
            if (h < 40 || h >= 330) print (dark ? "embers" : "sun"); else if (h < 70) print "sun"; else if (h < 160) print "ripple"
            else if (h < 200) print "tide"; else if (h < 260) print (dark ? "moon" : "tide"); else print (dark ? "moon" : "flight") }' "$1"
}
look_picked() {   # look_picked PALETTE_FILE FACE FAMILY ANIMATION -> the rest of look.env
    _lpf=${2:-$(face_word "${FONT%%:*}")} || _lpf=''
    [ -z "$_lpf" ] || printf 'FACE=%s\n' "$_lpf"
    _lps=$(look_font_size); case $_lps in [6-9]|[1-3][0-9]|40) printf 'TEXT_SIZE=%s\n' "$_lps" ;; esac
    printf 'ALPHA=%s\nPOINTER=%s\nANIMATION=%s\nGLYPH_FAMILY=%s\n' "$ALPHA" "${POINTER:-}" "${4:-$(anim_for_colors "$1")}" "${3:-$GLYPH_FAMILY}"
}
theme_picture() {   # theme_picture PATH [face=F] [family=G] [animation=N]
    [ -n "${1:-}" ] || refuse_in theme "picture takes a picture's path"
    _lpy=$(look_picks "$*") || refuse_in theme "$_lpy"
    look_picks "$*"; set -- "$_lpr"
    _pp=$(wall_picture_ok "$1") || refuse_in theme "${_pp#wallpaper: }"
    command -v python3 >/dev/null 2>&1 || refuse_in theme "python3 is not installed, and it reads the picture's colors"
    _small=$(look_small "$_pp") || refuse_in theme "$_small"
    name=$(look_name "$(basename "${_pp%.*}")")
    _d=$LOOKS_DIR/$name; rm -rf "$_d.new"; mkdir_state "$_d.new"
    python3 -I "$REPO/lib/look.py" palette "$_small" > "$_d.new/palette.env" 2>"$TMP/look.err" || refuse_in theme "the picture's colors could not be read: $(head -1 "$TMP/look.err")"
    cp "$_pp" "$_d.new/${_pp##*/}"
    { printf 'FORMAT=%s\nPALETTE=picture\nPICTURE=%s\nWALLPAPER=picture\n' "$LOOK_FORMAT" "${_pp##*/}"
      look_picked "$_d.new/palette.env" "$_lp_face" "$_lp_family" "$_lp_animation"; } > "$_d.new/look.env"
    rm -rf "$_d"; mv "$_d.new" "$_d"
    echo "a theme from ${_pp##*/}: $name -- spark-shell theme save NAME keeps it, theme back returns"
    theme_apply "$name"
}
theme_from_words() {   # theme_from_words WORDS
    spark=$(spark_bin); [ -n "$spark" ] || refuse_in theme "spark is not installed -- spark reads the words (github.com/forgewright-ai/spark)"
    command -v python3 >/dev/null 2>&1 || refuse_in theme "python3 is not installed, and it makes the palette"
    [ "$OS" = Darwin ] || pm_detect; theme_load; SND=''
    printf 'theme> %s\n' "$1"
    PANEL_WORDS=$1
    WANT_ONLY=theme_words want_steps "$1" || :
    want_run
}
WORDS_TAKE='theme: words take a hue, then accent, warmth, contrast and light'
theme_words_step() {   # theme_words_step 'HUE accent=A warmth=W contrast=C light=L [face=F] [family=G] [animation=N] [drawing=D] [name=SLUG]' -> the receipt
    case $1 in *[!a-z0-9=\ -]*|'') echo "$WORDS_TAKE"; return 1 ;; esac   # nothing the case below reads as a pattern
    _wh=''; _wa=''; _ww=''; _wc=''; _wl=''; _wn=''; _lp_face=''; _lp_family=''; _lp_animation=''; _lp_drawing=''
    for _w in $1; do
        case $_w in
            accent=*) _wa=${_w#*=} ;; warmth=*) _ww=${_w#*=} ;; contrast=*) _wc=${_w#*=} ;; light=*) _wl=${_w#*=} ;; name=*) _wn=${_w#*=} ;;
            face=*|family=*|animation=*|drawing=*) _lpk=${_w%%=*}; _lpv=${_w#*=}; look_pick_ok "$_lpk" "$_lpv" || { look_pick_why "$_lpk"; return 1; }; eval "_lp_$_lpk=\$_lpv" ;;
            *=*) echo "$WORDS_TAKE"; return 1 ;;
            *) [ -z "$_wh" ] || { echo "$WORDS_TAKE"; return 1; }; _wh=$_w ;;
        esac
    done
    theme_words_apply "$_wh" "$_wa" "$_ww" "$_wc" "$_wl" "$_wn" "${PANEL_WORDS:-}" "$_lp_face" "$_lp_family" "$_lp_animation" "$_lp_drawing"
}
theme_words_apply() {   # theme_words_apply HUE ACCENT WARMTH CONTRAST LIGHT [NAME] [WORDS] [FACE] [FAMILY] [ANIMATION] [DRAWING] -> the receipt
    command -v python3 >/dev/null 2>&1 || { echo "python3 is not installed, and it makes the palette"; return 1; }
    if [ -n "${6:-}" ]; then _words=$(printf '%s' "$6" | tr '-' ' ')
    elif [ -n "${7:-}" ]; then _words=$7
    else _words="$1$([ "$2" = same ] || printf ' and %s' "$2"), $5"; fi
    name=$(look_name "$_words")
    _d=$LOOKS_DIR/$name; rm -rf "$_d.new"; mkdir_state "$_d.new"
    python3 -I "$REPO/lib/look.py" words --hue "$1" --accent "$2" --warmth "$3" --contrast "$4" --light "$5" > "$_d.new/palette.env" 2>"$TMP/look.err" || { echo "no palette from those words: $(head -1 "$TMP/look.err")"; rm -rf "$_d.new"; return 1; }
    _lw=$WALLPAPER; [ -z "${11:-}" ] || [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || wall_yours || _lw=${11}   # the drawing, unless yours is a picture
    { printf 'FORMAT=%s\nPALETTE=words\nWORDS=%s\n' "$LOOK_FORMAT" "$(printf '%s' "$_words" | tr -cd 'A-Za-z0-9 ,.-' | cut -c1-80)"
      printf 'WALLPAPER=%s\n' "$_lw"
      look_picked "$_d.new/palette.env" "${8:-}" "${9:-}" "${10:-}"; } > "$_d.new/look.env"
    rm -rf "$_d"; mv "$_d.new" "$_d"
    theme_apply "$name" >/dev/null
    echo "$(theme_words_of "$name") is on $PANEL_SEP spark-shell theme save NAME keeps it, theme back returns"
}


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
                    || { chk theme fail "$THEME: spark-shell-console.service does not set it at boot" "$CONSOLE_AGAIN"; return; } ;;
            runit) [ "$(marked "$ROOT/etc/rc.local" "$PALETTE_MARK")" = "$(palette_line)" ] \
                    || { chk theme fail "$THEME: no line in /etc/rc.local sets it at boot" "$CONSOLE_AGAIN"; return; } ;;
        esac
        if vt_here && [ "$(vt_live)" != "$(head -1 "$CONSOLE_RGB")" ]; then
            chk theme warn "$THEME: the console uses another palette until the next boot" "spark-shell on"; return
        fi
    fi
    chk theme ok "$THEME: theme.env and the console's palette are current"
}
