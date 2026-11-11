# shellcheck extended-analysis=false
# --- the gallery
# sets: GALLERY_FLOOR GALLERY_FORMAT GALLERY_GIT GALLERY_KEYS GALLERY_PICTURE_MAX GALLERY_PIXELS_MAX GALLERY_URL GALLERY_WALLS
# reads: ANIMATION_NAMES OS PALETTE_DIR PATH_REFUSED REPO STATE_DIR TAB THEME_KEYS THEME_WORDS TMP
# a release is a tag gallery-vN signed by a key in allowed-signers, read only through its
# tree's object id; one older than the floor is never taken. Data alone: no SVG, no GIF, no
# font, never code, and nothing it names runs.
GALLERY_URL=${SPARK_SHELL_GALLERY_URL:-https://github.com/forgewright-ai/spark-shell-gallery.git}   # the tests point it at a folder
GALLERY_GIT=$STATE_DIR/gallery.git
GALLERY_FLOOR=$STATE_DIR/gallery.floor
GALLERY_FORMAT=1
GALLERY_PICTURE_MAX=4194304   # bytes: 4 MiB a picture
GALLERY_PIXELS_MAX=7680x4320
GALLERY_WALLS=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/gallery   # the wallpapers installed from it
GALLERY_KEYS='FORMAT PALETTE WORDS WALLPAPER PICTURE FACE ALPHA ANIMATION GLYPH_FAMILY BAR_GLYPHS WALLPAPER_MOTION DIALOG_ICONS DIALOG_SPACING'   # what a shared theme may set: never the text size, the pointer or a file of the machine
gallery_git() { GIT_TERMINAL_PROMPT=0 git -c protocol.allow=never -c protocol.https.allow=always -c protocol.file.allow=always -c core.hooksPath=/dev/null -c transfer.fsckObjects=true -c gc.auto=0 -c maintenance.auto=false "$@"; }   # https or a folder, no prompt, no hook, every object checked; no upkeep after a fetch (it rewrote the shallow file under the next one)
gallery_said() { case $GALLERY_URL in https://github.com/forgewright-ai/spark-shell-gallery.git) echo forgewright-ai/spark-shell-gallery ;; *) printf '%s' "$GALLERY_URL" ;; esac; }
gallery_num() { case ${1#gallery-v} in [1-9]|[1-9][0-9]|[1-9][0-9][0-9]|[1-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9][0-9]) [ "${1%%v*}" = gallery- ] && printf '%s' "${1#gallery-v}" ;; *) return 1 ;; esac; }   # gallery_num gallery-vN -> N, 1 to 999999; false for any other name
gallery_signed() {   # gallery_signed TAG -> 0 when a key in allowed-signers signed TAG, it names itself and a commit, and its message says "spark-shell-gallery TAG"; GALLERY_TREE its tree's object id
    _go=$(gallery_git -C "$GALLERY_GIT" rev-parse --verify -q "refs/tags/$1" 2>/dev/null) || return 1
    case $_go in *[!0-9a-f]*|'') return 1 ;; esac
    gallery_git -C "$GALLERY_GIT" -c gpg.format=ssh -c "gpg.ssh.allowedSignersFile=$REPO/allowed-signers" -c gpg.program=false -c gpg.openpgp.program=false -c gpg.x509.program=false verify-tag "$_go" >/dev/null 2>&1 || return 1
    gallery_git -C "$GALLERY_GIT" cat-file tag "$_go" > "$TMP/gallery.tag" 2>/dev/null || return 1
    [ "$(sed -n 's/^tag //p' "$TMP/gallery.tag" | sed -n 1p)" = "$1" ] && [ "$(sed -n 's/^type //p' "$TMP/gallery.tag" | sed -n 1p)" = commit ] || return 1
    [ "$(sed -n '/^$/{n;p;q;}' "$TMP/gallery.tag")" = "spark-shell-gallery $1" ] || return 1
    GALLERY_TREE=$(gallery_git -C "$GALLERY_GIT" rev-parse --verify -q "$_go^{tree}" 2>/dev/null) || return 1
    case $GALLERY_TREE in *[!0-9a-f]*|'') return 1 ;; esac
}
gallery_fetch() {   # -> GALLERY_TAG the newest signed release, GALLERY_TREE its tree, GALLERY_SKIPPED the newer unsigned ones; the index read and the floor raised; one line and 1 when none can be had
    command -v git >/dev/null 2>&1 || { echo "git is not installed, and it fetches the gallery"; return 1; }
    command -v ssh-keygen >/dev/null 2>&1 || { echo "ssh-keygen (openssh) is not installed, and it checks the gallery's signature"; return 1; }
    [ -f "$REPO/allowed-signers" ] || { echo "no allowed-signers beside spark-shell: no key can vouch for the gallery"; return 1; }
    _gf=''; if [ -e "$GALLERY_FLOOR" ]; then _gf=$(sed -n 1p "$GALLERY_FLOOR" 2>/dev/null); gallery_num "$_gf" >/dev/null || { echo "the gallery's floor ($GALLERY_FLOOR) names no release: remove it to start over"; return 1; }; fi
    mkdir_private "$STATE_DIR"; [ -d "$GALLERY_GIT" ] || gallery_git -C "$STATE_DIR" init -q --bare "$GALLERY_GIT" >/dev/null 2>&1 || { echo "the gallery's folder could not be made: $GALLERY_GIT"; return 1; }
    gallery_git -C "$GALLERY_GIT" ls-remote --tags --refs "$GALLERY_URL" 'refs/tags/gallery-v*' > "$TMP/gallery.refs" 2>"$TMP/gallery.err" || { echo "the gallery could not be reached ($(gallery_said)): $(head -1 "$TMP/gallery.err" | tr -d '\001-\037\177' | cut -c1-120)"; return 1; }
    GALLERY_TAG=''; GALLERY_TREE=''; GALLERY_SKIPPED=''
    for _gn in $(sed -n 's|^[0-9a-f]*[[:space:]]*refs/tags/gallery-v\([1-9][0-9]\{0,5\}\)$|\1|p' "$TMP/gallery.refs" | sort -rn | head -20); do   # newest first
        gallery_git -C "$GALLERY_GIT" fetch -q --depth 1 --no-tags "$GALLERY_URL" "+refs/tags/gallery-v$_gn:refs/tags/gallery-v$_gn" >/dev/null 2>"$TMP/gallery.err" || { echo "the gallery's gallery-v$_gn could not be fetched: $(head -1 "$TMP/gallery.err" | tr -d '\001-\037\177' | cut -c1-120)"; return 1; }
        if gallery_signed "gallery-v$_gn"; then GALLERY_TAG=gallery-v$_gn; break; fi
        GALLERY_SKIPPED="$GALLERY_SKIPPED gallery-v$_gn"
    done
    [ -n "$GALLERY_TAG" ] || { echo "the gallery ($(gallery_said)) has no release a key in allowed-signers signed${GALLERY_SKIPPED:+:$GALLERY_SKIPPED}"; return 1; }
    [ -z "$_gf" ] || [ "$(gallery_num "$GALLERY_TAG")" -ge "$(gallery_num "$_gf")" ] || { echo "the gallery offers $GALLERY_TAG, older than the $_gf seen before: not taken"; return 1; }
    gallery_index || return 1
    [ "$GALLERY_TAG" = "$_gf" ] || { printf '%s\n' "$GALLERY_TAG" > "$GALLERY_FLOOR.new" && mv "$GALLERY_FLOOR.new" "$GALLERY_FLOOR"; }   # raised once the release holds
}
gallery_index() {   # -> $TMP/gallery.index: GALLERY_TAG's index.tsv past its format line, each line KIND NAME PATH BYTES SHA256; one line and 1 when it is not
    gallery_blob index.tsv 262144 "$TMP/gallery.index.tsv" || return 1
    [ "$(sed -n 1p "$TMP/gallery.index.tsv")" = "# spark-shell gallery $GALLERY_FORMAT" ] || { echo "the gallery's $GALLERY_TAG is of another format than this spark-shell reads -- spark-shell update"; return 1; }
    sed 1d "$TMP/gallery.index.tsv" > "$TMP/gallery.index"
    _gb=$(awk -F '\t' -v max="$GALLERY_PICTURE_MAX" '
        function bad(why) { print NR + 1 ": " why; exit }
        NF != 5 { bad("not five fields") }
        $1 != "theme" && $1 != "wallpaper" { bad("no such kind") }
        $2 !~ /^[a-z][a-z0-9-]*$/ || length($2) > 40 { bad("not a name") }
        $1 == "theme" && $3 !~ ("^themes/" $2 "/(look\\.env|palette\\.env|[A-Za-z0-9][A-Za-z0-9_-]*\\.(png|jpg|jpeg))$") { bad("not a theme file") }
        $1 == "wallpaper" && $3 !~ ("^wallpapers/" $2 "\\.(png|jpg|jpeg)$") { bad("not a wallpaper file") }
        length($3) > 120 || $4 !~ /^(0|[1-9][0-9]*)$/ || length($4) > 8 || $4 + 0 > max || $5 !~ /^[0-9a-f]+$/ || length($5) != 64 { bad("not a size and a sha256") }
        seen[$3]++ { bad("a file named twice") }
        kind[$2] != "" && kind[$2] != $1 { bad("a theme and a wallpaper of one name") }
        { kind[$2] = $1; n[$2]++; z[$2] += $4 }
        ($1 == "theme" && n[$2] > 3) || ($1 == "wallpaper" && n[$2] > 1) { bad("more files than its kind holds") }
        z[$2] > max + 16384 { bad("more bytes than its kind holds") }' "$TMP/gallery.index")
    [ -z "$_gb" ] || { echo "the gallery's index is not as its format says (line $_gb)"; return 1; }
}
gallery_blob() {   # gallery_blob PATH MAX OUT -> the plain file at PATH in GALLERY_TREE in OUT, MAX bytes at most; one line and 1 when not
    _gl=$(gallery_git -C "$GALLERY_GIT" ls-tree "$GALLERY_TREE" -- "$1" 2>/dev/null)
    case $_gl in "100644 blob "*) ;; '') echo "the gallery's $GALLERY_TAG has no $1"; return 1 ;; *) echo "$1 is not a plain file in the gallery"; return 1 ;; esac
    _gs=$(gallery_git -C "$GALLERY_GIT" cat-file -s "$GALLERY_TREE:$1" 2>/dev/null) && [ "$_gs" -le "$2" ] || { echo "$1 in the gallery is over $2 bytes"; return 1; }
    gallery_git -C "$GALLERY_GIT" cat-file blob "$GALLERY_TREE:$1" > "$3" 2>/dev/null || { echo "$1 could not be read from the gallery"; return 1; }
}
gallery_take() {   # gallery_take NAME DIR -> the entry's files in DIR, each checked against its index line; GALLERY_KIND theme or wallpaper; one line and 1 when one is not
    awk -F '\t' -v n="$1" '$2 == n' "$TMP/gallery.index" > "$TMP/gallery.entry"
    [ -s "$TMP/gallery.entry" ] || { echo "the gallery has no theme or wallpaper named $1"; return 1; }
    GALLERY_KIND=$(cut -f1 "$TMP/gallery.entry" | sed -n 1p)
    rm -rf "$2"; mkdir -p "$2"
    while IFS="$TAB" read -r _gk _gn _gp _gz _gh; do
        case ${_gp##*/} in look.env|palette.env) _gm=8192 ;; *) _gm=$GALLERY_PICTURE_MAX ;; esac
        gallery_blob "$_gp" "$_gm" "$2/${_gp##*/}" || return 1
        [ "$(wc -c < "$2/${_gp##*/}" | tr -d ' ')" = "$_gz" ] && [ "$(sha256_of "$2/${_gp##*/}")" = "$_gh" ] || { echo "$_gp is not the file the gallery's index names: its size or its sha256 differs"; return 1; }
    done < "$TMP/gallery.entry"
}
gallery_picture_ok() {   # gallery_picture_ok FILE -> 0 for a PNG or a JPEG as its name says, within the size and the pixels allowed, read from its header before anything decodes it; else one line and 1
    command -v python3 >/dev/null 2>&1 || { echo "python3 is not installed, and it reads a picture's header"; return 1; }
    [ "$(wc -c < "$1" | tr -d ' ')" -le "$GALLERY_PICTURE_MAX" ] || { echo "its picture is over $((GALLERY_PICTURE_MAX / 1048576)) MiB"; return 1; }
    _gq=$(python3 -I "$REPO/lib/look.py" picture "$1" 2>&1) || { echo "its picture is $(printf '%s' "$_gq" | tr -d '\001-\037\177' | cut -c1-80)"; return 1; }
    set -- "$1" $_gq
    case $(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z'):$2 in png:png|jpg:jpeg|jpeg:jpeg) ;; *) echo "its picture is a $2 named ${1##*/}"; return 1 ;; esac
    [ "$3" -ge 1 ] && [ "$4" -ge 1 ] && [ "$3" -le "${GALLERY_PIXELS_MAX%x*}" ] && [ "$4" -le "${GALLERY_PIXELS_MAX#*x}" ] || { echo "its picture is $3x$4, past $GALLERY_PIXELS_MAX"; return 1; }
}
gallery_theme_ok() {   # gallery_theme_ok DIR -> 0 when a theme from the gallery holds data alone, as its format says; else one line and 1
    [ -f "$1/look.env" ] && [ -f "$1/palette.env" ] || { echo "it has no look.env or no palette.env"; return 1; }
    ! LC_ALL=C grep -q '[^ -~]' "$1/look.env" "$1/palette.env" || { echo "its look.env or palette.env is not plain ASCII"; return 1; }
    _gw=$(look_ok "$1") || { echo "$_gw"; return 1; }
    [ "$(look_get "$1" FORMAT)" = 2 ] || { echo "its look.env is not of format 2"; return 1; }
    _gb=$(grep -Ev '^[[:space:]]*(#|$)' "$1/look.env" | cut -d= -f1 | awk -v ok=" $GALLERY_KEYS " 'index(ok, " " $0 " ") == 0 { print "holds " $0 ", which a shared theme never sets"; exit } seen[$0]++ { print "names " $0 " twice"; exit }')
    [ -z "$_gb" ] || { echo "its look.env $_gb"; return 1; }
    _gv=$(look_get "$1" WALLPAPER); case $_gv in ''|default|picture) ;; *) hex_rgb "$_gv" >/dev/null || wall_shipped "$_gv" || { echo "its WALLPAPER is not default, picture, #rrggbb or one of the drawings"; return 1; } ;; esac
    _gv=$(look_get "$1" ALPHA); case $_gv in ''|1|1.0|0.[5-9]|0.[5-9][0-9]) ;; *) echo "its ALPHA is not 0.5 to 1: a shared theme keeps windows readable"; return 1 ;; esac
    _gb=$(awk -v keys=" $THEME_KEYS " '/^[[:space:]]*(#|$)/ { next }
        { k = $0; sub(/=.*/, "", k); v = substr($0, length(k) + 2)
          if (index(keys, " " k " ") == 0 || v !~ /^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/ || seen[k]++) { print NR; b = 1; exit }
          n++ }
        END { if (!b && n != split(keys, a, " ")) print "count" }' "$1/palette.env")
    [ -z "$_gb" ] || { echo "its palette.env is not the twenty colors, each #rrggbb once"; return 1; }
    _gp=$(look_get "$1" PICTURE)
    for _gf in "$1"/*; do case ${_gf##*/} in look.env|palette.env|"$_gp") ;; *) echo "it holds a file that is none of its own: ${_gf##*/}"; return 1 ;; esac; done
    if [ "$(look_get "$1" WALLPAPER)" = picture ]; then gallery_picture_ok "$1/$_gp" || return 1
    elif [ -n "$_gp" ]; then echo "it names a PICTURE its WALLPAPER does not use"; return 1; fi
}
theme_gallery() {   # theme_gallery -- what the gallery's release offers: the themes and the wallpapers
    [ $# -eq 0 ] || refuse_in theme "gallery takes no word"
    gallery_fetch > "$TMP/gallery.why" || refuse_in theme "$(cat "$TMP/gallery.why")"
    echo "The gallery at $GALLERY_TAG ($(gallery_said)), signed by a key in allowed-signers:"
    _gt=$(awk -F '\t' '$1 == "theme" && !s[$2]++ { print $2 }' "$TMP/gallery.index")
    if [ -n "$_gt" ]; then echo "Themes:"
        for _gn in $_gt; do
            _gd=$TMP/gallery.row; rm -rf "$_gd"; mkdir -p "$_gd"; gallery_blob "themes/$_gn/look.env" 8192 "$_gd/look.env" >/dev/null || continue
            _gl=''; for _gk in FACE GLYPH_FAMILY ANIMATION; do _gv=$(look_get "$_gd" "$_gk"); case $_gk:$_gv in FACE:*) look_pick_ok face "$_gv" || _gv='?' ;; GLYPH_FAMILY:*) look_pick_ok family "$_gv" || _gv='?' ;; ANIMATION:*) case " none $ANIMATION_NAMES " in *" $_gv "*) ;; *) _gv='?' ;; esac ;; esac; _gl="$_gl, ${_gv:-?}"; done
            _gv=$(look_get "$_gd" WALLPAPER); case $_gv in picture) _gv='a picture' ;; ''|default) _gv='the ground' ;; *) hex_rgb "$_gv" >/dev/null || wall_shipped "$_gv" || _gv='?' ;; esac
            _gi=''; [ -z "$(look_get "$PALETTE_DIR/$_gn" GALLERY)" ] || _gi=", installed"
            printf '  %-20s %s%s\n' "$_gn" "${_gl#, }, $_gv" "$_gi"
        done
    fi
    _gt=$(awk -F '\t' '$1 == "wallpaper" { print $2 "\t" $3 "\t" $4 }' "$TMP/gallery.index")
    if [ -n "$_gt" ]; then echo "Wallpapers:"
        printf '%s\n' "$_gt" | while IFS="$TAB" read -r _gn _gp _gz; do
            _gi=''; [ ! -f "$GALLERY_WALLS/${_gp##*/}" ] || _gi=", installed"
            printf '  %-20s %s, %s KiB%s\n' "$_gn" "${_gp##*.}" "$((_gz / 1024))" "$_gi"
        done
    fi
    [ -z "$GALLERY_SKIPPED" ] || echo "Not taken, as no key in allowed-signers signed them:$GALLERY_SKIPPED."
    echo "spark-shell theme install NAME puts one in place and uses it."
}
theme_install() {   # theme_install NAME -- a theme or a wallpaper from the gallery, checked, put in place and used
    [ $# -eq 1 ] || refuse_in theme "install takes one name -- spark-shell theme gallery lists them"
    case $1 in [a-z]*) ;; *) refuse_in theme "install takes a gallery name: lowercase letters, digits and -" ;; esac
    case $1 in *[!a-z0-9-]*) refuse_in theme "install takes a gallery name: lowercase letters, digits and -" ;; esac
    [ ${#1} -le 40 ] || refuse_in theme "install takes a gallery name of 40 letters at most"
    case " $THEME_WORDS " in *" $1 "*) refuse_in theme "$1 is a word of spark-shell theme, so no theme can go by it" ;; esac
    gallery_fetch > "$TMP/gallery.why" || refuse_in theme "$(cat "$TMP/gallery.why")"
    cut -f2 "$TMP/gallery.index" | grep -qx -- "$1" || refuse_in theme "the gallery's $GALLERY_TAG has no theme or wallpaper named $1 -- spark-shell theme gallery lists them"
    _gd=$TMP/gallery.take
    gallery_take "$1" "$_gd" > "$TMP/gallery.why" || refuse_in theme "$1 from the gallery's $GALLERY_TAG was not installed: $(cat "$TMP/gallery.why")"
    if [ "$GALLERY_KIND" = wallpaper ]; then
        [ "$OS" != Darwin ] || refuse_in theme "$1 is a wallpaper, and macOS has its own desktop"
        [ "$DESKTOP" = sway ] || refuse_in theme "$1 is a wallpaper -- DESKTOP=$DESKTOP: spark-shell on desktop first"
        _gf=$(ls "$_gd"); gallery_picture_ok "$_gd/$_gf" > "$TMP/gallery.why" || refuse_in theme "$1 from the gallery's $GALLERY_TAG was not installed: $(sed 's/^its picture/the picture/' "$TMP/gallery.why")"
        mkdir -p "$GALLERY_WALLS"; cp "$_gd/$_gf" "$GALLERY_WALLS/$_gf.new" && mv "$GALLERY_WALLS/$_gf.new" "$GALLERY_WALLS/$_gf"
        wall_value_ok "$GALLERY_WALLS/$_gf" || refuse_in theme "$PATH_REFUSED"
        echo "installed the wallpaper $1 from the gallery's $GALLERY_TAG, signed and its sha256 checked ($GALLERY_WALLS/$_gf)"
        config_set WALLPAPER "$GALLERY_WALLS/$_gf" >/dev/null; WALLPAPER=$GALLERY_WALLS/$_gf; export WALLPAPER
        theme_load; wall_follow; look_apply; login_follow
        echo "a running sway shows it now"
        return 0
    fi
    case $(theme_kind "$1") in
        shipped|yours) refuse_in theme "$1 is a palette's name here: the gallery's $1 was not installed" ;;
        saved) [ -n "$(look_get "$PALETTE_DIR/$1" GALLERY)" ] || refuse_in theme "a saved theme of yours is named $1 -- spark-shell theme delete $1 first, or keep yours" ;;
    esac
    gallery_theme_ok "$_gd" > "$TMP/gallery.why" || refuse_in theme "$1 from the gallery's $GALLERY_TAG was not installed: $(cat "$TMP/gallery.why")"
    _gw=$(look_get "$_gd" WORDS | tr -cd 'A-Za-z0-9 ,.-' | cut -c1-80); [ -z "$(look_get "$_gd" WORDS)" ] || look_set "$_gd" WORDS "$_gw"   # the words held to the characters a look's name takes
    look_set "$_gd" PALETTE gallery; look_set "$_gd" GALLERY "$GALLERY_TAG"
    _gt=$PALETTE_DIR/$1   # the name held to its shape above: never empty, never a path
    mkdir_private "$PALETTE_DIR"; rm -rf "$_gt.new"; cp -R "$_gd" "$_gt.new" && rm -rf "${_gt:?}" && mv "$_gt.new" "$_gt"
    echo "installed the theme $1 from the gallery's $GALLERY_TAG, signed and its sha256s checked -- spark-shell theme $1 brings it back"
    theme_apply "$1"
}

