#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_CRATE="$PROJECT_ROOT/rshangul"
TARGET_DIR="$PROJECT_ROOT/target"
GENERATED_DIR="$PROJECT_ROOT/OngeulApp/Generated"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/Ongeul.app"
APP_CONTENTS="$APP_BUNDLE/Contents"

# ── 1. Rust 빌드 → librshangul.a ──

echo "=== [1/5] Building rshangul (Rust) ==="

LIB_DIR="$TARGET_DIR/universal/release"
mkdir -p "$LIB_DIR"

cargo build --manifest-path "$RUST_CRATE/Cargo.toml" --release --target aarch64-apple-darwin

# x86_64 타겟이 설치되어 있으면 universal binary 생성
if rustup target list --installed | grep -q x86_64-apple-darwin; then
    cargo build --manifest-path "$RUST_CRATE/Cargo.toml" --release --target x86_64-apple-darwin
    lipo -create \
        "$TARGET_DIR/aarch64-apple-darwin/release/librshangul.a" \
        "$TARGET_DIR/x86_64-apple-darwin/release/librshangul.a" \
        -output "$LIB_DIR/librshangul.a"
    echo "    Universal library: $LIB_DIR/librshangul.a"
else
    cp "$TARGET_DIR/aarch64-apple-darwin/release/librshangul.a" "$LIB_DIR/librshangul.a"
    echo "    aarch64-only library: $LIB_DIR/librshangul.a"
    echo "    (Install x86_64-apple-darwin target for universal binary)"
fi

# ── 2. UniFFI Swift 바인딩 생성 ──

echo "=== [2/5] Generating Swift bindings ==="

mkdir -p "$GENERATED_DIR"
cargo run --manifest-path "$RUST_CRATE/Cargo.toml" \
    --bin uniffi-bindgen generate \
    --library "$TARGET_DIR/aarch64-apple-darwin/release/librshangul.dylib" \
    --language swift \
    --out-dir "$GENERATED_DIR"

echo "    Generated: $GENERATED_DIR/"

# ── 3. Swift 소스 컴파일 ──

echo "=== [3/5] Compiling Swift sources ==="

mkdir -p "$APP_CONTENTS/MacOS"

SDK_PATH=$(xcrun --show-sdk-path)

HEADER="$GENERATED_DIR/RshangulFFI.h"

# Swift 소스 파일 수집
SWIFT_SOURCES=(
    "$GENERATED_DIR/Rshangul.swift"
    "$PROJECT_ROOT/OngeulApp/Sources/main.swift"
    "$PROJECT_ROOT/OngeulApp/Sources/OngeulInputController.swift"
)

swiftc \
    -target arm64-apple-macos14.0 \
    -sdk "$SDK_PATH" \
    -import-objc-header "$HEADER" \
    -L "$LIB_DIR" -lrshangul \
    -framework Cocoa -framework InputMethodKit \
    -module-name Ongeul \
    "${SWIFT_SOURCES[@]}" \
    -o "$APP_CONTENTS/MacOS/Ongeul"

echo "    Binary: $APP_CONTENTS/MacOS/Ongeul"

# ── 4. 앱 번들 구조 생성 ──

echo "=== [4/5] Creating app bundle ==="

# Info.plist 복사
cp "$PROJECT_ROOT/OngeulApp/Resources/Info.plist" "$APP_CONTENTS/Info.plist"

# Resources 디렉토리 생성 및 리소스 복사
mkdir -p "$APP_CONTENTS/Resources"

# 레이아웃 파일 복사
cp "$RUST_CRATE/layouts/2-standard.json5" "$APP_CONTENTS/Resources/"
cp "$RUST_CRATE/layouts/3-390.json5" "$APP_CONTENTS/Resources/"
cp "$RUST_CRATE/layouts/3-final.json5" "$APP_CONTENTS/Resources/"

# 아이콘 복사
cp "$PROJECT_ROOT/OngeulApp/Resources/icon_ko.tiff" "$APP_CONTENTS/Resources/"
cp "$PROJECT_ROOT/OngeulApp/Resources/icon_menubar.tiff" "$APP_CONTENTS/Resources/"

# 로컬라이제이션 파일 복사
mkdir -p "$APP_CONTENTS/Resources/ko.lproj"
cp "$PROJECT_ROOT/OngeulApp/Resources/ko.lproj/InfoPlist.strings" \
   "$APP_CONTENTS/Resources/ko.lproj/"

echo "    Bundle: $APP_BUNDLE"
echo "    Resources:"
ls "$APP_CONTENTS/Resources/"

# ── 5. 코드 서명 (ad-hoc) ──

echo "=== [5/5] Code signing (ad-hoc) ==="

codesign --force --sign - "$APP_BUNDLE"

echo "=== Build complete ==="
echo "    $APP_BUNDLE"
