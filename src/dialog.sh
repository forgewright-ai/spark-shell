# shellcheck extended-analysis=false
# --- the dialog
# sets: DIALOG_BIN DIALOG_URL SEMANTIC_LOG SEMANTIC_MODEL SEMANTIC_SHA256 SEMANTIC_SIZE SEMANTIC_URL WALLPAPER_BIN
# reads: MODE REPO STATE_DIR TMP
DIALOG_BIN=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/spark-dialog
DIALOG_URL=${SPARK_SHELL_DIALOG_URL:-https://github.com/forgewright-ai/spark-shell/releases/download}   # the release assets; file:// or none in the tests
# the embedding model, pinned by its sha256 and size
SEMANTIC_URL=${SPARK_SHELL_SEMANTIC_URL:-https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/6ea3e3a309d12a4779cfda98b8c19800d2d5da71/embeddinggemma-2-Q8_0.gguf}   # the tests point it at a file:// one, or none
SEMANTIC_SHA256=2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135
SEMANTIC_SIZE=309855456   # bytes, 310 MB
SEMANTIC_MODEL=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/models/embeddinggemma-2-Q8_0.gguf
SEMANTIC_LOG=$STATE_DIR/semantic.log
semantic_where() { SEMANTIC_RUN=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; SEMANTIC_RUN=${SEMANTIC_RUN:-$STATE_DIR}; SEMANTIC_SOCK=$SEMANTIC_RUN/semantic.sock; SEMANTIC_PID=$SEMANTIC_RUN/semantic.pid; }   # read when asked: XDG_RUNTIME_DIR is set after this file is read
dialog_target() { case $(uname -m) in x86_64|amd64) echo x86_64-linux-musl ;; *) return 1 ;; esac; }   # -> the release's build for this machine, or false
dialog_want_sha() {   # -> the sha256 the release tag's tree pins for this machine, or nothing
    _dk=DIALOG_SHA256_$(dialog_target | tr 'a-z-' 'A-Z_'); _rt=$(release_tag) || return 0
    git -C "$REPO" show "$_rt:component/dialog/dialog.env" 2>/dev/null | sed -n "s/^$_dk=\([0-9a-f]\{64\}\)$/\1/p"
}
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
dialog_ok() { [ -x "$DIALOG_BIN" ] && _dw=$(dialog_want_sha) && [ -n "$_dw" ] && [ "$(sha256_of "$DIALOG_BIN")" = "$_dw" ]; }   # the binary in place is the one the tree pins
tag_floor() {   # -> the newest signed tag at or behind HEAD; false when none
    for _tf in $(git -C "$REPO" tag -l 'v[0-9]*.[0-9]*' --merged HEAD --sort=-v:refname 2>/dev/null); do
        if tag_signed "$_tf"; then printf '%s\n' "$_tf"; return 0; fi
    done
    return 1
}
clone_tag() { tag_floor || git -C "$REPO" describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*' 2>/dev/null; }   # -> the release this clone is at: the signed tag, else the nearest
release_tag() {   # -> clone_tag when it pins a dialog and component/dialog/ is unchanged since; false otherwise
    _rt=$(clone_tag) || return 1
    git -C "$REPO" cat-file -e "$_rt:component/dialog/dialog.env" 2>/dev/null || return 1
    git -C "$REPO" diff --quiet "$_rt" -- component/dialog 2>/dev/null || return 1
    printf '%s\n' "$_rt"
}
tag_verify() { git -C "$REPO" -c gpg.format=ssh -c "gpg.ssh.allowedSignersFile=$REPO/allowed-signers" -c gpg.program=false -c gpg.openpgp.program=false -c gpg.x509.program=false verify-tag "$1"; }   # tag_verify TAG -- by allowed-signers alone: a signature of another kind gets no program
tag_signed() {   # tag_signed TAG -> 0 when a key in allowed-signers signed it and the tag object names itself TAG
    command -v ssh-keygen >/dev/null 2>&1 && [ -f "$REPO/allowed-signers" ] || return 1
    tag_verify "$1" >/dev/null 2>&1 || return 1
    [ "$(git -C "$REPO" cat-file tag "$1" 2>/dev/null | sed -n 's/^tag //p' | sed -n 1p)" = "$1" ]
}
cmd_update() {   # the clone moves forward to the newest signed tag past its own; then on --yes when the seat is on
    REFUSE_AS=update
    config_load
    command -v git >/dev/null 2>&1 || refuse "git is not installed"
    command -v ssh-keygen >/dev/null 2>&1 || refuse "ssh-keygen is not installed: a release tag's signature cannot be read (the openssh package)"
    [ -f "$REPO/allowed-signers" ] || refuse "no allowed-signers beside spark-shell: not a clone of spark-shell"
    git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || refuse "$REPO is not a git clone"
    _here=$(tag_floor || echo none)
    # a tag moved on origin fails the whole fetch: it stays as first seen, and is said
    _fo=$(LC_ALL=C git -C "$REPO" fetch origin 'refs/tags/*:refs/tags/*' 2>&1) || {
        _moved=$(printf '%s\n' "$_fo" | sed -n 's/.*\[rejected\] *\([^ ]*\) .*would clobber existing tag.*/\1/p' | paste -sd' ' -)
        [ -n "$_moved" ] || refuse "could not fetch the tags from origin"
        echo "spark-shell update: $_moved moved on origin: the copy here stays"
    }
    _to=''; _skipped=''
    for _t in $(git -C "$REPO" tag -l 'v[0-9]*.[0-9]*' --sort=-v:refname); do   # a release is a dotted name: gallery-v1 is not one
        [ "$_t" != "$_here" ] || break        # newest first: the rest are behind the clone's own
        if tag_signed "$_t"; then _to=$_t; break; fi
        _skipped="$_skipped $_t"
    done
    if [ -z "$_to" ]; then
        [ -n "$_skipped" ] || { echo "spark-shell update: at $_here, the newest release"; return 0; }
        refuse "the releases past $_here are not signed by a key in allowed-signers:$_skipped -- nothing moved"
    fi
    # a tag is up minutes before its release: a seat moved now would find no build
    if seat_on && ! release_up "$_to"; then
        refuse "$_to is signed, but its release is not published yet -- nothing moved; try again in a few minutes"
    fi
    _by=$(tag_verify "$_to" 2>&1 | sed -n 's/.*signature for \([^ ]*\) with.*/\1/p' | sed -n 1p)
    _note=''; [ -z "$_skipped" ] || _note=" (skipped, not a signed release:$_skipped)"
    if [ "$MODE" = dry ]; then
        echo "spark-shell update: would move $_here -> $_to, signed by ${_by:-a key in allowed-signers}$_note"
        ! seat_on || echo "spark-shell update: then spark-shell on --yes, from $_to"
        return 0
    fi
    [ -z "$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null)" ] || refuse "the clone has changes of its own (git -C $REPO status) -- nothing moved"
    git -C "$REPO" -c advice.detachedHead=false checkout -q --detach "$_to" 2>/dev/null || refuse "could not move the clone to $_to"
    echo "spark-shell update: $_to, signed by ${_by:-a key in allowed-signers} (was $_here)$_note"
    seat_on || return 0
    rm -rf "$TMP"; trap - EXIT   # an exec runs no trap
    exec "$REPO/spark-shell" on --yes     # the new tree applies itself
}
release_up() {   # release_up TAG -> 0 when TAG's dialog can be fetched, or there is nothing to fetch here
    _ut=$(dialog_target) || return 0
    [ "$DIALOG_URL" != none ] || return 0
    command -v curl >/dev/null 2>&1 || return 0
    curl -fsIL --proto '=https,file' --proto-redir '=https' -o /dev/null "$DIALOG_URL/$1/spark-dialog-$_ut" 2>/dev/null
}
dialog_install() {   # the dialog's row of on: in place as pinned, or fetched for the signed tag and checked
    _dt=$(dialog_target) || { skip dialog "no build for $(uname -m) yet: the desktop keys open nothing"; return 0; }
    _rt=$(release_tag) || { row todo dialog "this clone is past its release: the dialog comes with the next tag"; return 0; }
    _dw=$(dialog_want_sha); [ -n "$_dw" ] || { row todo dialog "$_rt pins no build for $_dt in component/dialog/dialog.env"; return 0; }
    if dialog_ok; then ok dialog "$DIALOG_BIN, the sha256 $_rt pins"; return 0; fi
    [ "$DIALOG_URL" != none ] || { skip dialog "no release to fetch it from (SPARK_SHELL_DIALOG_URL=none)"; return 0; }
    tag_signed "$_rt" || { row todo dialog "$_rt is not signed by a key in allowed-signers: no dialog installed"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo dialog "curl is not installed: the dialog cannot be fetched (spark-shell on installs it)"; return 0; }
    need dialog "fetch spark-dialog for $_rt and check its sha256" || return 0
    _df=$TMP/spark-dialog
    curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$_df" "$DIALOG_URL/$_rt/spark-dialog-$_dt" 2>/dev/null || { rm -f "$_df"; row todo dialog "could not fetch spark-dialog for $_rt -- spark-shell on again"; return 0; }
    [ "$(sha256_of "$_df")" = "$_dw" ] || { rm -f "$_df"; row todo dialog "the spark-dialog fetched for $_rt is not the one the tree pins: not installed"; return 0; }
    mkdir -p "$(dirname "$DIALOG_BIN")" && cp "$_df" "$DIALOG_BIN.new" && chmod 755 "$DIALOG_BIN.new" && mv "$DIALOG_BIN.new" "$DIALOG_BIN"
    row ok dialog "installed for $_rt ($DIALOG_BIN), sha256 checked"
}
# --- the wallpaper loop
WALLPAPER_BIN=${XDG_DATA_HOME:-$HOME/.local/share}/spark-shell/spark-wallpaper
wallpaper_target() { case $(uname -m) in x86_64|amd64) echo x86_64-linux-gnu ;; *) return 1 ;; esac; }   # -> the release's build for this machine, or false
wallpaper_release_tag() {   # -> clone_tag when it pins a wallpaper loop and component/wallpaper/ is unchanged since; false otherwise
    _plr=$(clone_tag) || return 1
    git -C "$REPO" cat-file -e "$_plr:component/wallpaper/wallpaper.env" 2>/dev/null || return 1
    git -C "$REPO" diff --quiet "$_plr" -- component/wallpaper 2>/dev/null || return 1
    printf '%s\n' "$_plr"
}
wallpaper_want_sha() {   # -> the sha256 the release tag's tree pins for this machine, or nothing
    _plk=WALLPAPER_SHA256_$(wallpaper_target | tr 'a-z-' 'A-Z_'); _plr=$(wallpaper_release_tag) || return 0
    git -C "$REPO" show "$_plr:component/wallpaper/wallpaper.env" 2>/dev/null | sed -n "s/^$_plk=\([0-9a-f]\{64\}\)$/\1/p"
}
wallpaper_ok() { [ -x "$WALLPAPER_BIN" ] && _plw=$(wallpaper_want_sha) && [ -n "$_plw" ] && [ "$(sha256_of "$WALLPAPER_BIN")" = "$_plw" ]; }   # the binary in place is the one the tree pins
wallpaper_cmd() { [ -n "${SPARK_SHELL_WALLPAPER:-}" ] || SPARK_SHELL_WALLPAPER=${SPARK_SHELL_PLAYER:-}; if [ -n "${SPARK_SHELL_WALLPAPER:-}" ]; then [ -x "$SPARK_SHELL_WALLPAPER" ] && printf '%s' "$SPARK_SHELL_WALLPAPER"; elif wallpaper_ok; then printf '%s' "$WALLPAPER_BIN"; else return 1; fi; }   # -> SPARK_SHELL_WALLPAPER (another build, as it is), else the pinned player; false when none
wallpaper_install() {   # the wallpaper loop's row of on desktop: in place as pinned, or fetched for the signed tag and checked
    _plt=$(wallpaper_target) || { skip motion "no spark-wallpaper built for $(uname -m) yet: the wallpaper stays still"; return 0; }
    _plr=$(wallpaper_release_tag) || { row todo motion "this clone is past its release: spark-wallpaper comes with the next tag"; return 0; }
    _plw=$(wallpaper_want_sha); [ -n "$_plw" ] || { skip motion "$_plr pins no spark-wallpaper: the wallpaper stays still"; return 0; }
    if wallpaper_ok; then ok motion "$WALLPAPER_BIN, the sha256 $_plr pins"; return 0; fi
    [ "$DIALOG_URL" != none ] || { skip motion "no release to fetch it from (SPARK_SHELL_DIALOG_URL=none)"; return 0; }
    tag_signed "$_plr" || { row todo motion "$_plr is not signed by a key in allowed-signers: spark-wallpaper not installed"; return 0; }
    command -v curl >/dev/null 2>&1 || { row todo motion "curl is not installed: spark-wallpaper cannot be fetched (spark-shell on installs it)"; return 0; }
    need motion "fetch spark-wallpaper for $_plr and check its sha256" || return 0
    _plf=$TMP/spark-wallpaper
    curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$_plf" "$DIALOG_URL/$_plr/spark-wallpaper-$_plt" 2>/dev/null || { rm -f "$_plf"; row todo motion "could not fetch spark-wallpaper for $_plr -- spark-shell on desktop again"; return 0; }
    [ "$(sha256_of "$_plf")" = "$_plw" ] || { rm -f "$_plf"; row todo motion "the spark-wallpaper fetched for $_plr is not the one the tree pins: not installed"; return 0; }
    mkdir -p "$(dirname "$WALLPAPER_BIN")" && cp "$_plf" "$WALLPAPER_BIN.new" && chmod 755 "$WALLPAPER_BIN.new" && mv "$WALLPAPER_BIN.new" "$WALLPAPER_BIN"
    row ok motion "spark-wallpaper installed for $_plr ($WALLPAPER_BIN), sha256 checked"
}

