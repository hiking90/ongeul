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
    private func setMode(_ mode: InputMode, syncCapsLock: Bool = true) {
        engine.setMode(mode: mode)
        KeyEventTap.currentInputMode = mode
        // LED 동기화는 CGEventTap이 설치된 경우에만 수행.
        // CGEventTap 미설치 시 IOHIDSet이 유발하는 flagsChanged를
        // shouldHandle로 필터링할 수 없어 재진입이 발생한다.
        if syncCapsLock && KeyEventTap.toggleKey == .capsLock
            && KeyEventTap.shared.isInstalled {
            CapsLockSync.setState(mode == .korean)
        }
    }

    private func toggleEngineMode() -> ProcessResult {
        let result = engine.toggleMode()
        let mode = engine.getMode()
        KeyEventTap.currentInputMode = mode
        // setMode()를 거치지 않는 별도 경로이므로 CapsLock 동기화를 직접 수행.
        if KeyEventTap.toggleKey == .capsLock
            && KeyEventTap.shared.isInstalled {
            CapsLockSync.setState(mode == .korean)
        }
        return result
    }

    // MARK: - Layout loading

    /// 레이아웃 로드. 초기 로드 시 영문 모드 설정, 재로드 시 조합 flush.
    func loadLayout(json: String, isInitialLoad: Bool) throws -> ProcessResult? {
        let flushResult = isInitialLoad ? nil : engine.flush()
        try engine.loadLayout(json: json)
        if isInitialLoad {
            // CapsLock 모드에서는 하드웨어 상태에 맞춤 (LED를 덮어쓰지 않음)
            if KeyEventTap.toggleKey == .capsLock && KeyEventTap.shared.isInstalled {
                let mode: InputMode = CapsLockSync.isHardwareOn() ? .korean : .english
                setMode(mode, syncCapsLock: false)
            } else {
                setMode(.english)
            }
        }
        return flushResult
    }

    // MARK: - State transitions

    /// 앱 활성화: 모드 복원, Lock 체크, 앱 전환 감지를 일괄 처리
    func activateApp(bundleId: String) -> StateEffect {
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

        // CapsLock 모드: 하드웨어 CapsLock 상태가 source of truth.
        // CapsLock은 전역 하드웨어 상태이므로, activeController가 nil인 동안
        // 사용자가 누른 CapsLock도 포커스 복귀 시 자동 반영된다.
        if KeyEventTap.toggleKey == .capsLock && KeyEventTap.shared.isInstalled {
            let capsLockOn = CapsLockSync.isHardwareOn()
            let mode: InputMode = capsLockOn ? .korean : .english
            setMode(mode, syncCapsLock: false)  // 이미 하드웨어와 일치
            perAppStore.saveMode(mode, for: bundleId)
            return StateEffect(lockOverlay: isAppSwitch ? .hide : nil)
        }

        // 일반 모드 복원
        let mode = perAppStore.savedMode(for: bundleId) ?? .english
        setMode(mode)
        perAppStore.saveMode(mode, for: bundleId)

        // 앱 전환 시 이전 앱과 모드가 다르면 인디케이터 표시
        let prevMode = isAppSwitch
            ? activeAppBundleId.flatMap { perAppStore.savedMode(for: $0) }
            : nil
        let modeChanged = prevMode != nil && prevMode != mode

        return StateEffect(
            showIndicator: modeChanged,
            lockOverlay: isAppSwitch ? .hide : nil
        )
    }

    /// 한/영 전환. Lock 상태면 nil 반환 (구조적 가드).
    func toggleMode(for bundleId: String?) -> StateEffect? {
        if isLocked(bundleId) { return nil }

        let result = toggleEngineMode()
        let newMode = engine.getMode()
        if let bundleId { perAppStore.saveMode(newMode, for: bundleId) }

        return StateEffect(processResult: result, showIndicator: true)
    }

    /// English Lock 토글
    func toggleLock(for bundleId: String) -> StateEffect {
        if lockStore.isLocked(bundleId) {
            engine.reset()  // 잠금 중 쌓인 detector 키 시퀀스 무효화
            if KeyEventTap.toggleKey == .capsLock && KeyEventTap.shared.isInstalled {
                // CapsLock 모드: 하드웨어 상태가 source of truth.
                // 잠금 중 사용자가 CapsLock을 토글했을 수 있으므로
                // previousMode 대신 현재 하드웨어 상태에 따라 모드 결정.
                _ = lockStore.removeLock(for: bundleId)
                let mode: InputMode = CapsLockSync.isHardwareOn() ? .korean : .english
                setMode(mode, syncCapsLock: false)  // 이미 하드웨어와 일치
                perAppStore.saveMode(mode, for: bundleId)
            } else {
                // 해제: 저장된 이전 모드 복원
                let previousMode = lockStore.removeLock(for: bundleId) ?? .korean
                setMode(previousMode)
                perAppStore.saveMode(previousMode, for: bundleId)
            }
            return StateEffect(lockOverlay: .show(locked: false))
        } else {
            // 잠금: 현재 모드 저장 -> 영어 강제
            let currentMode = engine.getMode()
            lockStore.addLock(for: bundleId, previousMode: currentMode)
            let flushResult = (currentMode == .korean) ? engine.flush() : nil
            // CapsLock 모드: LED를 건드리지 않음.
            // 잠금 중 CapsLock은 원래 기능(대문자)으로 동작하며,
            // 해제 시 하드웨어 상태에 따라 모드를 결정한다.
            setMode(.english, syncCapsLock: KeyEventTap.toggleKey != .capsLock)
            return StateEffect(
                processResult: flushResult,
                lockOverlay: .show(locked: true)
            )
        }
    }

    /// CapsLock 누름에 의한 모드 SET. flush + 모드 변경 + perAppStore 저장.
    /// CapsLock은 하드웨어가 이미 LED를 변경했으므로 syncCapsLock: false.
    func setCapsLockMode(korean: Bool, for bundleId: String?) -> StateEffect {
        let mode: InputMode = korean ? .korean : .english
        let flushResult = engine.flush()
        setMode(mode, syncCapsLock: false)
        if let bundleId { perAppStore.saveMode(mode, for: bundleId) }
        // CapsLock LED가 이미 모드를 표시하므로 인디케이터 미표시
        return StateEffect(processResult: flushResult, showIndicator: false)
    }

    /// ESC -> 영문 전환. 설정 비활성화 또는 이미 영문이면 nil.
    func escapeToEnglish(for bundleId: String?, enabled: Bool) -> StateEffect? {
        guard enabled, engine.getMode() == .korean else { return nil }
        setMode(.english)
        if let bundleId { perAppStore.saveMode(.english, for: bundleId) }
        return StateEffect(showIndicator: true)
    }

    /// Focus-steal correction: 한글 모드 강제 + flush + perAppStore 저장.
    /// activateApp이 복원한 모드와 무관하게 한글 모드를 강제한다.
    /// correctFocusSteal에서만 호출되며, 버퍼된 키를 한글로 리플레이하기 위한 전제 조건.
    func forceKoreanForReplay(for bundleId: String?) -> ProcessResult {
        let flushResult = engine.flush()
        setMode(.korean)
        if let bundleId { perAppStore.saveMode(.korean, for: bundleId) }
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
