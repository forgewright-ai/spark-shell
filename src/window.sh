# shellcheck extended-analysis=false
# The window keys: a place is a half or a quarter of the workspace's area, a two by two grid;
# sets: LAYOUT_PLACE_SLACK
# reads: OS REPO TMP WM_NAME
# past the top the window fills the area, past the bottom it goes to the pad with its place
layout_window_at() {   # layout_window_at PLACE X Y W H -> "X Y W H" of PLACE on that area: L R F a column, T B F a row (FF fills it)
    case $1 in L?) _wx=$2; _ww=$(($4 / 2)) ;; R?) _wx=$(($2 + $4 / 2)); _ww=$(($4 - $4 / 2)) ;; *) _wx=$2; _ww=$4 ;; esac
    case $1 in ?T) _wy=$3; _wh=$(($5 / 2)) ;; ?B) _wy=$(($3 + $5 / 2)); _wh=$(($5 - $5 / 2)) ;; *) _wy=$3; _wh=$5 ;; esac
    echo "$_wx $_wy $_ww $_wh"
}
layout_window_said() {   # layout_window_said PLACE -> where the window is, in words
    case $1 in
        LF) echo 'on the left half' ;; RF) echo 'on the right half' ;; FT) echo 'on the top half' ;; FB) echo 'on the bottom half' ;;
        LT) echo 'in the top left quarter' ;; RT) echo 'in the top right quarter' ;; LB) echo 'in the bottom left quarter' ;; RB) echo 'in the bottom right quarter' ;;
        *) echo 'maximized' ;;
    esac
}
layout_window_near() { _wd=$(($1 - $2)); [ "${_wd#-}" -le 2 ]; }   # layout_window_near A B -- two pixels apart at most: a client's own rounding
layout_window_fits() { [ "$1" -le $(($2 + 2)) ] && [ "$1" -ge $(($2 - $2 / 8)) ]; }   # layout_window_fits GOT WANT -- a size that fills its place: a terminal rounds itself down to whole cells (foot's 1918x537 for 1920x540), an eighth at most
layout_window_place() {   # layout_window_place RX RY RW RH X Y W H -> the place a floating window's rect sits at on that area, or free
    for _wp in FF LF RF FT FB LT RT LB RB; do
        # shellcheck disable=SC2046   # four numbers, split on purpose
        set -- "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" $(layout_window_at "$_wp" "$5" "$6" "$7" "$8")
        if layout_window_near "$1" "$9" && layout_window_near "$2" "${10}" && layout_window_fits "$3" "${11}" && layout_window_fits "$4" "${12}"; then echo "$_wp"; return; fi
        set -- "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
    done
    echo free
}
layout_window_next() {   # layout_window_next KEY PLACE -> the place the key takes a window at PLACE to, or min
    case $1 in
        left|right) _wc=L; [ "$1" = left ] || _wc=R
            case $2 in ?T) echo "${_wc}T" ;; ?B) echo "${_wc}B" ;; *) echo "${_wc}F" ;; esac ;;
        up) case $2 in free) echo FT ;; LF) echo LT ;; RF) echo RT ;; FB) echo FT ;; LB) echo LF ;; RB) echo RF ;; *) echo FF ;; esac ;;
        down) case $2 in free|FF|FT) echo FB ;; LF) echo LB ;; RF) echo RB ;; LT) echo LF ;; RT) echo RF ;; *) echo min ;; esac ;;
        max) echo FF ;;
        *) echo min ;;
    esac
}
# The place marks: _spark-shell.place.PLACE.ID and _spark-shell.area.X.Y.W.H.ID, the area the
# window was placed on; `desktop window refit` puts each placed window back after the area changes
layout_place_marks() { printf ', mark --add _spark-shell.place.%s.%s, mark --add _spark-shell.area.%s.%s.%s.%s.%s' "$1" "$2" "$3" "$4" "$5" "$6" "$2"; }   # layout_place_marks PLACE ID X Y W H -> the place and the area a window wears, after a command
layout_place_unmarks() { [ "$1" = - ] || { printf '%s\n' "$1" | tr ',' '\n' | grep . | sed 's/^/unmark /; s/$/, /' | tr -d '\n'; }; }   # layout_place_unmarks MARKS|- -> "unmark M, " for each of a comma list
LAYOUT_PLACE_SLACK=32   # twice the outer gap and more: how far sway itself may move a placed window when the area's corner moves
layout_refit_soon() {   # a refit half a second on and again a second later: sway lays out a bar or a screen a moment after the command; only under a real sway
    wm_live || return 0
    ( sleep 0.5; sh "$REPO/spark-shell" desktop window refit; sleep 1; sh "$REPO/spark-shell" desktop window refit ) </dev/null >/dev/null 2>&1 &
}
layout_window_refit() {   # layout_window_refit -- after layout_window read the tree: each placed window in sight at its place on the area as it is now; one that left it loses it
    jq -r '.nodes[]? | select(.type == "output" and .name != "__i3") | .current_workspace as $cw | .nodes[]? | select(.type == "workspace" and .name == $cw) | .rect as $a
        | .. | objects | select(.type == "con" or .type == "floating_con") | . as $c
        | [(.marks // [])[] | select(startswith("_spark-shell.place."))] as $p | select($p | length > 0)
        | [(.marks // [])[] | select(startswith("_spark-shell.area."))] as $q
        | "\(.id) \(.type) \(.fullscreen_mode // 0) \(.rect.x) \(.rect.y) \(.rect.width) \(.rect.height) \($p | join(",")) \(if ($q | length) == 0 then "-" else ($q | join(",")) end) \($a.x) \($a.y) \($a.width) \($a.height)"' "$TMP/tree" > "$TMP/refit" 2>/dev/null || :
    _rn=0; _rm=0; _rl=0   # windows wearing a place, moved, left their places
    while read -r _ri _rt _rf _rx _ry _rw _rh _rp _rq _ax _ay _aw _ah; do
        [ -n "${_ah:-}" ] || continue
        _rn=$((_rn + 1))
        _rk=${_rp%%,*}; _rk=${_rk#_spark-shell.place.}; _rk=${_rk%%.*}
        [ "$_rf" = 0 ] || continue   # full screen: left as it is, its place kept for when it leaves full screen
        case $_rk in FF|LF|RF|FT|FB|LT|RT|LB|RB) _rgo=1 ;; *) _rgo='' ;; esac
        [ "$_rt" = floating_con ] || _rgo=''   # tiled again: the tiling has it
        _rax=$_ax _ray=$_ay _raw=$_aw _rah=$_ah   # the area it was placed on: its own, else the area as it is now
        case ${_rq%%,*} in _spark-shell.area.*)
            # shellcheck disable=SC2046   # the mark's four numbers, split on purpose
            set -- $(printf '%s\n' "${_rq%%,*}" | awk -F. '{ print $3, $4, $5, $6 }')
            [ "$#" = 4 ] && _rax=$1 _ray=$2 _raw=$3 _rah=$4 ;;
        esac
        if [ -n "$_rgo" ]; then
            # a client's rounding, and sway's own move: the area can change and come back between two refits
            _rsx=$((2 + LAYOUT_PLACE_SLACK)); _rsy=$((2 + LAYOUT_PLACE_SLACK))
            if [ "$_rax $_ray $_raw $_rah" != "$_ax $_ay $_aw $_ah" ]; then
                _rd=$((_ax - _rax)); _rsx=$((_rsx + ${_rd#-})); _rd=$((_aw - _raw)); _rsx=$((_rsx + ${_rd#-}))
                _rd=$((_ay - _ray)); _rsy=$((_rsy + ${_rd#-})); _rd=$((_ah - _rah)); _rsy=$((_rsy + ${_rd#-}))
            fi
            # shellcheck disable=SC2046   # four numbers, split on purpose
            set -- $(layout_window_at "$_rk" "$_rax" "$_ray" "$_raw" "$_rah")
            _rd=$((_rx - $1)); [ "${_rd#-}" -le "$_rsx" ] || _rgo=''
            _rd=$((_ry - $2)); [ "${_rd#-}" -le "$_rsy" ] || _rgo=''
            layout_window_fits "$_rw" "$3" && layout_window_fits "$_rh" "$4" || _rgo=''   # resized by hand: its size is no longer its place's
        fi
        if [ -z "$_rgo" ]; then   # it left its place: the person's now
            _rc=$(layout_place_unmarks "$_rp,$_rq"); wm_on "con_id=$_ri" "${_rc%, }" </dev/null >/dev/null 2>&1 || :
            _rl=$((_rl + 1)); continue
        fi
        # shellcheck disable=SC2046   # four numbers, split on purpose
        set -- $(layout_window_at "$_rk" "$_ax" "$_ay" "$_aw" "$_ah")
        if layout_window_near "$_rx" "$1" && layout_window_near "$_ry" "$2" && layout_window_fits "$_rw" "$3" && layout_window_fits "$_rh" "$4"; then
            [ "$_rq" != - ] || wm_on "con_id=$_ri" "mark --add _spark-shell.area.$_ax.$_ay.$_aw.$_ah.$_ri" </dev/null >/dev/null 2>&1 || :   # there already
            continue
        fi
        _rc="resize set width $3 px height $4 px, move absolute position $1 $2, $(layout_place_unmarks "$_rq")mark --add _spark-shell.area.$_ax.$_ay.$_aw.$_ah.$_ri"
        wm_on "con_id=$_ri" "$_rc" </dev/null >/dev/null 2>&1 && _rm=$((_rm + 1)) || :
    done < "$TMP/refit"
    if [ "$_rn" = 0 ]; then echo "no window in sight has a place the keys gave it"; return 0; fi
    _rs=''
    case $_rm in 0) ;; 1) _rs='1 window is at its place again' ;; *) _rs="$_rm windows are at their places again" ;; esac
    case $_rl in 0) ;; 1) _rs="${_rs:+$_rs; }1 window that left its place stays where it is" ;; *) _rs="${_rs:+$_rs; }$_rl windows that left their places stay where they are" ;; esac
    echo "${_rs:-the windows the keys placed are at their places}"
}
# A new window: a sway rule marks it _spark-shell.new and runs `desktop window new`; on a
# workspace of placed windows and no tiled one it floats to the largest free place, else it tiles
layout_window_covered() {   # layout_window_covered FILE X Y W H -- a floating window of FILE (layout_window_new's lines) reaches more than 16 pixels into that place each way
    awk -v x="$2" -v y="$3" -v w="$4" -v h="$5" '$1 == "floating" {
        ix = (x + w < $3 + $5 ? x + w : $3 + $5) - (x > $3 ? x : $3); iy = (y + h < $4 + $6 ? y + h : $4 + $6) - (y > $4 ? y : $4)
        if (ix > 16 && iy > 16) found = 1 } END { exit !found }' "$1"
}
layout_window_new() {   # layout_window_new -- after layout_window read the tree: the window the rule marked new, floated to a free place, or left to the tiling
    jq -r 'def views: .. | objects | select(.pid? != null);
        def isnew: any((.marks // [])[]; . == "_spark-shell.new");
        [.. | objects | select(.type == "workspace") | select(any(views; isnew))][0] // empty | . as $w
        | [views | select(isnew)][0] as $n
        | (($n.app_id // "") as $app | ($n.type != "con") or (($n.fullscreen_mode // 0) != 0)
            or (["spark-dialog", "spark-preview", "spark-idle", "spark-pad"] | any(. == $app))
            or any(($n.marks // [])[]; startswith("_spark-shell.") and . != "_spark-shell.new")
            or $w.name == "__i3_scratch" or $w.name == "idle" or ($w.name | startswith("idle "))) as $leave
        | "\(if $leave then "leave" else "new" end) \($n.id) \($w.rect.x) \($w.rect.y) \($w.rect.width) \($w.rect.height)",
          ($w.nodes[]? | views | select(.id != $n.id) | "tiled \(.id)"),
          ($w.floating_nodes[]? | select(.id != $n.id) | "floating \(.id) \(.rect.x) \(.rect.y) \(.rect.width) \(.rect.height) \([(.marks // [])[] | select(startswith("_spark-shell.place."))] | length)")' "$TMP/tree" > "$TMP/new" 2>/dev/null || :
    _nk=''; _ni=''; read -r _nk _ni _nx _ny _nw _nh < "$TMP/new" || :
    [ -n "$_ni" ] || refuse "no window opened just now"
    _nc="[con_id=$_ni] unmark _spark-shell.new"; _ns='tiles'
    [ "$_nk" = new ] || _ns='stays as it opened'
    if [ "$_nk" = new ] && ! grep -q '^tiled ' "$TMP/new"; then
        _npl=''   # a window the keys placed: one that wears a place, or sits at one of the area
        while read -r _nt _ _fx _fy _fw _fh _fp; do
            [ "$_nt" = floating ] || continue
            if [ "$_fp" != 0 ] || [ "$(layout_window_place "$_fx" "$_fy" "$_fw" "$_fh" "$_nx" "$_ny" "$_nw" "$_nh")" != free ]; then _npl=1; break; fi
        done < "$TMP/new"
        if [ -n "$_npl" ]; then
            _nn=''
            for _np in LF RF FT FB LT RT LB RB; do
                # shellcheck disable=SC2046   # four numbers, split on purpose
                set -- $(layout_window_at "$_np" "$_nx" "$_ny" "$_nw" "$_nh")
                layout_window_covered "$TMP/new" "$@" || { _nn=$_np; break; }
            done
            if [ -n "$_nn" ]; then
                _nc="$_nc, floating enable, resize set width $3 px height $4 px, move absolute position $1 $2$(layout_place_marks "$_nn" "$_ni" "$_nx" "$_ny" "$_nw" "$_nh")"; _ns="is $(layout_window_said "$_nn")"
            else
                _nc="$_nc, floating enable, resize set width $((_nw * 2 / 3)) px height $((_nh * 2 / 3)) px, move position center"; _ns='floats at two thirds of the screen, centered: no place is free'
            fi
        fi
    fi
    wm_send "$_nc" >/dev/null 2>&1 || refuse "$WM_NAME refused: $_nc"
    echo "the new window $_ns"
}
layout_window() {   # layout_window float|left|right|up|down|max|min|restore [ID] | refit | new -- the focused window, or the window ID; every placed window in sight; the window just opened (the sway rule's)
    [ "$OS" != Darwin ] || refuse "not on macOS, which has its own window keys"
    case ${1:-} in float|left|right|up|down|max|min|restore|refit|new) ;; *) refuse "window takes float, left, right, up, down, max, min, restore or refit" ;; esac
    wm_up || refuse "moves the desktop's windows: run it inside it"
    wm_tree > "$TMP/tree" || refuse "$WM_NAME did not answer"
    case ${2:-} in *[!0-9]*) refuse "window takes a window's ID, its digits, after the word" ;; esac
    case $1 in restore) layout_window_restore "${2:-}"; return ;; refit) layout_window_refit; return ;; new) layout_window_new; return ;; esac
    _dwid=${2:-}
    # the window: ID TYPE FULL X Y W H TILED MARKS; then its workspace's area
    _dw=$(jq -r --arg id "$_dwid" '[.. | objects | select((if $id == "" then .focused == true else (.id | tostring) == $id end) and (.type == "con" or .type == "floating_con"))][0] // empty
        | "\(.id) \(.type) \(.fullscreen_mode // 0) \(.rect.x // 0) \(.rect.y // 0) \(.rect.width // 0) \(.rect.height // 0) \([(.marks // [])[] | select(startswith("_spark-shell.tiled."))] | length) \([(.marks // [])[] | select(startswith("_spark-shell.place.") or startswith("_spark-shell.area."))] | if length == 0 then "-" else join(",") end)"' "$TMP/tree" 2>/dev/null)
    [ -n "$_dw" ] || refuse "no window has the focus"
    set -- "$1" $_dw
    _dt=${9:-0}   # 1: the window keys floated it from the tiling (its _spark-shell.tiled mark), so the pad tiles it again
    _dun=$(layout_place_unmarks "${10:--}")   # the place it wore: every key gives another, or none
    _da=$(jq -r --argjson i "$2" '[.. | objects | select(.type == "workspace") | select([.. | objects | select(.id == $i)] | length > 0)][0].rect // empty
        | "\(.x) \(.y) \(.width) \(.height)"' "$TMP/tree" 2>/dev/null)
    [ -n "$_da" ] || refuse "the window is on no workspace"
    _dr="$5 $6 $7 $8"
    # shellcheck disable=SC2086   # four numbers, split on purpose
    set -- "$1" "$2" "$3" "$4" $_da   # KIND ID TYPE FULL X Y W H
    _dfs=''; [ "$4" = 0 ] || _dfs='fullscreen disable, '
    _dp=free   # where it sits: a floating window the keys move, not full screen; a window named by its ID is free
    # shellcheck disable=SC2086   # four numbers, split on purpose
    [ -n "$_dwid" ] || [ "$3" != floating_con ] || [ "$4" != 0 ] || _dp=$(layout_window_place $_dr "$5" "$6" "$7" "$8")
    _du=''; [ "$_dt" = 0 ] || _du="unmark _spark-shell.tiled.$2, "   # the float key, or the pad, ends what the tiling mark says
    _dpad=''
    case $1 in
        float) if [ "$3" = floating_con ]; then _dc="${_du}${_dun}floating disable, mark --add _spark-shell.yours.$2"; _ds="tiled"   # tiled by the person: a new window's rule leaves it tiled
            else _dc="${_dfs}${_du}${_dun}floating enable, resize set width $(($7 * 2 / 3)) px height $(($8 * 2 / 3)) px, move position center"; _ds="floating"; fi ;;
        *) _dn=$(layout_window_next "$1" "$_dp")
            if [ "$_dn" = min ]; then
                _dk=$_dp; [ "$_dk" != free ] || { _dk=float; [ "$3" = floating_con ] || _dk=tiled; }   # the place it leaves, else floating or tiled
                [ "$_dt" = 0 ] || _dk=tiled   # a window the keys floated from the tiling tiles again when it comes back
                _dc="${_dfs}${_du}${_dun}mark --add _spark-shell.min.$_dk.$2, move scratchpad"; _ds="on the pad: a click or Super+minus brings it back"; _dpad=1
            else
                _dtm=$_du; [ "$3" = floating_con ] || _dtm="mark --add _spark-shell.tiled.$2, "   # from the tiling: it comes back tiled; a second place a key gives it replaces the mark
                # shellcheck disable=SC2046   # four numbers, split on purpose
                set -- "$@" $(layout_window_at "$_dn" "$5" "$6" "$7" "$8")
                _dc="${_dfs}${_dtm}${_dun}floating enable, resize set width ${11} px height ${12} px, move absolute position $9 ${10}$(layout_place_marks "$_dn" "$2" "$5" "$6" "$7" "$8")"; _ds=$(layout_window_said "$_dn")
            fi ;;
    esac
    wm_on "con_id=$2" "$_dc" >/dev/null 2>&1 || refuse "$WM_NAME refused: $_dc"
    [ -z "$_dpad" ] || { pad_wake; bar_redraw; }   # the pad shows it, and the bar's count
    echo "the window is $_ds"
}
layout_window_restore() {   # layout_window_restore [ID] -- the window ID from the pad, else the last one, back at the place it left; after layout_window read the tree
    _dm=$(jq -r --arg id "${1:-}" '[.. | objects | select(.type == "workspace" and .name == "__i3_scratch") | .floating_nodes[]? | . as $c
        | select($id == "" or (.id | tostring) == $id) | (.marks // [])[] | select(startswith("_spark-shell.min.")) | "\($c.id) \(.)"] | last // empty' "$TMP/tree" 2>/dev/null)
    [ -n "$_dm" ] || { [ -z "${1:-}" ] || refuse "window $1 is not on the pad"; refuse "no window is on the pad"; }
    _di=${_dm%% *}; _dk=${_dm#* }; _dk=${_dk#_spark-shell.min.}; _dk=${_dk%%.*}
    _dc="unmark ${_dm#* }, scratchpad show"
    case $_dk in
        tiled) _dc="$_dc, floating disable"; _ds=tiled ;;
        float) _ds=floating ;;
        *) _da=$(jq -r '[.. | objects | select(.type == "workspace" and .name != "__i3_scratch") | select([.. | objects | select(.focused == true)] | length > 0)][0].rect // empty
                | "\(.x) \(.y) \(.width) \(.height)"' "$TMP/tree" 2>/dev/null)
            [ -n "$_da" ] || refuse "no workspace has the focus"
            # shellcheck disable=SC2046,SC2086   # four numbers, split on purpose
            set -- $(layout_window_at "$_dk" $_da)
            # shellcheck disable=SC2086   # four numbers, split on purpose
            _dc="$_dc, floating disable, floating enable, resize set width $3 px height $4 px, move absolute position $1 $2$(layout_place_marks "$_dk" "$_di" $_da)"; _ds=$(layout_window_said "$_dk") ;;
    esac
    wm_on "con_id=$_di" "$_dc" >/dev/null 2>&1 || refuse "$WM_NAME refused: $_dc"
    bar_redraw   # one window fewer on the pad
    echo "the window is back, $_ds"
}
