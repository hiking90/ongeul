# 32. HID 기반 CapsLock 입력 처리 (짧게 / 길게 분리)

> **상태**: 설계 v2 — Phase 1.5 스파이크 결과 대기

## Context

[30. CapsLock LED 기반 한영 모드 동기화](30-capslock-mode-sync.md)는 `IOHIDSetModifierLockState`로 LED와 입력 모드를 양방향 SET하는 의미론을 정의했다(2차 검토 완료, 구현 대기). 본 문서는 그 기반 위에서 **macOS 플랫폼 표준 동작과의 parity** — *"CapsLock 짧은 탭 = 입력 소스 전환, 길게 누름 = 본연 대문자 잠금"* — 을 Ongeul에 도입하는 설계를 다룬다.

이 짧게/길게 분리는 fringe 기능이 *아니다*. macOS 입력 소스 설정의 *"Use Caps Lock to switch to and from U.S."* 옵션 본문은 Apple 자체 UI 문구로 다음을 명시한다:

> **"Press and hold to enable typing in all uppercase."**

한국어/일본어 macOS 사용자는 Sierra(2016) 이래 이 패턴에 학습돼 있고, SokIM·구름·Apple 기본 Korean IM이 모두 이 규약을 따른다. **현재 Ongeul의 "길게 = 미지원" 입장이 플랫폼 표준에서 벗어난 쪽**이며, 본 doc은 그 격차를 메운다.

단일 CGEvent 레이어로는 **물리 키의 press 지속시간을 측정할 수 없으므로** (`flagsChanged`는 잠금-상태 토글 통지만 전달), HID(IOHIDManager) 레이어를 추가 도입한다.

### 비-목표

- 모든 키 입력을 HID로 받는 SokIM/Karabiner 스타일 IME로의 전환 — 아키텍처 손상이 크고 충돌 위험 증가.
- 본연 CapsLock 대문자를 Ongeul 자체 엔진으로 합성 — `(B)` 기능을 위해 입력 전체 경로를 바꾸는 것은 비례성 어긋남. (단, [§ 스파이크](#스파이크-계획) 결과 B면 영문 통과 경로에 한정 합성을 *후속 추가*하는 폴백은 열어둠.)

## 가장 큰 단일 가정 — 스파이크 우선

본 설계 전체는 **하나의 미검증 가정** 위에 서 있다:

> *"`IOHIDSetModifierLockState(handle, kIOHIDCapsLockState, true)` 호출 후, 후속 keyDown들이 alpha-shift 적용된(대문자) 문자로 macOS 텍스트 입력 경로를 통해 앱에 전달된다."*

근거와 우려:

- [doc 30](30-capslock-mode-sync.md)의 실측표(2026-03-21, macOS 26.3.0)에서 `IOHIDSetModifierLockState`는 **상태 변경 + LED 변경** 모두 성공으로 기록됨. 단 *"alpha-lock이 켜진 동안 실제 키 입력이 대문자로 들어가는지"*는 직접 검증 항목으로 명시되지 않았다.
- 반증 정황: [SokIM](https://github.com/kiding/SokIM)은 본연 CapsLock 활성화 의도로 `setKeyboardCapsLock(enabled: true)`를 호출하지만, 본체([Helpers.swift](https://github.com/kiding/SokIM/blob/main/SokIM/Helpers.swift))는 `enabled` 값과 무관하게 `IOHIDSetModifierLockState(..., false)` + `HIS_XPC_SetCapsLockModifierState(false)`를 호출한다. 시스템 상태를 ON으로 두지 못해 LED만 ON하고 자체 `QwertyEngine`으로 대문자를 합성하는 방식. OS가 외부 상태 변경을 되돌리는 것에 대비해 false-set을 `0, 20, …, 180ms` 11회 반복 예약하며 주석에 *"HIS_XPC: Sonoma 이후 커서 밑에 생기는 '버블'/HUD/Indicator/Accessory 방지"* 라 명시.
- `IOHIDSetModifierLockState(true)`가 단순·신뢰성 있게 동작한다면 SokIM이 그런 우회를 할 이유가 없다.

→ **결론**: 본 doc의 구현 검증 전 *반드시* 다음 스파이크가 선행되어야 한다 (상세는 [§ 스파이크 계획](#스파이크-계획)).

선택지 매트릭스 (스파이크 결과에 따른 분기):

| 결과 | 옵션 | 함의 |
|---|---|---|
| `IOHIDSetModifierLockState(true)` → 앱이 대문자 수신 | **A** | 본 doc 그대로 진행 |
| 상태/LED는 켜지나 앱은 소문자 수신 | **B** | 영문 통과 경로에 *uppercase override* 합성 추가. HID는 여전히 press 지속시간 감지에만 사용 |
| 상태/LED 자체가 외부 stomp에 의해 즉시 되돌려짐 | **C** | 이 doc 보류. (B) 기능 미지원 유지 — HID는 짧은 탭 신뢰성·#10 race 차단 용도로만 한정 채택할지 별도 판단 |

본 문서 이하 내용은 결과 **A** 가정. **B**가 되면 § 기존 코드 통합 절의 일부만 교체(영문 통과 경로에 대문자 합성). **C**면 doc 폐기.

## 목표

| | |
|---|---|
| (1) | CapsLock **짧은 탭** → 한/영 토글 (현행 유지, 무지연) |
| (2) | CapsLock **길게 누름(≥800ms)** → 본연 CapsLock 대문자 ON, 한/영 토글 억제 (**macOS native parity**) |
| (3) | 본연 CapsLock ON 상태에서 **짧은 탭** → CapsLock OFF만 (한/영 토글 없음) |
| (4) | #10 race를 단일 권위 드라이버(HID)로 좁힘 |
| (5) | 옵트인 — `toggleKey != .capsLock` 사용자에겐 영향·권한 부담 없음 |

## 왜 CGEvent로는 부족한가 (요지)

CapsLock은 macOS 표준 이벤트 모델에서 **잠금 모디파이어**다. CGEventTap·`NSEvent.flagsChanged` 레이어는 *alpha-lock 상태가 토글됐다는 통지*만 전달한다. 물리 키의 down/up 분리 이벤트와 hardware timestamp가 모두 노출되지 않으므로, **press 지속시간을 측정할 방법이 없다**.

반면 HID(USB HID Usage Tables) 레이어에서 CapsLock은 Keyboard/Keypad usage `0x39`이고, IOHIDManager의 input value 콜백은 raw make(1)/break(0)을 **`IOHIDValueGetTimeStamp`로 얻는 하드웨어 타임스탬프와 함께** 보고한다. SokIM이 본 메커니즘으로 800ms 길게-누름을 구현하고 있는 것이 작동 증명.

## HID 도입의 부수 효과 (사용자 안내 단순화)

본 도입의 추가 가치 — HID 레이어는 **macOS의 시스템 Caps Lock 지연(약 100–250ms)보다 아래** 에 있어, 사용자가 `hidutil property --set '{"CapsLockDelayOverride":0}'` 같은 명령으로 시스템 지연을 비활성화하지 *않아도* 모든 물리 press를 raw로 받는다(SokIM이 사용자 지연 설정과 무관하게 동작하는 것이 증거).

기존 [docs/.../capslock.md](../docs/src/user/features/capslock.md) 는 *"시스템 설정에서 CapsLock 지연을 비활성화"* 라고 안내하지만:

1. **그런 시스템 UI는 존재하지 않는다** (Sequoia/Tahoe 모두 없음).
2. 유일한 합법 경로는 `hidutil` CLI이며 재부팅 시 초기화 (영구화는 LaunchAgent 필요).
3. **HID 활성 상태에서는 이 안내 자체가 불필요해진다.**

→ Phase 3에서 capslock.md를 갱신하여, *HID 모드에선 권한 부여만 하면 끝 / CGEventTap 폴백 모드에서만 `hidutil` 안내* 로 분리. (스파이크 측정 항목 #6에서 *"HID 콜백이 시스템 Caps Lock 지연과 무관하게 도착하는지"* 1차 검증.)

## Doc 30과의 관계

doc 32는 doc 30을 *대체하지 않는다*. 분업:

| 책임 | 모듈 | 출처 |
|---|---|---|
| LED/상태 양방향 SET, 재진입 가드(`expectedState` + 100ms 타임아웃) | `CapsLockSync` | doc 30 |
| 모드 ↔ LED 동기화 (모든 모드 변경 경로) | `InputStateCoordinator.setMode(_, syncCapsLock:)` | doc 30 |
| `TICapsLockLanguageSwitchCapable` 제거 | Info.plist | doc 30 (현재 코드 확인: 이미 없음) |
| **CapsLock press 짧게/길게 분리** | `CapsLockHIDMonitor` (신규) | **doc 32** |
| **본연 CapsLock 활성화 (`setState(true)`)** | `CapsLockSync` API는 doc 30이 정의, doc 32는 호출자 | **doc 32** |
| **CGEventTap CapsLock 분기의 게이팅(HID 활성 시 우회)** | `KeyEventTap` 수정 | **doc 32** |
| TCC UX 시트(권한 안내·딥링크) | `OngeulInputController` 설정 패널 | **doc 32** |

doc 30이 정의한 SET 의미론(*"LED ON = 한글"*)은 **CGEventTap 폴백 모드(HID 미활성)에서만 유효**하고, HID 모드(hidToggleAuthority/hidRealLockOn)에서는 **LED가 *본연 CapsLock 활성 여부* 만을 표현**한다. 이유: HID 모드에선 길게-누름이 진짜 Caps Lock을 켤 수 있으므로 LED가 두 의미를 가지면(Korean indicator vs Caps Lock 활성) 사용자에게 ambiguous. macOS 표준 의미("LED ON = 대문자 잠금")와 정합하도록 *LED = realLockOn 표시 전용*으로 통일. 모드 indicator는 메뉴바 아이콘이 담당.

## 옵트인 게이팅

HID 모니터는 다음 조건에서만 기동·유지:

```
toggleKey == .capsLock  AND  사용자가 입력 모니터링 권한 부여
```

전환 키가 다른 값이면 HID 모니터는 즉시 정지·해제. 다른 전환 키 사용자는 본 doc의 모든 코드 경로·권한 요구에 노출되지 않는다.

### 매칭 범위 — CapsLock만

```swift
IOHIDManagerSetDeviceMatching(hid, [
    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
] as CFDictionary)

IOHIDManagerSetInputValueMatching(hid, [
    kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,  // 0x07
    kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock      // 0x39
] as CFDictionary)
```

> **솔직한 한계**: 매칭은 콜백 수신 범위만 좁힌다. **TCC(Input Monitoring) 권한 요구 자체는 동일** — 권한은 앱 단위로 부여되며, "CapsLock만 모니터" 같은 부분 권한은 존재하지 않는다.

### 생명주기

- 앱 기동 / IMK `activateServer` 시점에서 `toggleKey == .capsLock`이면 `CapsLockHIDMonitor.start()` 시도.
- 설정 UI에서 전환 키가 `.capsLock`으로 변경되는 순간 시작, 다른 값으로 변경되는 순간 정지.
- `NSWorkspace.didWakeNotification` / `screensDidWakeNotification` → 재시작.

## 단일 상태 — `CapsLockMode` enum

직전 검토에서 3개 플래그(`isActive`/`realCapsLockActive`/`suppressCapsLockModeSync`)는 사실 한 상태머신을 세 곳에 나눠놓은 형태로 식별됨. **단일 enum으로 통합**한다.

```swift
enum CapsLockMode {
    /// HID 모니터 미활성 (toggleKey != .capsLock, 권한 미부여, 충돌 등).
    /// 기존 CGEventTap 경로가 권위. doc 30 SET 의미론 그대로 동작.
    case cgEventTapAuthority

    /// HID 모니터 활성, 짧은 탭 모드.
    /// HID가 press/release 감지, 임계 미만이면 한/영 토글.
    case hidToggleAuthority

    /// HID 모니터 활성, 길게-누름으로 본연 CapsLock 진입 상태.
    /// alpha-lock 시스템 상태 ON 유지. 다음 짧은 탭에서 OFF로 환원.
    case hidRealLockOn
}
```

모듈별 해석:

| 모듈 | 동작 |
|---|---|
| `KeyEventTap` flagsChanged CapsLock 분기 (doc 30) | `current == .cgEventTapAuthority` 일 때만 실행 |
| `KeyEventTap` keyDown `.maskAlphaShift` strip ([PR #11](https://github.com/hiking90/ongeul/pull/11)) | `current != .hidRealLockOn` 일 때만 실행 (본연 잠금 중엔 대문자 통과) |
| `InputStateCoordinator.setMode` LED 동기화 (doc 30) | `current == .cgEventTapAuthority` 일 때만 LED set. HID 모드(toggleAuthority/realLockOn)에선 LED 미동기화 — LED는 realLockOn 전용 indicator |
| `CapsLockHIDMonitor` | 자기 자신이 상태 변경의 권위. 시작/정지/타이머 발화/short tap/long press 시 `current`를 변경 |

상태 전이:

```
cgEventTapAuthority  ──HID start success──▶  hidToggleAuthority
hidToggleAuthority   ──HID stop / fail──▶   cgEventTapAuthority
hidToggleAuthority   ──long press fire──▶   hidRealLockOn
hidRealLockOn        ──next short tap──▶    hidToggleAuthority
hidRealLockOn        ──HID fail/stop──▶     cgEventTapAuthority  (+ LED off)
```

## 상태머신 — HID 콜백 본체

```
        ┌─────────────────────────────────────────────┐
        │   [CapsOFF]                                 │
        │     │ HID: keyDown(0x39)                    │
        │     │   ├─ start 800ms timer                │
        │     │   ├─ CapsLockSync.setState(false)     │
        │     │   │  (doc 30 expectedState 가드 적용) │
        │     │   └─ pressTimestamp = HID ts          │
        │     ▼                                       │
        │   [Pressing]                                │
        │     │                                       │
        │     ├─ HID: keyUp(0x39) (timer 아직)        │
        │     │     → coordinator.toggleMode()        │
        │     │       (HID 모드: LED 미동기화 — 항상 OFF) │
        │     │       복귀 ─▶ [CapsOFF]                │
        │     │                                       │
        │     └─ Timer 발화 (keyDown 유지 중)         │
        │           ├─ CapsLockMode = .hidRealLockOn  │
        │           ├─ CapsLockSync.setState(true)    │
        │           │  (LED ON, 모드 불변)            │
        │           └─ 복귀 ─▶ [CapsON]                │
        │                                             │
        │   [CapsON]                                  │
        │     └─ HID: keyDown(0x39)                   │
        │          ├─ CapsLockMode = .hidToggleAuth.  │
        │          ├─ CapsLockSync.setState(false)    │
        │          └─ 토글 안 함                       │
        │             복귀 ─▶ [CapsOFF]                │
        └─────────────────────────────────────────────┘
```

| 현재 | 입력 | 동작 | 다음 LED |
|---|---|---|---|
| CapsOFF | 짧은 탭 (< 800ms) | toggleMode (HID 모드라 LED 미동기화 — 모드만 변경) | OFF |
| CapsOFF | 길게 (≥ 800ms) | `setState(true)` + 토글 억제 + mode=`hidRealLockOn` | **ON** (realLockOn 표시) |
| CapsON | 짧은 탭 | exitRealCapsLock — `setState(false)` + mode=`hidToggleAuthority` + 진입직전 모드 복원, 토글 안 함 | OFF |
| CapsON | 길게 | 짧은 탭과 동일 — `setState(false)` + 종료 | OFF |

> **LED 의미**: HID 모드에서 LED는 *본연 CapsLock 활성 여부* 만 표현(=`hidRealLockOn` 상태). macOS 표준 의미와 일치, 사용자 혼란 방지. 모드 표시는 메뉴바 아이콘이 담당.

## 임계값 — 800ms 하드코딩

**값**: `800ms`. 하드코딩, 설정 UI 미노출.

**근거**:
- SokIM이 출하 검증한 값. 사용자에게 익숙한 reference.
- 짧은 탭(통상 50–200ms)과 명확 분리 → 오발동 거의 0.
- 사용자 설정 노출의 조정 비용 < 단일 값 단순성. 단일 값으로 두고 필요 시 후속에서 조정.

**solid한 trade-off**:
- macOS 네이티브 *"Press and hold"* 동작은 시스템 Caps Lock 지연(~100–250ms) 위에서 동작 → 사용자가 macOS 기본 IM에서 익숙해진 *체감 임계*는 800ms보다 짧다. 즉 800ms는 **SokIM-parity**이지 **macOS-parity**가 아님. 의도된 보수성(오발동 < 반응성). SokIM 사용자에게는 익숙하지만, macOS 네이티브 사용 경험과는 약간의 *길게 느낌* 차이 발생.

**시스템 값 매칭은 채택하지 않음**:
- macOS는 Caps Lock 지연을 사용자 UI로 노출하지 않음 (`hidutil` CLI 전용).
- 99%의 사용자는 Apple 디폴트 상태 → "사용자 시스템 값" 매칭은 사실상 "Apple 디폴트 매칭"에 수렴.
- 디폴트 값 자체가 정확한 공식 수치 없음(외부 보고 100ms vs 250ms 엇갈림).

## 기존 코드와의 통합

### `CapsLockHIDMonitor.swift` (신규)

```swift
final class CapsLockHIDMonitor {
    static let shared = CapsLockHIDMonitor()

    /// 통합 상태. KeyEventTap·InputStateCoordinator가 읽기-전용으로 참조.
    private(set) var mode: CapsLockMode = .cgEventTapAuthority

    private var hid: IOHIDManager?
    private var longPressTimer: DispatchWorkItem?

    weak var coordinator: InputStateCoordinator?
    weak var controller: OngeulInputController?

    /// 800ms — SokIM 출하 검증값.
    private static let longPressThresholdMs: Int = 800

    /// 시작. 성공 시 mode=.hidToggleAuthority. 권한·충돌 실패 시 throws.
    func start() throws { /* IOHIDManagerCreate + 매칭 + 콜백 + Open */ }
    func stop() { /* close + unschedule + mode=.cgEventTapAuthority */ }
    func restart() { stop(); try? start() }

    /// 콜백 본체 (자세한 의사코드는 § 상태머신 참조).
    fileprivate func onValue(_ value: IOHIDValue) {
        let usage = IOHIDElementGetUsage(IOHIDValueGetElement(value))
        guard usage == kHIDUsage_KeyboardCapsLock else { return }
        let isDown = IOHIDValueGetIntegerValue(value) != 0

        if isDown {
            if mode == .hidRealLockOn {
                exitRealCapsLock()
                return
            }
            scheduleLongPressTimer()
            CapsLockSync.setState(false)
        } else { // keyUp
            longPressTimer?.cancel()
            if mode == .hidRealLockOn { return }
            DispatchQueue.main.async { [controller] in
                controller?.performToggleFromTap()
            }
        }
    }

    private func scheduleLongPressTimer() {
        let work = DispatchWorkItem { [weak self] in self?.enterRealCapsLock() }
        longPressTimer = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.longPressThresholdMs),
            execute: work
        )
    }

    private func enterRealCapsLock() {
        mode = .hidRealLockOn
        CapsLockSync.setState(true)
    }

    private func exitRealCapsLock() {
        mode = .hidToggleAuthority
        CapsLockSync.setState(false)
    }
}
```

### `KeyEventTap.swift` 수정

```swift
// flagsChanged 분기 (doc 30이 추가)
if type == .flagsChanged && keyCode == Int64(KeyCode.capsLock)
    && KeyEventTap.toggleKey == .capsLock
    && CapsLockHIDMonitor.shared.mode == .cgEventTapAuthority {  // 게이트
    // ... 기존 doc 30 로직 (CapsLockSync.shouldHandle + performCapsLockModeSet) ...
}

// keyDown 방어 ([PR #11](https://github.com/hiking90/ongeul/pull/11))
if KeyEventTap.toggleKey == .capsLock
    && flags.contains(.maskAlphaShift) {
    if CapsLockHIDMonitor.shared.mode == .hidRealLockOn {
        // 본연 CapsLock ON 중에는 strip·setState 호출 자체를 면제 → 대문자 통과
    } else {
        CapsLockSync.setState(false)
        flags.subtract(.maskAlphaShift)
        event.flags = flags
    }
}
```

### `InputStateCoordinator.swift` 수정

doc 30의 `setMode(_, syncCapsLock:)`에 본 doc의 게이트 한 줄:

```swift
private func setMode(_ mode: InputMode, syncCapsLock: Bool = true) {
    engine.setMode(mode: mode)
    KeyEventTap.currentInputMode = mode
    if syncCapsLock
        && KeyEventTap.toggleKey == .capsLock
        && CapsLockHIDMonitor.shared.mode != .hidRealLockOn {  // 본연 잠금 중 LED 건드리지 않음
        CapsLockSync.setState(mode == .korean)
    }
}
```

### `OngeulInputController.swift` 수정

- `okClicked` 흐름에서 toggleKey 전이 감지 → [§ TCC UX 시트](#tcc--ux-안내-시트) 호출.
- `applicationDidFinishLaunching` / `activateServer`에서 toggleKey 확인 → HID 모니터 `start()` 시도, 실패 시 헬스 배너 갱신.
- `CapsLockHIDMonitor.shared.controller`에 self 주입.

## TCC / UX 안내 시트

### 권한 요구

| 권한 | TCC 서비스 | 위치 |
|---|---|---|
| 입력 모니터링 (신규) | `kTCCServiceListenEvent` | 개인정보 보호 및 보안 → 입력 모니터링 |
| 손쉬운 사용 (현행) | `kTCCServiceAccessibility` | 개인정보 보호 및 보안 → 손쉬운 사용 |

### 결손 권한 있을 때만 시트 표시 (게이팅)

매번 다이얼로그를 띄우지 않는다. 두 권한 모두 부여돼 있으면 조용히 진행:

```swift
import IOKit.hid
import ApplicationServices

private enum Perm {
    static var inputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    static var accessibility: Bool { AXIsProcessTrusted() }
}

// okClicked, toggleKey 전이 시
let missingInput  = !Perm.inputMonitoring
let missingAccess = !Perm.accessibility

if !missingInput && !missingAccess {
    // 둘 다 부여돼 있음 → 다이얼로그 생략, 즉시 활성
    commitSetting()
    try? CapsLockHIDMonitor.shared.start()
} else {
    presentCapsLockPermissionSheet(
        missingInput: missingInput,
        missingAccess: missingAccess,
        on: preferencesPanel,
        onConfirm: {
            commitSetting()
            try? CapsLockHIDMonitor.shared.start()
        },
        onCancel: { revertToggleKey() }
    )
}
```

`IOHIDCheckAccess`는 프롬프트 트리거 없이 상태만 조회. `IOHIDAccessType.unknown`은 *결손으로 간주* (보수적 디폴트).

### 다이얼로그 — 결손 종류에 따라 동적 구성

| 결손 | 표시 |
|---|---|
| 둘 다 부여돼 있음 | 다이얼로그 없음, 즉시 활성 |
| 입력 모니터링만 결손 (가장 흔함) | 본문 1줄 + 버튼 *"입력 모니터링 설정 열기"* / *"취소"* |
| 손쉬운 사용만 결손 (이론상) | 본문 1줄 + 버튼 *"손쉬운 사용 설정 열기"* / *"취소"* |
| 둘 다 결손 | 본문 2줄 + 버튼 *"입력 모니터링 설정 열기"* / *"손쉬운 사용 설정 열기"* / *"취소"* |

딥링크:

```swift
NSWorkspace.shared.open(URL(string:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
)!)
NSWorkspace.shared.open(URL(string:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
)!)
```

> **Tahoe 검증 항목**: 위 URL 앵커가 *Privacy & Security 루트가 아니라 정확히 해당 하위 페인까지* 깊이 들어가는지 1분 스파이크. 실패 시 다이얼로그 본문에 수동 경로 텍스트(*"개인정보 보호 및 보안 → 입력 모니터링"*) 함께 표기.

### 상시 헬스체크 배너

- `toggleKey == .capsLock`인데 HID 모니터 `start()` 실패(`kIOReturnNotPermitted` 등) 지속 → 메뉴바 아이콘 옆 작은 경고 또는 메뉴 항목 *"CapsLock 모드: 입력 모니터링 권한 필요"* + 같은 딥링크 버튼.
- `activateServer` 호출마다 `start()` 재시도. 성공하면 배너 제거.
- 권한 부여는 macOS가 앱에 통지하지 않음 → 폴링/재시도 패턴이 표준.

### 폴백

| 실패 사유 | 동작 |
|---|---|
| 권한 미부여 (`kIOReturnNotPermitted`) | `mode = .cgEventTapAuthority`. doc 30 CGEventTap 경로 그대로 동작 (짧은 탭 한/영 전환만). (B) 길게-누름 미지원. 사용자가 *오늘보다 나빠지지 않음*. |
| 다른 HID 모니터와 충돌 (`kIOReturnExclusiveAccess`) | 동일 폴백 + *"다른 키보드 모니터링 앱과 충돌"* 안내. Karabiner 호환 분기는 MVP에서 보류. |
| HID 콜백 침묵 (절전 복귀 등) | `NSWorkspace.didWakeNotification`에서 `restart()`. |

폴백 경로에서도 [PR #11](https://github.com/hiking90/ongeul/pull/11)의 keyDown strip이 작동 → #10 가시 증상은 닫혀 있다.

## 서명·공증 선결조건 (Phase 4 의존성)

[16. 샌드박스와 코드 서명](50-sandbox-and-signing.md)에 정의된 Developer ID + 공증 파이프라인은 본 doc 채택 시 **준 필수**.

- 현재 [build.sh:165](../scripts/build.sh)·[package.sh:67](../scripts/package.sh)·[release.yml](../.github/workflows/release.yml) 모두 `codesign --force --sign -` (ad-hoc) — 공증 없음.
- ad-hoc 서명에서 TCC는 designated requirement 불안정 → **업데이트/재빌드마다 입력 모니터링 권한이 풀리는 사용자 사례 빈발**. 매번 제거→재추가 UX는 장기 채택 차단 요인.
- 손쉬운 사용은 [install.sh:63-86](../scripts/install.sh)이 SIP-off 환경에서 TCC.db 직접 주입 우회 중. 입력 모니터링도 SIP-off에서 동일 우회 가능, **일반 사용자 해법 아님**.

→ 본 doc 32 정식 배포는 **doc 50 (Developer ID + 공증) 도입과 한 묶음** 권고. 분리 배포 시 한계를 capslock.md에 명시.

개발/repro 단계에선 install.sh의 SIP-off TCC 자동부여 로직을 `kTCCServiceListenEvent`로 확장하면 e2e 테스트 가능.

## 다른 HID 모니터와의 충돌

| 시나리오 | 동작 |
|---|---|
| SokIM·구름·Karabiner-Elements 미설치 | HID 단독 권위. 정상. |
| SokIM 등 비-seize HID 모니터 공존 | IOHIDManagerOpen `0` (비-seize)는 충돌하지 않음. 양쪽이 `IOHIDSetModifierLockState` 등으로 같은 상태를 다투면 race 잔존 — Ongeul은 본연 잠금 의도가 분명한 시점(`hidRealLockOn`)에만 `setState(true)` 호출하므로 충돌 가능성은 좁힘. |
| Karabiner-Elements 가상 HID 드라이버 | SokIM은 시리얼 매칭 호환 분기 채택. MVP에선 미지원 — 폴백 + 안내. |

## 동작 시나리오

| # | 상황 | 결과 |
|---|---|---|
| 1 | OFF 상태에서 짧게 탭 (전환 키=CapsLock, HID 정상) | HID keyDown → 타이머 시작 + `setState(false)`. keyUp이 임계 전 → `toggleMode()` → 엔진 모드만 토글 (HID 모드에선 LED 미동기화 — LED는 OFF 유지). PR #11 strip 정상. |
| 2 | OFF 상태에서 800ms 이상 보유 | 타이머 발화 → `mode=.hidRealLockOn` + `setState(true)`. 한/영 토글 안 함. 이후 keyDown들은 strip 면제 → 대문자가 앱에 전달 (스파이크 결과 A 가정). |
| 3 | ON 상태에서 짧게 탭 | `mode == .hidRealLockOn` 확인 → `exitRealCapsLock()` → `setState(false)` + `mode=.hidToggleAuthority`. 토글 안 함. |
| 4 | ON 상태에서 한/영 모드가 다른 경로(우커맨드 탭 등)로 변경 | `setMode`가 HID 모드 가드에 막혀 LED 안 건드림 — 사용자가 켠 본연 CapsLock LED 유지. |
| 5 | 권한 미부여 | `start()` `kIOReturnNotPermitted` throws → `mode=.cgEventTapAuthority` 유지 → doc 30 CGEventTap 경로. 메뉴바 배너 + 딥링크. (B) 미지원. |
| 6 | SokIM과 공존 | HID open 성공(비-seize). 양측 상태 set 시도가 겹치면 race — `hidRealLockOn` 시점에만 set ON하므로 일상 짧은 탭은 안전. 사용자 안내 권고. |
| 7 | 절전 → 복귀 | `didWakeNotification` → `CapsLockHIDMonitor.restart()`. |
| 8 | 전환 키를 CapsLock→우커맨드로 변경 | `okClicked`에서 `stop()` + `CapsLockSync.reset()` + LED OFF. TCC 권한은 시스템에 남되 모니터는 정지. |
| 9 | 우커맨드→CapsLock 변경 | UX 시트 (권한 결손 시) 또는 즉시 활성 (권한 둘 다 있음) → `start()`. |
| 10 | 본연 CapsLock ON 상태에서 IME 전환(앱 변경) | `mode=.hidRealLockOn` 그대로 유지 (전역). macOS Caps Lock 의미론 매칭. |
| 11 | 암호 필드 진입 (Secure Input) | doc 30 시나리오와 동일. HID 콜백은 계속 들어오지만 `controller.isCurrentAppLocked`/`IsSecureEventInputEnabled` 체크로 coordinator 호출 억제. |
| 12 | `hidRealLockOn` 상태에서 사용자가 권한 회수 | HID 콜백 중단. 헬스체크가 회수를 탐지하면 `CapsLockSync.setState(false)` + `mode=.cgEventTapAuthority`로 환원. |

## 스파이크 계획

목표: § 가장 큰 단일 가정의 A/B/C 분기 결정.

### 환경

- 우선 [Sequoia repro VM](../README.md) (`ongeul-sequoia`).
- **Tahoe(macOS 26.x) repro 환경 신규 구축 필수** — 제보자 환경, 현재 미커버.

### 측정 항목 (6개)

1. **상태 set + 입력 검증**: stand-alone 작은 Cocoa 앱에서 `IOHIDSetModifierLockState(service, kIOHIDCapsLockState, true)` 호출 → 직후 키보드로 `a`. NSTextField가 `A`? `a`?
2. **다양한 대상 앱**: TextEdit·Safari·Terminal·Xcode·Electron 1개 — 텍스트 입력 경로 차이 확인.
3. **LED 검증**: 호출 후 외부 키보드 LED 켜지는가? (내장 키보드는 LED 없음)
4. **`CGEventSourceFlagsState(.combinedSessionState).contains(.maskAlphaShift)`**: 즉시 true?
5. **stomp 검증**: 호출 후 1~2초 관찰. OS가 외부 요인으로 false로 되돌리는가? SokIM 11회 반복 패턴의 현재 OS 유효성.
6. **HID 콜백이 시스템 Caps Lock 지연과 무관하게 도착하는가?** `hidutil property --set CapsLockDelayOverride 250` 설정 후 짧은 탭 — HID 모니터가 받는가? (받는다면 사용자에게 `hidutil` 안내 불필요화 가능.)
7. **`CapsLockSync.shouldHandle()` 100ms 타임아웃의 OS 부하 민감성**: 정상 환경에선 `IOHIDSetModifierLockState` 후 echo `flagsChanged`가 1~10ms 내 도착해 `expectedState` 가드가 정확히 동작하지만, 무거운 VM/CI/저성능 환경에서 echo가 100ms 이상 지연되면 가드가 만료되어 echo를 *사용자 입력*으로 오인 → spurious 토글 발생. 측정: 인위적 부하(`stress-ng -c N` 등) 상태에서 mode 변경 → echo 도착 시간 분포 측정. 디폴트 100ms로 부족하면 doc 30·doc 32의 `expectedStateTimeout`을 상향 검토 (단, 사용자가 임계 안에 CapsLock을 누를 물리적 한계와 균형).

### 예상 시간

- Tahoe VM 구축: 1~2시간
- 스파이크 코드 작성 + 두 OS 측정 + 관찰: 4~6시간
- **총 5~8시간**

### 결과별 분기

- **A**: 대문자 전달 OK → 본 doc 그대로 Phase 2 진행.
- **B**: LED/상태 OK, 앱은 소문자 → 영문 통과 경로에 *uppercase override* 합성 추가 (KeyEventTap의 영문 모드 keyDown post 또는 IMK handle 단계에서 `.uppercased()` 변환). HID 도입 의의는 유지.
- **C**: stomp 활발, 안정성 부족 → 본 doc 보류. HID는 *짧은 탭 신뢰성만* 한정 채택할지 별도 판단.

## 수정·신규 파일

| 파일 | 종류 | 변경 |
|---|---|---|
| `OngeulApp/Sources/CapsLockHIDMonitor.swift` | 신규 | 본 doc § 기존 코드 통합 본체 |
| `OngeulApp/Sources/CapsLockMode.swift` | 신규 | enum 정의 (또는 `CapsLockHIDMonitor.swift` 내 nested) |
| `OngeulApp/Sources/CapsLockSync.swift` | 수정 | doc 30: `setState(true/false)` + `expectedState` 가드 |
| `OngeulApp/Sources/KeyEventTap.swift` | 수정 | flagsChanged CapsLock 분기에 `mode == .cgEventTapAuthority` 게이트, keyDown strip에 `mode != .hidRealLockOn` 게이트 |
| `OngeulApp/Sources/InputStateCoordinator.swift` | 수정 | `setMode`에 `syncCapsLock` + `mode != .hidRealLockOn` 게이트, `toggleEngineMode` 동기화 |
| `OngeulApp/Sources/OngeulInputController.swift` | 수정 | `okClicked` 전이 감지 + TCC 시트, HID start 트리거, 헬스 배너, `performCapsLockModeSet` |
| `OngeulApp/Resources/Localizable.strings` (ko/en) | 수정 | 시트·배너 문구 |
| `OngeulApp/Resources/Info.plist` | (확인) | `TICapsLockLanguageSwitchCapable` 이미 없음. `NSInputMonitoringUsageDescription` IMK 적용성 검증 필요 |
| `docs/src/user/features/capslock.md` | 수정 | (B) 길게-누름 지원 명시, 권한 안내, `hidutil` 정정(폴백 한정) |
| `scripts/install.sh` | 수정 | SIP-off TCC 자동부여를 `kTCCServiceListenEvent`로 확장 (개발 한정) |

## 단계화

| Phase | 내용 | 의존 |
|---|---|---|
| **0 (완료)** | [PR #11](https://github.com/hiking90/ongeul/pull/11): CGEventTap keyDown strip — #10 가시 증상 hardening | — |
| **0.5** | Tahoe repro VM 구축 | 인프라 작업 |
| **1** | doc 30 구현 (`CapsLockSync.setState/expectedState` + `setMode(syncCapsLock:)` + KeyEventTap flagsChanged 분기 + `performCapsLockModeSet`) | — |
| **1.5** | 본 doc 스파이크 — A/B/C 결정 | Phase 0.5 |
| **2** | 본 doc 구현 (`CapsLockHIDMonitor` + `CapsLockMode` enum + 게이팅 + TCC 시트 + 헬스 배너) | Phase 1, 1.5 (결과 A 또는 B) |
| **3** | 문서 정정 ([capslock.md](../docs/src/user/features/capslock.md): `hidutil` 정정, 길게-누름 지원 명시; HID 모드에서 `hidutil` 안내 불필요 분리) | Phase 2 |
| **4** | Developer ID + 공증 ([doc 50](50-sandbox-and-signing.md)) | Phase 2와 한 묶음 권고 |

> **PR 직렬화**: 각 Phase의 PR은 *이전 단계가 main에 머지된 후* 베이스를 잡는다 ([메모리: PR base trap](https://github.com/hiking90/ongeul/issues/7)). Phase 1과 Phase 1.5는 독립 — 병행 가능.

## 미해결 / 후속 검토

1. **`hidRealLockOn`의 영속성**: 앱 전환 시 전역 ON 유지로 결정([§ 동작 시나리오](#동작-시나리오) #10). macOS Caps Lock 의미론과 일치하며 사용자 멘탈 모델과도 합치. *전역* 결정으로 doc 32 확정.
2. **HID 콜백 침묵 자동 복구**: SokIM `restartIfIdle()` 패턴 도입 여부. idle 임계와 false positive 검토.
3. **`IOHIDSetModifierLockState` Tahoe 동작 차이**: 스파이크에서 정밀화.
4. **`NSInputMonitoringUsageDescription` IMK 적용성**: ~~미검증~~ → **검증됨 (필수)**. 이 키가 Info.plist에 없으면 `IOHIDManagerOpen` 호출이 TCC 리스트에 앱을 *등록조차 시키지 못함* (시스템 설정 → 입력 모니터링에 앱이 안 보임). on-demand 등록 흐름이 무력화되어 사용자가 권한 부여 자체를 할 수 없는 막다른 상태가 됨. **현재 [`OngeulApp/Resources/Info.plist`](../OngeulApp/Resources/Info.plist)에 `NSAccessibilityUsageDescription`과 함께 추가됨**. IMK 앱이 표준 TCC 프롬프트를 띄우지 못하는 한계는 여전 → 우리 시트 + 딥링크 경로 유지.
5. **다중 키보드 동시**: 두 키보드의 CapsLock 거의 동시 누름 시 상태머신 일관성 검증.
6. **이슈 #10과의 연결**: 본 doc 채택 후 #10 환경 원인(SokIM 공존 / Tahoe race) 중 무엇이 실제였는지 사후 회고 필요. PR #11으로 충분히 닫혔는지, 본 doc 구현 후에야 닫히는지 분리 검증.
7. **`CapsLockSync.expectedState` 단일 변수 덮어쓰기 race**: 빠른 연속 `setState()` 호출(예: `loadLayout` 직후 `activateApp` 같은 init 시퀀스, 또는 `enterRealCapsLock`의 `setState(true)`가 직전 `setState(false)` echo 도착 전에 일어나는 경우) 시 이전 `expectedState`가 덮어써져 *#1의 echo가 #2의 expected와 불일치 → `shouldHandle()`이 사용자 입력으로 오인 → spurious 토글* 가능. doc 30의 100ms 타임아웃은 echo 미도착만 처리하고 덮어쓰기는 막지 못함. 실제 발생 조건은 5ms 내 두 번의 mode-set이라 좁지만 0은 아님. 견고한 해결은 `expectedState`를 *큐* 구조로 두고 echo 도착 시 oldest와 매칭하는 것 — 복잡도 증가로 doc 32 범위 외, 후속 RFC. 스파이크 측정 항목 #7(OS 부하 민감성)에서 함께 확인 가치.

---

## 참고

- [30. CapsLock LED 기반 한영 모드 동기화](30-capslock-mode-sync.md)
- [50. 샌드박스와 코드 서명](50-sandbox-and-signing.md)
- [capslock-hangul-toggle.md](capslock-hangul-toggle.md) — 가장 초기의 CapsLock 검토
- [PR #11 — fix(capslock): strip stale maskAlphaShift on keyDown](https://github.com/hiking90/ongeul/pull/11)
- [이슈 #10](https://github.com/hiking90/ongeul/issues/10)
- [SokIM `InputMonitor.swift`](https://github.com/kiding/SokIM/blob/main/SokIM/InputMonitor.swift) — IOHIDManager + 800ms 길게-누름 참조 구현
- [SokIM `Helpers.swift`](https://github.com/kiding/SokIM/blob/main/SokIM/Helpers.swift) — `setKeyboardCapsLock` 본체 (LED-only + Sonoma stomp 대응 패턴)
- Apple Input Sources 설정 옵션: *"Use the Caps Lock key to switch to and from U.S. **Press and hold to enable typing in all uppercase**."*
