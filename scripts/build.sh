#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_CRATE="$PROJECT_ROOT/rshangul"
GENERATED_DIR="$PROJECT_ROOT/OngeulApp/Generated"

echo "=== Building rshangul (Rust) ==="

# Build for both architectures
cargo build --manifest-path "$RUST_CRATE/Cargo.toml" --release --target aarch64-apple-darwin
cargo build --manifest-path "$RUST_CRATE/Cargo.toml" --release --target x86_64-apple-darwin

# Create universal static library
UNIVERSAL_DIR="$RUST_CRATE/target/universal/release"
mkdir -p "$UNIVERSAL_DIR"
lipo -create \
    "$RUST_CRATE/target/aarch64-apple-darwin/release/librshangul.a" \
    "$RUST_CRATE/target/x86_64-apple-darwin/release/librshangul.a" \
    -output "$UNIVERSAL_DIR/librshangul.a"

echo "=== Universal library created: $UNIVERSAL_DIR/librshangul.a ==="

# Generate Swift bindings
echo "=== Generating Swift bindings ==="
mkdir -p "$GENERATED_DIR"
cargo run --manifest-path "$RUST_CRATE/Cargo.toml" \
    --bin uniffi-bindgen generate \
    --library "$RUST_CRATE/target/aarch64-apple-darwin/release/librshangul.dylib" \
    --language swift \
    --out-dir "$GENERATED_DIR"

echo "=== Done ==="
echo "Generated files:"
ls -la "$GENERATED_DIR/"
