import Foundation

// MARK: - Production adapters for FocusStealCorrector dependencies

/// CGEventTap의 keyBuffer를 KeyEvidenceSource로 노출.
final class CGEventTapKeyEvidence: KeyEvidenceSource {
    func consumeKeys() -> [RecordedKey] {
        let buffer = KeyEventTap.keyBuffer
        KeyEventTap.keyBuffer = []
        return buffer
    }
}

/// DispatchQueue.main 기반 Scheduler.
final class MainQueueScheduler: Scheduler {
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledTask {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return DispatchWorkItemTask(item: item)
    }

    func scheduleImmediate(_ work: @escaping () -> Void) -> ScheduledTask {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.async(execute: item)
        return DispatchWorkItemTask(item: item)
    }
}

/// DispatchWorkItem을 ScheduledTask로 감싸는 wrapper.
final class DispatchWorkItemTask: ScheduledTask {
    private let item: DispatchWorkItem

    init(item: DispatchWorkItem) {
        self.item = item
    }

    func cancel() {
        item.cancel()
    }
}
