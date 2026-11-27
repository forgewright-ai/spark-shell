# shellcheck shell=sh
# shellcheck extended-analysis=false
# --- the bar's arrangement: what its status shows, in what order and how much of each. One table declares every group
# and every module. The config holds what the person chose (BAR_ORDER, BAR_HIDE, BAR_PINS, BAR_GAUGES): each line of
# the bar reads it again, and arrange_write alone writes the four keys, together
# sets: BAR_FRAME BAR_GROUPS BAR_GROUP_OF BAR_LEVELS BAR_MODULES BAR_STATUS BAR_TABLE BAR_TABLE_GROUPS
# reads: PANEL_SEP

# a group a row: its name | its words. The rows' order is the shipped one. The time's group is the bar's own, at its
# end: it is in no order a person sets
BAR_TABLE_GROUPS='now|now
network|network
sound|sound
screen|screen and keys
power|power and health
time|the time'
# a module a row, in the shipped order, its group's rows together:
#   its name | its group | level, where it has one | toggle, where a click changes it in place and opens nothing
#   | here: 0 where this machine has it | says: its fact, added to the line | click: what a click on it does
#   | its plain name | what it shows
# A later module is one row here, those three functions (src/bar.sh) and its icon. A name is never built from the config
BAR_TABLE='pad|now|-|toggle|bar_here_always|bar_fact_pad|bar_click_pad|windows on the pad|the windows that wait on the pad
due|now|-|-|bar_here_always|bar_fact_due|bar_click_due|reminder due|a reminder that is due
media|now|-|toggle|bar_here_media|bar_fact_media|bar_click_media|what plays|what plays: a click plays or pauses it, the wheel skips
lan|network|-|-|bar_here_lan|bar_fact_lan|bar_click_open|wire|the wired network
bt|network|-|-|bar_here_bt|bar_fact_bt|bar_click_open|bluetooth|bluetooth
wifi|network|level|-|bar_here_wifi|bar_fact_wifi|bar_click_open|wifi|wifi; pinned, its signal as a number, with a gauge or none
out|sound|level|toggle|bar_here_sound|bar_fact_out|bar_click_sound|volume|the sound, its sign mutes; pinned, a number sets the level, with a gauge or none
mic|sound|level|-|bar_here_sound|bar_fact_mic|bar_click_sound|microphone|the microphone, a red dot while something records; pinned, its level
light|screen|level|-|bar_here_light|bar_fact_light|bar_click_light|brightness|the brightness of the screen; pinned, a number sets it, with a gauge or none
kb|screen|-|toggle|bar_here_kb|bar_fact_kb|bar_click_kb|keyboard|the keyboard layout in use
bat|power|-|-|bar_here_bat|bar_fact_bat|bar_click_open|battery|the battery
clock|time|-|-|bar_here_always|bar_fact_clock|bar_click_open|time|the time
notifications|time|-|-|bar_here_notifications|bar_fact_notifications|bar_click_notifications|notifications|the notifications not seen; a moon in do not disturb'
# what the table says, read once: every name the bar has (the workspaces are its own and stay), the levels, the
# status's modules and the time's, each module's group, and the status's groups
BAR_MODULES=workspaces
BAR_LEVELS=''
BAR_STATUS=''
BAR_FRAME=''
BAR_GROUP_OF=' '
BAR_GROUPS=''
while IFS='|' read -r _atn _atg _atl _atr; do
    BAR_MODULES="$BAR_MODULES $_atn"; BAR_GROUP_OF="$BAR_GROUP_OF$_atn=$_atg "
    [ "$_atl" != level ] || BAR_LEVELS="${BAR_LEVELS:+$BAR_LEVELS }$_atn"
    if [ "$_atg" = time ]; then BAR_FRAME="${BAR_FRAME:+$BAR_FRAME }$_atn"; else BAR_STATUS="${BAR_STATUS:+$BAR_STATUS }$_atn"; fi
done <<EOF
$BAR_TABLE
EOF
while IFS='|' read -r _atn _atr; do
    [ "$_atn" = time ] || BAR_GROUPS="${BAR_GROUPS:+$BAR_GROUPS }$_atn"
done <<EOF
$BAR_TABLE_GROUPS
EOF

# arrange_row NAME -> its row: _ag its group, _al level or nothing, _at toggle or nothing, _ah _as _ac its three
# functions, _an its plain name, _aw what it shows; 1 for a name the table does not have
arrange_row() {
    while IFS='|' read -r _arn _ag _al _at _ah _as _ac _an _aw; do
        [ "$_arn" = "$1" ] || continue
        [ "$_al" = level ] || _al=''
        [ "$_at" = toggle ] || _at=''
        return 0
    done <<EOF
$BAR_TABLE
EOF
    _ag=''; _al=''; _at=''; _ah=''; _as=''; _ac=''; _an=''; _aw=''
    return 1
}
# arrange_group NAME -> _ag, its group, with no walk of the table; 1 and nothing for a name the table does not have
arrange_group() {
    case $BAR_GROUP_OF in *" $1="*) _ag=${BAR_GROUP_OF#*" $1="}; _ag=${_ag%% *} ;; *) _ag=''; return 1 ;; esac
}
arrange_group_words() {   # arrange_group_words GROUP -> its words; 1 for a name that is no group
    while IFS='|' read -r _agn _agw; do
        [ "$_agn" != "$1" ] || { printf '%s\n' "$_agw"; return 0; }
    done <<EOF
$BAR_TABLE_GROUPS
EOF
    return 1
}
arrange_is_group() { case " $BAR_GROUPS " in *" $1 "*) ;; *) return 1 ;; esac; }   # arrange_is_group WORD -> 0 for a group of the status
arrange_of() {   # arrange_of GROUP -> _of: its modules, in _order's order
    _of=''
    for _aom in $_order; do arrange_group "$_aom"; [ "$_ag" != "$1" ] || _of="${_of:+$_of }$_aom"; done
}
arrange_groups() {   # -> _groups: the status's groups, in _order's order
    _groups=''
    for _agm in $_order; do
        arrange_group "$_agm"; [ "$_ag" != time ] || continue
        case " $_groups " in *" $_ag "*) ;; *) _groups="${_groups:+$_groups }$_ag" ;; esac
    done
}

# the order as the config has it now. BAR_ORDER is never refused: a name the table does not have, a name said twice and
# the time's two are passed over. A group stands where its first module is named; a module the line does not name (a
# later release's) stands last in its group, and a group it does not name at its shipped place among the others
arrange_order() {   # -> _order: the status's modules, a group together, then the time's
    _aon=''; _aogn=''
    for _aom in $(bar_style BAR_ORDER '' | tr -d '"'); do
        case " $_aon " in *" $_aom "*) continue ;; esac
        arrange_group "$_aom" && [ "$_ag" != time ] || continue
        _aon="$_aon $_aom"
        case " $_aogn " in *" $_ag "*) ;; *) _aogn="$_aogn $_ag" ;; esac
    done
    _aogo=''; _aoq=${_aogn# }   # the named groups take, in their own order, the shipped places of the named ones
    for _aog in $BAR_GROUPS; do
        case " $_aogn " in
            *" $_aog "*) _aogo="$_aogo ${_aoq%% *}"; case $_aoq in *' '*) _aoq=${_aoq#* } ;; *) _aoq='' ;; esac ;;
            *) _aogo="$_aogo $_aog" ;;
        esac
    done
    _order=''
    for _aog in $_aogo; do
        for _aom in $_aon; do arrange_group "$_aom"; [ "$_ag" != "$_aog" ] || _order="$_order $_aom"; done
        for _aom in $BAR_STATUS; do
            case " $_aon " in *" $_aom "*) continue ;; esac
            arrange_group "$_aom"; [ "$_ag" != "$_aog" ] || _order="$_order $_aom"
        done
    done
    _order="${_order# } $BAR_FRAME"
}
# what the config says of the modules, now: _order; _hidden, the modules off the bar (BAR_HIDE); _pinned, the levels
# whose number is on it (BAR_PINS: out where no line says, none for no one); _gauged, the pinned ones that draw a gauge
# beside it (BAR_GAUGES: every pinned level where no line says, as before v0.171, none for no one). A BAR_PINS that
# names a module with no level is v0.147's, the modules it showed: what it leaves out is hidden, and out is pinned
arrange_read() {
    _pinned=$(bar_style BAR_PINS out | tr -d '"'); _hidden=$(bar_style BAR_HIDE '' | tr -d '"')
    [ "$_pinned" != none ] || _pinned=''
    if ! words_in "$_pinned" "$BAR_LEVELS"; then
        for _arm in ${BAR_MODULES#workspaces }; do [ "$_arm" != media ] || continue; case " $_pinned " in *" $_arm "*) ;; *) _hidden="$_hidden $_arm" ;; esac; done   # a line of v0.147 says nothing of media, made after it
        _pinned=out
    fi
    _gauged=$(bar_style BAR_GAUGES '' | tr -d '"'); _argn=''
    case $_gauged in
        '') _argn=$_pinned ;;
        none) ;;
        *) for _arm in $_gauged; do case " $_pinned " in *" $_arm "*) _argn="${_argn:+$_argn }$_arm" ;; esac; done ;;   # a gauge is a pinned level's
    esac
    _gauged=$_argn
    arrange_order
}
arrange_value() {   # arrange_value NAME -> hidden, shown, pinned or gauge, by what arrange_read read
    case " $_hidden " in *" $1 "*) echo hidden; return ;; esac
    case " $_gauged " in *" $1 "*) echo gauge; return ;; esac
    case " $_pinned " in *" $1 "*) echo pinned; return ;; esac
    echo shown
}
# the four keys as _order, _hidden, _pinned and _gauged have them, in one step under the config's lock: no line is
# drawn between two of them. The order names every module of the status; none says no pin and no gauge, since an empty
# value reads as no line. No bar starts again: its next line says it
arrange_write() {
    _awo=''; for _awm in $_order; do arrange_group "$_awm"; [ "$_ag" = time ] || _awo="${_awo:+$_awo }$_awm"; done
    _awh=''; _awp=''; _awg=''   # each list in the bar's own order
    for _awm in ${BAR_MODULES#workspaces }; do
        case " $_hidden " in *" $_awm "*) _awh="${_awh:+$_awh }$_awm" ;; esac
        case " $_pinned " in *" $_awm "*) _awp="${_awp:+$_awp }$_awm" ;; esac
        case " $_gauged " in *" $_awm "*) _awg="${_awg:+$_awg }$_awm" ;; esac
    done
    config_keep BAR_ORDER "$_awo" BAR_HIDE "$_awh" BAR_PINS "${_awp:-none}" BAR_GAUGES "${_awg:-none}" || exit 1
    _hidden=$_awh; _pinned=$_awp; _gauged=$_awg
    bar_redraw
}
arrange_list() { printf '%s' "$1" | sed 's/ /, /g'; }   # arrange_list NAMES -> the names, a comma between
arrange_names_only() { for _ano in "$@"; do case " $BAR_MODULES " in *" $_ano "*) ;; *) return 1 ;; esac; done; }   # arrange_names_only WORD... -> 0 when each is a module's name, and with no word at all
arrange_on_bar() {   # -> _onbar: the modules on the bar, in its order, the workspaces first
    _onbar=workspaces
    for _abm in $_order; do case " $_hidden " in *" $_abm "*) ;; *) _onbar="$_onbar $_abm" ;; esac; done
}
arrange_levels_said() {   # -> what the bar shows of the pinned levels, in words
    _alg=''; _aln=''
    for _alm in $_order; do
        case " $_hidden " in *" $_alm "*) continue ;; esac
        case " $_gauged " in *" $_alm "*) _alg="${_alg:+$_alg }$_alm"; continue ;; esac
        case " $_pinned " in *" $_alm "*) _aln="${_aln:+$_aln }$_alm" ;; esac
    done
    if [ -n "$_alg" ] && [ -n "$_aln" ]; then echo "the bar shows a gauge and a number for $(arrange_list "$_alg"), and a number for $(arrange_list "$_aln")"
    elif [ -n "$_alg" ]; then echo "the bar shows a gauge and a number for $(arrange_list "$_alg")"
    elif [ -n "$_aln" ]; then echo "the bar shows a number for $(arrange_list "$_aln")"
    else echo 'the bar shows no gauge now'; fi
}
# the modules, a line each, in the bar's order, a group's together: its name, its value and what it shows
arrange_listing() {
    arrange_read
    printf '%-13s %-17s %s %s\n' workspaces shown "$PANEL_SEP" 'the workspaces: ten places, and a plate with the number where you are'
    for _alm in $_order; do
        arrange_row "$_alm"; _alv=$(arrange_value "$_alm"); [ "$_alv" != gauge ] || _alv='pinned with gauge'
        printf '%-13s %-17s %s %s\n' "$_alm" "$_alv" "$PANEL_SEP" "$_aw"
    done
}
# the verbs of how much of a module the bar shows. A hide takes it off the bar and a show brings it back. A pin puts a
# level's number and its gauge beside its sign, and an unpin takes both off; gauge off leaves a pinned level its number
# alone, and gauge on draws the gauge again, pinning the level where it was not
arrange_set() {   # arrange_set pin|unpin|hide|show|gauge|ungauge [MODULE...] -- pin alone lists the modules; ungauge is gauge off
    _asv=$1; shift; _asy=$(sparkbar_no_pins "$_asv")   # sway's bar shows every module: nothing to pin or to hide there
    _asw=on; [ "$_asv" != ungauge ] || { _asv=gauge; _asw=off; }
    if [ "$#" = 0 ]; then
        [ "$_asv" = pin ] || refuse_in bar "$_asv takes a module's name: ${BAR_MODULES#workspaces }"
        arrange_listing
        [ -z "$_asy" ] || echo "$_asy"
        return 0
    fi
    [ -z "$_asy" ] || refuse_in bar "$_asy"
    arrange_read
    for _asm in "$@"; do
        case $_asv in
            pin|unpin|gauge) case " $BAR_LEVELS " in *" $_asm "*) ;; *) refuse_in bar "$_asm has no level to pin: a pin is for $BAR_LEVELS" ;; esac ;;
            *) [ "$_asm" != workspaces ] || refuse_in bar "the workspaces stay on the bar (spark-shell bar off --desktop hides the bar)" ;;
        esac
        case $_asv in pin|gauge) case " $_hidden " in *" $_asm "*) refuse_in bar "$_asm is hidden (spark-shell bar show $_asm)" ;; esac ;; esac
        [ "$_asv:$_asw" != gauge:off ] || case " $_pinned " in *" $_asm "*) ;; *) refuse_in bar "$_asm is not pinned: it has no gauge to take off" ;; esac
    done
    _asp=''; _ash=''; _asg=''; _asc=''; _asd=''   # the three lists as they become; what changed; a sound device named
    for _asm in ${BAR_MODULES#workspaces }; do
        case " $_pinned " in *" $_asm "*) _ap1=1 ;; *) _ap1='' ;; esac
        case " $_hidden " in *" $_asm "*) _ah1=1 ;; *) _ah1='' ;; esac
        case " $_gauged " in *" $_asm "*) _ag1=1 ;; *) _ag1='' ;; esac
        case " $* " in *" $_asm "*)
            case $_asm in out|mic) _asd=1 ;; esac
            case $_asv:$_asw in
                pin:*) [ -n "$_ap1" ] || { _ap1=1; _ag1=1; _asc=1; } ;;
                unpin:*) [ -z "$_ap1" ] || { _ap1=''; _ag1=''; _asc=1; } ;;
                hide:*) [ -n "$_ah1" ] || { _ah1=1; _asc=1; } ;;
                show:*) [ -z "$_ah1" ] || { _ah1=''; _asc=1; } ;;
                gauge:on) [ -n "$_ag1" ] || { _ap1=1; _ag1=1; _asc=1; } ;;
                gauge:off) [ -z "$_ag1" ] || { _ag1=''; _asc=1; } ;;
            esac ;;
        esac
        [ -z "$_ap1" ] || _asp="${_asp:+$_asp }$_asm"
        [ -z "$_ah1" ] || _ash="${_ash:+$_ash }$_asm"
        [ -z "$_ag1" ] || _asg="${_asg:+$_asg }$_asm"
    done
    [ -n "$_asc" ] || case $_asv:$_asw in
        pin:*) refuse_in bar "$* pinned already" ;; unpin:*) refuse_in bar "$* not pinned" ;;
        hide:*) refuse_in bar "$* hidden already" ;; show:*) refuse_in bar "$* not hidden" ;;
        gauge:on) refuse_in bar "$* has its gauge already" ;; gauge:off) refuse_in bar "$* has no gauge already" ;;
    esac
    _pinned=$_asp; _hidden=$_ash; _gauged=$_asg
    arrange_write
    arrange_on_bar
    case $_asv in
        pin|unpin) echo "${_asv}ned $* $PANEL_SEP $(arrange_levels_said)" ;;
        gauge) echo "gauge $_asw $* $PANEL_SEP $(arrange_levels_said)" ;;
        hide) _asn=''; [ -z "$_asd" ] || _asn="the shortcut is off the bar, not the device $PANEL_SEP "
            echo "hidden $* $PANEL_SEP ${_asn}the bar shows $(arrange_list "$_onbar")" ;;
        show) echo "shown $* $PANEL_SEP the bar shows $(arrange_list "$_onbar")" ;;
    esac
}

# arrange_put LIST ITEM first|last|before|after [OTHER] -> _put: LIST with ITEM at that place
arrange_put() {
    _apr=''; for _apw in $1; do [ "$_apw" = "$2" ] || _apr="${_apr:+$_apr }$_apw"; done
    _put=''
    case $3 in
        first) _put="$2${_apr:+ $_apr}" ;;
        last) _put="${_apr:+$_apr }$2" ;;
        *) for _apw in $_apr; do
                if [ "$_apw" != "$4" ]; then _put="${_put:+$_put }$_apw"
                elif [ "$3" = before ]; then _put="${_put:+$_put }$2 $_apw"
                else _put="${_put:+$_put }$_apw $2"; fi
            done ;;
    esac
}
arrange_here() {   # arrange_here NAME... -> _here: the ones this machine has, in that order
    _here=''; SND=${SND:-$(snd_tool)}
    for _ahm in "$@"; do arrange_row "$_ahm" && "$_ah" || continue; _here="${_here:+$_here }$_ahm"; done
}
arrange_beside() {   # arrange_beside LIST ITEM left|right -> _beside: the one before or after ITEM in LIST, or nothing
    _beside=''; _abp=''; _abn=''
    for _abw in $1; do
        if [ "$_abw" = "$2" ]; then _abn=1; [ "$3" != left ] || { _beside=$_abp; return 0; }
        elif [ -n "$_abn" ]; then _beside=$_abw; return 0
        else _abp=$_abw; fi
    done
}
arrange_named() {   # arrange_named WORD -> _named: a module's plain name or a group's words; 1 for neither
    if arrange_is_group "$1"; then _named=$(arrange_group_words "$1"); else arrange_row "$1" && _named=$_an; fi
}
# where a module or a group stands. A module moves inside its group, and a group among the groups: the modules of a
# group stand together. left and right are one step, as a key or a row's move asks it: past the modules beside it that
# this machine has, and, from its group's end, the whole group past the next one. default is the shipped order again
arrange_move() {   # arrange_move NAME first|last|left|right | NAME before|after OTHER | default -> the receipt, or exit 1
    _amy=$(sparkbar_no_pins move); [ -z "$_amy" ] || refuse_in bar "$_amy"
    arrange_read
    if [ "${1:-}" = default ] && [ "$#" = 1 ]; then
        _order="$BAR_STATUS $BAR_FRAME"; arrange_write
        echo "the bar's order is the shipped one again"; return 0
    fi
    _amn=${1:-}; _amw=${2:-}; _amo=${3:-}
    _amsay="spark-shell bar move NAME first, last, left, right, before OTHER or after OTHER; NAME is a module (${BAR_STATUS}) or a group ($BAR_GROUPS)"
    case $_amw in first|last|left|right) [ "$#" = 2 ] || refuse_in bar "$_amsay" ;; before|after) [ "$#" = 3 ] || refuse_in bar "$_amsay" ;; *) refuse_in bar "$_amsay" ;; esac
    _amg=''   # the group that moves, where NAME is one or a step takes a module past its group's end
    if arrange_is_group "$_amn"; then _amg=$_amn
    else
        arrange_group "$_amn" || refuse_in bar "$_amn is no module and no group of the bar: $BAR_STATUS, $BAR_GROUPS"
        [ "$_ag" != time ] || refuse_in bar "$_amn stays at the bar's end"
        _amgr=$_ag; arrange_of "$_amgr"; _amof=$_of
        case $_amw in
            left|right) arrange_here $_amof; arrange_beside "$_here" "$_amn" "$_amw"
                if [ -n "$_beside" ]; then _amo=$_beside; _amw=before; [ "$2" = left ] || _amw=after; else _amg=$_amgr; fi ;;
            before|after)
                [ "$_amo" != "$_amn" ] || refuse_in bar "$_amn cannot stand $_amw itself"
                arrange_group "$_amo" && [ "$_ag" = "$_amgr" ] || refuse_in bar "$_amn moves inside its group, $_amgr ($_amof); the group moves as one: spark-shell bar move $_amgr $_amw GROUP" ;;
        esac
    fi
    arrange_groups
    if [ -n "$_amg" ]; then
        case $_amw in
            left|right) _amhg=''   # the groups with a module this machine has: a step passes one of those
                for _amx in $_groups; do arrange_of "$_amx"; arrange_here $_of; [ -z "$_here" ] && [ "$_amx" != "$_amg" ] || _amhg="${_amhg:+$_amhg }$_amx"; done
                arrange_beside "$_amhg" "$_amg" "$_amw"
                [ -n "$_beside" ] || refuse_in bar "$(arrange_group_words "$_amg") is at the status's end already"
                _amo=$_beside; if [ "$_amw" = left ]; then _amw=before; else _amw=after; fi ;;
            before|after)
                arrange_is_group "$_amo" || { arrange_group "$_amo" && [ "$_ag" != time ] && _amo=$_ag; } || refuse_in bar "$_amo is no module and no group of the bar: $BAR_STATUS, $BAR_GROUPS"
                [ "$_amo" != "$_amg" ] || refuse_in bar "$_amg cannot stand $_amw itself" ;;
        esac
        arrange_put "$_groups" "$_amg" "$_amw" "$_amo"
        [ "$_put" != "$_groups" ] || refuse_in bar "$(arrange_group_words "$_amg") stands there already"
        _amgs=$_put; _amnew=''
        for _amx in $_amgs; do arrange_of "$_amx"; _amnew="${_amnew:+$_amnew }$_of"; done
        _order="$_amnew $BAR_FRAME"; _amn=$_amg
    else
        arrange_put "$_amof" "$_amn" "$_amw" "$_amo"
        [ "$_put" != "$_amof" ] || refuse_in bar "$_amn stands there already"
        _amin=$_put; _amnew=''
        for _amx in $_groups; do if [ "$_amx" = "$_amgr" ]; then _amnew="${_amnew:+$_amnew }$_amin"; else arrange_of "$_amx"; _amnew="${_amnew:+$_amnew }$_of"; fi; done
        _order="$_amnew $BAR_FRAME"
    fi
    arrange_write
    arrange_named "$_amn"; _amsaid=$_named
    case $_amw in
        first|last) if [ -n "$_amg" ]; then echo "$_amsaid moved $_amw"; else echo "$_amsaid moved $_amw in $(arrange_group_words "$_amgr")"; fi ;;
        *) arrange_named "$_amo"; echo "$_amsaid moved $_amw $_named" ;;
    esac
}
