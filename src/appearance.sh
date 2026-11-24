# shellcheck extended-analysis=false
# sets: APPEARANCE_CURATION
# reads: CONFIG_DIR CORE_DIR OS PALETTE_DIR PANEL_SEP REPO SCENE_MAKE TAB TERM_NAME THEME_COLOR_WORDS THEME_KEYS THUMB_DIR TMP WALL_TYPES
appearance_gallery_entries() {
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
    } | jq -Rn --arg current "${THEME:-none}" --argjson chips "$(theme_chips theme)" '
        [inputs | split("\t") | select(length == 4 and $chips[.[2]] != null)] as $entries
        | (any($entries[]; .[0] == "local")) as $multiple
        | reduce $entries[] as [$kind,$group,$id,$label] ({seen:{}, labels:{}, rows:[]};
              if .seen[$id] or ($kind == "palette" and .labels[$label]) then . else
                  .seen[$id] = true | .labels[$label] = true |
                  .rows += [{id: ("theme:entry:" + $id), text: $label, _kind: $kind, _room: $group,
                      group: (if $kind == "core" and ($multiple | not) then null elif $kind == "local" then ($group | gsub("-";" ")) else $group end),
                      children: ("spark-shell://theme/rows/gallery/" + $id), page: ("spark-shell://theme/preview/" + $id), chip: $chips[$id],
                      sign: (if $id == $current then "check" else "opens" end)}]
              end)
        | {title: "Theme gallery", state: ("\(.rows | length) themes"), rows: .rows, short: []}'
}

# The gallery: the sections of the permanent collection, the exhibitions that
# are open, and your own. Each shows a lead work's picture, a note and its count;
# looking changes nothing.
APPEARANCE_CURATION='
.rows as $all |
def onview($name): (($c[0].dispositions // {})[$name].status // "exhibited") == "exhibited";
def works($names): [$names[] as $name | $all[] | select(.text == $name)];
def lead($lead; $works): ([$works[] | select(.text == ($lead // ""))] + [$works[] | select(onview(.text))] + $works)[0];
def count($works): ($works | length | tostring) + (if ($works | length) == 1 then " work" else " works" end);
def words($k): ($idx[$k] // null) as $a
    | if $a == null then null
      else ({vector: "vector", illustration: "illustrated scene", cinematic: "cinematic illustration", pixel: "pixel scene", picture: "picture", color: "plain ground"}[$a.media] // "plain ground")
           + " " + $sep + " " + $a.variant + ([$a.variants | keys[] | select(. != $a.variant) | " " + $sep + " has a " + . + " variant"] | join(""))
      end;
def shown: del(._kind, ._room) | .group = null | words(.id | ltrimstr("theme:entry:")) as $w | if $w == null then del(.line) else .line = $w end;
def collection($title; $state; $works):
    ([$works[] | select(onview(.text))] | length) as $nv
    | ($nv > 0 and $nv < ($works | length)) as $split
    | {title: $title, state: $state, short: [],
       rows: [$works[] | (onview(.text)) as $on | shown | .group = (if $split then (if $on then "on view" else "supporting" end) else null end)]
             | sort_by(if .group == "supporting" then 1 else 0 end)};
'
appearance_gallery() {
    appearance_gallery_entries | jq -c --slurpfile c "$CORE_DIR/curation.json" --argjson idx "$(art_index)" --arg sep "$PANEL_SEP" "$APPEARANCE_CURATION"'
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
           rows: ([$sections[] | del(._n)] + $shows + $personal + $custom), short: []}'
}

# One section, exhibition or collection of yours. A work keeps its id, preview,
# palette and apply, and a theme of yours keeps its precedence by name.
appearance_gallery_collection() {
    appearance_gallery_entries | jq -ec --arg room "$1" --slurpfile c "$CORE_DIR/curation.json" --argjson idx "$(art_index)" --arg sep "$PANEL_SEP" "$APPEARANCE_CURATION"'
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
appearance_colors() {
    _acp=$(palette_file "${THEME:-none}") || return 1
    for _e in $THEME_COLOR_WORDS; do printf '%s\t%s\t%s\n' "${_e%%:*}" "${_e#*:}" "$(palette_get "$_acp" "THEME_${_e#*:}")"; done \
        | jq -Rn --arg label "$(theme_label "$THEME")" '[inputs | split("\t")] as $c
            | ["black","red","green","yellow","blue","magenta","cyan","white"] as $names
            | {title: "Colors", state: $label, short: [],
               rows: ([{id: "theme:colors:from", text: "another theme'"'"'s colors", sign: "opens", children: "spark-shell://theme/rows/colors/from"}]
                      + [$c[] | .[0] as $w | .[1] as $k | .[2] as $hex | ($k | ltrimstr("ANSI_") | tonumber? // null) as $i
                         | {id: ("theme:color:" + $k), group: (if $i == null then "theme colors" elif $i < 8 then "ANSI regular" else "ANSI bright" end),   # as the terminal palette has them
                            text: (if $i == null then ($w | (.[0:1] | ascii_upcase) + .[1:]) else "\($i)  \($names[$i % 8])" end),
                            swatch: $hex, columns: [$hex], tool: {name: "theme_color", arguments: {word: $w}, ask: ["color"]}}])}'
}
appearance_colors_from() {   # every theme, its swatch: Enter takes its colors
    appearance_gallery_entries | jq -c '{title: "Another theme'"'"'s colors", state: "", short: [],
        rows: [.rows[] | (.id | ltrimstr("theme:entry:")) as $n | {id: ("theme:colors:" + $n), text, group, chip, page, quiet: true,
               tool: {name: "theme_colors", arguments: {name: $n}}}]}'
}
# Screens and art: the pictures each screen shows, the clock over the art, the other variant, a loop per picture, the
# dialog's own reels; a picture or a file is picked from your files, and more takes one away
appearance_screens() {
    _asd=$(theme_dir "${THEME:-none}"); _asn=${_asd##*/}; _asa=$(art_of "${THEME:-none}")
    { for _r in landscape-2 landscape-3 portrait dialog-open dialog-close; do
          _f=''; for _e in jpg png webp; do [ -z "$_asd" ] || [ ! -f "$_asd/$_asn-$_r.$_e" ] || _f=$_asn-$_r.$_e; done; printf 'file\t%s\t%s\n' "$_r" "$_f"
      done
      art_stills | while IFS= read -r _f; do _l=$_f; [ -f "${_f%.*}.mp4" ] && _m=loop || _m=still; printf 'loop\t%s\t%s\t%s\n' "$(art_role "$_f")" "$(art_label "$_f")" "$_m"; done
      _p=$(printf '%s' "$_asa" | jq -r '.portrait_file // empty'); [ -z "$_p" ] || { [ -f "$_asd/${_p%.*}.mp4" ] && _m=loop || _m=still; printf 'loop\tportrait\tPortrait\t%s\n' "$_m"; }
    } | jq -Rn --argjson art "$_asa" --arg label "$(theme_label "${THEME:-none}")" '
        [inputs | split("\t")] as $in | ($in | map(select(.[0] == "file")) | map({(.[1]): .[2]}) | add // {}) as $f
        | def file($n; $r; $what; $tool; $args; $types): {id: ("theme:screens:" + $r), group: $what, text: $n, sign: "opens",
              columns: [if $f[$r] == "" then "none" elif ($r | startswith("dialog-")) then "its own" else ($r | gsub("-"; " ") | (.[0:1] | ascii_upcase) + .[1:]) end],   # by its role, as the wallpaper list says it
              children: "spark-shell://files/rows",
              pick: {tool: $tool, types: $types, arguments: $args},
              more: (if $f[$r] == "" then [] else [{name: $tool, arguments: ($args + {path: "none"}), said: "take it away"}] end)};
        {title: "Screens and art", state: $label, short: [],
         rows: ([file("second screen"; "landscape-2"; "pictures"; "theme_panel"; {n: "2"}; ["jpg", "jpeg", "png"]),
                 file("third screen"; "landscape-3"; "pictures"; "theme_panel"; {n: "3"}; ["jpg", "jpeg", "png"]),
                 (file("turned screen"; "portrait"; "pictures"; "theme_portrait"; {}; ["jpg", "jpeg", "png"]) | .pick.arguments = {})]
                + [{id: "theme:screens:clock", group: "idle and lock", text: "clock over the art", columns: [],
                    switch: {on: $art.clock, turn_on: {name: "theme_clock", arguments: {to: "on"}}, turn_off: {name: "theme_clock", arguments: {to: "off"}}}},
                   {id: "theme:screens:pair", group: "variants", text: "other variant", sign: "opens", children: "spark-shell://theme/rows/screens/pair",
                    columns: [([$art.variants | to_entries[] | select(.key != $art.variant) | .value] | first) // "none"]}]
                + [$in[] | select(.[0] == "loop") | {id: ("theme:screens:loop:" + .[1]), group: "loops", text: .[2], sign: "opens", columns: [.[3]],
                    children: "spark-shell://files/rows", pick: {tool: "theme_loop", types: ["mp4"], arguments: {role: .[1]}},
                    more: (if .[3] == "loop" then [{name: "theme_loop", arguments: {role: .[1], path: "none"}, said: "take it away"}] else [] end)}]
                + [file("opening"; "dialog-open"; "dialog"; "theme_reel"; {which: "open"}; ["webp"]), file("closing"; "dialog-close"; "dialog"; "theme_reel"; {which: "close"}; ["webp"])])}'
}
appearance_pairs() {   # the themes in the other light, and none: Enter pairs it
    _apv=$(art_of "${THEME:-none}" | jq -r .variant)
    appearance_gallery_entries | jq -c --argjson idx "$(art_index)" --arg v "$_apv" '{title: "Other variant", state: "", short: [],
        rows: ([{id: "theme:pair:none", text: "none", tool: {name: "theme_pair", arguments: {name: "none"}}}]
               + [.rows[] | (.id | ltrimstr("theme:entry:")) as $n | select(($idx[$n].variant // "") != $v and ($idx[$n].variant // "") != "")
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
appearance_yours() {
    appearance_gallery_entries | jq -c --arg cur "${THEME:-none}" --arg label "$(theme_label "${THEME:-none}")" --arg types "$WALL_TYPES" '
        [.rows[] | select(._kind == "saved")] as $mine
        | {title: "Your themes", short: [],
           state: (($mine | length | tostring) + (if ($mine | length) == 1 then " theme" else " themes" end)),
           rows: ([{id: "theme:new:look", group: "new theme", text: "from the look in use", tool: {name: "theme_save", arguments: {}, ask: ["name"]}},
                   {id: "theme:new:picture", group: "new theme", text: "from a picture", sign: "opens", children: "spark-shell://files/rows",
                    pick: {tool: "theme_picture", types: ($types | split(" "))}},
                   {id: "theme:new:file", group: "new theme", text: "from a theme file", sign: "opens", children: "spark-shell://files/rows",
                    pick: {tool: "theme_install", types: ["spark-theme"]}}]
                  + (if $cur == "none" then [] else [{id: "theme:new:copy", group: "new theme", text: ("a copy of " + $label),
                      tool: {name: "theme_duplicate", arguments: {name: $cur}, ask: ["to"]}}] end)
                  + [$mine[] | del(._kind, ._room) | .group = "yours"
                     | .more = [{name: "theme_rename", arguments: {name: .text}, ask: ["to"], said: "rename"},
                                {name: "theme_duplicate", arguments: {name: .text}, ask: ["to"], said: "duplicate"},
                                {name: "theme_delete", arguments: {name: .text}, said: "delete"}]])}'
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
    _ad_bar=''; _ad_icons=''; _ad_spacing=''
    [ -z "$_ad_dir" ] || { _ad_bar=$(look_get "$_ad_dir" BAR_GLYPHS); _ad_icons=$(look_get "$_ad_dir" DIALOG_ICONS); _ad_spacing=$(look_get "$_ad_dir" DIALOG_SPACING); }
    jq -cn --arg name "$1" --arg label "$(theme_label "$1")" --arg ref "$(palette_reference "$1")" --arg current "${THEME:-none}" --arg chip "$_ad_chip" \
        --arg wall "$_ad_wall" --arg motion "$_ad_motion" --arg anim "$_ad_anim" \
        --arg face "$_ad_face" --arg family "$_ad_family" --arg alpha "$_ad_alpha" --arg size "$_ad_size" \
        --arg bar "$_ad_bar" --arg icons "$_ad_icons" --arg spacing "$_ad_spacing" --argjson art "$(art_of "$1")" \
        --argjson mine "$([ "$_ad_kind" = saved ] && echo true || echo false)" --argjson folder "$([ -n "$_ad_dir" ] && echo true || echo false)" \
        --argjson desktop "$([ "$OS" != Darwin ] && [ "$DESKTOP" = sway ] && echo true || echo false)" '
        def fact($g; $id; $label; $value):
            {id: ("theme:detail:" + $id), group: $g, text: $label, columns: [if $value == "" then "keep current" else $value end]};
        {title: $label, short: [], rows: ([
            {id: ("theme:apply:" + $name), text: (if $name == $current then "in use" else "apply theme" end),
             sign: (if $name == $current then "check" else "blank" end), chip: ($chip | split(" ")),
             quiet: true, page: ("spark-shell://theme/preview/" + $name), tool: {name:"theme_palette",arguments:{name:$name}}}]
            + [{id:"theme:terminal-palette", text:"Terminal palette", sign:"opens", columns:[$ref], children:("spark-shell://theme/rows/palette/"+$name)}]
            + [fact("art"; "media"; "medium"; ({vector: "vector", illustration: "illustrated scene", cinematic: "cinematic illustration", pixel: "pixel scene", picture: "picture", color: "plain ground"}[$art.media] // "plain ground"))]
            + (if $art.source == "family" then [fact("art"; "family-of"; "family"; $art.title)] else [] end)
            + [fact("art"; "variant"; "variant"; $art.variant)]
            + [$art.variants | to_entries[] | select(.key != $art.variant)
               | {id: ("theme:variant:" + .key), group: "art", text: (.key + " variant"), sign: "opens", columns: [.value | ltrimstr("core-")],
                  children: ("spark-shell://theme/rows/gallery/" + .value)}]
            + (if $desktop then [fact("wallpaper and motion"; "wall"; "wallpaper"; $wall),
                                 fact("wallpaper and motion"; "moves"; "art motion"; (if $art.motion == "ambient" then "moves with moving wallpaper on" else "still" end)),
                                 fact("wallpaper and motion"; "motion"; "wallpaper motion"; $motion),
                                 {id: "theme:compositions", group: "screens", text: "compositions", sign: "opens",
                                  columns: [if ($art.screens | length) > 1 then "panels for " + ($art.screens[1:] | map(tostring) | join(" and ")) + " screens too" else "landscape and portrait" end], children: ("spark-shell://theme/rows/gallery/" + $name + "/art")},
                                 fact("screens"; "turned"; "turned screen"; (if $art.portrait == "authored" then "its own composition" else "the art fitted, never cropped" end)),
                                 fact("screens"; "panels"; "two and three screens"; (if ($art.screens | length) > 1 then "panels for " + ($art.screens[1:] | map(tostring) | join(" and ")) + " screens" else "the art on each screen" end)),
                                 fact("idle and lock"; "rest"; "idle and lock"; (if $art.clock then "the art, the clock over it" else "the art alone" end))] else [] end)
            + [fact("wallpaper and motion"; "animation"; "dialog motion"; $anim),
               fact("type and glyphs"; "face"; "typeface"; $face), fact("type and glyphs"; "size"; "text size"; $size),
               fact("type and glyphs"; "family"; "glyph family"; $family), fact("type and glyphs"; "bar"; "the bar"; $bar),
               fact("windows"; "alpha"; "opacity"; (if $alpha == "" then "" else (($alpha | tonumber) * 100 | round | tostring) + "%" end)),
               fact("windows"; "icons"; "app icons"; $icons), fact("windows"; "spacing"; "app spacing"; $spacing)]
            + (if $mine then
                 [{id: "theme:manage:rename", group: "manage", text: "Rename", tool: {name: "theme_rename", arguments: {name: $name}, ask: ["to"]}},
                  {id: "theme:manage:duplicate", group: "manage", text: "Duplicate", tool: {name: "theme_duplicate", arguments: {name: $name}, ask: ["to"]}},
                  {id: "theme:manage:delete", group: "manage", text: "Delete", tool: {name: "theme_delete", arguments: {name: $name}}}]
               else [{id: "theme:manage:duplicate", group: "manage", text: "Duplicate as yours", tool: {name: "theme_duplicate", arguments: {name: $name}, ask: ["to"]}}] end)
            + (if $folder then [{id: "theme:manage:export", group: "manage", text: "Export", columns: ["a theme file in Downloads, to share"], tool: {name: "theme_export", arguments: {name: $name}}}] else [] end))}'
}
appearance_art() {   # appearance_art THEME -> its compositions: one screen, a turned screen and the panels its family has; each a preview, none applied
    case $(theme_kind "$1") in shipped|bundled|yours|saved|look) ;; *) return 1 ;; esac
    _aac=$(palette_chip "$1") || return 1
    art_of "$1" | jq -c --arg name "$1" --arg label "$(theme_label "$1")" --arg chip "$_aac" '
        ("spark-shell://theme/preview/" + $name) as $p | ($chip | split(" ")) as $c
        | {title: "Compositions", state: $label, short: [], rows: ([
            {id: "theme:art:landscape", text: "one screen", columns: ["landscape"], page: $p, chip: $c},
            {id: "theme:art:portrait", text: "turned screen", columns: [if .portrait == "authored" then "its own composition" else "the art fitted" end], page: ($p + "/portrait"), chip: $c}]
          + [.screens[1:][] | tostring as $n | {id: ("theme:art:panels-" + $n), text: ({"2": "two screens", "3": "three screens"}[$n]), columns: ["panels"], page: ($p + "/panels-" + $n), chip: $c}])}'
}

appearance_palette() (
    _colors=$(palette_export "$1" env) || return 1
    printf '%s\n' "$_colors" | jq -Rn --arg name "$1" --arg label "$(theme_label "$1")" --arg ref "$(palette_reference "$1")" '
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
    jq -cn --arg name "$1" --arg label "$(theme_label "$1")" --arg native "$TERM_NAME" '
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
    jq -cn --arg title "$(theme_label "$_key")" --arg wall "$_label" --arg ref "$(palette_reference "$_key")" --arg picture "$_picture" --argjson full "$([ "$_width" = 1600 ] && echo true || echo false)" \
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
            else _say='the art fitted, never cropped'; _how=fit; fi ;;
        panels-2|panels-3) _files=$(printf '%s' "$_art" | jq -r --arg n "${_role#panels-}" '.panels[$n] // [] | .[] | (.landscape // .portrait)')
            [ -n "$_files" ] || return 1; _say="${_role#panels-} panels, left to right"; _how=strip ;;
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
    jq -cn --arg title "$(theme_label "$_key")" --arg say "$_say" --arg ref "$(palette_reference "$_key")" --arg picture "$_picture" \
        --argjson full "$([ "${3:-}" = full ] && echo true || echo false)" \
        '{title: $title, facts: [$say, $ref], full: $full} + (if $picture != "" then {picture: $picture} else {say: "Composition preview unavailable"} end)'
)

appearance_sections() {
    _asn=$(theme_saved_names | grep -c '' || :)
    jq -c --arg label "$(theme_label "${THEME:-none}")" --arg yours "$_asn $([ "$_asn" = 1 ] && echo theme || echo themes)" '
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
                    section("interface";"Interface";["theme:show:Transparency","theme:show:Pointer","theme:show:Words on the bar","theme:show:App icons","theme:show:App spacing"]),
                    {id:"theme:settings:colors", text:"Colors", sign:"opens", choice:true, columns:[], children:"spark-shell://theme/rows/colors"}]
                 + (if any($rows[]; .id=="theme:wallpaper") then [{id:"theme:settings:screens", text:"Screens and art", sign:"opens", choice:true, columns:[], children:"spark-shell://theme/rows/screens"}] else [] end)   # the screens of a desktop: none on a Mac
                 + [{id:"theme:settings:yours", text:"Your themes", sign:"opens", choice:true, columns:[$yours],
                     children:"spark-shell://theme/rows/yours"}]'
}
appearance_section() {
    jq -ec --arg key "theme:settings:$1" '
        .rows as $rows | ($rows[]|select(.id==$key)) as $s
        | {title:$s.text, rows:[$s.members[] as $id | $rows[] | select(.id==$id) | .group=null], short:[]}'
}
