# shellcheck extended-analysis=false
# --------------------------------------------------------------- renders
# sets: DESKTOP_RENDERED RENDERED USER_DIRS USER_DIRS_ROLES
# reads: CONFIG_DIR HEX_KEYS MODE NEON NEON_OLD NL OS PANEL_KEYS POINTER_DIR POINTER_KEYS POINTER_SEEN POINTER_THEMES REPO SCREENS_CONF SLOT_KEYS STATE_DIR TAB TERM_CONFIG_REL TERM_DIALOG_REL TERM_NAME THEME_KEYS TMP WALL_COVER WALL_KEYS WIN_KEYS WM_CONFIG_REL WM_NAME
# a symlink for a file used as-is, a rendered file where a value is baked
# in. A file marked `rendered by spark-shell` is ours to render again; any
# other is yours and moves to <path>.bak. The first .bak stays for off; a
# later one goes beside it by its time, and a copy of one kept is dropped
changes=0
backup() {
    changes=$((changes + 1))
    if [ "$MODE" = dry ]; then row would "back up" "$1"; return; fi
    _bk=$1.bak
    if [ -e "$_bk" ] || [ -L "$_bk" ]; then
        for _bo in "$_bk" "$_bk".*; do
            [ -f "$1" ] && [ ! -L "$1" ] && [ -f "$_bo" ] && [ ! -L "$_bo" ] && cmp -s "$1" "$_bo" || continue
            rm -f "$1"; row "back" "up" "$1 -- kept already, as $_bo"; return
        done
        _bs=$1.bak.$(date +%Y%m%d%H%M%S); _bk=$_bs; _bn=1
        while [ -e "$_bk" ] || [ -L "$_bk" ]; do _bk=$_bs.$_bn; _bn=$((_bn + 1)); done
    fi
    mv "$1" "$_bk"
    row "back" "up" "$1 -> $_bk"
}
link_one() {   # link_one SRC DST
    if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then ok rc "$2"; return; fi
    if [ -e "$2" ] && [ ! -L "$2" ]; then backup "$2"
    elif [ -L "$2" ]; then case $(readlink "$2") in "$REPO"/*) ;; *) backup "$2" ;; esac; fi
    changes=$((changes + 1))
    if [ "$MODE" = dry ]; then row would rc "$2"; return; fi
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
    row link rc "$2"
}
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
bar_mode() { if [ "$DESKTOP_BAR" = yes ]; then echo dock; else echo invisible; fi; }   # sway bar mode: shown, or there but never drawn
bar_tray_output() { if [ "$BAR_TRAY" = yes ]; then echo '*'; else echo none; fi; }   # sway's tray_output: every screen's bar, or none
bar_place() { if [ "$DESKTOP_BAR" != yes ]; then echo hidden; else echo "$BAR_POSITION"; fi; }   # -> top, bottom or hidden: the one place the bar's section and its verb say
bar_place_words() { case $1 in top) echo 'at the top of the screen' ;; bottom) echo 'at the bottom of the screen' ;; *) echo hidden ;; esac; }
bar_font() {   # bar_font [SPEC] -- foot's FONT ("Face:size=N", or :pixelsize=N) in pango's words: "Face N", "Face Npx"; no size, 12
    _bf=${1:-$FONT}; face=${_bf%%:*}; opts=""; case $_bf in *:*) opts=${_bf#*:} ;; esac
    size=$(printf '%s' "$opts" | tr ':' '\n' | sed -n 's/^size=\([0-9.]*\)$/\1/p' | head -1)
    px=$(printf '%s' "$opts" | tr ':' '\n' | sed -n 's/^pixelsize=\([0-9.]*\)$/\1/p' | head -1)
    if [ -n "$size" ]; then printf '%s %s' "$face" "$size"; elif [ -n "$px" ]; then printf '%s %spx' "$face" "$px"; else printf '%s 12' "$face"; fi
}
# BAR_TEXT auto: the text size, larger on a screen over 1080 rows by the square root of its rows
# over 1080 (1440: 15%, 2160: 41%); the shortest screen decides. Outside a running sway it is the
# text size, and the bar's loop puts the screen's size on it once it runs
bar_line_font() {   # bar_line_font [SPEC] -- the bar's font in pango's words: FONT's face at BAR_TEXT's size (points), or at auto's
    _blf=$(bar_font "${1:-$(font_spec)}"); _bls=${_blf##* }; _blf=${_blf% *}; _blu=''
    case $_bls in *px) _blu=px; _bls=${_bls%px} ;; esac
    case ${BAR_TEXT:-auto} in auto) _bls=$(bar_auto_size "$_bls" "$(bar_screen_rows)") ;; *) _bls=$BAR_TEXT; _blu='' ;; esac
    printf '%s %s%s' "$_blf" "$_bls" "$_blu"
}
bar_auto_size() {   # bar_auto_size SIZE ROWS -> SIZE as it is for 1080 rows or fewer (or none known), else SIZE times the square root of ROWS/1080, whole, 40 at most
    case $2 in ''|*[!0-9]*) printf '%s' "$1"; return 0 ;; esac
    [ "$2" -gt 1080 ] || { printf '%s' "$1"; return 0; }
    awk -v n="$1" -v h="$2" 'BEGIN { s = int(n * sqrt(h / 1080) + 0.5); if (s > 40) s = 40; if (s < n) s = n; print s }'
}
bar_screen_rows() {   # -> the rows of the shortest screen on, its shorter side after sway's scale, from a running sway; nothing outside one
    wm_live && wm_here && command -v jq >/dev/null 2>&1 || return 0
    wm_outputs | jq -r '[.[] | select(.active) | [.rect.width, .rect.height] | min] | min // empty' 2>/dev/null || :
}
render_expr() {   # -> the sed script that renders a template, one s command a line: BSD sed reads a -e script of 2048 bytes at most, and the idle watcher line alone passed it
    e="s|@HOME@|$(esc "$HOME")|g${NL}s|@USER@|$(esc "$(id -un)")|g${NL}s|@NAME@|$(esc "$(short_host)")|g${NL}s|@REPO@|$(esc "$REPO")|g"
    for k in $THEME_KEYS; do
        eval "v=\$$k"
        # shellcheck disable=SC2154   # v is set by the eval above
        e="$e${NL}s|@$k@|$(esc "$v")|g"
    done
    for k in $SLOT_KEYS $HEX_KEYS $WALL_KEYS $PANEL_KEYS $WIN_KEYS $POINTER_KEYS; do
        eval "v=\$$k"
        e="$e${NL}s|@$k@|$(esc "$v")|g"
    done
    _fs=$(font_spec)   # FONT as foot can draw it: the old face until Monaspace Neon is installed
    # foot's font is a list: a glyph Neon lacks (U+2304) comes from DejaVu Sans Mono before
    # fontconfig's own list, whose first is the proportional DejaVu Sans
    case $_fs in "$NEON"|"$NEON":*|'Monaspace '*) _ff="$_fs,$NEON_OLD${_fs#"${_fs%%:*}"}" ;; *) _ff=$_fs ;; esac   # each of the curated faces, as Neon
    e="$e${NL}s|@FONT@|$(esc "$_ff")|g"
    e="$e${NL}s|@BAND_GLYPHS@|$(esc "$(winpad_buttons)")|g${NL}s|@BAND_TERM_GLYPHS@|$(esc "$(winpad_buttons)$(winpad_mic)")|g"
    e="$e${NL}s|@BAR_MODE@|$(bar_mode)|g${NL}s|@BAR_FONT@|$(esc "$(bar_font "$_fs")")|g${NL}s|@BAR_LINE_FONT@|$(esc "$(bar_line_font "$_fs")")|g"
    e="$e${NL}s|@BAR_POSITION@|$BAR_POSITION|g${NL}s|@BAR_TRAY@|$(bar_tray_output)|g${NL}s|@NOTIFY_ANCHOR@|$(notify_anchor)|g"
    e="$e${NL}s|@FOOT_COLORS@|$(term_colors_section)|g"
    if desktop_wanted; then e="$e${NL}s|@LAYOUT_SLOTS@|yes|g"; else e="$e${NL}s|@LAYOUT_SLOTS@|no|g"; fi   # sgr.sh: the five slots in foot only where the desktop's foot.ini sets them
    e="$e${NL}s|@SCREENS_CONF@|$(esc "$SCREENS_CONF")|g${NL}s|@IDLE_EXEC@|$(esc "$(idle_exec)")|g${NL}s|@KB_LAYOUT@|$(esc "$(kb_line layout)")|g${NL}s|@KB_VARIANT@|$(esc "$(kb_line variant)")|g"
    for k in POINTER_TAP POINTER_SCROLL POINTER_SPEED KEY_REPEAT_DELAY KEY_REPEAT_RATE; do
        eval "v=\$$k"
        case $v in on) v=enabled ;; off) v=disabled ;; esac
        e="$e${NL}s|@$k@|$(esc "$v")|g"
    done
    e="$e${NL}s|@KEY_CAPS@|$(input_caps "$KEY_CAPS")|g"
    printf '%s' "$e"
}
render_sed() { printf '%s\n' "$1" > "$TMP/render.sed"; sed -f "$TMP/render.sed" "$2"; }   # render_sed SCRIPT SRC -> SRC through the script, from a file (never one -e line)
render_tmp() {   # render_tmp SRC DST -- the template through EXPR, every placeholder gone
    render_sed "$EXPR" "$1" > "$2"
    case $1 in "$(wm_config_template)") python3 "$REPO/lib/home.py" render "$2" || exit 1 ;; esac
    if grep -q '@[A-Z_0-9]*@' "$2"; then
        printf 'spark-shell: %s: unrendered placeholder: %s\n' "$1" "$(grep -o '@[A-Z_0-9]*@' "$2" | head -1)" >&2
        exit 1
    fi
}
# a render changed by hand: each render's checksum is kept in the state; a file of ours that no
# longer matches was edited since, and is kept as .bak before the new render
render_sum() { { cksum < "$1"; } 2>/dev/null | awk '{ print $1 "-" $2 }'; }   # render_sum FILE -> its checksum and size
render_by_hand() {   # render_by_hand DST -> true when DST is a render whose kept checksum it no longer has
    [ -f "$STATE_DIR/renders" ] || return 1
    _rbh=$(awk -F '\t' -v p="$1" '$1 == p { s = $2 } END { print s }' "$STATE_DIR/renders")
    [ -n "$_rbh" ] && [ "$_rbh" != "$(render_sum "$1")" ]
}
render_sum_keep() {   # render_sum_keep DST -- its checksum now, in place of the one kept before
    [ "$MODE" != dry ] || return 0
    _rsk=$(render_sum "$1")
    ! grep -qxF "$1$TAB$_rsk" "$STATE_DIR/renders" 2>/dev/null || return 0
    mkdir_private "$STATE_DIR"
    { [ ! -f "$STATE_DIR/renders" ] || awk -F '\t' -v p="$1" '$1 != p' "$STATE_DIR/renders"; printf '%s\t%s\n' "$1" "$_rsk"; } > "$TMP/renders" \
        && cp "$TMP/renders" "$STATE_DIR/renders" && chmod 0600 "$STATE_DIR/renders"
}
render_one() {   # render_one SRC DST -- EXPR must be set
    render_tmp "$1" "$TMP/render"
    if [ -f "$2" ] && [ ! -L "$2" ] && cmp -s "$TMP/render" "$2"; then ok look "$2"; render_sum_keep "$2"; return; fi
    if [ -f "$2" ] && [ ! -L "$2" ] && { ! grep -q 'rendered by spark-shell' "$2" || render_by_hand "$2"; }; then backup "$2"; fi
    changes=$((changes + 1))
    if [ "$MODE" = dry ]; then row would look "$2"; return; fi
    mkdir -p "$(dirname "$2")"
    rm -f "$2"
    cp "$TMP/render" "$2"
    chmod 0644 "$2"
    render_sum_keep "$2"
    row render look "$2"
}

# what on renders and off hands back; sgr.sh is the prompt's color, sourced by the rc files
RENDERED=".tmux.conf .config/btop/btop.conf .config/spark-shell/sgr.sh"
rc_files() { if [ "$OS" = Darwin ]; then echo ".zshrc .zprofile"; else echo ".bashrc .bash_profile"; fi; }
rc_tree() { if [ "$OS" = Darwin ]; then echo "$REPO/template/macos"; else echo "$REPO/template/linux"; fi; }
# the desktop's renders, only with DESKTOP=sway on Linux; off hands them
# back whatever the config says
DESKTOP_RENDERED="$TERM_CONFIG_REL $TERM_DIALOG_REL $WM_CONFIG_REL .local/share/applications/spark-shell-tmux.desktop .config/fontconfig/conf.d/50-spark-shell.conf .config/mako/config .config/xdg-desktop-portal/sway-portals.conf"   # fontconfig: the wifi bars' family, unhinted; mako: the notifications
desktop_na() {   # -> why this machine has no desktop of spark-shell's, or nothing: macOS draws its own, WSL has no seat and Windows draws it
    if [ "$OS" = Darwin ]; then echo "not on macOS, which has its own desktop"; elif is_wsl; then echo "not on WSL, where Windows draws the desktop"; fi
}
login_na() { if [ "$OS" = Darwin ]; then echo "not on macOS, which has its own login screen"; elif is_wsl; then echo "not on WSL, which has no tty1 for a login screen"; fi; }   # -> why no login screen here, or nothing
desktop_wanted() { [ -z "$(desktop_na)" ] && [ "$DESKTOP" = sway ]; }
desktop_tools() {   # -> the missing ones, if any (PATH or ~/.local/bin)
    _miss=''
    for t in $WM_NAME $TERM_NAME; do
        command -v "$t" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$t" ] || _miss="$_miss $t"
    done
    printf '%s' "$_miss"
}
pointer_apply() {   # the pointer row of `on desktop`: the two spark themes drawn under ~/.local/share/icons, again when the geometry changed
    if pointer_drawn; then ok pointer "spark-white and spark-black are in $POINTER_DIR"; return 0; fi
    if ! pointer_can; then skip pointer "python3 cannot draw the spark pointer here (spark needs python3 too): sway keeps its built-in cursors"; return 0; fi
    need pointer "draw the spark pointer, spark-white and spark-black, in $POINTER_DIR" || return 0
    if python3 "$REPO/lib/pointer.py" "$POINTER_DIR" 2>"$TMP/pointer.err" && pointer_drawn; then ok pointer "spark-white and spark-black drawn in $POINTER_DIR"
    else row todo pointer "lib/pointer.py failed: $(head -1 "$TMP/pointer.err" 2>/dev/null)"; acting=0; fi
}
pointer_off() {   # the two spark themes are spark-shell's own: gone with the desktop
    _had=0
    for _t in $POINTER_THEMES; do [ ! -d "$POINTER_DIR/$_t" ] || { _had=1; [ "$MODE" = dry ] || rm -rf "${POINTER_DIR:?}/$_t"; }; done
    [ "$MODE" = dry ] || rm -f "$POINTER_SEEN"
    [ "$_had" = 0 ] || { if [ "$MODE" = dry ]; then row would pointer "spark-white and spark-black removed from $POINTER_DIR"; else row ok pointer "spark-white and spark-black removed from $POINTER_DIR"; fi; }
}
desktop_reload() {   # desktop_reload [WHY] -- a running sway reads its new config (on, on desktop: the keys may have changed), under a cover so the wallpaper never goes black; WHY, its row's words
    [ "$MODE" = dry ] && return 0
    wm_session || return 0
    [ -f "$(wm_config_file)" ] || return 0
    wm_here || return 0
    wall_cover; [ -z "$WALL_COVER" ] || sleep 0.25   # drawn before the reload stops sway's own
    wm_reload >/dev/null 2>&1 || { wall_uncover; return 0; }
    wall_uncover
    winpad_again   # the bar may have started again: a pad keeping its strip starts after it, so the new bar is not inside that strip
    # a reload gives the gaps to new workspaces only: the ones open take them now
    [ -z "${GAPS_INNER:-}" ] || { wm_cmd "gaps inner all set $GAPS_INNER" >/dev/null 2>&1; wm_cmd "gaps outer all set $GAPS_OUTER" >/dev/null 2>&1; } || :
    [ -z "${BORDER:-}" ] || wm_act "tiling" "border $BORDER" >/dev/null 2>&1 || :   # and the windows open now their border (a reload gives it to new ones only)
    layout_refit_soon   # a bar moved or another gap: the windows the keys placed take their places on the new area
    if [ -n "${1:-}" ]; then row ok "$WM_NAME" "reloaded ($1)"; else row ok "$WM_NAME" "reloaded (~/$WM_CONFIG_REL)"; fi
}
wall_missing() {   # a todo row when the picture the config names is not there: the ground instead
    if [ "$WALLPAPER" != none ] && [ "$WALLPAPER" != default ] && ! wall_color && ! wall_there; then
        row todo wallpaper "$(wall_path) is missing -- the ground instead (spark-shell theme wallpaper PATH)"
    fi
}
# the home's folders: ~/.config/user-dirs.dirs written where there is none, so a program asked for
# the downloads folder makes no ~/Downloads of its own. A missing folder is made lowercase; a
# capitalized one alone is named as it is. The desktop folder is the home
USER_DIRS=$HOME/.config/user-dirs.dirs
USER_DIRS_ROLES='DOWNLOAD:downloads PICTURES:pictures DOCUMENTS:documents MUSIC:music VIDEOS:videos'
user_dir_of() {   # user_dir_of NAME -> the folder for its role: ~/NAME, or ~/Name where that one alone is there
    _uc=$(printf '%s' "$1" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')
    if [ -d "$HOME/$1" ] || [ ! -d "$HOME/$_uc" ]; then echo "$1"; else echo "$_uc"; fi
}
user_dirs_apply() {   # on desktop: ours rendered where no file is, its folders made where missing; one of yours kept whole
    if [ -f "$USER_DIRS" ] && ! grep -q 'rendered by spark-shell' "$USER_DIRS"; then ok folders "$USER_DIRS is yours: kept as it is"; return 0; fi
    { echo '# rendered by spark-shell: the user folders (#119)'
      echo 'XDG_DESKTOP_DIR="$HOME"'
      for _ur in $USER_DIRS_ROLES; do printf 'XDG_%s_DIR="$HOME/%s"\n' "${_ur%%:*}" "$(user_dir_of "${_ur#*:}")"; done
    } > "$TMP/user-dirs"
    if [ -f "$USER_DIRS" ] && cmp -s "$TMP/user-dirs" "$USER_DIRS"; then ok folders "$USER_DIRS"; return 0; fi
    changes=$((changes + 1))
    if [ "$MODE" = dry ]; then row would folders "$USER_DIRS: the downloads, pictures, documents, music and videos folders named"; return 0; fi
    for _ur in $USER_DIRS_ROLES; do mkdir -p "$HOME/$(user_dir_of "${_ur#*:}")"; done
    mkdir -p "$(dirname "$USER_DIRS")" && cp "$TMP/user-dirs" "$USER_DIRS" && chmod 0644 "$USER_DIRS"
    row render folders "$USER_DIRS: the downloads, pictures, documents, music and videos folders named"
}
user_dirs_off() {   # off desktop: ours goes, the folders stay (there was no file before ours); yours stays whole
    [ -f "$USER_DIRS" ] && grep -q 'rendered by spark-shell' "$USER_DIRS" || return 0
    if [ "$MODE" = dry ]; then row would folders "$USER_DIRS removed"; return 0; fi
    rm -f "$USER_DIRS"; row ok folders "$USER_DIRS removed (the folders stay)"
}
user_pictures() {   # -> the pictures folder the file names under your home (~/pictures, ~/Pictures), else ~/pictures: a screenshot's
    _up=$(sed -n 's|^XDG_PICTURES_DIR="\$HOME/\([A-Za-z0-9._ -]*\)"$|\1|p' "$USER_DIRS" 2>/dev/null | head -1)
    case $_up in ''|.*|*/*) echo "$HOME/pictures" ;; *) echo "$HOME/$_up" ;; esac
}
desktop_files() {   # the desktop's renders: foot's, the dialog's, sway's, the tmux entry, mako's, the screens' file, the home's folders; a mako that runs reads its new file
    _mk=$({ cksum < "$HOME/.config/mako/config"; } 2>/dev/null || :)
    for rel in $DESKTOP_RENDERED; do
        render_one "$REPO/template/$rel" "$HOME/$rel"
    done
    user_dirs_apply
    [ "$MODE" = dry ] || mkdir -p "$(wm_config_file).d"   # your own sway lines: the config reads the folder last
    [ "$MODE" = dry ] || [ -f "$SCREENS_CONF" ] || { mkdir -p "$CONFIG_DIR" && echo '# rendered by spark-shell: the screens, as spark-shell desktop screen set them' > "$SCREENS_CONF"; }   # the template includes it
    [ "$MODE" = dry ] || [ "$({ cksum < "$HOME/.config/mako/config"; } 2>/dev/null || :)" = "$_mk" ] || notify_reload   # a new look reaches the next notification, with no login
}
desktop_look_apply() {   # on and on desktop: the renders, the pointer, and a running sway reloaded when its file changed (its keys may have)
    wall_missing
    wall_follow   # a shipped drawing under a palette not its own: drawn in that palette first, so the render names the picture
    _sc=$({ cksum < "$(wm_config_file)"; } 2>/dev/null || :)
    desktop_files
    pointer_apply
    if [ "$({ cksum < "$(wm_config_file)"; } 2>/dev/null || :)" != "$_sc" ]; then desktop_reload
    elif bar_stale; then desktop_reload "the bar starts again on this spark-shell"; fi   # after an update the bar still ran the old code until a logout: a reload starts it on the new
    look_burst   # the open terminals take the look too: after an upgrade, the slots their new shells draw in
}
look_inputs() { printf '%s %s' "$(winpad_cmd 2>/dev/null || echo -)" "$(voice_here && echo voice || echo -)"; }   # what the titles are rendered from, beyond the look
desktop_apply() {
    _dai=$(look_inputs)
    desktop_look_apply
    seat_apply
    sound_apply
    bt_apply
    light_apply
    storage_apply
    power_apply
    dialog_install
    semantic_install
    wallpaper_install
    winpad_install
    voice_install
    [ "$(look_inputs)" = "$_dai" ] || { EXPR=$(render_expr); desktop_look_apply; }   # a component came: the titles follow
    winpad_session
    motion_row
    mcp_apply
    notify_start
}

