import Foundation

/// Focus-steal correction에서 사용하는 키 기록.
/// CGEventTap이 시스템 레벨에서 잡은 키와 해당 시각을 보관한다.
struct RecordedKey {
    let character: String
    let timestamp: CFAbsoluteTime
}
