# shellcheck extended-analysis=false
# ---------------------------------------------- verbs: theme, font, quiet
# sets: MOTION_DIR MOTION_NOW THEME_COLOR_WORDS THEME_WORDS WORDS_TAKE
# reads: ANIMATION_NAMES CONFIG CONFIG_DIR CONSOLE_AGAIN CONSOLE_COLORS CONSOLE_RGB CONSOLE_UNIT FONT_FACES GALLERY_KEYS GLYPH_FAMILIES LOOKS_DIR LOOK_FORMAT MODE NEON NEON_OLD NL OS PALETTE_DIR PALETTE_MARK PALETTE_WHY PANEL_SEP PATH_REFUSED PM RENDERED REPO ROOT SCENE_MAKE STATE_DIR TAB TERMINAL_SEEN TERM_PALETTE_FORMATS THEME_ENV THEME_FILE_PICTURE_MAX THEME_KEYS THEME_TRASH TMP WALL_NAMES WALL_SCENES WALL_SHIPPED
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
    elif [ "$failed" -gt 0 ]; then echo "Not all of it could be written: $failed_said"
    elif [ "$todos" -gt 0 ]; then echo "Not all of it is done: the todo rows above say what is left."
    else echo "$1"; fi
}

THEME_WORDS='none show list save delete back wallpaper text transparency animation glyphs icons spacing family face workspaces motion picture gallery install preview variant screens rename duplicate restore color colors pointer clock pair portrait panel loop reel export'   # no theme may be named one
cmd_theme() {   # cmd_theme [NAME|none|show|list|WORD ARG...|"WORDS"]
    CONFIG_MEND=1; [ -n "${THEME_LOCKED:-}" ] || config_load   # under the lock it is read already
    [ "$MODE" != dry ] || theme_dry_takes "$@"
    themes_settle
    case ${1:-show} in
        show) [ $# -le 1 ] || refuse_in theme "show takes no word"; theme_show; return ;;
        list) [ $# -le 1 ] || refuse_in theme "list takes no word"; theme_list; return ;;
        export) if [ $# -gt 1 ] || [ -z "$(theme_kind export)" ]; then
                if [ $# -lt 2 ] || [ $# -gt 3 ]; then echo "usage: spark-shell theme export NAME [$TERM_PALETTE_FORMATS|spark-theme]" >&2; return 1; fi
                if [ "${3:-}" = spark-theme ]; then theme_export_file "$2"; return; fi   # the theme itself, as a file to share
                palette_export "$2" "${3:-env}"; return
            fi ;;
        # these ask, fetch or think first, and take the themes' lock themselves once they change one
        save) shift; theme_save "$@"; return ;;
        delete) shift; theme_delete "$@"; return ;;
        gallery) shift; theme_gallery "$@"; return ;;
        install) shift; theme_install "$@"; return ;;
        screens) shift; theme_screens "$@"; return ;;
        workspaces) refuse_in theme "the glyph family names the workspaces now -- spark-shell theme family stone, star or banner" ;;   # not a theme name
        rename|duplicate|restore|color|colors|pointer|clock|pair|portrait|panel|loop|reel|back|wallpaper|text|transparency|animation|glyphs|icons|spacing|family|face|motion|picture|variant)
            if [ $# -gt 1 ] || [ "$1" = back ]; then theme_locked theme_change "$@"; else theme_change "$@"; fi   # bare, it is a question
            return ;;
    esac
    case "$*" in *' '*) theme_from_words "$*"; return ;; esac
    theme_locked theme_apply "$1"
}
theme_change() {   # theme_change WORD ARG... -- one of the theme's words that change it, alone with the themes
    case $1 in
        rename) shift; [ $# -ge 2 ] || refuse_in theme "rename NAME NEW -- which theme, and its new name?"; theme_rename "$@" ;;
        duplicate) shift; [ $# -ge 2 ] || refuse_in theme "duplicate NAME NEW -- which theme, and the new one's name?"; theme_duplicate "$@" ;;
        restore) shift; theme_restore "$@" ;;
        color) shift; theme_color "$@" ;;
        colors) shift; theme_colors "$@" ;;
        pointer) shift; theme_pointer "$@" ;;
        clock) jq_need; shift; theme_clock "$@" ;;
        pair) jq_need; shift; theme_pair "$@" ;;
        portrait) jq_need; shift; theme_portrait "$@" ;;
        panel) jq_need; shift; theme_panel "$@" ;;
        loop) shift; theme_loop "$@" ;;
        reel) shift; theme_reel "$@" ;;
        back) [ $# -le 1 ] || refuse_in theme "back takes no word"; theme_back ;;
        wallpaper) shift; theme_wallpaper "$@" ;;
        text) shift; theme_text "$@" ;;
        transparency) shift; theme_transparency "$@" ;;
        animation) shift; theme_animation "$@" ;;
        glyphs) shift; theme_glyphs "$@" ;;
        icons) shift; theme_icons "$@" ;;
        spacing) shift; theme_spacing "$@" ;;
        family) shift; theme_family "$@" ;;
        face) shift; theme_face "$@" ;;
        motion) shift; theme_motion "$@" ;;
        picture) shift; theme_picture "$@" ;;
        variant) jq_need; shift; theme_variant "$@" ;;
    esac
}
theme_dry_takes() {   # theme_dry_takes WORD... -- --dry-run shows what a theme, another variant or the look before would change; a word that would be done under it is refused
    case ${1:-show} in
        none|show|list|screens|gallery|variant|back) return 0 ;;
        export) [ "${3:-}" = spark-theme ] || return 0 ;;
        *) case " $THEME_WORDS " in *" $1 "*) ;; *) case "$*" in *" "*) ;; *) return 0 ;; esac ;; esac ;;
    esac
    refuse_in theme "$1 takes no --dry-run, so nothing was done"
}
# what the look in use takes, in the shell at once and in the config together: a kill in between leaves the old look whole
look_take() { config_is "$1" "$2" || _ltk="$_ltk $1"; eval "$1=\$2"; export "${1?}"; }   # look_take KEY VALUE -- _ltk the config's lines that change with it
look_taken() {   # the config's lines for what look_take changed, in one step; 1 and one line with none of them written
    [ "$MODE" != dry ] && [ -n "$_ltk" ] || return 0
    set --
    for _k in $_ltk; do eval "_v=\$$_k"; set -- "$@" "$_k" "$_v"; done
    config_keep "$@"
}
theme_animation_for() {   # NAME DIRECTORY -> the transition the theme requests
    if [ -n "$2" ]; then
        _taf=$(look_get "$2" ANIMATION)
        [ -z "$_taf" ] || { printf '%s' "$_taf"; return; }
        anim_for_palette "$(look_get "$2" PALETTE)"
    else anim_for_palette "$1"; fi
}
theme_apply() {   # theme_apply NAME|none [back] -- back keeps the history
    name=$1; _w=''; _ltk=''
    [ -n "$(theme_kind "$name")" ] || refuse_in theme "no palette named $name -- spark-shell theme list shows them"
    _td=$(theme_dir "$name")
    if [ -n "$_td" ]; then _lw=$(look_ok "$_td") || refuse_in theme "$name cannot be used: $_lw. Nothing was changed"; fi
    [ "$name" = none ] || palette_render "$name" || refuse_in theme "$PALETTE_WHY"
    PALETTE_RENDERED=$name   # for theme_files
    pm_detect
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
            look_take "$_k" "$_v"
        done
        for _k in BAR_GLYPHS GLYPH_FAMILY DIALOG_ICONS DIALOG_SPACING WALLPAPER_MOTION; do
            _v=$(look_get "$_td" "$_k"); [ -z "$_v" ] || look_take "$_k" "$_v"
        done
    elif [ "$name" != none ] && [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && ! wall_yours && _w=$(wall_for_palette "$name") && [ "$_w" != "$WALLPAPER" ]; then look_take WALLPAPER "$_w"   # the palette's drawing, unless a picture of yours
    else _w=''; fi
    [ "$name" = none ] || [ "$DIALOG_ANIMATION" = none ] || look_take DIALOG_ANIMATION "$(theme_animation_for "$name" "$_td")"
    look_take THEME "$name"
    look_taken || return 1
    case $_ltk in *' THEME') [ "$MODE" = dry ] || row ok config "THEME=$name ($CONFIG)" ;; esac
    theme_files
    _painted=0
    look_now
    case "$_ltk " in *' BAR_GLYPHS '*|*' GLYPH_FAMILY '*) [ "$MODE" = dry ] || { bar_redraw; ! wm_session || bar_ws_names; } ;; esac
    if [ "$name" = none ]; then palette_off all; terminal_off
    else palette_boot; terminal_apply; fi
    login_follow
    console_now
    if [ "$_painted" -eq 1 ]; then echo "Repainted 1 open terminal."
    elif [ "$_painted" -gt 1 ]; then echo "Repainted $_painted open terminals."; fi
    [ "${2:-}" = back ] || [ "$MODE" = dry ] || [ "$name" = none ] || kept_note theme "$name" || :   # none: nothing to come back to
    if [ "$name" = none ]; then verb_close "No palette: the console and the terminal use their default colors."
    elif [ -n "$_td" ]; then verb_close "The theme is $(theme_words_of "$name"): $(theme_look_words). A program that is already running, such as btop, takes it when it starts again."
    else verb_close "The palette is $name${_w:+, with $_w}. A program that is already running, such as btop, takes it when it starts again."; fi
    [ "$failed" -eq 0 ]
}
theme_wear() { _twl=$(theme_apply "$THEME" 2>&1) || refuse_in theme "$1, but the look is not all on: $(printf '%s\n' "$_twl" | tail -n 1 | sed 's/^spark-shell theme: //')"; }   # theme_wear DONE -- the theme in use put on again after a change of it, DONE what is done already
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
    _saved=$(theme_saved_lines)
    if [ -n "$_saved" ]; then
        echo "Saved themes (folders in $PALETTE_DIR):"
        printf '%s\n' "$_saved" | while IFS="$TAB" read -r n _from _wl; do
            note="$_from $PANEL_SEP $_wl"; [ "$n" != "${THEME:-}" ] || note="$note, current"
            printf '  %-20s %s\n' "$n" "$note"
        done
    fi
    echo "Bundled themes:"
    { theme_facts; core_theme_ids; } | awk -F '\t' 'NF > 1 { if ($2 == "bundled") wall[$1] = $8; next } $1 in wall { printf "  %-20s %s\n", $1, wall[$1] == "-" ? "" : wall[$1] }'
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
theme_save() {   # theme_save [NAME...] -- the look in use kept as a theme of yours; asked here, before the lock, when it would write over another
    name=$(layout_name_of "$*"); _tsw=''
    if [ -n "$name" ] && [ "$name" != "${THEME:-}" ] && [ "$(theme_kind "$name")" = saved ] && [ -t 0 ] && { : < /dev/tty; } 2>/dev/null; then
        printf 'write over the saved theme %s? [y/N] ' "$name" > /dev/tty; IFS= read -r _y < /dev/tty || _y=''
        case $_y in y|Y|yes) _tsw=over ;; *) refuse_in theme "$name kept as it was" ;; esac
    fi
    theme_locked theme_save_now "$name" "$_tsw"
}
theme_save_now() {   # theme_save_now NAME [over]
    name=$1
    [ -n "${THEME:-}" ] && [ "$THEME" != none ] || refuse_in theme "no palette is in use -- spark-shell theme NAME first"
    if [ -z "$name" ]; then case $(theme_kind "$THEME") in look) name=$THEME ;; *) refuse_in theme "save NAME -- a name for this look" ;; esac; fi
    case " $THEME_WORDS " in *" $name "*) refuse_in theme "$name is a word of spark-shell theme, so no theme can go by it" ;; esac
    [ -n "$(palette_file "$THEME")" ] || refuse_in theme "no palette named $THEME -- spark-shell theme list shows them"
    case $(theme_kind "$name") in
        shipped|yours) refuse_in theme "$name is a palette's name -- give the theme another" ;;
        saved) [ "$name" = "$THEME" ] || [ "${2:-}" = over ] || refuse_in theme "$name is saved already -- spark-shell theme delete $name first, or another name" ;;
        *) ! dir_there "$PALETTE_DIR/$name" || refuse_in theme "$PALETTE_DIR/$name is there and is no theme -- move it, or another name" ;;
    esac
    look_write "$PALETTE_DIR/$name" || refuse_in theme "could not keep the look$(store_said)"
    echo "saved $name ($PALETTE_DIR/$name) -- spark-shell theme $name brings the look back"
    kept_note theme "$name" || :
}
look_write() {   # look_write DIR -- the look in use as the theme DIR, its pictures, loops, reels and family with it, and that theme in use: nothing is drawn again; 1 with nothing changed
    theme_load
    _lwn=${1##*/}; _lww=''; _ltk=''
    theme_at "$THEME" && [ -n "$_tap" ] && dir_stage "$1" || return 1
    _lws=$_tad; _lwp=$_tap
    _lwl="FORMAT=$LOOK_FORMAT${NL}PALETTE=$THEME"
    if [ -n "$_lws" ]; then
        _lwo=$(look_get "$_lws" PALETTE); _lwl="FORMAT=$LOOK_FORMAT${NL}PALETTE=${_lwo:-$THEME}"
        _lwo=$(look_get "$_lws" WORDS); _lwl="$_lwl${_lwo:+${NL}WORDS=$_lwo}"
    fi
    if wall_shipped "$WALLPAPER"; then _lwl="$_lwl${NL}WALLPAPER=$WALLPAPER${NL}DRAWING=$WALLPAPER"
    elif wall_there; then
        _lww=${WALLPAPER##*/}
        case ${_lws:+$WALLPAPER} in "$_lws"/*) _lwo=${_lws##*/}; case $_lww in "$_lwo"-*) _lww=$_lwn-${_lww#"$_lwo"-} ;; esac ;; esac   # the theme's own: copied with its folder
        _lwl="$_lwl${NL}WALLPAPER=picture${NL}PICTURE=$_lww"
    else _lwl="$_lwl${NL}WALLPAPER=$WALLPAPER"; fi
    _lwo=$(face_word "${FONT%%:*}") || _lwo=''; _lwl="$_lwl${_lwo:+${NL}FACE=$_lwo}"   # your own face stays out
    _lwo=$(look_font_size); case $_lwo in [6-9]|[1-3][0-9]|40) _lwl="$_lwl${NL}TEXT_SIZE=$_lwo" ;; esac   # only a size theme text sets
    _lwl="$_lwl${NL}ALPHA=$ALPHA${NL}POINTER=${POINTER:-}${NL}ANIMATION=$(anim_now)${NL}BAR_GLYPHS=$BAR_GLYPHS${NL}GLYPH_FAMILY=$GLYPH_FAMILY${NL}WALLPAPER_MOTION=$WALLPAPER_MOTION${NL}DIALOG_ICONS=$DIALOG_ICONS${NL}DIALOG_SPACING=$DIALOG_SPACING"
    if look_write_files "$_lws" "$_lwp" "$_lwn" "$_dsn" && write_whole "$_dsn/look.env" printf '%s\n' "$_lwl" && dir_swap "$1"; then
        look_take THEME "$_lwn"; [ -z "$_lww" ] || look_take WALLPAPER "$1/$_lww"   # the folder's copy from now on
        if look_taken 2>"$TMP/store.why"; then
            dir_settle "$1"
            case "$_ltk " in *' WALLPAPER '*) ! desktop_wanted || desktop_file_apply ;; esac   # sway's file names the copy
            return 0
        fi
        dir_unswap "$1"
    fi
    dir_unstage "$1"; return 1
}
look_write_files() {   # look_write_files FOLDER PALETTE NAME NEWDIR -- the files of the look in use in NEWDIR: its theme's FOLDER (nothing for a palette's), its colors and its wallpaper
    { [ -z "$1" ] || theme_copy "$1" "$4" "$3"; } && cp "$2" "$4/palette.env" 2>"$TMP/store.why" || return 1
    if wall_shipped "$WALLPAPER"; then
        _lwf=$(wall_path)
        for _lwe in png svg; do [ ! -f "${_lwf%.png}.$_lwe" ] || cp "${_lwf%.png}.$_lwe" "$4/wallpaper.$_lwe" 2>"$TMP/store.why" || return 1; done
    elif wall_there; then case ${1:+$WALLPAPER} in "$1"/*) ;; *) cp "$WALLPAPER" "$4/${WALLPAPER##*/}" 2>"$TMP/store.why" || return 1 ;; esac
    fi
}
theme_named() {   # theme_named WORDS... -> the name of a theme here: the words as they are, else as a name is made of plain words (My Theme is my-theme); never another theme's
    [ -z "$(theme_kind "$*")" ] || { printf '%s' "$*"; return; }
    case "$*" in *[!A-Za-z0-9\ -]*) printf '%s' "$*" ;; *) layout_name_of "$*" ;; esac
}
theme_delete() {   # theme_delete NAME... -- a theme of yours, and what names it; asked here, before the lock
    name=$(theme_named "$@"); [ -n "$name" ] || refuse_in theme "delete NAME -- which theme?"
    theme_delete_ok "$name"
    kept_delete_ok theme "$name" || return 0
    theme_locked theme_delete_now "$name"
}
theme_delete_ok() {   # theme_delete_ok NAME -- refused unless it is a theme of yours that is not in use
    case $(theme_kind "$1") in
        saved|look) ;;
        shipped) refuse_in theme "$1 is a palette spark-shell ships, not a saved theme" ;;
        bundled) refuse_in theme "$1 belongs to the bundled gallery" ;;
        yours) refuse_in theme "$1 is a palette file of yours ($PALETTE_DIR/$1.env): remove the file to drop it" ;;
        *) refuse_in theme "no saved theme named $1 -- spark-shell theme list shows them" ;;
    esac
    [ "$1" != "${THEME:-}" ] || refuse_in theme "$1 is the theme in use -- spark-shell theme NAME another first"
}
theme_delete_now() {   # theme_delete_now NAME
    theme_delete_ok "$1"; _tdd=$(theme_dir "$1"); _ltk=''
    case ${WALLPAPER:-} in "$_tdd"/*)   # its picture is the wallpaper: the one the theme in use brings takes its place
        look_take WALLPAPER "$(theme_wallpaper_of "${THEME:-none}")"
        look_taken 2>"$TMP/store.why" || refuse_in theme "could not delete $1$(store_said)" ;;
    esac
    if [ -n "${THEME_UNDO:-}" ]; then   # the dialog's undo brings it back
        { mkdir_private "$THEME_TRASH" && rm -rf "${THEME_TRASH:?}/$1" && mv "$_tdd" "$THEME_TRASH/$1" && touch "$THEME_TRASH/$1"; } 2>"$TMP/store.why"
    else dir_drop "$_tdd"; fi || refuse_in theme "could not delete $1$(store_said)"
    families_drop "$1"
    kept_drop theme "$1" || :
    [ -z "$_ltk" ] || look_apply || return 1
    echo "deleted $1${_ltk:+; its picture was the wallpaper, $(wall_now) is now}"
}
theme_wallpaper_of() {   # theme_wallpaper_of NAME -> the WALLPAPER the theme brings, default when none
    _two=$(art_wall "$1"); [ "$_two" != picture ] || _two=$(theme_dir "$1")/$(look_get "$(theme_dir "$1")" PICTURE)
    if wall_value_ok "$_two"; then printf '%s' "$_two"; else printf default; fi
}
theme_restore() {   # theme_restore NAME -- a theme deleted from the dialog or the panel, back, and in its families again: its undo
    _trn=$(printf '%s' "$*" | tr -d '/'); case $_trn in ''|.*) _trn='' ;; esac
    [ -n "$_trn" ] && [ -d "$THEME_TRASH/$_trn" ] && theme_name_free "$_trn" >/dev/null || refuse_in theme "${_trn:-it} can no longer come back"
    mv "$THEME_TRASH/$_trn" "$PALETTE_DIR/$_trn" 2>"$TMP/store.why" || refuse_in theme "could not bring $_trn back$(store_said)"
    families_back "$_trn" || :
    echo "$_trn is back"
}
# a family of yours names the themes that are its variants: it follows one that is renamed, deleted or brought back
families_naming() { for _fnf in "$PALETTE_DIR"/*/family.json "$LOOKS_DIR"/*/family.json "$CONFIG_DIR"/families/*.json; do [ ! -f "$_fnf" ] || printf '%s\n' "$_fnf"; done | tr '\n' '\000' | xargs -0 grep -lF -e "\"$1\"" /dev/null 2>/dev/null; }   # families_naming NAME -> the family files of yours that hold the name
families_rename() {   # families_rename OLD NEW -- 1 when one that names OLD could not be written
    families_naming "$1" | ( _frr=0
        while IFS= read -r _frf; do [ "$_frf" != "$PALETTE_DIR/$1/family.json" ] || continue; write_whole "$_frf" jq --arg o "$1" --arg n "$2" '.variants |= map_values(if .theme == $o then .theme = $n else . end)' "$_frf" || _frr=1; done
        exit "$_frr" )
}
families_drop() {   # families_drop NAME -- it is no family's variant; where undo is offered, each is kept beside the theme
    families_naming "$1" | while IFS= read -r _frf; do
        [ -z "${THEME_UNDO:-}" ] || jq -r --arg o "$1" --arg f "$_frf" '.variants | to_entries[] | select(.value.theme == $o) | [$f, .key, (.value | tojson)] | join("\t")' "$_frf" >> "$THEME_TRASH/$1/.families" 2>/dev/null || :
        write_whole "$_frf" jq --arg o "$1" '.variants |= with_entries(select(.value.theme != $o))' "$_frf" || :
    done
}
families_back() {   # families_back NAME -- the families it was dropped from have it again, where they have no other by then
    _fbf=$PALETTE_DIR/$1/.families; [ -f "$_fbf" ] || return 0
    while IFS="$TAB" read -r _frf _frv _frj; do
        [ ! -f "$_frf" ] || write_whole "$_frf" jq --arg v "$_frv" --argjson j "$_frj" '.variants[$v] //= $j' "$_frf" || :
    done < "$_fbf"
    rm -f "$_fbf"
}
theme_export_file() {   # theme_export_file NAME -- the theme as NAME.spark-theme in the downloads folder: its look as a shared theme sets it, its colors, its pictures, loops and reels with no metadata, its family
    case $(theme_kind "$1") in ''|none) refuse_in theme "no theme named $1 -- spark-shell theme list shows them" ;; esac
    _txd=$(theme_dir "$1"); [ -n "$_txd" ] || refuse_in theme "$1 is a palette, with no folder -- spark-shell theme export $1 kitty gives it for a terminal"
    case $1 in [a-z]*) ;; *) refuse_in theme "a theme file takes a name of a to z, 0 to 9 and - -- spark-shell theme duplicate $1 NEW first" ;; esac
    case $1 in *[!a-z0-9-]*) refuse_in theme "a theme file takes a name of a to z, 0 to 9 and - -- spark-shell theme duplicate $1 NEW first" ;; esac
    [ ${#1} -le 40 ] || refuse_in theme "a theme file takes a name of 40 letters at most -- spark-shell theme duplicate $1 NEW first"
    command -v python3 >/dev/null 2>&1 || refuse_in theme "python3 is not installed, and it writes a theme file"
    _txs=$TMP/theme.export/$1; rm -rf "$TMP/theme.export"
    _txf=$(palette_file "$1") || refuse_in theme "no palette named $1"
    _txw=$(look_get "$_txd" WALLPAPER); _txp=''; [ "$_txw" != picture ] || _txp=$(look_get "$_txd" PICTURE)
    _txl="FORMAT=$LOOK_FORMAT"
    for _txk in $GALLERY_KEYS; do
        case $_txk in FORMAT) continue ;; PICTURE) _txv=$_txp ;; *) _txv=$(look_get "$_txd" "$_txk") ;; esac
        [ "$_txk" != FACE ] || [ -n "$_txv" ] || _txv=$(face_word "$(look_get "$_txd" FONT | sed 's/:.*//')") || _txv=''
        _txl="$_txl${_txv:+$NL$_txk=$_txv}"
    done
    { mkdir -p "$_txs" && cp "$_txf" "$_txs/palette.env" && printf '%s\n' "$_txl" > "$_txs/look.env"; } 2>"$TMP/store.why" || refuse_in theme "$1 could not be exported$(store_said)"
    for _txf in "$_txd"/*; do
        _txb=${_txf##*/}; [ -f "$_txf" ] && [ ! -L "$_txf" ] || continue
        case $_txb in
            look.env|palette.env) ;;
            family.json) cp "$_txf" "$_txs/$_txb" 2>"$TMP/store.why" || refuse_in theme "$1 could not be exported$(store_said)" ;;
            "$1"-landscape-[1-9].mp4|"$1"-portrait.mp4|"$1"-dialog-open.webp|"$1"-dialog-close.webp|"$1"-landscape-[1-9].jpg|"$1"-landscape-[1-9].png|"$1"-portrait.jpg|"$1"-portrait.png|"$_txp")
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
theme_new_name() {   # theme_new_name WORDS... -- _tnn the name a new theme of yours takes, or one line and exit
    _tnn=$(layout_name_of "$*"); [ -n "$_tnn" ] || refuse_in theme "a theme's name is letters and digits"
    _tnw=$(theme_name_free "$_tnn") || refuse_in theme "$_tnw"
}
theme_copy() {   # theme_copy DIR NEWDIR NEW -- a theme's plain files alone in NEWDIR, its own (DIR's name-*) named NEW-*, its look and family saying so; 1 when one cannot be
    _tco=${1##*/}
    [ ! -f "$1/family.json" ] || command -v jq >/dev/null 2>&1 || { echo "jq is not installed, and it reads the theme's family (spark-shell on)" > "$TMP/store.why"; return 1; }
    for _tcf in "$1"/*; do
        [ -f "$_tcf" ] && [ ! -L "$_tcf" ] || continue
        _tcb=${_tcf##*/}; case $_tcb in "$_tco"-*) _tcb=$3-${_tcb#"$_tco"-} ;; esac
        cp "$_tcf" "$2/$_tcb" 2>"$TMP/store.why" || return 1
    done
    [ ! -f "$2/look.env" ] || write_whole "$2/look.env" sed "s|^PICTURE=$_tco-|PICTURE=$3-|" "$2/look.env" || return 1
    [ -f "$2/family.json" ] || return 0
    # the family names the new theme and its files; a variant that is another theme stays. Its files' names alone: a new
    # name that begins with the old one (NAME-changed) is renamed once
    write_whole "$2/family.json" jq --arg o "$_tco" --arg l "$(theme_label "$_tco")" --arg n "$3" 'def ren: if type == "string" and startswith($o + "-") then $n + "-" + ltrimstr($o + "-") else . end;
        .variants |= map_values((if has("portrait") then .portrait |= ren else . end) | (if has("panels") then .panels |= map_values(map(map_values(ren))) else . end)
                                 | (if .theme == $o or .theme == $l then .theme = $n else . end))
        | .id = $n | .title = $n' "$2/family.json" \
        || ! jq -e '.variants | type == "object"' "$2/family.json" >/dev/null 2>&1   # one nothing reads goes along as it is
}
theme_make() {   # theme_make NEW CMD ARG... -- the theme NEW from what CMD ARG... puts in the folder it is given last; 1 with nothing there
    _tmd=$PALETTE_DIR/$1; shift
    if dir_stage "$_tmd" && "$@" "$_dsn" && dir_swap "$_tmd"; then dir_settle "$_tmd"; return 0; fi
    dir_unstage "$_tmd"; return 1
}
theme_editable() {   # -- _ted the folder of the theme in use to change: one of yours as it is; a bundled theme or a palette kept first as a look of its own, NAME-changed, until it is saved
    case $(theme_kind "${THEME:-none}") in
        saved|look) _ted=$(theme_dir "$THEME"); return 0 ;;
        none) refuse_in theme "no theme is in use -- spark-shell theme NAME first" ;;
        '') refuse_in theme "$THEME, the theme in use, is no longer here -- spark-shell theme NAME first" ;;
    esac
    look_write "$LOOKS_DIR/$(look_free "$(layout_name_of "$(theme_label "$THEME")" | cut -c1-24)-changed")" || refuse_in theme "could not keep the look to change$(store_said)"
    kept_note theme "$THEME" || :
    _ted=$(theme_dir "$THEME")
}
THEME_COLOR_WORDS='background:BG text:FG accent:ACCENT muted:MUTED black:ANSI_0 red:ANSI_1 green:ANSI_2 yellow:ANSI_3 blue:ANSI_4 magenta:ANSI_5 cyan:ANSI_6 white:ANSI_7 bright-black:ANSI_8 bright-red:ANSI_9 bright-green:ANSI_10 bright-yellow:ANSI_11 bright-blue:ANSI_12 bright-magenta:ANSI_13 bright-cyan:ANSI_14 bright-white:ANSI_15'   # the 20 colors by their words, in the palette's order
theme_color() {   # theme_color WORD COLOR -- one of the 20 colors of the theme in use; its contrast on the ground said when it reads poorly
    _tck=''; for _e in $THEME_COLOR_WORDS; do [ "${_e%%:*}" != "${1:-}" ] || _tck=THEME_${_e#*:}; done
    [ -n "$_tck" ] || refuse_in theme "color takes a color's word ($(printf '%s' "$THEME_COLOR_WORDS" | sed 's/:[A-Z_0-9]*//g; s/ /, /g')), then #rrggbb"
    _tcv=$(wall_hex "${2:-}") || refuse_in theme "$1 takes #rrggbb or a color's name"
    theme_editable
    env_put "$_ted/palette.env" "$_tck" "$_tcv" || refuse_in theme "could not keep $1$(store_said)"
    theme_wear "$1 is $_tcv"
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
    if [ "$_tcp" != "$_ted/palette.env" ]; then   # both files made before either is in place
        file_stage "$_ted/palette.env" cat "$_tcp" && file_stage "$_ted/look.env" env_with "$_ted/look.env" PALETTE "$1" && file_commit "$_ted/palette.env" && file_commit "$_ted/look.env" \
            || { file_unstage "$_ted/palette.env"; refuse_in theme "could not take the colors of $1$(store_said)"; }
    fi
    theme_wear "the colors are those of $1"
    echo "the colors of $(theme_label "$1")"
}
theme_pointer() {   # theme_pointer NAME [SIZE]|default -- the pointer of the look in use: a cursor theme and its size, or spark's own
    case ${1:-} in '') echo "pointer ${POINTER:-default} $PANEL_SEP default, or a cursor theme and its size"; return ;; default) _tpv='' ;; *) _tpv=$1${2:+ $2} ;; esac
    pointer_ok "$_tpv" || refuse_in theme "pointer takes default, or a cursor theme's name and its size in pixels (Adwaita 32)"
    _tpd=''; case $(theme_kind "${THEME:-none}") in saved|look) _tpd=$(theme_dir "$THEME") ;; esac
    [ -z "$_tpd" ] || file_stage "$_tpd/look.env" env_with "$_tpd/look.env" POINTER "$_tpv" || refuse_in theme "could not keep the pointer$(store_said)"
    _ltk=''; look_take POINTER "$_tpv"
    look_taken 2>"$TMP/store.why" || { [ -z "$_tpd" ] || file_unstage "$_tpd/look.env"; refuse_in theme "could not keep the pointer$(store_said)"; }
    [ -z "$_tpd" ] || file_commit "$_tpd/look.env" || refuse_in theme "the pointer is ${_tpv:-default}, but the theme could not keep it$(store_said)"
    look_apply || return 1
    echo "pointer ${_tpv:-default}"
}
theme_family_edit() {   # theme_family_edit JQ [JQ ARGS...] -- the theme in use's own family file changed by JQ ($me its name, $v its variant), made first with the theme its one variant; refused whole when it is no family this spark-shell reads
    command -v jq >/dev/null 2>&1 || refuse_in theme "jq is not installed, and it reads the theme's family (spark-shell on)"
    theme_editable; _tff=$_ted/family.json; _tfn=${_ted##*/}; _tfj=$1; shift
    _tfa=$(art_of "$THEME"); _tfv=$(printf '%s' "$_tfa" | jq -r .variant)
    file_stage "$_tff" theme_family_lines "$@" --arg me "$_tfn" --arg v "$_tfv" "$_tfj" || refuse_in theme "could not change the theme's family$(store_said)"
    stage_of "$_tff"
    _tfw=$(family_why "$_sgn" "$_tff") || { file_unstage "$_tff"; refuse_in theme "not changed: $_tfw"; }
    file_commit "$_tff" || refuse_in theme "could not change the theme's family$(store_said)"
}
theme_family_lines() {   # theme_family_lines JQ ARGS... -> the family of the theme in use through them; its first family when it has none
    if [ -f "$_tff" ]; then jq "$@" "$_tff"
    else printf '%s' "$_tfa" | jq --arg n "$_tfn" '{format: 1, id: $n, title: $n, media, variants: {(.variant): {theme: $n}}}' | jq "$@"; fi
}
theme_clock() {   # theme_clock on|off -- the clock over the art on the idle screen and the lock
    case ${1:-} in on|off) ;; *) refuse_in theme "clock takes on or off" ;; esac
    theme_family_edit '.clock = ($c == "on")' --arg c "$1"
    echo "the clock over the art $1"
}
theme_pair() {   # theme_pair NAME|none -- the theme in use's other variant: a theme here in the other light, or none
    command -v jq >/dev/null 2>&1 || refuse_in theme "jq is not installed, and it reads the theme's family (spark-shell on)"
    case ${1:-} in '') refuse_in theme "pair takes a theme in the other light, or none" ;; none) _tpo=''; _tpw='' ;; *) _tpo=$1
        case $(theme_kind "$_tpo") in ''|none) refuse_in theme "no theme named $_tpo -- spark-shell theme list shows them" ;; esac
        _tpw=$(art_variant "$_tpo")
        [ "$_tpw" != "$(art_of "${THEME:-none}" | jq -r .variant)" ] || refuse_in theme "$_tpo is $_tpw too: a pair is one dark and one light" ;;
    esac
    theme_family_edit '.variants |= with_entries(select(.value.theme == $me)) | if $o == "" then . else .variants[$w] = {theme: $o} end' --arg o "$_tpo" --arg w "$_tpw"
    if [ -n "$_tpo" ]; then echo "its $_tpw variant is $_tpo -- spark-shell theme variant $_tpw"; else echo "no other variant"; fi
}
theme_take() {   # theme_take FILE BASE picture|loop|reel -- FILE with no metadata and checked, beside the theme's own files (_tkw); _tkf the name it goes by, BASE.EXT. Nothing of the theme's is touched
    _tkn=$(file_named "$1"); [ -f "$1" ] && [ -r "$1" ] || refuse_in theme "$_tkn not taken: not a file that can be read"
    command -v python3 >/dev/null 2>&1 || refuse_in theme "python3 is not installed, and it reads $_tkn"
    _tki='it is '; case $3 in loop) _tke=mp4 ;; reel) _tke=webp ;; *) _tki=''; _tke=$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z'); [ "$_tke" != jpeg ] || _tke=jpg ;; esac
    _tkf=$2.$_tke; _tkt=$TMP/take; rm -rf "$_tkt"; mkdir -p "$_tkt"
    _tky=$(python3 -I "$REPO/lib/look.py" bare "$1" "$_tkt/$_tkf" "$3" 2>&1) || refuse_in theme "$_tkn not taken: $_tki$(media_why "$_tky")"
    case $3 in picture) _tky=$(gallery_picture_ok "$_tkt/$_tkf" "$THEME_FILE_PICTURE_MAX" 2>&1) ;; loop) _tky=$(media_ok "$_tkt/$_tkf" mp4) ;; reel) _tky=$(media_ok "$_tkt/$_tkf" webp) ;; esac || refuse_in theme "$_tkn not taken: ${_tky#its picture is }"   # a picture is the theme's own 4K still, as a theme file holds it
    find "$_ted" -maxdepth 1 \( -name '.new-*' -o -name '.was-*' \) -mtime +1 -exec rm -f {} + 2>/dev/null || :   # what a killed one left
    _tkw=$_ted/.new-${TMP##*/}; cp "$_tkt/$_tkf" "$_tkw" 2>/dev/null || { rm -f "$_tkw"; refuse_in theme "could not copy $_tkn"; }
}
theme_taken() { mv -f "$_tkw" "$_ted/$_tkf" || { rm -f "$_tkw"; refuse_in theme "could not put $_tkf in place"; }; }   # what theme_take took, by its name at once, over the one before
theme_picture_set() {   # theme_picture_set BASE JQ [JQ ARGS...] -- the picture taken (_tkf; empty: the role's goes) and the family changed by JQ together; the family refused, the picture is the one before
    _tps=$1; shift; _tpw=$_ted/.was-${TMP##*/}
    if [ -n "$_tkf" ]; then
        [ ! -f "$_ted/$_tkf" ] || ln "$_ted/$_tkf" "$_tpw" 2>/dev/null || cp "$_ted/$_tkf" "$_tpw" 2>/dev/null || { rm -f "$_tpw" "$_tkw"; refuse_in theme "could not keep $_tkf as it was"; }
        theme_taken
    fi
    if ! ( theme_family_edit "$@" ); then
        [ -z "$_tkf" ] || if [ -f "$_tpw" ]; then mv -f "$_tpw" "$_ted/$_tkf"; else rm -f "$_ted/$_tkf"; fi
        exit 1
    fi
    rm -f "$_tpw"; for _e in jpg png; do [ "$_tps.$_e" = "$_tkf" ] || rm -f "$_ted/$_tps.$_e"; done   # the role's older picture, which the family names no more
}
theme_portrait() {   # theme_portrait PICTURE|none -- the picture a turned screen shows, copied into the theme as NAME-portrait
    [ -n "${1:-}" ] || refuse_in theme "portrait takes a picture, or none"
    theme_editable; _tkf=''; [ "$1" = none ] || theme_take "$1" "${_ted##*/}-portrait" picture
    theme_picture_set "${_ted##*/}-portrait" 'if $f == "" then del(.variants[$v].portrait) else .variants[$v].portrait = $f end' --arg f "$_tkf"
    theme_apply "$THEME" >/dev/null
    if [ -n "$_tkf" ]; then echo "a turned screen shows $_tkf"; else echo "a turned screen shows the art fitted"; fi
}
theme_panel() {   # theme_panel 2|3 PICTURE|none -- the picture the second or third screen from the left shows, copied in as NAME-landscape-N; the theme's picture leads
    case ${1:-} in 2|3) ;; *) refuse_in theme "panel takes 2 or 3, then a picture or none" ;; esac
    [ -n "${2:-}" ] || refuse_in theme "panel $1 takes a picture, or none"
    theme_editable; _tpl=$(look_get "$_ted" PICTURE); _tpn=${_ted##*/}
    [ "$(look_get "$_ted" WALLPAPER)" = picture ] && [ -n "$_tpl" ] || refuse_in theme "panels follow a picture of the theme's own -- spark-shell theme wallpaper PICTURE first"
    case $_tpl in "$_tpn-landscape-$1".*) refuse_in theme "$_tpl is the theme's own picture, which leads: it is no panel $1 beside itself" ;; esac
    printf '%s\n' "$_tpl" | grep -Eqx '[A-Za-z0-9][A-Za-z0-9_-]{0,63}[.](png|jpg|jpeg)' || refuse_in theme "panels lead with the theme's picture, and $_tpl is no name for one -- letters, digits, - and _, then .jpg or .png"
    _tp2=''; _tp3=''; for _e in jpg png; do [ ! -f "$_ted/$_tpn-landscape-2.$_e" ] || _tp2=$_tpn-landscape-2.$_e; [ ! -f "$_ted/$_tpn-landscape-3.$_e" ] || _tp3=$_tpn-landscape-3.$_e; done
    _tkf=''; [ "$2" = none ] || theme_take "$2" "$_tpn-landscape-$1" picture
    if [ "$1" = 2 ]; then _tp2=$_tkf; else _tp3=$_tkf; fi
    theme_picture_set "$_tpn-landscape-$1" '.variants[$v].panels = ((if $p2 == "" then {} else {"2": [{landscape: $l}, {landscape: $p2}]} end)
            + (if $p2 == "" or $p3 == "" then {} else {"3": [{landscape: $l}, {landscape: $p2}, {landscape: $p3}]} end))
        | if .variants[$v].panels == {} then del(.variants[$v].panels) else . end' --arg l "$_tpl" --arg p2 "$_tp2" --arg p3 "$_tp3"
    theme_apply "$THEME" >/dev/null
    if [ -z "$_tp2" ]; then echo "no panels: each screen shows the art"; elif [ -z "$_tp3" ]; then echo "panels for 2 screens"; else echo "panels for 2 and 3 screens"; fi
}
theme_loop() {   # theme_loop ROLE LOOP|none -- a loop for one of the theme's own pictures (landscape-1, portrait), copied in beside it
    theme_editable; _tlp=''
    for _tlf in "$_ted"/*.jpg "$_ted"/*.png; do [ -f "$_tlf" ] || continue; _tlb=${_tlf##*/}; _tlb=${_tlb%.*}; case ${1:-} in "$_tlb"|"${_tlb#"${_ted##*/}"-}") _tlp=$_tlf ;; esac; done
    [ -n "$_tlp" ] || refuse_in theme "no picture of the theme's own is ${1:-?} -- spark-shell theme screens shows them"
    [ -n "${2:-}" ] || refuse_in theme "loop $1 takes an MP4, or none"
    if [ "$2" = none ]; then rm -f "${_tlp%.*}.mp4"; _tld='still'
    else _tlb=${_tlp##*/}; theme_take "$2" "${_tlb%.*}" loop; theme_taken; _tld='a loop'; fi
    theme_apply "$THEME" >/dev/null
    echo "${_tlp##*/}: $_tld"
}
theme_reel() {   # theme_reel open|close REEL|none -- the dialog's own opening or closing for the theme, an animated WebP copied in as NAME-dialog-open; with both, it plays its own
    case ${1:-} in open|close) ;; *) refuse_in theme "reel takes open or close, then an animated WebP or none" ;; esac
    [ -n "${2:-}" ] || refuse_in theme "reel $1 takes an animated WebP, or none"
    theme_editable; _trn=${_ted##*/}
    if [ "$2" = none ]; then rm -f "$_ted/$_trn-dialog-$1.webp"; _trs="no $1 reel"
    else theme_take "$2" "$_trn-dialog-$1" reel; theme_taken; _trs="the $1 reel set"; fi
    if [ -f "$_ted/$_trn-dialog-open.webp" ] && [ -f "$_ted/$_trn-dialog-close.webp" ]; then
        look_set "$_ted" ANIMATION own; config_locked config_edit DIALOG_ANIMATION own; DIALOG_ANIMATION=own; export DIALOG_ANIMATION
        echo "the theme plays its own opening and closing"
    else
        if [ "$(look_get "$_ted" ANIMATION)" = own ]; then
            _tra=$(anim_for_palette "$(look_get "$_ted" PALETTE)"); look_set "$_ted" ANIMATION "$_tra"
            config_locked config_edit DIALOG_ANIMATION "$_tra"; DIALOG_ANIMATION=$_tra; export DIALOG_ANIMATION
        fi
        echo "$_trs; the theme plays its own once both are there"
    fi
}
theme_duplicate() {   # theme_duplicate NAME NEW... -- any theme as a new one of yours, to change: its folder copied, or a palette's look written
    _dpf=$1; shift
    _dpk=$(theme_kind "$_dpf"); [ -n "$_dpk" ] && [ "$_dpk" != none ] || refuse_in theme "no theme named $_dpf -- spark-shell theme list shows them"
    theme_new_name "$@"
    theme_make "$_tnn" theme_duplicate_files "$_dpf" "$_tnn" || refuse_in theme "could not copy $_dpf$(store_said)"
    echo "$_tnn is a copy of $(theme_label "$_dpf") -- spark-shell theme $_tnn uses it"
}
theme_duplicate_files() {   # theme_duplicate_files NAME NEW NEWDIR
    _dpd=$(theme_dir "$1")
    if [ -n "$_dpd" ]; then theme_copy "$_dpd" "$3" "$2"; return; fi
    _dpp=$(palette_file "$1") && cp "$_dpp" "$3/palette.env" 2>"$TMP/store.why" || return 1
    _dpw=$(wall_for_palette "$1" 2>/dev/null) || _dpw=''
    write_whole "$3/look.env" printf '%s\n' "FORMAT=$LOOK_FORMAT${NL}PALETTE=$1${_dpw:+${NL}WALLPAPER=$_dpw${NL}DRAWING=$_dpw}"
}
theme_rename() {   # theme_rename NAME NEW... -- a theme of yours by a new name: its folder and its own files, and what names it: the config, its families, the history
    _rnf=$1; shift
    case $(theme_kind "$_rnf") in
        saved) ;;
        look) refuse_in theme "$_rnf is not saved yet -- spark-shell theme save NAME keeps it" ;;
        shipped|bundled) refuse_in theme "$_rnf comes with spark-shell -- spark-shell theme duplicate $_rnf NEW makes it yours" ;;
        *) refuse_in theme "no theme of yours named $_rnf" ;;
    esac
    theme_new_name "$@"; _rnd=$(theme_dir "$_rnf"); _rnt=$PALETTE_DIR/$_tnn
    theme_make "$_tnn" theme_rename_files "$_rnd" "$_tnn" || refuse_in theme "could not rename $_rnf$(store_said)"
    _ltk=''
    [ "$_rnf" != "${THEME:-}" ] || look_take THEME "$_tnn"
    case $WALLPAPER in "$_rnd"/*) _rnw=${WALLPAPER#"$_rnd"/}; case $_rnw in "$_rnf"-*) _rnw=$_tnn-${_rnw#"$_rnf"-} ;; esac; look_take WALLPAPER "$_rnt/$_rnw" ;; esac
    look_taken 2>"$TMP/store.why" || { _rns=$(store_said); dir_drop "$_rnt" || :; refuse_in theme "could not rename $_rnf$_rns"; }   # the config first: what it names is always there
    kept_rename theme "$_rnf" "$_tnn" || :
    _rnw=''; families_rename "$_rnf" "$_tnn" || _rnw=$(store_said)
    dir_drop "$_rnd" || refuse_in theme "$_tnn is there, but $_rnf could not be removed$(store_said)"
    [ -z "$_ltk" ] || look_apply || return 1
    [ -z "$_rnw" ] || refuse_in theme "renamed $_rnf to $_tnn, but a family still names $_rnf$_rnw"
    echo "renamed $_rnf to $_tnn"
}
theme_rename_files() { theme_copy "$1" "$3" "$2"; }   # theme_rename_files DIR NEW NEWDIR
theme_back() {   # one look further back each call
    _n=${THEME:-}
    while :; do
        _n=$(kept_back theme "$_n") || refuse_in theme "no look before this one in the last ten"
        [ "$_n" = none ] || ! theme_usable "$_n" >/dev/null || break   # gone looks, broken ones and none skipped
    done
    echo "back to $(theme_words_of "$_n")"
    theme_apply "$_n" back
}
theme_place() {   # theme_place DIR NAME RECEIPT -- a theme from elsewhere, checked, put in place as NAME and used; the gallery's own newer one over its older
    [ -n "$(look_get "$PALETTE_DIR/$2" GALLERY)" ] || ! dir_there "$PALETTE_DIR/$2" || refuse_in theme "$2 is taken -- another name"
    theme_make "$2" theme_place_files "$1" || refuse_in theme "could not put $2 in place$(store_said)"
    echo "$3"
    theme_apply "$2"
}
theme_place_files() { for _tpf in "$1"/*; do cp "$_tpf" "$2/${_tpf##*/}" 2>"$TMP/store.why" || return 1; done; }   # theme_place_files DIR NEWDIR
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
    case $want in /*) _pwy=$(pic_why "$want") || refuse_in theme "$_pwy" ;; esac
    config_set WALLPAPER "$want"
    WALLPAPER=$want; export WALLPAPER
    wall_follow
    look_apply || return 1
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
    config_set FONT "$_f" >/dev/null; FONT=$_f; export FONT; look_apply || return 1; login_follow >/dev/null 2>&1 || :
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
    [ "${FONT%%:*}" != "$_fn" ] || ! config_is FONT "$FONT" || { echo "the text is in $1 already"; return 1; }
    _f="$_fn${FONT#"${FONT%%:*}"}"   # the face swapped, the rest kept
    config_set FONT "$_f" >/dev/null; FONT=$_f; export FONT; look_apply || return 1; login_follow >/dev/null 2>&1 || :
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
theme_family() {   # theme_family [stone|star|banner]
    [ -n "${1:-}" ] || { echo "glyph family $GLYPH_FAMILY $PANEL_SEP stone, star or banner"; return; }
    [ $# -eq 1 ] || refuse_in theme "family takes one word: stone, star or banner"
    family_step "$1" || exit 1
}
family_step() {   # family_step stone|star|banner -> the receipt; 1 when refused
    case " $GLYPH_FAMILIES " in *" $1 "*) ;; *) echo "family takes stone, star or banner"; return 1 ;; esac
    ! config_is GLYPH_FAMILY "$1" || { echo "the glyph family is $1 already"; return 1; }
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
    ! config_is DIALOG_ICONS "$1" || { echo "app icons are $1 already"; return 1; }
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
    ! config_is DIALOG_SPACING "$1" || { echo "app spacing is $1 already"; return 1; }
    config_set DIALOG_SPACING "$1" >/dev/null; DIALOG_SPACING=$1; export DIALOG_SPACING
    echo "app spacing $1"
}
glyphs_step() {   # glyphs_step signs|words -> the receipt; 1 when refused
    case $1 in signs|words) ;; *) echo "glyphs takes signs or words"; return 1 ;; esac
    ! config_is BAR_GLYPHS "$1" || { echo "the bar is in $1 already"; return 1; }
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
    ! config_is WALLPAPER_MOTION "$1" || { echo "the moving wallpaper is $1 already"; return 1; }
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
    ! config_is ALPHA "$_new" || { if [ "$1" = less ]; then echo "transparency is off already"; elif [ "$1" = more ]; then echo "transparency stops at 50%"; else echo "transparency is $(transparency_of "$ALPHA")% already"; fi; return 1; }
    config_set ALPHA "$_new" >/dev/null; ALPHA=$_new; export ALPHA; look_apply || return 1
    _st=$(transparency_of "$_new"); if [ "$_st" -eq 0 ]; then echo "transparency off"; else echo "transparency at $_st%"; fi
}
look_small() {   # look_small PICTURE -> a small PNG, or the PNG itself
    pic_magic "$1" || { echo "${1##*/} is empty or no picture"; return 1; }
    if pic_small "$1" "$TMP/small.png"; then printf '%s' "$TMP/small.png"; return 0; fi
    case $(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z') in png) printf '%s' "$1"; return 0 ;; esac
    [ -z "$(svg_tool)" ] || { echo "${1##*/} could not be read"; return 1; }
    echo "a picture is read through rsvg-convert (the $(svg_pkg) package), which is not installed; a PNG is read without it"; return 1
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
    name=$(look_free "$(basename "${_pp%.*}")"); _d=$LOOKS_DIR/$name
    dir_stage "$_d" || refuse_in theme "the look could not be made$(store_said)"
    write_whole "$_dsn/palette.env" python3 -I "$REPO/lib/look.py" palette "$_small" || { dir_unstage "$_d"; refuse_in theme "the picture's colors could not be read: $(head -1 "$TMP/store.why")"; }
    { cp "$_pp" "$_dsn/${_pp##*/}" 2>"$TMP/store.why" && write_whole "$_dsn/look.env" printf '%s\n' "FORMAT=$LOOK_FORMAT${NL}PALETTE=picture${NL}PICTURE=${_pp##*/}${NL}WALLPAPER=picture" "$(look_picked "$_dsn/palette.env" "$_lp_face" "$_lp_family" "$_lp_animation")" && dir_swap "$_d"; } \
        || { dir_unstage "$_d"; refuse_in theme "the look could not be made$(store_said)"; }
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
    name=$(look_free "$_words"); _d=$LOOKS_DIR/$name
    dir_stage "$_d" || { echo "the look could not be made$(store_said)"; return 1; }
    write_whole "$_dsn/palette.env" python3 -I "$REPO/lib/look.py" words --hue "$1" --accent "$2" --warmth "$3" --contrast "$4" --light "$5" || { echo "no palette from those words: $(head -1 "$TMP/store.why")"; dir_unstage "$_d"; return 1; }
    _lw=$WALLPAPER; [ -z "${11:-}" ] || [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || wall_yours || _lw=${11}   # the drawing, unless yours is a picture
    { write_whole "$_dsn/look.env" printf '%s\n' "FORMAT=$LOOK_FORMAT${NL}PALETTE=words${NL}WORDS=$(printf '%s' "$_words" | tr -cd 'A-Za-z0-9 ,.-' | cut -c1-80)${NL}WALLPAPER=$_lw" "$(look_picked "$_dsn/palette.env" "${8:-}" "${9:-}" "${10:-}")" && dir_swap "$_d"; } \
        || { dir_unstage "$_d"; echo "the look could not be made$(store_said)"; return 1; }
    _twl=$(theme_apply "$name" 2>&1) || { printf '%s\n' "$_twl" | tail -n 1; return 1; }
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
    if ! palette_render "$THEME"; then chk theme fail "THEME=$THEME: $PALETTE_WHY" "spark-shell theme list"; return; fi
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
