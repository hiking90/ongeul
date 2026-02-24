#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/build/Ongeul.app"
INSTALL_DIR="$HOME/Library/Input Methods"

# ── 1. 빌드 ──

echo "=== Building Ongeul ==="
"$PROJECT_ROOT/scripts/build.sh"
echo ""

# ── 2. 기존 프로세스 종료 ──

echo "=== Stopping existing Ongeul process ==="
killall Ongeul 2>/dev/null || true
sleep 1

# ── 3. 기존 앱 제거 후 복사 ──

echo "=== Installing to $INSTALL_DIR ==="
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/Ongeul.app"
cp -r "$APP_BUNDLE" "$INSTALL_DIR/"

echo "=== Installation complete ==="
echo ""
echo "다음 단계:"
echo "  1. 최초 설치 시 로그아웃 후 재로그인이 필요합니다."
echo "  2. 시스템 설정 → 키보드 → 입력 소스 → 편집... → + → Ongeul 추가"
echo "  3. (권장) ABC 등 다른 입력 소스를 제거하고 Ongeul만 사용"
echo "  4. (권장) 'Caps Lock으로 ABC 입력 소스 전환' 옵션 비활성화"
echo ""
echo "로그 확인:"
echo "  log stream --predicate 'process == \"Ongeul\"' --level debug"
