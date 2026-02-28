#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
UNIVERSAL_DIR="$BUILD_DIR/universal"
UNIVERSAL_APP="$UNIVERSAL_DIR/Ongeul.app"
PKG_SCRIPTS="$PROJECT_ROOT/scripts/pkg"
PKG_RESOURCES="$PKG_SCRIPTS/resources"

# 인자가 있으면 사용, 없으면 Info.plist에서 추출
VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$PROJECT_ROOT/OngeulApp/Resources/Info.plist")}"

echo "=== Ongeul $VERSION Universal Package Build ==="
echo ""

# ── 1. 사전 검증 ──

echo "=== [1/6] Checking prerequisites ==="

if ! rustup target list --installed | grep -q x86_64-apple-darwin; then
    echo "Error: x86_64-apple-darwin target is not installed."
    echo "Install with: rustup target add x86_64-apple-darwin"
    exit 1
fi

echo "    All prerequisites satisfied."

# ── 2. 양쪽 아키텍처 빌드 ──

echo "=== [2/6] Building aarch64 ==="
"$PROJECT_ROOT/scripts/build.sh" aarch64-apple-darwin
echo ""

echo "=== [3/6] Building x86_64 ==="
"$PROJECT_ROOT/scripts/build.sh" x86_64-apple-darwin
echo ""

# ── 3. Universal 바이너리 조합 ──

echo "=== [4/6] Creating universal binary ==="

ARM64_APP="$BUILD_DIR/aarch64-apple-darwin/Ongeul.app"
X86_64_APP="$BUILD_DIR/x86_64-apple-darwin/Ongeul.app"

rm -rf "$UNIVERSAL_APP"
mkdir -p "$UNIVERSAL_DIR"
cp -R "$ARM64_APP" "$UNIVERSAL_APP"

lipo -create \
    "$ARM64_APP/Contents/MacOS/Ongeul" \
    "$X86_64_APP/Contents/MacOS/Ongeul" \
    -output "$UNIVERSAL_APP/Contents/MacOS/Ongeul"

echo "    Universal binary:"
file "$UNIVERSAL_APP/Contents/MacOS/Ongeul"

# 앱 번들 Info.plist에 버전 반영
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    "$UNIVERSAL_APP/Contents/Info.plist"

# ── 4. 코드 서명 (ad-hoc) ──

echo "=== [5/6] Code signing (ad-hoc) ==="

codesign --force --sign - "$UNIVERSAL_APP"

# ── 5. .pkg 생성 ──

echo "=== [6/6] Building installer package ==="

# pkgbuild: 컴포넌트 패키지
# --root는 앱 번들 자체가 아닌 앱 번들을 담는 디렉토리를 가리켜야 함
PKG_ROOT="$BUILD_DIR/pkg-root"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT"
cp -R "$UNIVERSAL_APP" "$PKG_ROOT/"

pkgbuild \
    --root "$PKG_ROOT" \
    --component-plist "$PKG_SCRIPTS/component.plist" \
    --identifier io.github.hiking90.inputmethod.Ongeul \
    --version "$VERSION" \
    --install-location "/Library/Input Methods" \
    --scripts "$PKG_SCRIPTS" \
    "$BUILD_DIR/Ongeul-component.pkg"

# productbuild: 배포용 패키지
productbuild \
    --distribution "$PKG_SCRIPTS/distribution.xml" \
    --package-path "$BUILD_DIR" \
    --resources "$PKG_RESOURCES" \
    "$BUILD_DIR/Ongeul-$VERSION.pkg"

# 임시 파일 정리
rm -f "$BUILD_DIR/Ongeul-component.pkg"
rm -rf "$PKG_ROOT"

echo ""
echo "=== Package build complete ==="
echo "    $BUILD_DIR/Ongeul-$VERSION.pkg"
echo ""
echo "설치 테스트:"
echo "    open $BUILD_DIR/Ongeul-$VERSION.pkg"
