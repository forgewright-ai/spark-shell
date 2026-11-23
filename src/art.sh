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
# sets: ART_FORMAT ART_SCREENS FAMILY_CORE FAMILY_MAX FAMILY_RULES SCENES_PIXEL
# reads: CONFIG_DIR CORE_DIR LOOKS_DIR OS PALETTE_DIR PANEL_SEP REPO STATE_DIR TAB THEME_FILE_PICTURE_MAX TMP WALL_CACHE
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
family_files() {   # -> the family files, yours first, one a line; an id once: a theme's own (family.json in its folder, its id the folder's name), then the shared
    for _ff in "$PALETTE_DIR"/*/family.json "$LOOKS_DIR"/*/family.json "$CORE_DIR"/*/family.json "$CONFIG_DIR"/families/*.json "$FAMILY_CORE"/*.json; do [ -f "$_ff" ] && printf '%s\n' "$_ff"; done \
        | awk -F/ '{ k = ($NF == "family.json") ? $(NF - 1) ".json" : $NF } !seen[k]++'
}
family_why() {   # family_why FILE -> nothing and 0 for a family this spark-shell reads; else why in one line and 1
    [ -f "$1" ] && [ ! -L "$1" ] || { echo "it is not a plain file"; return 1; }
    [ "$(wc -c < "$1" | tr -d ' ')" -le "$FAMILY_MAX" ] || { echo "it is over $((FAMILY_MAX / 1024)) KiB"; return 1; }
    ! LC_ALL=C grep -q "[^ -~$TAB]" "$1" || { echo "it holds a byte that is not plain text"; return 1; }
    _fw=$(jq -r --argjson fmt "$ART_FORMAT" "$FAMILY_RULES" "$1" 2>/dev/null) || { echo "it is not JSON"; return 1; }
    [ -z "$_fw" ] || { echo "$_fw"; return 1; }
    _fi=${1##*/}; [ "$_fi" != family.json ] || { _fi=${1%/family.json}; _fi=${_fi##*/}.json; }
    [ "$_fi" = "$(jq -r .id "$1").json" ] || { echo "its id is not its file's name"; return 1; }
    # a theme's own names that theme among its variants: a theme that came from someone else speaks for itself alone
    [ "${1##*/}" != family.json ] || jq -e --arg t "${_fi%.json}" 'any(.variants[]; .theme == $t)' "$1" >/dev/null 2>&1 || { echo "it is in the folder of a theme it does not name"; return 1; }
    # the themes it names are here, and each picture is a plain PNG or JPEG in its variant's folder
    jq -r '.variants | to_entries[] | .key as $v | .value as $x
        | ([$v, $x.theme, ""] | @tsv), ([$x.portrait // empty, ($x.panels // {} | .[][] | .[])] | unique[] | [$v, $x.theme, .] | @tsv)' "$1" > "$TMP/family.files"
    while IFS="$TAB" read -r _fv _ft _fp; do
        if [ "${1##*/}" = family.json ] && [ "$_ft" = "${_fi%.json}" ]; then _fd=${1%/family.json}   # its own theme: the folder it is in, there or on its way in
        else
            case $(theme_kind "$_ft") in ''|none) echo "its $_fv variant names $_ft, which is no theme here"; return 1 ;; esac
            [ -n "$_fp" ] || continue
            _fd=$(theme_dir "$_ft"); [ -n "$_fd" ] || { echo "its $_fv variant names $_fp, and $_ft has no folder to hold it"; return 1; }
        fi
        [ -n "$_fp" ] || continue
        [ -f "$_fd/$_fp" ] && [ ! -L "$_fd/$_fp" ] || { echo "its $_fv variant names $_fp, which is not a plain file in the folder of $_ft"; return 1; }
        _fq=$(gallery_picture_ok "$_fd/$_fp" "$THEME_FILE_PICTURE_MAX") || { echo "its $_fv variant names $_fp: ${_fq#its picture is }"; return 1; }
    done < "$TMP/family.files"
}
family_for() {   # family_for THEME -> the file of the family it is a variant of, or false
    _fl=$(theme_label "$1")
    family_files | while IFS= read -r _ff; do
        grep -qF -e "\"$_fl\"" -e "\"core-$_fl\"" -e "\"$1\"" "$_ff" 2>/dev/null || continue   # no mention, no jq
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
    _awp=$(theme_dir "$1")/$(look_get "$(theme_dir "$1")" PICTURE); [ "$_aw" != picture ] || [ ! -f "${_awp%.*}.mp4" ] || _amv=ambient
    if _af=$(family_for "$1"); then
        jq -c --arg t "$1" --arg l "$(theme_label "$1")" --arg wall "$_aw" --arg mv "$_amv" --arg pt "$_apt" '
            ([.variants | to_entries[] | select(.value.theme == $t or .value.theme == $l or (.value.theme | ltrimstr("core-")) == $l)] | first) as $me
            | {format, id, title, media, note: (.note // null), clock: (if has("clock") then .clock else true end), source: "family",
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
art_index() { dirs_cached art.index "$(THEME_DIRS) $LOOKS_DIR $FAMILY_CORE $CONFIG_DIR/families" art_index_now; }   # -> {THEME: {family, title, media, variant, variants}} for every theme here, kept until a theme or family file changes
art_index_now() {
    family_files | while IFS= read -r _aif; do family_why "$_aif" >/dev/null && cat "$_aif"; done | jq -cs . > "$TMP/art.families"
    theme_names | while IFS= read -r _aik; do
        _aiw=$(art_wall "$_aik"); printf '%s\t%s\t%s\t%s\n' "$_aik" "$(theme_label "$_aik")" "$(art_media "$_aiw")" "$(art_variant "$_aik")"
    done | jq -Rnc --slurpfile f "$TMP/art.families" '
        ([$f[0][] | . as $x | .variants | to_entries[] | {key: .value.theme, value: {family: $x.id, title: $x.title, media: $x.media, variant: .key,
            variants: ($x.variants | map_values(.theme))}}] | from_entries) as $fam
        | reduce (inputs | split("\t")) as [$k, $l, $m, $v] ({};
            .[$k] = ($fam[$k] // $fam[$l] // $fam["core-" + $l] // {family: null, title: $l, media: $m, variant: $v, variants: {($v): $k}}))'
}
art_mime() { case $(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z') in jpg|jpeg) echo image/jpeg ;; *) echo image/png ;; esac; }   # art_mime FILE -> its data URI type
art_edges() {   # art_edges PICTURE #GROUND SCRATCH.png -> "#TOP #BOTTOM": the colors along its top and bottom, else the ground twice
    if pic_small "$1" "$3" && _aeg=$(python3 -I "$REPO/lib/look.py" edges "$3" 2>/dev/null); then printf '%s' "$_aeg"
    else printf '%s %s' "$2" "$2"; fi
    rm -f "$3"
}
theme_screens() {   # theme_screens -- what each screen shows, from the left
    [ $# -eq 0 ] || refuse_in theme "screens takes no word"
    [ "$OS" != Darwin ] || refuse_in theme "not on macOS, which has its own desktop"
    command -v jq >/dev/null 2>&1 && wm_up || refuse_in theme "the screens are the desktop's: run it inside it"
    theme_load
    _tsl=$(art_screens); [ -n "$_tsl" ] || refuse_in theme "sway shows no screen on"
    _tsn=$(printf '%s\n' "$_tsl" | grep -c '')
    printf '%s\n' "$_tsl" | while IFS="$TAB" read -r _tsa _tsi _tst _tso _tss _tsr _tsf _tsm; do
        case ${WALLPAPER:-default} in default|none) _tsw="the ground" ;; '#'*) _tsw="the color $WALLPAPER" ;; *) _tsw='' ;; esac
        if [ -z "$_tsw" ] && art_wall_theirs; then _tsw="your wallpaper as you set it"; fi
        if [ -z "$_tsw" ]; then
            case $_tsr:$_tsm in
                landscape:*) _tsw="the art" ;;
                panel*) _tsw="$_tsr ($_tsf)" ;;
                chosen:*) _tsw="the wallpaper ($_tsf)" ;;
                portrait:fill) _tsw="its portrait ($_tsf)" ;;
                portrait:scene) _tsw="the scene drawn for a turned screen" ;;
                *) _tsw="the art fitted, never cropped" ;;
            esac
        fi
        printf '%-10s %s of %s from the left, %s %s: %s\n' "$_tsa" "$_tst" "$_tsn" "$_tso" "$_tss" "$_tsw"
    done
}
art_fit() {   # art_fit PICTURE WxH "#TOP #BOTTOM" OUT -> the picture whole inside WxH, its own top and bottom colors carried on above and below it, a PNG; never cropped
    command -v base64 >/dev/null 2>&1 && command -v rsvg-convert >/dev/null 2>&1 && [ -f "$1" ] || return 1
    _afw=${2%x*}; _afh=${2#*x}; _aft=${3%% *}; _afb=${3##* }
    { printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%s" height="%s">' "$_afw" "$_afh"
      printf '<rect width="%s" height="%s" fill="%s"/><rect y="%s" width="%s" height="%s" fill="%s"/>' "$_afw" "$((_afh / 2))" "$_aft" "$((_afh / 2))" "$_afw" "$((_afh - _afh / 2))" "$_afb"
      printf '<image width="%s" height="%s" preserveAspectRatio="xMidYMid meet" xlink:href="data:%s;base64,' "$_afw" "$_afh" "$(art_mime "$1")"
      base64 < "$1" | tr -d '\n'; printf '"/></svg>\n'; } > "$4.svg" && rsvg-convert -w "$_afw" -h "$_afh" -o "$4.new" "$4.svg" 2>/dev/null && mv "$4.new" "$4"; _afr=$?
    rm -f "$4.svg" "$4.new"; return "$_afr"
}
art_frame() {   # art_frame PICTURE WxH #GROUND #EDGE OUT -> the picture whole, as a screen with a hairline edge, centered on the ground
    command -v base64 >/dev/null 2>&1 && command -v rsvg-convert >/dev/null 2>&1 && [ -f "$1" ] || return 1
    _arw=${2%x*}; _arh=${2#*x}; _arm=$((_arh / 18)); _ari=$((_arh - 2 * _arm))
    set -- "$@" $(png_size "$1"); [ -n "${7:-}" ] || return 1
    _arpw=$((${6} * _ari / ${7})); _arx=$(((_arw - _arpw) / 2))
    { printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%s" height="%s"><rect width="100%%" height="100%%" fill="%s"/>' "$_arw" "$_arh" "$3"
      printf '<image x="%s" y="%s" width="%s" height="%s" preserveAspectRatio="xMidYMid meet" xlink:href="data:%s;base64,' "$_arx" "$_arm" "$_arpw" "$_ari" "$(art_mime "$1")"
      base64 < "$1" | tr -d '\n'
      printf '"/><rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-width="2"/></svg>\n' "$((_arx - 1))" "$((_arm - 1))" "$((_arpw + 2))" "$((_ari + 2))" "$4"; } > "$5.svg" \
        && rsvg-convert -w "$_arw" -h "$_arh" -o "$5.new" "$5.svg" 2>/dev/null && mv "$5.new" "$5"; _arr=$?
    rm -f "$5.svg" "$5.new"; return "$_arr"
}
art_strip() {   # art_strip OUT HEIGHT #GROUND PICTURE... -> the pictures side by side, each 16:9 at HEIGHT with a gap of the ground: a preview of panels
    command -v base64 >/dev/null 2>&1 && command -v rsvg-convert >/dev/null 2>&1 || return 1
    _aso=$1; _ash=$2; _asg=$3; shift 3; _asw=$((_ash * 16 / 9)); _asn=$#; _asgap=$((_ash / 24))
    _astw=$((_asn * _asw + (_asn - 1) * _asgap))
    { printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%s" height="%s"><rect width="100%%" height="100%%" fill="%s"/>' "$_astw" "$_ash" "$_asg"
      _asx=0; for _asp; do
          printf '<image x="%s" width="%s" height="%s" preserveAspectRatio="xMidYMid meet" xlink:href="data:%s;base64,' "$_asx" "$_asw" "$_ash" "$(art_mime "$_asp")"
          base64 < "$_asp" | tr -d '\n'; printf '"/>'; _asx=$((_asx + _asw + _asgap))
      done; printf '</svg>\n'; } > "$_aso.svg" && rsvg-convert -w "$_astw" -h "$_ash" -o "$_aso.new" "$_aso.svg" 2>/dev/null && mv "$_aso.new" "$_aso"; _asr=$?
    rm -f "$_aso.svg" "$_aso.new"; return "$_asr"
}
# The screens: each one's place from the left, its turn and its size, and the
# picture the theme has for it. A family's panels for that many screens go to
# the screens in their order from the left, a panel's portrait picture to a
# turned screen; a turned screen with no panel takes the portrait companion, a
# scene's own portrait view, or the art fitted with its own edges carried on:
# never one picture stretched over turned screens, never a forced crop.
ART_SCREENS='
def pick($p; $tall): if $p == null then null elif $tall then ($p.portrait // null) else ($p.landscape // null) end;
[.[] | select(.active)
  | {name, id: ([.make, .model, .serial] | map(if . == null or . == "" then "Unknown" else . end) | join(" ")),
     x: .rect.x, y: .rect.y, tall: (.rect.height > .rect.width),
     size: "\((.rect.width * (.scale // 1)) | floor)x\((.rect.height * (.scale // 1)) | floor)"}]
| sort_by(.x, .y) | length as $n
| ($art.panels[$n | tostring] // null) as $set
| to_entries[] | (.key + 1) as $at | .value
| (if $set then pick($set[$at - 1]; .tall) else null end) as $panel
| (if $panel then ["panel \($at) of \($n)", $panel, "fill"]
   elif .tall and $art.portrait_file then ["portrait", $art.portrait_file, "fill"]
   elif .tall and $art.portrait == "authored" then ["portrait", "-", "scene"]
   elif .tall then ["fitted", "-", "fit"]
   else ["landscape", "-", "fill"] end) as $r
| [.name, .id, ($at | tostring), (if .tall then "portrait" else "landscape" end), .size] + $r | @tsv'
art_screens() {   # [OUTPUTS-JSON-FILE] -> NAME<tab>ID<tab>AT<tab>TURN<tab>WxH<tab>ROLE<tab>FILE<tab>MODE per screen on, from the left; FILE - for none (a tab is IFS white space: an empty field would vanish)
    _asa=$(art_of "${THEME:-none}")
    _asw=$(printf '%s' "$_asa" | jq -r .wallpaper); _asd=$(theme_dir "${THEME:-none}")
    case ${WALLPAPER:-default} in
        "$_asw") ;;
        "$_asd"/*) [ "$_asw" = picture ] || _asa='' ;;
        *) _asa='' ;;
    esac
    # another wallpaper than the theme's own: read from itself, no companion of the theme's
    [ -n "$_asa" ] || { _asa='{"panels": {}, "portrait_file": null, "portrait": "fitted"}'; ! wall_scene "${WALLPAPER:-}" || _asa='{"panels": {}, "portrait_file": null, "portrait": "authored"}'; }
    _asc=''; case ${WALLPAPER:-} in "$_asd"/?*) [ -z "$_asd" ] || _asc=${WALLPAPER#"$_asd"/} ;; esac   # a picture of the theme's own, chosen
    # the chosen picture is on a screen: where the panels leave it out, the first landscape screen's panel gives way to it
    if [ -n "${1:-}" ]; then cat "$1"; else wm_outputs; fi 2>/dev/null | jq -r --argjson art "$_asa" "$ART_SCREENS" 2>/dev/null \
        | awk -F '\t' -v OFS='\t' -v c="$_asc" '{ r[NR] = $0; f[NR] = $7; if ($7 == c) on = 1; if (!p && $4 == "landscape" && $6 ~ /^panel /) p = NR }
            END { for (i = 1; i <= NR; i++) { if (i == p && c != "" && !on) { $0 = r[i]; $6 = "chosen"; $7 = c; r[i] = $0 }; print r[i] } }' || :
}
art_stills() {   # -> the theme's own landscape pictures, full paths, one a line: its picture, then its panels'
    _ast=$(theme_dir "${THEME:-none}"); [ -n "$_ast" ] || return 0
    { printf '%s\n' "$(look_get "$_ast" PICTURE)"; art_of "$THEME" | jq -r '.panels[][] | .landscape // empty'; } \
        | awk 'NF && !seen[$0]++' | while IFS= read -r _asf; do [ ! -f "$_ast/$_asf" ] || printf '%s\n' "$_ast/$_asf"; done
}
art_still() {   # art_still NAME -> the theme's own landscape picture NAME (its file's name with or without the extension, or its role: landscape-2), full path; else false
    art_stills | while IFS= read -r _asf; do _asb=${_asf##*/}; case $1 in "$_asb"|"${_asb%.*}"|"$(art_role "$_asf")") printf '%s' "$_asf"; exit 0 ;; esac; done | grep .
}
art_role() {   # art_role FILE -> its role in the theme: its name without the extension and the theme's name before it (landscape-1)
    _arb=${1##*/}; _arb=${_arb%.*}; _arb=${_arb#"${THEME:-}"-}; printf '%s' "$_arb"
}
art_label() {   # art_label FILE -> its role as the list says it: Landscape 1
    _arl=$(art_role "$1" | tr '_-' '  '); printf '%s%s' "$(printf '%s' "$_arl" | cut -c1 | tr 'a-z' 'A-Z')" "$(printf '%s' "$_arl" | cut -c2-)"
}
art_wall_theirs() {   # -> 0 when the wallpaper is a picture or a color of the person's own; a theme's own picture, in its folder, is the theme's
    _awt=$(theme_dir "${THEME:-none}")
    if [ -n "$_awt" ]; then case ${WALLPAPER:-} in "$_awt"/*) return 1 ;; esac; fi
    wall_yours || wall_color
}
media_ok() {   # media_ok FILE mp4|webp -> nothing and 0 for a plain MP4 (ftyp, H.264 where ffprobe can say, 7680 by 4320 and 64 MiB at most) or an animated WebP (16 MiB at most); else why in one line and 1
    [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] || { echo "it is not a plain file"; return 1; }
    _mos=$(wc -c < "$1" | tr -d ' ')
    case $2 in
        mp4) [ "$_mos" -le 67108864 ] || { echo "a loop is 64 MiB at most"; return 1; }
            [ "$(od -An -c -j4 -N4 "$1" | tr -d ' \n')" = ftyp ] || { echo "it is no MP4"; return 1; }
            command -v ffprobe >/dev/null 2>&1 || return 0
            _moc=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=p=0 "$1" 2>/dev/null | head -1)
            case $_moc in h264,[0-9]*,[0-9]*) ;; *) echo "its video is not H.264"; return 1 ;; esac
            _mow=${_moc#h264,}; _mow=${_mow%%,*}; _moh=${_moc##*,}
            [ "$_mow" -le 7680 ] && [ "$_moh" -le 7680 ] && [ $((_mow * _moh)) -le $((7680 * 4320)) ] || { echo "it is ${_mow}x$_moh, past 7680x4320"; return 1; } ;;
        webp) [ "$_mos" -le 16777216 ] || { echo "a reel is 16 MiB at most"; return 1; }
            [ "$(od -An -c -N4 "$1" | tr -d ' \n')" = RIFF ] && [ "$(od -An -c -j8 -N4 "$1" | tr -d ' \n')" = WEBP ] || { echo "it is no WebP"; return 1; }
            od -An -c -j12 -N36 "$1" | tr -d ' \n' | grep -q ANIM || { echo "it is a still WebP, no animation"; return 1; } ;;
        *) echo "no such kind"; return 1 ;;
    esac
}
art_loop_of() {   # art_loop_of PICTURE -> the loop beside a picture of the theme's own (NAME.mp4 beside NAME.jpg), a plain MP4; else false
    _ald=$(theme_dir "${THEME:-none}"); [ -n "$_ald" ] || return 1
    case $1 in "$_ald"/*) ;; *) return 1 ;; esac
    _alf=${1%.*}.mp4
    [ -f "$_alf" ] && [ ! -L "$_alf" ] && [ "$(od -An -c -j4 -N4 "$_alf" | tr -d ' \n')" = ftyp ] && printf '%s' "$_alf"
}
art_loops() {   # -> LOOP<tab>SCREEN for each screen whose still has its loop beside it, as the screens plan them; false for none
    art_loop_of "${WALLPAPER:-}" >/dev/null || return 1
    _ald=$(theme_dir "${THEME:-none}")
    art_screens | while IFS="$TAB" read -r _aln _ali _ala _alt _als _alr _alx _alm; do
        [ "$_alm" = fill ] || continue
        if [ "$_alx" = - ]; then _alp=$WALLPAPER; else _alp=$_ald/$_alx; fi
        _all=$(art_loop_of "$_alp") && printf '%s\t%s\n' "$_all" "$_aln"
    done | grep .
}
art_plan_file() { printf '%s' "${XDG_RUNTIME_DIR:-$STATE_DIR}/spark-shell-screens.plan"; }   # -> the screens as last drawn
art_screen_file() {   # art_screen_file FILE MODE WxH -> the still a screen of the plan shows, when it is made; the lock takes these, never a loop
    case $2 in
        fill) case $1 in ""|-) return 0 ;; esac; { _asd=$(theme_dir "${THEME:-}"); [ -f "$_asd/$1" ] && printf '%s' "$_asd/$1"; } ;;
        scene) [ ! -f "$WALL_CACHE/$WALLPAPER-$THEME-$3.png" ] || printf '%s' "$WALL_CACHE/$WALLPAPER-$THEME-$3.png" ;;
        fit) [ ! -f "$WALL_CACHE/screens/$WALLPAPER-$THEME-$3-fit.png" ] || printf '%s' "$WALL_CACHE/screens/$WALLPAPER-$THEME-$3-fit.png" ;;
    esac
}
art_screens_follow() {   # each screen output * does not suit gets its own still: a panel, a portrait, a scene's portrait view or the art fitted; made in the background
    [ "$OS" != Darwin ] && wm_up && command -v jq >/dev/null 2>&1 || return 0
    _asp=$(art_screens); { printf '%s\n' "$_asp"; printf '%s %s\n' "${THEME:-}" "${WALLPAPER:-}"; } > "$(art_plan_file)" 2>/dev/null || :
    case ${WALLPAPER:-default} in default|none|'#'*) return 0 ;; esac
    ! art_wall_theirs || return 0   # a picture or a color of yours: on every screen as you set it
    _asl=$(printf '%s\n' "$_asp" | awk -F '\t' '$6 != "landscape"'); [ -n "$_asl" ] || return 0
    _asd=$(theme_dir "${THEME:-}"); _asw=$(wall_path); [ -n "${HEX_BG:-}" ] || theme_load 2>/dev/null || :; _asg=$(wall_ground 2>/dev/null) || _asg='#000000'; _asf=$(palette_file "${THEME:-}" 2>/dev/null) || _asf=''
    # after a look change's own output * (wall_uncover sends it at 0.25 s), under its cover (gone at 0.85 s): no black frame, nothing overwritten
    ( TMP=$(mktemp -d "${TMPDIR:-/tmp}/spark-shell-art.XXXXXX") || exit 0; trap 'rm -rf "$TMP"' EXIT   # its own scratch: the step's TMP is gone by now, and a helper writing there would leave a folder behind
      sleep 0.5; printf '%s\n' "$_asl" | while IFS="$TAB" read -r _asn _asi _asa _ast _ass _asr _asx _asm; do   # TMP dies with its step: the list in hand
          case $_asm in
              fill) [ -f "$_asd/$_asx" ] || continue
                  wm_send "output \"$_asn\" bg \"$_asd/$_asx\" fill" ;;
              scene) [ -n "$_asf" ] && scene_ready || continue
                  _ssf=$WALL_CACHE/$WALLPAPER-$THEME-$_ass.png
                  [ -f "$_ssf" ] || { mkdir_state "$WALL_CACHE" && scene_still "$WALLPAPER" "$_asf" "$_ass" "$_ssf"; } || continue
                  wm_send "output \"$_asn\" bg \"$_ssf\" fill" ;;
              fit) [ -f "$_asw" ] || continue
                  _ssf=$WALL_CACHE/screens/$WALLPAPER-$THEME-$_ass-fit.png
                  [ -f "$_ssf" ] || { mkdir_state "$WALL_CACHE/screens" && art_fit "$_asw" "$_ass" "$(art_edges "$_asw" "$_asg" "$_ssf.edges.png")" "$_ssf"; } || continue
                  wm_send "output \"$_asn\" bg \"$_ssf\" fill" ;;
          esac >/dev/null 2>&1 || :
      done
      sleep 0.5; motion_raise ) </dev/null >/dev/null 2>&1 3>&- 4<&- &   # each still starts the background drawer anew, over a loop already playing
}
art_screens_changed() {   # on sway's output events: a screen came, went, moved or turned since the screens were last drawn, so every screen's still and loop again
    command -v jq >/dev/null 2>&1 && wm_up || return 0
    _asc=$(art_screens; printf '%s %s\n' "${THEME:-}" "${WALLPAPER:-}")
    [ "$_asc" != "$(cat "$(art_plan_file)" 2>/dev/null)" ] || return 0
    wm_send "output * bg $WALL_BG" >/dev/null 2>&1 || :   # a screen turned back to landscape: output * merges into each screen's own line
    motion_follow
}
