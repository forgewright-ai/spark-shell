# shellcheck extended-analysis=false
# --------------------------------------------------------- the console font
# sets: FACES_OTHER FONT_FACES MAC_FACES MAC_SYSTEM_FACES NEON NEON_MOVED NEON_OLD NEON_PS NEON_PS_OLD NEON_SHA256 NEON_STYLES NEON_URL NEON_VERSION NEON_WOULD
# reads: CONFIG MODE OS REPO ROOT STATE_DIR THEME_ENV TMP
# console-setup (Debian), vconsole.conf (Arch), rc.conf (Void).
console_shape() {   # -> setup | vconsole | rcconf
    console_linux || return 0
    if [ -f "$ROOT/etc/default/console-setup" ]; then echo setup
    elif [ -f "$ROOT/etc/vconsole.conf" ]; then echo vconsole
    elif [ -f "$ROOT/etc/rc.conf" ] && [ -d "$ROOT/etc/runit" ]; then echo rcconf; fi
}
font_file() { case $1 in setup) echo "$ROOT/etc/default/console-setup" ;; rcconf) echo "$ROOT/etc/rc.conf" ;; *) echo "$ROOT/etc/vconsole.conf" ;; esac; }
font_keys() { if [ "$1" = setup ]; then echo "FONTFACE FONTSIZE"; else echo FONT; fi; }
font_value() { sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$1" 2>/dev/null | head -1; }   # font_value FILE KEY
font_now() {   # font_now SHAPE -> FACE SIZE (setup) or FACE
    _ff=$(font_file "$1")
    if [ "$1" = setup ]; then printf '%s %s' "$(font_value "$_ff" FONTFACE)" "$(font_value "$_ff" FONTSIZE)"
    else font_value "$_ff" FONT; fi
}
font_want() { if [ "$1" = setup ]; then printf '%s' "$CONSOLE_FONT"; else printf '%s' "${CONSOLE_FONT%% *}"; fi; }
font_text() {   # font_text FILE LINE[|LINE] [SEP] -> FILE with each KEY or #KEY line set, else appended
    LC_ALL=C awk -v kv="$2" -v sep="${3:-=}" '
        BEGIN { n = split(kv, a, "|"); for (i = 1; i <= n; i++) { key[i] = substr(a[i], 1, index(a[i], sep) - 1) } }
        NR == FNR { for (i = 1; i <= n; i++) { if (index($0, key[i] sep) == 1) on[i] = 1; else if (!(i in off) && index($0, "#" key[i] sep) == 1) off[i] = FNR }; next }
        { for (i = 1; i <= n; i++) if ((on[i] && index($0, key[i] sep) == 1) || (!on[i] && off[i] == FNR)) { print a[i]; seen[i] = 1; next } ; print }
        END { for (i = 1; i <= n; i++) if (!seen[i]) print a[i] }' "$1" "$1"
}
font_restored() {   # font_restored FILE ORIG KEYS SEP -> FILE with ORIG's KEY lines
    LC_ALL=C awk -v keys="$3" -v sep="$4" '
        function keyof(l,   i) { for (i = 1; i <= n; i++) if (index(l, k[i] sep) == 1 || index(l, "#" k[i] sep) == 1) return k[i]; return "" }
        BEGIN { n = split(keys, k, " ") }
        NR == FNR { x = keyof($0); if (x != "") old[x, ++no[x]] = $0; next }
        { x = keyof($0); if (x == "") { print; next } ; if (used[x] < no[x]) print old[x, ++used[x]] }' "$2" "$1"
}
font_redraw() {   # font_redraw SHAPE FACE
    case $1 in
        setup) root_do setupcon --force >/dev/null 2>&1 || true ;;
        vconsole) root_do systemctl restart systemd-vconsole-setup >/dev/null 2>&1 || true ;;
        rcconf) root_do setfont "$2" >/dev/null 2>&1 || true ;;
    esac
}
font_apply() {
    if [ "$OS" = Darwin ]; then return 0; fi   # Terminal.app's profile carries it
    [ -n "$CONSOLE_FONT" ] || { skip font "CONSOLE_FONT unset: the console keeps its font"; return 0; }
    is_wsl && { skip font "WSL has no console: the font is Windows Terminal's"; return 0; }
    shape=$(console_shape)
    [ -n "$shape" ] || { row todo font "no console-setup, vconsole.conf or rc.conf here -- spark-shell font none"; return 0; }
    file=$(font_file "$shape"); face=${CONSOLE_FONT%% *}; size=${CONSOLE_FONT#* }
    if [ "$(font_now "$shape")" = "$(font_want "$shape")" ]; then ok font "$CONSOLE_FONT ($file)"; return 0; fi
    changes=$((changes + 1))
    need font "$CONSOLE_FONT in $file, the console redrawn (sudo)" || return 0
    root_ready font || return 0
    [ -e "$file.spark-shell-orig" ] || root_do cp "$file" "$file.spark-shell-orig"   # off puts it back
    case $shape in
        setup) lines="FONTFACE=\"$face\"|FONTSIZE=\"$size\"" ;;
        vconsole) lines="FONT=$face" ;;
        *) lines="FONT=\"$face\"" ;;
    esac
    font_text "$file" "$lines" > "$TMP/font"
    root_put "$TMP/font" "$file"
    font_redraw "$shape" "$face"
    if [ "$shape" = rcconf ]; then ok font "$CONSOLE_FONT ($file): the console has it now and at every boot"
    else ok font "$CONSOLE_FONT ($file)"; fi
}
font_off() {   # the font lines back from every .spark-shell-orig
    for shape in setup vconsole rcconf; do
        file=$(font_file "$shape")
        [ -e "$file.spark-shell-orig" ] || continue
        if [ "$MODE" = dry ]; then row would font "the font lines of $file back from ${file##*/}.spark-shell-orig (sudo)"; continue; fi
        root_ready font || continue
        root_read "$file.spark-shell-orig" > "$TMP/font.orig" || { row todo font "root could not read ${file##*/}.spark-shell-orig -- spark-shell off again"; continue; }
        if [ -e "$file" ]; then
            root_read "$file" > "$TMP/font.cur" || { row todo font "root could not read $file -- spark-shell off again"; continue; }
            font_restored "$TMP/font.cur" "$TMP/font.orig" "$(font_keys "$shape")" = > "$TMP/font"
        else cp "$TMP/font.orig" "$TMP/font"; fi
        root_put "$TMP/font" "$file" && root_do rm -f "$file.spark-shell-orig"
        if [ "$shape" = rcconf ]; then row ok font "the font lines of $file are back: the console's own font at the next boot"
        else font_redraw "$shape" ""; row ok font "the console's font is back as it was ($file)"; fi
    done
}

# console-setup names a face by file, <codeset>-<Face><Size>.
consolefonts_dir() { for _d in "$ROOT/usr/share/kbd/consolefonts" "$ROOT/usr/share/consolefonts"; do [ -d "$_d" ] && { printf '%s' "$_d"; return 0; }; done; return 1; }
psf_size() {   # psf_size FILE -> WxH (PSF1 or PSF2)
    case $1 in *.gz) _hd=$(gzip -dc "$1" 2>/dev/null | od -An -tu1 -N32) ;; *) _hd=$(od -An -tu1 -N32 "$1" 2>/dev/null) ;; esac
    # shellcheck disable=SC2086   # the header's bytes, one word each
    set -- $_hd
    if [ "${1:-}" = 54 ] && [ "${2:-}" = 4 ] && [ $# -ge 4 ]; then echo "8x$4"
    elif [ "${1:-}" = 114 ] && [ "${2:-}" = 181 ] && [ "${3:-}" = 74 ] && [ "${4:-}" = 134 ] && [ $# -ge 32 ]; then
        shift 24; _h=$(($1 + $2 * 256)); shift 4; echo "$(($1 + $2 * 256))x$_h"
    fi
}
console_fonts() {   # -> "FACE SIZE" lines, sorted
    _d=$(consolefonts_dir) || return 0
    if [ "$(console_shape)" = setup ]; then
        for _f in "$_d"/*; do
            printf '%s\n' "${_f##*/}" | sed -n 's/^[A-Za-z0-9]*-\([A-Za-z]*\)\([0-9][0-9x]*\)\.psfu\{0,1\}\(\.gz\)\{0,1\}$/\1 \2/p'
        done | awk '{ s = $2; if (s ~ /x/) { split(s, p, "x"); s = p[2] "x" p[1] } else s = "8x" s; print $1, s }'
    else
        for _f in "$_d"/*.psf* ; do
            [ -f "$_f" ] || continue
            _s=$(psf_size "$_f"); [ -n "$_s" ] || continue
            _n=${_f##*/}; _n=${_n%.gz}; _n=${_n%.psfu}; _n=${_n%.psf}
            printf '%s %s\n' "$_n" "$_s"
        done
    fi | sort -u
}
MAC_FACES="MonaspaceNeon-Regular Menlo-Regular Monaco SFMono-Regular Courier CourierNewPSMT AndaleMono JetBrainsMono-Regular FiraCode-Regular Hack-Regular SourceCodePro-Regular CascadiaCode-Regular UbuntuMono-Regular DejaVuSansMono IBMPlexMono"
MAC_SYSTEM_FACES="Menlo-Regular Monaco SFMono-Regular Courier CourierNewPSMT AndaleMono"
mac_face_here() {   # mac_face_here FACE; tests pin SPARK_SHELL_MAC_FONTS
    if [ -n "${SPARK_SHELL_MAC_FONTS:-}" ]; then case " $SPARK_SHELL_MAC_FONTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; fi
    case " $MAC_SYSTEM_FACES " in *" $1 "*) return 0 ;; esac
    for _d in "$HOME/Library/Fonts" /Library/Fonts; do for _x in otf ttf ttc; do [ ! -f "$_d/$1.$_x" ] || return 0; done; done
    [ -n "$(mdfind "kMDItemFonts == '$1'" 2>/dev/null | head -1)" ] && return 0
    python3 "$REPO/lib/terminal_profile.py" has-font "$1" >/dev/null 2>&1   # when Spotlight is off
}

# ---------------------------------------------------- the terminal's font
# Monaspace Neon (SIL OFL 1.1). Until it is installed FONT keeps the
# old face: fontconfig draws a missing face in a proportional one.
NEON='Monaspace Neon'                      # FONT's face
NEON_PS=MonaspaceNeon-Regular              # its PostScript name
NEON_OLD='DejaVu Sans Mono'                # FONT's old face
NEON_PS_OLD=Menlo-Regular                  # Terminal.app's default face
NEON_VERSION=1.400
NEON_URL=${SPARK_SHELL_FONT_URL:-https://github.com/githubnext/monaspace/releases/download/v1.400/monaspace-static-v1.400.zip}   # tests: a file:// zip, or none
NEON_SHA256=ab66d71be751495f679727332a3345597943bd4d7beebca03f5cde04bf994de7   # the zip's sha256 (GitHub's listing)
NEON_STYLES='Regular Bold Italic BoldItalic'   # the styles foot uses
NEON_MOVED=$STATE_DIR/font.moved           # after the move an old face is a choice
if [ "$OS" = Darwin ]; then NEON_DIR=$HOME/Library/Fonts; else NEON_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/fonts/monaspace-neon; fi
NEON_WOULD=0                               # a dry run would fetch: say the move too
neon_ours() { for _s in $NEON_STYLES; do [ -f "$NEON_DIR/MonaspaceNeon-$_s.otf" ] || return 1; done; }   # all four in NEON_DIR
neon_here() {
    neon_ours && return 0
    if [ "$OS" = Darwin ]; then [ -f "/Library/Fonts/$NEON_PS.otf" ]; return; fi
    [ ! -d "$NEON_DIR" ] || return 1   # our folder, incomplete: install again
    command -v fc-list >/dev/null 2>&1 && [ -n "$(fc-list "$NEON" family 2>/dev/null)" ]
}
neon_pkg() { for _p in $PKG_DESKTOP; do case $_p in *monaspace*) printf '%s' "$_p"; return 0 ;; esac; done; return 1; }   # -> the distro's package, after pm_detect
font_spec() {   # -> FONT as foot can draw it
    case $FONT in
        "$NEON"|"$NEON":*) neon_here || { printf '%s%s' "$NEON_OLD" "${FONT#"$NEON"}"; return 0; } ;;
        'Monaspace '*)   # not installed: Neon, else the old face
            _fsf=${FONT%%:*}
            if _fsw=$(face_word "$_fsf") && ! face_ours "$_fsw" && ! { command -v fc-list >/dev/null 2>&1 && [ -n "$(fc-list "$_fsf" family 2>/dev/null)" ]; }; then
                if neon_here; then printf '%s%s' "$NEON" "${FONT#"$_fsf"}"; else printf '%s%s' "$NEON_OLD" "${FONT#"$_fsf"}"; fi
                return 0
            fi ;;
    esac
    printf '%s' "$FONT"
}
term_font() {   # -> Terminal.app's "FACE SIZE" (13 points)
    # shellcheck disable=SC2086   # FACE SIZE, split on purpose
    set -- $CONSOLE_FONT
    if [ -n "${1:-}" ]; then printf '%s %s' "$1" "${2:-13}"
    elif neon_here; then printf '%s 13' "$NEON_PS"
    else printf '%s 13' "$NEON_PS_OLD"; fi
}
neon_unzip() {   # neon_unzip ZIP DIR (Void has no unzip)
    _nmiss=0
    if command -v unzip >/dev/null 2>&1; then
        for _s in $NEON_STYLES; do unzip -p "$1" "Static Fonts/Monaspace Neon/MonaspaceNeon-$_s.otf" > "$2/MonaspaceNeon-$_s.otf" 2>/dev/null || :; done
    fi
    for _s in $NEON_STYLES; do [ -s "$2/MonaspaceNeon-$_s.otf" ] || _nmiss=1; done
    if [ "$_nmiss" = 1 ] && command -v python3 >/dev/null 2>&1; then
        # shellcheck disable=SC2086   # the four styles, one word each
        python3 -I -c 'import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for s in sys.argv[3:]:
    n = "MonaspaceNeon-%s.otf" % s
    with open(sys.argv[2] + "/" + n, "wb") as f:
        f.write(z.read("Static Fonts/Monaspace Neon/" + n))' "$1" "$2" $NEON_STYLES >/dev/null 2>&1 || :
    fi
    for _s in $NEON_STYLES; do [ -s "$2/MonaspaceNeon-$_s.otf" ] || return 1; done
}
neon_wanted() {   # Neon, or the old face before the move
    if [ "$OS" = Darwin ]; then
        # shellcheck disable=SC2086   # FACE SIZE, split on purpose
        set -- $CONSOLE_FONT
        case ${1:-} in ''|"$NEON_PS") return 0 ;; "$NEON_PS_OLD") [ ! -e "$NEON_MOVED" ]; return ;; *) return 1 ;; esac
    fi
    case $FONT in "$NEON"|"$NEON":*) return 0 ;; "$NEON_OLD"|"$NEON_OLD":*) [ ! -e "$NEON_MOVED" ]; return ;; *) return 1 ;; esac
}
neon_install() {   # the font row of `on`
    if [ "$OS" != Darwin ] && ! desktop_wanted && ! login_wanted; then skip font "DESKTOP=none: Monaspace Neon is for foot, the desktop's terminal"; return 0; fi
    if neon_ours; then ok font "$NEON is in $NEON_DIR"; return 0; fi
    if ! neon_wanted; then
        if [ "$OS" = Darwin ]; then skip font "CONSOLE_FONT=$CONSOLE_FONT is yours: $NEON is not fetched"; else skip font "FONT=$FONT is yours: $NEON is not fetched"; fi
        return 0
    fi
    if neon_here; then ok font "$NEON is installed$(_np=$(neon_pkg) && printf ' (%s)' "$_np")"; return 0; fi
    if [ "$OS" = Darwin ]; then _nkeep="Terminal.app keeps its font"; else _nkeep="foot draws $NEON_OLD"; fi
    [ "$NEON_URL" != none ] || { skip font "no release to fetch $NEON from (SPARK_SHELL_FONT_URL=none): $_nkeep"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo font "curl is not installed, so $NEON cannot be fetched: $_nkeep -- spark-shell on desktop installs curl"; return 0; }
    need font "fetch $NEON $NEON_VERSION from GitHub (56 MB), check its sha256 and put its four faces in $NEON_DIR" || { NEON_WOULD=1; return 0; }
    _nz=$TMP/monaspace.zip; _nd=$TMP/monaspace; mkdir -p "$_nd"
    if ! curl -fsSL --proto '=https,file' --proto-redir '=https' --connect-timeout 30 -o "$_nz" "$NEON_URL" 2>/dev/null; then
        rm -f "$_nz"; row todo font "could not fetch $NEON: $_nkeep until spark-shell on fetches it"; acting=0; return 0
    fi
    if [ "$(sha256_of "$_nz")" != "$NEON_SHA256" ]; then
        rm -f "$_nz"; row todo font "the file fetched is not the $NEON $NEON_VERSION spark-shell pins: nothing installed, $_nkeep"; acting=0; return 0
    fi
    neon_unzip "$_nz" "$_nd" || { row todo font "could not open $NEON's zip (python3 or unzip): nothing installed, $_nkeep"; acting=0; return 0; }
    mkdir -p "$NEON_DIR"
    for _s in $NEON_STYLES; do
        cp "$_nd/MonaspaceNeon-$_s.otf" "$NEON_DIR/MonaspaceNeon-$_s.otf.new" && chmod 0644 "$NEON_DIR/MonaspaceNeon-$_s.otf.new" && mv -f "$NEON_DIR/MonaspaceNeon-$_s.otf.new" "$NEON_DIR/MonaspaceNeon-$_s.otf" \
            || { row todo font "could not write $NEON_DIR -- spark-shell on again"; acting=0; return 0; }
    done
    [ "$OS" = Darwin ] || ! command -v fc-cache >/dev/null 2>&1 || fc-cache -f "$NEON_DIR" >/dev/null 2>&1 || :
    ok font "$NEON $NEON_VERSION installed in $NEON_DIR, its sha256 checked"
}
neon_move() {   # once: the old face moves to Neon
    [ ! -e "$NEON_MOVED" ] || return 0
    if [ "$OS" = Darwin ]; then
        # shellcheck disable=SC2086   # FACE SIZE, split on purpose
        set -- $CONSOLE_FONT
        _nold=$NEON_PS_OLD
        if [ "${1:-}" = "$NEON_PS_OLD" ]; then _nkey=CONSOLE_FONT; _nval="$NEON_PS ${2:-13}"; else _nkey=''; fi
    else
        desktop_wanted || login_wanted || return 0
        _nwas=$(sed -n 's/^FONT=//p' "$CONFIG" 2>/dev/null | tail -1); _nwas=${_nwas#\"}; _nwas=${_nwas%\"}; _nold=$NEON_OLD
        case $_nwas in "$NEON_OLD"|"$NEON_OLD":*) _nkey=FONT; _nval="$NEON${_nwas#"$NEON_OLD"}" ;; *) _nkey='' ;; esac
    fi
    if [ -n "$_nkey" ]; then
        neon_here || [ "$NEON_WOULD" = 1 ] || return 0   # not installed: the move waits
        need font "$_nkey=$_nval, the new default face at your size ($_nold was the old one)" || return 0
        config_set "$_nkey" "$_nval" >/dev/null
        eval "$_nkey=\$_nval"; export "${_nkey?}"
        ok font "$_nkey=$_nval, the new default face at your size ($_nold was the old one)"
    fi
    [ "$MODE" = dry ] || { mkdir_private "$STATE_DIR"; printf '%s\n' "${_nkey:-nothing}${_nkey:+ moved to $_nval}" > "$NEON_MOVED"; }
}

# The five faces share Neon's cell: 2000 to the em, ascent 1890, descent
# 400, gap 200, advance 1240.
FONT_FACES='neon argon xenon radon krypton'   # in theme's order
face_name() { printf 'Monaspace %s' "$(printf '%s' "$1" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"; }   # face_name argon -> Monaspace Argon
face_word() { case $1 in 'Monaspace '*) _fw=${1#Monaspace }; case " $FONT_FACES " in *" $(printf '%s' "$_fw" | tr 'A-Z' 'a-z') "*) printf '%s' "$_fw" | tr 'A-Z' 'a-z'; return 0 ;; esac ;; esac; return 1; }   # face_word "Monaspace Argon" -> argon, or 1
face_dir() { if [ "$OS" = Darwin ]; then printf '%s' "$NEON_DIR"; else printf '%s/fonts/monaspace-%s' "${XDG_DATA_HOME:-$HOME/.local/share}" "$1"; fi; }   # face_dir argon -> its folder
face_file() { _ff=$(face_name "$1"); printf 'Monaspace%s-%s.otf' "${_ff#Monaspace }" "$2"; }   # face_file argon Bold -> MonaspaceArgon-Bold.otf
face_ours() { for _s in $NEON_STYLES; do [ -f "$(face_dir "$1")/$(face_file "$1" "$_s")" ] || return 1; done; }   # face_ours argon -> four styles in place
font_with() {   # font_with FACE SIZE -> FONT with them set, empty ones kept
    _fwf=${FONT%%:*}; _fwr=${FONT#"$_fwf"}
    [ -z "$1" ] || _fwf=$(face_name "$1")
    if [ -n "$2" ]; then case $_fwr in *size=[0-9]*) _fwr=$(printf '%s' "$_fwr" | sed "s/size=[0-9][0-9.]*/size=$2/") ;; *) _fwr="$_fwr:size=$2" ;; esac; fi
    printf '%s%s' "$_fwf" "$_fwr"
}
FACES_OTHER='argon xenon radon krypton'   # the four beside Neon
faces_ours() { for _fo in $FACES_OTHER; do face_ours "$_fo" || return 1; done; }
faces_unzip() {   # faces_unzip ZIP DIR
    for _fo in $FACES_OTHER; do
        _fn=$(face_name "$_fo")
        for _s in $NEON_STYLES; do
            _ff=$(face_file "$_fo" "$_s")
            if command -v unzip >/dev/null 2>&1; then unzip -p "$1" "Static Fonts/$_fn/$_ff" > "$2/$_ff" 2>/dev/null || :; fi
            [ -s "$2/$_ff" ] || ! command -v python3 >/dev/null 2>&1 || python3 -I -c 'import sys, zipfile
open(sys.argv[3], "wb").write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' "$1" "Static Fonts/$_fn/$_ff" "$2/$_ff" >/dev/null 2>&1 || :
            [ -s "$2/$_ff" ] || return 1
        done
    done
}
faces_install() {   # the faces row of `on`
    [ "$OS" != Darwin ] || return 0   # a Mac draws CONSOLE_FONT
    desktop_wanted || login_wanted || return 0
    face_word "${FONT%%:*}" >/dev/null || return 0   # your own FONT: nothing fetched
    if faces_ours; then ok faces "Monaspace Argon, Xenon, Radon and Krypton are in $(dirname "$(face_dir argon)")"; return 0; fi
    [ "$NEON_URL" != none ] || { skip faces "no release to fetch them from (SPARK_SHELL_FONT_URL=none): theme face takes neon alone"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo faces "curl is not installed, so Monaspace Argon, Xenon, Radon and Krypton cannot be fetched -- spark-shell on desktop installs curl"; return 0; }
    need faces "put Monaspace Argon, Xenon, Radon and Krypton, four styles each, in $(dirname "$(face_dir argon)"), from the zip the font row checks" || return 0
    _nz=$TMP/monaspace.zip; _fd=$TMP/faces; mkdir -p "$_fd"
    if [ ! -s "$_nz" ] || [ "$(sha256_of "$_nz")" != "$NEON_SHA256" ]; then   # unless the font row fetched it
        if ! curl -fsSL --proto '=https,file' --proto-redir '=https' --connect-timeout 30 -o "$_nz" "$NEON_URL" 2>/dev/null; then
            rm -f "$_nz"; row todo faces "could not fetch the faces: theme face takes neon until spark-shell on fetches them"; acting=0; return 0
        fi
        [ "$(sha256_of "$_nz")" = "$NEON_SHA256" ] || { rm -f "$_nz"; row todo faces "the file fetched is not the zip spark-shell pins: nothing installed"; acting=0; return 0; }
    fi
    faces_unzip "$_nz" "$_fd" || { row todo faces "could not open the faces in the zip (python3 or unzip): nothing installed"; acting=0; return 0; }
    for _fo in $FACES_OTHER; do
        _fdir=$(face_dir "$_fo"); mkdir -p "$_fdir"
        for _s in $NEON_STYLES; do
            _ff=$(face_file "$_fo" "$_s")
            cp "$_fd/$_ff" "$_fdir/$_ff.new" && chmod 0644 "$_fdir/$_ff.new" && mv -f "$_fdir/$_ff.new" "$_fdir/$_ff" || { row todo faces "could not write $_fdir -- spark-shell on again"; acting=0; return 0; }
        done
        ! command -v fc-cache >/dev/null 2>&1 || fc-cache -f "$_fdir" >/dev/null 2>&1 || :
    done
    ok faces "Monaspace Argon, Xenon, Radon and Krypton installed in $(dirname "$(face_dir argon)"), the zip's sha256 checked"
}


cmd_font() {   # font [FACE SIZE|list|none]
    config_load
    pm_detect
    case ${1:-show} in
        show) [ $# -le 1 ] || refuse_in font "show takes no word"; font_show; return ;;
        list) [ $# -le 1 ] || refuse_in font "list takes no word"; font_list; return ;;
        none)
            [ $# -eq 1 ] || refuse_in font "none takes no word"
            [ "$MODE" = dry ] || [ -z "$CONSOLE_FONT" ] || config_set CONSOLE_FONT ''
            CONSOLE_FONT=''
            if [ "$OS" = Darwin ]; then terminal_apply; else font_off; fi
            verb_close "The console keeps its own font."; return ;;
    esac
    [ $# -eq 2 ] || refuse_in font "a face and a size: spark-shell font FACE SIZE (spark-shell font list shows them)"
    face=$1; size=$2
    printf '%s' "$face" | grep -qE '^[A-Za-z0-9._-]+$' || refuse_in font "$face is not a font name (spark-shell font list shows them)"
    if [ "$OS" = Darwin ]; then
        printf '%s' "$size" | grep -qE '^[0-9]{1,2}(\.[0-9])?$' && [ "${size%%.*}" -ge 6 ] && [ "${size%%.*}" -le 72 ] \
            || refuse_in font "$size is not a size: points on macOS, 6 to 72 (13)"
        mac_face_here "$face" || refuse_in font "no font named $face is installed here (spark-shell font list shows them)"
    else
        is_wsl && refuse_in font "WSL has no console: the font is Windows Terminal's."
        [ -n "$(console_shape)" ] || refuse_in font "this Linux has no console-setup, vconsole.conf or rc.conf."
        printf '%s' "$size" | grep -qE '^[0-9]+x[0-9]+$' || refuse_in font "$size is not a size: WxH on the console (16x32)"
        console_fonts > "$TMP/fonts"
        if [ -s "$TMP/fonts" ]; then
            grep -q "^$face " "$TMP/fonts" || refuse_in font "no console font named $face here (spark-shell font list shows them)"
            grep -qx "$face $size" "$TMP/fonts" || refuse_in font "$face comes in $(sed -n "s/^$face //p" "$TMP/fonts" | paste -sd' ' -), not $size"
        fi
    fi
    [ "$MODE" = dry ] || [ "$CONSOLE_FONT" = "$face $size" ] || config_set CONSOLE_FONT "$face $size"
    CONSOLE_FONT="$face $size"; export CONSOLE_FONT
    if [ "$OS" = Darwin ]; then
        [ -f "$THEME_ENV" ] && [ -n "$THEME" ] && [ "$THEME" != none ] \
            || { verb_close "On a Mac the font is part of the Terminal.app profile, which spark-shell theme NAME makes."; return 0; }
        terminal_apply
    else
        font_apply
    fi
    verb_close "The console's font is $face $size."
}
font_show() {
    if [ "$OS" = Darwin ]; then
        echo "font  $(term_font): Terminal.app's profile$([ -n "$CONSOLE_FONT" ] || printf ' (the default)')"
    elif is_wsl; then echo "font  WSL has no console: the font is Windows Terminal's"
    elif [ -z "$(console_shape)" ]; then echo "font  there is no console-setup, vconsole.conf or rc.conf here"
    elif [ -z "$CONSOLE_FONT" ]; then echo "font  unset: the console keeps its font (spark-shell font list shows the faces)"
    else echo "font  $CONSOLE_FONT ($(font_file "$(console_shape)"))"; fi
}
font_list() {
    if [ "$OS" = Darwin ]; then
        echo "The monospace faces here, by PostScript name (the size is points, 13):"
        for f in $MAC_FACES; do mac_face_here "$f" && printf '  %s\n' "$f"; done
        echo "Font Book shows any other font's PostScript name."
        return 0
    fi
    is_wsl && { echo "WSL has no console: the font is Windows Terminal's."; return 0; }
    shape=$(console_shape)
    [ -n "$shape" ] || { echo "There is no console-setup, vconsole.conf or rc.conf here."; return 0; }
    console_fonts > "$TMP/fonts"
    if [ ! -s "$TMP/fonts" ]; then echo "No console fonts under /usr/share/kbd/consolefonts or /usr/share/consolefonts."; return 0; fi
    echo "The console fonts in $(consolefonts_dir), as spark-shell font takes them:"
    awk '{ s[$1] = s[$1] " " $2 } END { for (f in s) printf "  %-24s%s\n", f, s[f] }' "$TMP/fonts" | sort
    echo "spark-shell font FACE SIZE puts one in $(font_file "$shape")."
}
check_font() {
    if [ -z "$CONSOLE_FONT" ]; then chk font ok "na (CONSOLE_FONT unset: the console keeps its font)"; return; fi
    if [ "$OS" = Darwin ]; then chk font ok "$CONSOLE_FONT in Terminal.app's profile"; return; fi
    if is_wsl; then chk font ok "na (WSL has no console)"; return; fi
    shape=$(console_shape)
    if [ -z "$shape" ]; then chk font warn "no console-setup, vconsole.conf or rc.conf here" "spark-shell font none"; return; fi
    if [ "$(font_now "$shape")" = "$(font_want "$shape")" ]; then chk font ok "$CONSOLE_FONT ($(font_file "$shape"))"
    else chk font fail "$(font_file "$shape") says $(font_now "$shape")" "spark-shell on (sudo once)"; fi
}
