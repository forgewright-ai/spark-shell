# shellcheck extended-analysis=false
# --- the config: the readers of the settings and the theme
# sets: ANIMATION_NAMES ANIM_PAIRED CONFIG_UNSET GLYPH_FAMILIES KB_RE PATH_REFUSED PATH_SAID SAVER_NAMES THEME_KEYS
# reads: CONFIG CONFIG_DIR OS REPO TERM_NAME TMP
GLYPH_FAMILIES='stone star banner'
# load_env FILE [env] -> each KEY=value exported; the file wins over the
# environment (sway's children inherit login's keys), `env` keeps a set key
load_env() {
    [ -f "$1" ] || return 0
    bad=$(grep -nEv '^[[:space:]]*(#|$)|^[A-Z_0-9]+=[^;`$()|&<>]*$' "$1" || true)
    if [ -n "$bad" ]; then
        printf 'spark-shell: %s: refused, these lines are not KEY=value:\n%s\n' "$1" "$bad" >&2
        return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in ''|'#'*|' '*|'	'*) continue ;; esac
        key=${line%%=*}
        val=${line#*=}
        case $val in \"*\") val=${val#\"}; val=${val%\"} ;; esac
        tilde='~'
        case $val in "$tilde"|"$tilde/"*) val=$HOME${val#"$tilde"} ;; esac
        [ -n "$val" ] || continue
        if [ "${2:-}" = env ]; then eval "cur=\${$key:-}"; [ -z "$cur" ] || continue; fi
        export "$key=$val"
    done < "$1"
}
# the keys spark-shell exports; a shell or desktop it starts gets them unset
CONFIG_UNSET='-u PROMPT -u PROMPT_STYLE -u DESKTOP -u FONT -u WALLPAPER -u POINTER -u POINTER_TAP -u POINTER_SCROLL -u POINTER_SPEED -u KEY_REPEAT_DELAY -u KEY_REPEAT_RATE -u KEY_CAPS -u ALPHA -u THEME -u CONSOLE_FONT -u QUIET_LOGIN -u QUIET_BOOT -u DESKTOP_BAR -u BAR_POSITION -u BAR_TEXT -u BAR_TRAY -u WINDOWS -u LOGIN -u DIALOG_SEMANTIC -u DIALOG_ATTACH -u DIALOG_ATTACH_TYPES -u DIALOG_MODEL -u DIALOG_TALK -u DIALOG_ANIMATION -u DIALOG_ICONS -u DIALOG_SPACING -u BAR_GLYPHS -u BAR_WORKSPACES -u GLYPH_FAMILY -u WALLPAPER_MOTION -u DISPLAY_IDLE -u DISPLAY_LOCK -u DISPLAY_SAVER -u KEYBOARD -u DO_NOT_DISTURB -u CLOCK_FORMAT -u WEEK_START -u WINPAD_PLACE -u WINPAD_WIDTH -u WINPAD_SIDE_WIDTH -u WINPAD_BAND -u WINPAD_VIEW -u WINPAD_HEIGHT -u VOICE -u VOICE_ENGINE'

# short_host -> this machine's short name; on a Mac LocalHostName, by
# scutil's full path (/usr/sbin is not on every PATH; hostname -s moves)
short_host() {
    _host=
    [ "$OS" != Darwin ] || _host=$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || true)
    [ -n "$_host" ] || _host=$(hostname -s 2>/dev/null || uname -n | cut -d. -f1)
    printf '%s' "$_host"
}

# the shapes a look's values take: each lands in a line foot, sway or the
# idle screen parses, so no quote, comma, backslash or control character
font_ok() { case $1 in [A-Za-z0-9]*) ;; *) return 1 ;; esac; case $1 in *[!A-Za-z0-9\ :=.+_-]*) return 1 ;; esac; [ ${#1} -le 128 ]; }   # font_ok FONT -> 0 for a face and foot's options (Monaspace Neon:size=11)
alpha_ok() { case $1 in 0|1|0.[0-9]|0.[0-9][0-9]|1.0) return 0 ;; *) return 1 ;; esac; }   # alpha_ok ALPHA -> 0 for 0 to 1, two places at most
pointer_ok() { [ -z "$1" ] || printf '%s\n' "$1" | grep -qE '^[A-Za-z0-9._-]+( [1-9][0-9]{0,2})?$'; }   # pointer_ok POINTER -> 0 for nothing, or a cursor theme's NAME and its SIZE in pixels
path_ok() {   # path_ok PATH -> 0 for a full path a wallpaper may name: PATH_SAID's shape
    case $1 in /*) ;; *) return 1 ;; esac
    case $1 in *[';`$()|&<>']*|*\"*|*\'*|*\\*) return 1 ;; esac
    [ "$(printf '%s' "$1" | tr -d '\001-\037\177')" = "$1" ]
}
PATH_SAID="none of ; \` \$ ( ) | & < >, no quote, no backslash, no control character"
PATH_REFUSED='a path with one of ; ` $ ( ) | & < >, a quote, a backslash or a control character cannot be a wallpaper -- rename the picture'
wall_value_ok() { case $1 in default|none) return 0 ;; esac; wall_shipped "$1" || hex_rgb "$1" >/dev/null || path_ok "$1"; }   # wall_value_ok WALLPAPER -> 0 for default, none, a drawing's name, #rrggbb or a picture's full path in path_ok's shape

config_load() {
    load_env "$CONFIG" || exit 1
    : "${PROMPT:=starship}"
    : "${PROMPT_STYLE:=minimal}"
    : "${DESKTOP:=none}"
    : "${FONT:=Monaspace Neon:size=11}"     # foot's spec, verbatim; drawn as font_spec says until the font is installed
    : "${WALLPAPER:=default}"               # the desktop's background: default (the forge), none, a full path or #rrggbb
    : "${POINTER:=}"                        # the pointer: "NAME [SIZE]", a cursor theme's name and its size in pixels (24); empty: the spark pointer by palette
    : "${ALPHA:=0.95}"                      # foot over a picture: 0..1, 1 = opaque
    : "${DESKTOP_BAR:=yes}"                # the bar on the desktop: yes (shown) or no (hidden)
    : "${BAR_POSITION:=top}"               # where the bar sits: top or bottom
    : "${BAR_TEXT:=auto}"                  # the bar's text size: auto (the text size, larger on a screen of many pixels) or 6 to 40
    : "${BAR_TRAY:=no}"                    # the apps' own icons (the tray) at the bar's end: yes or no
    : "${WINDOWS:=split}"                  # how new windows sit on a workspace: split (side by side), tabs or stacked
    : "${LOGIN:=no}"                       # the login screen on tty1: yes or no
    case $WINDOWS in split|tabs|stacked) ;;
        *) echo "spark-shell: WINDOWS=$WINDOWS in $CONFIG: split, tabs or stacked" >&2; exit 1 ;; esac
    case $BAR_POSITION in top|bottom) ;; *) echo "spark-shell: BAR_POSITION=$BAR_POSITION in $CONFIG: top or bottom" >&2; exit 1 ;; esac
    case $BAR_TEXT in auto|[6-9]|[1-3][0-9]|40) ;; *) echo "spark-shell: BAR_TEXT=$BAR_TEXT in $CONFIG: auto, or a size from 6 to 40" >&2; exit 1 ;; esac
    alpha_ok "$ALPHA" || { echo "spark-shell: ALPHA=$ALPHA in $CONFIG: 0 to 1 (0.95)" >&2; exit 1; }
    font_ok "$FONT" || { echo "spark-shell: FONT=$FONT in $CONFIG: a face and its size as $TERM_NAME takes them (Monaspace Neon:size=11): letters, digits, spaces and : = . + _ -" >&2; exit 1; }
    wall_value_ok "$WALLPAPER" || { echo "spark-shell: WALLPAPER=$WALLPAPER in $CONFIG: default, a drawing's name, #rrggbb or a picture's full path, with $PATH_SAID" >&2; exit 1; }
    case $DESKTOP in none|sway) ;;
        *) echo "spark-shell: DESKTOP=$DESKTOP in $CONFIG: none or sway" >&2; exit 1 ;; esac
    # the console's four: a palette's name, "FACE SIZE", and two switches
    : "${THEME:=}" "${CONSOLE_FONT:=}" "${QUIET_LOGIN:=no}" "${QUIET_BOOT:=no}"
    case $THEME in .*|*[!A-Za-z0-9._-]*) echo "spark-shell: THEME=$THEME in $CONFIG: a palette's name or none (spark-shell theme list)" >&2; exit 1 ;; esac
    if [ -n "$CONSOLE_FONT" ] && ! printf '%s' "$CONSOLE_FONT" | grep -qE '^[A-Za-z0-9._-]+ [0-9][0-9x.]*$'; then
        echo "spark-shell: CONSOLE_FONT=$CONSOLE_FONT in $CONFIG: FACE SIZE (spark-shell font list)" >&2; exit 1
    fi
    pointer_ok "$POINTER" || { echo "spark-shell: POINTER=$POINTER in $CONFIG: a cursor theme's NAME and, after a space, its SIZE in pixels (spark-white 24, spark-black 32, Adwaita)" >&2; exit 1; }
    # the dialog's composer: plus and the file types it attaches, the model chip, talk
    : "${DIALOG_ATTACH:=yes}" "${DIALOG_ATTACH_TYPES:=txt md}" "${DIALOG_MODEL:=yes}" "${DIALOG_TALK:=yes}"
    : "${DIALOG_SEMANTIC:=yes}"   # the dialog's rows ranked by meaning, with spark; no keeps the word search
    : "${DIALOG_ANIMATION:=}"   # the dialog's transitions: a piece of gallery/animation, none, or empty for the palette's own
    [ -z "$DIALOG_ANIMATION" ] || case " none $ANIMATION_NAMES " in *" $DIALOG_ANIMATION "*) ;; *) echo "spark-shell: DIALOG_ANIMATION=$DIALOG_ANIMATION in $CONFIG: none or one of $ANIMATION_NAMES" >&2; exit 1 ;; esac
    : "${DIALOG_ICONS:=on}"   # each app's icon before its name in home's apps; the dialog reads it each second
    case $DIALOG_ICONS in on|off) ;; *) echo "spark-shell: DIALOG_ICONS=$DIALOG_ICONS in $CONFIG: on or off" >&2; exit 1 ;; esac
    : "${DIALOG_SPACING:=groups}"   # the space around the apps with their icons: none, groups, rows
    case $DIALOG_SPACING in none|groups|rows) ;; *) echo "spark-shell: DIALOG_SPACING=$DIALOG_SPACING in $CONFIG: none, groups or rows" >&2; exit 1 ;; esac
    : "${BAR_GLYPHS:=signs}"   # the bar's glyphs: signs or words
    case $BAR_GLYPHS in signs|words) ;; *) echo "spark-shell: BAR_GLYPHS=$BAR_GLYPHS in $CONFIG: signs or words" >&2; exit 1 ;; esac
    : "${GLYPH_FAMILY:=stone}"   # the theme's glyph family: the dialog's signs and waits, the bar's gauges and workspaces; BAR_WORKSPACES is ignored
    case " $GLYPH_FAMILIES " in *" $GLYPH_FAMILY "*) ;; *) echo "spark-shell: GLYPH_FAMILY=$GLYPH_FAMILY in $CONFIG: stone, star or banner" >&2; exit 1 ;; esac
    : "${WALLPAPER_MOTION:=off}"   # a moving wallpaper where the drawing has one: on or off
    case $WALLPAPER_MOTION in on|off) ;; *) echo "spark-shell: WALLPAPER_MOTION=$WALLPAPER_MOTION in $CONFIG: on or off" >&2; exit 1 ;; esac
    : "${VOICE:=yes}"   # the ear on the terminal's band and under Super+Space held; no leaves it out
    : "${VOICE_ENGINE:=}"   # your own engine's command, speaking the ear's contract; empty: spark-ear
    : "${DO_NOT_DISTURB:=no}"   # the notifications kept out of sight, as mako's do-not-disturb mode, across logins
    # the pad: its place, its most width at the top, the bottom or floating (0: the screen's) and at a side,
    # its most height (0: as many rows as its windows need)
    for k in PLACE WIDTH SIDE_WIDTH HEIGHT VIEW BAND; do   # a config from v0.142 or before names them PAD_*: read here, written under the new names by spark-shell on
        eval "v=\${PAD_$k:-}; w=\${WINPAD_$k:-}"; [ -z "$v" ] || [ -n "$w" ] || { eval "WINPAD_$k=\$v"; export "WINPAD_$k"; }
    done
    : "${WINPAD_PLACE:=bottom center}" "${WINPAD_WIDTH:=0}" "${WINPAD_SIDE_WIDTH:=36}" "${WINPAD_HEIGHT:=0}"
    winpad_place_ok "$WINPAD_PLACE" || { echo "spark-shell: WINPAD_PLACE=$WINPAD_PLACE in $CONFIG: top, bottom, left or right and center, start, end or pixels along that edge (bottom center), or free X Y" >&2; exit 1; }
    winpad_width_ok "$WINPAD_WIDTH" 0 || { echo "spark-shell: WINPAD_WIDTH=$WINPAD_WIDTH in $CONFIG: pixels, 0 to 9999 (0: as wide as the screen allows)" >&2; exit 1; }
    winpad_width_ok "$WINPAD_SIDE_WIDTH" 36 || { echo "spark-shell: WINPAD_SIDE_WIDTH=$WINPAD_SIDE_WIDTH in $CONFIG: pixels, 36 to 9999" >&2; exit 1; }
    winpad_width_ok "$WINPAD_HEIGHT" 0 || { echo "spark-shell: WINPAD_HEIGHT=$WINPAD_HEIGHT in $CONFIG: pixels, 0 to 9999 (0: as many rows as needed)" >&2; exit 1; }
    # the pad's view: icons, one a window with its title on hover; titles, a slot a window with icon, app and title
    : "${WINPAD_VIEW:=icons}"
    case $WINPAD_VIEW in icons|titles) ;; *) echo "spark-shell: WINPAD_VIEW=$WINPAD_VIEW in $CONFIG: icons or titles" >&2; exit 1 ;; esac
    # the pad's band: off (the handle alone) or on. A pad hands its band's color down as WINPAD_BAND to what it
    # runs, so a value the config does not hold is that color and falls back to off
    : "${WINPAD_BAND:=off}"
    case $WINPAD_BAND in on|off) ;;
        *) if grep -q '^WINPAD_BAND=' "$CONFIG" 2>/dev/null; then echo "spark-shell: WINPAD_BAND=$WINPAD_BAND in $CONFIG: on or off" >&2; exit 1; fi
           WINPAD_BAND=off ;;
    esac
    for k in QUIET_LOGIN QUIET_BOOT DESKTOP_BAR BAR_TRAY DIALOG_ATTACH DIALOG_MODEL DIALOG_TALK DIALOG_SEMANTIC LOGIN DO_NOT_DISTURB VOICE; do
        eval "v=\$$k"
        case $v in yes|no) ;; *) echo "spark-shell: $k=$v in $CONFIG: yes or no" >&2; exit 1 ;; esac
    done
    # the display (minutes, 0 never) and the keyboard's layouts (xkb names, a variant after a plus)
    : "${DISPLAY_IDLE:=10}" "${DISPLAY_LOCK:=15}" "${DISPLAY_SAVER:=clock}" "${KEYBOARD:=}"
    for k in DISPLAY_IDLE DISPLAY_LOCK; do
        eval "v=\$$k"
        case $v in 0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;; *) echo "spark-shell: $k=$v in $CONFIG: minutes, 0 to 999 (0: never)" >&2; exit 1 ;; esac
    done
    saver_known "$DISPLAY_SAVER" || { echo "spark-shell: DISPLAY_SAVER=$DISPLAY_SAVER in $CONFIG: clock, or one of $SAVER_NAMES" >&2; exit 1; }
    [ -z "$KEYBOARD" ] || printf '%s\n' "$KEYBOARD" | grep -qE "$KB_RE" || { echo "spark-shell: KEYBOARD=$KEYBOARD in $CONFIG: layouts by their xkb names, a space between, a variant after a plus (us us+intl)" >&2; exit 1; }
    printf '%s\n' "$DIALOG_ATTACH_TYPES" | grep -qE '^[a-z0-9]{1,8}( [a-z0-9]{1,8})*$' || { echo "spark-shell: DIALOG_ATTACH_TYPES=$DIALOG_ATTACH_TYPES in $CONFIG: file types in lower case, a space between (txt md)" >&2; exit 1; }
    : "${CLOCK_FORMAT:=24}" "${WEEK_START:=sunday}"
    case $CLOCK_FORMAT in 12|24) ;; *) refuse "CLOCK_FORMAT is 12 or 24" ;; esac
    case $WEEK_START in sunday|monday) ;; *) refuse "WEEK_START is sunday or monday" ;; esac
    export CLOCK_FORMAT WEEK_START
    : "${POINTER_TAP:=on}" "${POINTER_SCROLL:=off}" "${POINTER_SPEED:=0}"
    : "${KEY_REPEAT_DELAY:=600}" "${KEY_REPEAT_RATE:=25}" "${KEY_CAPS:=caps}"
    for k in POINTER_TAP POINTER_SCROLL POINTER_SPEED KEY_REPEAT_DELAY KEY_REPEAT_RATE KEY_CAPS; do
        eval "v=\$$k"
        input_valid "$k" "$v" || { echo "spark-shell: invalid $k in $CONFIG" >&2; exit 1; }
    done
    export POINTER_TAP POINTER_SCROLL POINTER_SPEED KEY_REPEAT_DELAY KEY_REPEAT_RATE KEY_CAPS
    export PROMPT PROMPT_STYLE DESKTOP FONT WALLPAPER ALPHA THEME CONSOLE_FONT QUIET_LOGIN QUIET_BOOT DESKTOP_BAR BAR_POSITION BAR_TEXT BAR_TRAY WINDOWS DIALOG_ATTACH DIALOG_ATTACH_TYPES DIALOG_MODEL DIALOG_TALK DIALOG_SEMANTIC DIALOG_ANIMATION DIALOG_ICONS DIALOG_SPACING BAR_GLYPHS GLYPH_FAMILY WALLPAPER_MOTION LOGIN DISPLAY_IDLE DISPLAY_LOCK DISPLAY_SAVER KEYBOARD POINTER DO_NOT_DISTURB VOICE VOICE_ENGINE WINPAD_PLACE WINPAD_WIDTH WINPAD_SIDE_WIDTH WINPAD_BAND WINPAD_VIEW WINPAD_HEIGHT
}
winpad_place_ok() { printf '%s\n' "$1" | grep -qE '^((top|bottom|left|right) (center|start|end|[0-9]{1,5})|free [0-9]{1,5} [0-9]{1,5})$'; }   # winpad_place_ok PLACE -> 0 for an edge and where along it (bottom center, left 300), or free X Y
winpad_width_ok() { case $1 in ''|*[!0-9]*|0?*) return 1 ;; 0) [ "$2" = 0 ] ;; *) [ "${#1}" -le 4 ] && [ "$1" -ge "$2" ] ;; esac; }   # winpad_width_ok N LEAST -> 0 for whole pixels, LEAST to 9999 (0 alone where LEAST is 0)
ANIMATION_NAMES='moon ripple tide embers sun flight'   # gallery/animation's pieces, in the theme row's order; none is no motion
# the piece each palette brings with its drawing
ANIM_PAIRED="tokyonight-night:moon nord:tide everforest-dark:embers gruvbox-dark:sun catppuccin-mocha:moon dracula:embers rose-pine:ripple selenized-dark:tide solarized-light:sun catppuccin-latte:flight tokyonight-day:flight gruvbox-light:sun everforest-light:ripple rose-pine-dawn:sun selenized-light:tide one-light:flight"
anim_for_palette() { for _e in $ANIM_PAIRED; do [ "${_e%%:*}" != "$1" ] || { printf '%s' "${_e#*:}"; return 0; }; done; echo embers; }   # anim_for_palette PALETTE -> the piece it brings; embers for one with none
anim_palette() { _apd=$(theme_dir "${THEME:-}"); if [ -n "$_apd" ]; then look_get "$_apd" PALETTE; else printf '%s' "${THEME:-}"; fi; }   # -> the shipped palette under the theme in use: a saved theme's own, else the theme
dialog_transitions() {   # -> the piece's drawn folder for the palette in use, else draw:PIECE for the dialog to draw itself; nothing for none
    _dtn=$(anim_now); [ "$_dtn" != none ] || return 0
    _dtp=$(anim_palette); _dta=$REPO/gallery/animation/$_dtn/$_dtp
    if [ -n "$_dtp" ] && [ -f "$_dta/open.gif" ]; then printf '%s\n' "$_dta"; else printf 'draw:%s\n' "$_dtn"; fi
}
anim_drawn() { [ -n "$1" ] && [ -f "$REPO/gallery/animation/${ANIMATION_NAMES%% *}/$1/open.gif" ]; }   # anim_drawn PALETTE -> true when the pieces were drawn ahead for it (the shipped palettes)
anim_now() {   # -> the piece the dialog plays: none with no palette, else the one set, else the palette's own
    _anp=$(anim_palette)
    if [ -z "$_anp" ] || [ "$_anp" = none ]; then printf none
    elif [ -n "${DIALOG_ANIMATION:-}" ]; then printf '%s' "$DIALOG_ANIMATION"
    else anim_for_palette "$_anp"; fi
}
SAVER_NAMES='spark starfield drift'   # lib/saver.py's list, in its order: what DISPLAY_SAVER takes besides clock
KB_RE='^[a-z]{2,10}(\+[a-z0-9_-]{1,24})?( [a-z]{2,10}(\+[a-z0-9_-]{1,24})?){0,7}$'   # one to eight layouts, a variant after a plus: us us+intl
config_renames() {   # spark-shell on: the pad's settings a config from v0.142 or before names PAD_*, written once under their WINPAD_* names
    [ -f "$CONFIG" ] && _crn=$(grep -cE '^PAD_(PLACE|WIDTH|SIDE_WIDTH|HEIGHT|VIEW|BAND)=' "$CONFIG") || return 0
    need config "$_crn settings of the pad take their WINPAD_ names, PAD_ before ($CONFIG)" || return 0
    # a setting the config already holds under its new name keeps that line; the old one goes
    awk 'NR == FNR { if ($0 ~ /^WINPAD_[A-Z_]*=/) { k = $0; sub(/=.*/, "", k); have[k] = 1 }; next }
        /^PAD_(PLACE|WIDTH|SIDE_WIDTH|HEIGHT|VIEW|BAND)=/ { k = $0; sub(/=.*/, "", k); if (!(("WIN" k) in have)) print "WIN" $0; next }
        { print }' "$CONFIG" "$CONFIG" > "$TMP/config" && cp "$TMP/config" "$CONFIG"
    ok config "$_crn settings of the pad are WINPAD_ now ($CONFIG)"
}
config_set() {   # config_set KEY VALUE -- one line replaced or added; a value load_env would refuse is refused first
    case $2 in *[';`$()|&<>']*) printf 'spark-shell: %s=%s cannot be kept: a value holds none of ; ` $ ( ) | & < >\n' "$1" "$2" >&2; exit 1 ;; esac
    [ "$(printf '%s' "$2" | tr -d '\001-\037\177')" = "$2" ] || { printf 'spark-shell: %s cannot be kept: a value holds no control character, a new line included\n' "$1" >&2; exit 1; }   # a new line would be a second line of the config
    case $1 in
        FONT) font_ok "$2" || { printf 'spark-shell: FONT=%s cannot be kept: letters, digits, spaces and : = . + _ -\n' "$2" >&2; exit 1; } ;;
        WALLPAPER) wall_value_ok "$2" || { printf 'spark-shell: WALLPAPER=%s cannot be kept: %s\n' "$2" "$PATH_SAID" >&2; exit 1; } ;;
    esac
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CONFIG" ] && grep -q "^$1=" "$CONFIG"; then
        sed "s|^$1=.*|$1=$(esc "$2")|" "$CONFIG" > "$TMP/config"
        cp "$TMP/config" "$CONFIG"
    else
        [ -f "$CONFIG" ] || printf '# spark-shell config -- KEY=value (config.example shows the keys)\n' > "$CONFIG"
        printf '%s=%s\n' "$1" "$2" >> "$CONFIG"
    fi
    row ok config "$1=$2 ($CONFIG)"
}

THEME_KEYS="THEME_BG THEME_FG THEME_ACCENT THEME_MUTED THEME_ANSI_0 THEME_ANSI_1 THEME_ANSI_2 THEME_ANSI_3 THEME_ANSI_4 THEME_ANSI_5 THEME_ANSI_6 THEME_ANSI_7 THEME_ANSI_8 THEME_ANSI_9 THEME_ANSI_10 THEME_ANSI_11 THEME_ANSI_12 THEME_ANSI_13 THEME_ANSI_14 THEME_ANSI_15"

