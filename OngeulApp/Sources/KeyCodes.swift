enum KeyCode {
    static let enter: UInt16      = 36
    static let numpadEnter: UInt16 = 76
    static let space: UInt16      = 49
    static let backspace: UInt16  = 51
    static let escape: UInt16     = 53
    static let rightCommand: UInt16 = 54
    static let leftCommand: UInt16 = 55
    static let leftShift: UInt16  = 56
    static let capsLock: UInt16   = 57
    static let leftOption: UInt16 = 58
    static let rightShift: UInt16 = 60
    static let rightOption: UInt16 = 61
    static let leftBracket: UInt16 = 0x21  // [ key
    static let arrowLeft: UInt16  = 123
    static let arrowRight: UInt16 = 124
    static let arrowDown: UInt16  = 125
    static let arrowUp: UInt16    = 126

    /// 키패드(텐키) 키코드 집합. Enter(0x4C)는 제외 — 일반 Enter와 통합 처리.
    /// kVK_ANSI_Keypad* (Decimal, Multiply, Plus, Clear, Divide, Minus, Equals, 0-9)
    static let numpadKeys: Set<UInt16> = [
        0x41, 0x43, 0x45, 0x47, 0x4B, 0x4E, 0x51,
        0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C,
    ]
}
