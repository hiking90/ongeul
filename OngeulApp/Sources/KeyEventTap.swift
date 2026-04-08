import Cocoa
import ApplicationServices
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "eventTap")

class KeyEventTap {
    static let shared = KeyEventTap()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    static weak var activeController: OngeulInputController?
    static var toggleKey: ToggleKey = .rightCommand
    private static var toggleDetector = ToggleDetector()

    // Focus-steal correction: 키 버퍼 (activateServer에서 초기화)
    struct RecordedKey {
        let character: String
        let timestamp: CFAbsoluteTime
    }
    static var keyBuffer: [RecordedKey] = []
    static var keyBufferWasKoreanMode = false

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
                let flags = event.flags

                // keyDown → modifier tap 판정 취소 + 마지막 키 기록
                if type == .keyDown {
                    // CapsLock 방어: 어떤 이유로든 CapsLock이 켜져 있으면 즉시 OFF
                    if KeyEventTap.toggleKey == .capsLock
                        && flags.contains(.maskAlphaShift) {
                        CapsLockSync.forceOff()
                    }

                    KeyEventTap.toggleDetector.cancelOnKeyDown()

                    // Modifier 단축키(cmd, ctrl, option)는 텍스트 입력이 아니므로
                    // focus-steal 버퍼에 기록하지 않는다.
                    let hasModifier = flags.contains(.maskCommand)
                        || flags.contains(.maskControl)
                        || flags.contains(.maskAlternate)

                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    event.keyboardGetUnicodeString(
                        maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
                    if hasModifier {
                        KeyEventTap.keyBuffer.removeAll()
                    } else if length > 0 {
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
                                KeyEventTap.keyBufferWasKoreanMode = (KeyEventTap.currentInputMode == .korean)
                            }
                            KeyEventTap.keyBuffer.append(RecordedKey(
                                character: label,
                                timestamp: now
                            ))
                            os_log("focusSteal: recorded key='%{public}@' koreanMode=%d bufSize=%d",
                                   log: log, type: .debug, label,
                                   KeyEventTap.keyBufferWasKoreanMode,
                                   KeyEventTap.keyBuffer.count)
                        }
                    }
                }

                // === Control+[ → Vim ESC 등가 (이벤트는 소비하지 않고 통과) ===
                if type == .keyDown
                    && keyCode == 0x21  // [ key
                    && flags.contains(.maskControl)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskAlternate)
                    && KeyEventTap.currentInputMode == .korean {
                    if let controller = KeyEventTap.activeController {
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
                    // English Lock 상태 → 시스템에 통과 (소비하지 않음)
                    if KeyEventTap.activeController?.isCurrentAppLocked() == true {
                        return Unmanaged.passUnretained(event)
                    }
                    if type == .keyDown {
                        if let controller = KeyEventTap.activeController {
                            os_log("Shift+Space intercepted (keyDown), toggling",
                                   log: log, type: .debug)
                            DispatchQueue.main.async {
                                controller.performToggleFromTap()
                            }
                        } else {
                            os_log("Shift+Space intercepted (keyDown), no active controller",
                                   log: log, type: .error)
                        }
                    }
                    // activeController 유무와 관계없이 항상 소비
                    // (JetBrains 등에서 deactivate→activate 갭 중 space 누출 방지)
                    return nil
                }

                // === flagsChanged: CapsLock 기반 한영 TOGGLE ===
                // CapsLock은 하드웨어 토글이므로 ToggleDetector를 사용하지 않고
                // flagsChanged에서 직접 감지하되, 다른 전환 키와 동일한 TOGGLE로 처리한다.
                // LED는 항상 OFF로 강제하여 CapsLock이 켜지지 않도록 한다.
                if type == .flagsChanged && keyCode == Int64(KeyCode.capsLock)
                    && KeyEventTap.toggleKey == .capsLock {
                    let capsLockOn = flags.contains(.maskAlphaShift)
                    os_log("capsLock flagsChanged: capsLockOn=%{public}d", log: log, type: .debug, capsLockOn)
                    // capsLockOn=true (OFF→ON press)만 처리. forceOff()가 하드웨어를 항상 OFF로
                    // 유지하므로 모든 실제 press는 capsLockOn=true. false는 echo 또는 release.
                    if capsLockOn {
                        CapsLockSync.forceOff()
                        if let controller = KeyEventTap.activeController,
                           !controller.isCurrentAppLocked() {
                            // 동기 호출: CapsLock은 key press 시점에 발생하므로
                            // async를 사용하면 다음 keyDown이 모드 전환 전에 도착할 수 있다.
                            controller.performToggleFromTap()
                            os_log("capsLock: toggled", log: log, type: .debug)
                        }
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
                        if let controller = KeyEventTap.activeController,
                           !controller.isCurrentAppLocked() {
                            os_log("modifier tap intercepted, toggling", log: log, type: .debug)
                            DispatchQueue.main.async {
                                controller.performToggleFromTap()
                            }
                        }
                    case .englishLockToggle:
                        if let controller = KeyEventTap.activeController {
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
