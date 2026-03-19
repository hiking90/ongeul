import AppKit

/// handleKeyDown의 라우팅 결정. 부수 효과 없이 어떤 동작을 수행할지만 결정한다.
enum KeyDownAction: Equatable {
    /// Shift+Space 한/영 전환 (shiftSpace 모드)
    case shiftSpaceToggle
    /// 영문 모드: 시스템에 위임
    case passToSystem
    /// Cmd/Ctrl 단축키 또는 방향키: flush 후 시스템에 위임
    case flushAndPassToSystem
    /// Backspace: 엔진에 위임
    case backspace
    /// Enter: flush 후 합성 Enter 처리
    case enter(isSynthetic: Bool)
    /// Space: flush 후 시스템에 위임
    case space
    /// Escape: 조합 폐기 (+ 옵션: 영문 전환)
    case escape
    /// 일반 키: 엔진에 위임
    case processKey(label: String)
    /// 알 수 없는 키: flush 후 시스템에 위임
    case flushUnknownKey
}

/// 키 이벤트의 속성으로부터 수행할 동작을 결정하는 순수 함수.
func routeKeyDown(
    keyCode: UInt16,
    characters: String?,
    modifiers: NSEvent.ModifierFlags,
    engineMode: InputMode,
    toggleKey: ToggleKey,
    isSyntheticEnter: Bool
) -> KeyDownAction {
    // Shift+Space → 한/영 전환 (shiftSpace 모드일 때)
    if toggleKey == .shiftSpace
        && keyCode == KeyCode.space
        && modifiers.contains(.shift)
        && !modifiers.contains(.option)
        && !modifiers.contains(.command)
        && !modifiers.contains(.control) {
        return .shiftSpaceToggle
    }

    // 영문 모드: 전환 키 외 모든 키를 시스템에 위임
    if engineMode == .english {
        return .passToSystem
    }

    // Control+[ → Vim ESC 등가
    if modifiers.contains(.control)
        && !modifiers.contains(.command)
        && !modifiers.contains(.option)
        && keyCode == KeyCode.leftBracket {
        return .escape
    }

    // 시스템 단축키 → flush 후 통과
    if modifiers.contains(.command) || modifiers.contains(.control) {
        return .flushAndPassToSystem
    }

    // Backspace
    if keyCode == KeyCode.backspace {
        return .backspace
    }

    // Enter
    if keyCode == KeyCode.enter {
        return .enter(isSynthetic: isSyntheticEnter)
    }

    // Space → flush 후 시스템 위임
    if keyCode == KeyCode.space {
        return .space
    }

    // Escape
    if keyCode == KeyCode.escape {
        return .escape
    }

    // 방향키 → flush 후 통과
    let arrowKeys: Set<UInt16> = [
        KeyCode.arrowLeft, KeyCode.arrowRight,
        KeyCode.arrowDown, KeyCode.arrowUp,
    ]
    if arrowKeys.contains(keyCode) {
        return .flushAndPassToSystem
    }

    // 일반 키 → 엔진에 위임
    if let chars = characters,
       let label = keyLabel(
           characters: chars,
           capsLock: modifiers.contains(.capsLock),
           shift: modifiers.contains(.shift)
       ) {
        return .processKey(label: label)
    }

    return .flushUnknownKey
}
