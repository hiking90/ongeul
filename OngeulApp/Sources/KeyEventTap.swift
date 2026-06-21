import Cocoa
import ApplicationServices
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "eventTap")

class KeyEventTap {
    static let shared = KeyEventTap()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    static weak var activeController: OngeulInputController?
    /// activeController가 IMK 라이프사이클 레이스(전체화면/Space 전환 시 activate→deactivate
    /// 역순 배달, deactivate 후 activate 누락 등)로 nil이 되어도 토글이 죽지 않도록, 마지막으로
    /// 활성화된 컨트롤러를 보존한다. deactivateServer에서는 지우지 않는다 (weak 이므로 컨트롤러
    /// 해제 시 자동 nil). 배경·전체 분석은 doc 33.
    static weak var lastController: OngeulInputController?
    /// 탭 진입점이 사용할 컨트롤러 — activeController 우선, 없으면 마지막 활성 컨트롤러.
    /// 단 lastController 폴백은 **Ongeul이 실제 활성 입력 소스일 때만** 적용한다.
    /// activeController가 nil이면서 Ongeul이 활성이면 = 라이프사이클 레이스(path 2, 세션은 살아있음).
    /// Ongeul이 비활성(다른 입력기 사용 중)이면 폴백을 금지 — stale lastController로 토글/소비하면
    /// 다른 입력기의 키를 먹고 per-app 모드를 잘못 저장한다 (doc 33 #1).
    static var resolvedController: OngeulInputController? {
        if let active = activeController { return active }
        return OngeulInputController.isOngeulActiveInputSource() ? lastController : nil
    }
    static var toggleKey: ToggleKey = .rightCommand
    private static var toggleDetector = ToggleDetector()

    // Focus-steal correction: 키 버퍼 (activateServer에서 초기화)
    // RecordedKey 정의는 RecordedKey.swift로 이동됨.
    static var keyBuffer: [RecordedKey] = []
    static var keyBufferWasKoreanMode = false

    // keyBuffer 강제 만료: 입력이 멈춘 뒤 복호화된 (민감할 수 있는) 문자가 메모리에
    // 무기한 남지 않도록 한다. activateServer/modifier 외에는 다음 keyDown 시에만
    // lazy prune 되므로, 키 입력이 끊기면 잔존했다. 만료 시각을 focus-steal 의 포기
    // 임계값(첫 키 0.5s 경과 시 보정 포기 — FocusStealCorrector)과 정렬해, 마지막
    // 입력 +0.5s 후 비워도 보정에 실제로 쓰일 키는 제거하지 않는다.
    private static let keyBufferMaxLifetime: TimeInterval = 0.5
    private static var keyBufferExpiryTask: DispatchWorkItem?

    /// keyBuffer 강제 만료 타이머를 (재)예약한다. 키 append 시마다 호출.
    /// 모두 메인 런루프에서 실행되므로 별도 동기화 불필요.
    static func scheduleKeyBufferExpiry() {
        keyBufferExpiryTask?.cancel()
        let task = DispatchWorkItem {
            KeyEventTap.keyBuffer.removeAll()
            KeyEventTap.keyBufferExpiryTask = nil
        }
        keyBufferExpiryTask = task
        DispatchQueue.main.asyncAfter(
            deadline: .now() + keyBufferMaxLifetime, execute: task)
    }

    // 현재 입력 모드 (모드 변경 시 OngeulInputController에서 갱신)
    static var currentInputMode: InputMode = .english

    var isInstalled: Bool { eventTap != nil }

    func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func install() {
        guard eventTap == nil else {
            os_log("install: tap already exists", log: log, type: .debug)
            return
        }
        guard isAccessibilityGranted() else {
            os_log("install: accessibility not granted", log: log, type: .fault)
            return
        }

        // keyDown + keyUp + flagsChanged 모두 가로채기
        // - shiftSpace: keyDown/keyUp에서 Space 소비
        // - modifier 키: flagsChanged에서 tap 감지 (이벤트는 통과)
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                // macOS가 콜백 지연으로 탭을 비활성화한 경우 자동 복구
                // 권한이 철회된 경우 불필요한 재활성화 시도를 방지
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    os_log("tap disabled by %{public}@, re-enabling",
                           log: log, type: .error,
                           type == .tapDisabledByTimeout ? "timeout" : "userInput")
                    if KeyEventTap.shared.isAccessibilityGranted(),
                       let tap = KeyEventTap.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                var flags = event.flags

                // keyDown → modifier tap 판정 취소 + 마지막 키 기록
                if type == .keyDown {
                    // CapsLock 방어 (영문 모드 한정): 영문 통과 경로에서 stale
                    // maskAlphaShift가 남으면 대문자가 누수된다(이슈 #10).
                    // CapsLockSync.setState(false)의 IOKit 왕복 지연 동안 keyDown에 남는
                    // 비트를 이벤트에서 직접 제거하고 LED도 OFF로 강제한다. 탭이 IME·앱보다
                    // 앞단이므로 IMK 경로와 영문 직통 경로가 한 곳에서 모두 보정된다.
                    // 이후 keyboardGetUnicodeString도 보정된 flags를 사용한다.
                    //
                    // 한글 모드에서는 strip하지 않는다: doc 30의 "LED ON = 한글" 의미론상
                    // alpha-lock이 켜져 있는 것이 정상(= LED 인디케이터)이고, 자모는 keycode
                    // 기반이라 대문자 누수가 없다. 여기서 끄면 한글 진입 후 첫 키 입력에
                    // LED가 꺼져 인디케이터가 무력화된다.
                    //
                    // 본연 CapsLock 잠금(HID 길게-누름으로 진입) 중에도 strip 면제 —
                    // realLockOn은 영문 모드로 강제되므로 currentInputMode 가드만으로는
                    // 막히지 않는다. 사용자가 명시적으로 켠 대문자 잠금이 통과돼야 한다 (doc 32).
                    if KeyEventTap.toggleKey == .capsLock
                        && flags.contains(.maskAlphaShift)
                        && KeyEventTap.currentInputMode == .english
                        && CapsLockHIDMonitor.shared.mode != .hidRealLockOn {
                        CapsLockSync.setState(false)
                        flags.subtract(.maskAlphaShift)
                        event.flags = flags
                    }

                    KeyEventTap.toggleDetector.cancelOnKeyDown()

                    // focus-steal 키 버퍼 기록은 한글 모드에서만 의미가 있다.
                    // 소비처(activateServer)가 keyBufferWasKoreanMode로 게이트하므로 영문 모드
                    // 기록은 시스템 전역 키마다 헛도는 할당·GCD 타이머(scheduleKeyBufferExpiry)
                    // churn일 뿐이고, 복호화된 영문 키가 메모리에 남아 프라이버시에도 불리하다.
                    // 버퍼링 윈도우 중 후발 키는 forceKoreanForReplay가 이미 currentInputMode를
                    // .korean으로 동기 설정한 뒤이므로 이 게이트를 통과해 정상 캡처된다.
                    if KeyEventTap.currentInputMode == .korean {
                        // Modifier 단축키(cmd, ctrl, option)는 텍스트 입력이 아니므로
                        // focus-steal 버퍼에 기록하지 않는다.
                        let hasModifier = flags.contains(.maskCommand)
                            || flags.contains(.maskControl)
                            || flags.contains(.maskAlternate)

                        if hasModifier {
                            KeyEventTap.keyBuffer.removeAll()
                        } else {
                            // 비modifier 키일 때만 유니코드 문자열을 추출한다 — modifier
                            // 단축키에서 호출 후 폐기하던 keyboardGetUnicodeString 비용 제거.
                            var length = 0
                            var chars = [UniChar](repeating: 0, count: 4)
                            event.keyboardGetUnicodeString(
                                maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
                            if length > 0 {
                                let str = String(utf16CodeUnits: chars, count: length)
                                let capsLock = flags.contains(.maskAlphaShift)
                                let shift = flags.contains(.maskShift)
                                if let label = keyLabel(characters: str, capsLock: capsLock, shift: shift) {
                                    let now = CFAbsoluteTimeGetCurrent()
                                    // 첫 키가 200ms보다 오래되면 버퍼 리셋 (메모리 증가 방지)
                                    if let first = KeyEventTap.keyBuffer.first,
                                       now - first.timestamp > 0.2 {
                                        KeyEventTap.keyBuffer.removeAll()
                                    }
                                    if KeyEventTap.keyBuffer.isEmpty {
                                        // 이 블록은 한글 모드 게이트 내부이므로 항상 true.
                                        KeyEventTap.keyBufferWasKoreanMode = true
                                    }
                                    KeyEventTap.keyBuffer.append(RecordedKey(
                                        character: label,
                                        timestamp: now
                                    ))
                                    KeyEventTap.scheduleKeyBufferExpiry()
                                    // 복호화된 타이핑 문자는 민감할 수 있으므로 private 으로 로깅
                                    // (통합 로그에 평문 키가 남지 않도록). bufSize/koreanMode 만 public.
                                    os_log("focusSteal: recorded key='%{private}@' koreanMode=%d bufSize=%d",
                                           log: log, type: .debug, label,
                                           KeyEventTap.keyBufferWasKoreanMode,
                                           KeyEventTap.keyBuffer.count)
                                }
                            }
                        }
                    }
                }

                // === Control+[ → Vim ESC 등가 (이벤트는 소비하지 않고 통과) ===
                // 이중 경로 주의 (doc 27 §Phase 2): 탭 설치 시 이 경로가 권위이고,
                // 탭 미설치(접근성 미허용) 시에는 IMK handle() → routeKeyDown의 .escape 분기가 폴백.
                // 탭 설치 상태에서는 두 경로가 모두 발화하지만, 먼저 실행된 쪽이 flush+영문전환을
                // 끝내면 나머지는 mode==.english로 인해 no-op이 되므로 실효 실행은 1회다.
                if type == .keyDown
                    && keyCode == 0x21  // [ key
                    && flags.contains(.maskControl)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskAlternate)
                    && KeyEventTap.currentInputMode == .korean {
                    if let controller = KeyEventTap.resolvedController {
                        DispatchQueue.main.async {
                            controller.performVimEscapeFromTap()
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                // === Shift+Space 처리 (shiftSpace 모드) ===
                if KeyEventTap.toggleKey == .shiftSpace
                    && keyCode == 49  // Space
                    && flags.contains(.maskShift)
                    && !flags.contains(.maskAlternate)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskControl) {
                    // activeController가 라이프사이클 레이스로 nil이어도 lastController로 폴백.
                    let controller = KeyEventTap.resolvedController
                    // English Lock 상태 → 시스템에 통과 (소비하지 않음)
                    if controller?.isCurrentAppLocked() == true {
                        return Unmanaged.passUnretained(event)
                    }
                    // 토글을 확실히 적용할 수 있는 컨트롤러(살아있는 client)가 있을 때만 소비한다.
                    // 없으면 통과시켜 IMK handle()이 진짜 포커스된 세션에서 처리하게 한다
                    // (올바른 라우팅 + 합성 중 한글 commit 보장). 무조건 소비하면 이 갭에서
                    // 토글이 죽고(블랙홀) 합성 중 한글이 유실될 수 있다 (doc 33).
                    guard let controller, controller.hasLiveClient else {
                        if type == .keyDown {
                            os_log("Shift+Space: no live controller → IMK fallback",
                                   log: log, type: .error)
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    if type == .keyDown {
                        os_log("Shift+Space intercepted (keyDown), toggling%{public}@",
                               log: log, type: .default,
                               KeyEventTap.activeController == nil ? " [lastController fallback]" : "")
                        DispatchQueue.main.async {
                            controller.performToggleFromTap()
                        }
                    }
                    // keyDown/keyUp 모두 소비 (짝 맞춤) — JetBrains 등에서 space 누출 방지.
                    return nil
                }

                // === flagsChanged: CapsLock 기반 한영 TOGGLE ===
                // CapsLock은 하드웨어 토글이므로 ToggleDetector를 사용하지 않고
                // flagsChanged에서 직접 감지하되, 다른 전환 키와 동일한 TOGGLE로 처리한다.
                // LED는 항상 OFF로 강제하여 CapsLock이 켜지지 않도록 한다.
                // HID 모니터가 활성이면 (mode != .cgEventTapAuthority) HID가 권위 —
                // CapsLock 분기는 건너뛴다. HID가 keyDown/keyUp으로 short/long 판정 후
                // performToggleFromTap (짧은 탭) 또는 performEnterRealCapsLock (길게)을 호출.
                if type == .flagsChanged && keyCode == Int64(KeyCode.capsLock)
                    && KeyEventTap.toggleKey == .capsLock
                    && CapsLockHIDMonitor.shared.mode == .cgEventTapAuthority {
                    let capsLockOn = flags.contains(.maskAlphaShift)
                    // doc 30 SET 의미론: LED ON=한글, LED OFF=영문. 하드웨어가 이미 상태를
                    // 토글했으므로 SET을 그대로 받아들이고 모드를 그에 맞춘다.
                    // CapsLockSync.shouldHandle()이 setState() echo를 필터링한다.
                    if CapsLockSync.shouldHandle(capsLockOn: capsLockOn) {
                        os_log("capsLock flagsChanged: capsLockOn=%{public}d (user)",
                               log: log, type: .debug, capsLockOn)
                        if let controller = KeyEventTap.resolvedController,
                           !controller.isCurrentAppLocked() {
                            // 동기 호출: CapsLock은 key press 시점에 발생하므로
                            // async를 사용하면 다음 keyDown이 모드 전환 전에 도착할 수 있다.
                            controller.performCapsLockModeSet(korean: capsLockOn)
                        }
                    } else {
                        os_log("capsLock flagsChanged: capsLockOn=%{public}d (echo, filtered)",
                               log: log, type: .debug, capsLockOn)
                    }
                    return Unmanaged.passUnretained(event)  // 이벤트 통과 — 앱에 정상 전달
                }

                // === flagsChanged: modifier 기반 전환 키 처리 ===
                // modifier flagsChanged는 소비하지 않고 통과시킨다.
                // 소비하면 앱이 modifier를 눌린 상태로 오인하는 치명적 버그 발생.
                if type == .flagsChanged {
                    let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
                    let action = KeyEventTap.toggleDetector.handleFlagsChanged(
                        keyCode: UInt16(keyCode),
                        flags: nsFlags,
                        toggleKey: KeyEventTap.toggleKey
                    )
                    switch action {
                    case .toggle:
                        if let controller = KeyEventTap.resolvedController,
                           !controller.isCurrentAppLocked() {
                            os_log("modifier tap intercepted, toggling", log: log, type: .debug)
                            DispatchQueue.main.async {
                                controller.performToggleFromTap()
                            }
                        }
                    case .englishLockToggle:
                        if let controller = KeyEventTap.resolvedController {
                            os_log("4-key English Lock intercepted", log: log, type: .debug)
                            DispatchQueue.main.async {
                                controller.performEnglishLockToggleFromTap()
                            }
                        }
                    case .none:
                        break
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            os_log("install: CGEventTap installed successfully", log: log, type: .info)
        } else {
            os_log("install: CGEvent.tapCreate returned nil", log: log, type: .error)
        }
    }

    func uninstall() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        os_log("uninstall: CGEventTap removed", log: log, type: .info)
    }
}
