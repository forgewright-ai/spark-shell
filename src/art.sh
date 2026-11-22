# shellcheck extended-analysis=false
# ------------------------------------------------- art: families and variants
# A family is one visual concept. Its variants, dark and light, are themes of
# their own, each with its own composition, never one picture inverted. A
# family file (gallery/family/ID.json, or yours in families/) says what a
# look.env cannot: the variants, the medium, whether the art may move, a
# portrait companion and the panels for two and three screens. A theme with no
# family is read from its own look.env, so every theme has the same shape. The
# file is data: jq reads it, each key is checked, and a picture it names is a
# plain PNG or JPEG in the variant's own folder.
# sets: ART_FORMAT FAMILY_CORE FAMILY_MAX FAMILY_RULES SCENES_PIXEL
# reads: CONFIG_DIR PANEL_SEP REPO TAB TMP
ART_FORMAT=1   # a newer format is refused, not half read
FAMILY_CORE=$REPO/gallery/family
FAMILY_MAX=16384
SCENES_PIXEL='garoa horizon watch problem continue crossing'
FAMILY_RULES='
def text($n): type == "string" and length >= 1 and length <= $n and test("^[ -~]*$");
def picture: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}[.](png|jpg|jpeg)$");
def extra($keys): keys_unsorted - $keys;
def panel: type == "object" and length >= 1 and (extra(["landscape", "portrait"]) | length == 0) and all(.[]; picture);
def problems:
  if type != "object" then ["it is not a JSON object"]
  elif (.format | type) != "number" then ["its format is not a number"]
  elif .format > $fmt then ["it was made by a newer spark-shell (format \(.format), this one reads \($fmt)) -- spark-shell update"]
  elif .format != $fmt then ["its format is not \($fmt)"]
  else [
    (extra(["format", "id", "title", "media", "note", "clock", "variants"])[] | "it has a key format \($fmt) has not: \(.)"),
    (if (.id | type == "string" and test("^[a-z][a-z0-9-]{0,39}$")) then empty else "its id is not lowercase letters, digits and dashes, 40 at most" end),
    (if (.title | text(40)) then empty else "its title is not plain text of 40 characters at most" end),
    (if (.media | IN("vector", "illustration", "cinematic", "pixel", "picture", "color")) then empty else "its media is not vector, illustration, cinematic, pixel, picture or color" end),
    (if has("note") and ((.note | text(160)) | not) then "its note is not plain text of 160 characters at most" else empty end),
    (if has("clock") and (.clock | type) != "boolean" then "its clock is not true or false" else empty end),
    (if (.variants | type) != "object" or (.variants | length) == 0 then "it has no variants"
     else (.variants | extra(["dark", "light"])[] | "it has a variant that is not dark or light: \(.)"),
          (.variants | to_entries[] | .key as $v | .value |
             if type != "object" then "its \($v) variant is not an object"
             else (extra(["theme", "portrait", "panels", "motion"])[] | "its \($v) variant has a key format \($fmt) has not: \(.)"),
                  (if (.theme | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")) then empty else "its \($v) variant names no theme" end),
                  (if has("portrait") and ((.portrait | picture) | not) then "its \($v) portrait is not the name of a PNG or JPEG" else empty end),
                  (if has("motion") and ((.motion | IN("ambient", "still")) | not) then "its \($v) motion is not ambient or still" else empty end),
                  (if has("panels") | not then empty
                   elif (.panels | type) != "object" or (.panels | length) == 0 then "its \($v) panels are not panels for 2 or 3 screens"
                   else (.panels | extra(["2", "3"])[] | "its \($v) panels are for 2 or 3 screens, not \(.)"),
                        (.panels | to_entries[] | select(.key | IN("2", "3")) | .key as $n | .value |
                           if type != "array" or length != ($n | tonumber) then "its \($v) panels for \($n) screens are not \($n) panels"
                           elif all(.[]; panel) | not then "its \($v) panels for \($n) screens name something that is not a PNG or JPEG"
                           else empty end)
                   end)
             end)
     end)
  ] end;
problems | first // empty'
family_files() {   # -> the family files, yours first, one a line; an id once
    for _ff in "$CONFIG_DIR"/families/*.json "$FAMILY_CORE"/*.json; do [ -f "$_ff" ] && printf '%s\n' "$_ff"; done | awk -F/ '!seen[$NF]++'
}
family_why() {   # family_why FILE -> nothing and 0 for a family this spark-shell reads; else why in one line and 1
    [ -f "$1" ] && [ ! -L "$1" ] || { echo "it is not a plain file"; return 1; }
    [ "$(wc -c < "$1" | tr -d ' ')" -le "$FAMILY_MAX" ] || { echo "it is over $((FAMILY_MAX / 1024)) KiB"; return 1; }
    ! LC_ALL=C grep -q "[^ -~$TAB]" "$1" || { echo "it holds a byte that is not plain text"; return 1; }
    _fw=$(jq -r --argjson fmt "$ART_FORMAT" "$FAMILY_RULES" "$1" 2>/dev/null) || { echo "it is not JSON"; return 1; }
    [ -z "$_fw" ] || { echo "$_fw"; return 1; }
    [ "${1##*/}" = "$(jq -r .id "$1").json" ] || { echo "its id is not its file's name"; return 1; }
    # the themes it names are here, and each picture is a plain PNG or JPEG in its variant's folder
    jq -r '.variants | to_entries[] | .key as $v | .value as $x
        | ([$v, $x.theme, ""] | @tsv), ([$x.portrait // empty, ($x.panels // {} | .[][] | .[])] | unique[] | [$v, $x.theme, .] | @tsv)' "$1" > "$TMP/family.files"
    while IFS="$TAB" read -r _fv _ft _fp; do
        case $(theme_kind "$_ft") in ''|none) echo "its $_fv variant names $_ft, which is no theme here"; return 1 ;; esac
        [ -n "$_fp" ] || continue
        _fd=$(theme_dir "$_ft"); [ -n "$_fd" ] || { echo "its $_fv variant names $_fp, and $_ft has no folder to hold it"; return 1; }
        [ -f "$_fd/$_fp" ] && [ ! -L "$_fd/$_fp" ] || { echo "its $_fv variant names $_fp, which is not a plain file in the folder of $_ft"; return 1; }
        _fq=$(gallery_picture_ok "$_fd/$_fp") || { echo "its $_fv variant names $_fp: ${_fq#its picture is }"; return 1; }
    done < "$TMP/family.files"
}
family_for() {   # family_for THEME -> the file of the family it is a variant of, or false
    _fl=$(theme_label "$1")
    family_files | while IFS= read -r _ff; do
        jq -e --arg t "$1" --arg l "$_fl" 'any(.variants[]?; (.theme? // "") as $k | $k == $t or $k == $l or ($k | ltrimstr("core-")) == $l)' "$_ff" >/dev/null 2>&1 || continue
        family_why "$_ff" >/dev/null || continue
        printf '%s\n' "$_ff"; break
    done | grep .
}
family_problems() {   # -> FILE<tab>why for each family file this spark-shell refuses
    family_files | while IFS= read -r _ff; do _fw=$(family_why "$_ff") || printf '%s\t%s\n' "$_ff" "$_fw"; done
}
check_art() {   # the family files are read; a refused one is named, never half used
    command -v jq >/dev/null 2>&1 || { chk art ok "na (no jq)"; return; }
    family_problems > "$TMP/art.refused"
    if [ -s "$TMP/art.refused" ]; then
        IFS="$TAB" read -r _caf _caw < "$TMP/art.refused"
        chk art warn "${_caf##*/} is not read: $_caw$([ "$(grep -c '' "$TMP/art.refused")" -lt 2 ] || printf ' (and %s more)' "$(($(grep -c '' "$TMP/art.refused") - 1))")" "correct or remove $_caf"
    else chk art ok "$(family_files | grep -c '') families, each read"; fi
}
art_wall() {   # art_wall THEME -> the wallpaper it brings: a drawing, a scene, picture, a color or default
    _awd=$(theme_dir "$1")
    if [ -n "$_awd" ]; then _aww=$(look_get "$_awd" WALLPAPER); printf '%s' "${_aww:-default}"; return 0; fi
    wall_for_palette "$(theme_label "$1")" || printf default
}
art_media() {   # art_media WALLPAPER -> vector, illustration, pixel, picture or color
    case $1 in picture) echo picture; return ;; esac
    if wall_scene "$1"; then case " $SCENES_PIXEL " in *" $1 "*) echo pixel ;; *) echo illustration ;; esac
    elif wall_shipped "$1"; then echo vector
    else echo color; fi
}
art_variant() {   # art_variant THEME -> dark or light, by its background
    _avp=$(palette_file "$1") || { echo dark; return 0; }
    awk -F= '$1 == "THEME_BG" { b = tolower($2); gsub(/[^0-9a-f]/, "", b) }
        function hx(s, i) { return (index("0123456789abcdef", substr(s, i, 1)) - 1) * 16 + index("0123456789abcdef", substr(s, i + 1, 1)) - 1 }
        END { print ((hx(b, 1) * 299 + hx(b, 3) * 587 + hx(b, 5) * 114) / 1000 < 128 ? "dark" : "light") }' "$_avp"
}
art_of() {   # art_of THEME -> one line of JSON: its family, from the family file or, with none, from the theme itself
    _aw=$(art_wall "$1")
    _amv=still; ! motion_has "$_aw" || _amv=ambient
    _apt=fitted; ! wall_scene "$_aw" || _apt=authored   # every scene draws its own portrait view
    if _af=$(family_for "$1"); then
        jq -c --arg t "$1" --arg l "$(theme_label "$1")" --arg wall "$_aw" --arg mv "$_amv" --arg pt "$_apt" '
            ([.variants | to_entries[] | select(.value.theme == $t or .value.theme == $l or (.value.theme | ltrimstr("core-")) == $l)] | first) as $me
            | {format, id, title, media, note: (.note // null), clock: (.clock // true), source: "family",
               variants: (.variants | map_values(.theme)), variant: $me.key, theme: $me.value.theme, wallpaper: $wall,
               motion: (if $me.value.motion == "still" then "still" else $mv end),
               portrait: (if $me.value.portrait then "authored" else $pt end), portrait_file: ($me.value.portrait // null),
               panels: ($me.value.panels // {}), screens: ([1] + ($me.value.panels // {} | keys | map(tonumber)))}' "$_af"
        return
    fi
    _av=$(art_variant "$1")
    jq -nc --arg t "$1" --arg l "$(theme_label "$1")" --arg wall "$_aw" --arg mv "$_amv" --arg pt "$_apt" --arg v "$_av" --arg m "$(art_media "$_aw")" '
        {format: 1, id: $l, title: $l, media: $m, note: null, clock: true, source: "theme",
         variants: {($v): $t}, variant: $v, theme: $t, wallpaper: $wall, motion: $mv,
         portrait: $pt, portrait_file: null, panels: {}, screens: [1]}'
}
art_words() {   # art_words THEME -> "everforest, dark (light: everforest-light), vector, still, portrait fitted"
    art_of "$1" | jq -r '.variant as $v | [.id, ($v + (.variants | to_entries | map(select(.key != $v) | " (" + .key + ": " + .value + ")") | join(""))), .media, .motion,
        ("portrait " + .portrait), (if (.screens | length) > 1 then "panels for " + (.screens[1:] | map(tostring) | join(" and ")) + " screens" else empty end)] | join(", ")'
}
theme_variant() {   # theme_variant [dark|light] -- the theme in use in its other variant
    [ -n "${THEME:-}" ] && [ "$THEME" != none ] || refuse_in theme "no theme is in use -- spark-shell theme NAME first"
    _tva=$(art_of "$THEME"); _tvn=$(printf '%s' "$_tva" | jq -r .variant)
    [ -n "${1:-}" ] || { printf 'variant %s %s %s\n' "$_tvn" "$PANEL_SEP" "$(printf '%s' "$_tva" | jq -r '.variants | keys | join(" or ")')"; return 0; }
    [ $# -eq 1 ] || refuse_in theme "variant takes one word: dark or light"
    case $1 in dark|light) ;; *) refuse_in theme "variant takes dark or light" ;; esac
    [ "$1" != "$_tvn" ] || { echo "$(theme_label "$THEME") is the $1 variant already"; return 0; }
    _tvt=$(printf '%s' "$_tva" | jq -r --arg v "$1" '.variants[$v] // empty')
    [ -n "$_tvt" ] || refuse_in theme "$(theme_label "$THEME") has no $1 variant"
    theme_apply "$_tvt"
}
