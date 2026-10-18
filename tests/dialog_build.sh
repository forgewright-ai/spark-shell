#!/bin/sh
# The dialog's release build, the one CI's dialog job and release.yml
# both run: musl static, the toolchain rust-toolchain.toml pins, the
# locked crates, every path remapped, so the same tree builds the same
# bytes. Prints the binary's path and its sha256. Linux only.
set -eu
cd "$(dirname "$0")/../dialog"
target=x86_64-unknown-linux-musl
# the newest commit of what the binary is built from (dialog.env is not among them)
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct -- src assets Cargo.toml Cargo.lock rust-toolchain.toml 2>/dev/null || echo 0)
export SOURCE_DATE_EPOCH CARGO_INCREMENTAL=0
RUSTFLAGS="--remap-path-prefix=$(pwd)=/build/dialog --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo --remap-path-prefix=${RUSTUP_HOME:-$HOME/.rustup}=/rustup -C target-feature=+crt-static"
export RUSTFLAGS
cargo build --release --locked --target "$target" --bin spark-dialog >&2
bin=${CARGO_TARGET_DIR:-target}/$target/release/spark-dialog
printf '%s %s\n' "$(sha256sum "$bin" | cut -d' ' -f1)" "$bin"
