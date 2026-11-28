# shellcheck extended-analysis=false
# sets: APPEARANCE_CURATION
# reads: CONFIG_DIR CORE_DIR FONT_FACES GLYPH_FAMILIES OS PALETTE_DIR PANEL_SEP REPO SCENE_MAKE SCREEN_CALLED_JQ TAB TERM_NAME THEME_COLOR_WORDS THEME_KEYS THUMB_DIR TMP WALL_TYPES
appearance_gallery_entries() {   # the colors and the index go by file: a thousand themes pass what one argument holds. A row says a theme by its title (Mars Conquest); _label keeps the name the curation lists it by
    theme_chips theme > "$TMP/theme.chips"
    if [ "${1:-}" = plain ]; then : > "$TMP/theme.titles"; else theme_titles > "$TMP/theme.titles"; fi   # plain: the rows by their names, for a count of them
    {
        for gallery in "$CONFIG_DIR"/galleries/*.list; do
            [ -f "$gallery" ] || continue
            group=${gallery##*/}; group=${group%.list}
            case $group in ''|core|first-gallery|*[!a-z0-9-]*) continue ;; esac
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
    } | jq -Rn --arg current "${THEME:-none}" --slurpfile c "$TMP/theme.chips" --rawfile t "$TMP/theme.titles" '
        $c[0] as $chips | [inputs | split("\t") | select(length == 4 and $chips[.[2]] != null)] as $entries
        | ($t | split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}) as $titles
        | (any($entries[]; .[0] == "local")) as $multiple
        | reduce $entries[] as [$kind,$group,$id,$label] ({seen:{}, labels:{}, rows:[]};
              if .seen[$id] or ($kind == "palette" and .labels[$label]) then . else
                  .seen[$id] = true | .labels[$label] = true |
                  .rows += [{id: ("theme:entry:" + $id), text: ($titles[$id] // $label), _label: $label, _kind: $kind, _room: $group,
                      group: (if $kind == "core" and ($multiple | not) then null elif $kind == "local" then ($group | gsub("-";" ")) else $group end),
                      children: ("spark-shell://theme/rows/gallery/" + $id), page: ("spark-shell://theme/preview/" + $id), chip: $chips[$id],
                      sign: (if $id == $current then "check" else "opens" end)}]
              end)
        | {title: "Theme gallery", state: ("\(.rows | length) themes"), rows: .rows, short: []}'
}

# The gallery: the exhibitions that are open first, then the sections of the
# permanent collection, and your own. Each shows a lead work's picture, a note and its count;
# looking changes nothing.
APPEARANCE_CURATION='
.rows as $all |
def onview($name): (($c[0].dispositions // {})[$name].status // "exhibited") == "exhibited";
def works($names): [$names[] as $name | $all[] | select(._label == $name)];
def lead($lead; $works): ([$works[] | select(._label == ($lead // ""))] + [$works[] | select(onview(._label))] + $works)[0];
def count($works): ($works | length | tostring) + (if ($works | length) == 1 then " work" else " works" end);
def words($k): ($idx[0][$k] // null) as $a
    | if $a == null then null
      else ({vector: "vector", illustration: "illustrated scene", cinematic: "cinematic illustration", pixel: "pixel scene", picture: "picture", color: "plain ground"}[$a.media] // "plain ground")
           + " " + $sep + " " + $a.variant + ([$a.variants | keys[] | select(. != $a.variant) | " " + $sep + " has a " + . + " variant"] | join(""))
      end;
def shown: del(._kind, ._room, ._label) | .group = null | words(.id | ltrimstr("theme:entry:")) as $w | if $w == null then del(.line) else .line = $w end;
def collection($title; $state; $works):
    ([$works[] | select(onview(._label))] | length) as $nv
    | ($nv > 0 and $nv < ($works | length)) as $split
    | {title: $title, state: $state, short: [],
       rows: [$works[] | (onview(._label)) as $on | shown | .group = (if $split then (if $on then "on view" else "supporting" end) else null end)]
             | sort_by(if .group == "supporting" then 1 else 0 end)};
'
appearance_gallery() {
    art_index > "$TMP/theme.index"
    appearance_gallery_entries | jq -c --slurpfile c "$CORE_DIR/curation.json" --slurpfile idx "$TMP/theme.index" --arg sep "$PANEL_SEP" "$APPEARANCE_CURATION"'
        [$c[0].sections[] as $s | works($s.works) as $w | lead($s.lead; $w) as $l
            | {id: ("theme:room:permanent:" + $s.id), text: $s.title, group: $c[0].title, columns: [count($w)], line: $s.description,
               children: ("spark-shell://theme/rows/gallery/collection/permanent/" + $s.id), page: $l.page, chip: $l.chip, choice: true, sign: "opens", _n: ($w | length)}] as $sections
        | [($c[0].exhibitions // [])[] | select(.status == "open") as $e | works($e.works) as $w | select(($w | length) > 0)
            | {id: ("theme:room:exhibition:" + $e.id), text: $e.title, group: "Exhibitions", columns: [count($w)], line: $e.note,
               children: ("spark-shell://theme/rows/gallery/collection/exhibition/" + $e.id), page: $w[0].page, chip: $w[0].chip, choice: true, sign: "opens"}] as $shows
        | [$all[] | select(._kind == "saved")] as $saved
        | (if ($saved | length) > 0 then
            [{id: "theme:room:saved", text: "Saved themes", group: "Your Collection", choice: true, columns: [count($saved)],
              children: "spark-shell://theme/rows/gallery/collection/saved", sign: "opens", page: $saved[0].page, chip: $saved[0].chip}]
           else [] end) as $personal
        | ([$all[] | select(._kind == "local") | ._room] | unique) as $locals
        | [$locals[] as $slug | [$all[] | select(._kind == "local" and ._room == $slug)] as $w
            | {id: ("theme:room:local:" + $slug), text: ($slug | gsub("-"; " ")), group: "Your Collection", choice: true, columns: [count($w)],
               children: ("spark-shell://theme/rows/gallery/collection/local/" + $slug), page: $w[0].page, chip: $w[0].chip, sign: "opens"}] as $custom
        | {title: "The Gallery",
           state: (([$sections[]._n] | add // 0 | tostring) + " works in " + ($sections | length | tostring) + " sections"
                   + (if ($shows | length) > 0 then ", " + ($shows | length | tostring) + (if ($shows | length) == 1 then " exhibition" else " exhibitions" end) else "" end)),
           rows: ($shows + [$sections[] | del(._n)] + $personal + $custom), short: []}'
}

# One section, exhibition or collection of yours. A work keeps its id, preview,
# palette and apply, and a theme of yours keeps its precedence by name.
appearance_gallery_collection() {
    art_index > "$TMP/theme.index"
    appearance_gallery_entries | jq -ec --arg room "$1" --slurpfile c "$CORE_DIR/curation.json" --slurpfile idx "$TMP/theme.index" --arg sep "$PANEL_SEP" "$APPEARANCE_CURATION"'
        if ($room | startswith("permanent/")) then
            ($c[0].sections[] | select(.id == ($room | ltrimstr("permanent/")))) as $s
            | collection($s.title; $s.description; works($s.works))
          elif ($room | startswith("exhibition/")) then
            ($c[0].exhibitions // [] | .[] | select(.status == "open" and .id == ($room | ltrimstr("exhibition/")))) as $e
            | works($e.works) as $w | if ($w | length) > 0 then collection($e.title; $e.note; $w) else empty end
          elif $room == "saved" then
            [$all[] | select(._kind == "saved")] as $w | collection("Saved themes"; count($w); $w)
          elif ($room | startswith("local/")) then
            ($room | ltrimstr("local/")) as $slug
            | [$all[] | select(._kind == "local" and ._room == $slug)] as $w
            | if ($w | length) > 0 then collection($slug | gsub("-"; " "); count($w); $w) else empty end
          else empty end'
}

# Your themes: the ways to make one, then every theme of yours, each with its page and its rename, duplicate and
# delete; the theme in use is checked.
# Colors: the 20 of the theme in use, each changed by its value, its swatch beside it; above them, another theme's
appearance_colors() {   # the 20 colors of the theme in use, each with the color it is read against (the ground; the text for the ground; none for the two blacks, which no text is written in); above them, another theme's colors and the theme's other variant
    _acp=$(palette_file "${THEME:-none}") || return 1
    _acv=none
    if command -v jq >/dev/null 2>&1; then
        _aco=$(art_of "$THEME" | jq -r '. as $a | [$a.variants | to_entries[] | select(.key != $a.variant) | .value] | first // ""' 2>/dev/null) || _aco=''
        [ -z "$_aco" ] || _acv=$(theme_title "$(appearance_theme_of "$_aco")")
    fi
    for _e in $THEME_COLOR_WORDS; do printf '%s\t%s\t%s\n' "${_e%%:*}" "${_e#*:}" "$(palette_get "$_acp" "THEME_${_e#*:}")"; done \
        | jq -Rn --arg label "$(theme_title "$THEME")" --arg pair "$_acv" '[inputs | split("\t")] as $c
            | ["black","red","green","yellow","blue","magenta","cyan","white"] as $names
            | ([$c[] | select(.[1] == "BG") | .[2]] | first // "") as $ground | ([$c[] | select(.[1] == "FG") | .[2]] | first // "") as $ink
            | {title: "Colors", state: $label, short: [],
               rows: ([{id: "theme:colors:from", text: "another theme'"'"'s colors", sign: "opens", children: "spark-shell://theme/rows/colors/from"},
                       {id: "theme:colors:pair", text: "other variant", sign: "opens", choice: true, columns: [$pair], children: "spark-shell://theme/rows/colors/pair"}]
                      + [$c[] | .[0] as $w | .[1] as $k | .[2] as $hex | ($k | ltrimstr("ANSI_") | tonumber? // null) as $i
                         | (if $k == "BG" then $ink elif $k == "ANSI_0" or $k == "ANSI_8" then "" else $ground end) as $on
                         | {id: ("theme:color:" + $k), group: (if $i == null then "theme colors" elif $i < 8 then "ANSI regular" else "ANSI bright" end),   # as the terminal palette has them
                            text: (if $i == null then ($w | (.[0:1] | ascii_upcase) + .[1:]) else "\($i)  \($names[$i % 8])" end),
                            swatch: $hex, columns: [$hex], tool: {name: "theme_color", arguments: {word: $w}, ask: ["color"]}}
                           + (if ($on | test("^#[0-9A-Fa-f]{6}$")) then {against: $on} else {} end)])}'
}
appearance_theme_of() {   # appearance_theme_of NAME -> the theme a family names: the name, or the curated work it is the label of (dracula is core-dracula)
    if [ -n "$(theme_kind "$1")" ]; then printf '%s' "$1"; elif [ -n "$(theme_kind "core-$1")" ]; then printf 'core-%s' "$1"; else printf '%s' "$1"; fi
}
appearance_colors_from() {   # every theme, its swatch: Enter takes its colors
    appearance_gallery_entries | jq -c '{title: "Another theme'"'"'s colors", state: "", short: [],
        rows: [.rows[] | (.id | ltrimstr("theme:entry:")) as $n | {id: ("theme:colors:" + $n), text, group, chip, page, quiet: true,
               tool: {name: "theme_colors", arguments: {name: $n}}}]}'
}
# Wallpaper and screens: the wallpaper and whether it moves; then each connected screen that shows something of its
# own (a turned screen, a second or a third one), by the name display gives it, with what it shows now and the way to
# give it a picture; a loop for each of the theme's own pictures; the clock over the art. The first landscape screen
# is the wallpaper's: it has no row while it shows it. A screen says what is on it, never "none".
appearance_screens() {   # -> the rows of the screens, the loops and the clock, one JSON array
    _asd=$(theme_dir "${THEME:-none}"); _asn=${_asd##*/}; _asa=$(art_of "${THEME:-none}")
    _asw=$(wall_now); _ask=picture   # what the wallpaper is called, and its kind: ground, color, drawing, scene or picture
    case ${WALLPAPER:-default} in
        default|none) _asw='the ground'; _ask=ground ;;
        '#'*) _ask=color ;;
        *) if wall_scene "$WALLPAPER"; then _ask=scene; elif wall_shipped "$WALLPAPER"; then _ask=drawing; fi ;;
    esac
    _ast=''; ! art_wall_theirs || _ast=1   # a picture or a color of yours stands on every screen as you set it
    _asp=''; [ "$_ask" != picture ] || case $(printf '%s' "${WALLPAPER##*.}" | tr 'A-Z' 'a-z') in jpg|jpeg|png) _asp=1 ;; esac   # a second screen's picture goes beside a JPEG or a PNG
    _asc=''; case ${WALLPAPER:-} in "$_asd"/?*) [ -z "$_asd" ] || _asc=${WALLPAPER#"$_asd"/} ;; esac   # the theme's own picture chosen as the wallpaper
    : > "$TMP/theme.outputs"; ! wm_session || wm_outputs > "$TMP/theme.outputs" 2>/dev/null || :
    jq -e 'type == "array"' "$TMP/theme.outputs" >/dev/null 2>&1 || echo '[]' > "$TMP/theme.outputs"
    {
        art_screens "$TMP/theme.outputs" | while IFS="$TAB" read -r _sn _si _sa _st _ss _sr _sf _sm; do
            _sl=''; case $_sf in ''|-) ;; *) _sl=$(art_named "$_asd/$_sf" "$_asn") ;; esac
            printf 'screen\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_sn" "$_sa" "$_st" "$_sr" "${_sf:--}" "$_sm" "${_sl:--}"
        done
        art_stills | while IFS= read -r _f; do [ -f "${_f%.*}.mp4" ] && _m=loop || _m=still; printf 'loop\t%s\t%s\t%s\n' "$(art_role "$_f")" "$(art_label "$_f")" "$_m"; done
        _p=$(printf '%s' "$_asa" | jq -r '.portrait_file // empty'); [ -z "$_p" ] || { [ -f "$_asd/${_p%.*}.mp4" ] && _m=loop || _m=still; printf 'loop\tportrait\tPortrait\t%s\n' "$_m"; }
    } | jq -Rnc --argjson art "$_asa" --slurpfile screens "$TMP/theme.outputs" --arg wall "$_asw" --arg kind "$_ask" --arg theirs "$_ast" --arg lead "$_asp" --arg chosen "$_asc" '
        def outs: ($screens[0] // []) | if type == "array" then . else [] end
            | map(select(type == "object" and (.name | type) == "string" and (.name | test("^[A-Za-z0-9_.:-]{1,80}$"))));
        '"$SCREEN_CALLED_JQ"'
        def named($n): ([outs[] | select(.name == $n)] | first) as $o | if $o == null then $n else ($o | called) end;
        [inputs | split("\t")] as $in
        | [$in[] | select(.[0] == "screen") | {name: .[1], at: (.[2] | tonumber? // 0), tall: (.[3] == "portrait"), role: .[4],
              file: (if .[5] == "-" then "" else .[5] end), mode: .[6], label: (if .[7] == "-" then "" else .[7] end)}] as $scr
        | ([$scr[] | select(.tall | not)] | first) as $first
        | [$scr[] | select(.tall | not) | .name] as $wides   # panel N goes to the Nth landscape screen: a turned one takes none
        | ($kind == "ground" or $kind == "color") as $plain   # a color or the ground: one thing on every screen, and none takes a picture beside it
        | ($plain or $theirs != "") as $same   # as it stands, one thing on every screen: a picture of yours too, until a screen is given its own
        | def shows: if $same then $wall
              elif .mode == "scene" or .mode == "drawn" then $wall + ", drawn for a turned screen"
              elif .mode == "scene2" or .mode == "drawing2" then $wall + ", its second view"
              elif .mode == "fit" then $wall + ", fitted"
              elif .role == "landscape" or .role == "chosen" or .file == "" or .file == $chosen then $wall
              else .label end;
          def its: ($same | not) and .mode == "fill" and .file != "" and .file != $chosen and (.role == "portrait" or (.role | startswith("panel")));   # a picture of the screen alone
          def away($tool; $args): if its then [{name: $tool, arguments: ($args + {path: "none"}), said: "take it away"}] else [] end;
          ([$scr[] | . as $s
              | select(($first != null and $s.name == $first.name and ($s | shows) == $wall) | not)
              | {id: ("theme:screen:" + $s.name), group: "screens", text: (named($s.name) + (if $s.tall then " (turned)" else "" end)), sign: "opens", columns: [$s | shows]}
                + (if $s.tall and ($plain | not) then
                       {children: "spark-shell://files/rows", pick: {tool: "theme_portrait", types: ["jpg", "jpeg", "png"], arguments: {}}, more: ($s | away("theme_portrait"; {}))}
                   elif ($s.tall | not) and ($plain | not) and $first != null and $s.name != $first.name and $lead != "" and (($wides | index($s.name)) as $w | $w == 1 or $w == 2) then
                       ((($wides | index($s.name)) + 1) | tostring) as $p
                       | {children: "spark-shell://files/rows", pick: {tool: "theme_panel", types: ["jpg", "jpeg", "png"], arguments: {n: $p}}, more: ($s | away("theme_panel"; {n: $p}))}
                   else {children: "spark-shell://theme/rows/wallpapers", more: []} end)]
           + [$in[] | select(.[0] == "loop") | {id: ("theme:screens:loop:" + .[1]), group: "loops", text: .[2], sign: "opens", columns: [.[3]],
                 children: "spark-shell://files/rows", pick: {tool: "theme_loop", types: ["mp4"], arguments: {role: .[1]}},
                 more: (if .[3] == "loop" then [{name: "theme_loop", arguments: {role: .[1], path: "none"}, said: "take it away"}] else [] end)}]
           + [{id: "theme:screens:clock", group: "idle and lock", text: "clock over the art", columns: [],
               switch: {on: $art.clock, turn_on: {name: "theme_clock", arguments: {to: "on"}}, turn_off: {name: "theme_clock", arguments: {to: "off"}}}}])'
}
appearance_wallpaper() {   # stdin: the theme section's rows -> the Wallpaper and screens page: the section's own two rows, then the screens, the loops and the clock; false where the section has no wallpaper (a Mac)
    cat > "$TMP/theme.root"
    appearance_screens > "$TMP/theme.screens" 2>/dev/null || echo '[]' > "$TMP/theme.screens"
    [ -s "$TMP/theme.screens" ] || echo '[]' > "$TMP/theme.screens"
    jq -ec --slurpfile more "$TMP/theme.screens" --arg label "$(theme_title "${THEME:-none}")" '
        [.rows[] | select(.id == "theme:wallpaper" or .id == "theme:show:Moving wallpaper") | .group = "wallpaper"] as $w
        | select(($w | length) > 0)
        | {title: "Wallpaper and screens", state: $label, short: [], rows: ($w + ($more[0] // []))}' "$TMP/theme.root"
}
appearance_pairs() {   # the themes in the other light, and none: Enter pairs it
    _apv=$(art_of "${THEME:-none}" | jq -r .variant)
    art_index > "$TMP/theme.index"
    appearance_gallery_entries | jq -c --slurpfile idx "$TMP/theme.index" --arg v "$_apv" '{title: "Other variant", state: "", short: [],
        rows: ([{id: "theme:pair:none", text: "none", tool: {name: "theme_pair", arguments: {name: "none"}}}]
               + [.rows[] | (.id | ltrimstr("theme:entry:")) as $n | select(($idx[0][$n].variant // "") != $v and ($idx[0][$n].variant // "") != "")
                  | {id: ("theme:pair:" + $n), text, chip, page, quiet: true, tool: {name: "theme_pair", arguments: {name: $n}}}])}'
}
appearance_pointers() {   # default, then each cursor theme here at the size in use
    _aps=${POINTER##* }; case $_aps in ''|*[!0-9]*) _aps=24 ;; esac
    for _apd in "$HOME/.local/share/icons" "$HOME/.icons" /usr/local/share/icons /usr/share/icons; do
        for _apc in "$_apd"/*/cursors; do [ -d "$_apc" ] || continue; _apc=${_apc%/cursors}; printf '%s\n' "${_apc##*/}"; done
    done | LC_ALL=C sort -u | grep -E '^[A-Za-z0-9._-]+$' | jq -Rn --arg cur "${POINTER:-default}" --arg size "$_aps" '{title: "Pointer", state: $cur, short: [],
        rows: ([{id: "theme:pointer:default", text: "default", columns: ["spark'"'"'s own"], sign: (if $cur == "default" then "check" else "blank" end),
                 tool: {name: "theme_pointer", arguments: {name: "default"}}}]
               + [inputs | {id: ("theme:pointer:" + .), text: ., columns: [$size + " px"], sign: (if ($cur | split(" ")[0]) == . then "check" else "blank" end),
                            tool: {name: "theme_pointer", arguments: {name: (. + " " + $size)}}}])}'
}
appearance_yours() {   # the look in use where it is not saved (save it, or put the theme it came from back), the ways to make a theme, then each theme of yours with its rename, duplicate and delete
    _ayk=$(theme_kind "${THEME:-none}"); _ayo=''; _ayt=''
    if [ "$_ayk" = look ] && _ayo=$(theme_origin "$THEME"); then _ayt=$(theme_title "$_ayo"); else _ayo=''; fi
    appearance_gallery_entries | jq -c --arg cur "${THEME:-none}" --arg label "$(theme_title "${THEME:-none}")" --arg types "$WALL_TYPES" --arg kind "$_ayk" --arg origin "$_ayo" --arg otitle "$_ayt" '
        [.rows[] | select(._kind == "saved")] as $mine
        | {title: "Your themes", short: [],
           state: (($mine | length | tostring) + (if ($mine | length) == 1 then " theme" else " themes" end)),
           rows: ((if $kind == "look" then
                     [{id: "theme:look:save", group: "this look", text: "save it as a theme", tool: {name: "theme_save", arguments: {}, ask: ["name"]}}]
                     + (if $origin != "" then [{id: "theme:look:back", group: "this look", text: ("put " + $otitle + " back"), tool: {name: "theme_palette", arguments: {name: $origin}}}] else [] end)
                   else [{id: "theme:new:look", group: "new theme", text: "from the look in use", tool: {name: "theme_save", arguments: {}, ask: ["name"]}}] end)
                  + [{id: "theme:new:picture", group: "new theme", text: "from a picture", sign: "opens", children: "spark-shell://files/rows",
                      pick: {tool: "theme_picture", types: ($types | split(" "))}},
                     {id: "theme:new:file", group: "new theme", text: "from a theme file", sign: "opens", children: "spark-shell://files/rows",
                      pick: {tool: "theme_install", types: ["spark-theme"]}}]
                  + (if $cur == "none" then [] else [{id: "theme:new:copy", group: "new theme", text: ("a copy of " + $label),
                      tool: {name: "theme_duplicate", arguments: {name: $cur}, ask: ["to"]}}] end)
                  + [$mine[] | del(._kind, ._room, ._label) | .group = "yours"
                     | .more = [{name: "theme_rename", arguments: {name: .text}, ask: ["to"], said: "rename"},
                                {name: "theme_duplicate", arguments: {name: .text}, ask: ["to"], said: "duplicate"},
                                {name: "theme_delete", arguments: {name: .text}, said: "delete"}]])}'
}
# A theme's page says what is shown and nothing else: the dialog draws every row it is given. Apply, its terminal
# palette, its compositions and its other variant; what it brings, one line each and only where the theme sets it (a
# theme that leaves the text as it is says nothing of the text); then what can be done with it.
appearance_detail() {
    _ad_kind=$(theme_kind "$1")
    case $_ad_kind in shipped|bundled|yours|saved|look) ;; *) return 1 ;; esac
    _ad_dir=$(theme_dir "$1")
    _ad_wall=''; _ad_face=''; _ad_family=''; _ad_alpha=''; _ad_size=''
    if [ -n "$_ad_dir" ]; then
        look_ok "$_ad_dir" >/dev/null || return 1
        _ad_wall=$(look_get "$_ad_dir" WALLPAPER)
        case $_ad_wall in
            picture) _ad_wall=$(art_named "$_ad_dir/$(look_get "$_ad_dir" PICTURE)" "${_ad_dir##*/}") ;;   # by its role: Landscape 1
            /*) _ad_wall=${_ad_wall##*/} ;;
            default|none) _ad_wall='the ground' ;;
        esac
        _ad_face=$(look_get "$_ad_dir" FACE); _ad_size=$(look_get "$_ad_dir" TEXT_SIZE)
        _ad_font=$(look_get "$_ad_dir" FONT)
        if [ -n "$_ad_font" ] && [ -z "$_ad_face$_ad_size" ]; then
            _ad_face=$(face_word "${_ad_font%%:*}" || :)
            _ad_size=$(FONT=$_ad_font look_font_size)
        fi
        _ad_family=$(look_get "$_ad_dir" GLYPH_FAMILY)
        _ad_alpha=$(look_get "$_ad_dir" ALPHA)
    elif ! wall_yours; then _ad_wall=$(wall_for_palette "$1" || :); fi
    _ad_anim=$(theme_animation_for "$1" "$_ad_dir")   # the theme's own piece, whatever plays now
    _ad_chip=$(palette_chip "$1") || return 1
    theme_titles > "$TMP/theme.titles"
    jq -cn --arg name "$1" --arg title "$(theme_title "$1")" --arg ref "$(palette_reference "$1")" --arg current "${THEME:-none}" --arg chip "$_ad_chip" \
        --arg wall "$_ad_wall" --arg anim "$_ad_anim" --arg face "$_ad_face" --arg family "$_ad_family" --arg alpha "$_ad_alpha" --arg size "$_ad_size" \
        --arg sep "$PANEL_SEP" --rawfile t "$TMP/theme.titles" --argjson art "$(art_of "$1")" \
        --argjson mine "$([ "$_ad_kind" = saved ] && echo true || echo false)" --argjson folder "$([ -n "$_ad_dir" ] && echo true || echo false)" \
        --argjson desktop "$([ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && echo true || echo false)" '
        ($t | split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}) as $titles
        | def titled($n): $titles[$n] // $titles["core-" + $n] // ($n | ltrimstr("core-"));
          def fact($id; $label; $value): {id: ("theme:detail:" + $id), group: "it brings", text: $label, columns: [$value]};
        ({vector: "vector", illustration: "illustrated scene", cinematic: "cinematic illustration", pixel: "pixel scene", picture: "picture", color: "plain ground"}[$art.media] // "plain ground") as $medium
        | ([$face, $size] | map(select(. != "")) | join(" ")) as $type
        | {title: $title, short: [], rows: ([
            {id: ("theme:apply:" + $name), text: (if $name == $current then "in use" else "apply theme" end),
             sign: (if $name == $current then "check" else "blank" end), chip: ($chip | split(" ")), line: ($medium + " " + $sep + " " + $art.variant),
             quiet: true, page: ("spark-shell://theme/preview/" + $name), tool: {name:"theme_palette",arguments:{name:$name}}},
            {id:"theme:terminal-palette", text:"Terminal palette", sign:"opens", columns:[$ref], children:("spark-shell://theme/rows/palette/"+$name)}]
            + (if $desktop then [{id: "theme:compositions", text: "compositions", sign: "opens",
                  columns: [if ($art.screens | length) > 1 then "panels for " + ($art.screens[1:] | map(tostring) | join(" and ")) + " screens too" else "landscape and portrait" end],
                  children: ("spark-shell://theme/rows/gallery/" + $name + "/art")}] else [] end)
            + [$art.variants | to_entries[] | select(.key != $art.variant)
               | {id: ("theme:variant:" + .key), text: (.key + " variant"), sign: "opens", columns: [titled(.value)], children: ("spark-shell://theme/rows/gallery/" + .value)}]
            + [(if $desktop and $wall != "" then fact("wallpaper"; "wallpaper"; $wall + (if $art.motion == "ambient" then ", moving" else "" end)) else empty end),
               (if $type != "" then fact("type"; "type"; $type) else empty end),
               (if $family != "" then fact("glyphs"; "glyphs"; $family) else empty end),
               (if $anim != "" then fact("motion"; "dialog motion"; (if $anim == "own" then "its own" else $anim end)) else empty end),
               (if $alpha != "" then fact("windows"; "windows"; (($alpha | tonumber? // 1) * 100 | round) as $p | if $p >= 100 then "solid" else "\($p)% solid" end) else empty end)]
            + (if $mine then
                 [{id: "theme:manage:rename", group: "manage", text: "Rename", tool: {name: "theme_rename", arguments: {name: $name}, ask: ["to"]}},
                  {id: "theme:manage:duplicate", group: "manage", text: "Duplicate", tool: {name: "theme_duplicate", arguments: {name: $name}, ask: ["to"]}},
                  {id: "theme:manage:delete", group: "manage", text: "Delete", tool: {name: "theme_delete", arguments: {name: $name}}}]
               else [{id: "theme:manage:duplicate", group: "manage", text: "Duplicate as yours", tool: {name: "theme_duplicate", arguments: {name: $name}, ask: ["to"]}}] end)
            + (if $folder then [{id: "theme:manage:export", group: "manage", text: "Export", columns: ["a theme file in Downloads"], tool: {name: "theme_export", arguments: {name: $name}}}] else [] end))}'
}
appearance_art() {   # appearance_art THEME -> its compositions: one screen, a turned screen and the panels its family has; each a preview, none applied
    case $(theme_kind "$1") in shipped|bundled|yours|saved|look) ;; *) return 1 ;; esac
    _aac=$(palette_chip "$1") || return 1
    art_of "$1" | jq -c --arg name "$1" --arg label "$(theme_title "$1")" --arg chip "$_aac" '
        ("spark-shell://theme/preview/" + $name) as $p | ($chip | split(" ")) as $c
        | {title: "Compositions", state: $label, short: [], rows: ([
            {id: "theme:art:landscape", text: "one screen", columns: ["landscape"], page: $p, chip: $c},
            {id: "theme:art:portrait", text: "turned screen", columns: [if .portrait == "authored" or .portrait == "drawn" then "its own composition" else "the art fitted" end], page: ($p + "/portrait"), chip: $c}]
          + [.second as $sv | .screens[1:][] | tostring as $n | {id: ("theme:art:panels-" + $n), text: ({"2": "two screens", "3": "three screens"}[$n]),
              columns: [if $sv then "its second landscape" else "panels" end], page: ($p + "/panels-" + $n), chip: $c}])}'
}

appearance_palette() (
    _colors=$(palette_export "$1" env) || return 1
    printf '%s\n' "$_colors" | jq -Rn --arg name "$1" --arg label "$(theme_title "$1")" --arg ref "$(palette_reference "$1")" '
        ["black","red","green","yellow","blue","magenta","cyan","white"] as $names
        | {BG:"Background",FG:"Foreground",ACCENT:"Accent",MUTED:"Muted"} as $roles
        | [inputs | select(startswith("THEME_")) | split("=") | (.[0] | ltrimstr("THEME_")) as $k | .[1] as $hex
            | (if $roles[$k] then null else ($k|ltrimstr("ANSI_")|tonumber) end) as $i
            | {id:("theme:color:"+$k), text:($roles[$k] // ("\($i)  "+$names[$i%8])),
               group:(if $i==null then "theme colors" elif $i<8 then "ANSI regular" else "ANSI bright" end),
               swatch:$hex, columns:[$hex], tool:{name:"theme_copy_color",arguments:{name:$name,key:$k}}}] as $colors
        | {title:"Terminal palette",state:$label,reference:$ref,rows:([{id:"theme:palette:reference",text:"Palette reference",columns:[$ref]},
           {id:"theme:palette:export",text:"Export palette",sign:"opens",
           children:("spark-shell://theme/rows/exports/"+$name)}]+$colors)}'
)

appearance_exports() {
    palette_file "$1" >/dev/null || return 1
    jq -cn --arg name "$1" --arg label "$(theme_title "$1")" --arg native "$TERM_NAME" '
        {title:"Export palette",state:$label,rows:([["env","spark-shell",".env"],[$native,$native,".ini"],["kitty","kitty",".conf"],
          ["ghostty","Ghostty","theme file"],["alacritty","Alacritty",".toml"]] | map({
          id:("theme:export:"+.[0]),text:.[1],columns:[.[2]],tool:{name:"theme_export_palette",arguments:{name:$name,format:.[0]}}}))}'
}

appearance_copy_color() (
    case $2 in ''|*[!A-Z0-9_]*) return 1 ;; esac
    case " $THEME_KEYS " in *" THEME_$2 "*) ;; *) return 1 ;; esac
    _pal=$(palette_file "$1") || return 1
    _color=$(palette_get "$_pal" "THEME_$2")
    hex_rgb "$_color" >/dev/null || return 1
    if [ "$OS" = Darwin ]; then printf '%s' "$_color" | pbcopy
    else printf '%s' "$_color" | wm_copy; fi 2>/dev/null || { echo "clipboard unavailable: $_color"; return 1; }
    printf 'copied %s\n' "$_color"
)

appearance_save_palette() (
    case $2 in env) _ext=env ;; "$TERM_NAME") _ext=$TERM_NAME.ini ;; kitty) _ext=kitty.conf ;; ghostty) _ext=ghostty ;; alacritty) _ext=toml ;; *) return 1 ;; esac
    _text=$(palette_export "$1" "$2") || return 1
    printf '%s\n' "$_text" > "$TMP/palette.keep" || return 1
    downloads_keep "$TMP/palette.keep" "$(theme_label "$1")" "$_ext"
)
downloads_keep() (   # downloads_keep FILE BASE EXT -- FILE as BASE.EXT in the downloads folder, never over another file (BASE-2.EXT, ...); "saved PATH"
    _dir=$(xdg-user-dir DOWNLOAD 2>/dev/null) || _dir=''
    case $_dir in /*) ;; *) _dir=$HOME/$(user_dir_of downloads) ;; esac
    mkdir -p "$_dir" || return 1
    _file=$(mktemp "$_dir/.spark-keep.XXXXXX") || return 1
    trap 'rm -f "$_file"' EXIT
    cat "$1" > "$_file" || return 1
    _base=$_dir/$2; _out=$_base.$3; _n=1
    while :; do
        if [ ! -e "$_out" ] && [ ! -L "$_out" ]; then
            ln "$_file" "$_out" 2>/dev/null && break
            { [ -e "$_out" ] || [ -L "$_out" ]; } || { echo "cannot save in $_dir"; return 1; }
        fi
        if [ -f "$_out" ] && [ ! -L "$_out" ] && cmp -s "$_file" "$_out"; then break; fi
        _n=$((_n + 1)); _out=$_base-$_n.$3
    done
    printf 'saved %s\n' "$_out"
)

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
        picture) _source=$_dir/$(look_get "$_dir" PICTURE); _label=$(art_named "$_source" "${_dir##*/}"); _kind=picture ;;   # by its role: Landscape 1
        /*) _source=$(wall_picture_ok "$_wall") || _source=''; _label=${_wall##*/}; _kind=picture
            if wall_of_theme "$_wall"; then _source=$_wall; _lpd=${_wall%/*}; _label=$(art_named "$_wall" "${_lpd##*/}"); fi ;;   # a theme's own, not under your home
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
    jq -cn --arg title "$(theme_title "$_key")" --arg wall "$_label" --arg ref "$(palette_reference "$_key")" --arg picture "$_picture" --argjson full "$([ "$_width" = 1600 ] && echo true || echo false)" \
        '{title:$title, facts:[$wall,$ref], full:$full} + (if $picture != "" then {picture:$picture} else {say:"Wallpaper preview unavailable"} end)'
)

# A composition's picture, made without changing the active look: a portrait
# companion, a scene's own portrait view or the art fitted, and panels in a row.
appearance_preview_art() (
    _key=$1; _role=$2; _h=540; [ "${3:-}" != full ] || _h=1080
    _pal=$(palette_file "$_key") || return 1
    _art=$(art_of "$_key") || return 1
    _dir=$(theme_dir "$_key"); _wall=$(printf '%s' "$_art" | jq -r .wallpaper)
    HEX_BG=$(palette_get "$_pal" THEME_BG); HEX_BG=${HEX_BG#\#}; _ground=$(wall_ground)
    case $_role in
        portrait) _file=$(printf '%s' "$_art" | jq -r '.portrait_file // empty')
            if [ -n "$_file" ]; then _say='its own portrait'; _how=file
            elif wall_scene "$_wall"; then _say='the scene drawn for a turned screen'; _how=scene
            elif [ "$(printf '%s' "$_art" | jq -r .portrait)" = drawn ]; then _say='the drawing drawn for a turned screen'; _how=drawn
            else _say='the art fitted, never cropped'; _how=fit; fi ;;
        panels-2|panels-3) _files=$(printf '%s' "$_art" | jq -r --arg n "${_role#panels-}" '.panels[$n] // [] | .[] | (.landscape // .portrait)')
            if [ -n "$_files" ]; then _say="${_role#panels-} panels, left to right"; _how=strip
            elif [ "$_role" = panels-2 ] && [ "$(printf '%s' "$_art" | jq -r '.second // empty')" != "" ]; then _say='its first and second landscape, left to right'; _how=second
            else return 1; fi ;;
        *) return 1 ;;
    esac
    _stamp=$({ printf '%s\n' "$_role" "$_art"; cat "$_pal"; } | cksum | cut -d' ' -f1)
    _out=$THUMB_DIR/themes/$_key-$_role-$_stamp-$_h.png; _picture=''
    if [ -s "$_out" ]; then _picture=$_out
    else
        _made=$TMP/theme-art.png; rm -f "$_made"
        case $_how in
            file) pic_png "$_dir/$_file" "$_made" "$_h" || : ;;
            scene) scene_still "$_wall" "$_pal" "$((_h * 9 / 32 * 2))x$_h" "$_made" || : ;;
            drawn) WALLPAPER=$_wall; art_view_draw drawn "$((_h * 9 / 32 * 2))x$_h" "$_pal" "$_made" || : ;;
            second) _land=$(appearance_preview "$_key" | jq -r '.picture // empty'); _two=$TMP/theme-art-2.png; rm -f "$_two"
                if wall_scene "$_wall"; then scene_still "$_wall" "$_pal" "$((_h * 16 / 9))x$_h" "$_two" 2 || :
                else WALLPAPER=$_wall; art_view_draw drawing2 "$((_h * 16 / 9))x$_h" "$_pal" "$_two" || :; fi
                [ -z "$_land" ] || [ ! -s "$_two" ] || art_strip "$_made" "$((_h / 2))" "$_ground" "$_land" "$_two" || : ;;
            fit) _land=$(appearance_preview "$_key" | jq -r '.picture // empty')
                [ -z "$_land" ] || art_fit "$_land" "$((_h * 9 / 32 * 2))x$_h" "$(art_edges "$_land" "$_ground" "$TMP/edges.png")" "$_made" || : ;;
            strip) set --; for _f in $_files; do set -- "$@" "$_dir/$_f"; done; art_strip "$_made" "$((_h / 2))" "$_ground" "$@" || : ;;
        esac
        # the poster is wide: a turned screen in it is drawn as a screen, its edge in the muted color, on the ground
        if [ "$_role" = portrait ] && [ "${3:-}" != full ] && [ -s "$_made" ]; then
            art_frame "$_made" 960x540 "$_ground" "$(palette_get "$_pal" THEME_MUTED)" "$TMP/theme-art-framed.png" && mv "$TMP/theme-art-framed.png" "$_made" || :
        fi
        if [ -s "$_made" ]; then
            mkdir_state "$THUMB_DIR/themes"
            _tmp=$(mktemp "$THUMB_DIR/themes/.preview.XXXXXX") && cp "$_made" "$_tmp" && mv -f "$_tmp" "$_out" && _picture=$_out
            [ -z "${_tmp:-}" ] || rm -f "$_tmp"
        fi
    fi
    jq -cn --arg title "$(theme_title "$_key")" --arg say "$_say" --arg ref "$(palette_reference "$_key")" --arg picture "$_picture" \
        --argjson full "$([ "${3:-}" = full ] && echo true || echo false)" \
        '{title: $title, facts: [$say, $ref], full: $full} + (if $picture != "" then {picture: $picture} else {say: "Composition preview unavailable"} end)'
)

appearance_sections() {   # stdin: the theme section's rows -> the same with the root's six places: the gallery, the wallpaper and the screens, the type, the interface, the colors, your themes
    # the themes its page lists, counted from the same rows: one of yours under a bundled work's name is that work
    # in the gallery and no row of the page (a count of the folders said 3 themes over a page of two)
    _asn=$(appearance_gallery_entries plain < /dev/null | jq '[.rows[] | select(._kind == "saved")] | length' || :)
    _asy="$_asn $([ "$_asn" = 1 ] && echo theme || echo themes)"
    # a look in use by its own colors: the chips are read for the palettes, the bundled works and the saved themes,
    # so a look kept to change stood with no poster and under the name of its folder
    _asc=''; _ask=$(theme_kind "${THEME:-none}")
    if [ "$_ask" = look ]; then _asc=$(palette_chip "$THEME" 2>/dev/null) || _asc=''; _asy='not saved'; fi
    jq -c --arg label "$(theme_title "${THEME:-none}")" --arg yours "$_asy" --arg chip "$_asc" '
        .rows as $rows | (.state // "none") as $active
        | ($chip | split(" ") | map(select(test("^#[0-9A-Fa-f]{6}$")))) as $own
        | def section($id;$text;$ids):
            [$ids[] as $id | $rows[] | select(.id==$id)] as $items
            | select($items|length>0)
            | {id:("theme:settings:"+$id), text:$text, sign:"opens", children:("spark-shell://theme/rows/settings/"+$id),
               members:[$items[].id], columns:[], choice:true};
        .rows |= map(if .id=="theme:gallery:open" and ($own | length) > 0 then .chip = $own else . end)
        | (if any(.rows[]; .id=="theme:gallery:open" and (.chip|length)>0) then .state=$label else . end)
        | .rows |= map(if .id=="theme:gallery:open" and $active!="none" and (.chip|length)>0
                     then .page="spark-shell://theme/current-wallpaper" | .columns=[$label] else . end)
        | .rows += [section("wallpaper";"Wallpaper and screens";["theme:wallpaper","theme:show:Moving wallpaper"]),   # the screens of a desktop: none on a Mac
                    section("type";"Type and glyphs";["theme:show:Text face","theme:show:Text size","theme:show:Glyph family"]),
                    section("interface";"Interface";["theme:show:Transparency","theme:show:Pointer","theme:show:Words on the bar","theme:show:App icons","theme:show:App spacing","theme:show:Animation"]),
                    {id:"theme:settings:colors", text:"Colors", sign:"opens", choice:true, columns:[], children:"spark-shell://theme/rows/colors"},
                    {id:"theme:settings:yours", text:"Your themes", sign:"opens", choice:true, columns:[$yours],
                     children:"spark-shell://theme/rows/yours"}]'
}
# The type page shows each choice as what it is: a typeface installed here by its family's name, so a specimen never lies,
# and a glyph family by its own signs, its gauge pair twice and its thinking sign.
appearance_type() {   # -> {WORD: {face}} for each typeface here and {WORD: {sample}} for each glyph family
    {
        for _atf in $FONT_FACES; do ! appearance_face_here "$_atf" || printf '%s\tface\t%s\n' "$_atf" "$(face_name "$_atf")"; done
        for _atf in $GLYPH_FAMILIES; do ( family_set "$_atf"; printf '%s\tsample\t%s\n' "$_atf" "$FAM_ON$FAM_OFF$FAM_ON$FAM_OFF $FAM_THINK" ); done
    } | jq -Rnc '[inputs | split("\t") | {(.[0]): {(.[1]): .[2]}}] | add // {}'
}
appearance_face_here() {   # appearance_face_here neon -> 0 when it is installed, by spark-shell or otherwise
    case $1 in neon) neon_here; return ;; esac
    face_ours "$1" || { command -v fc-list >/dev/null 2>&1 && [ -n "$(fc-list "$(face_name "$1")" family 2>/dev/null)" ]; }
}
appearance_section() {
    jq -ec --arg key "theme:settings:$1" '
        .rows as $rows | ($rows[]|select(.id==$key)) as $s
        | {title:$s.text, rows:[$s.members[] as $id | $rows[] | select(.id==$id) | .group=null], short:[]}'
}
