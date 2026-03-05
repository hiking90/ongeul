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

                // keyDown → modifier tap 판정 취소
                if type == .keyDown {
                    KeyEventTap.toggleDetector.cancelOnKeyDown()
                }

                // === Shift+Space 처리 (shiftSpace 모드) ===
                if KeyEventTap.toggleKey == .shiftSpace
                    && keyCode == 49  // Space
                    && flags.contains(.maskShift)
                    && !flags.contains(.maskAlternate)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskControl) {
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
                        if let controller = KeyEventTap.activeController {
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
