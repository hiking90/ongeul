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

echo "=== [1/7] Checking prerequisites ==="

if ! rustup target list --installed | grep -q x86_64-apple-darwin; then
    echo "Error: x86_64-apple-darwin target is not installed."
    echo "Install with: rustup target add x86_64-apple-darwin"
    exit 1
fi

echo "    All prerequisites satisfied."

# ── 2. 양쪽 아키텍처 빌드 ──

echo "=== [2/7] Building aarch64 ==="
"$PROJECT_ROOT/scripts/build.sh" aarch64-apple-darwin
echo ""

echo "=== [3/7] Building x86_64 ==="
"$PROJECT_ROOT/scripts/build.sh" x86_64-apple-darwin --skip-bindgen
echo ""

# ── 3. Universal 바이너리 조합 ──

echo "=== [4/7] Creating universal binary ==="

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

# ── 4. 코드 서명 ──
#
# ONGEUL_SIGN_ID(Developer ID Application)가 있으면 hardened runtime과 함께 서명한다.
# hardened runtime은 공증의 전제 조건이다 (design 50).
# 없으면 ad-hoc으로 떨어지며, 그 산출물은 Gatekeeper 우회 없이는 설치되지 않는다.
#
# 중첩 바이너리가 없는 번들이라 --deep 없이 번들 하나만 서명하면 된다
# (Resources는 전부 데이터). lipo가 arm64 빌드의 서명을 깨뜨리므로 여기서 다시 서명한다.

if [[ -n "${ONGEUL_SIGN_ID:-}" ]]; then
    echo "=== [5/7] Code signing (Developer ID) ==="
    echo "    Identity: $ONGEUL_SIGN_ID"
    codesign --force --timestamp --options runtime \
        --entitlements "$PROJECT_ROOT/OngeulApp/Ongeul.entitlements" \
        --sign "$ONGEUL_SIGN_ID" "$UNIVERSAL_APP"
    codesign --verify --strict --verbose=2 "$UNIVERSAL_APP"
else
    echo "=== [5/7] Code signing (ad-hoc) ==="
    echo "    WARNING: ONGEUL_SIGN_ID is unset — the package will not pass Gatekeeper."
    codesign --force --sign - "$UNIVERSAL_APP"
fi

# ── 5. .pkg 생성 ──

echo "=== [6/7] Building installer package ==="

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
# .pkg 서명에는 앱과 **다른** 인증서(Developer ID Installer)가 필요하다.
# 앱만 서명하고 pkg를 빼면 설치 시점에 Gatekeeper가 다시 막는다.
PKG_OUT="$BUILD_DIR/Ongeul-$VERSION.pkg"
PRODUCTBUILD_ARGS=(
    --distribution "$PKG_SCRIPTS/distribution.xml"
    --package-path "$BUILD_DIR"
    --resources "$PKG_RESOURCES"
)
if [[ -n "${ONGEUL_INSTALLER_ID:-}" ]]; then
    echo "    Installer identity: $ONGEUL_INSTALLER_ID"
    PRODUCTBUILD_ARGS+=(--sign "$ONGEUL_INSTALLER_ID" --timestamp)
else
    echo "    WARNING: ONGEUL_INSTALLER_ID is unset — the .pkg will be unsigned."
fi
productbuild "${PRODUCTBUILD_ARGS[@]}" "$PKG_OUT"

# 임시 파일 정리
rm -f "$BUILD_DIR/Ongeul-component.pkg"
rm -rf "$PKG_ROOT"

# ── 6. 공증 (notarization) ──
#
# 공증 대상은 **.pkg**다. 앱만 공증하고 pkg를 빼면 설치가 차단된다.
# 자격 증명은 두 가지 중 하나를 쓴다:
#   - ONGEUL_NOTARY_PROFILE          : 로컬. `xcrun notarytool store-credentials`로 만든 키체인 프로필
#   - ONGEUL_NOTARY_KEY_{PATH,ID}    : CI. App Store Connect API 키(.p8) + ONGEUL_NOTARY_ISSUER_ID
# 둘 다 없으면 건너뛴다 (경고만). ONGEUL_SKIP_NOTARIZE=1로 명시적으로 끌 수도 있다.

echo "=== [7/7] Notarization ==="

NOTARY_ARGS=()
if [[ "${ONGEUL_SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "    Skipped (ONGEUL_SKIP_NOTARIZE=1)."
elif [[ -n "${ONGEUL_NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$ONGEUL_NOTARY_PROFILE")
elif [[ -n "${ONGEUL_NOTARY_KEY_PATH:-}" && -n "${ONGEUL_NOTARY_KEY_ID:-}" \
        && -n "${ONGEUL_NOTARY_ISSUER_ID:-}" ]]; then
    NOTARY_ARGS=(
        --key "$ONGEUL_NOTARY_KEY_PATH"
        --key-id "$ONGEUL_NOTARY_KEY_ID"
        --issuer "$ONGEUL_NOTARY_ISSUER_ID"
    )
else
    echo "    Skipped — no notarization credentials."
    echo "    The .pkg will be blocked by Gatekeeper on other machines."
fi

if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
    # --wait은 실패해도 0이 아닌 종료 코드를 내지 않는 경우가 있어 status를 직접 본다.
    xcrun notarytool submit "$PKG_OUT" "${NOTARY_ARGS[@]}" --wait --output-format json \
        > "$BUILD_DIR/notarize.json"
    NOTARY_STATUS=$(/usr/bin/plutil -extract status raw -o - "$BUILD_DIR/notarize.json" 2>/dev/null \
        || echo "unknown")
    echo "    Status: $NOTARY_STATUS"
    if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
        SUBMISSION_ID=$(/usr/bin/plutil -extract id raw -o - "$BUILD_DIR/notarize.json" 2>/dev/null || true)
        echo "    Notarization failed. Log:"
        [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" || true
        exit 1
    fi
    # stapling: 티켓을 pkg에 박아 오프라인에서도 Gatekeeper가 확인할 수 있게 한다.
    xcrun stapler staple "$PKG_OUT"
    xcrun stapler validate "$PKG_OUT"
    rm -f "$BUILD_DIR/notarize.json"
fi

echo ""
echo "=== Package build complete ==="
echo "    $PKG_OUT"
echo ""
echo "설치 테스트:"
echo "    open $PKG_OUT"
