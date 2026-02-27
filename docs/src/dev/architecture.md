# 아키텍처

Ongeul은 **Rust 엔진 + Swift 프론트엔드** 하이브리드 구조입니다.

## 전체 구조

```
┌─────────────────────────────────┐
│  OngeulApp (Swift)              │
│  macOS InputMethodKit 연동      │
│  모드 인디케이터, 설정 UI        │
└──────────┬──────────────────────┘
           │ UniFFI (FFI)
┌──────────▼──────────────────────┐
│  rshangul (Rust)                │
│  한글 조합 오토마타              │
│  자모 합성/분해, 유니코드 처리   │
│  키보드 레이아웃 파서            │
└─────────────────────────────────┘
```

### rshangul (Rust)

한글 조합의 **모든 로직**을 담당합니다. Swift 쪽에는 한글 처리 로직이 전혀 없습니다.

- `HangulEngine`: UniFFI로 노출되는 공개 API 객체
- `ProcessResult`: 키 처리 결과 (committed text, composing text, handled flag)
- `EngineState`: 레이아웃과 오토마타를 관리하는 내부 상태
- `InputMode`: 영문(English) / 한글(Korean) 모드

### OngeulApp (Swift)

macOS InputMethodKit과의 연동만 담당하는 **얇은 셸**입니다.

- `OngeulInputController`: IMKInputController 구현
  - 키 이벤트 수신 → Rust 엔진에 위임 → 결과 적용
  - 한/영 전환 키 감지 (flagsChanged)
  - 앱별 모드 저장/복원
  - 영문 잠금 관리
- 모드 인디케이터 (NSPanel)
- 설정 다이얼로그

### UniFFI

[Mozilla UniFFI](https://mozilla.github.io/uniffi-rs/)를 통해 Rust와 Swift를 연결합니다. `HangulEngine`의 메서드들이 Swift에서 직접 호출 가능한 형태로 자동 생성됩니다.

## 키 이벤트 처리 흐름

```
1. macOS  →  키 이벤트 발생 (NSEvent)
2. Swift  →  OngeulInputController.handle(event:client:) 수신
3. Swift  →  전환 키 확인 (Cmd/Shift+Space)
4. Swift  →  engine.process_key(keyCode, char, shift) 호출
5. Rust   →  현재 모드에 따라 처리
              English → 문자 그대로 반환
              Korean  → 오토마타로 한글 조합
6. Rust   →  ProcessResult 반환 (committed, composing, handled)
7. Swift  →  결과를 IMKTextInput에 적용
              committed → insertText
              composing → setMarkedText
```

## 한글 조합 오토마타

### 두벌식 6단계 상태 머신

```
Empty → Choseong → Jungseong → Jungseong2 → Jongseong → Jongseong2
```

- 초성 입력 → 중성 입력 시 조합 시작
- 종성 입력 후 모음이 오면 종성을 다음 음절의 초성으로 분리
- 겹받침(ㄳ, ㄺ 등) 뒤에 모음이 오면 겹받침을 분리

### 세벌식

초성, 중성, 종성이 키보드에서 분리되어 있어 위치(position) 기반으로 처리합니다.
