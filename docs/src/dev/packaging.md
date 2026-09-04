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
5. **코드 서명**: `ONGEUL_SIGN_ID`가 있으면 Developer ID + hardened runtime, 없으면 ad-hoc
6. **패키지 생성**: `pkgbuild` → `productbuild` (`ONGEUL_INSTALLER_ID`가 있으면 서명)
7. **공증**: 자격 증명이 있으면 `notarytool submit --wait` → `stapler staple`

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

`package.sh`가 서명·공증·stapling까지 수행합니다. 환경 변수로 자격 증명을 넘기며,
설정하지 않으면 ad-hoc 서명으로 떨어져 로컬 테스트에는 그대로 쓸 수 있습니다
(단, 그 산출물은 다른 Mac에서 Gatekeeper에 막힙니다).

| 변수 | 용도 |
|------|------|
| `ONGEUL_SIGN_ID` | Developer ID **Application** identity (이름 또는 SHA-1 해시) |
| `ONGEUL_INSTALLER_ID` | Developer ID **Installer** identity — `.pkg` 서명용 |
| `ONGEUL_NOTARY_PROFILE` | `notarytool store-credentials`로 만든 키체인 프로필 이름 |
| `ONGEUL_SKIP_NOTARIZE` | `1`이면 공증 생략 |

인증서는 두 종류가 모두 필요합니다. 앱만 서명하고 `.pkg`를 빼면 설치 시점에 다시 막힙니다.

```bash
# 최초 1회: 공증 자격 증명을 키체인에 저장
xcrun notarytool store-credentials ongeul-notary \
    --apple-id <Apple ID> --team-id <Team ID> --password <앱 전용 비밀번호>

# identity 이름 확인
security find-identity -v | grep "Developer ID"

# 서명 + 공증까지 한 번에
export ONGEUL_SIGN_ID="Developer ID Application: <이름> (<Team ID>)"
export ONGEUL_INSTALLER_ID="Developer ID Installer: <이름> (<Team ID>)"
export ONGEUL_NOTARY_PROFILE="ongeul-notary"
./scripts/package.sh 0.4.0
```

hardened runtime(`--options runtime`)은 공증의 전제 조건이라 Developer ID 서명 시 항상
함께 켭니다.

> **서명 identity를 바꾸면 TCC 권한이 초기화됩니다.** macOS는 손쉬운 사용·입력 모니터링
> 부여를 코드 서명에 묶어 관리하므로, ad-hoc ↔ Developer ID를 오가면 그때마다 권한을
> 다시 줘야 합니다. 로컬 개발에서는 `ONGEUL_SIGN_ID`를 켜고 끄지 말고 하나로 고정하는
> 편이 편합니다.

### 릴리스

**서명·공증은 로컬에서만 합니다.** Developer ID 개인 키를 GitHub에 두지 않기 위해서입니다.
Actions 시크릿은 영지식이 아니고(복호화 키를 GitHub이 가집니다), 애초에 GitHub 호스티드
러너에서 서명하면 키가 그 VM에 평문으로 존재하게 됩니다. 키가 유출돼 Apple이 인증서를
폐기하면 이미 설치된 사용자들의 Ongeul까지 Gatekeeper가 막습니다.

`release.yml`은 태그에 맞춰 **문서만** 배포하며 시크릿을 쓰지 않습니다.

```bash
git tag v0.4.0-rc1 && git push origin v0.4.0-rc1   # 문서 배포 트리거
./scripts/release.sh v0.4.0-rc1                    # 빌드 → 서명 → 공증 → 발행
```

`release.sh`가 수행하는 일:

1. **사전 검증** — 도구(`gh`, `git-cliff`), 서명 환경 변수, 깨끗한 작업 트리,
   태그가 origin에 있고 HEAD와 같은 커밋인지, 같은 이름의 릴리스가 이미 없는지.
   서명·공증에 수 분이 걸리므로 실패 조건은 전부 여기서 걸러냅니다.
2. **빌드·서명·공증** — `package.sh` 호출
3. **Gatekeeper 검증** — `spctl -a -t install`이 통과해야 진행합니다.
   공증이나 stapling이 빠지면 여기서 멈춥니다.
4. **릴리스 노트** — `git-cliff --latest` + 설치 가이드 링크 + SHA-256
5. **발행** — `gh release create`. 태그에 `-`가 있으면 pre-release로 올려
   rc가 "Latest"를 차지하지 않게 합니다.
