#!/bin/bash
set -euo pipefail

# 로컬 릴리스: universal .pkg를 서명·공증한 뒤 GitHub Release로 발행한다.
#
# 서명은 **이 Mac에서만** 한다. Developer ID 개인 키를 CI에 두면, 시크릿에 넣든
# 아니든 서명이 도는 동안 키가 GitHub 소유 러너에 평문으로 존재한다. GitHub Actions
# 시크릿은 영지식이 아니라 복호화 키를 GitHub이 쥐고 있다. 키가 유출되어 Apple이
# 인증서를 폐기하면 이미 설치된 사용자들의 Ongeul까지 Gatekeeper가 막는다.
# release.yml은 태그에 맞춰 문서만 배포한다.
#
# 사용법:
#     ./scripts/release.sh v0.4.0-rc1
#
# 사전 준비 (최초 1회):
#     xcrun notarytool store-credentials ongeul-notary \
#         --apple-id <Apple ID> --team-id <Team ID> --password <앱 전용 비밀번호>
#     export ONGEUL_SIGN_ID="Developer ID Application: ... (<Team ID>)"
#     export ONGEUL_INSTALLER_ID="Developer ID Installer: ... (<Team ID>)"
#     export ONGEUL_NOTARY_PROFILE="ongeul-notary"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <tag>     (예: $0 v0.4.0-rc1)" >&2
    exit 1
fi

TAG="$1"
[[ "$TAG" == v* ]] || TAG="v$TAG"
VERSION="${TAG#v}"

# 태그에 '-'가 있으면 pre-release로 발행한다 (rc가 "Latest"를 차지하지 않도록).
# 배열이 아닌 문자열인 이유: macOS는 bash 3.2라 set -u 아래에서 빈 배열을
# "${arr[@]}"로 펼치면 unbound variable로 죽는다. 빈 문자열은 비인용 전개 시
# 인자가 그냥 사라지므로 이 경우에 안전하다.
PRERELEASE_FLAG=""
[[ "$VERSION" == *-* ]] && PRERELEASE_FLAG="--prerelease"

echo "=== Ongeul $VERSION 릴리스 ==="
echo ""

# ── 1. 사전 검증 ──
#
# 서명·공증은 수 분이 걸리므로, 실패할 조건은 전부 여기서 먼저 걸러낸다.

echo "=== [1/5] Preflight ==="

fail() { echo "Error: $*" >&2; exit 1; }

for tool in gh git-cliff xcrun; do
    command -v "$tool" > /dev/null || fail "$tool 이 없습니다."
done
gh auth status > /dev/null 2>&1 || fail "gh 인증이 안 돼 있습니다. 'gh auth login'을 먼저 실행하세요."

[[ -n "${ONGEUL_SIGN_ID:-}" ]] \
    || fail "ONGEUL_SIGN_ID가 없습니다 (Developer ID Application). 서명 없이는 릴리스하지 않습니다."
[[ -n "${ONGEUL_INSTALLER_ID:-}" ]] \
    || fail "ONGEUL_INSTALLER_ID가 없습니다 (Developer ID Installer). .pkg 서명에 필요합니다."
if [[ -z "${ONGEUL_NOTARY_PROFILE:-}" && -z "${ONGEUL_NOTARY_KEY_PATH:-}" ]]; then
    fail "공증 자격 증명이 없습니다. ONGEUL_NOTARY_PROFILE을 설정하세요 (파일 상단 참고)."
fi

git -C "$PROJECT_ROOT" diff-index --quiet HEAD -- \
    || fail "작업 트리가 깨끗하지 않습니다. 릴리스는 커밋된 상태에서만 만듭니다."

git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/$TAG" > /dev/null \
    || fail "태그 $TAG 가 없습니다. 먼저 'git tag $TAG && git push origin $TAG'."

# 태그가 origin에 없으면 문서 배포 워크플로가 돌지 않았다는 뜻이다.
git -C "$PROJECT_ROOT" ls-remote --exit-code --tags origin "$TAG" > /dev/null 2>&1 \
    || fail "태그 $TAG 가 origin에 없습니다. 'git push origin $TAG' 먼저."

# 태그가 지금 체크아웃된 커밋을 가리키는지 — 다른 커밋을 릴리스하는 사고 방지.
[[ "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" == "$(git -C "$PROJECT_ROOT" rev-parse "$TAG^{commit}")" ]] \
    || fail "HEAD가 $TAG 와 다른 커밋입니다. 'git checkout $TAG' 후 다시 실행하세요."

gh release view "$TAG" > /dev/null 2>&1 \
    && fail "릴리스 $TAG 가 이미 있습니다. 지우고 다시 하려면 'gh release delete $TAG'."

echo "    OK — $TAG @ $(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
echo ""

# ── 2. 빌드 + 서명 + 공증 ──

echo "=== [2/5] Building, signing, notarizing ==="
"$PROJECT_ROOT/scripts/package.sh" "$VERSION"
echo ""

PKG_FILE="$BUILD_DIR/Ongeul-$VERSION.pkg"
[[ -f "$PKG_FILE" ]] || fail "$PKG_FILE 이 만들어지지 않았습니다."

# ── 3. Gatekeeper 검증 ──
#
# 서명·공증·stapling이 모두 성공했는지 사용자와 같은 방식으로 확인한다.
# package.sh가 공증을 건너뛰었어도 여기서 잡힌다.

echo "=== [3/5] Verifying with Gatekeeper ==="
if ! SPCTL_OUT=$(spctl -a -vvv -t install "$PKG_FILE" 2>&1); then
    echo "$SPCTL_OUT" >&2
    fail "Gatekeeper가 거부했습니다. 공증·stapling을 확인하세요."
fi
echo "$SPCTL_OUT" | sed 's/^/    /'
echo ""

# ── 4. 릴리스 노트 ──

echo "=== [4/5] Generating changelog ==="
NOTES=$(cd "$PROJECT_ROOT" && git-cliff --latest --strip header)
SHA256=$(shasum -a 256 "$PKG_FILE" | awk '{print $1}')
DOCS_VERSION="${VERSION%%-*}"
DOCS_URL="https://hiking90.github.io/ongeul/${DOCS_VERSION}/user/installation.html"
FOOTER=$(printf '\n\n---\n📖 [설치 가이드](%s)\n**SHA-256:** `%s`\nVerify: `shasum -a 256 Ongeul-%s.pkg`' \
    "$DOCS_URL" "$SHA256" "$VERSION")
echo "    $(echo "$NOTES" | wc -l | tr -d ' ') lines"
echo ""

# ── 5. 발행 ──

echo "=== [5/5] Publishing GitHub Release ==="
# shellcheck disable=SC2086  # 위 주석 참고 — 비면 인자가 사라져야 한다
gh release create "$TAG" "$PKG_FILE" \
    --title "Ongeul ${VERSION}" \
    --notes "${NOTES}${FOOTER}" \
    $PRERELEASE_FLAG

echo ""
echo "=== Release published ==="
gh release view "$TAG" --json url --jq .url
