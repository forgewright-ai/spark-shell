#!/bin/sh
# The dialog's crates as a CycloneDX 1.5 file, from dialog/Cargo.lock and
# cargo metadata (the licences), for the release beside the binary.
set -eu
cd "$(dirname "$0")/../dialog"
cargo metadata --locked --format-version 1 --filter-platform x86_64-unknown-linux-musl \
    | jq --arg v "$(sed -n 's/^version = "\(.*\)"$/\1/p' Cargo.toml | head -1)" '
        (.resolve.nodes | map(.id)) as $ids
        | {bomFormat: "CycloneDX", specVersion: "1.5", version: 1,
           metadata: {component: {type: "application", name: "spark-dialog", version: $v}},
           components: [.packages[] | select(.id as $i | $ids | index($i)) | select(.name != "spark-dialog")
             | {type: "library", name, version, purl: ("pkg:cargo/" + .name + "@" + .version), licenses: [{expression: (.license // "NOASSERTION")}]}]
           | sort_by(.name)}'
