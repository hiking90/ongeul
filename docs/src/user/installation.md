# 설치

## .pkg 설치 (권장)

1. [GitHub Releases](https://github.com/hiking90/ongeul/releases) 페이지에서 최신 `.pkg` 파일을 다운로드합니다.
2. 다운로드한 `.pkg` 파일을 더블클릭합니다.
3. Installer의 안내에 따라 설치합니다.
   - **시스템 전체 설치**: `/Library/Input Methods`에 설치됩니다 (관리자 권한 필요).
   - **현재 사용자만**: `~/Library/Input Methods`에 설치됩니다.

### Gatekeeper 경고

공증(notarization)되지 않은 빌드의 경우 macOS Gatekeeper가 실행을 차단할 수 있습니다.

1. **시스템 설정** → **개인 정보 보호 및 보안** 으로 이동합니다.
2. 하단에 "Ongeul.app이(가) 차단되었습니다" 메시지를 확인합니다.
3. **확인 없이 열기** 를 클릭합니다.

## 소스에서 빌드

개발 환경에서 직접 빌드하려면 [빌드](../dev/building.md) 페이지를 참고하세요.

```bash
# 빌드 + 설치
./scripts/install.sh
```

## 요구사항

- macOS 14.0 (Sonoma) 이상
- Apple Silicon (aarch64) 또는 Intel (x86_64)
