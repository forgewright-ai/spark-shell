#!/bin/sh
# The dialog's crates as a CycloneDX 1.5 file, from component/Cargo.lock and
# the dialog's target graph and cargo metadata (the licences).
set -eu
cd "$(dirname "$0")/../component/dialog"
target=x86_64-unknown-linux-gnu
# The workspace also builds the bar and pad. Use the features selected for the dialog binary.
tree=$(cargo tree --locked -p spark-dialog --target "$target" --edges normal,build --prefix none --format '{p}')
cargo metadata --locked --format-version 1 --filter-platform "$target" \
    | jq --arg tree "$tree" --arg v "$(sed -n 's/^version = "\(.*\)"$/\1/p' Cargo.toml | head -1)" '
        ($tree | split("\n") | map(split(" ") | .[0] + "@" + (.[1] | ltrimstr("v"))) | INDEX(.)) as $built
        | {bomFormat: "CycloneDX", specVersion: "1.5", version: 1,
           metadata: {component: {type: "application", name: "spark-dialog", version: $v}},
           components: [.packages[] | select($built[.name + "@" + .version]) | select(.name != "spark-dialog")
             | {type: "library", name, version, purl: ("pkg:cargo/" + .name + "@" + .version), licenses: [{expression: (.license // "NOASSERTION")}]}]
           | sort_by(.name)}'
