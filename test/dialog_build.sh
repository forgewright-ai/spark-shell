#!/bin/sh
# The dialog's release build, the one CI's dialog-build job and release.yml both run,
# in the pinned Debian 12 image the bar builds in (glibc 2.36): the toolchain
# component/dialog/rust-toolchain.toml pins, the locked crates, every path remapped, no
# build id, so the same tree builds the same bytes. It links glibc
# dynamically: the dialog opens Wayland, cairo, pango and the keyboard's layouts
# at run time for its own window. Prints the binary's sha256 and its path.
set -eu
cd "$(dirname "$0")/../component/dialog"
target=x86_64-unknown-linux-gnu
export CARGO_INCREMENTAL=0
RUSTFLAGS="--remap-path-prefix=$(cd .. && pwd)=/build/component --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup -C link-arg=-Wl,--build-id=none"
export RUSTFLAGS
cargo build --release --locked --target "$target" --bin spark-dialog >&2
bin=${CARGO_TARGET_DIR:-../target}/$target/release/spark-dialog
printf '%s %s\n' "$(sha256sum "$bin" | cut -d' ' -f1)" "$bin"
