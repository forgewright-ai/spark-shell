#!/bin/sh
# The wallpaper loop's release build, the one CI's wallpaper job and
# release.yml both run, in the same pinned Debian 12 image (glibc 2.36):
# the toolchain component/wallpaper/rust-toolchain.toml pins, the locked crates, every
# path remapped, no build id, so the same tree builds the same bytes. It
# links glibc dynamically: the player loads libmpv, EGL and Wayland's
# client library at run time. Prints the binary's sha256 and its path.
set -eu
cd "$(dirname "$0")/../component/wallpaper"
target=x86_64-unknown-linux-gnu
export CARGO_INCREMENTAL=0
RUSTFLAGS="--remap-path-prefix=$(pwd)=/build/wallpaper --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup -C link-arg=-Wl,--build-id=none"
export RUSTFLAGS
cargo build --release --locked --target "$target" --bin spark-wallpaper >&2
bin=${CARGO_TARGET_DIR:-target}/$target/release/spark-wallpaper
printf '%s %s\n' "$(sha256sum "$bin" | cut -d' ' -f1)" "$bin"
