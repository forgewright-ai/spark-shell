# shellcheck extended-analysis=false
# ---------------------------------------------- verbs: theme, font, quiet
refuse_in() { echo "spark-shell $1: $2"; exit 1; }   # refuse_in VERB SENTENCE
seat_on() { _r=$(rc_files); _r=${_r%% *}; [ -L "$HOME/$_r" ] && [ "$(readlink "$HOME/$_r")" = "$(rc_tree)/$_r" ]; }
look_now() {   # a palette change: the palette loaded and the drawing drawn in it, the switch, then the files for new windows and the next login
    for _k in $THEME_KEYS; do unset "$_k"; done; theme_load   # the palette just written, never the one before
    wall_follow
    look_burst
    EXPR=$(render_expr)
    seat_on || return 0
    for rel in $RENDERED; do render_one "$REPO/template/$rel" "$HOME/$rel"; done
    prompt_render
    ! desktop_wanted || { wall_missing; desktop_files; }
    [ "$MODE" = dry ] || { tmux_reload; theme_seen; }
}
prompt_render() {   # starship's config from the style; on the desktop also its foot twin, slots 16 and 17 for the accent and the muted color
    [ "$PROMPT" = starship ] || return 0
    render_one "$REPO/template/.config/starship.toml.$PROMPT_STYLE" "$HOME/.config/starship.toml"
    desktop_wanted || return 0
    _ex=$EXPR; EXPR="s|@ACCENT_STAR@|16|g${NL}s|@MUTED_STAR@|17|g${NL}$EXPR"
    render_one "$REPO/template/.config/starship.toml.$PROMPT_STYLE" "$HOME/.config/starship-foot.toml"
    EXPR=$_ex
}
verb_close() {   # verb_close SENTENCE -- the last line of a verb: the count on a dry run, else SENTENCE
    if [ "$MODE" = dry ]; then dry_close
    elif [ "$todos" -gt 0 ]; then echo "Not all of it is done: the todo rows above say what is left."
    else echo "$1"; fi
}

THEME_WORDS='none show list save delete back wallpaper text transparency animation glyphs icons spacing family face workspaces motion picture gallery install preview'   # cmd_theme's own words: no theme may take one as its name
cmd_theme() {   # theme [NAME|none|list|show] | save [NAME] | delete NAME | back | wallpaper [X] | text [N|bigger|smaller] | transparency [N|more|less] | animation [NAME|none|next|back] | glyphs [signs|words] | family [stone|star|banner] | face NAME | motion [on|off] | picture PATH [face= family= animation=] | gallery | install NAME | "WORDS"
    config_load
    case ${1:-show} in
        show) [ $# -le 1 ] || refuse_in theme "show takes no word"; theme_show; return ;;
        list) [ $# -le 1 ] || refuse_in theme "list takes no word"; theme_list; return ;;
        save) shift; theme_save "$@"; return ;;
        delete) shift; theme_delete "$@"; return ;;
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
        workspaces) refuse_in theme "the glyph family names the workspaces now -- spark-shell theme family stone, star or banner" ;;   # never read as words for a theme
        motion) shift; theme_motion "$@"; return ;;
        picture) shift; theme_picture "$@"; return ;;
        gallery) shift; theme_gallery "$@"; return ;;
        install) shift; theme_install "$@"; return ;;
    esac
    case "$*" in *' '*) theme_from_words "$*"; return ;; esac   # words: the model reads them into a look
    [ -n "$(theme_kind "$1")" ] || refuse_in theme "no palette named $1 -- spark-shell theme list shows them"
    theme_apply "$1"
}
anim_follow() {   # anim_follow PIECE -- the dialog's animation follows the look; none stays none
    [ "${DIALOG_ANIMATION:-}" != none ] && [ "${DIALOG_ANIMATION:-}" != "$1" ] || return 0
    [ "$MODE" = dry ] || config_set DIALOG_ANIMATION "$1" >/dev/null
    DIALOG_ANIMATION=$1; export DIALOG_ANIMATION
}
theme_apply() {   # theme_apply NAME|none [back] -- the whole look follows the theme; back leaves the history as it is
    name=$1; _w=''
    _td=$(theme_dir "$name")
    if [ -n "$_td" ]; then _lw=$(look_ok "$_td") || refuse_in theme "$name cannot be used: $_lw. Nothing was changed"; fi
    [ "$name" = none ] || palette_render "$name" || refuse_in theme "$(cat "$TMP/palette.why")"
    PALETTE_RENDERED=$name   # theme_files takes these files as they are
    pm_detect
    _td=$(theme_dir "$name")
    if [ -n "$_td" ]; then
        _lfc=$(look_get "$_td" FACE); _lsz=$(look_get "$_td" TEXT_SIZE)
        for _k in WALLPAPER FONT ALPHA POINTER; do
            _v=$(look_get "$_td" "$_k")
            [ "$_k:$_v" != WALLPAPER:picture ] || _v=$_td/$(look_get "$_td" PICTURE)
            [ "$_k" != FONT ] || [ -z "$_lfc$_lsz" ] || _v=$(font_with "$_lfc" "$_lsz")   # format 2: the face and the size, each kept when the theme names none
            [ "$_k" != FONT ] || case $_v:$FONT in "$NEON_OLD"*:"$NEON"*) _v="$NEON${_v#"$NEON_OLD"}" ;; esac   # a theme saved on the old face keeps its size, in the face in use
            [ "$_k" != FONT ] || [ -z "$_v" ] || face_word "${_v%%:*}" >/dev/null || _v="${FONT%%:*}${_v#"${_v%%:*}"}"   # only a curated face is taken; its size is
            [ -n "$_v" ] || [ "$_k" = POINTER ] || continue
            [ "$_k" != POINTER ] || grep -q '^POINTER=' "$_td/look.env" || continue   # a theme that names no pointer (the gallery's) keeps yours
            eval "_cur=\$$_k"
            # shellcheck disable=SC2154   # _cur is set by the eval above
            [ "$MODE" = dry ] || [ "$_cur" = "$_v" ] || config_set "$_k" "$_v" >/dev/null
            eval "$_k=\$_v"; export "${_k?}"
        done
        _an=$(look_get "$_td" ANIMATION); case " $ANIMATION_NAMES " in *" $_an "*) ;; *) _an=$(anim_for_palette "$(look_get "$_td" PALETTE)") ;; esac
        anim_follow "$_an"
        bar_look_follow "$(look_get "$_td" BAR_GLYPHS)" "$(look_get "$_td" GLYPH_FAMILY)"
        case $(look_get "$_td" DIALOG_ICONS) in on|off) _li=$(look_get "$_td" DIALOG_ICONS); [ "$_li" = "$DIALOG_ICONS" ] || { [ "$MODE" = dry ] || config_set DIALOG_ICONS "$_li" >/dev/null; DIALOG_ICONS=$_li; export DIALOG_ICONS; } ;; esac
        case $(look_get "$_td" DIALOG_SPACING) in none|groups|rows) _ls=$(look_get "$_td" DIALOG_SPACING); [ "$_ls" = "$DIALOG_SPACING" ] || { [ "$MODE" = dry ] || config_set DIALOG_SPACING "$_ls" >/dev/null; DIALOG_SPACING=$_ls; export DIALOG_SPACING; } ;; esac
        case $(look_get "$_td" WALLPAPER_MOTION) in on|off) _lm=$(look_get "$_td" WALLPAPER_MOTION); [ "$_lm" = "$WALLPAPER_MOTION" ] || { [ "$MODE" = dry ] || config_set WALLPAPER_MOTION "$_lm" >/dev/null; WALLPAPER_MOTION=$_lm; export WALLPAPER_MOTION; } ;; esac
    elif [ "$name" != none ] && [ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && ! wall_yours && _w=$(wall_for_palette "$name") && [ "$_w" != "$WALLPAPER" ]; then   # the palette brings its own drawing; only a picture of yours stays
        [ "$MODE" = dry ] || config_set WALLPAPER "$_w" >/dev/null
        WALLPAPER=$_w; export WALLPAPER
    else _w=''; fi
    [ -n "$_td" ] || [ "$name" = none ] || anim_follow "$(anim_for_palette "$name")"
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
    [ "${2:-}" = back ] || [ "$MODE" = dry ] || [ "$name" = none ] || kept_note theme "$name"   # none is no look to come back to
    if [ "$name" = none ]; then verb_close "No palette: the console and the terminal use their default colors."
    elif [ -n "$_td" ]; then verb_close "The theme is $(theme_words_of "$name"): $(theme_look_words). A program that is already running, such as btop, takes it when it starts again."
    else verb_close "The palette is $name${_w:+, with $_w}. A program that is already running, such as btop, takes it when it starts again."; fi
}
wall_now() { _wn=$(wall_name); printf '%s' "${_wn:-$(basename "$(wall_path)")}"; }   # -> the wallpaper's word, or a picture's file name
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
theme_save() {   # theme_save [NAME...] -- the look in use kept as a folder under that name; a look from words or a picture keeps its own name when none is given
    [ -n "${THEME:-}" ] && [ "$THEME" != none ] || refuse_in theme "no palette is in use -- spark-shell theme NAME first"
    name=$(desk_name_of "$*")
    if [ -z "$name" ]; then case $(theme_kind "$THEME") in look) name=$THEME ;; *) refuse_in theme "save NAME -- a name for this look" ;; esac; fi
    case $(theme_kind "$name") in shipped|yours) refuse_in theme "$name is a palette's name -- give the theme another" ;; esac
    _pf=$(palette_file "$THEME") || refuse_in theme "no palette named $THEME -- spark-shell theme list shows them"
    _d=$PALETTE_DIR/$name
    if [ -d "$_d" ] && [ "$name" != "$THEME" ]; then
        if [ -t 0 ] && { : < /dev/tty; } 2>/dev/null; then
            printf 'write over the saved theme %s? [y/N] ' "$name" > /dev/tty; IFS= read -r _y < /dev/tty || _y=''
            case $_y in y|Y|yes) ;; *) refuse_in theme "$name kept as it was" ;; esac
        else refuse_in theme "$name is saved already -- spark-shell theme delete $name first, or another name"; fi
    fi
    theme_load
    _src=$(theme_dir "$THEME")
    mkdir_private "$PALETTE_DIR"; rm -rf "$_d.new"; mkdir -p "$_d.new"
    cp "$_pf" "$_d.new/palette.env"
    _origin=$THEME; [ -z "$_src" ] || _origin=$(look_get "$_src" PALETTE)
    _tsp=''   # the look's own picture, copied into the folder
    {
        printf 'FORMAT=%s\nPALETTE=%s\n' "$LOOK_FORMAT" "${_origin:-$THEME}"
        _ws=''; [ -z "$_src" ] || _ws=$(look_get "$_src" WORDS); [ -z "$_ws" ] || printf 'WORDS=%s\n' "$_ws"
        if wall_shipped "$WALLPAPER"; then
            printf 'WALLPAPER=%s\nDRAWING=%s\n' "$WALLPAPER" "$WALLPAPER"
            _wp=$(wall_path); cp "$_wp" "$_d.new/wallpaper.png"; [ ! -f "${_wp%.png}.svg" ] || cp "${_wp%.png}.svg" "$_d.new/wallpaper.svg"
        elif wall_there; then
            _tsp=${WALLPAPER##*/}; cp "$WALLPAPER" "$_d.new/$_tsp"; printf 'WALLPAPER=picture\nPICTURE=%s\n' "$_tsp"
        else printf 'WALLPAPER=%s\n' "$WALLPAPER"; fi
        _fc=$(face_word "${FONT%%:*}") || _fc=''; [ -z "$_fc" ] || printf 'FACE=%s\n' "$_fc"   # a face of your own is no theme's
        _fs=$(look_font_size); case $_fs in [6-9]|[1-3][0-9]|40) printf 'TEXT_SIZE=%s\n' "$_fs" ;; esac   # a size theme text never sets stays out
        printf 'ALPHA=%s\nPOINTER=%s\nANIMATION=%s\nBAR_GLYPHS=%s\nGLYPH_FAMILY=%s\nWALLPAPER_MOTION=%s\nDIALOG_ICONS=%s\nDIALOG_SPACING=%s\n' "$ALPHA" "${POINTER:-}" "$(anim_now)" "$BAR_GLYPHS" "$GLYPH_FAMILY" "$WALLPAPER_MOTION" "$DIALOG_ICONS" "$DIALOG_SPACING"
    } > "$_d.new/look.env"
    rm -rf "$_d"; mv "$_d.new" "$_d"
    echo "saved $name ($_d) -- spark-shell theme $name brings the look back"
    # the look just kept becomes the theme in use; nothing is drawn again
    [ "$THEME" = "$name" ] || config_set THEME "$name" >/dev/null
    THEME=$name; export THEME
    if [ -n "$_tsp" ] && [ "$WALLPAPER" != "$_d/$_tsp" ]; then   # the folder's copy of the picture from now on
        config_set WALLPAPER "$_d/$_tsp" >/dev/null; WALLPAPER=$_d/$_tsp; export WALLPAPER
        ! desktop_wanted || sway_file_apply   # sway's file names the copy
    fi
    kept_note theme "$name"
}
theme_delete() {   # theme_delete NAME... -- a saved theme's folder and its history lines gone; never a palette, never the theme in use
    name=$(desk_name_of "$*"); [ -n "$name" ] || refuse_in theme "delete NAME -- which theme?"
    case $(theme_kind "$name") in
        saved|look) ;;
        shipped) refuse_in theme "$name is a palette spark-shell ships, not a saved theme" ;;
        yours) refuse_in theme "$name is a palette file of yours ($PALETTE_DIR/$name.env): remove the file to drop it" ;;
        *) refuse_in theme "no saved theme named $name -- spark-shell theme list shows them" ;;
    esac
    [ "$name" != "${THEME:-}" ] || refuse_in theme "$name is the theme in use -- spark-shell theme NAME another first"
    kept_delete_ok theme "$name" || return 0
    rm -rf "$(theme_dir "$name")"
    _kh=$(kept_hist theme); [ ! -f "$_kh" ] || { awk -F '\t' -v n="$name" '$2 != n' "$_kh" > "$_kh.new" && mv "$_kh.new" "$_kh"; }
    echo "deleted $name"
}
theme_back() {   # the look before this one, one step further each time
    while :; do
        _n=$(kept_back theme "${THEME:-}") || refuse_in theme "no look before this one in the last ten"
        [ "$_n" != none ] && palette_file "$_n" >/dev/null && break   # a look that is gone is skipped, and none
    done
    echo "back to $(theme_words_of "$_n")"
    theme_apply "$_n" back
}
theme_wallpaper() {   # theme_wallpaper [X] -- the wallpaper: a drawing, a picture, a color or default (the ground); bare, what it is now
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
    wall_value_ok "$want" || refuse_in theme "$PATH_REFUSED"   # the config would refuse it at the next read
    config_set WALLPAPER "$want"
    WALLPAPER=$want; export WALLPAPER
    wall_follow   # its row: the drawing drawn in the palette, or why it cannot be
    look_apply
    login_follow
    _tr="the windows keep their transparency, $(transparency_of "$ALPHA")%"; [ "$(transparency_of "$ALPHA")" -ne 0 ] || _tr="the windows are solid (spark-shell theme transparency N)"
    if [ "$1" = none ]; then echo "the ground is back: none is the ground now, and $_tr"
    elif [ "$want" = default ]; then echo "the ground is back -- the palette's background a shade darker, and it follows the palette"
    elif wall_color; then echo "a running sway shows $want now, and $_tr; a palette with a drawing of its own replaces it"
    elif wall_shipped "$want"; then case $(wall_path) in "$REPO"/*) _dr='' ;; *) _dr=", drawn in $THEME" ;; esac; echo "a running sway shows $want now$_dr -- it follows the palette: a palette with a drawing of its own brings that one"
    else echo "a running sway shows it now, and $_tr"; fi
}
theme_text() {   # theme_text [N|bigger|smaller] -- the text size for every surface; the pointer's size follows it
    _sz=$(look_font_size); [ -n "$_sz" ] || refuse_in theme "FONT=$FONT has no size to change (the config)"
    [ -n "${1:-}" ] || { echo "text $_sz $PANEL_SEP the pointer $(pointer_size_for "$_sz") pixels"; return; }
    case $1 in bigger|smaller) ;; [6-9]|[1-3][0-9]|40) ;; *) refuse_in theme "text takes a size, 6 to 40, or bigger or smaller" ;; esac
    text_step "$1" || exit 1
}
text_step() {   # text_step N|bigger|smaller -> the receipt, or the refusal and 1
    _sz=$(look_font_size); [ -n "$_sz" ] || { echo "FONT=$FONT has no size to change (the config)"; return 1; }
    case $1 in bigger) _new=$((_sz + 1)) ;; smaller) _new=$((_sz - 1)) ;; *) _new=$1 ;; esac
    [ "$_new" -ge 6 ] && [ "$_new" -le 40 ] || { echo "text size $_sz stays (6 to 40)"; return 1; }
    _f=$(printf '%s' "$FONT" | sed "s/size=$_sz/size=$_new/")
    config_set FONT "$_f" >/dev/null; FONT=$_f; export FONT; look_apply; login_follow >/dev/null 2>&1 || :
    echo "text at $_new $PANEL_SEP new windows and the bar take it; the pointer $(pointer_size_for "$_new") pixels"
}
theme_face() {   # theme_face [neon|argon|xenon|radon|krypton] -- the text's face; FONT keeps its size
    [ -n "${1:-}" ] || { echo "face $(face_word "${FONT%%:*}" || printf '%s' "${FONT%%:*}") $PANEL_SEP neon, argon, xenon, radon or krypton"; return; }
    [ $# -eq 1 ] || refuse_in theme "face takes one word: neon, argon, xenon, radon or krypton"
    face_step "$1" || exit 1
}
face_step() {   # face_step NAME -> the receipt, or the refusal and 1
    case " $FONT_FACES " in *" $1 "*) ;; *) echo "face takes neon, argon, xenon, radon or krypton"; return 1 ;; esac
    [ "$OS" != Darwin ] || { echo "on a Mac the text is Terminal.app's: spark-shell font FACE SIZE"; return 1; }
    _fn=$(face_name "$1")
    [ "${FONT%%:*}" != "$_fn" ] || { echo "the text is in $1 already"; return 1; }
    _f="$_fn${FONT#"${FONT%%:*}"}"   # the face swapped, its size and the rest as they were
    config_set FONT "$_f" >/dev/null; FONT=$_f; export FONT; look_apply; login_follow >/dev/null 2>&1 || :
    if [ "$1" = neon ] || face_ours "$1"; then echo "text in $1 $PANEL_SEP new windows and the bar take it"
    else echo "text in $1 $PANEL_SEP from spark-shell on, which installs it; neon until then"; fi
}
theme_animation() {   # theme_animation [NAME|none|next|back] -- the dialog's transitions: a piece by name, none for no motion
    [ -n "${1:-}" ] || { echo "animation $(anim_now) $PANEL_SEP none, $(printf '%s' "$ANIMATION_NAMES" | sed 's/ /, /g')"; return; }
    [ $# -eq 1 ] || refuse_in theme "animation takes one word"
    anim_step "$1" || exit 1
}
anim_step() {   # anim_step NAME|none|next|back -> the receipt, or the refusal and 1
    # shellcheck disable=SC2086   # the names, a word each, on purpose
    case $1 in
        next|back) _an=$(printf '%s\n' none $ANIMATION_NAMES | awk -v c="$(anim_now)" -v d="$1" '{ n[NR] = $0; if ($0 == c) i = NR } END { if (!i) i = 1; print n[d == "next" ? i % NR + 1 : (i + NR - 2) % NR + 1] }') ;;
        *) case " none $ANIMATION_NAMES " in *" $1 "*) _an=$1 ;; *) echo "animation takes none, $(printf '%s' "$ANIMATION_NAMES" | sed 's/ /, /g'), next or back"; return 1 ;; esac ;;
    esac
    config_set DIALOG_ANIMATION "$_an" >/dev/null; DIALOG_ANIMATION=$_an; export DIALOG_ANIMATION
    if [ "$_an" = none ]; then echo "animation none $PANEL_SEP the dialog opens and closes with no motion"; else echo "animation $_an $PANEL_SEP from the dialog's next opening"; fi
}
bar_look_follow() {   # bar_look_follow GLYPHS FAMILY -- a saved theme's bar glyphs and glyph family, each when it names one
    _bc=''
    case ${1:-} in signs|words) [ "$1" = "$BAR_GLYPHS" ] || { [ "$MODE" = dry ] || config_set BAR_GLYPHS "$1" >/dev/null; BAR_GLYPHS=$1; export BAR_GLYPHS; _bc=1; } ;; esac
    case " $GLYPH_FAMILIES " in *" ${2:-none} "*) [ "$2" = "$GLYPH_FAMILY" ] || { [ "$MODE" = dry ] || config_set GLYPH_FAMILY "$2" >/dev/null; GLYPH_FAMILY=$2; export GLYPH_FAMILY; _bc=1; } ;; esac
    [ -n "$_bc" ] && [ "$MODE" != dry ] || return 0
    bar_redraw; [ -z "${SWAYSOCK:-}" ] || bar_ws_names
}
theme_family() {   # theme_family [stone|star|banner] -- the glyph family
    [ -n "${1:-}" ] || { echo "glyph family $GLYPH_FAMILY $PANEL_SEP stone, star or banner"; return; }
    [ $# -eq 1 ] || refuse_in theme "family takes one word: stone, star or banner"
    family_step "$1" || exit 1
}
family_step() {   # family_step stone|star|banner -> the receipt, or the refusal and 1
    case " $GLYPH_FAMILIES " in *" $1 "*) ;; *) echo "family takes stone, star or banner"; return 1 ;; esac
    [ "$1" != "$GLYPH_FAMILY" ] || { echo "the glyph family is $1 already"; return 1; }
    config_set GLYPH_FAMILY "$1" >/dev/null; GLYPH_FAMILY=$1; export GLYPH_FAMILY
    bar_redraw; [ -z "${SWAYSOCK:-}" ] || bar_ws_names
    echo "glyph family $1"
}
theme_glyphs() {   # theme_glyphs [signs|words] -- the bar's glyphs
    [ -n "${1:-}" ] || { echo "the bar in $BAR_GLYPHS $PANEL_SEP signs or words"; return; }
    [ $# -eq 1 ] || refuse_in theme "glyphs takes one word: signs or words"
    glyphs_step "$1" || exit 1
}
theme_icons() {   # theme_icons [on|off] -- each app's icon before its name in home's apps
    [ -n "${1:-}" ] || { echo "app icons $DIALOG_ICONS $PANEL_SEP on or off"; return; }
    [ $# -eq 1 ] || refuse_in theme "icons takes one word: on or off"
    icons_step "$1" || exit 1
}
icons_step() {   # icons_step on|off -> the receipt, or the refusal and 1
    case $1 in on|off) ;; *) echo "icons takes on or off"; return 1 ;; esac
    [ "$1" != "$DIALOG_ICONS" ] || { echo "app icons are $1 already"; return 1; }
    config_set DIALOG_ICONS "$1" >/dev/null; DIALOG_ICONS=$1; export DIALOG_ICONS
    echo "app icons $1"
}
theme_spacing() {   # theme_spacing [none|groups|rows] -- the space around home's apps
    [ -n "${1:-}" ] || { echo "app spacing $DIALOG_SPACING $PANEL_SEP none, groups or rows"; return; }
    [ $# -eq 1 ] || refuse_in theme "spacing takes one word: none, groups or rows"
    spacing_step "$1" || exit 1
}
spacing_step() {   # spacing_step none|groups|rows -> the receipt, or the refusal and 1
    case $1 in none|groups|rows) ;; *) echo "spacing takes none, groups or rows"; return 1 ;; esac
    [ "$1" != "$DIALOG_SPACING" ] || { echo "app spacing is $1 already"; return 1; }
    config_set DIALOG_SPACING "$1" >/dev/null; DIALOG_SPACING=$1; export DIALOG_SPACING
    echo "app spacing $1"
}
glyphs_step() {   # glyphs_step signs|words -> the receipt, or the refusal and 1
    case $1 in signs|words) ;; *) echo "glyphs takes signs or words"; return 1 ;; esac
    [ "$1" != "$BAR_GLYPHS" ] || { echo "the bar is in $1 already"; return 1; }
    config_set BAR_GLYPHS "$1" >/dev/null; BAR_GLYPHS=$1; export BAR_GLYPHS; bar_redraw
    echo "the bar in $1"
}
# the moving wallpaper: a loop a wallpaper, made by mpv into the cache by wallpaper,
# palette and size, played by spark-wallpaper over the still; a player of yours is never stopped
MOTION_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/spark-shell/motion
motion_names() { for _ms in "$REPO"/lib/motion_*.py; do [ -f "$_ms" ] || continue; _ms=${_ms##*/motion_}; printf '%s\n' "${_ms%.py}"; done; printf '%s\n' $WALL_SCENES; }   # -> the wallpapers that move, one a line
motion_has() { wall_scene "$1" || { wall_shipped "$1" && [ -f "$REPO/lib/motion_$1.py" ]; }; }   # motion_has WALLPAPER -> 0 when it moves
motion_missing() {   # -> what a loop of the wallpaper in use needs that is not here, or nothing
    _mm=''
    command -v mpv >/dev/null 2>&1 || _mm="$_mm mpv"
    if wall_scene "${WALLPAPER:-}"; then scene_ready || _mm="$_mm numpy"
    else for _mt in python3 rsvg-convert; do command -v "$_mt" >/dev/null 2>&1 || _mm="$_mm $_mt"; done; fi
    player_cmd >/dev/null || _mm="$_mm spark-wallpaper"
    printf '%s' "${_mm# }"
}
motion_why() {   # -> why a moving wallpaper cannot play here, or nothing (after pm_detect)
    [ "$OS" != Darwin ] || { echo "the moving wallpaper is the Linux desktop's: macOS has its own"; return; }
    [ "$DESKTOP" = sway ] || { echo "the moving wallpaper is the desktop's: spark-shell on desktop first"; return; }
    _mw=$(motion_missing); [ -n "$_mw" ] || return 0
    echo "the moving wallpaper needs $_mw: spark-shell on desktop installs it"
}
motion_want() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-motion.want"; }   # -> the file that holds the player's words, one a line
motion_ours() {   # -> the pids of the players playing a loop of ours (a file in the cache)
    if command -v pgrep >/dev/null 2>&1; then { pgrep -u "$(id -u)" -f "spark-wallpaper .*$MOTION_DIR/"; pgrep -u "$(id -u)" -f "mpvpaper .*$MOTION_DIR/"; } 2>/dev/null || :; return 0; fi
    # no pgrep (a bare container has none): the same from /proc
    _muid=$(id -u)
    grep -l -s -F "$MOTION_DIR/" /proc/[0-9]*/cmdline 2>/dev/null | while IFS= read -r _mc; do
        _mpid=${_mc#/proc/}; _mpid=${_mpid%/cmdline}
        { tr '\0' ' ' < "$_mc"; } 2>/dev/null | grep -Eq '(^|/)(spark-wallpaper|mpvpaper) -' || continue   # a process gone meanwhile has no file
        [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/$_mpid/status" 2>/dev/null)" != "$_muid" ] || echo "$_mpid"
    done || :
}
motion_stop() {   # the loops of ours gone, and nothing wanted
    rm -f "$(motion_want)"
    for _mp in $(motion_ours); do kill "$_mp" 2>/dev/null || :; done
}
motion_play() {   # motion_play ARGS... -- spark-wallpaper on ARGS in its own session, any other loop of ours stopped
    _mpc=$(player_cmd) || return 0
    for _mp in $(motion_ours); do kill "$_mp" 2>/dev/null || :; done
    if command -v setsid >/dev/null 2>&1; then setsid "$_mpc" "$@" </dev/null >/dev/null 2>&1 &
    else ( trap '' HUP; exec "$_mpc" "$@" ) </dev/null >/dev/null 2>&1 & fi
}
motion_make() {   # motion_make DRAWING SEDFILE OUT -- the drawing's loop: its script's frames recolored by SEDFILE (empty: as drawn), made into OUT by mpv
    _md=$(mktemp -d "${TMPDIR:-/tmp}/spark-shell-motion.XXXXXX") || return 1
    if python3 -I "$REPO/lib/motion_$1.py" "$_md" >/dev/null 2>&1 && [ -f "$_md/f0000.svg" ] \
        && printf '%s\n' "$_md"/f*.svg | xargs -P "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" -n 32 sh -c 's=$1; shift; for f; do if [ -s "$s" ]; then sed -f "$s" "$f"; else cat "$f"; fi | rsvg-convert -o "${f%.svg}.png" || exit 1; done' _ "$2" \
        && mpv --no-config --really-quiet "mf://$_md/f*.png" --mf-fps=30 --vf=format=yuv420p --ovc=libx264 --ovcopts=crf=20,preset=medium --of=mp4 --o="$3.part" </dev/null >/dev/null 2>&1 \
        && [ -s "$3.part" ] && mv "$3.part" "$3"; then _mk=0; else _mk=1; rm -f "$3.part"; fi
    rm -rf "${_md:?}"
    return "$_mk"
}
scene_info() {   # scene_info SCENE WxH -> make.py's info line for the scene at that size (fps, kind, grid), cached
    _sik=$MOTION_DIR/info-$1-$2-$(cksum < "$SCENE_MAKE" | cut -d' ' -f1).json
    [ -s "$_sik" ] || { mkdir -p "$MOTION_DIR" && python3 -I "$SCENE_MAKE" --info --scene "$1" --size "$2" > "$_sik.new" 2>/dev/null && mv "$_sik.new" "$_sik"; } || { rm -f "$_sik.new"; return 1; }
    cat "$_sik"
}
scene_loop_size() {   # scene_loop_size SCENE WxH -> the loop's size for that screen: a pixel scene's grid, else the screen's own, even for the video
    _sls=$(scene_info "$1" "$2" | jq -r 'if .kind == "pixel" and .grid != null then (.grid | if type == "array" then "\(.[0])x\(.[1])" else tostring end) else empty end' 2>/dev/null) || return 1
    [ -n "$_sls" ] || { _slw=${2%x*}; _slh=${2#*x}; _sls="$((_slw - _slw % 2))x$((_slh - _slh % 2))"; }
    printf '%s' "$_sls"
}
motion_make_scene() {   # motion_make_scene SCENE PALETTE_FILE WxH OUT -- the scene's loop at that size in that palette; a pixel scene lossless 4:4:4
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
motion_screens() {   # -> NAME<tab>WxH for each screen on, its size in pixels
    swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.active) | [.name, (((.rect.width * (.scale // 1)) | floor | tostring) + "x" + ((.rect.height * (.scale // 1)) | floor | tostring))] | @tsv' 2>/dev/null || :
}
scene_screens() {   # a scene's still on each portrait screen, drawn for its shape, in the background
    wall_scene "${WALLPAPER:-}" && _ssp=$(palette_file "${THEME:-}" 2>/dev/null) && scene_ready || return 0
    _ssl=$(motion_screens | awk -F '\t' '{ split($2, s, "x"); if (s[2] + 0 > s[1] + 0) print }')
    [ -n "$_ssl" ] || return 0
    ( printf '%s\n' "$_ssl" | while IFS="$TAB" read -r _ssn _sss; do   # the list in hand: TMP goes with the step that started this
          _ssf=$WALL_CACHE/$WALLPAPER-$THEME-$_sss.png
          [ -f "$_ssf" ] || { mkdir_state "$WALL_CACHE" && scene_still "$WALLPAPER" "$_ssp" "$_sss" "$_ssf"; } || continue
          swaymsg -- "output \"$_ssn\" bg \"$_ssf\" fill" >/dev/null 2>&1 || :
      done ) </dev/null >/dev/null 2>&1 3>&- 4<&- &
}
MOTION_NOW=''   # what motion_follow did: playing, making (they play once made), or nothing
motion_follow() {   # the loops of the wallpaper in use, in the palette in use, a screen each: playing, or made first in the background; else none of ours
    MOTION_NOW=''
    [ "$OS" != Darwin ] && desk_in_sway || return 0
    scene_screens
    if [ "${WALLPAPER_MOTION:-off}" != on ] || ! motion_has "${WALLPAPER:-}" || [ -n "$(motion_missing)" ]; then motion_stop; return 0; fi
    _mj=$(mktemp -d "${TMPDIR:-/tmp}/spark-shell-motion.XXXXXX") || return 0
    mkdir -p "$MOTION_DIR"
    if wall_scene "$WALLPAPER"; then   # a loop a screen: LOOP<tab>SIZE<tab>SCREEN a line
        _mpf=$(palette_file "${THEME:-}" 2>/dev/null) || { rm -rf "${_mj:?}"; motion_stop; return 0; }   # a scene is drawn in a palette: with none, its still alone
        cp "$_mpf" "$_mj/palette.env"
        _msum=$(cat "$SCENE_MAKE" "$_mpf" | cksum | cut -d' ' -f1)
        motion_screens | while IFS="$TAB" read -r _mn _ms; do
            _msz=$(scene_loop_size "$WALLPAPER" "$_ms") || continue
            printf '%s\t%s\t%s\n' "$MOTION_DIR/$WALLPAPER-$_msum-$_msz.mp4" "$_msz" "$_mn"
        done > "$_mj/plan"
        [ -s "$_mj/plan" ] || { rm -rf "${_mj:?}"; motion_stop; return 0; }
        _mscale=smooth; [ "$(scene_info "$WALLPAPER" "$(motion_screens | awk -F '\t' 'NR == 1 { print $2 }')" | jq -r '.kind // empty' 2>/dev/null)" != pixel ] || _mscale=nearest
        { printf -- '--scale\n%s\n' "$_mscale"; awk -F '\t' '{ print "--screen"; print $3 "=" $1 }' "$_mj/plan"; } > "$_mj/args"
    else   # a drawing's one loop, every screen alike
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
    [ ! -f "$MOTION_DIR/making" ] || ! pid_running "$(cat "$MOTION_DIR/making" 2>/dev/null)" || { rm -rf "${_mj:?}"; return 0; }   # being made: the newest wanted plays once ready
    for _mp in $(motion_ours); do kill "$_mp" 2>/dev/null || :; done   # the loops before are not this look's
    ( trap '' HUP; sh -c 'echo "$PPID"' > "$MOTION_DIR/making"
      _mok=1
      while IFS="$TAB" read -r _mf _msz _mn; do
          [ ! -f "$_mf" ] || continue
          if [ "$_msz" = drawing ]; then motion_make "$WALLPAPER" "$_mj/palette.sed" "$_mf" || _mok=0
          else motion_make_scene "$WALLPAPER" "$_mj/palette.env" "$_msz" "$_mf" || _mok=0; fi
      done < "$_mj/plan"
      if [ "$_mok" = 1 ] && cmp -s "$_mj/args" "$(motion_want)"; then
          motion_play_want
          for _mo in "$MOTION_DIR/$WALLPAPER"-*.mp4; do grep -qF "$_mo" "$_mj/plan" || rm -f "$_mo"; done   # the wallpaper's loops of another palette or size
      fi
      rm -f "$MOTION_DIR/making"; rm -rf "${_mj:?}" ) </dev/null >/dev/null 2>&1 3>&- 4<&- &
}
motion_play_want() {   # the player started on the want file's words
    [ -f "$(motion_want)" ] || return 0
    set --; while IFS= read -r _ma; do set -- "$@" "$_ma"; done < "$(motion_want)"
    motion_play "$@"
}
motion_row() {   # the moving wallpaper's row of on and on desktop, when it is on
    [ "${WALLPAPER_MOTION:-off}" = on ] || return 0
    _mw=$(motion_why); if [ -z "$_mw" ]; then ok motion "the moving wallpaper is on: $(motion_names | grep -c '') wallpapers move"; else skip motion "$_mw"; fi
}
theme_motion() {   # theme_motion [on|off] -- the moving wallpaper
    [ -n "${1:-}" ] || { echo "moving wallpaper $WALLPAPER_MOTION $PANEL_SEP on or off; $(motion_names | grep -c '') wallpapers move"; return; }
    [ $# -eq 1 ] || refuse_in theme "motion takes one word: on or off"
    motion_step "$1" || exit 1
}
motion_step() {   # motion_step on|off -> the receipt, or the refusal and 1
    case $1 in on|off) ;; *) echo "motion takes on or off"; return 1 ;; esac
    [ "$1" != "$WALLPAPER_MOTION" ] || { echo "the moving wallpaper is $1 already"; return 1; }
    if [ "$1" = on ]; then [ -n "${PM:-}" ] || pm_detect; _mw=$(motion_why); [ -z "$_mw" ] || { echo "$_mw"; return 1; }; fi
    config_set WALLPAPER_MOTION "$1" >/dev/null; WALLPAPER_MOTION=$1; export WALLPAPER_MOTION
    motion_follow
    if [ "$1" = off ]; then echo "moving wallpaper off"
    elif motion_has "$WALLPAPER"; then case $MOTION_NOW in making) echo "moving wallpaper on $PANEL_SEP $WALLPAPER moves once its loop is made" ;; playing) echo "moving wallpaper on $PANEL_SEP $WALLPAPER moves" ;; *) echo "moving wallpaper on $PANEL_SEP $WALLPAPER moves on the desktop" ;; esac
    else echo "moving wallpaper on $PANEL_SEP $WALLPAPER is still; $(motion_names | grep -c '') wallpapers move"; fi
}
theme_transparency() {   # theme_transparency [N|more|less] -- the windows' transparency, 0 (off) to 50 percent; more and less step by 10
    _st=$(transparency_of "$ALPHA")
    [ -n "${1:-}" ] || { if [ "$_st" -eq 0 ]; then echo "transparency off"; else echo "transparency $_st%"; fi; return; }
    case ${1%\%} in more|less) ;; [0-9]|[1-4][0-9]|50) ;; *) refuse_in theme "transparency takes a percent, 0 to 50, or more or less" ;; esac
    alpha_step "${1%\%}" || exit 1
}
alpha_step() {   # alpha_step N|more|less -> the receipt, or the refusal and 1
    case $1 in
        more) _d=-0.1 ;; less) _d=0.1 ;;
        *) _d=$(awk -v n="$1" 'BEGIN { printf "%.2f", 1 - n / 100 }'); _d=$(awk -v a="$ALPHA" -v v="$_d" 'BEGIN { printf "%.2f", v - a }') ;;
    esac
    _new=$(awk -v a="$ALPHA" -v d="$_d" 'BEGIN { v = a + d; if (v > 1) v = 1; if (v < 0.5) v = 0.5; s = sprintf("%.2f", v); sub(/0$/, "", s); print s }')
    [ "$_new" != "$ALPHA" ] || { if [ "$1" = less ]; then echo "transparency is off already"; elif [ "$1" = more ]; then echo "transparency stops at 50%"; else echo "transparency is $(transparency_of "$ALPHA")% already"; fi; return 1; }
    config_set ALPHA "$_new" >/dev/null; ALPHA=$_new; export ALPHA; look_apply
    _st=$(transparency_of "$_new"); if [ "$_st" -eq 0 ]; then echo "transparency off"; else echo "transparency at $_st%"; fi
}
# a theme from a picture: its colors as the palette, the picture as the wallpaper, a look
# folder under the state
look_small() {   # look_small PICTURE -> a small PNG of it in TMP, or the PNG itself; one line and 1 when neither can be
    if pic_small "$1" "$TMP/small.png"; then printf '%s' "$TMP/small.png"; return 0; fi
    case $(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z') in png) printf '%s' "$1"; return 0 ;; esac
    echo "a picture is read through rsvg-convert (the $(svg_pkg) package), which is not installed; a PNG is read without it"; return 1
}
look_name() {   # look_name WORDS -> a name for a kept look that is no palette's and no saved theme's
    _ln=$(desk_name_of "$1"); [ -n "$_ln" ] || _ln=look
    case $(theme_kind "$_ln") in ''|look) ;; *) _ln=$_ln-look ;; esac
    printf '%s' "$_ln"
}
# the picks (face, family, animation, drawing) each come from a list the tool's schema
# names; the step is checked against the same lists before anything is made
look_pick_ok() {   # look_pick_ok KIND VALUE -> 0 when VALUE is on KIND's list; empty is none picked
    case $1:$2 in
        *:) return 0 ;;
        face:*) case " $FONT_FACES " in *" $2 "*) return 0 ;; esac ;;
        family:*) case " $GLYPH_FAMILIES " in *" $2 "*) return 0 ;; esac ;;
        animation:*) case " $ANIMATION_NAMES " in *" $2 "*) return 0 ;; esac ;;
        drawing:*) for _e in $WALL_SHIPPED; do [ "${_e%%:*}" != "$2" ] || return 0; done ;;
    esac
    return 1
}
look_pick_list() {   # look_pick_list KIND -> the list as a schema's enum, a|b|c
    case $1 in face) _lpl=$FONT_FACES ;; family) _lpl=$GLYPH_FAMILIES ;; animation) _lpl=$ANIMATION_NAMES ;; drawing) _lpl=''; for _e in $WALL_SHIPPED; do _lpl="$_lpl ${_e%%:*}"; done ;; *) _lpl='' ;; esac
    _lpo=''; for _e in $_lpl; do _lpo="$_lpo|$_e"; done; printf '%s' "${_lpo#|}"
}
look_pick_why() { echo "$1 takes $(look_pick_list "$1" | sed 's/|/, /g; s/, \([a-z]*\)$/ or \1/')"; }   # look_pick_why KIND -> "face takes neon, argon,... or krypton"
look_picks() {   # look_picks 'WORDS [face=F] [family=G] [animation=N] [drawing=D]' -> _lpr the words before the picks, _lp_face _lp_family _lp_animation _lp_drawing; one line and 1 for a pick off its list
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
anim_for_colors() {   # anim_for_colors PALETTE_FILE -> the piece for a palette with no name, by its accent's hue and its ground
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
look_picked() {   # look_picked PALETTE_FILE FACE FAMILY ANIMATION -> a made look's lines past its palette and wallpaper: the picks, or the ones in use
    _lpf=${2:-$(face_word "${FONT%%:*}")} || _lpf=''
    [ -z "$_lpf" ] || printf 'FACE=%s\n' "$_lpf"
    _lps=$(look_font_size); case $_lps in [6-9]|[1-3][0-9]|40) printf 'TEXT_SIZE=%s\n' "$_lps" ;; esac
    printf 'ALPHA=%s\nPOINTER=%s\nANIMATION=%s\nGLYPH_FAMILY=%s\n' "$ALPHA" "${POINTER:-}" "${4:-$(anim_for_colors "$1")}" "${3:-$GLYPH_FAMILY}"
}
theme_picture() {   # theme_picture PATH [face=F] [family=G] [animation=N] -- a theme from a picture of yours, applied now
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
# a theme from words: the model gives a hue, a warmth, a contrast and light or dark; the
# palette is made from them
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
theme_words_step() {   # theme_words_step 'HUE accent=A warmth=W contrast=C light=L [face=F] [family=G] [animation=N] [drawing=D] [name=SLUG]' -> theme_words_apply's receipt
    case $1 in *[!a-z0-9=\ -]*|'') echo "$WORDS_TAKE"; return 1 ;; esac   # no character the loop below could take as a pattern
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
theme_words_apply() {   # theme_words_apply HUE ACCENT WARMTH CONTRAST LIGHT [NAME] [WORDS] [FACE] [FAMILY] [ANIMATION] [DRAWING] -> the receipt; why and 1 when no palette came
    command -v python3 >/dev/null 2>&1 || { echo "python3 is not installed, and it makes the palette"; return 1; }
    if [ -n "${6:-}" ]; then _words=$(printf '%s' "$6" | tr '-' ' ')
    elif [ -n "${7:-}" ]; then _words=$7
    else _words="$1$([ "$2" = same ] || printf ' and %s' "$2"), $5"; fi
    name=$(look_name "$_words")
    _d=$LOOKS_DIR/$name; rm -rf "$_d.new"; mkdir_state "$_d.new"
    python3 -I "$REPO/lib/look.py" words --hue "$1" --accent "$2" --warmth "$3" --contrast "$4" --light "$5" > "$_d.new/palette.env" 2>"$TMP/look.err" || { echo "no palette from those words: $(head -1 "$TMP/look.err")"; rm -rf "$_d.new"; return 1; }
    _lw=$WALLPAPER; [ -z "${11:-}" ] || [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || wall_yours || _lw=${11}   # the drawing on the desktop, unless a picture of yours is on
    { printf 'FORMAT=%s\nPALETTE=words\nWORDS=%s\n' "$LOOK_FORMAT" "$(printf '%s' "$_words" | tr -cd 'A-Za-z0-9 ,.-' | cut -c1-80)"
      printf 'WALLPAPER=%s\n' "$_lw"
      look_picked "$_d.new/palette.env" "${8:-}" "${9:-}" "${10:-}"; } > "$_d.new/look.env"
    rm -rf "$_d"; mv "$_d.new" "$_d"
    theme_apply "$name" >/dev/null
    echo "$(theme_words_of "$name") is on $PANEL_SEP spark-shell theme save NAME keeps it, theme back returns"
}

