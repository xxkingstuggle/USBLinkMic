#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MANIFEST="$ROOT/third_party/gnirehtet/relay-rust/Cargo.toml"
OUTPUT="$ROOT/mac-native/USBLinkMicNative/Resources/gnirehtet-relay"

cargo build --locked --release --manifest-path "$MANIFEST"
install -m 755 "$ROOT/third_party/gnirehtet/relay-rust/target/release/gnirehtet" "$OUTPUT"
shasum -a 256 "$OUTPUT"
