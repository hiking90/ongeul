import Cocoa
import Carbon
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "inputSourceLock")

final class InputSourceLock: NSObject {
    static let shared = InputSourceLock()

    private static let ongeulKoreanId = "io.github.hiking90.inputmethod.Ongeul"
    private static let ongeulEnglishId = "io.github.hiking90.inputmethod.Ongeul.English"
    private static let ongeulInputSourceIds: Set<String> = [
        ongeulKoreanId,
        ongeulEnglishId,
    ]

    private var isObserving = false
    /// 복귀 대상 입력 소스. 사용자가 한쪽만 enable해도 동작하도록 동적으로 선택.
    /// 우선순위: English > Korean. 캐시가 무효화되면 `refreshCache()`로 재조회.
    private var cachedInputSource: TISInputSource?
    private var lastSwitchTime: CFAbsoluteTime = 0
    private let minimumInterval: CFAbsoluteTime = 0.3  // 300ms 디바운스
    private var activityToken: NSObjectProtocol?
    private var wakeTimer: Timer?
    /// 디바운스 윈도우에 걸려 무시된 호출의 1회 재시도용 타이머.
    /// 디바운스 직후 OS가 다시 ABC로 돌려놓는 race에서 사용자가 갇히는 것을 방지.
    private var debounceRetryTimer: Timer?
    /// ABC 전환 시점에 Ongeul IMK 세션이 살아 있으면, 그 세션의 deactivateServer가 올 때까지
    /// 복귀를 미룬다. 앱은 TIS 변경을 비동기로 처리하므로, 앱이 ABC 전환을 처리하기 전에
    /// 직전과 같은 Ongeul 모드로 되돌리면(English → ABC → English) 앱은 ABC 전환에 대한
    /// deactivate만 하고, 현재 소스가 직전과 같아 activate하지 않는다. 그러면 TIS는 Ongeul인데
    /// 키 입력이 Ongeul을 거치지 않는 상태가 포커스가 바뀔 때까지 이어진다 (#28).
    /// deactivate가 오지 않는 경우(activeController가 stale 등)를 위해 상한을 둔다.
    private var deactivateWaitTimer: Timer?
    private let deactivateWaitLimit: TimeInterval = 0.3

    private override init() {
        super.init()
    }

    /// 감시 시작 — 설정 활성화 시 또는 앱 시작 시 호출
    func start() {
        guard !isObserving else { return }
        isObserving = true

        // Ongeul TISInputSource를 캐싱하여 매 notification마다 검색하지 않음
        _ = refreshCache()

        // App Nap 방지 — notification 전달 지연 차단
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "InputSourceLock: monitoring"
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
        // Sleep/Wake, 화면 잠금 해제 감시
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        os_log("InputSourceLock: started", log: log, type: .default)
    }

    /// 감시 중지 — 설정 비활성화 시 호출
    func stop() {
        guard isObserving else { return }
        isObserving = false
        cachedInputSource = nil

        wakeTimer?.invalidate()
        wakeTimer = nil

        debounceRetryTimer?.invalidate()
        debounceRetryTimer = nil

        deactivateWaitTimer?.invalidate()
        deactivateWaitTimer = nil

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }

        NSWorkspace.shared.notificationCenter.removeObserver(self)

        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
        os_log("InputSourceLock: stopped", log: log, type: .default)
    }

    /// Ongeul 입력 소스 캐시를 갱신.
    /// 사용자가 한쪽만 enable해도 복귀가 가능하도록, 번들 ID로 enabled 소스를 조회하여
    /// English 우선, 없으면 Korean을 선택한다. 둘 다 disabled면 캐시를 비우고 nil 반환.
    ///
    /// English를 우선하는 이유: 복귀는 ABC 같은 ASCII keyboard layout으로 전환되었을 때만
    /// 일어나므로, 그 전환이 요청한 입력은 영문이다. 한글 모드로 쓰던 중 OS가 ABC로
    /// 바꾼 경우에도 영문 모드로 복귀하며, 그 앱의 per-app 저장 모드도 영문으로 바뀐다.
    ///
    /// 번들 ID로 조회하면 IME 상위 항목(`TISTypeKeyboardInputMethodModeEnabled`)도 함께 나오는데,
    /// 이 항목은 Korean 모드와 같은 InputSourceID를 가지면서 선택이 불가능하다
    /// (`TISSelectInputSource` → -50). 따라서 select-capable 항목으로 한정한다.
    private func refreshCache() -> TISInputSource? {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            cachedInputSource = nil
            return nil
        }
        let filter = [
            kTISPropertyBundleID: bundleId,
            kTISPropertyInputSourceIsSelectCapable: true,
        ] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              !sources.isEmpty
        else {
            cachedInputSource = nil
            os_log("InputSourceLock: no enabled Ongeul input source", log: log, type: .default)
            return nil
        }

        // English를 우선 탐색, 없으면 첫 번째 enabled 소스 (Korean)
        let english = sources.first { src in
            let id = unsafeBitCast(
                TISGetInputSourceProperty(src, kTISPropertyInputSourceID),
                to: CFString.self
            ) as String
            return id == Self.ongeulEnglishId
        }

        let chosen = english ?? sources.first
        cachedInputSource = chosen
        if let chosen {
            let id = unsafeBitCast(
                TISGetInputSourceProperty(chosen, kTISPropertyInputSourceID),
                to: CFString.self
            ) as String
            os_log("InputSourceLock: cache refreshed → %{public}@", log: log, type: .default, id)
        }
        return chosen
    }

    /// 현재 입력 소스를 확인하고, Ongeul이 아닌 keyboard layout이면 복귀한다.
    /// notification, wake, unlock, activateServer 등 다양한 경로에서 호출.
    /// activateServer 경로는 호출한 세션 자신이 activeController이므로 deactivate를 기다리지 않는다.
    func verifyAndRecover(source: String = "notification") {
        verifyAndRecover(source: source, waitsForDeactivate: source != "activateServer")
    }

    /// OngeulInputController.deactivateServer 끝에서 호출. 복귀가 deactivate를 기다리는 중이면
    /// 지금 진행한다. deactivateServer가 IMK로 반환된 뒤 실행되도록 다음 run loop로 넘긴다.
    func sessionDidDeactivate() {
        guard let timer = deactivateWaitTimer else { return }
        timer.invalidate()
        deactivateWaitTimer = nil
        DispatchQueue.main.async { [weak self] in
            self?.verifyAndRecover(source: "after-deactivate", waitsForDeactivate: false)
        }
    }

    private func verifyAndRecover(source: String, waitsForDeactivate: Bool) {
        guard isObserving else { return }

        // 디바운스: 짧은 시간 내 반복 전환 방지.
        // 윈도우 내 호출은 즉시 무시하되, 디바운스 직후 OS가 다시 ABC로 돌려놓는
        // race에 대비해 1회 재시도를 예약한다 (사용자가 ABC에 갇히는 것 방지).
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastSwitchTime
        if elapsed <= minimumInterval {
            if debounceRetryTimer == nil {
                let delay = (minimumInterval - elapsed) + 0.05
                let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                    self?.debounceRetryTimer = nil
                    self?.verifyAndRecover(source: "debounce-retry")
                }
                RunLoop.main.add(timer, forMode: .common)
                debounceRetryTimer = timer
            }
            return
        }

        // 보안 입력 활성 시 (암호 필드 등) → 복귀하지 않음
        if IsSecureEventInputEnabled() {
            os_log("InputSourceLock: skip — secure input active (via %{public}@)",
                   log: log, type: .info, source)
            return
        }

        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }

        let currentId = unsafeBitCast(
            TISGetInputSourceProperty(current, kTISPropertyInputSourceID),
            to: CFString.self
        ) as String

        // 이미 Ongeul이면 무시 (자기 자신의 TISSelectInputSource 호출에 의한 재진입 방지)
        if Self.ongeulInputSourceIds.contains(currentId) { return }

        // ABC 등 keyboard layout만 차단, 다른 IME(일본어, 중국어 등)는 허용
        let sourceType = unsafeBitCast(
            TISGetInputSourceProperty(current, kTISPropertyInputSourceType),
            to: CFString.self
        ) as String
        if sourceType != kTISTypeKeyboardLayout as String {
            os_log("InputSourceLock: skip — non-keyboard-layout: %{public}@ (via %{public}@)",
                   log: log, type: .info, currentId, source)
            return
        }

        // keyboard layout 중에서도 ASCII-capable인 것(ABC, U.S. 등)만 차단한다.
        // Russian, Greek 같은 layout은 Ongeul이 대신할 수 없는 입력이므로 다른 IME처럼 허용한다.
        // 복귀 대상이 English 모드인 근거(`refreshCache()`)도 이 조건에 의존한다.
        let isASCIICapable = TISGetInputSourceProperty(current, kTISPropertyInputSourceIsASCIICapable)
            .map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) }
            ?? false
        if !isASCIICapable {
            os_log("InputSourceLock: skip — non-ASCII keyboard layout: %{public}@ (via %{public}@)",
                   log: log, type: .info, currentId, source)
            return
        }

        // 앱이 아직 ABC 전환을 처리하지 않아 Ongeul 세션이 살아 있으면 deactivate까지 미룬다.
        // 대기 중에 들어온 다른 호출은 버린다 — 대기가 끝나면 그 시점의 소스로 다시 판정한다.
        if deactivateWaitTimer != nil { return }
        if waitsForDeactivate, KeyEventTap.activeController != nil {
            os_log("InputSourceLock: waiting for deactivate before recovery (via %{public}@)",
                   log: log, type: .default, source)
            let timer = Timer(timeInterval: deactivateWaitLimit, repeats: false) { [weak self] _ in
                self?.deactivateWaitTimer = nil
                self?.verifyAndRecover(source: "deactivate-timeout", waitsForDeactivate: false)
            }
            RunLoop.main.add(timer, forMode: .common)
            deactivateWaitTimer = timer
            return
        }

        // 캐싱된 Ongeul 입력 소스로 복귀 (캐시 없으면 갱신 시도)
        guard let ongeul = cachedInputSource ?? refreshCache() else {
            os_log("InputSourceLock: Ongeul input source not found (via %{public}@)",
                   log: log, type: .error, source)
            return
        }

        lastSwitchTime = now
        let err = TISSelectInputSource(ongeul)
        if err != noErr {
            // 캐시된 TISInputSource가 무효화된 경우 — 갱신 후 1회 재시도
            os_log("InputSourceLock: TISSelectInputSource failed (err=%d), refreshing cache (via %{public}@)",
                   log: log, type: .error, err, source)
            if let fresh = refreshCache() {
                let retryErr = TISSelectInputSource(fresh)
                os_log("InputSourceLock: retry result (err=%d) (via %{public}@)",
                       log: log, type: .default, retryErr, source)
            }
        } else {
            let targetId = unsafeBitCast(
                TISGetInputSourceProperty(ongeul, kTISPropertyInputSourceID),
                to: CFString.self
            ) as String
            os_log("InputSourceLock: switched back from %{public}@ to %{public}@ (via %{public}@)",
                   log: log, type: .default, currentId, targetId, source)
        }
    }

    @objc private func inputSourceChanged() {
        verifyAndRecover(source: "notification")
    }

    @objc private func systemDidWake() {
        os_log("InputSourceLock: system woke", log: log, type: .default)
        scheduleWakeRecover(delay: 1.0, source: "wake")
    }

    @objc private func screenDidUnlock() {
        os_log("InputSourceLock: screen unlocked", log: log, type: .default)
        scheduleWakeRecover(delay: 0.5, source: "unlock")
    }

    /// wake/unlock 공용 — 이전 타이머를 취소하고 새로 예약하여 중복 방지
    private func scheduleWakeRecover(delay: TimeInterval, source: String) {
        wakeTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.wakeTimer = nil
            self?.verifyAndRecover(source: source)
        }
        RunLoop.main.add(timer, forMode: .common)
        wakeTimer = timer
    }
}
