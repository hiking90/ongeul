#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ARCH="$(uname -m)"
case "$ARCH" in
    arm64)  TARGET="aarch64-apple-darwin" ;;
    x86_64) TARGET="x86_64-apple-darwin" ;;
    *)
        echo "Error: Unknown architecture '$ARCH'"
        exit 1
        ;;
esac

APP_BUNDLE="$PROJECT_ROOT/build/$TARGET/Ongeul.app"
INSTALL_DIR="$HOME/Library/Input Methods"
SYSTEM_INSTALL="/Library/Input Methods/Ongeul.app"

# ── 1. 빌드 ──

echo "=== Building Ongeul ==="
"$PROJECT_ROOT/scripts/build.sh"
echo ""

# ── 2. 기존 프로세스 종료 ──

echo "=== Stopping existing Ongeul process ==="
killall Ongeul 2>/dev/null || true
sleep 1

# ── 3. 반대쪽 설치 정리 ──

if [ -d "$SYSTEM_INSTALL" ]; then
    echo "=== Removing system-wide installation ==="
    if sudo rm -rf "$SYSTEM_INSTALL"; then
        echo "    Removed: $SYSTEM_INSTALL"
    else
        echo "    Warning: Could not remove $SYSTEM_INSTALL (requires admin privileges)"
    fi
fi

# ── 4. 기존 앱 제거 후 복사 ──

echo "=== Installing to $INSTALL_DIR ==="
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/Ongeul.app"
cp -r "$APP_BUNDLE" "$INSTALL_DIR/"

# ── 5. 손쉬운 사용(Accessibility) 권한 설정 ──

BUNDLE_ID="io.github.hiking90.inputmethod.Ongeul"
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
INSTALLED_APP="$INSTALL_DIR/Ongeul.app"

echo "=== Setting up Accessibility permission ==="

# 앱이 재서명되면 기존 TCC 항목이 무효화되므로 리셋
sudo tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

SIP_STATUS=$(csrutil status 2>&1)
if echo "$SIP_STATUS" | grep -q "disabled"; then
    # SIP 비활성화 상태: sqlite3로 자동 권한 부여
    # 서명된 앱에서 csreq blob 생성
    CSREQ_VALUE="NULL"
    REQ_STR=$(codesign -d -r- "$INSTALLED_APP" 2>&1 | awk -F ' => ' '/designated/{print $2}')
    if [ -n "$REQ_STR" ]; then
        CSREQ_TMP=$(mktemp /tmp/ongeul_csreq.XXXXXX)
        if echo "$REQ_STR" | csreq -r- -b "$CSREQ_TMP" 2>/dev/null; then
            REQ_HEX=$(xxd -p "$CSREQ_TMP" | tr -d '\n')
            CSREQ_VALUE="X'${REQ_HEX}'"
        fi
        rm -f "$CSREQ_TMP"
    fi

    sudo sqlite3 "$TCC_DB" \
        "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAccessibility', '${BUNDLE_ID}', 0, 2, 3, 1, ${CSREQ_VALUE}, NULL, NULL, 'UNUSED', NULL, 0, CAST(strftime('%s','now') AS INTEGER));"

    # tccd 재시작으로 변경사항 반영
    sudo killall tccd 2>/dev/null || true

    echo "    Accessibility 권한이 자동으로 부여되었습니다."
else
    # SIP 활성화 상태: 수동 설정 안내
    echo "    SIP이 활성화되어 있어 자동 권한 부여가 불가합니다."
    echo "    시스템 설정 → 개인 정보 보호 및 보안 → 손쉬운 사용 에서"
    echo "    Ongeul을 추가하고 활성화해 주세요."
fi
echo ""

echo "=== Installation complete ==="
echo ""
echo "다음 단계:"
echo "  1. 최초 설치 시 로그아웃 후 재로그인이 필요합니다."
echo "  2. 시스템 설정 → 키보드 → 입력 소스 → 편집... → + → Ongeul 추가"
echo "  3. (권장) ABC 등 다른 입력 소스를 제거하고 Ongeul만 사용"
echo "  4. (권장) 'Caps Lock으로 ABC 입력 소스 전환' 옵션 비활성화"
echo ""
echo "로그 확인:"
echo "  log stream --predicate 'subsystem == \"io.github.hiking90.inputmethod.Ongeul\"'"
