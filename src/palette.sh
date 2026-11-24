# shellcheck extended-analysis=false
# ------------------------------------------------------------ the palette
# sets: CONSOLE_NOW CORE_DIR KEPT_LAYOUTS KEPT_MAX LOOKS_DIR LOOK_FORMAT PALETTE_DIR PALETTE_WHY PTS_DIR THEME_TRASH VT_SYSFS WALL_CACHE WALL_COVER
# reads: ANIMATION_NAMES CONFIG_DIR CONSOLE_COLORS CONSOLE_RGB CONSOLE_UNIT FONT_FACES GLYPH_FAMILIES MODE NL OS PALETTE_MARK PATH_SAID REPO ROOT STATE_DIR TAB TERMINAL_SEEN TERM_NAME TERM_PALETTE_FORMATS THEME_ENV THEME_KEYS THEME_WORDS TMP VGA_HEX WALL_TYPES
PALETTE_DIR=$CONFIG_DIR/themes
CORE_DIR=$REPO/gallery/core
THEME_TRASH=$PALETTE_DIR/.deleted   # a theme deleted where undo is offered, for a day
PALETTE_WHY=''
# theme.env, rendered from the palette, is what spark and every render read
theme_at() {   # theme_at NAME -> _tak its kind (saved, look, yours, shipped, bundled, none), _tad its folder, _tap its palette's file, each empty where it has none; no process, for it runs over every theme. False when NAME is none
    _tak=''; _tad=''; _tap=''
    case $1 in none) _tak=none; return 0 ;; ''|.*|*[!A-Za-z0-9._-]*) return 1 ;; esac
    if [ -f "$PALETTE_DIR/$1/palette.env" ]; then _tak=saved; _tad=$PALETTE_DIR/$1; _tap=$_tad/palette.env
    elif [ -f "$LOOKS_DIR/$1/palette.env" ]; then _tak=look; _tad=$LOOKS_DIR/$1; _tap=$_tad/palette.env
    elif [ -f "$PALETTE_DIR/$1.env" ]; then _tak=yours; _tap=$PALETTE_DIR/$1.env
    else
        [ ! -f "$CORE_DIR/$1/look.env" ] || { _tak=bundled; _tad=$CORE_DIR/$1; }
        if [ -f "$REPO/gallery/theme/$1.env" ]; then _tak=shipped; _tap=$REPO/gallery/theme/$1.env
        elif [ -f "$CORE_DIR/$1/palette.env" ]; then _tap=$CORE_DIR/$1/palette.env
        elif [ "$_tak" = bundled ] && [ "${1#core-}" != "$1" ] && [ -f "$REPO/gallery/theme/${1#core-}.env" ]; then _tap=$REPO/gallery/theme/${1#core-}.env; fi   # a curated variant can reuse the stock colors under its own key
    fi
    [ -n "$_tak" ]
}
palette_file() { theme_at "$1" && [ -n "$_tap" ] && printf '%s' "$_tap"; }   # palette_file NAME -> the palette's file; false when none
theme_dir() { ! theme_at "$1" || printf '%s' "$_tad"; }   # theme_dir NAME -> its folder, or nothing
theme_kind() { ! theme_at "$1" || printf '%s\n' "$_tak"; }   # theme_kind NAME -> saved | look | yours | shipped | bundled | none, or nothing
# look.env format 1 (no FORMAT line) has FONT for FACE and TEXT_SIZE
LOOK_FORMAT=2   # a newer format is refused, not half read
theme_saved_names() {   # -> the themes kept as folders; one whose name no verb takes, and what a save of v0.166 left when killed (NAME.new), are none
    for _d in "$PALETTE_DIR"/*/; do
        _d=${_d%/}; _n=${_d##*/}
        case $_n in *[!A-Za-z0-9._-]*|*.new) continue ;; esac
        [ ! -f "$_d/palette.env" ] || printf '%s\n' "$_n"
    done | sort
}
core_theme_ids() { awk -F '\t' '{print (NF == 2 ? $2 : $1)}' "$CORE_DIR/themes.tsv"; }
theme_names() { { palette_names; theme_saved_names; core_theme_ids; } | LC_ALL=C sort -u; }
theme_label_of() {   # theme_label_of NAME -> _tal, the name it is shown by
    _tal=$1
    case $1 in
        core-*) [ ! -f "$CORE_DIR/$1/look.env" ] || _tal=${1#core-} ;;
        first-*) if [ -f "$CORE_DIR/core-${1#first-}/look.env" ] &&
            grep -qxF "$1" "$CONFIG_DIR/galleries/first-gallery.list" 2>/dev/null; then _tal=${1#first-}; fi ;;
    esac
}
theme_label() { theme_label_of "$1"; printf '%s' "$_tal"; }
theme_enum() { dirs_cached theme.enum "$(THEME_DIRS)" theme_enum_now; }   # -> the schema's enum, a|b|c
theme_enum_now() { { theme_names; echo none; } | LC_ALL=C grep -E '^[A-Za-z0-9._-]+$' | sort -u | paste -sd'|' -; }
look_get() {   # look_get DIR KEY -> the value, control characters dropped
    [ -f "$1/look.env" ] && [ -r "$1/look.env" ] || return 0
    while IFS= read -r _lgl || [ -n "$_lgl" ]; do
        case $_lgl in "$2="*) _lgl=${_lgl#*=}; case $_lgl in *[!\ -~]*) _lgl=$(printf '%s' "$_lgl" | tr -d '\001-\037\177') ;; esac; printf '%s' "$_lgl"; return 0 ;; esac
    done < "$1/look.env"
}
look_set() { env_put "$1/look.env" "$2" "$3"; }   # look_set DIR KEY VALUE -- in one step; 1 with look.env as it was
# a saved theme may come from another machine
look_ok() {   # look_ok DIR -> 0, or why and 1
    _lf=$1/look.env
    [ -f "$_lf" ] || { ! dir_there "$_lf" || { echo "its look.env is not a file"; return 1; }; return 0; }
    [ -r "$_lf" ] || { echo "its look.env cannot be read"; return 1; }
    _lb=$(grep -nEv '^[[:space:]]*(#|$)|^[A-Z_0-9]+=[^;`$()|&<>]*$' "$_lf" | head -1 | cut -d: -f1)
    [ -z "$_lb" ] || { echo "line $_lb of its look.env is not KEY=value"; return 1; }
    [ "$(LC_ALL=C tr -d '\n -~\200-\377' < "$_lf" | wc -c)" -eq 0 ] || { echo "its look.env holds a control character"; return 1; }   # counted: to grep a NUL ends the line
    _lv=$(look_get "$1" FORMAT); case $_lv in ''|1|2) ;; [1-9]|[1-9][0-9]) echo "it was made by a newer spark-shell (format $_lv, this one reads $LOOK_FORMAT) -- spark-shell update"; return 1 ;; *) echo "its FORMAT is not a number"; return 1 ;; esac
    _lv=$(look_get "$1" FONT); [ -z "$_lv" ] || font_ok "$_lv" || { echo "its FONT is not a face and a size (letters, digits, spaces and : = . + _ -)"; return 1; }
    _lv=$(look_get "$1" FACE); case $_lv in *[!a-z]*) _lv=-- ;; esac; case " $FONT_FACES " in *" ${_lv:-neon} "*) ;; *) echo "its FACE is not neon, argon, xenon, radon or krypton"; return 1 ;; esac
    _lv=$(look_get "$1" TEXT_SIZE); case $_lv in ''|[6-9]|[1-3][0-9]|40) ;; *) echo "its TEXT_SIZE is not 6 to 40"; return 1 ;; esac
    _lv=$(look_get "$1" ANIMATION); case $_lv in *[!a-z]*) _lv=-- ;; esac; case " none own $ANIMATION_NAMES " in *" ${_lv:-none} "*) ;; *) echo "its ANIMATION is not none, own or one of $(printf '%s' "$ANIMATION_NAMES" | sed 's/ /, /g')"; return 1 ;; esac
    _lv=$(look_get "$1" GALLERY); [ -z "$_lv" ] || gallery_num "$_lv" >/dev/null || { echo "its GALLERY is not a gallery release (gallery-v1, gallery-v2...)"; return 1; }
    _lv=$(look_get "$1" ALPHA); [ -z "$_lv" ] || alpha_ok "$_lv" || { echo "its ALPHA is not 0 to 1"; return 1; }
    _lv=$(look_get "$1" POINTER); pointer_ok "$_lv" || { echo "its POINTER is not a cursor theme's NAME and SIZE"; return 1; }
    _lv=$(look_get "$1" DRAWING); [ -z "$_lv" ] || wall_shipped "$_lv" || { echo "its DRAWING is not one of the drawings"; return 1; }
    _lv=$(look_get "$1" PALETTE); case $_lv in .*|*[!A-Za-z0-9._-]*) echo "its PALETTE is not a palette's name"; return 1 ;; esac
    _lv=$(look_get "$1" BAR_GLYPHS); case $_lv in ''|signs|words) ;; *) echo "its BAR_GLYPHS is not signs or words"; return 1 ;; esac
    _lv=$(look_get "$1" GLYPH_FAMILY); case $_lv in *[!a-z]*) _lv=-- ;; esac; case " $GLYPH_FAMILIES " in *" ${_lv:-stone} "*) ;; *) echo "its GLYPH_FAMILY is not stone, star or banner"; return 1 ;; esac   # BAR_WORKSPACES: any value, never read
    _lv=$(look_get "$1" WALLPAPER_MOTION); case $_lv in ''|on|off) ;; *) echo "its WALLPAPER_MOTION is not on or off"; return 1 ;; esac
    _lv=$(look_get "$1" DIALOG_ICONS); case $_lv in ''|on|off) ;; *) echo "its DIALOG_ICONS is not on or off"; return 1 ;; esac
    _lv=$(look_get "$1" DIALOG_SPACING); case $_lv in ''|none|groups|rows) ;; *) echo "its DIALOG_SPACING is not none, groups or rows"; return 1 ;; esac
    _lv=$(look_get "$1" WALLPAPER)
    case $_lv in
        '') ;;
        picture) _lp=$(look_get "$1" PICTURE)
            case $_lp in ''|.*|*/*) echo "its PICTURE is not a file name in the folder"; return 1 ;; esac
            path_ok "$1/$_lp" && [ -f "$1/$_lp" ] && [ ! -L "$1/$_lp" ] || { echo "its PICTURE is not a file of the folder's own"; return 1; }
            [ -r "$1/$_lp" ] || { echo "its $_lp cannot be read"; return 1; }
            pic_magic "$1/$_lp" || { echo "its $_lp is not a PNG, a JPEG, a WebP or a GIF"; return 1; }
            case " $WALL_TYPES " in *" $(printf '%s' "${_lp##*.}" | tr 'A-Z' 'a-z') "*) ;; *) echo "its PICTURE is not a picture ($WALL_TYPES)"; return 1 ;; esac ;;
        *) wall_value_ok "$_lv" || { echo "its WALLPAPER is not default, a drawing's name, #rrggbb or a picture's full path with $PATH_SAID"; return 1; } ;;
    esac
}
theme_usable() {   # theme_usable NAME -> 0 when it can be used (palette_render's files made), or why in one line and 1
    theme_at "$1" || { echo "no palette named $1 (spark-shell theme list)"; return 1; }
    [ -z "$_tad" ] || look_ok "$_tad" || return 1
    palette_render "$1" || { echo "$PALETTE_WHY"; return 1; }
}
# every theme here in one pass, kept until one changes: a line each, its fields a tab apart, an empty one -
#   NAME KIND LABEL FOLDER dark|light PALETTE WORDS WALLPAPER PICTURE ANIMATION, then its nine colors (palette_chip's)
theme_facts() { dirs_cached theme.facts "$(THEME_DIRS)" theme_facts_now; }
theme_facts_now() {
    theme_names | while IFS= read -r _tfn; do
        theme_at "$_tfn" && [ -n "$_tap" ] || continue
        theme_label_of "$_tfn"; printf '%s\t%s\t%s\t%s\t%s\n' "$_tfn" "$_tak" "$_tal" "${_tad:--}" "$_tap"
    done | LC_ALL=C awk -F '\t' '
        function hx(s, i) { return (index("0123456789abcdef", substr(s, i, 1)) - 1) * 16 + index("0123456789abcdef", substr(s, i + 1, 1)) - 1 }
        function plain(s) { gsub(/[\001-\037\177]/, "", s); return s == "" ? "-" : s }
        function env(file, first,   l, k) {   # KEY=value lines into v; the last of a key wins, the first in a look
            split("", v)
            while ((getline l < file) > 0) { k = l; if (!sub(/=.*/, "", k) || (first && k in v)) continue; sub(/^[^=]*=/, "", l); v[k] = l }
            close(file)
        }
        {
            env($5, 0); n = split("BG FG ACCENT ANSI_1 ANSI_2 ANSI_3 ANSI_4 ANSI_5 ANSI_6", key, " "); chips = ""
            for (i = 1; i <= n; i++) { c = v["THEME_" key[i]]; gsub(/["\r]/, "", c); chips = chips "\t" plain(c); if (i == 1) bg = tolower(c) }
            sub(/^#/, "", bg); dark = (hx(bg, 1) * 299 + hx(bg, 3) * 587 + hx(bg, 5) * 114) / 1000 < 128 ? "dark" : "light"
            if ($4 == "-") split("", v); else env($4 "/look.env", 1)
            print $1 "\t" $2 "\t" $3 "\t" $4 "\t" dark "\t" plain(v["PALETTE"]) "\t" plain(v["WORDS"]) "\t" plain(v["WALLPAPER"]) "\t" plain(v["PICTURE"]) "\t" plain(v["ANIMATION"]) chips
        }'
}
theme_saved_lines() {   # -> NAME<tab>where its colors come from<tab>its wallpaper, a line a saved theme
    theme_facts | awk -F '\t' '$2 == "saved" {
        from = $6 == "words" ? $7 : $6 == "picture" ? $9 : $6; wall = $8 == "picture" ? $9 : $8
        print $1 "\t" (from == "-" ? "palette" : from) "\t" (wall == "-" ? "default" : wall) }'
}
theme_words_of() {   # theme_words_of NAME -> its words, else NAME
    _td=$(theme_dir "$1"); _tw=''
    case $_td in "$LOOKS_DIR"/*) _tw=$(look_get "$_td" WORDS) ;; esac
    if [ -n "$_tw" ]; then printf '%s' "$_tw"; else theme_label "$1"; fi
}
# one change of the themes at a time: every verb that writes one, the config's look or the history
theme_locked() {   # theme_locked CMD ARG... -- CMD alone with the themes, what a killed change left settled first and the config read as it is now; 1 and one line when another change is not over in 20 seconds
    if [ -n "${THEME_LOCKED:-}" ] || [ "$MODE" = dry ]; then "$@"; return; fi
    mkdir_private "$STATE_DIR" 2>/dev/null || :
    locked "$STATE_DIR/theme.lock" theme 20 theme_alone "$@"
}
theme_alone() { THEME_LOCKED=1; themes_recover; config_load; "$@"; }
themes_settle() {   # what a killed change left, finished or undone; nothing while a change is under way
    [ "$MODE" != dry ] || return 0
    for _tsl in "$PALETTE_DIR"/.*.new "$PALETTE_DIR"/.*.old "$PALETTE_DIR"/.*.gone "$LOOKS_DIR"/.*.new "$LOOKS_DIR"/.*.old "$LOOKS_DIR"/.*.gone "$PALETTE_DIR"/*.new "$LOOKS_DIR"/*.new; do
        dir_there "$_tsl" || continue
        if [ -n "${THEME_LOCKED:-}" ]; then themes_recover
        else locked "$STATE_DIR/theme.lock" theme 0 themes_recover 2>/dev/null || :; fi
        return 0
    done
}
themes_recover() {   # the caller holds the themes' lock
    [ ! -d "$THEME_TRASH" ] || find "$THEME_TRASH" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf {} + 2>/dev/null || :
    for _trp in "$PALETTE_DIR" "$LOOKS_DIR"; do
        dirs_recover "$_trp" palette.env
        for _trl in "$_trp"/*.new; do   # as v0.166 and before left them: NAME.new, the only copy where NAME is not there
            [ -d "$_trl" ] && [ ! -L "$_trl" ] || continue
            _trn=$_trl; while case $_trn in *.new) true ;; *) false ;; esac; do _trn=${_trn%.new}; done
            if [ -f "$_trn/palette.env" ]; then rm -rf "$_trl"
            elif ! dir_there "$_trn" && [ -f "$_trl/palette.env" ] && [ -f "$_trl/look.env" ] && [ "$(grep -c '^THEME_[A-Z_0-9]*=#' "$_trl/palette.env")" -ge 20 ] && look_ok "$_trl" >/dev/null; then mv "$_trl" "$_trn"; fi
        done
    done
}
theme_name_free() {   # theme_name_free NAME -> 0 when a theme can be made by that name, or why not in one line and 1
    case " $THEME_WORDS " in *" $1 "*) echo "$1 is a word of spark-shell theme, so no theme can go by it"; return 1 ;; esac
    [ -z "$(theme_kind "$1")" ] || { echo "$1 is taken -- another name"; return 1; }
    ! dir_there "$PALETTE_DIR/$1" || { echo "$PALETTE_DIR/$1 is there and is no theme -- move it, or another name"; return 1; }
}
look_free() {   # look_free WORDS -> the name of a look nothing here has: the words, NAME-look where that is a theme's, NAME-2 and on after a look's
    _lfn=$(layout_name_of "$1" | cut -c1-32); _lfn=${_lfn%-}; _lfn=${_lfn:-look}; _lfb=$_lfn; _lfi=1
    case $(theme_kind "$_lfn") in look) ;; *) theme_name_free "$_lfn" >/dev/null || { _lfn=$_lfn-look; _lfb=$_lfn; } ;; esac
    while ! theme_name_free "$_lfn" >/dev/null || dir_there "$LOOKS_DIR/$_lfn"; do _lfi=$((_lfi + 1)); _lfn=$_lfb-$_lfi; done
    printf '%s' "$_lfn"
}
# a kept kind: the last ten applied, in KIND.history
LOOKS_DIR=$STATE_DIR/looks            # looks not saved
KEPT_LAYOUTS=$STATE_DIR/layouts       # layouts not saved
WALL_CACHE=$STATE_DIR/wallpapers      # DRAWING-PALETTE.svg and .png
KEPT_MAX=10
kept_hist() { printf '%s/%s.history' "$STATE_DIR" "$1"; }   # kept_hist KIND -> its file
kept_dir() { if [ "$1" = theme ]; then printf '%s' "$LOOKS_DIR"; else printf '%s' "$KEPT_LAYOUTS"; fi; }   # kept_dir KIND -> where its unsaved ones are
kept_history() {   # kept_history KIND -> "EPOCH<tab>NAME" lines, newest first, a name once; a line of another shape is none
    _khh=$(kept_hist "$1"); [ -f "$_khh" ] && [ -r "$_khh" ] || return 0
    LC_ALL=C awk -F '\t' '{ sub(/\r$/, "") } NF == 2 && $1 ~ /^[0-9]+$/ && length($1) < 12 && $2 ~ /^[A-Za-z0-9._-]+$/ && !seen[$2]++' "$_khh"
}
kept_names() { kept_history "$1" | cut -f2; }
kept_known() {   # kept_known KIND -> the history, then the unsaved ones it does not name, the newest first: one that is lost or cut short costs no look
    { kept_history "$1"; ls -t "$(kept_dir "$1")" 2>/dev/null | sed "s/^/0$TAB/"; } | LC_ALL=C awk -F '\t' '$2 ~ /^[A-Za-z0-9._-]+$/ && !seen[$2]++'
}
kept_note() {   # kept_note KIND NAME -- NAME newest; the back cursor reset; the ones past the last ten go
    mkdir_private "$STATE_DIR"
    _knk=$(kept_known "$1" | awk -F '\t' -v n="$2" '$2 != n')
    write_whole "$(kept_hist "$1")" printf '%s\n' "$(date +%s)$TAB$2" ${_knk:+"$(printf '%s\n' "$_knk" | head -n $((KEPT_MAX - 1)))"} || return 1
    rm -f "$(kept_hist "$1").back"
    for _knn in $(printf '%s\n' "$_knk" | tail -n +"$KEPT_MAX" | cut -f2); do kept_gone "$1" "$_knn"; done   # by name, never by what a reading left out
}
kept_gone() {   # kept_gone KIND NAME -- the unsaved one by that name removed; the theme in use and the one whose picture is the wallpaper stay
    _kgf=$(kept_dir "$1")/$2
    [ "$1" = theme ] && { [ "$2" = "${THEME:-}" ] || [ "${WALLPAPER#"$_kgf"/}" != "$WALLPAPER" ]; } && return 0
    ! dir_there "$_kgf" || dir_drop "$_kgf" || :
}
kept_drop() { [ ! -f "$(kept_hist "$1")" ] || write_whole "$(kept_hist "$1")" awk -F '\t' -v n="$2" '{ sub(/\r$/, "") } $2 != n' "$(kept_hist "$1")"; }   # kept_drop KIND NAME -- out of the history
kept_rename() { [ ! -f "$(kept_hist "$1")" ] || write_whole "$(kept_hist "$1")" awk -F '\t' -v OFS='\t' -v o="$2" -v n="$3" '{ sub(/\r$/, "") } $2 == o { $2 = n } 1' "$(kept_hist "$1")"; }   # kept_rename KIND OLD NEW -- in the history
kept_back() {   # kept_back KIND [NAME] -> the one before NAME in the history (the newest where it is not there); with no NAME, before the last one gone back to
    _kbf=$(kept_hist "$1").back; _kbn=${2-$(sed -n 1p "$_kbf" 2>/dev/null || :)}
    _kbl=$(kept_known "$1" | cut -f2)
    [ $# -ge 2 ] || printf '%s\n' "$_kbl" | grep -qxF -e "$_kbn" || _kbn=${_kbl%%"$NL"*}
    _kbn=$(printf '%s\n' "$_kbl" | awk -v n="$_kbn" '{ l[NR] = $0; if ($0 == n) at = NR } END { print l[at + 1] }'); [ -n "$_kbn" ] || return 1
    [ $# -ge 2 ] || { printf '%s\n' "$_kbn" > "$_kbf"; } 2>/dev/null || :
    printf '%s' "$_kbn"
}
kept_when() {   # kept_when EPOCH -> today 10:12, yesterday 18:40, monday 09:15, else 3 oct
    _kd=$(when_of "$1" %Y%m%d); _kt=$(when_of "$1" %H:%M); _now=$(date +%s)
    if [ "$_kd" = "$(date +%Y%m%d)" ]; then printf 'today %s' "$_kt"
    elif [ "$_kd" = "$(when_of $((_now - 86400)) %Y%m%d)" ]; then printf 'yesterday %s' "$_kt"
    elif [ $((_now - $1)) -lt $((6 * 86400)) ]; then printf '%s %s' "$(when_of "$1" %A | tr 'A-Z' 'a-z')" "$_kt"
    else printf '%s' "$(when_of "$1" '%e %b' | sed 's/^ *//' | tr 'A-Z' 'a-z')"; fi
}
kept_delete_ok() {   # kept_delete_ok KIND NAME -> 0 to go on; a terminal asks
    [ -t 0 ] && { : < /dev/tty; } 2>/dev/null || return 0
    printf 'delete the %s %s? [y/N] ' "$1" "$2" > /dev/tty; IFS= read -r _y < /dev/tty || _y=''
    case $_y in y|Y|yes) return 0 ;; *) echo "kept"; return 1 ;; esac
}
palette_names() { for _p in "$REPO"/gallery/theme/*.env "$PALETTE_DIR"/*.env; do [ -f "$_p" ] || continue; _n=${_p##*/}; printf '%s\n' "${_n%.env}"; done | sort -u; }
palette_get() { sed -n "s/^$2=//p" "$1" | tail -1 | tr -d '"\r'; }   # palette_get FILE KEY
PALETTE_NONE="terminal default colors"   # palette none's row
palette_darks() { dirs_cached theme.darks "$(THEME_DIRS)" palette_darks_now; }   # -> the dark palettes
palette_darks_now() { { theme_facts; palette_names; } | awk -F '\t' 'NF > 1 { dark[$1] = $5 == "dark"; next } dark[$1]'; }   # the background's luminance under half
palette_chip() {   # palette_chip NAME -> bg, fg, accent, ANSI 1 to 6; false when none
    _f=$(palette_file "$1") || return 1
    awk -F= '{ v[$1] = $2; gsub(/["\r]/, "", v[$1]) } END { printf "%s %s %s %s %s %s %s %s %s\n", v["THEME_BG"], v["THEME_FG"], v["THEME_ACCENT"], v["THEME_ANSI_1"], v["THEME_ANSI_2"], v["THEME_ANSI_3"], v["THEME_ANSI_4"], v["THEME_ANSI_5"], v["THEME_ANSI_6"] }' "$_f"
}
palette_reference() (
    _pal=$(palette_file "$1") || return 1
    _label=$(theme_label "$1"); _dir=$(theme_dir "$1"); _origin=''
    [ -z "$_dir" ] || _origin=$(look_get "$_dir" PALETTE)
    case $_origin in
        handpicked) printf '%s (handpicked)\n' "$_label"; return ;;
        words) printf '%s (from words)\n' "$_label"; return ;;
        picture) printf '%s (from wallpaper)\n' "$_label"; return ;;
    esac
    _key=${_origin:-$_label}
    case $_key in ''|.*|*[!A-Za-z0-9._-]*) _key='' ;; esac
    _stock=$REPO/gallery/theme/$_key.env
    if [ -n "$_key" ] && [ -f "$_stock" ]; then
        _name=$(sed -n '1s/^# \(.*\) -- .*/\1/p' "$_stock")
        if [ "$_pal" = "$_stock" ] || awk -F= -v keys="$THEME_KEYS" '
            {v=$2; gsub(/["\r]/,"",v); values[FILENAME,$1]=tolower(v)}
            END {n=split(keys,k," "); for(i=1;i<=n;i++) if (!((ARGV[1],k[i]) in values) ||
                values[ARGV[1],k[i]]!=values[ARGV[2],k[i]]) exit 1}' "$_stock" "$_pal"; then
            printf '%s\n' "${_name:-$_key}"; return
        elif [ -n "$_origin" ]; then printf '%s (based on %s)\n' "$_label" "${_name:-$_key}"; return; fi
    fi
    printf '%s (custom)\n' "$_label"
)
palette_export() (
    case ${2:-env} in env|"$TERM_NAME"|kitty|ghostty|alacritty) ;; *) echo "choose a palette format: $TERM_PALETTE_FORMATS" >&2; return 1 ;; esac
    TMP=$TMP/terminal-palette
    mkdir -p "$TMP" || return 1
    palette_render "$1" || { echo "$PALETTE_WHY" >&2; return 1; }
    _section=''; [ "${2:-env}" != "$TERM_NAME" ] || _section=$(term_colors_section)
    printf '# Palette reference: %s\n' "$(palette_reference "$1")"
    awk -v format="${2:-env}" -v native="$TERM_NAME" -v section="$_section" -v theme="$(theme_label "$1")" -f "$REPO/lib/terminal-palette.awk" "$TMP/theme.env"
)
console_render() {   # console_render RRGGBB... (16) -> $TMP/console-colors and $TMP/console-colors.rgb
    _esc=''; _r=''; _g=''; _b=''
    for _i in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
        rgb_of "#$1"; _esc="$_esc $_i $1"; shift
        _r="$_r,$_R"; _g="$_g,$_G"; _b="$_b,$_B"
    done
    # shellcheck disable=SC2086   # an index and a color, sixteen times
    printf '\033]P%s%s' $_esc > "$TMP/console-colors" && printf '%s\n%s\n%s\n' "${_r#,}" "${_g#,}" "${_b#,}" > "$TMP/console-colors.rgb"
}
palette_render() {   # palette_render NAME -> $TMP's three files; 1 and PALETTE_WHY when they cannot be
    if ! _f=$(palette_file "$1"); then PALETTE_WHY="no palette named $1 (spark-shell theme list)"; return 1; fi
    if [ ! -r "$_f" ]; then PALETTE_WHY="$_f cannot be read"; return 1; fi
    _prk=$(palette_lines "$1" "$_f") || { PALETTE_WHY="$_f: $_prk"; return 1; }
    # shellcheck disable=SC2046   # sixteen colors, split on purpose
    { printf '%s\n' "$_prk" > "$TMP/theme.env" && console_render $(printf '%s\n' "$_prk" | sed -n 's/^THEME_ANSI_[0-9]*=#//p' | tr 'A-F' 'a-f'); } 2>/dev/null \
        || { PALETTE_WHY="$TMP takes no file, so the palette could not be made: is the disk full?"; return 1; }
}
palette_lines() {   # palette_lines NAME FILE -> theme.env's lines, or why not in one line and 1; the last line of a key wins
    awk -v keys="$THEME_KEYS" -v name="$1" '
        index($0, "=") { k = $0; sub(/=.*/, "", k); sub(/^[^=]*=/, ""); gsub(/["\r]/, ""); v[k] = $0 }
        END {
            n = split(keys, key, " "); lines = ""
            for (i = 1; i <= n; i++) {
                if (v[key[i]] !~ /^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) { print key[i] " is not #rrggbb"; exit 1 }
                lines = lines "\n" key[i] "=" v[key[i]]
            }
            if (v["THEME_LOGO"] ~ /[^A-Za-z0-9 _.#-]/) { print "THEME_LOGO holds more than names and colors"; exit 1 }
            print "# rendered by spark-shell from the palette " name " -- spark-shell theme NAME changes it" lines (v["THEME_LOGO"] == "" ? "" : "\nTHEME_LOGO=" v["THEME_LOGO"])
        }' "$2"
}
theme_ours() { [ -f "$THEME_ENV" ] && grep -q 'rendered by spark-shell' "$THEME_ENV"; }
console_send() {   # console_send FILE -- a tty console only
    [ "${TERM:-}" = linux ] && [ -t 1 ] && console_linux || return 0
    [ "$MODE" != dry ] || return 0
    cat "$1" 2>/dev/null || return 0
    [ "$todos" -gt 0 ] || printf '\033[2J\033[H'   # a todo row stays
}
# a framebuffer console paints a new palette only into cells drawn
# after it: so the escapes go last
CONSOLE_NOW=''
console_now() { [ -z "$CONSOLE_NOW" ] || console_send "$CONSOLE_NOW"; }
root_path_ok() { case $1 in *[!A-Za-z0-9/._-]*) return 1 ;; *) return 0 ;; esac; }
unit_render() { sed -e "s|@CONSOLE_RGB@|$(esc "$CONSOLE_RGB")|g" "$REPO/template/$CONSOLE_UNIT" > "$TMP/unit"; }
palette_line() { printf "[ -f '%s' ] && setvtrgb '%s'" "$CONSOLE_RGB" "$CONSOLE_RGB"; }   # the rc.local line (runit): a plain file alone, so a pipe left there never holds the boot
VT_SYSFS=$ROOT/sys/module/vt/parameters/default_red
vt_here() { [ -r "$VT_SYSFS" ]; }                              # not a container
vt_live() { head -1 "$VT_SYSFS" 2>/dev/null || true; }         # the kernel's reds now
vt_vga_rgb() {   # -> $TMP/vga.rgb, VGA for setvtrgb
    # shellcheck disable=SC2086
    console_render $VGA_HEX; cp "$TMP/console-colors.rgb" "$TMP/vga.rgb"
}

theme_files() {   # the three files, as THEME says
    [ -n "$THEME" ] || { skip theme "THEME unset: the palette stays as it is (spark-shell theme NAME)"; return 0; }
    if [ "$THEME" = none ]; then
        if [ -f "$THEME_ENV" ] && need theme "remove $THEME_ENV (THEME=none)"; then
            rm -f "$THEME_ENV"; ok theme "none: theme.env removed, terminal default colors"
        fi
        return 0
    fi
    if [ "${PALETTE_RENDERED:-}" != "$THEME" ] && ! palette_render "$THEME"; then row todo theme "THEME=$THEME: $PALETTE_WHY"; return 0; fi
    for _f in theme.env console-colors console-colors.rgb; do
        case $_f in theme.env) _d=$THEME_ENV ;; *) _d=$CONFIG_DIR/$_f ;; esac
        if [ -f "$_d" ] && cmp -s "$TMP/$_f" "$_d"; then ok theme "$THEME ($_d)"; continue; fi
        changes=$((changes + 1))
        need theme "$THEME: write $_d" || continue
        mkdir -p "$(dirname "$_d")" 2>/dev/null && write_whole "$_d" cat "$TMP/$_f" || { write_failed theme "$THEME: $_d could not be written$(store_said)"; continue; }   # in one step: a shell that starts now reads the old palette or the new one, never an emptied file
        [ "$_f" != console-colors ] || CONSOLE_NOW=$_d
        ok theme "$THEME: $_d written"
    done
}

palette_boot() {   # the boot palette, root's; the kernel's now
    [ -n "$THEME" ] && [ "$THEME" != none ] && [ -f "$CONSOLE_RGB" ] || return 0
    if ! console_linux; then
        if [ "$OS" = Darwin ]; then skip palette "macOS has no Linux console: Terminal.app takes the palette"
        else skip palette "WSL has no console: the palette is Windows Terminal's"; fi
        return 0
    fi
    shape=$(init_shape)
    if [ "$shape" = none ]; then skip palette "no systemd or runit here: nothing sets the palette at boot"; return 0; fi
    command -v setvtrgb >/dev/null 2>&1 || { row todo palette "setvtrgb is missing: the kbd package has it (spark-shell on)"; return 0; }
    root_path_ok "$CONSOLE_RGB" || { row todo palette "$CONSOLE_RGB holds a character a root file cannot carry: the palette at boot is left alone"; return 0; }
    if [ "$shape" = systemd ]; then
        unit_render
        if cmp -s "$TMP/unit" "$ROOT/$CONSOLE_UNIT" && unit_enabled spark-shell-console.service; then
            ok palette "spark-shell-console.service sets it at boot"
        elif need palette "write /$CONSOLE_UNIT and enable it (sudo)" && root_ready palette; then
            root_put "$TMP/unit" "$ROOT/$CONSOLE_UNIT"
            root_do systemctl daemon-reload >/dev/null 2>&1 || true
            root_do systemctl enable spark-shell-console.service >/dev/null 2>&1 || true
            ok palette "spark-shell-console.service sets it at boot"
        fi
    else
        palette_line > "$TMP/line"; echo >> "$TMP/line"
        if [ "$(marked "$ROOT/etc/rc.local" "$PALETTE_MARK")" = "$(palette_line)" ]; then
            ok palette "a line in /etc/rc.local sets it at boot"
        elif need palette "add one line at the end of /etc/rc.local, before any exit 0 (sudo)" && root_ready palette; then
            { [ -f "$ROOT/etc/rc.local" ] || printf '#!/bin/sh\n'; marked_text "$ROOT/etc/rc.local" "$PALETTE_MARK" "$TMP/line" exit; } > "$TMP/rc.local"
            root_put "$TMP/rc.local" "$ROOT/etc/rc.local" 0755
            ok palette "a line in /etc/rc.local sets it at boot"
        fi
    fi
    vt_here && [ "$(vt_live)" != "$(head -1 "$CONSOLE_RGB")" ] || return 0
    need palette "setvtrgb: every console uses the palette now (sudo)" || return 0
    root_ready palette || return 0
    if root_do setvtrgb "$CONSOLE_RGB" >/dev/null 2>&1; then ok palette "every console uses the palette now"
    else row todo palette "setvtrgb failed -- the next boot sets the palette"; acting=0; fi
}

palette_off() {   # palette_off all|ours -- VGA again, the files gone
    _unit=0; [ -e "$ROOT/$CONSOLE_UNIT" ] && _unit=1
    _line=$(marked "$ROOT/etc/rc.local" "$PALETTE_MARK")
    _files=0; [ -e "$CONSOLE_COLORS" ] || [ -e "$CONSOLE_RGB" ] && _files=1
    _env=0; if [ -f "$THEME_ENV" ] && { [ "$1" = all ] || theme_ours; }; then _env=1; fi
    [ "$_unit$_files$_env" != 000 ] || [ -n "$_line" ] || return 0
    held=1
    if console_linux && { [ "$_unit" = 1 ] || [ -n "$_line" ] || [ "$_files" = 1 ]; }; then
        vt_vga_rgb
        if [ "$_unit" = 0 ] && [ -z "$_line" ]; then
            # no root file: escapes alone
            cp "$TMP/console-colors" "$TMP/vga-colors"; CONSOLE_NOW=$TMP/vga-colors
        elif [ "$MODE" = dry ]; then
            row would palette "the console's default colors again, nothing sets a palette at boot (sudo)"
        elif root_ready palette; then
            cp "$TMP/console-colors" "$TMP/vga-colors"; CONSOLE_NOW=$TMP/vga-colors
            if [ "$_unit" = 1 ]; then
                root_do systemctl disable spark-shell-console.service >/dev/null 2>&1 || true
                root_do rm -f "$ROOT/$CONSOLE_UNIT" && root_do systemctl daemon-reload >/dev/null 2>&1 || true
                [ ! -e "$ROOT/$CONSOLE_UNIT" ] || held=0
            fi
            if [ -n "$_line" ]; then
                marked_text "$ROOT/etc/rc.local" "$PALETTE_MARK" > "$TMP/rc.local"
                if [ "$(cat "$TMP/rc.local")" = '#!/bin/sh' ]; then root_do rm -f "$ROOT/etc/rc.local" || held=0   # the one spark-shell made
                else root_try "$TMP/rc.local" "$ROOT/etc/rc.local" || held=0; fi
            fi
            if command -v setvtrgb >/dev/null 2>&1 && vt_here && [ "$(vt_live)" != "$(head -1 "$TMP/vga.rgb")" ]; then
                root_do setvtrgb vga >/dev/null 2>&1 || held=0
            fi
            [ "$held" = 0 ] || row ok palette "the console's default colors are back, nothing sets a palette at boot"
        else
            held=0
        fi
    fi
    if [ "$MODE" = dry ]; then
        [ "$_env$_files" = 00 ] || row would theme "remove the palette files from ~/.config (theme.env, console-colors)"
    elif [ "$held" = 1 ]; then
        [ "$_env" = 0 ] || rm -f "$THEME_ENV"
        rm -f "$CONSOLE_COLORS" "$CONSOLE_RGB"
        [ "$_env$_files" = 00 ] || row ok theme "the palette files are removed from ~/.config (theme.env, console-colors)"
    else
        row todo theme "the palette files stay until sudo resets the console colors -- spark-shell off at a terminal"
    fi
    return 0
}

# macOS: the stamp says what Terminal.app got; imported again on change
terminal_has() { python3 "$REPO/lib/terminal.py" has-profile >/dev/null 2>&1; }
terminal_apply() {
    [ "$OS" = Darwin ] || return 0
    [ -f "$THEME_ENV" ] && [ -n "$THEME" ] && [ "$THEME" != none ] || return 0
    # shellcheck disable=SC2046   # FACE SIZE, split on purpose
    set -- $(term_font)
    _face=$1; _size=$2
    _want="$(cksum < "$THEME_ENV" | cut -d' ' -f1) $_face $_size"
    _why="Terminal.app's profile from the palette, in $_face $_size"
    if [ "$(cat "$TERMINAL_SEEN" 2>/dev/null)" = "$_want" ]; then
        if terminal_has; then ok terminal "Terminal.app's profile is the palette, in $_face $_size"; return 0; fi
        _why="Terminal.app lost the spark-shell profile: import it again, in $_face $_size"
    fi
    need terminal "$_why" || return 0
    if python3 "$REPO/lib/terminal.py" apply "$THEME_ENV" "$_face" "$_size"; then
        mkdir_private "$STATE_DIR"; printf '%s\n' "$_want" > "$TERMINAL_SEEN"
        ok terminal "Terminal.app's profile is the palette, in $_face $_size"
    else
        row todo terminal "the helper could not write Terminal.app's profile -- spark-shell on again"; acting=0
    fi
}
terminal_off() {
    [ "$OS" = Darwin ] && [ -f "$TERMINAL_SEEN" ] || return 0
    if [ "$MODE" = dry ]; then row would terminal "Terminal.app's spark-shell profile removed"; return 0; fi
    if python3 "$REPO/lib/terminal.py" remove; then
        rm -f "$TERMINAL_SEEN"; row ok terminal "Terminal.app's spark-shell profile removed, open windows keep their look"
    else
        row todo terminal "Terminal.app kept the profile: Terminal > Settings > Profiles removes it"
    fi
}

# a tmux pane is left out: tmux would keep the codes to that pane;
# tests set SPARK_SHELL_PTS_DIR
PTS_DIR=${SPARK_SHELL_PTS_DIR:-/dev/pts}
osc_render() {   # osc_render plain|foot|dialog -> $TMP/osc.KIND: OSC 4, 10, 11 and 12; 1 when it could not be written: half an escape would hold a terminal
    _o=$TMP/osc.$1; : > "$_o"
    _i=0
    while [ "$_i" -le 15 ]; do
        eval "_h=\$HEX_ANSI_$_i"
        printf '\033]4;%d;#%s\033\\' "$_i" "$_h" >> "$_o" || return 1
        _i=$((_i + 1))
    done
    [ "$1" = plain ] || printf '\033]4;16;#%s\033\\\033]4;17;#%s\033\\\033]4;18;#%s\033\\\033]4;19;#%s\033\\\033]4;20;#%s\033\\\033]4;21;#%s\033\\' "$HEX_ACCENT" "$HEX_MUTED" "$PANEL_BG" "$PANEL_HI" "$PANEL_MUTED" "$PANEL_BAND" >> "$_o" || return 1
    case $1 in
        "$TERM_NAME") _bg=$(term_osc_bg "$FOOT_ALPHA" "$HEX_BG") ;;   # foot's form: opacity in percent, then the color
        dialog) _bg="#$PANEL_BG" ;;
        *) _bg="#$HEX_BG" ;;
    esac
    printf '\033]10;#%s\033\\\033]11;%s\033\\' "$HEX_FG" "$_bg" >> "$_o" || return 1
    _c=''; if [ -n "${THEME:-}" ] && [ "$THEME" != none ] && _pf=$(palette_file "$THEME"); then _c=$(palette_get "$_pf" THEME_CURSOR); fi
    if hex_rgb "$_c" >/dev/null; then printf '\033]12;%s\033\\' "$(printf '%s' "$_c" | tr 'A-F' 'a-f')" >> "$_o"
    else printf '\033]112\033\\' >> "$_o"; fi   # 112: the terminal's own cursor color
}
pts_mine() {   # -> yours, writable, not a tmux pane
    _me=$(id -u)
    _panes=''
    if command -v tmux >/dev/null 2>&1; then _panes=$(tmux list-panes -a -F '#{pane_tty}' 2>/dev/null || true); fi
    for _p in "$PTS_DIR"/*; do
        case ${_p##*/} in ''|*[!0-9]*) continue ;; esac   # N only: never ptmx
        [ -w "$_p" ] || continue
        [ "$(ls -lLdn "$_p" 2>/dev/null | awk '{print $3}')" = "$_me" ] || continue
        if printf '%s\n' "$_panes" | grep -qxF -- "$_p"; then continue; fi
        printf '%s\n' "$_p"
    done
}
pts_write() {   # pts_write PTY FILE -- 2 seconds: a stopped terminal cannot hang it
    if command -v timeout >/dev/null 2>&1; then timeout 2 sh -c 'cat "$1" > "$2"' sh "$2" "$1" 2>/dev/null
    else cat "$2" > "$1" 2>/dev/null; fi
}
pts_kinds() {   # -> "PTY<tab>KIND" lines; KIND dialog, foot or plain
    pts_mine > "$TMP/pts"
    [ -s "$TMP/pts" ] || return 0
    _fk=plain; ! desktop_wanted || _fk=$TERM_NAME
    ps -eo pid=,ppid=,tty=,comm= > "$TMP/ps" 2>/dev/null || : > "$TMP/ps"
    awk -v d="$PTS_DIR" -v fk="$_fk" -v tn="$TERM_NAME" 'NR == FNR { pp[$1] = $2; cm[$1] = $4; next }
        $3 ~ /^pts\/[0-9]+$/ { t = d "/" substr($3, 5)
            if ($4 == "spark-dialog") { k[t] = "dialog"; next }
            if (t in k) next
            p = $2; n = 0   # up the parents: a process under foot is in a window of the desktop, however deep (a shell in a shell, sudo)
            while (p != "" && p > 1 && n < 16) { if (cm[p] == tn) { k[t] = fk; break }; p = pp[p]; n++ } }
        END { while ((getline l < pts) > 0) printf "%s\t%s\n", l, (l in k) ? k[l] : "plain" }' pts="$TMP/pts" "$TMP/ps" "$TMP/ps"
}
look_terms() {   # look_terms prepare|send -- send writes all at once; _painted counts the takers
    case $1 in
        prepare)
            : > "$TMP/pts.todo"
            [ "$MODE" = apply ] && [ "$OS" != Darwin ] && [ -d "$PTS_DIR" ] || return 0
            { pts_kinds > "$TMP/pts.todo"; } 2>/dev/null || { : > "$TMP/pts.todo"; return 0; }
            for _k in plain $TERM_NAME dialog; do ! grep -q "$TAB$_k\$" "$TMP/pts.todo" || osc_render "$_k" 2>/dev/null || { : > "$TMP/pts.todo"; return 0; }; done ;;
        send)
            _painted=0; _pids=''
            [ -s "$TMP/pts.todo" ] || return 0
            while IFS="$TAB" read -r _p _k; do
                pts_write "$_p" "$TMP/osc.$_k" & _pids="$_pids $!"   # a terminal that hangs holds no other
            done < "$TMP/pts.todo"
            for _lw in $_pids; do if wait "$_lw"; then _painted=$((_painted + 1)); fi; done ;;   # not _w: the caller's _w is in use
    esac
}
# the compositor stops its background before the new one draws, 100 ms of black;
# ours covers that and goes once sway's own has drawn
WALL_COVER=''
wall_cover() {   # WALL_BG on top, now
    WALL_COVER=''
    [ "$MODE" = apply ] && wm_session && [ -n "${WAYLAND_DISPLAY:-}" ] && wm_background_here || return 0
    case $WALL_BG in
        *' solid_color') set -- -c "${WALL_BG% solid_color}" ;;
        *) _wp=${WALL_BG% fill}; _wp=${_wp#\"}; _wp=${_wp%\"}; set -- -i "$_wp" -m fill ;;
    esac
    wm_background "$@" >/dev/null 2>&1 </dev/null & WALL_COVER=$!   # it draws in 100 to 200 ms
}
wall_uncover() {   # wall_uncover [WALL_BG] -- sway's under ours, then ours goes
    [ -n "$WALL_COVER" ] || return 0
    ( sleep 0.25; [ -z "${1:-}" ] || wm_send "output * bg $1" >/dev/null 2>&1; sleep 0.6; kill "$WALL_COVER" 2>/dev/null ) >/dev/null 2>&1 </dev/null &
    WALL_COVER=''
}
wall_shown() { sed -n 's/^output \* bg //p' "$(wm_config_file)" 2>/dev/null | head -1; }   # -> the config's wallpaper
desktop_live_cmd() {   # -> one compositor command; not the wallpaper
    wm_session && wm_here || return 0
    _c="client.focused #$HEX_ACCENT #$HEX_ACCENT #$PANEL_INK #$HEX_ACCENT #$HEX_ACCENT; client.focused_inactive #$PANEL_LOW #$PANEL_LOW #$HEX_MUTED #$PANEL_LOW #$PANEL_LOW"   # the indicator: the frame's own color, so the frame is one line on every side
    _c="$_c; client.unfocused #$PANEL_LOW #$PANEL_LOW #$HEX_MUTED #$PANEL_LOW #$PANEL_LOW; client.urgent #$HEX_ANSI_1 #$HEX_ANSI_1 #$PANEL_INK_URGENT #$HEX_ANSI_1 #$HEX_ANSI_1"
    _c="$_c; font pango:$(bar_line_font "$(font_spec)"); $(pointer_fresh)seat * xcursor_theme $POINTER_NAME $POINTER_SIZE; gaps inner all set $GAPS_INNER; gaps outer all set $GAPS_OUTER; [tiling] border $BORDER"
    _b=$(wm_bar_id)
    [ -z "$_b" ] || _c="$_c; bar $_b mode $(bar_mode); bar $_b font pango:$(bar_line_font "$(font_spec)"); bar $_b colors background #$HEX_BG$BAR_ALPHA; bar $_b colors statusline #$HEX_FG; bar $_b colors separator #$HEX_MUTED; bar $_b colors focused_workspace #$HEX_ACCENT #$HEX_ACCENT #$PANEL_INK; bar $_b colors active_workspace #$HEX_MUTED #$HEX_MUTED #$HEX_BG; bar $_b colors inactive_workspace #$HEX_BG$BAR_ALPHA #$HEX_BG$BAR_ALPHA #$HEX_MUTED; bar $_b colors urgent_workspace #$HEX_ANSI_1 #$HEX_ANSI_1 #$PANEL_INK_URGENT; bar $_b colors binding_mode #$HEX_ACCENT #$HEX_ACCENT #$PANEL_INK"
    printf '%s' "$_c"
}
theme_preview() (   # theme_preview NAME|off -- nothing written; a subshell: the caller's palette stays
    case ${1:-} in '') echo "preview takes a palette's name, or off"; exit 1 ;; esac
    MODE=apply; LOOK_PREVIEW=1
    if [ "$1" = off ]; then config_load; theme_load
    else
        [ "$1" != none ] || { echo "none has no colors to show"; exit 1; }
        palette_render "$1" || { echo "$PALETTE_WHY"; exit 1; }
        [ "$OS" = Darwin ] || [ "$DESKTOP" != sway ] || wall_yours || ! _pw=$(wall_for_palette "$1") || WALLPAPER=$_pw   # its own drawing, unless your picture is on
        for _k in $THEME_KEYS; do unset "$_k"; done
        THEME=$1; THEME_ENV=$TMP/theme.env; theme_load
    fi
    wall_follow >/dev/null 2>&1 || :
    look_burst
    # for the dialog to wear
    [ "$1" = off ] || { panel_load; jq -cn --arg f "$HEX_FG" --arg a "$HEX_ACCENT" --arg m "$PANEL_MUTED" --arg b "$PANEL_BG" --arg h "$PANEL_HI" --arg r "${HEX_ANSI_1:-}" --arg g "${HEX_ANSI_2:-}" \
        '{HEX_FG: $f, HEX_ACCENT: $a, PANEL_MUTED: $m, PANEL_BG: $b, PANEL_HI: $h, HEX_ANSI_1: $r, HEX_ANSI_2: $g}' > "$TMP/preview.palette" 2>/dev/null || :; }
    if [ "$1" = off ]; then echo "the look in use is on the screen again"; else echo "$1 on the screen"; fi
)
look_burst() {   # one frame: all made ready, then sent while the wallpaper draws
    _painted=0
    [ "$MODE" = apply ] && [ "$OS" != Darwin ] || return 0
    [ -n "${LOOK_PREVIEW:-}" ] || portal_look   # a preview leaves the apps' mode alone
    _wn=''; ! desktop_wanted || ! wm_session || [ "$WALL_BG" = "$(wall_shown)" ] || _wn=1
    look_terms prepare
    ! desktop_wanted || bar_palette || write_failed bar "the bar's colors could not be written$(store_said)"
    _sc=''; ! desktop_wanted || _sc=$(desktop_live_cmd)   # the wallpaper goes under the cover
    [ -z "$_wn" ] || wall_cover
    if [ -n "$WALL_COVER" ]; then sleep 0.09   # the new picture draws meanwhile
    elif [ -n "$_wn" ]; then _sc="$_sc; output * bg $WALL_BG"; fi   # no cover: sway's own way, black frame
    _sw=''
    if [ -n "$_sc" ]; then wm_send "$_sc" >/dev/null 2>&1 & _sw=$!; bar_redraw; fi
    look_terms send
    [ -z "$_sw" ] || wait "$_sw" 2>/dev/null || :   # the cover's background process is a child too
    [ -z "$_sc" ] || pointer_seen
    wall_uncover "$WALL_BG"
    [ -n "${LOOK_PREVIEW:-}" ] || ! desktop_wanted || motion_follow   # a preview leaves the motion alone
    [ -n "${LOOK_PREVIEW:-}" ] || ! desktop_wanted || winpad_again
}

