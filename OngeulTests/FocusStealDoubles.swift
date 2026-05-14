import Foundation

// MARK: - FakeKeyEvidence

/// 테스트 주입용 evidence: 호출 시 반환할 키 배열을 미리 enqueue해둔다.
final class FakeKeyEvidence: KeyEvidenceSource {
    /// consumeKeys()가 차례로 반환할 배열들. pop_front 동작.
    var queuedBatches: [[RecordedKey]] = []
    /// 호출 횟수 (검증용).
    private(set) var consumeCallCount = 0

    func consumeKeys() -> [RecordedKey] {
        consumeCallCount += 1
        if queuedBatches.isEmpty { return [] }
        return queuedBatches.removeFirst()
    }
}

// MARK: - ManualScheduler

/// 시간을 명시적으로 advance(by:) 호출로 흐르게 하는 스케줄러.
/// 모든 task는 main queue가 아닌 내부 우선순위 큐에 들어가며,
/// advance가 호출되는 즉시 동기 실행된다.
final class ManualScheduler: Scheduler {
    private(set) var now: TimeInterval = 0

    private final class Task: ScheduledTask {
        let fireTime: TimeInterval
        let work: () -> Void
        var cancelled = false
        init(fireTime: TimeInterval, work: @escaping () -> Void) {
            self.fireTime = fireTime
            self.work = work
        }
        func cancel() { cancelled = true }
    }

    private var pending: [Task] = []

    /// 현재 큐에 있는(취소되지 않은) 작업 수.
    var pendingTaskCount: Int { pending.filter { !$0.cancelled }.count }

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledTask {
        let task = Task(fireTime: now + delay, work: work)
        pending.append(task)
        return task
    }

    func scheduleImmediate(_ work: @escaping () -> Void) -> ScheduledTask {
        // 즉시 실행이라도 advance를 강제하지 않는다 — `runImmediates()`로 별도 트리거.
        let task = Task(fireTime: now, work: work)
        pending.append(task)
        return task
    }

    /// 시간을 진행시켜 fireTime <= now인 task들을 시간순으로 실행.
    func advance(by interval: TimeInterval) {
        now += interval
        runDueTasks()
    }

    /// 시간 변동 없이 fireTime == now인 즉시 task들만 실행.
    func runImmediates() {
        runDueTasks()
    }

    private func runDueTasks() {
        // 시간순 정렬 후 fireTime <= now인 것을 cancelled 체크하며 실행.
        // 실행 중 새 task가 추가될 수 있으므로 loop.
        while true {
            pending.sort { $0.fireTime < $1.fireTime }
            guard let idx = pending.firstIndex(where: { !$0.cancelled && $0.fireTime <= now }) else {
                break
            }
            let task = pending.remove(at: idx)
            task.work()
        }
    }
}

// MARK: - FakeModeController

final class FakeModeController: FocusStealModeController {
    var currentMode: InputMode = .english
    var processKeyResult: (String) -> ProcessResult = { _ in
        ProcessResult(committed: nil, composing: nil, handled: true)
    }
    var forceKoreanResult: ProcessResult = ProcessResult(committed: nil, composing: nil, handled: true)

    private(set) var processedKeys: [String] = []
    private(set) var forceKoreanCallCount = 0

    func forceKoreanForReplay() -> ProcessResult {
        forceKoreanCallCount += 1
        currentMode = .korean
        return forceKoreanResult
    }

    func processKey(key: String) -> ProcessResult {
        processedKeys.append(key)
        return processKeyResult(key)
    }
}

// MARK: - SpyFocusStealDelegate

final class SpyFocusStealDelegate: FocusStealDelegate {
    var bundleId: String? = "com.test.app"
    var hasAttachedClient: Bool = true

    private(set) var appliedResults: [ProcessResult] = []
    private(set) var postedBackspacesCalls: [Int] = []
    private(set) var iconSyncCount = 0

    func focusStealApplyResult(_ result: ProcessResult) {
        // 실제 controller 구현이 client nil 시 no-op이므로 동일하게 흉내.
        if hasAttachedClient {
            appliedResults.append(result)
        }
    }

    func focusStealPostSyntheticBackspaces(count: Int) {
        postedBackspacesCalls.append(count)
    }

    func focusStealSyncIconKorean() {
        if hasAttachedClient {
            iconSyncCount += 1
        }
    }

    var focusStealCurrentBundleId: String? { bundleId }
    var focusStealHasAttachedClient: Bool { hasAttachedClient }
}
