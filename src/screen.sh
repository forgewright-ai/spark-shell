# shellcheck extended-analysis=false
# Screens: each by its make, model and serial (its place on any port), in screens.conf
# sets: SCREENS_CONF SCREEN_MAIN_MARK
# reads: CONFIG_DIR TAB TMP
SCREENS_CONF=$CONFIG_DIR/screens.conf
screen_scale_valid() { [ "${#1}" -le 16 ] && printf '%s\n' "$1" | awk '/^[0-9]+([.][0-9]+)?$/ && $0 + 0 > 0 {ok=1} END {exit !ok}'; }
screen_action() (   # screen_action ACTION ARGS [check]
    action=$1; value=$2; check=${3:-}
    set -f; set -- $value
    [ "$#" -ge 1 ] || { echo "a screen is required"; exit 1; }
    name=$1; shift
    printf '%s\n' "$name" | grep -qE '^[A-Za-z0-9_.:-]{1,80}$' && [ -n "$(screen_find "$name")" ] || { echo "no connected screen $name"; exit 1; }
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
    [ "$check" != check ] || exit 0
    layout_screen "$name" "$@"
)
provide_screen_rows() {   # provide_screen_rows NAME -> the screen's choices as rows, JSON
    printf '%s\n' "$1" | grep -qE '^[A-Za-z0-9_.:-]{1,80}$' || return 1
    screens_json | jq -ce --arg n "$1" --arg main "$(screen_main || :)" '
        . as $screens | [.[] | select(.name == $n)][0] | select(. != null) | . as $screen | ([.make, .model, .serial] | map(if . == null or . == "" then "Unknown" else . end) | join(" ")) as $id |
        def row($key; $text; $args; $group): {id: ($n + ":" + $key + ":" + ($args | tojson)), sign: "blank", text: $text, tool: {name: ("display_" + $key), arguments: ({screen: $n} + $args)}, more: [], columns: [], children: null, group: $group};
        [row((if .active then "off" else "on" end); (if .active then "turn off" else "turn on" end); {}; "power")]
        + ["0.5", "0.75", "1", "1.25", "1.5", "1.75", "2", "2.5", "3" | row("scale"; ("scale " + .); {scale: .}; "scale")]
        + [($screen.modes // [] | map("\(.width)x\(.height)" + (if (.refresh // 0) > 0 then "@\(.refresh / 1000)Hz" else "" end)) | unique)[] | row("mode"; .; {mode: .}; "resolution")]
        + [$screens[] | select(.name != $n and .active) | .name as $other | ["left-of", "right-of", "above", "below"][] | row("place"; (. + " " + $other); {side: ., other: $other}; "arrangement")]
        + ["normal", "90", "180", "270" | row("transform"; (if . == "normal" then "upright" else "turned " + . end); {transform: .}; "orientation")]
        + [row("main"; (if $main != "" and ($main == $n or $main == $id) then "the main screen" else "make it the main screen" end); {}; "main") | if $main != "" and ($main == $n or $main == $id) then .sign = "check" | .tool = null else . end]
        | {title: $n, state: ($screen.model // ""), rows: .} | .short = [.rows[].id]'
}

screens_json() { wm_outputs || echo '[]'; }
screen_rows() { read_once screens screen_rows_now; }   # -> NAME<tab>ID<tab>ON<tab>MODE<tab>SCALE<tab>X<tab>Y<tab>W<tab>H<tab>MODEL<tab>TRANSFORM per screen (W, H: its place in layout pixels; TRANSFORM normal, 90, 180 or 270)
screen_rows_now() {
    screens_json | jq -r '.[] | [.name, ([.make, .model, .serial] | map(if . == null or . == "" then "Unknown" else . end) | join(" ")), (if .active then "on" else "off" end),
        (if .current_mode then "\(.current_mode.width)x\(.current_mode.height)" + (if (.current_mode.refresh // 0) > 0 then "@\(.current_mode.refresh / 1000)Hz" else "" end) else "" end), ((.scale // 1) + 0 | tostring), (.rect.x | tostring), (.rect.y | tostring), (.rect.width | tostring), (.rect.height | tostring), (.model // ""), (.transform // "normal")] | @tsv' 2>/dev/null || :
}
screen_find() { screen_rows | awk -F '\t' -v n="$(panel_lower "$1")" 'tolower($1) == n || (n != "" && index(tolower($2), n) > 0) { print; exit }'; }   # screen_find NAME -> its row: by the port's name, or words of its make and model
screen_save() {   # screen_save ID WORDS [SIDE OTHER-ID] -- the screen's line of that kind in screens.conf, the rest kept; a place beside another is kept as a comment, so a turn places it again
    mkdir -p "$CONFIG_DIR"
    _kd=${2%% *}; case $_kd in enable|disable) _kd="enable disable" ;; esac
    { [ -f "$SCREENS_CONF" ] && grep -v '^# rendered' "$SCREENS_CONF" | while IFS= read -r _ln; do
            _drop=''; for _k in $_kd; do case $_ln in "output \"$1\" $_k"|"output \"$1\" $_k "*) _drop=1 ;; esac; done
            [ "$_kd" != position ] || case $_ln in "# beside \"$1\" "*) _drop=1 ;; esac
            [ -n "$_drop" ] || printf '%s\n' "$_ln"
        done || :; } > "$TMP/screens"
    { echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them'; grep . "$TMP/screens" || :; printf 'output "%s" %s\n' "$1" "$2"
      [ -z "${3:-}" ] || printf '# beside "%s" %s "%s"\n' "$1" "$3" "$4"; } > "$SCREENS_CONF"
}
SCREEN_MAIN_MARK='# the main screen (#135): workspace 1 and the focus at the start'
screen_main_save() {   # screen_main_save ID -- the main screen in screens.conf: workspace 1 and the focus on it at the start
    mkdir -p "$CONFIG_DIR"
    { [ -f "$SCREENS_CONF" ] && grep -v -e '^# rendered' -e "^$SCREEN_MAIN_MARK" "$SCREENS_CONF" | wm_main_screen_strip || :; } > "$TMP/screens"
    { echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them'; grep . "$TMP/screens" || :
      printf '%s\n' "$SCREEN_MAIN_MARK"; wm_main_screen_lines "$1"; } > "$SCREENS_CONF"
}
screen_main() { [ -f "$SCREENS_CONF" ] && wm_main_screen_of "$SCREENS_CONF"; }   # -> the main screen's id, as screens.conf names it; nothing when none is set (sway's order decides)
screen_beside_again() {   # screen_beside_again ID -- the screens placed beside ID, and ID beside another, placed again (a turn changed its width)
    [ -f "$SCREENS_CONF" ] || return 0
    grep '^# beside "' "$SCREENS_CONF" | while IFS= read -r _bl; do
        _bi=${_bl#\# beside \"}; _bi=${_bi%%\"*}; _bs=${_bl#*\" }; _bs=${_bs%% *}; _bo=${_bl##* \"}; _bo=${_bo%\"}
        [ "$_bi" = "$1" ] || [ "$_bo" = "$1" ] || continue
        _bn=$(screen_rows | awk -F '\t' -v i="$_bi" '$2 == i || $1 == i { print $1; exit }'); _bon=$(screen_rows | awk -F '\t' -v i="$_bo" '$2 == i || $1 == i { print $1; exit }')
        [ -n "$_bn" ] && [ -n "$_bon" ] || continue
        printf '%s\t%s\t%s\n' "$_bn" "$_bs" "$_bon"
    done > "$TMP/beside"
    while IFS="$TAB" read -r _bn _bs _bon; do ( layout_screen "$_bn" "$_bs" "$_bon" ) >/dev/null 2>&1 || :; done < "$TMP/beside"   # its own shell: the turn's receipt stays the turn's
}
