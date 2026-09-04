import AppKit

enum ToggleKey: String, CaseIterable {
    case rightCommand = "rightCommand"
    case rightOption = "rightOption"
    case leftShift = "leftShift"
    case rightShift = "rightShift"
    case shiftSpace = "shiftSpace"
    case capsLock = "capsLock"
    case hangulKey = "hangulKey"

    /// flagsChanged에서 감지할 keyCode
    /// (shiftSpace, capsLock, hangulKey는 nil → keyDown 등 별도 경로에서 처리)
    var keyCode: UInt16? {
        switch self {
        case .rightCommand: return KeyCode.rightCommand
        case .rightOption:  return KeyCode.rightOption
        case .leftShift:    return KeyCode.leftShift
        case .rightShift:   return KeyCode.rightShift
        case .shiftSpace:   return nil
        case .capsLock:     return nil   // CGEventTap 콜백에서 직접 처리
        case .hangulKey:    return nil   // keyDown(keycode 104)에서 직접 처리
        }
    }

    /// press/release 판정에 사용할 modifier flag
    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .rightCommand: return .command
        case .rightOption:  return .option
        case .leftShift, .rightShift: return .shift
        case .shiftSpace:   return nil
        case .capsLock:     return nil
        case .hangulKey:    return nil
        }
    }
}

extension ToggleKey {
    /// 이 전환 키의 modifier 역할을 앱에서 지워도 되는지 (doc 35, issue #22).
    ///
    /// 오른쪽 Command/Option만 대상이다. 왼쪽 짝이 단축키·특수문자 입력을 그대로
    /// 담당하므로 잃는 것이 없다. Shift 계열은 억제하면 그 Shift로 대문자를 못 치게
    /// 되므로 제외하고, Shift+Space·CapsLock·한/영 키는 애초에 modifier 조합이
    /// 아니거나 이미 전용 경로에서 이벤트를 소비한다.
    var suppressesModifier: Bool {
        switch self {
        case .rightCommand, .rightOption: return true
        case .leftShift, .rightShift, .shiftSpace, .capsLock, .hangulKey: return false
        }
    }
}

/// 전환 키(오른쪽 ⌘/⌥)가 앱에 modifier로 전달되지 않도록 CGEvent flags를 다듬는다.
///
/// 배경(doc 35, issue #22): modifier `flagsChanged`는 소비하지 않고 통과시키므로
/// (소비하면 앱이 modifier를 눌린 상태로 오인 — doc 20) 전환 키가 눌린 동안 도착한
/// keyDown은 `⌘`를 달고 앱에 전달된다. 한/영을 톡 치고 곧바로 다음 글자를 누르면 두
/// 키가 수십 ms 겹치므로, 그 글자가 `⌘A` 같은 단축키로 발화한다.
///
/// 상태를 두지 않는 순수 계산이다. 탭이 잠시 비활성화돼 press/release를 놓쳐도
/// 추적 상태가 어긋날 일이 없다.
enum ToggleModifierSuppression {
    // IOKit/hidsystem/IOLLEvent.h — CGEvent flags에 실려 오는 좌/우 구분 비트.
    static let deviceLeftCommand: UInt64  = 0x0000_0008  // NX_DEVICELCMDKEYMASK
    static let deviceRightCommand: UInt64 = 0x0000_0010  // NX_DEVICERCMDKEYMASK
    static let deviceLeftOption: UInt64   = 0x0000_0020  // NX_DEVICELALTKEYMASK
    static let deviceRightOption: UInt64  = 0x0000_0040  // NX_DEVICERALTKEYMASK

    /// 앱에 전달할 flags에서 전환 키의 modifier 비트를 제거한다.
    ///
    /// 반대쪽(왼쪽) 키가 함께 눌려 있으면 일반 마스크(`.maskCommand`/`.maskAlternate`)는
    /// 남긴다 — 왼쪽 ⌘로 시작한 단축키가 오른쪽 ⌘를 곁들였다고 죽으면 안 된다.
    ///
    /// - Returns: 바꿀 것이 있을 때만 새 flags. 없으면 nil (핫패스에서 불필요한 쓰기 회피).
    static func apply(to flags: CGEventFlags, toggleKey: ToggleKey) -> CGEventFlags? {
        let ownBit: UInt64
        let otherSideBit: UInt64
        let genericMask: CGEventFlags
        switch toggleKey {
        case .rightCommand:
            ownBit = deviceRightCommand
            otherSideBit = deviceLeftCommand
            genericMask = .maskCommand
        case .rightOption:
            ownBit = deviceRightOption
            otherSideBit = deviceLeftOption
            genericMask = .maskAlternate
        case .leftShift, .rightShift, .shiftSpace, .capsLock, .hangulKey:
            return nil
        }

        guard flags.rawValue & ownBit != 0 else { return nil }

        var result = flags
        result.remove(CGEventFlags(rawValue: ownBit))
        if flags.rawValue & otherSideBit == 0 {
            result.remove(genericMask)
        }
        return result
    }
}
