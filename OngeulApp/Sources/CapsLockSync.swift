import IOKit
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "capsLockSync")

// Private API declaration
@_silgen_name("IOHIDSetModifierLockState")
func IOHIDSetModifierLockState(_ handle: io_connect_t, _ selector: Int32, _ state: Bool) -> Int32

private let kIOHIDCapsLockState: Int32 = 1

/// CapsLock LED/상태를 IOHIDSystem 레벨에서 SET하는 래퍼.
///
/// [doc 30](../../../design/30-capslock-mode-sync.md)의 양방향 SET 의미론을 구현한다:
/// - 모드 변경 → `setState(mode == .korean)` → LED 동기화
/// - 사용자 CapsLock 누름 → `flagsChanged` 수신 → mode SET (호출자가 처리)
///
/// `IOHIDSetModifierLockState` 호출은 후속 `flagsChanged` echo를 발생시킬 수 있으므로,
/// 그 echo를 사용자 입력으로 오해하지 않도록 `expectedState` 가드를 둔다.
enum CapsLockSync {
    /// 소프트웨어가 설정한 예상 상태. `nil`이면 예상 대기 중 아님.
    private static var expectedState: Bool? = nil
    /// `expectedState` 설정 시각 (타임아웃 판정용).
    private static var expectedStateTimestamp: CFAbsoluteTime = 0
    /// `expectedState` 타임아웃 (100ms).
    /// `IOHIDSetModifierLockState` 호출 후 echo가 발생하지 않는 경우 `expectedState`가
    /// 영구히 남아 다음 사용자 CapsLock 입력을 한 번 무시하는 것을 방지한다.
    /// 사용자가 100ms 이내에 CapsLock을 누르는 것은 물리적으로 불가능하므로 안전.
    private static let expectedStateTimeout: CFAbsoluteTime = 0.1

    /// `IOHIDSetModifierLockState`로 CapsLock LED/상태 설정.
    /// 호출 후 발생하는 `flagsChanged` echo는 `shouldHandle()`에서 필터링된다.
    static func setState(_ enabled: Bool) {
        os_log("setState: %{public}d", log: log, type: .debug, enabled)
        expectedState = enabled
        expectedStateTimestamp = CFAbsoluteTimeGetCurrent()
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        )
        if service != IO_OBJECT_NULL {
            _ = IOHIDSetModifierLockState(service, kIOHIDCapsLockState, enabled)
            IOObjectRelease(service)
        }
    }

    /// `flagsChanged`에서 호출. 소프트웨어가 유발한 echo면 `false`(무시), 사용자 입력이면 `true`(처리).
    ///
    /// 타이밍 의존적인 `isSyncing` 플래그 대신 *예상 상태 비교* 방식을 쓴다:
    /// 소프트웨어가 설정한 상태와 도착한 이벤트가 일치하면 echo로 간주.
    /// 100ms 타임아웃은 echo가 발생하지 않는 경우의 안전망.
    static func shouldHandle(capsLockOn: Bool) -> Bool {
        guard let expected = expectedState else { return true }
        if CFAbsoluteTimeGetCurrent() - expectedStateTimestamp > expectedStateTimeout {
            expectedState = nil
            return true  // 타임아웃 → 사용자 입력으로 간주
        }
        if expected == capsLockOn {
            expectedState = nil  // 예상된 echo → 무시
            return false
        }
        expectedState = nil
        return true  // 예상과 다름 → 사용자 입력
    }

    /// 설정 변경 시 LED OFF + 상태 초기화.
    /// `toggleKey`를 `.capsLock`에서 다른 키로 변경할 때 호출.
    static func reset() {
        setState(false)
    }

    /// 하위 호환: 기존 호출자(설정 패널·KeyEventTap keyDown 방어 등)가 사용.
    /// 기능적으로 `setState(false)`와 동일.
    static func forceOff() {
        setState(false)
    }
}
