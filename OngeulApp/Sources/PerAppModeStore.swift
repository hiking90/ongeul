import Foundation

/// 앱별 입력 모드를 인메모리로 저장하는 thread-safe 저장소.
final class PerAppModeStore {
    private var store: [String: InputMode] = [:]
    private let lock = NSLock()

    func savedMode(for bundleId: String) -> InputMode? {
        lock.lock()
        defer { lock.unlock() }
        return store[bundleId]
    }

    func saveMode(_ mode: InputMode, for bundleId: String) {
        lock.lock()
        defer { lock.unlock() }
        store[bundleId] = mode
    }
}

/// English Lock 상태를 UserDefaults에 저장하는 저장소.
///
/// 테스트에서 격리된 `UserDefaults(suiteName:)`을 주입할 수 있다.
final class EnglishLockStore {
    private let defaults: UserDefaults
    private let key = "EnglishLockApps"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 저장 형식: [String: String] — bundleId → 잠금 직전 모드 ("korean" / "english")
    func isLocked(_ bundleId: String) -> Bool {
        store()[bundleId] != nil
    }

    func addLock(for bundleId: String, previousMode: InputMode) {
        var s = store()
        s[bundleId] = previousMode == .korean ? "korean" : "english"
        defaults.set(s, forKey: key)
    }

    func removeLock(for bundleId: String) -> InputMode? {
        var s = store()
        guard let raw = s.removeValue(forKey: bundleId) else { return nil }
        defaults.set(s, forKey: key)
        return raw == "korean" ? .korean : .english
    }

    private func store() -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
