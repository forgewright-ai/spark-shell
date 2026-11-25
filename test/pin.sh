#!/bin/sh
# test/pin.sh -- write the sha256 of each part's release build into its component/PART/PART.env, built here as CI
# builds it: in the image ci.yml names by its digest, offline, in bwrap. A pin is then in the push that changes a
# part, not in a second one after CI's red. CI builds it again, twice, and release.yml refuses another.
#
#   sh test/pin.sh [PART...]          build and write: dialog bar winpad ear wallpaper, or the parts named
#   sh test/pin.sh --check [PART...]  build and compare, write nothing; exit 1 when a pin is not its build's
#   sh test/pin.sh --fetch            the image, once: some 300 MiB from Docker Hub, each layer held to its sha256
#
# The tree is this one's files as they are, the crates are the ones on disk (cargo fetch --locked brings a new one).
# PIN_DIR (/var/tmp/spark-shell-pin) holds the image and the builds. It runs at low priority.
set -eu
cd "$(dirname "$0")/.."
P=${PIN_DIR:-/var/tmp/spark-shell-pin}
image=$(awk '/^  dialog-build:/ { on = 1 } on && /^    container: rust:/ { print $2; exit }' .github/workflows/ci.yml)
case $image in rust:*@sha256:*) ;; *) echo "pin: ci.yml's dialog-build names no image by its digest" >&2; exit 2 ;; esac
check=''
case ${1:-} in
    --fetch) exec python3 -I test/pin_image.py "$image" "$P" ;;
    --check) check=1; shift ;;
    -*) echo "usage: sh test/pin.sh [--check] [PART...] | --fetch" >&2; exit 2 ;;
esac
[ $# -gt 0 ] || set -- dialog bar winpad ear wallpaper
command -v bwrap >/dev/null 2>&1 || { echo "pin: bwrap is not installed: CI's first build of a part prints its pin" >&2; exit 2; }
[ "$(cat "$P/image" 2>/dev/null)" = "$image" ] || { echo "pin: the image is not here: sh test/pin.sh --fetch brings it (some 300 MiB)" >&2; exit 2; }
rm -rf "$P/tree" "$P/cargo"; mkdir -p "$P/tree" "$P/root/__w/spark-shell/spark-shell" "$P/root/github/home"
{ git ls-files -z --cached; git ls-files -z --others --exclude-standard -- component; } | tar --null -T - -cf - --ignore-failed-read 2>/dev/null | tar -xf - -C "$P/tree"
cp -r "$P/root/usr/local/cargo" "$P/cargo"; rm -rf "$P/cargo/registry"; cp -r "${CARGO_HOME:-$HOME/.cargo}/registry" "$P/cargo/registry"
version=$(printf '%s\n' "$image" | sed 's/^rust:\([0-9.]*\).*/\1/')
rc=0
for c in "$@"; do
    env=component/$c/$c.env
    [ -f "$env" ] && [ -f "test/${c}_build.sh" ] || { echo "pin: no part $c" >&2; exit 2; }
    # the checkout's path, the homes and the toolchain are the ones CI's container has
    got=$(nice -n 15 bwrap --die-with-parent --new-session --unshare-all --ro-bind "$P/root" / --proc /proc --dev /dev --tmpfs /tmp \
        --bind "$P/tree" /__w/spark-shell/spark-shell --bind "$P/cargo" /usr/local/cargo --chdir /__w/spark-shell/spark-shell --clearenv \
        --setenv PATH /usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin --setenv HOME /github/home --setenv CI true \
        --setenv RUSTUP_HOME /usr/local/rustup --setenv CARGO_HOME /usr/local/cargo --setenv RUSTUP_TOOLCHAIN "$version-x86_64-unknown-linux-gnu" \
        --setenv CARGO_NET_OFFLINE true sh "test/${c}_build.sh" 2>"$P/$c.log" | cut -d' ' -f1) || got=''
    case $got in *[!0-9a-f]*|'') echo "pin: $c was not built: $P/$c.log" >&2; tail -3 "$P/$c.log" >&2; exit 1 ;; esac
    want=$(sed -n 's/^[A-Z]*_SHA256_X86_64_LINUX_GNU=//p' "$env")
    if [ "$got" = "$want" ]; then echo "ok    $c $got"
    elif [ -n "$check" ]; then echo "stale $c $want, its build is $got"; rc=1
    else
        sed "s/^\([A-Z]*_SHA256_X86_64_LINUX_GNU=\).*/\1$got/" "$env" > "$P/env.new" && cat "$P/env.new" > "$env"
        echo "wrote $c $got"
    fi
done
exit "$rc"
