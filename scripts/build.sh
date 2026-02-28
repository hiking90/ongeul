#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_CRATE="$PROJECT_ROOT/rshangul"
TARGET_DIR="$PROJECT_ROOT/target"
GENERATED_DIR="$PROJECT_ROOT/OngeulApp/Generated"

# ── 타겟 설정 ──

if [ -n "${1:-}" ]; then
    TARGET="$1"
else
    ARCH="$(uname -m)"
    case "$ARCH" in
        arm64)  TARGET="aarch64-apple-darwin" ;;
        x86_64) TARGET="x86_64-apple-darwin" ;;
        *)
            echo "Error: Unknown architecture '$ARCH'"
            exit 1
            ;;
    esac
fi

# 타겟 → clang/swiftc 타겟 매핑
case "$TARGET" in
    aarch64-apple-darwin) APPLE_TARGET="arm64-apple-macos14.0" ;;
    x86_64-apple-darwin)  APPLE_TARGET="x86_64-apple-macos14.0" ;;
    *)
        echo "Error: Unsupported target '$TARGET'"
        echo "Supported targets: aarch64-apple-darwin, x86_64-apple-darwin"
        exit 1
        ;;
esac

BUILD_DIR="$PROJECT_ROOT/build/$TARGET"
APP_BUNDLE="$BUILD_DIR/Ongeul.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
LIB_DIR="$TARGET_DIR/$TARGET/release"

echo "=== Building Ongeul for $TARGET ==="

# ── 1. Rust 빌드 → librshangul.a ──

echo "=== [1/5] Building rshangul (Rust) ==="

cargo build --manifest-path "$RUST_CRATE/Cargo.toml" --release --target "$TARGET"

echo "    Library: $LIB_DIR/librshangul.a"

# ── 2. UniFFI Swift 바인딩 생성 ──

echo "=== [2/5] Generating Swift bindings ==="

mkdir -p "$GENERATED_DIR"
cargo run --manifest-path "$RUST_CRATE/Cargo.toml" \
    --bin uniffi-bindgen generate \
    --library "$LIB_DIR/librshangul.dylib" \
    --language swift \
    --out-dir "$GENERATED_DIR"

echo "    Generated: $GENERATED_DIR/"

# ── 3. Swift 소스 컴파일 ──

echo "=== [3/5] Compiling Swift sources ==="

mkdir -p "$APP_CONTENTS/MacOS"

SDK_PATH=$(xcrun --show-sdk-path)

BRIDGING_HEADER="$PROJECT_ROOT/OngeulApp/Sources/Ongeul-Bridging-Header.h"
OBJC_SOURCES_DIR="$PROJECT_ROOT/OngeulApp/Sources"

# Obj-C 소스 컴파일
clang -c \
    -target "$APPLE_TARGET" \
    -isysroot "$SDK_PATH" \
    -fobjc-arc \
    "$OBJC_SOURCES_DIR/ObjCExceptionCatcher.m" \
    -o "$BUILD_DIR/ObjCExceptionCatcher.o"

# Swift 소스 파일 수집
SWIFT_SOURCES=(
    "$GENERATED_DIR/Rshangul.swift"
    "$PROJECT_ROOT/OngeulApp/Sources/main.swift"
    "$PROJECT_ROOT/OngeulApp/Sources/OngeulInputController.swift"
)

swiftc \
    -target "$APPLE_TARGET" \
    -sdk "$SDK_PATH" \
    -import-objc-header "$BRIDGING_HEADER" \
    -L "$LIB_DIR" -lrshangul \
    -framework Cocoa -framework InputMethodKit \
    -module-name Ongeul \
    "${SWIFT_SOURCES[@]}" \
    "$BUILD_DIR/ObjCExceptionCatcher.o" \
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
cp "$PROJECT_ROOT/OngeulApp/Resources/AppIcon.icns" "$APP_CONTENTS/Resources/"

# 로컬라이제이션 파일 복사
for lang in ko en; do
    mkdir -p "$APP_CONTENTS/Resources/${lang}.lproj"
    cp "$PROJECT_ROOT/OngeulApp/Resources/${lang}.lproj/"*.strings \
       "$APP_CONTENTS/Resources/${lang}.lproj/"
done

echo "    Bundle: $APP_BUNDLE"
echo "    Resources:"
ls "$APP_CONTENTS/Resources/"

# ── 5. 코드 서명 (ad-hoc) ──

echo "=== [5/5] Code signing (ad-hoc) ==="

codesign --force --sign - "$APP_BUNDLE"

echo "=== Build complete ==="
echo "    $APP_BUNDLE"
