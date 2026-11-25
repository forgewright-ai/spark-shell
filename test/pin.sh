#!/bin/sh
# test/pin.sh -- write the sha256 of each part's release build into its component/PART/PART.env, built here as CI
# builds it: in the image ci.yml names by its digest, offline, in bwrap. A pin is then in the push that changes a
# part, not in a second one after CI's red. CI builds it again, twice, and release.yml refuses another.
#
#   sh test/pin.sh [PART...]          build and write: dialog bar winpad ear wallpaper, or the parts named
#   sh test/pin.sh --check [PART...]  build and compare, write nothing; exit 1 when a pin is not its build's
#   sh test/pin.sh --fetch            the image, once: some 300 MiB from Docker Hub, each layer held to its sha256
#
# The tree is this one's files as they are; the crates are the ones on disk, each held to Cargo.lock (cargo fetch
# --locked brings a new one). PIN_DIR (/var/tmp/spark-shell-pin) holds the image and the builds, one run at a time.
# Exit 2: it could not be built here, and nothing is said of the pin.
set -eu
cd "$(dirname "$0")/.."
no() { echo "pin: $*" >&2; exit 2; }
P=${PIN_DIR:-/var/tmp/spark-shell-pin}
check=''; fetch=''; parts=''
for a in "$@"; do
    case $a in
        --check) check=1 ;;
        --fetch) fetch=1 ;;
        -*) no "usage: sh test/pin.sh [--check] [PART...] | --fetch" ;;
        *) [ -f "component/$a/$a.env" ] && [ -f "test/${a}_build.sh" ] || no "no part $a"; parts="$parts $a" ;;
    esac
done
image=$(grep -hoE 'rust:[0-9A-Za-z.-]+@sha256:[0-9a-f]{64}' .github/workflows/ci.yml .github/workflows/release.yml | sort -u)
case $image in ''|*'
'*) no "ci.yml and release.yml name no one build image: $image" ;; esac
version=$(printf '%s\n' "$image" | sed 's/^rust:\([0-9.]*\).*/\1/')
command -v bwrap >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 || no "bwrap and flock are needed: CI's first build of a part prints its pin"
# a folder of this script's own, and of nobody else's
[ -d "$P" ] || mkdir -m 700 "$P"
[ ! -L "$P" ] && [ "$(stat -c %u "$P")" = "$(id -u)" ] || no "$P is not your folder"
[ -f "$P/.spark-shell-pin" ] || [ -z "$(ls -A "$P")" ] || no "$P is there and is no folder of this script: not touched (PIN_DIR names another)"
chmod 700 "$P"; : > "$P/.spark-shell-pin"
exec 9> "$P/lock"; flock 9   # one run at a time: two would build each other's trees
[ -z "$fetch" ] || exec python3 -I test/pin_image.py "$image" "$P"
[ "$(cat "$P/image" 2>/dev/null)" = "$image" ] || no "the image is not here: sh test/pin.sh --fetch brings it (some 300 MiB)"
rm -rf "$P/tree" "$P/cargo"; mkdir -p "$P/tree" "$P/root/__w/spark-shell/spark-shell" "$P/root/github/home"
{ git ls-files -z --cached; git ls-files -z --others --exclude-standard -- component; } > "$P/files"
tar --null -T "$P/files" -cf "$P/tree.tar" || no "the tree could not be read whole"
tar -xf "$P/tree.tar" -C "$P/tree"; rm -f "$P/tree.tar"
cp -r "$P/root/usr/local/cargo" "$P/cargo"; rm -rf "$P/cargo/registry"; mkdir -p "$P/cargo/registry"
for d in index cache; do cp -r "${CARGO_HOME:-$HOME/.cargo}/registry/$d" "$P/cargo/registry/$d"; done   # unpacked anew from the crates
python3 -I test/pin_image.py --crates "$P/cargo/registry/cache" "$P"/tree/component/Cargo.lock "$P"/tree/component/*/Cargo.lock || no "a crate is not the one Cargo.lock names"
rc=0
for c in ${parts:-dialog bar winpad ear wallpaper}; do
    env=component/$c/$c.env; key=$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]')_SHA256_X86_64_LINUX_GNU
    [ "$(grep -c "^$key=" "$env")" = 1 ] || no "$env has not one line $key="
    asks=$(sed -n 's/^channel = "\(.*\)"/\1/p' "component/$c/rust-toolchain.toml" 2>/dev/null)
    [ "${asks:-$version}" = "$version" ] || no "$c asks for rust $asks, and the image has $version"
    # the checkout's path, the homes and the toolchain are the ones CI's container has
    got=$(nice -n 15 bwrap --die-with-parent --new-session --unshare-all --ro-bind "$P/root" / --proc /proc --dev /dev --tmpfs /tmp \
        --bind "$P/tree" /__w/spark-shell/spark-shell --bind "$P/cargo" /usr/local/cargo --chdir /__w/spark-shell/spark-shell --clearenv \
        --setenv PATH /usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin --setenv HOME /github/home --setenv CI true \
        --setenv RUSTUP_HOME /usr/local/rustup --setenv CARGO_HOME /usr/local/cargo --setenv RUSTUP_TOOLCHAIN "$version-x86_64-unknown-linux-gnu" \
        --setenv CARGO_NET_OFFLINE true sh "test/${c}_build.sh" 2>"$P/$c.log" </dev/null) || got=''
    got=${got%% *}
    printf '%s\n' "$got" | grep -qxE '[0-9a-f]{64}' || { tail -3 "$P/$c.log" >&2; no "$c was not built: $P/$c.log"; }
    want=$(sed -n "s/^$key=//p" "$env")
    if [ "$got" = "$want" ]; then echo "ok    $c $got"
    elif [ -n "$check" ]; then echo "stale $c $want, its build is $got"; rc=1
    else
        sed "s/^$key=.*/$key=$got/" "$env" > "$P/env.new" || no "$env could not be written"
        cat "$P/env.new" > "$env" || no "$env could not be written"
        [ "$(sed -n "s/^$key=//p" "$env")" = "$got" ] || no "$env does not hold what was written"
        echo "wrote $c $got"
    fi
done
exit "$rc"
