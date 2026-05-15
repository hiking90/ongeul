import Foundation
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "focusSteal")

/// 포커스 탈취 교정:
/// 입력창이 없는 상태에서 앱이 키를 가로채 영문을 삽입한 경우를 교정한다.
///
/// 1. startCorrection: 버퍼된 키를 확인, 조건 충족 시 한글 모드 강제 + 10ms 타이머 시작,
///    버퍼링 모드 진입.
/// 2. 10ms 동안 handle()을 거치는 키는 keyBuffer에 저장 (엔진 처리 안 함).
/// 3. 10ms 후 synthetic backspace 전송 → 시스템이 영문자 삭제.
/// 4. handle()이 backspace 수신 → backspace 카운트다운.
/// 5. 모든 backspace 소비되면 async replay → 버퍼 키를 엔진에 전달하여 한글 조합.
///
/// 동시성: 모든 메서드는 메인 스레드에서 호출되어야 한다 (IMK + DispatchQueue.main).
final class FocusStealCorrector {
    weak var delegate: FocusStealDelegate?

    private let evidence: KeyEvidenceSource
    private let scheduler: Scheduler
    private let mode: FocusStealModeController

    // 상태
    private var bufferingTask: ScheduledTask?
    private var replayTask: ScheduledTask?
    private var buffering = false
    private var expectingBackspace = 0
    private var replayPending = false
    private var keyBuffer: [String] = []
    private var preKeyCount = 0

    init(evidence: KeyEvidenceSource, scheduler: Scheduler, mode: FocusStealModeController) {
        self.evidence = evidence
        self.scheduler = scheduler
        self.mode = mode
    }

    // MARK: - Public API

    /// activateServer에서 (조건 검사 후) 호출. 보정 절차를 시작한다.
    /// evidence에서 키를 consume하여 검사하므로 호출자가 별도로 keyBuffer를
    /// 비우지 않는다.
    func startCorrection() {
        clearState()

        let buffer = evidence.consumeKeys()
        guard let firstKey = buffer.first else { return }

        let elapsed = CFAbsoluteTimeGetCurrent() - firstKey.timestamp
        guard elapsed < 0.5 else {
            os_log("focusSteal: skip — elapsed=%.3f > 0.5", log: log, type: .debug, elapsed)
            return
        }

        // 한글 모드 강제 (activateApp이 복원한 모드와 무관).
        // client 부착 여부와 무관하게 모드 자체는 변경; delegate가 client nil 가드.
        if mode.currentMode != .korean {
            let flushResult = mode.forceKoreanForReplay()
            delegate?.focusStealApplyResult(flushResult)
        }
        // 아이콘 동기화 (delegate가 client nil 가드).
        delegate?.focusStealSyncIconKorean()

        buffering = true
        keyBuffer = buffer.map { $0.character }
        preKeyCount = buffer.count

        os_log("focusSteal: buffering %d keys, elapsed=%.3f", log: log, type: .debug,
               preKeyCount, elapsed)

        bufferingTask = scheduler.schedule(after: 0.01) { [weak self] in
            self?.fireBufferingTimeout()
        }
    }

    /// activateServer/deactivateServer 진입 시 호출. 진행 중 작업 모두 취소.
    func cancel() {
        clearState()
    }

    /// handleKeyDown에서 가장 먼저 호출. 이 키를 corrector가 어떻게 다루는지 결정.
    /// keyLabel은 controller가 NSEvent에서 추출한 결과 (printable이 아니면 nil).
    func handle(keyCode: UInt16, keyLabel: String?) -> Handling {
        // 1) Synthetic backspace 카운트다운: 우리가 post한 backspace의 echo.
        if keyCode == KeyCode.backspace && expectingBackspace > 0 {
            expectingBackspace -= 1
            if expectingBackspace == 0 {
                scheduleReplay()
            }
            return .syntheticBackspaceConsumed
        }
        // 2) 버퍼링 가드: 세 가지 타이밍 모두 흡수.
        //    keyLabel이 nil(backspace/enter/arrow 등 non-printable)이어도 .consumed.
        if buffering || expectingBackspace > 0 || replayPending {
            if let label = keyLabel {
                keyBuffer.append(label)
            }
            return .consumed
        }
        return .passThrough
    }

    /// handle()의 반환 타입.
    enum Handling {
        /// 일반 키가 보정에 흡수됨. handleKeyDown은 return true.
        case consumed
        /// 우리의 합성 backspace. handleKeyDown은 return false (시스템 통과).
        case syntheticBackspaceConsumed
        /// corrector와 무관. 정상 라우팅으로 진행.
        case passThrough
    }

    // MARK: - Internal

    /// 10ms 후 호출: 후발 키 확인 + synthetic backspace post.
    private func fireBufferingTimeout() {
        bufferingTask = nil
        buffering = false

        // CGEventTap에 기록된 후발 키 확인.
        let lateKeys = evidence.consumeKeys()

        // handle() 버퍼링 가드에서 소비된 키 수.
        let imeConsumed = keyBuffer.count - preKeyCount
        // 앱에 직접 입력된 키 수 (IME를 거치지 않은 키).
        let appInserted = max(0, lateKeys.count - imeConsumed)

        if appInserted > 0 {
            // 앱에 입력된 키는 시간순으로 lateKeys 앞부분에 위치
            // (IME 활성화 전 → 앱 직접 입력, IME 활성화 후 → handle() 소비).
            let appKeys = lateKeys.prefix(appInserted).map { $0.character }
            keyBuffer.insert(contentsOf: appKeys, at: preKeyCount)
        }

        let totalBackspaces = preKeyCount + appInserted
        expectingBackspace = totalBackspaces

        os_log("focusSteal: sending %d backspaces (pre=%d late=%d)",
               log: log, type: .debug, totalBackspaces, preKeyCount, appInserted)

        delegate?.focusStealPostSyntheticBackspaces(count: totalBackspaces)
    }

    /// 모든 backspace 소비 후 호출: 버퍼된 키를 엔진에 replay.
    /// 예약 사이에 deactivateServer가 발생하면 replayTask가 cancel되어 실행되지 않는다.
    /// 활성 앱이 바뀌었으면 (다른 client 부착) replay 포기.
    private func scheduleReplay() {
        replayPending = true
        let targetBundleId = delegate?.focusStealCurrentBundleId
        replayTask?.cancel()
        replayTask = scheduler.scheduleImmediate { [weak self] in
            guard let self else { return }
            self.replayTask = nil
            self.replayPending = false
            let keys = self.keyBuffer
            self.keyBuffer = []
            guard !keys.isEmpty,
                  self.delegate?.focusStealCurrentBundleId == targetBundleId,
                  self.delegate?.focusStealHasAttachedClient == true
            else { return }
            for key in keys {
                let result = self.mode.processKey(key: key)
                self.delegate?.focusStealApplyResult(result)
            }
        }
    }

    /// 진행 중 작업 cancel + 모든 상태 리셋.
    /// startCorrection 진입 시 및 외부 cancel() 시 호출.
    private func clearState() {
        bufferingTask?.cancel()
        bufferingTask = nil
        replayTask?.cancel()
        replayTask = nil
        buffering = false
        expectingBackspace = 0
        replayPending = false
        keyBuffer = []
        preKeyCount = 0
    }
}
