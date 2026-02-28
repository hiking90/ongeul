import Cocoa
import ApplicationServices
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "eventTap")

class KeyEventTap {
    static let shared = KeyEventTap()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    static weak var activeController: OngeulInputController?

    func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func install() {
        guard eventTap == nil else {
            os_log("install: tap already exists", log: log, type: .default)
            return
        }
        guard isAccessibilityGranted() else {
            os_log("install: accessibility not granted", log: log, type: .default)
            return
        }

        // keyDown + keyUp 모두 가로채기 (JetBrains 등이 keyUp에서 공백 삽입 방지)
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
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
                           log: log, type: .default,
                           type == .tapDisabledByTimeout ? "timeout" : "userInput")
                    if KeyEventTap.shared.isAccessibilityGranted(),
                       let tap = KeyEventTap.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                if keyCode == 49  // Space
                    && flags.contains(.maskShift)
                    && !flags.contains(.maskAlternate)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskControl)
                    && KeyEventTap.activeController != nil {
                    if type == .keyDown {
                        os_log("Shift+Space intercepted (keyDown), consuming event",
                               log: log, type: .default)
                        DispatchQueue.main.async {
                            KeyEventTap.activeController?.performToggleFromTap()
                        }
                    }
                    // keyDown과 keyUp 모두 소비
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            os_log("install: CGEventTap installed successfully", log: log, type: .default)
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
        os_log("uninstall: CGEventTap removed", log: log, type: .default)
    }
}
