#!/bin/sh
# The bar's release build, the one CI's bar job and release.yml both run,
# in the wallpaper loop's pinned Debian 12 image (glibc 2.36): the toolchain
# component/bar/rust-toolchain.toml pins, the locked crates, every path remapped, no
# build id, so the same tree builds the same bytes. It links glibc
# dynamically: the bar opens Wayland, cairo and pango at run time.
# Prints the binary's sha256 and its path.
set -eu
cd "$(dirname "$0")/../component/bar"
target=x86_64-unknown-linux-gnu
export CARGO_INCREMENTAL=0
RUSTFLAGS="--remap-path-prefix=$(pwd)=/build/bar --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup -C link-arg=-Wl,--build-id=none"
export RUSTFLAGS
cargo build --release --locked --target "$target" --bin spark-bar >&2
bin=${CARGO_TARGET_DIR:-target}/$target/release/spark-bar
printf '%s %s\n' "$(sha256sum "$bin" | cut -d' ' -f1)" "$bin"
