# 패키징

`scripts/package.sh`로 universal `.pkg` 설치 파일을 생성합니다.

## 사전 준비

Intel(x86_64) 타겟이 설치되어 있어야 합니다:

```bash
rustup target add x86_64-apple-darwin
```

## 패키지 생성

```bash
./scripts/package.sh
```

결과물: `build/Ongeul-<version>.pkg`

## 빌드 과정

`package.sh`는 다음 단계를 수행합니다:

1. **사전 검증**: x86_64 타겟 설치 확인
2. **aarch64 빌드**: `build.sh aarch64-apple-darwin`
3. **x86_64 빌드**: `build.sh x86_64-apple-darwin`
4. **Universal 바이너리**: `lipo`로 양쪽 아키텍처 바이너리를 합침
5. **코드 서명**: ad-hoc 서명
6. **패키지 생성**: `pkgbuild` → `productbuild`

## 패키지 구조

```
scripts/pkg/
  distribution.xml     # Installer 설정 (제목, 요구사항, 설치 옵션)
  resources/
    welcome.html       # 설치 시작 화면
    conclusion.html    # 설치 완료 화면
  postinstall          # 설치 후 스크립트
```

### distribution.xml

- 설치 대상: macOS 14.0 이상
- 아키텍처: x86_64, arm64
- 설치 위치: `/Library/Input Methods` (시스템) 또는 `~/Library/Input Methods` (사용자)

## 코드 서명 및 공증

Developer ID 인증서가 있는 경우, 배포 전에 코드 서명과 공증을 수행할 수 있습니다:

```bash
# 코드 서명
codesign --force --sign "Developer ID Application: <이름>" build/universal/Ongeul.app

# 패키지 서명
productsign --sign "Developer ID Installer: <이름>" \
    build/Ongeul-<version>.pkg \
    build/Ongeul-<version>-signed.pkg

# 공증
xcrun notarytool submit build/Ongeul-<version>-signed.pkg \
    --apple-id <Apple ID> \
    --team-id <Team ID> \
    --password <앱 전용 비밀번호> \
    --wait
```

공증이 완료되면 Gatekeeper 경고 없이 설치할 수 있습니다.
