import AppKit

enum ToggleKey: String, CaseIterable {
    case rightCommand = "rightCommand"
    case rightOption = "rightOption"
    case leftShift = "leftShift"
    case rightShift = "rightShift"
    case shiftSpace = "shiftSpace"

    /// flagsChanged에서 감지할 keyCode (shiftSpace는 nil → keyDown에서 처리)
    var keyCode: UInt16? {
        switch self {
        case .rightCommand: return KeyCode.rightCommand
        case .rightOption:  return KeyCode.rightOption
        case .leftShift:    return KeyCode.leftShift
        case .rightShift:   return KeyCode.rightShift
        case .shiftSpace:   return nil
        }
    }

    /// press/release 판정에 사용할 modifier flag
    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .rightCommand: return .command
        case .rightOption:  return .option
        case .leftShift, .rightShift: return .shift
        case .shiftSpace:   return nil
        }
    }
}
