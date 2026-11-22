# shellcheck extended-analysis=false
# reads: CONFIG_DIR CORE_DIR OS PALETTE_DIR TAB
appearance_gallery() {
    {
        for gallery in "$CONFIG_DIR"/galleries/*.list; do
            [ -f "$gallery" ] || continue
            group=${gallery##*/}; group=${group%.list}
            case $group in ''|core|first-gallery|*[!a-z0-9-]*) continue ;; esac
            group=$(printf '%s' "$group" | tr '-' ' ')
            while IFS= read -r name || [ -n "$name" ]; do
                case $name in ''|.*|*[!A-Za-z0-9._-]*) continue ;; esac
                printf 'local\t%s\t%s\t%s\n' "$group" "$name" "$name"
            done < "$gallery"
        done
        while IFS="$TAB" read -r label id; do
            id=${id:-$label}
            # The private preview installed these variants under first-* keys.
            if [ "$id" != "$label" ]; then
                if [ -f "$PALETTE_DIR/$label/palette.env" ] || [ -f "$PALETTE_DIR/$label.env" ]; then id=$label
                elif [ -f "$PALETTE_DIR/first-$label/palette.env" ] &&
                    grep -qxF "first-$label" "$CONFIG_DIR/galleries/first-gallery.list" 2>/dev/null; then id=first-$label; fi
            fi
            printf 'core\tcore\t%s\t%s\n' "$id" "$label"
        done < "$CORE_DIR/themes.tsv"
        theme_saved_names | while IFS= read -r name; do printf 'saved\tsaved themes\t%s\t%s\n' "$name" "$name"; done
        palette_names | while IFS= read -r name; do printf 'palette\tpalettes\t%s\t%s\n' "$name" "$name"; done
    } | jq -Rn --arg current "${THEME:-none}" --argjson chips "$(theme_chips theme)" '
        [inputs | split("\t") | select(length == 4 and $chips[.[2]] != null)] as $entries
        | (any($entries[]; .[0] == "local")) as $multiple
        | reduce $entries[] as [$kind,$group,$id,$label] ({seen:{}, labels:{}, rows:[]};
              if .seen[$id] or ($kind == "palette" and .labels[$label]) then . else
                  .seen[$id] = true | .labels[$label] = true |
                  .rows += [{id: ("theme:entry:" + $id), text: $label,
                      group: (if $kind == "core" and ($multiple | not) then null else $group end),
                      children: ("spark-shell://theme/rows/gallery/" + $id), chip: $chips[$id],
                      sign: (if $id == $current then "check" else "opens" end)}]
              end)
        | {title: "Theme gallery", state: ("\(.rows | length) themes"), rows: .rows, short: []}'
}
appearance_detail() {
    _ad_kind=$(theme_kind "$1")
    case $_ad_kind in shipped|bundled|yours|saved|look) ;; *) return 1 ;; esac
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
    jq -cn --arg name "$1" --arg label "$(theme_label "$1")" --arg current "${THEME:-none}" --arg chip "$_ad_chip" \
        --arg wall "$_ad_wall" --arg motion "$_ad_motion" --arg anim "$_ad_anim" \
        --arg face "$_ad_face" --arg family "$_ad_family" --arg alpha "$_ad_alpha" --arg size "$_ad_size" \
        --argjson desktop "$([ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && echo true || echo false)" '
        def fact($g; $id; $label; $value):
            {id: ("theme:detail:" + $id), group: $g, text: $label, columns: [if $value == "" then "keep current" else $value end]};
        {title: $label, short: [], rows: ([
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
