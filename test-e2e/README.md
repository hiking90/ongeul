# E2E 테스트 (CGEvent 기반)

실제 키보드 이벤트를 주입하여 Ongeul IME 파이프라인 전체를 검증한다.

## 요구 사항

- **SIP 비활성화** — TCC.db 수동 수정에 필요
- **Accessibility 권한** — CGEventPost(키 주입) + AXUIElement(결과 읽기)
- **GUI 세션** — 로그인된 데스크톱 환경
- **Ongeul 설치 및 활성화** — 입력 소스로 등록

> 호스트 Mac의 보안을 유지하려면 **Tart VM**에서 실행을 권장한다.

## 아키텍처

호스트에서 빌드하고, VM에는 빌드 결과물만 전달하여 테스트한다. VM에는 Rust 툴체인이 불필요하다.

```
호스트 Mac                          Tart VM
─────────                          ────────
./scripts/build.sh                 (마운트된 디렉토리 접근)
    ↓                                  ↓
build/Ongeul.app  ──── --dir ────→  ~/ongeul/build/Ongeul.app
                                       ↓
                                   cp → ~/Library/Input Methods/
                                   Accessibility 권한 설정
                                   swift test-e2e/run_e2e.swift
```

## Tart VM 초기 설정 (최초 1회)

### 호스트에서

```bash
# 1. Tart 설치
brew install cirruslabs/cli/tart

# 2. macOS VM 이미지 생성
tart create ongeul-e2e --from-ipsw latest

# 3. VM 실행
tart run ongeul-e2e
```

### VM 내부 설정

```bash
# 1. Recovery Mode 부팅 → SIP 비활성화
#    Apple 메뉴 → 재시동 → 전원 버튼 길게 → Options → Terminal
csrutil disable
# 재부팅

# 2. 기본 환경
sudo pmset -a displaysleep 0 sleep 0    # 슬립 비활성화
# 시스템 설정 → 사용자 및 그룹 → 자동 로그인 활성화

# 3. Xcode Command Line Tools 설치 (swift 실행에 필요)
xcode-select --install

# 4. E2E 테스트 러너에 Accessibility 권한 부여
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAccessibility', '/usr/bin/swift', 1, 2, 3, 1, NULL, NULL, NULL, 'UNUSED', NULL, 0, CAST(strftime('%s','now') AS INTEGER));"
sudo killall tccd 2>/dev/null || true
```

설정 완료 후 이 상태를 기본 이미지로 보존한다 (VM 종료).

## E2E 테스트 실행 (매번)

### 1. 호스트에서 빌드

```bash
cd ~/ongeul   # 또는 프로젝트 경로
./scripts/build.sh
```

### 2. VM 실행 및 테스트

```bash
# 호스트에서: 깨끗한 VM 복사본 생성 + 프로젝트 디렉토리 마운트
tart clone ongeul-e2e ongeul-e2e-run
tart run --dir=ongeul:~/ongeul ongeul-e2e-run
```

```bash
# VM 내부에서:

# Ongeul 설치 (호스트에서 빌드된 앱 복사)
ARCH="$(uname -m)"
case "$ARCH" in
    arm64)  TARGET="aarch64-apple-darwin" ;;
    x86_64) TARGET="x86_64-apple-darwin" ;;
esac
killall Ongeul 2>/dev/null || true
mkdir -p "$HOME/Library/Input Methods"
rm -rf "$HOME/Library/Input Methods/Ongeul.app"
cp -r ~/ongeul/build/$TARGET/Ongeul.app "$HOME/Library/Input Methods/"

# Ongeul 앱에 Accessibility 권한 부여
BUNDLE_ID="io.github.hiking90.inputmethod.Ongeul"
APP="$HOME/Library/Input Methods/Ongeul.app"
REQ_STR=$(codesign -d -r- "$APP" 2>&1 | awk -F ' => ' '/designated/{print $2}')
CSREQ_VALUE="NULL"
if [ -n "$REQ_STR" ]; then
    CSREQ_TMP=$(mktemp)
    if echo "$REQ_STR" | csreq -r- -b "$CSREQ_TMP" 2>/dev/null; then
        REQ_HEX=$(xxd -p "$CSREQ_TMP" | tr -d '\n')
        CSREQ_VALUE="X'${REQ_HEX}'"
    fi
    rm -f "$CSREQ_TMP"
fi
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAccessibility', '${BUNDLE_ID}', 0, 2, 3, 1, ${CSREQ_VALUE}, NULL, NULL, 'UNUSED', NULL, 0, CAST(strftime('%s','now') AS INTEGER));"
sudo killall tccd 2>/dev/null || true

# 최초 설치 시: 로그아웃/로그인 → 시스템 설정에서 Ongeul 입력 소스 추가

# E2E 테스트 실행
swift ~/ongeul/test-e2e/run_e2e.swift
```

```bash
# 호스트에서: 테스트 완료 후 VM 삭제
tart delete ongeul-e2e-run
```

### Accessibility 권한 요약

| 주체 | 용도 | 부여 시점 |
|------|------|----------|
| **Ongeul 앱** | KeyEventTap (Shift+Space) | 매번 설치 시 (코드 서명이 바뀌므로) |
| **테스트 러너** (`/usr/bin/swift`) | CGEventPost + AXUIElement | 초기 설정 시 1회 |

## 테스트 목록

| # | 테스트 | 검증 내용 |
|---|--------|----------|
| 1 | 한글 단어 "한글" | 기본 2벌식 조합 |
| 2 | 겹받침 분리 "갑시" | 종성→초성 분리 |
| 3 | 겹모음 "과" | 이중 모음 조합 |
| 4 | 쌍자음 "빠" | Shift 키 조합 |
| 5 | Right Command 모드 전환 | modifier tap → flush + 영문 전환 |
| 6 | 백스페이스 | 조합 상태 역행 |
| 7 | Shift+Space 전환 | CGEventTap 가로채기 |
| 8 | ESC → 영문 전환 | flush + 모드 전환 |
| 9 | 연속 한글 문장 | 공백 구분 다단어 |
| 10 | 빈 상태 백스페이스 | 빈 상태 안정성 |

## 호스트 Mac에서 직접 실행

SIP 비활성화 + Accessibility 권한이 있으면 VM 없이 직접 실행 가능:

```bash
swift test-e2e/run_e2e.swift
```

단, 테스트 중 키 주입이 현재 포커스된 앱에 영향을 주므로 **테스트 실행 중에는 다른 작업을 하지 않아야 한다.**
