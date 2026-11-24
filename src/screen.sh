# shellcheck extended-analysis=false
# Screens: each by its make, model and serial (its place on any port), in screens.conf
# sets: SCREENS_CONF SCREEN_CALLED_JQ SCREEN_ID_CHARS SCREEN_MAIN_MARK SCREEN_PAGE_JQ
# reads: CONFIG_DIR OS PANEL_SEP SAVER_NAMES SAVER_OWN TAB THUMB_DIR TMP US
SCREENS_CONF=$CONFIG_DIR/screens.conf
# a monitor says its own make, model and serial: a quote, a $( ) or a ; in one would be read by the compositor's config and
# by the sh it starts. An id with any other character is never written and never sent: the screen goes by its port
SCREEN_ID_CHARS='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._:()+/,-'
screen_id_ok() {   # screen_id_ok ID -> 0 for 1 to 120 of those characters
    # shellcheck disable=SC2254   # the list is the pattern
    case $1 in ''|*[!$SCREEN_ID_CHARS]*) return 1 ;; esac
    [ "${#1}" -le 120 ]
}
screen_port_ok() { case $1 in *[\ \(\)+/,]*) return 1 ;; esac; [ "${#1}" -le 80 ] && screen_id_ok "$1"; }   # screen_port_ok NAME -> 0 for a port's name
screen_ref() {   # screen_ref ID PORT -> the word a screen's lines go by: its id, or its port where two share the id or a character in it is refused; false for neither
    if screen_id_ok "$1" && [ "$(screen_rows | awk -F '\t' -v i="$1" '$2 == i' | grep -c .)" -eq 1 ]; then printf '%s' "$1"
    elif screen_port_ok "$2"; then printf '%s' "$2"
    else return 1; fi
}
screen_send() { wm_output "\"$1\"" "$3" >/dev/null 2>&1 || { screen_port_ok "$2" && wm_output "$2" "$3" >/dev/null 2>&1; }; }   # screen_send REF PORT WORDS
screen_scale_valid() { [ "${#1}" -le 16 ] && printf '%s\n' "$1" | awk '/^[0-9]+([.][0-9]+)?$/ && $0 + 0 > 0 {ok=1} END {exit !ok}'; }
screen_setting() {   # screen_setting PORT scale|mode|transform VALUE -- _cmd what the compositor is told, _said the receipt; refused when that screen cannot
    case $2 in
        scale) screen_scale_valid "$3" || refuse "scale takes a positive decimal"
            _cmd="scale $3"; _said="$1 scale $3" ;;
        mode) screens_json | jq -e --arg n "$1" --arg m "$3" '.[] | select(.name == $n) | .modes[] | select("\(.width)x\(.height)" == $m or ("\(.width)x\(.height)@\((.refresh // 0) / 1000)Hz" == $m))' >/dev/null 2>&1 || refuse "$1 has no mode $3: $(screens_json | jq -r --arg n "$1" '[.[] | select(.name == $n) | .modes[] | "\(.width)x\(.height)"] | unique | join(", ")')"
            _cmd="mode $3"; _said="$1 $3" ;;
        transform) case $3 in normal|90|180|270) ;; *) refuse "transform takes normal, 90, 180 or 270 (clockwise); no mirrored orientation" ;; esac
            _cmd="transform $3"; if [ "$3" = normal ]; then _said="$1 upright"; else _said="$1 turned $3"; fi ;;
    esac
}
screen_action() (   # screen_action ACTION ARGS [check|try] -- check: the arguments alone; try: a trial (src/trial.sh)
    action=$1; value=$2; check=${3:-}
    set -f; set -- $value
    [ "$#" -ge 1 ] || { echo "a screen is required"; exit 1; }
    name=$1; shift
    screen_port_ok "$name" && [ -n "$(screen_find "$name")" ] || { echo "no connected screen $name"; exit 1; }
    case $action in
        scale) [ "$#" = 1 ] && [ "${1%%=*}" = scale ] && screen_scale_valid "${1#*=}" || exit 1; set -- scale "${1#*=}" ;;
        mode) [ "$#" = 1 ] && printf '%s\n' "$1" | grep -qE '^mode=[0-9]{2,5}x[0-9]{2,5}(@[0-9]{1,4}([.][0-9]{1,3})?Hz)?$' || exit 1; set -- mode "${1#*=}" ;;
        position) [ "$#" = 2 ] && printf '%s\n' "$1 $2" | grep -qE '^x=-?[0-9]{1,5} y=-?[0-9]{1,5}$' || exit 1; set -- position "${1#*=}" "${2#*=}" ;;
        place) [ "$#" = 2 ] && printf '%s\n' "$1 $2" | grep -qE '^side=(left-of|right-of|above|below) other=[A-Za-z0-9_.:-]{1,80}$' || exit 1; set -- "${1#*=}" "${2#*=}" ;;
        transform) [ "$#" = 1 ] && printf '%s\n' "$1" | grep -qE '^transform=(normal|90|180|270)$' || exit 1; set -- transform "${1#*=}" ;;
        screen-on|screen-off) [ "$#" = 0 ] || exit 1; set -- "${action#screen-}" ;;
        main) [ "$#" = 0 ] || exit 1; set -- main ;;
        *) exit 1 ;;
    esac
    case $check in check) exit 0 ;; try) trial_start "$name" "$@"; exit ;; esac
    layout_screen "$name" "$@"
)

# the pages' jq: a screen is called by its model, a laptop's own the built-in screen, by its port where two share a model or
# it has none; outs is get_outputs' list
SCREEN_CALLED_JQ='
def own: (.model // "") as $d | if ($d | type) != "string" or $d == "" or $d == "Unknown" or ($d | test("^0x[0-9A-Fa-f]+$")) then "" else $d | gsub("[|]"; "/") end;
def builtin: .name | test("^(eDP|LVDS|DSI)-");
def called: own as $d | if builtin and ([outs[] | select(builtin)] | length) == 1 then "built-in screen"
    elif $d != "" and ([outs[] | select(own == $d)] | length) == 1 then $d else .name end;
'
SCREEN_PAGE_JQ='
def outs: ($screens[0] // []) | if type == "array" then . else [] end
    | map(select(type == "object" and (.name | type) == "string" and (.name | test("^[A-Za-z0-9_.:-]{1,80}$"))));
'"$SCREEN_CALLED_JQ"'
def id: [.make, .model, .serial] | map(if type != "string" or . == "" then "Unknown" else . end) | join(" ");
def is_main: $main != "" and ($main == .name or $main == id);
def on: .active == true;
def sent: "\(.width)x\(.height)" + (if (.refresh // 0) > 0 then "@\(.refresh / 1000)Hz" else "" end);
def said: "\(.width)x\(.height)" + (if (.refresh // 0) > 0 then " \(.refresh / 10 | round / 100) Hz" else "" end);
def turn: .transform // "normal";
def turned: turn as $t | if $t == "normal" then [] elif $t == "90" or $t == "270" then ["turned"] elif $t == "180" then ["upside down"] else ["mirrored"] end;
def row: {sign: "blank", tool: null, more: [], columns: [], children: null, group: null} + .;
def step($values; $now; $tool; $args; $key; $words):
    {values: $values, at: ($values | map(.sent) | index([$now])), set: {name: $tool, arguments: $args}, key: $key, words: $words};
def place($a): "spark-shell://display/rows/screen/" + $a;
'
display_state() {   # -> "2 screens", "1 screen", nothing with no desktop
    wm_session || return 0
    screens_json | jq -r 'if type == "array" and length > 0 then (if length == 1 then "1 screen" else "\(length) screens" end) else empty end' 2>/dev/null || :
}
provide_display_rows() {   # -> the display section as the dialog shows it: the map and a row a screen, the brightness, then idle and lock
    ROWS_READ=$TMP/once; read_once_end
    if wm_session; then screens_json; fi > "$TMP/display.screens" 2>/dev/null || :
    jq -e 'type == "array"' "$TMP/display.screens" >/dev/null 2>&1 || echo '[]' > "$TMP/display.screens"
    screen_pictures "$TMP/display.screens" > "$TMP/display.pictures" 2>/dev/null || :
    _pdl=$(light_get); case $_pdl in *[!0-9]*) _pdl='' ;; esac
    _pds=$SAVER_OWN; ! saver_can || _pds="$SAVER_OWN $SAVER_NAMES"   # the savers that run here, and the one in use
    case " $_pds " in *" ${DISPLAY_SAVER:-clock} "*) ;; *) _pds="$_pds $DISPLAY_SAVER" ;; esac
    jq -cn --slurpfile screens "$TMP/display.screens" --rawfile pictures "$TMP/display.pictures" --arg main "$(screen_main || :)" --arg sep "$PANEL_SEP" \
        --arg light "$_pdl" --arg idle "${DISPLAY_IDLE:-10}" --arg lock "${DISPLAY_LOCK:-15}" --arg saver "${DISPLAY_SAVER:-clock}" --arg savers "$_pds" "$SCREEN_PAGE_JQ"'
        def minutes($id; $text; $now; $tool): ($now | tonumber) as $n
            | (([5, 10, 15, 30, 60] + [$n | select(. > 0)] | unique) + [0]) as $v
            | {id: ("display:" + $id), text: $text, group: "idle and lock",
               step: step([$v[] | {shown: (if . == 0 then "never" else "\(.) min" end), sent: tostring}]; ($n | tostring); $tool; {}; "minutes"; ["sooner", "later"])} | row;
        ($pictures | split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}) as $pic
        | ([outs[] | select(on)] | sort_by(.rect.x, .rect.y)) as $on
        | ($on + ([outs[] | select(on | not)] | sort_by(.name))) as $all
        | {title: "display", state: (if ($all | length) == 0 then "" elif ($all | length) == 1 then "1 screen" else "\($all | length) screens" end),
           rows: ((if ($all | length) == 0 then [] else
              [{id: "display:map", text: "screens", group: "screens", move: {name: "display_position", arguments: {}},
                screens: [$all[] | {name, text: called, x: (.rect.x // 0), y: (.rect.y // 0), w: (.rect.width // 0), h: (.rect.height // 0), on: on, main: is_main}
                                   + (if $pic[.name] then {picture: $pic[.name]} else {} end) + {children: place(.name)}]} | row]
              + [$all[] | {id: ("display:screen:" + .name), text: called, sign: "opens", children: place(.name), group: "screens",
                  columns: [(if on then [.current_mode | if . == null then empty else "\(.width)x\(.height)" end] + turned + (if is_main then ["main"] else [] end) else ["off"] end) | join(" \($sep) ")]} | row] end)
            + (if $light == "" then [] else ($light | tonumber) as $n | ([range(5; 101; 5), $n] | unique) as $v
                | [{id: "display:brightness", text: "brightness", group: "light",
                    step: step([$v[] | {shown: "\(.)%", sent: tostring}]; ($n | tostring); "display_brightness"; {}; "level"; ["dimmer", "brighter"])} | row] end)
            + [minutes("idle"; "idle screen"; $idle; "display_idle"),
               ({id: "display:saver", text: "saver", group: "idle and lock",
                 step: step([$savers | split(" ")[] | {shown: ., sent: .}]; $saver; "display_saver"; {}; "name"; ["back", "next"])} | row),
               minutes("lock"; "lock"; $lock; "display_lock")])}
        | .short = [.rows[].id]' && _pdr=0 || _pdr=$?
    read_once_end; ROWS_READ=''
    return "$_pdr"
}
provide_screen_rows() {   # provide_screen_rows NAME -> one screen's settings as rows; false for no screen of that name
    screen_port_ok "$1" || return 1
    screens_json > "$TMP/display.screens" 2>/dev/null || :
    jq -cen --arg n "$1" --slurpfile screens "$TMP/display.screens" --arg main "$(screen_main || :)" "$SCREEN_PAGE_JQ"'
        def side($a; $b): if $a.x + $a.width <= $b.x then "left-of" elif $b.x + $b.width <= $a.x then "right-of"
            elif $a.y + $a.height <= $b.y then "above" elif $b.y + $b.height <= $a.y then "below"
            else ($b.x + $b.width / 2 - $a.x - $a.width / 2) as $dx | ($b.y + $b.height / 2 - $a.y - $a.height / 2) as $dy   # one over the other: the way their middles lie
                | if ([$dx, -$dx] | max) >= ([$dy, -$dy] | max) then (if $dx >= 0 then "left-of" else "right-of" end) elif $dy > 0 then "above" else "below" end end;
        outs as $all | ([$all[] | select(.name == $n)][0] | select(. != null)) as $s | ("display:" + $n + ":") as $id
        | ([$all[] | select(on)] | length) as $lit | ($s | on) as $live
        | ($s.current_mode | if . == null then "" else said end) as $res
        | (if $live then [
             ($s | if is_main then {id: ($id + "main"), text: "main screen", columns: ["this one"], muted: true}
                   else {id: ($id + "main"), text: "make it the main screen", tool: {name: "display_main", arguments: {screen: $n}}} end | row),
             ({id: ($id + "resolution"), text: "resolution", columns: [$res | select(. != "")]}
                + (if ($s.modes // [] | length) > 0 then {sign: "opens", choice: true, children: (place($n) + "/modes")} else {muted: true} end) | row),
             ((($s.scale // 1) * 10000 | round / 10000) as $c | [0.75, 1, 1.25, 1.5, 2] as $usual
                | ([$usual[] | select(([. - $c, $c - .] | max) < 0.005)][0] // $c) as $c   # the compositor rounds a scale to a 120th
                | {id: ($id + "scale"), text: "scale",
                   step: step([$usual + [$c] | unique[] | {shown: "\(. * 100 | round)%", sent: tostring}]; ($c | tostring); "display_scale"; {screen: $n}; "scale"; ["smaller", "larger"])} | row),
             ($s | turn as $t | [{shown: "left", sent: "270"}, {shown: "upright", sent: "normal"}, {shown: "right", sent: "90"}, {shown: "upside down", sent: "180"}] as $v   # sway turns the picture clockwise: 90 is a quarter to the right. Each turn beside the one it is reached from: a step shows the screen so, and keeps what it passes
                | {id: ($id + "orientation"), text: "orientation"}
                  + (if ($v | map(.sent) | index([$t])) == null then {columns: ["mirrored"], muted: true}   # the tool makes no mirrored one to go back to
                     else {step: step($v; $t; "display_transform"; {screen: $n}; "transform"; ["turn left", "turn right"])} end) | row)]
             + [$all[] | select(on and .name != $n) | .name as $o
                | {id: ($id + "beside:" + $o), text: ("beside " + called),
                   step: step([{shown: "left", sent: "left-of"}, {shown: "right", sent: "right-of"}, {shown: "above", sent: "above"}, {shown: "below", sent: "below"}];
                              side($s.rect; .rect); "display_place"; {screen: $n, other: $o}; "side"; ["back", "next"])} | row]
           else [] end) as $rows
        | {title: ($s | called), state: (if $live then $res else "off" end),
           rows: ((if $live and $lit == 1 then [] else
                    [{id: ($id + "on"), text: "in use", switch: {on: $live, turn_on: {name: "display_on", arguments: {screen: $n}}, turn_off: {name: "display_off", arguments: {screen: $n}}}} | row] end) + $rows)}
        | .short = [.rows[].id]'
}
provide_screen_modes() {   # provide_screen_modes NAME -> the resolutions it offers as rows, the largest first, the one in use checked
    screen_port_ok "$1" || return 1
    screens_json > "$TMP/display.screens" 2>/dev/null || :
    jq -cen --arg n "$1" --slurpfile screens "$TMP/display.screens" --arg main '' "$SCREEN_PAGE_JQ"'
        ([outs[] | select(.name == $n)][0] | select(. != null)) as $s | ($s.current_mode | if . == null then "" else sent end) as $now
        | ([$s.modes // [] | .[] | select((.width | type) == "number" and (.height | type) == "number") | {sent: sent, said: said, size: [(.width * .height), .width, (.refresh // 0)]}]
           | group_by(.said) | map((map(select(.sent == $now)) + .)[0]) | sort_by(.size) | reverse) as $modes   # two a hundredth of a Hz apart read the same: one row, the one in use where it is one
        | {title: "resolution", state: ($s | called),
           rows: [$modes[] | (.sent == $now) as $at | {id: ("display:" + $n + ":mode:" + .sent), text: .said, sign: (if $at then "check" else "blank" end), back: true,
               tool: (if $at then null else {name: "display_mode", arguments: {screen: $n, mode: .sent}} end)} | row]}
        | .short = [.rows[].id]'
}

# the map's pictures: what each screen shows, small, kept by the picture and its time. Made apart: a page never waits for one
screen_pictures() {   # screen_pictures OUTPUTS-FILE -> NAME<tab>PNG for each screen whose picture is made; the missing are made in the background
    [ "$OS" != Darwin ] && wall_there || return 0
    _spt=''; ! art_wall_theirs || _spt=1   # a picture of yours: on every screen as you set it
    _spd=$THUMB_DIR/screens; : > "$TMP/pictures.make"
    art_screens "$1" 2>/dev/null | while IFS="$TAB" read -r _spn _ _ _ _sps _spr _spx _spm; do
        screen_port_ok "$_spn" || continue
        _spf=''; [ -n "$_spt" ] || [ "$_spr" = landscape ] || _spf=$(art_screen_file "$_spx" "$_spm" "$_sps") || _spf=''
        [ -n "$_spf" ] || _spf=$(wall_path)
        [ -f "$_spf" ] || continue
        _spw=${_sps%x*}; _sph=${_sps#*x}
        case $_spw$_sph in ''|*[!0-9]*) continue ;; esac
        [ "$_spw" -gt 0 ] && [ "$_sph" -gt 0 ] || continue
        if [ "$_spw" -ge "$_sph" ]; then _spz=360x$((360 * _sph / _spw)); else _spz=$((360 * _spw / _sph))x360; fi
        case $_spz in 0x*|*x0) continue ;; esac
        _spo=$_spd/$({ printf '%s %s ' "$_spf" "$_spz"; stat -c '%Y %s' "$_spf" 2>/dev/null || stat -f '%m %z' "$_spf" 2>/dev/null; } | cksum | tr ' ' '-').png
        if [ -s "$_spo" ]; then printf '%s\t%s\n' "$_spn" "$_spo"
        else printf '%s\t%s\t%s\n' "$_spf" "$_spz" "$_spo" >> "$TMP/pictures.make"; fi
    done
    [ ! -s "$TMP/pictures.make" ] || { mkdir_state "$_spd" && screen_pictures_make "$_spd" "$(cat "$TMP/pictures.make")"; }
}
screen_pictures_make() {   # screen_pictures_make DIR "PICTURE<tab>WxH<tab>PNG..." -- apart, one maker at a time; a provider's host reads the rows again once they are made
    [ -z "$(find "$1/.making" -mmin +1 2>/dev/null)" ] || lock_drop "$1/.making"   # a maker that died left its lock
    _spi=/dev/null; [ ! -p "$TMP/in" ] || _spi=$TMP/in
    ( lock_take "$1/.making" || exit 0
      _spq=$TMP/in; TMP=$(mktemp -d) || { lock_drop "$1/.making"; exit 0; }   # the read's TMP is gone before the pictures are made
      trap 'lock_drop "$1/.making"; rm -rf "$TMP"' EXIT; trap 'exit 143' INT TERM HUP
      find "$1" -type f -name '*.png' -mtime +30 -exec rm -f {} + || :
      printf '%s\n' "$2" | while IFS="$TAB" read -r _spf _spz _spo; do [ -s "$_spo" ] || screen_picture "$_spf" "$_spz" "$_spo" || :; done
      [ ! -p "$_spq" ] || fifo_put poke
    ) >/dev/null 2>&1 </dev/null 3>&- 4<&- 5>"$_spi" &
}
screen_picture() {   # screen_picture PICTURE WxH OUT -- the picture as a screen of that shape shows it, filled, a small PNG; whole or not there
    _sqt=$(mktemp "${3%/*}/.picture.XXXXXX") || return 1
    _sqs=1; case $1 in *.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[pP][nN][gG]) ;; *) _sqs='' ;; esac
    if [ -n "$_sqs" ] && [ -z "${SPARK_SHELL_NO_SVG:-}" ] && pic_magic "$1" && command -v rsvg-convert >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then
        { printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%s" height="%s"><image width="%s" height="%s" preserveAspectRatio="xMidYMid slice" xlink:href="data:%s;base64,' "${2%x*}" "${2#*x}" "${2%x*}" "${2#*x}" "$(art_mime "$1")"
          base64 < "$1" | tr -d '\n'; printf '"/></svg>\n'; } > "$TMP/screen.svg" && files_tool rsvg-convert -w "${2%x*}" -h "${2#*x}" -o "$_sqt" "$TMP/screen.svg" 2>/dev/null
    else pic_png "$1" "$_sqt" 360; fi && [ -s "$_sqt" ] && mv "$_sqt" "$3" || { rm -f "$_sqt"; return 1; }
}

screens_json() { wm_outputs || echo '[]'; }
screen_rows() { read_once screens screen_rows_now; }   # -> NAME<tab>ID<tab>ON<tab>MODE<tab>SCALE<tab>X<tab>Y<tab>W<tab>H<tab>MODEL<tab>TRANSFORM per screen (W, H: its place in layout pixels; TRANSFORM normal, 90, 180 or 270)
screen_rows_now() {
    screens_json | jq -r '.[] | [.name, ([.make, .model, .serial] | map(if . == null or . == "" then "Unknown" else . end) | join(" ")), (if .active then "on" else "off" end),
        (if .current_mode then "\(.current_mode.width)x\(.current_mode.height)" + (if (.current_mode.refresh // 0) > 0 then "@\(.current_mode.refresh / 1000)Hz" else "" end) else "" end), ((.scale // 1) * 10000 | round / 10000 | tostring), (.rect.x | tostring), (.rect.y | tostring), (.rect.width | tostring), (.rect.height | tostring), (.model // ""), (.transform // "normal")] | @tsv' 2>/dev/null || :
}
screen_find() { screen_rows | awk -F '\t' -v n="$(panel_lower "$1")" 'tolower($1) == n { r = $0; exit } r == "" && n != "" && index(tolower($2), n) > 0 { r = $0 } END { if (r != "") print r }'; }   # screen_find NAME -> its row: by the port's name, else by words of its make and model
screen_id_refused() {   # screen_id_refused PORT -> the id that port's screen has, where it is refused: a line by it, from before, would win over the port's at the next login
    _sir=$(screen_rows | awk -F '\t' -v n="$1" '$1 == n { print $2; exit }')
    [ -z "$_sir" ] || screen_id_ok "$_sir" || printf '%s' "$_sir"
}
# SCREEN_TRIED: the file a change being tried keeps its lines in until it is kept (src/trial.sh); screens.conf is left alone
screen_save() {   # screen_save REF WORDS [SIDE OTHER-REF] -- the screen's line of that kind in screens.conf, the rest kept; a place beside another is kept as a comment, so a turn places it again
    screen_id_ok "$1" || return 0
    [ -z "${3:-}" ] || screen_id_ok "${4:-}" || set -- "$1" "$2"
    if [ -n "${SCREEN_TRIED:-}" ]; then printf '%s\n' "keep${US}screen$US$1$US$2$US${3:-}$US${4:-}" >> "$SCREEN_TRIED"; return 0; fi
    mkdir -p "$CONFIG_DIR"
    _kd=${2%% *}; case $_kd in enable|disable) _kd="enable disable" ;; esac
    _sso=$(screen_id_refused "$1")
    { [ -f "$SCREENS_CONF" ] && grep -v '^# rendered' "$SCREENS_CONF" | while IFS= read -r _ln; do
            _drop=''; for _k in $_kd; do case $_ln in "output \"$1\" $_k"|"output \"$1\" $_k "*) _drop=1 ;; esac; done
            [ -z "$_sso" ] || for _k in $_kd; do case $_ln in "output \"$_sso\" $_k"|"output \"$_sso\" $_k "*) _drop=1 ;; esac; done
            [ "$_kd" != position ] || case $_ln in "# beside \"$1\" "*|"# beside \"${_sso:-$1}\" "*) _drop=1 ;; esac
            [ -n "$_drop" ] || printf '%s\n' "$_ln"
        done || :; } > "$TMP/screens"
    { echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them'; grep . "$TMP/screens" || :; printf 'output "%s" %s\n' "$1" "$2"
      [ -z "${3:-}" ] || printf '# beside "%s" %s "%s"\n' "$1" "$3" "$4"; } > "$SCREENS_CONF"
}
screen_place_save() {   # screen_place_save REF X Y -- its position line; what it stands beside is kept
    screen_id_ok "$1" || return 0
    if [ -n "${SCREEN_TRIED:-}" ]; then printf '%s\n' "keep${US}place$US$1$US$2$US$3$US" >> "$SCREEN_TRIED"; return 0; fi
    mkdir -p "$CONFIG_DIR"
    _sso=$(screen_id_refused "$1")
    { [ ! -f "$SCREENS_CONF" ] || grep -v -F -e "output \"$1\" position " -e "output \"${_sso:-$1}\" position " -e '# rendered' "$SCREENS_CONF" || :; } > "$TMP/screens"
    { echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them'; grep . "$TMP/screens" || :; printf 'output "%s" position %s %s\n' "$1" "$2" "$3"; } > "$SCREENS_CONF"
}
SCREEN_MAIN_MARK='# the main screen (#135): workspace 1 and the focus at the start'
screen_main_save() {   # screen_main_save REF -- the main screen in screens.conf: workspace 1 and the focus on it at the start
    screen_id_ok "$1" || return 0
    mkdir -p "$CONFIG_DIR"
    { [ -f "$SCREENS_CONF" ] && grep -v -e '^# rendered' -e "^$SCREEN_MAIN_MARK" "$SCREENS_CONF" | wm_main_screen_strip || :; } > "$TMP/screens"
    { echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them'; grep . "$TMP/screens" || :
      printf '%s\n' "$SCREEN_MAIN_MARK"; wm_main_screen_lines "$1"; } > "$SCREENS_CONF"
}
screen_main() { [ -f "$SCREENS_CONF" ] && wm_main_screen_of "$SCREENS_CONF"; }   # -> the main screen's id, as screens.conf names it; nothing when none is set (sway's order decides)
screen_beside_again() {   # screen_beside_again REF -- the screens placed beside REF, and REF beside another, placed again (a turn changed its width)
    [ -f "$SCREENS_CONF" ] || return 0
    grep '^# beside "' "$SCREENS_CONF" | while IFS= read -r _bl; do
        _bi=${_bl#\# beside \"}; _bi=${_bi%%\"*}; _bs=${_bl#*\" }; _bs=${_bs%% *}; _bo=${_bl##* \"}; _bo=${_bo%\"}
        [ "$_bi" = "$1" ] || [ "$_bo" = "$1" ] || continue
        screen_id_ok "$_bi" && screen_id_ok "$_bo" || continue
        _bn=$(screen_rows | awk -F '\t' -v i="$_bi" '$2 == i || $1 == i { print $1; exit }'); _bon=$(screen_rows | awk -F '\t' -v i="$_bo" '$2 == i || $1 == i { print $1; exit }')
        [ -n "$_bn" ] && [ -n "$_bon" ] || continue
        printf '%s\t%s\t%s\n' "$_bn" "$_bs" "$_bon"
    done > "$TMP/beside"
    while IFS="$TAB" read -r _bn _bs _bon; do ( layout_screen "$_bn" "$_bs" "$_bon" ) >/dev/null 2>&1 || :; done < "$TMP/beside"   # its own shell: the turn's receipt stays the turn's
}
