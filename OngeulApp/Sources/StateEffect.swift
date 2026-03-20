/// 모든 상태 전이의 결과를 하나의 타입으로 표현한다.
/// Coordinator의 State transition 메서드가 반환하며, Controller의 applyEffect()가 소비한다.
struct StateEffect {
    /// 클라이언트에 적용할 엔진 결과 (committed/composing)
    var processResult: ProcessResult? = nil
    /// 모드 인디케이터 표시 여부
    var showIndicator: Bool = false
    /// Lock 오버레이 동작
    var lockOverlay: LockOverlayAction? = nil

    enum LockOverlayAction {
        case show(locked: Bool)
        case hide
    }
}
