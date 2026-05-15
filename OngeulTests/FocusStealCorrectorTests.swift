import XCTest

/// FocusStealCorrector의 상태 머신, 타이밍 race, 라이프사이클 시나리오를
/// 결정론적으로 검증한다. ManualScheduler를 통해 10ms 대기와 async replay를
/// 동기적으로 제어한다.
final class FocusStealCorrectorTests: XCTestCase {
    private var evidence: FakeKeyEvidence!
    private var scheduler: ManualScheduler!
    private var mode: FakeModeController!
    private var delegate: SpyFocusStealDelegate!
    private var corrector: FocusStealCorrector!

    override func setUp() {
        super.setUp()
        evidence = FakeKeyEvidence()
        scheduler = ManualScheduler()
        mode = FakeModeController()
        delegate = SpyFocusStealDelegate()
        corrector = FocusStealCorrector(
            evidence: evidence,
            scheduler: scheduler,
            mode: mode
        )
        corrector.delegate = delegate
    }

    // MARK: - 유틸

    /// 신선한 timestamp (elapsed < 0.5 통과).
    /// corrector는 CFAbsoluteTimeGetCurrent()로 elapsed 측정하므로 wall clock 기준.
    private func key(_ char: String, atOffset offset: TimeInterval = 0) -> RecordedKey {
        RecordedKey(character: char, timestamp: CFAbsoluteTimeGetCurrent() + offset)
    }

    /// 활성 보정의 전형적 흐름(보정 시작 → 10ms 대기 → backspace 소비) 를 진행.
    /// 입력: 초기 버퍼. 호출 후 expectingBackspace > 0 상태가 된다.
    private func startAndAdvanceToBackspacePhase(initialBuffer: [RecordedKey],
                                                 lateBuffer: [RecordedKey] = []) {
        evidence.queuedBatches = [initialBuffer, lateBuffer]
        corrector.startCorrection()
        scheduler.advance(by: 0.01)  // 10ms 대기 종료
    }

    // MARK: - T1: Happy path

    func testHappyPath_twoKeysReplayedAfterBackspaces() {
        // 이미 한글 모드 — forceKorean 경로는 T13에서 별도 검증.
        mode.currentMode = .korean
        let buffer: [RecordedKey] = [key("d"), key("k")]
        startAndAdvanceToBackspacePhase(initialBuffer: buffer)

        // 모드는 유지, 아이콘 동기화는 항상 호출
        XCTAssertEqual(mode.forceKoreanCallCount, 0)
        XCTAssertEqual(mode.currentMode, .korean)
        XCTAssertEqual(delegate.iconSyncCount, 1)

        // backspace 2개 post
        XCTAssertEqual(delegate.postedBackspacesCalls, [2])

        // backspace 응답으로 카운트다운
        XCTAssertEqual(corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil),
                       .syntheticBackspaceConsumed)
        XCTAssertEqual(corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil),
                       .syntheticBackspaceConsumed)

        // 마지막 backspace 후 immediate replay 예약 → run
        scheduler.runImmediates()

        // 2개 키가 mode.processKey로 흘러갔고 결과가 적용됨
        XCTAssertEqual(mode.processedKeys, ["d", "k"])
        XCTAssertEqual(delegate.appliedResults.count, 2)
    }

    // MARK: - T2: 빈 버퍼

    func testEmptyBuffer_doesNothing() {
        evidence.queuedBatches = [[]]
        corrector.startCorrection()
        XCTAssertEqual(scheduler.pendingTaskCount, 0)
        XCTAssertEqual(delegate.postedBackspacesCalls, [])
        XCTAssertEqual(mode.forceKoreanCallCount, 0)
    }

    // MARK: - T3: 500ms 초과한 키 → skip

    func testStaleKeys_skip() {
        // wall clock - 1.0초 (>0.5 임계값)
        let staleKey = RecordedKey(character: "d", timestamp: CFAbsoluteTimeGetCurrent() - 1.0)
        evidence.queuedBatches = [[staleKey]]
        corrector.startCorrection()
        XCTAssertEqual(scheduler.pendingTaskCount, 0)
        XCTAssertEqual(delegate.postedBackspacesCalls, [])
    }

    // MARK: - T4: 10ms 대기 중 evidence에 후발 키 도착

    func testLateAppKeys_addedToBackspaceCount() {
        mode.currentMode = .korean
        let initial: [RecordedKey] = [key("d"), key("k")]
        // 후발 키 3개 — 모두 앱에 직접 입력된 것으로 처리됨 (IME 통과한 키 없음)
        let late: [RecordedKey] = [key("a"), key("b"), key("c")]
        startAndAdvanceToBackspacePhase(initialBuffer: initial, lateBuffer: late)

        // preKeyCount=2, imeConsumed=0, appInserted=3 → totalBackspaces=5
        XCTAssertEqual(delegate.postedBackspacesCalls, [5])

        // 5개 backspace 응답
        for _ in 0..<5 {
            XCTAssertEqual(corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil),
                           .syntheticBackspaceConsumed)
        }
        scheduler.runImmediates()

        // replay 순서: appKeys(["a","b","c"]) at preKeyCount=2 인덱스에 삽입 후
        // ["d","k","a","b","c"] 순서로 processKey
        XCTAssertEqual(mode.processedKeys, ["d", "k", "a", "b", "c"])
    }

    // MARK: - T5: 10ms 대기 중 handle()로 키 도착 → 흡수

    func testKeyDuringBuffering_consumed() {
        mode.currentMode = .korean
        evidence.queuedBatches = [[key("d"), key("k")], []]
        corrector.startCorrection()

        // 10ms 대기 중 handle() 호출 — 흡수되어 .consumed
        XCTAssertEqual(corrector.handle(keyCode: 38, keyLabel: "j"), .consumed)

        // 10ms 진행
        scheduler.advance(by: 0.01)

        // preKeyCount=2, focusStealKeyBuffer.count=3, imeConsumed=1, late=0
        // → appInserted=0, totalBackspaces=preKeyCount=2
        XCTAssertEqual(delegate.postedBackspacesCalls, [2])
    }

    // MARK: - T6: backspace 카운트다운 중 추가 키 도착 → 흡수, replay에 포함

    func testKeyDuringBackspaceCountdown_consumed() {
        mode.currentMode = .korean
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d"), key("k")])
        // backspace 1개 소비
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)

        // 추가 키
        XCTAssertEqual(corrector.handle(keyCode: 38, keyLabel: "j"), .consumed)

        // 마지막 backspace 소비 → replay 예약
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        scheduler.runImmediates()

        // ["d","k","j"] 순서로 processKey
        XCTAssertEqual(mode.processedKeys, ["d", "k", "j"])
    }

    // MARK: - T7: replay pending 중 키 도착 → 흡수

    func testKeyDuringReplayPending_consumed() {
        // 이 케이스는 ManualScheduler 특성상 어렵다 — scheduleImmediate 후
        // runImmediates 호출 전까지가 "pending" 상태이지만, 보통 이 사이에
        // handle()이 호출되는 시나리오. 직접 시뮬레이션.
        mode.currentMode = .korean
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d"), key("k")])
        // 모든 backspace 소비 → replay 예약됨
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)

        // 아직 runImmediates 안 함 → replayPending = true 상태
        XCTAssertEqual(corrector.handle(keyCode: 38, keyLabel: "j"), .consumed)

        // 이제 replay
        scheduler.runImmediates()
        XCTAssertEqual(mode.processedKeys, ["d", "k", "j"])
    }

    // MARK: - T8: 10ms 대기 중 cancel() → bufferingTask 취소

    func testCancelDuringBuffering_noBackspacePosted() {
        mode.currentMode = .korean
        evidence.queuedBatches = [[key("d"), key("k")], []]
        corrector.startCorrection()
        XCTAssertEqual(scheduler.pendingTaskCount, 1)

        corrector.cancel()
        XCTAssertEqual(scheduler.pendingTaskCount, 0)

        // 시간이 흘러도 backspace post 안 됨
        scheduler.advance(by: 0.1)
        XCTAssertEqual(delegate.postedBackspacesCalls, [])
    }

    // MARK: - T9: backspace expecting 중 cancel() → 카운트 0으로

    func testCancelDuringBackspaceExpecting_replayNotTriggered() {
        mode.currentMode = .korean
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d"), key("k")])

        // backspace 1개 소비 후 cancel
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        corrector.cancel()

        // 추가 backspace는 corrector와 무관 (.passThrough)
        XCTAssertEqual(corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil),
                       .passThrough)

        // immediate run도 아무 영향 없음
        scheduler.runImmediates()
        XCTAssertEqual(mode.processedKeys, [])
    }

    // MARK: - T10: replay pending 중 cancel() → replay 미실행

    func testCancelDuringReplayPending_noKeysReplayed() {
        mode.currentMode = .korean
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d"), key("k")])
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        // replay 예약된 상태

        corrector.cancel()
        scheduler.runImmediates()

        XCTAssertEqual(mode.processedKeys, [])
        XCTAssertEqual(delegate.appliedResults, [])
    }

    // MARK: - T11: replay 시점에 bundleId 변경 → replay skip

    func testReplayWithBundleIdChange_skipped() {
        mode.currentMode = .korean
        delegate.bundleId = "com.app.original"
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d"), key("k")])
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)

        // replay 예약 → fire 전에 bundleId 변경
        delegate.bundleId = "com.app.other"
        scheduler.runImmediates()

        // processKey 미호출
        XCTAssertEqual(mode.processedKeys, [])
    }

    // MARK: - T12: replay 시점에 client 미부착 → replay skip

    func testReplayWithoutAttachedClient_skipped() {
        mode.currentMode = .korean
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d"), key("k")])
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)

        // replay 예약 → client 비활성화
        delegate.hasAttachedClient = false
        scheduler.runImmediates()

        XCTAssertEqual(mode.processedKeys, [])
        XCTAssertEqual(delegate.appliedResults, [])
    }

    // MARK: - T13: 영문 모드 → forceKoreanForReplay 호출

    func testEnglishMode_forcesKorean() {
        mode.currentMode = .english
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d")])

        XCTAssertEqual(mode.forceKoreanCallCount, 1)
        XCTAssertEqual(mode.currentMode, .korean)
        // forceKorean의 ProcessResult 1개 + 아이콘 sync
        XCTAssertEqual(delegate.appliedResults.count, 1)
        XCTAssertEqual(delegate.iconSyncCount, 1)
    }

    // MARK: - T14: 이미 한글 모드면 forceKorean 미호출

    func testKoreanMode_doesNotForceKorean() {
        mode.currentMode = .korean
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d")])

        XCTAssertEqual(mode.forceKoreanCallCount, 0)
        // forceKorean 호출 안 했으므로 applyResult도 그 분만큼 안 호출
        // (아이콘 sync는 호출됨)
        XCTAssertEqual(delegate.appliedResults, [])
        XCTAssertEqual(delegate.iconSyncCount, 1)
    }

    // MARK: - T15: startCorrection 두 번 연속 호출 → 이전 cancel

    func testStartCorrectionTwice_previousCancelled() {
        mode.currentMode = .korean
        // 1차
        evidence.queuedBatches = [[key("d"), key("k")], []]
        corrector.startCorrection()
        XCTAssertEqual(scheduler.pendingTaskCount, 1)

        // 2차 — 이전 task cancel, 새 task 시작
        evidence.queuedBatches = [[key("j")], []]
        corrector.startCorrection()
        // cancelled task가 제거된 후 새 task 1개
        XCTAssertEqual(scheduler.pendingTaskCount, 1)

        // 시간 진행 → 2차 보정만 동작 (preKeyCount=1)
        scheduler.advance(by: 0.01)
        XCTAssertEqual(delegate.postedBackspacesCalls, [1])
    }

    // MARK: - T16: 가드 순서 — synthetic backspace가 일반 가드보다 우선

    func testSyntheticBackspace_takesPrecedenceOverBufferingGuard() {
        mode.currentMode = .korean
        startAndAdvanceToBackspacePhase(initialBuffer: [key("d"), key("k")])

        // expectingBackspace > 0인 상태에서 backspace → syntheticBackspaceConsumed
        XCTAssertEqual(corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil),
                       .syntheticBackspaceConsumed)
    }

    // MARK: - T17: 버퍼링 중 keyLabel nil → .consumed but 버퍼 미변경

    func testKeyDuringBuffering_nilLabel_consumedButNotBuffered() {
        mode.currentMode = .korean
        evidence.queuedBatches = [[key("d"), key("k")], []]
        corrector.startCorrection()

        // keyLabel nil (예: backspace as user key during 10ms wait)
        XCTAssertEqual(corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil),
                       .consumed)

        // 10ms 진행
        scheduler.advance(by: 0.01)
        // 버퍼는 여전히 ["d","k"] 만 (nil label은 append 안 됨)
        // → preKeyCount=2, imeConsumed=0 (focusStealKeyBuffer.count=2 그대로),
        //   late=0, appInserted=0, totalBackspaces=2
        XCTAssertEqual(delegate.postedBackspacesCalls, [2])

        // replay 시 ["d","k"] 만
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        _ = corrector.handle(keyCode: KeyCode.backspace, keyLabel: nil)
        scheduler.runImmediates()
        XCTAssertEqual(mode.processedKeys, ["d", "k"])
    }
}
