import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "coordinator")

/// 상태 전이 로직 전담. Engine, PerAppModeStore, EnglishLockStore를 소유.
/// UI 의존성 없음. KeyEventTap.currentInputMode 동기화는 CGEvent 레벨의 상태 동기화이므로 여기서 담당.
final class InputStateCoordinator {
    private let engine = HangulEngine()
    private let perAppStore = PerAppModeStore()
    private let lockStore = EnglishLockStore()
    private(set) var activeAppBundleId: String?

    // MARK: - Read-only

    var mode: InputMode { engine.getMode() }

    func isLocked(_ bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return lockStore.isLocked(bundleId)
    }

    // MARK: - Engine passthrough
    // SAFETY: 아래 메서드들은 모드/스토어 부수효과 없음.
    // 향후 모드 변경이 수반되는 로직이 필요하면 passthrough가 아닌
    // State transition 메서드로 승격해야 한다.

    func processKey(key: String) -> ProcessResult { engine.processKey(key: key) }
    func backspace() -> ProcessResult { engine.backspace() }
    func flush() -> ProcessResult { engine.flush() }

    // MARK: - Private: 모드 변경 + KeyEventTap 동기화

    /// 모드 변경 + KeyEventTap 동기화.
    /// KeyEventTap은 CGEvent 레벨에서 현재 모드를 참조하므로(Control+[ 필터링, keyBuffer 기록),
    /// 모든 모드 변경 시 반드시 동기화해야 한다.
    private func setMode(_ mode: InputMode) {
        engine.setMode(mode: mode)
        KeyEventTap.currentInputMode = mode
    }

    private func toggleEngineMode() -> ProcessResult {
        let result = engine.toggleMode()
        KeyEventTap.currentInputMode = engine.getMode()
        return result
    }

    // MARK: - Layout loading

    /// 레이아웃 로드. 초기 로드 시 영문 모드 설정, 재로드 시 조합 flush.
    func loadLayout(json: String, isInitialLoad: Bool) throws -> ProcessResult? {
        let flushResult = isInitialLoad ? nil : engine.flush()
        try engine.loadLayout(json: json)
        if isInitialLoad { setMode(.english) }
        return flushResult
    }

    // MARK: - State transitions

    /// 앱 활성화: 모드 복원, Lock 체크, 앱 전환 감지를 일괄 처리.
    /// `systemMode`: 현재 macOS TIS가 가리키는 Ongeul 모드 (있다면). 메뉴바에서 사용자가
    /// 직접 전환한 경우 TIS와 엔진 모드가 다르므로, 이때는 TIS를 우선하여 per-app 기본값이
    /// 사용자 선택을 덮어쓰지 않도록 한다.
    func activateApp(bundleId: String, systemMode: InputMode? = nil) -> StateEffect {
        let isAppSwitch = (bundleId != activeAppBundleId)
        defer { activeAppBundleId = bundleId }

        // 앱 전환 시 이전 앱의 상태 초기화.
        // Phase 1: reset()은 오토마타 flush만 수행. deactivateServer가 이미 flush했으므로 실질적으로 no-op.
        // Phase 3: reset()에 detector 리셋이 추가되면, 이전 앱의 키 시퀀스를 무효화하는 역할을 한다.
        if isAppSwitch { engine.reset() }

        // English Lock 우선
        if lockStore.isLocked(bundleId) {
            setMode(.english)
            return StateEffect(
                lockOverlay: isAppSwitch ? .show(locked: true) : nil
            )
        }

        // 모드 결정 우선순위:
        // 1. systemMode가 현재 엔진 모드와 다르면 → 사용자가 메뉴바에서 직접 전환. TIS 우선.
        // 2. per-app 저장 모드 → 앱별 기억 복원.
        // 3. systemMode (fallback) → 최초 활성화 시 TIS 따름.
        // 4. .english (최종 기본값).
        let mode: InputMode
        if let systemMode, systemMode != engine.getMode() {
            mode = systemMode
        } else if let stored = perAppStore.savedMode(for: bundleId) {
            mode = stored
        } else if let systemMode {
            mode = systemMode
        } else {
            mode = .english
        }
        setMode(mode)
        perAppStore.saveMode(mode, for: bundleId)

        // 앱 전환 시 이전 앱과 모드가 다르면 아이콘 동기화
        let prevMode = isAppSwitch
            ? activeAppBundleId.flatMap { perAppStore.savedMode(for: $0) }
            : nil
        let modeChanged = prevMode != nil && prevMode != mode

        return StateEffect(
            modeChanged: modeChanged,
            lockOverlay: isAppSwitch ? .hide : nil
        )
    }

    /// 한/영 전환. Lock 상태면 nil 반환 (구조적 가드).
    func toggleMode(for bundleId: String?) -> StateEffect? {
        if isLocked(bundleId) { return nil }

        let result = toggleEngineMode()
        let newMode = engine.getMode()
        if let bundleId { perAppStore.saveMode(newMode, for: bundleId) }

        return StateEffect(processResult: result, modeChanged: true)
    }

    /// English Lock 토글
    func toggleLock(for bundleId: String) -> StateEffect {
        if lockStore.isLocked(bundleId) {
            // 해제: 저장된 이전 모드 복원 + detector 리셋
            let previousMode = lockStore.removeLock(for: bundleId) ?? .korean
            setMode(previousMode)
            engine.reset()  // 잠금 중 쌓인 detector 키 시퀀스 무효화
            perAppStore.saveMode(previousMode, for: bundleId)
            return StateEffect(lockOverlay: .show(locked: false))
        } else {
            // 잠금: 현재 모드 저장 -> 영어 강제
            let currentMode = engine.getMode()
            lockStore.addLock(for: bundleId, previousMode: currentMode)
            let flushResult = (currentMode == .korean) ? engine.flush() : nil
            setMode(.english)
            return StateEffect(
                processResult: flushResult,
                lockOverlay: .show(locked: true)
            )
        }
    }

    /// 시스템 발 모드 변경 (setValue:forTag:client: 경유).
    /// UI/아이콘은 이미 시스템이 변경했으므로 내부 상태만 동기화.
    /// flush 결과를 반환하여 호출자가 client에 적용할 수 있도록 한다.
    func setModeFromExternal(_ mode: InputMode, for bundleId: String?) -> ProcessResult? {
        let flushResult = (self.mode == .korean) ? engine.flush() : nil
        setMode(mode)
        if let bundleId { perAppStore.saveMode(mode, for: bundleId) }
        return flushResult
    }

    /// ESC -> 영문 전환. 설정 비활성화 또는 이미 영문이면 nil.
    func escapeToEnglish(for bundleId: String?, enabled: Bool) -> StateEffect? {
        guard enabled, engine.getMode() == .korean else { return nil }
        setMode(.english)
        if let bundleId { perAppStore.saveMode(.english, for: bundleId) }
        return StateEffect(modeChanged: true)
    }

    /// Focus-steal correction: 한글 모드 강제 + flush.
    /// activateApp이 복원한 모드와 무관하게 한글 모드를 강제한다.
    /// correctFocusSteal에서만 호출되며, 버퍼된 키를 한글로 리플레이하기 위한 전제 조건.
    ///
    /// perAppStore는 의도적으로 갱신하지 않는다: focus-steal은 *일시적* 보정이며,
    /// 사용자의 명시적 의도(토글/메뉴바/외부 변경/비활성화 시 저장)와 구분되어야 한다.
    /// 사용자가 그 앱을 한글 기본으로 쓰고자 한다면 다른 경로(토글 등)에서 학습된다.
    func forceKoreanForReplay() -> ProcessResult {
        let flushResult = engine.flush()
        setMode(.korean)
        return flushResult
    }

    /// 비활성화: 모드 저장 + flush. 호출자가 Chromium 여부에 따라 적용 결정.
    func deactivate(for bundleId: String?) -> ProcessResult {
        if let bundleId {
            perAppStore.saveMode(engine.getMode(), for: bundleId)
        }
        return engine.flush()
    }
}
