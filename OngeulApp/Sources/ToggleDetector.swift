import AppKit

/// modifier tap 또는 4키 English Lock 감지 결과
enum ToggleAction: Equatable {
    case none
    case toggle
    case englishLockToggle
}

/// modifier tap + 4키 English Lock 상태 머신.
///
/// 순수 판정만 수행하며 부수 효과(engine 호출, UI 표시)는 호출자가 처리한다.
struct ToggleDetector {
    var pendingKeyCode: UInt16? = nil
    var expiredAt: CFAbsoluteTime = 0
    var fourKeysSeen: Set<UInt16> = []
    var allFourReached: Bool = false

    static let timeoutSeconds: CFAbsoluteTime = 0.5

    private static let fourKeys: Set<UInt16> = [
        KeyCode.leftCommand, KeyCode.rightCommand,
        KeyCode.leftOption, KeyCode.rightOption,
    ]

    /// keyDown 시 호출하여 진행 중인 감지 상태를 초기화한다.
    mutating func cancelOnKeyDown() {
        pendingKeyCode = nil
        fourKeysSeen.removeAll()
        allFourReached = false
    }

    /// flagsChanged 이벤트를 처리하여 토글 동작을 판정한다.
    ///
    /// - Parameters:
    ///   - keyCode: NSEvent.keyCode
    ///   - flags: NSEvent.modifierFlags
    ///   - toggleKey: 사용자 설정 전환 키
    ///   - now: 현재 시각 (테스트에서 주입 가능, 기본값: CFAbsoluteTimeGetCurrent())
    /// - Returns: 수행할 동작
    mutating func handleFlagsChanged(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        toggleKey: ToggleKey,
        now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) -> ToggleAction {
        // === 4키 English Lock 감지 ===

        // Step 1: 대상 키 → Set에 누적 (멱등, 중복 이벤트 무관)
        //         다른 modifier → 사이클 취소
        if Self.fourKeys.contains(keyCode) {
            fourKeysSeen.insert(keyCode)
        } else {
            fourKeysSeen.removeAll()
            allFourReached = false
        }

        // Step 2: 4키 모두 감지
        if fourKeysSeen.count == 4 {
            allFourReached = true
            pendingKeyCode = nil
        }

        // Step 3: 모든 modifier 해제 시
        let allReleased = !flags.contains(.command) && !flags.contains(.option)
        if allReleased {
            if allFourReached {
                fourKeysSeen.removeAll()
                allFourReached = false
                return .englishLockToggle
            }
            fourKeysSeen.removeAll()
        }

        // === 통합 modifier tap 감지 ===

        // shiftSpace는 keyDown 경로에서 처리
        guard let toggleKeyCode = toggleKey.keyCode,
              let toggleFlag = toggleKey.modifierFlag else {
            return .none
        }

        // ① 다중 modifier 가드 (CapsLock 제외)
        let activeCount: Int = [
            NSEvent.ModifierFlags.shift,
            NSEvent.ModifierFlags.command,
            NSEvent.ModifierFlags.option,
            NSEvent.ModifierFlags.control,
        ].filter { flags.contains($0) }.count
        if activeCount > 1 {
            pendingKeyCode = nil
            return .none
        }

        // ② 설정된 전환 키의 press 감지
        if keyCode == toggleKeyCode
            && flags.contains(toggleFlag)
            && pendingKeyCode == nil
            && !allFourReached {
            pendingKeyCode = keyCode
            expiredAt = now + Self.timeoutSeconds
            return .none
        }

        // ③ 설정된 전환 키의 release 감지
        if keyCode == toggleKeyCode
            && !flags.contains(toggleFlag) {
            if pendingKeyCode == keyCode
                && now < expiredAt {
                pendingKeyCode = nil
                return .toggle
            }
            pendingKeyCode = nil
            return .none
        }

        // ④ 다른 modifier 키 → pending 해제
        pendingKeyCode = nil
        return .none
    }
}
