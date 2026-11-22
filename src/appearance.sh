# shellcheck extended-analysis=false
# reads: CONFIG_DIR CORE_DIR OS PALETTE_DIR REPO SCENE_MAKE TAB THUMB_DIR TMP
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
                      children: ("spark-shell://theme/rows/gallery/" + $id), page: ("spark-shell://theme/preview/" + $id), chip: $chips[$id],
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
             quiet: true, page: ("spark-shell://theme/preview/" + $name), tool: {name:"theme_palette",arguments:{name:$name}}}]
            + (if $desktop then [fact("wallpaper and motion"; "wall"; "wallpaper"; $wall),
                                 fact("wallpaper and motion"; "motion"; "wallpaper motion"; $motion)] else [] end)
            + [fact("wallpaper and motion"; "animation"; "dialog motion"; $anim),
               fact("type and glyphs"; "face"; "typeface"; $face), fact("type and glyphs"; "size"; "text size"; $size),
               fact("type and glyphs"; "family"; "glyph family"; $family),
               fact("windows"; "alpha"; "opacity"; (if $alpha == "" then "" else (($alpha | tonumber) * 100 | round | tostring) + "%" end))])}'
}

# A theme's own wallpaper, resolved without changing the active look.
appearance_preview() (
    _key=$1; _width=960; [ "${2:-}" != full ] || _width=1600
    _pal=$(palette_file "$_key") || return 1
    _dir=$(theme_dir "$_key"); _wall=''
    if [ -n "$_dir" ]; then
        look_ok "$_dir" >/dev/null || return 1
        _wall=$(look_get "$_dir" WALLPAPER)
    elif ! wall_yours; then _wall=$(wall_for_palette "$_key" || :); fi
    if [ "${3:-}" = current ]; then
        _wall=${WALLPAPER:-default}
        if [ -n "$_dir" ] && [ "$_wall" = "$_dir/$(look_get "$_dir" PICTURE)" ]; then _wall=picture; fi
    fi
    _wall=${_wall:-${WALLPAPER:-default}}
    _label=$_wall; _picture=''; _source=''; _kind=flat
    case $_wall in
        picture) _source=$_dir/$(look_get "$_dir" PICTURE); _label=${_source##*/}; _kind=picture ;;
        /*) _source=$(wall_picture_ok "$_wall") || _source=''; _label=${_wall##*/}; _kind=picture ;;
        none|default|'#'*) ;;
        *) if wall_scene "$_wall"; then _kind=scene; _source=$SCENE_MAKE
           elif wall_shipped "$_wall"; then _kind=drawing; _source=$REPO/gallery/wallpaper/$_wall.svg
           else return 1; fi ;;
    esac
    _cache=$THUMB_DIR/themes
    _stamp=$({ printf '%s\n' "$_wall" "$_source"; cat "$_pal"; } | cksum | cut -d' ' -f1)
    _out=$_cache/$_key-$_stamp-$_width.png
    if [ -s "$_out" ] && { [ -z "$_source" ] || { [ -f "$_source" ] && [ -z "$(find "$_source" -newer "$_out" 2>/dev/null)" ]; }; }; then _picture=$_out
    else
        _made=$TMP/theme-preview.png
        rm -f "$_made"
        case $_kind in
            scene) scene_still "$_wall" "$_pal" "${_width}x$((_width * 9 / 16))" "$_made" || : ;;
            drawing) if wall_recolor "$_source" "$_pal" > "$TMP/theme-preview.svg"; then svg_png "$TMP/theme-preview.svg" "$_made" "$_width" || :; fi
                if [ ! -s "$_made" ] && cmp -s "$_pal" "$REPO/gallery/theme/$(wall_palette_of "$_wall").env"; then _picture=$REPO/gallery/wallpaper/$_wall.png; fi ;;
            picture) if [ -f "$_source" ]; then
                    pic_png "$_source" "$_made" "$_width" || { case $_source in *.png) pic_magic "$_source" && _picture=$_source ;; esac; }
                fi ;;
            flat) if [ "${_wall#\#}" != "$_wall" ]; then _color=$_wall
                else HEX_BG=$(palette_get "$_pal" THEME_BG); HEX_BG=${HEX_BG#\#}; _color=$(wall_ground); fi
                printf '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="9"><rect width="16" height="9" fill="%s"/></svg>\n' "$_color" > "$TMP/theme-preview.svg"
                svg_png "$TMP/theme-preview.svg" "$_made" "$_width" || : ;;
        esac
        if [ -s "$_made" ]; then
            mkdir_state "$_cache"
            _tmp=$(mktemp "$_cache/.preview.XXXXXX") && cp "$_made" "$_tmp" && mv -f "$_tmp" "$_out" && _picture=$_out
            [ -z "${_tmp:-}" ] || rm -f "$_tmp"
        fi
    fi
    jq -cn --arg title "$(theme_label "$_key")" --arg wall "$_label" --arg picture "$_picture" --argjson full "$([ "$_width" = 1600 ] && echo true || echo false)" \
        '{title:$title, facts:[$wall], full:$full} + (if $picture != "" then {picture:$picture} else {say:"Wallpaper preview unavailable"} end)'
)

appearance_sections() {
    jq -c --arg label "$(theme_label "${THEME:-none}")" '
        .rows as $rows | (.state // "none") as $active
        | def section($id;$text;$ids):
            [$ids[] as $id | $rows[] | select(.id==$id)] as $items
            | select($items|length>0)
            | {id:("theme:settings:"+$id), text:$text, sign:"opens", children:("spark-shell://theme/rows/settings/"+$id),
               members:[$items[].id], columns:[], choice:true};
        (if any($rows[]; .id=="theme:gallery:open" and (.chip|length)>0) then .state=$label else . end)
        | .rows |= map(if .id=="theme:gallery:open" and $active!="none" and (.chip|length)>0
                     then .page="spark-shell://theme/current-wallpaper" | .columns=[$label] else . end)
        | .rows += [section("wallpaper";"Wallpaper and motion";["theme:wallpaper","theme:show:Moving wallpaper","theme:show:Animation"]),
                    section("type";"Type and glyphs";["theme:show:Text face","theme:show:Text size","theme:show:Glyph family"]),
                    section("interface";"Interface";["theme:show:Transparency","theme:show:Words on the bar","theme:show:App icons","theme:show:App spacing"]),
                    section("manage";"Manage themes";["theme:save","theme:picture","theme:none"])]'
}
appearance_section() {
    jq -ec --arg key "theme:settings:$1" '
        .rows as $rows | ($rows[]|select(.id==$key)) as $s
        | {title:$s.text, rows:[$s.members[] as $id | $rows[] | select(.id==$id) | .group=null], short:[]}'
}
