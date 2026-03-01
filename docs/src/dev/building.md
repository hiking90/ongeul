# 빌드

## 요구사항

- **macOS 14.0** (Sonoma) 이상
- **Rust toolchain**: `aarch64-apple-darwin` 타겟 (기본 설치됨)
- **Xcode Command Line Tools**: `swiftc`, `clang`, `codesign` 등
- (선택) Intel 빌드를 위한 추가 타겟: `rustup target add x86_64-apple-darwin`

## 디렉토리 구조

```
ongeul-automata/       # Rust 한글 엔진
  src/
    lib.rs             # UniFFI 공개 API
    engine.rs          # 입력 모드, 키 처리
    automata/          # 한글 조합 상태 머신
    layout/            # 키보드 레이아웃 파서 (JSON5)
    unicode.rs         # 한글 유니코드 유틸리티
  layouts/             # 레이아웃 정의 파일 (JSON5)
  tests/               # 통합 테스트

OngeulApp/             # Swift macOS 프론트엔드
  Sources/
    main.swift         # IMKServer 초기화
    OngeulInputController.swift  # IMKInputController
  Generated/           # UniFFI 자동 생성 (빌드 시)
  Resources/           # Info.plist, 아이콘, 로컬라이제이션

scripts/
  build.sh             # 빌드 스크립트
  install.sh           # 빌드 + 설치
  package.sh           # universal .pkg 생성
  gen_icon.swift       # 메뉴바 아이콘 생성
```

## 빌드

```bash
# 기본 빌드 (Apple Silicon)
./scripts/build.sh

# Intel 타겟 빌드
./scripts/build.sh x86_64-apple-darwin
```

빌드 결과물은 `build/<target>/Ongeul.app`에 생성됩니다.

### 빌드 과정

`build.sh`는 다음 단계를 수행합니다:

1. **Rust 빌드**: `cargo build`로 `libongeul_automata.a` 정적 라이브러리 생성
2. **UniFFI 바인딩**: Rust 라이브러리에서 Swift 바인딩 코드 자동 생성
3. **Swift 컴파일**: `swiftc`로 Swift 소스 및 Obj-C 소스 컴파일
4. **앱 번들**: `Ongeul.app` 번들 구조 생성 (Info.plist, 리소스 복사)
5. **코드 서명**: ad-hoc 서명

## 테스트

```bash
cargo test -p ongeul-automata
```

유니코드 처리, 두벌식/세벌식 오토마타, 레이아웃 파서, 통합 테스트를 포함합니다.

## 설치

```bash
./scripts/install.sh
```

빌드 후 `~/Library/Input Methods/`에 설치합니다. 최초 설치 시 로그아웃/로그인이 필요합니다.

## 디버그 로그

```bash
log stream --predicate 'subsystem == "io.github.hiking90.inputmethod.Ongeul"'
```

## .pkg와 install.sh 중복 설치

`.pkg`로 설치하면 `/Library/Input Methods/`에, `install.sh`로 설치하면 `~/Library/Input Methods/`에 설치됩니다. 두 곳에 모두 설치된 경우 충돌이 발생할 수 있습니다.

한쪽의 `Ongeul.app`을 삭제하고 로그아웃/로그인하세요.

```bash
# .pkg 설치본 제거 (관리자 권한 필요)
sudo rm -rf "/Library/Input Methods/Ongeul.app"

# 또는 install.sh 설치본 제거
rm -rf ~/Library/Input\ Methods/Ongeul.app
```
