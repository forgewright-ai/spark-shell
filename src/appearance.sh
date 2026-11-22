# shellcheck extended-analysis=false
# reads: CONFIG_DIR OS
appearance_gallery() {
    _ag_dark=" $(palette_darks | tr '\n' ' ') "
    {
        for gallery in "$CONFIG_DIR"/galleries/*.list; do
            [ -f "$gallery" ] || continue
            group=${gallery##*/}; group=${group%.list}
            case $group in ''|*[!a-z0-9-]*) continue ;; esac
            group=$(printf '%s' "$group" | tr '-' ' ')
            while IFS= read -r name || [ -n "$name" ]; do
                case $name in ''|.*|*[!A-Za-z0-9._-]*) continue ;; esac
                printf '%s\t%s\n' "$group" "$name"
            done < "$gallery"
        done
        theme_saved_names | while IFS= read -r name; do printf 'saved themes\t%s\n' "$name"; done
        palette_names | while IFS= read -r name; do
            case $_ag_dark in *" $name "*) tone=dark ;; *) tone=light ;; esac
            printf '%s\t%s\n' "$tone" "$name"
        done | LC_ALL=C sort
    } | jq -Rn --arg current "${THEME:-none}" --argjson chips "$(theme_chips theme)" '
        [inputs | split("\t") | select(.[1] | test("^[A-Za-z0-9_-][A-Za-z0-9._-]*$"))
         | {group: .[0], text: .[1]}]
        | reduce .[] as $r ({seen:{},rows:[]};
              if .seen[$r.text] or $chips[$r.text] == null then . else .seen[$r.text] = true | .rows += [$r] end)
        | .rows | map(.text as $n | . + {id: ("theme:entry:" + $n), children: ("spark-shell://theme/rows/gallery/" + $n),
              chip: $chips[$n], sign: (if $n == $current then "check" else "opens" end)})
        | {title: "theme gallery", state: ("\(length) themes"), rows: ., short: []}'
}
appearance_detail() {
    _ad_kind=$(theme_kind "$1")
    case $_ad_kind in shipped|yours|saved|look) ;; *) return 1 ;; esac
    _ad_dir=$(theme_dir "$1")
    _ad_wall=''; _ad_motion=''; _ad_face=''; _ad_family=''; _ad_alpha=''; _ad_size=''; _ad_picture=''
    if [ -n "$_ad_dir" ]; then
        look_ok "$_ad_dir" >/dev/null || return 1
        _ad_wall=$(look_get "$_ad_dir" WALLPAPER)
        _ad_picture=$(look_get "$_ad_dir" PICTURE)
        _ad_motion=$(look_get "$_ad_dir" WALLPAPER_MOTION)
        _ad_face=$(look_get "$_ad_dir" FACE); _ad_size=$(look_get "$_ad_dir" TEXT_SIZE)
        _ad_font=$(look_get "$_ad_dir" FONT)
        if [ -n "$_ad_font" ] && [ -z "$_ad_face$_ad_size" ]; then
            _ad_face=$(face_word "${_ad_font%%:*}" || :)
            _ad_size=$(FONT=$_ad_font look_font_size)
        fi
        _ad_family=$(look_get "$_ad_dir" GLYPH_FAMILY)
        _ad_alpha=$(look_get "$_ad_dir" ALPHA)
    elif ! wall_yours; then _ad_wall=$(wall_for_palette "$1" || :); fi
    case $_ad_wall in picture) _ad_wall=$_ad_picture ;; /*) _ad_wall=${_ad_wall##*/} ;; esac
    _ad_anim=$(theme_animation_for "$1" "$_ad_dir")
    [ "${DIALOG_ANIMATION:-}" != none ] || _ad_anim=none
    _ad_chip=$(palette_chip "$1") || return 1
    jq -cn --arg name "$1" --arg current "${THEME:-none}" --arg chip "$_ad_chip" \
        --arg wall "$_ad_wall" --arg motion "$_ad_motion" --arg anim "$_ad_anim" \
        --arg face "$_ad_face" --arg family "$_ad_family" --arg alpha "$_ad_alpha" --arg size "$_ad_size" \
        --argjson desktop "$([ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && echo true || echo false)" '
        def fact($g; $id; $label; $value):
            {id: ("theme:detail:" + $id), group: $g, text: $label, columns: [if $value == "" then "keep current" else $value end]};
        {title: $name, short: [], rows: ([
            {id: ("theme:apply:" + $name), text: (if $name == $current then "in use" else "apply theme" end),
             sign: (if $name == $current then "check" else "blank" end), chip: ($chip | split(" ")),
             quiet: true, tool: {name:"theme_palette",arguments:{name:$name}}}]
            + (if $desktop then [fact("wallpaper and motion"; "wall"; "wallpaper"; $wall),
                                 fact("wallpaper and motion"; "motion"; "wallpaper motion"; $motion)] else [] end)
            + [fact("wallpaper and motion"; "animation"; "dialog motion"; $anim),
               fact("type and glyphs"; "face"; "typeface"; $face), fact("type and glyphs"; "size"; "text size"; $size),
               fact("type and glyphs"; "family"; "glyph family"; $family),
               fact("windows"; "alpha"; "opacity"; (if $alpha == "" then "" else (($alpha | tonumber) * 100 | round | tostring) + "%" end))])}'
}
