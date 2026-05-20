import Foundation
import IOKit
import IOKit.hid
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "capsLockHID")

/// CapsLock 전용 HID 모니터의 권위 상태 — [doc 32](../../design/32-hid-capslock-press-duration.md) § 단일 상태.
///
/// 단일 enum으로 *HID 활성 여부*와 *본연 CapsLock 진입 여부*를 함께 표현하여
/// 세 곳(KeyEventTap·InputStateCoordinator·CapsLockHIDMonitor)이 같은 값을 본다.
enum CapsLockMode {
    /// HID 모니터 미활성 — `toggleKey != .capsLock`, 권한 미부여, HID open 실패, 충돌 등.
    /// 기존 CGEventTap 경로(doc 30 SET 의미론)가 권위.
    case cgEventTapAuthority

    /// HID 모니터 활성, 짧은 탭 모드 — 본연 CapsLock 잠금 없음.
    /// HID가 keyDown/keyUp을 가지고 short/long 판정의 권위.
    case hidToggleAuthority

    /// HID 모니터 활성, 길게-누름으로 본연 CapsLock 진입 상태.
    /// alpha-lock = true, LED ON. 모드는 영문 고정(macOS native parity).
    /// 다음 짧은 탭에서 OFF로 환원.
    case hidRealLockOn
}

/// CapsLock 전용 HID 모니터 — [doc 32](../../design/32-hid-capslock-press-duration.md).
///
/// `IOHIDManager`로 키보드 디바이스의 CapsLock usage(0x39)만 매칭하여 raw make/break를 받는다.
/// 짧은 탭(<800ms)은 한/영 토글, 길게-누름(≥800ms)은 본연 CapsLock 활성화.
///
/// 옵트인: `toggleKey == .capsLock`이고 사용자가 입력 모니터링 권한을 부여한 경우에만 기동.
final class CapsLockHIDMonitor {
    static let shared = CapsLockHIDMonitor()
    private init() {}

    /// 외부에서 읽기만. 상태 전이는 본 클래스가 단독 수행.
    private(set) var mode: CapsLockMode = .cgEventTapAuthority

    /// controller 주입 — 짧은 탭의 toggleMode·길게의 enterRealCapsLock 위임.
    weak var controller: OngeulInputController?

    /// 길게-누름 임계값. SokIM 출하 검증값과 동일. [doc 32 § 임계값](../../design/32-hid-capslock-press-duration.md#임계값--800ms-하드코딩).
    private static let longPressThresholdMs: Int = 800

    private var hid: IOHIDManager?
    private var isKeyDown: Bool = false
    /// 현재 진행 중인 press가 임계 발화로 `.hidRealLockOn` 진입을 일으켰는지.
    /// keyUp에서 *exit press의 up*(=다음 press의 up)인지 *진입 press의 up*인지 구별.
    private var pressTriggeredLockTransition: Bool = false
    private var longPressTimer: DispatchWorkItem?

    /// `start()` 실패 사유.
    enum StartError: Error, CustomStringConvertible {
        case notPermitted
        case exclusiveAccess
        case other(IOReturn)

        var description: String {
            switch self {
            case .notPermitted:    return "입력 모니터링 권한이 필요합니다."
            case .exclusiveAccess: return "키보드 입력을 모니터링하는 다른 앱과 충돌합니다."
            case .other(let r):    return "HID 오픈 실패 (\(r))"
            }
        }
    }

    /// 외부에서 HID 모니터 활성 여부 빠른 조회.
    var isStarted: Bool { hid != nil }

    /// IOHIDManager 생성 + CapsLock-only 매칭 + 콜백 등록 + Open.
    /// 이미 시작돼 있으면 멱등 (return). 실패 시 throws.
    func start() throws {
        if hid != nil {
            os_log("start: already started", log: log, type: .debug)
            return
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)

        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ] as CFDictionary)

        // Caps Lock(0x39) usage만 받음 — 다른 키엔 개입 안 함.
        IOHIDManagerSetInputValueMatching(manager, [
            kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
            kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock
        ] as CFDictionary)

        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard result == kIOReturnSuccess else { return }
            guard let context = context else { return }
            let monitor = Unmanaged<CapsLockHIDMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onValue(value)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let res = IOHIDManagerOpen(manager, 0)
        switch res {
        case kIOReturnSuccess:
            os_log("start: success", log: log, type: .info)
            self.hid = manager
            self.mode = .hidToggleAuthority
        case kIOReturnNotPermitted:
            os_log("start: not permitted (Input Monitoring TCC)", log: log, type: .error)
            IOHIDManagerClose(manager, 0)
            throw StartError.notPermitted
        case kIOReturnExclusiveAccess:
            os_log("start: exclusive access conflict", log: log, type: .error)
            IOHIDManagerClose(manager, 0)
            throw StartError.exclusiveAccess
        default:
            os_log("start: other error %d", log: log, type: .error, res)
            IOHIDManagerClose(manager, 0)
            throw StartError.other(res)
        }
    }

    /// HID 모니터 정지 + 상태 초기화. 멱등.
    func stop() {
        if let hid {
            IOHIDManagerClose(hid, 0)
            IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerRegisterInputValueCallback(hid, nil, nil)
            self.hid = nil
        }
        longPressTimer?.cancel()
        longPressTimer = nil
        isKeyDown = false
        pressTriggeredLockTransition = false
        if mode != .cgEventTapAuthority {
            mode = .cgEventTapAuthority
        }
        os_log("stop: done", log: log, type: .info)
    }

    /// 절전 복귀 등에서 모니터 재시작.
    func restart() {
        stop()
        try? start()
    }

    // MARK: - HID 콜백 본체

    private func onValue(_ value: IOHIDValue) {
        let usage = IOHIDElementGetUsage(IOHIDValueGetElement(value))
        guard usage == kHIDUsage_KeyboardCapsLock else { return }
        let isDown = IOHIDValueGetIntegerValue(value) != 0
        if isDown {
            onKeyDown()
        } else {
            onKeyUp()
        }
    }

    private func onKeyDown() {
        isKeyDown = true
        pressTriggeredLockTransition = false
        if mode == .hidRealLockOn {
            // exit press 시작 — keyUp에서 exitRealCapsLock 실행.
            os_log("keyDown (exit press starts; mode=hidRealLockOn)", log: log, type: .debug)
            return
        }
        // 일반 toggle press
        os_log("keyDown (toggle press starts)", log: log, type: .debug)
        // macOS 하드웨어가 alpha-lock을 토글했을 수 있음 → 즉시 OFF (LED 깜빡임 차단).
        // CapsLockSync.expectedState 가드가 echo flagsChanged를 필터링.
        CapsLockSync.setState(false)
        scheduleLongPressTimer()
    }

    private func onKeyUp() {
        isKeyDown = false
        longPressTimer?.cancel()
        longPressTimer = nil
        if mode == .hidRealLockOn {
            if pressTriggeredLockTransition {
                // 이 press에서 길게-누름 발화. enterRealCapsLock 이미 실행됨. 추가 동작 없음.
                os_log("keyUp (entry press completed)", log: log, type: .debug)
                pressTriggeredLockTransition = false
            } else {
                // 이전 press가 .hidRealLockOn 진입시켰고, 새 press(=exit press)의 up이 도착 → exit.
                os_log("keyUp (exit press completed)", log: log, type: .debug)
                exitRealCapsLock()
            }
        } else {
            // .hidToggleAuthority — 짧은 탭 완료 → 한/영 토글
            os_log("keyUp (short tap → toggle)", log: log, type: .debug)
            DispatchQueue.main.async { [weak controller] in
                controller?.performToggleFromTap()
            }
        }
    }

    private func scheduleLongPressTimer() {
        let work = DispatchWorkItem { [weak self] in
            self?.onLongPressTimerFired()
        }
        longPressTimer = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.longPressThresholdMs),
            execute: work
        )
    }

    private func onLongPressTimerFired() {
        guard isKeyDown else { return }  // race safety: keyUp이 발화 직전 도착
        pressTriggeredLockTransition = true
        enterRealCapsLock()
    }

    private func enterRealCapsLock() {
        os_log("enterRealCapsLock", log: log, type: .info)
        // mode를 먼저 변경 → 이후 setMode 호출이 LED 동기화 게이트(`mode != .hidRealLockOn`)에 걸림.
        mode = .hidRealLockOn
        DispatchQueue.main.async { [weak controller] in
            controller?.performEnterRealCapsLock()
        }
    }

    private func exitRealCapsLock() {
        os_log("exitRealCapsLock", log: log, type: .info)
        mode = .hidToggleAuthority
        CapsLockSync.setState(false)  // LED off
        // mode(엔진 입력 모드)는 변경하지 않음 — 사용자가 진입 시 SET한 영문 그대로 유지.
    }
}
