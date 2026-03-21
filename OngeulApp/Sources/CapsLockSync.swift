import IOKit
import ApplicationServices
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "capsLockSync")

// Private API declaration
@_silgen_name("IOHIDSetModifierLockState")
func IOHIDSetModifierLockState(_ handle: io_connect_t, _ selector: Int32, _ state: Bool) -> Int32

private let kIOHIDCapsLockState: Int32 = 1

enum CapsLockSync {
    /// 소프트웨어가 설정한 예상 상태. nil이면 예상 대기 중 아님.
    private static var expectedState: Bool? = nil
    /// expectedState 설정 시각 (타임아웃 판정용)
    private static var expectedStateTimestamp: CFAbsoluteTime = 0

    /// expectedState 타임아웃 (100ms).
    /// IOHIDSetModifierLockState 호출 후 flagsChanged가 발생하지 않는 경우,
    /// expectedState가 남아 다음 사용자 CapsLock 입력을 한 번 무시하는 것을 방지한다.
    private static let expectedStateTimeout: CFAbsoluteTime = 0.1

    /// IOHIDSetModifierLockState로 CapsLock LED 설정
    static func setState(_ enabled: Bool) {
        os_log("setState: enabled=%{public}d", log: log, type: .debug, enabled)
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

    /// flagsChanged에서 호출. 소프트웨어가 유발한 이벤트면 false, 사용자 입력이면 true.
    static func shouldHandle(capsLockOn: Bool) -> Bool {
        guard let expected = expectedState else {
            os_log("shouldHandle: capsLockOn=%{public}d → true (no expected)", log: log, type: .debug, capsLockOn)
            return true
        }

        // 타임아웃: flagsChanged가 발생하지 않은 경우 expectedState 자동 만료
        let elapsed = CFAbsoluteTimeGetCurrent() - expectedStateTimestamp
        if elapsed > expectedStateTimeout {
            expectedState = nil
            os_log("shouldHandle: capsLockOn=%{public}d → true (timeout %.0fms)", log: log, type: .debug, capsLockOn, elapsed * 1000)
            return true  // 타임아웃 → 사용자 입력으로 간주
        }

        if expected == capsLockOn {
            expectedState = nil  // 예상된 이벤트 → 무시
            os_log("shouldHandle: capsLockOn=%{public}d → false (expected match, filtered)", log: log, type: .debug, capsLockOn)
            return false
        }
        expectedState = nil
        os_log("shouldHandle: capsLockOn=%{public}d expected=%{public}d → true (mismatch)", log: log, type: .debug, capsLockOn, expected)
        return true  // 사용자 입력 → 처리
    }

    /// 현재 하드웨어 CapsLock 상태 읽기 (Public API)
    static func isHardwareOn() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    /// 설정 변경 시 LED OFF + 상태 초기화
    static func reset() {
        setState(false)
    }
}
