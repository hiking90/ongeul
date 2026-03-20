import Carbon
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "inputSourceLock")

final class InputSourceLock: NSObject {
    static let shared = InputSourceLock()

    private static let ongeulInputSourceId = "io.github.hiking90.inputmethod.Ongeul"

    private var isObserving = false
    private var cachedInputSource: TISInputSource?
    private var lastSwitchTime: CFAbsoluteTime = 0
    private let minimumInterval: CFAbsoluteTime = 0.3  // 300ms 디바운스

    private override init() {
        super.init()
    }

    /// 감시 시작 — 설정 활성화 시 또는 앱 시작 시 호출
    func start() {
        guard !isObserving else { return }
        isObserving = true

        // Ongeul TISInputSource를 캐싱하여 매 notification마다 검색하지 않음
        let filter = [kTISPropertyInputSourceID: Self.ongeulInputSourceId] as CFDictionary
        if let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] {
            cachedInputSource = sources.first
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
        os_log("InputSourceLock: started", log: log, type: .default)
    }

    /// 감시 중지 — 설정 비활성화 시 호출
    func stop() {
        guard isObserving else { return }
        isObserving = false
        cachedInputSource = nil

        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
        os_log("InputSourceLock: stopped", log: log, type: .default)
    }

    @objc private func inputSourceChanged() {
        // 디바운스: 짧은 시간 내 반복 전환 방지
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSwitchTime > minimumInterval else { return }

        // 보안 입력 활성 시 (암호 필드 등) → 복귀하지 않음
        if IsSecureEventInputEnabled() {
            os_log("InputSourceLock: skip — secure input active", log: log, type: .debug)
            return
        }

        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }

        let currentId = unsafeBitCast(
            TISGetInputSourceProperty(current, kTISPropertyInputSourceID),
            to: CFString.self
        ) as String

        // 이미 Ongeul이면 무시 (자기 자신의 TISSelectInputSource 호출에 의한 재진입 방지)
        if currentId == Self.ongeulInputSourceId { return }

        // ABC 등 keyboard layout만 차단, 다른 IME(일본어, 중국어 등)는 허용
        let sourceType = unsafeBitCast(
            TISGetInputSourceProperty(current, kTISPropertyInputSourceType),
            to: CFString.self
        ) as String
        if sourceType != kTISTypeKeyboardLayout as String {
            os_log("InputSourceLock: skip — non-keyboard-layout: %{public}@",
                   log: log, type: .debug, currentId)
            return
        }

        // 캐싱된 Ongeul 입력 소스로 복귀
        guard let ongeul = cachedInputSource else {
            os_log("InputSourceLock: Ongeul input source not cached", log: log, type: .error)
            return
        }

        lastSwitchTime = now
        let err = TISSelectInputSource(ongeul)
        os_log("InputSourceLock: switched back from %{public}@ (err=%d)",
               log: log, type: .default, currentId, err)
    }
}
