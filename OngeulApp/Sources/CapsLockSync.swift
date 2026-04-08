import IOKit
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "capsLockSync")

// Private API declaration
@_silgen_name("IOHIDSetModifierLockState")
func IOHIDSetModifierLockState(_ handle: io_connect_t, _ selector: Int32, _ state: Bool) -> Int32

private let kIOHIDCapsLockState: Int32 = 1

enum CapsLockSync {
    /// CapsLock LED를 항상 OFF로 강제.
    static func forceOff() {
        os_log("forceOff", log: log, type: .debug)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        )
        if service != IO_OBJECT_NULL {
            _ = IOHIDSetModifierLockState(service, kIOHIDCapsLockState, false)
            IOObjectRelease(service)
        }
    }
}
