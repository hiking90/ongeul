import Foundation

/// 외부에서 기록된 키 증거 (CGEventTap.keyBuffer 같은).
/// FocusStealCorrector가 초기 read + 10ms 후 후발 read에 사용.
/// 테스트에서는 FakeKeyEvidence를 주입하여 결정론적 검증.
protocol KeyEvidenceSource: AnyObject {
    /// 버퍼를 반환하고 비운다.
    func consumeKeys() -> [RecordedKey]
}

/// 시간 제어 가능한 스케줄러 추상화.
/// Production: MainQueueScheduler (DispatchQueue.main).
/// Tests: ManualScheduler (advance(by:)로 시간 제어).
protocol Scheduler: AnyObject {
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledTask
    func scheduleImmediate(_ work: @escaping () -> Void) -> ScheduledTask
}

/// 스케줄러가 반환하는 취소 가능한 작업 핸들.
protocol ScheduledTask: AnyObject {
    func cancel()
}

/// 한글 엔진 인터페이스 (FocusStealCorrector가 필요로 하는 만큼만).
/// Production: InputStateCoordinator가 채택.
/// Tests: FakeModeController.
protocol FocusStealModeController: AnyObject {
    var currentMode: InputMode { get }
    func forceKoreanForReplay() -> ProcessResult
    func processKey(key: String) -> ProcessResult
}

/// FocusStealCorrector → 외부 (IMK client, CGEvent post) 부수효과 위임.
/// OngeulInputController가 채택.
protocol FocusStealDelegate: AnyObject {
    /// 한글 모드 강제 / 리플레이 결과를 IMK client에 적용.
    /// client가 부착되지 않은 상태에서 호출되면 no-op이어야 한다.
    func focusStealApplyResult(_ result: ProcessResult)

    /// 합성 backspace를 시스템에 post.
    func focusStealPostSyntheticBackspaces(count: Int)

    /// 한글 모드로 강제 전환됐으므로 메뉴바 아이콘 동기화.
    /// client가 부착되지 않은 상태에서 호출되면 no-op이어야 한다.
    func focusStealSyncIconKorean()

    /// replay 시점에 현재 활성 앱 bundleId.
    /// closure 캡처 시점과 비교하여 client identity 검증.
    var focusStealCurrentBundleId: String? { get }

    /// IMK client가 현재 부착되어 있는지.
    var focusStealHasAttachedClient: Bool { get }
}
