import XCTest
import AppKit

class ToggleDetectorTests: XCTestCase {
    var detector: ToggleDetector!

    override func setUp() {
        detector = ToggleDetector()
    }

    // MARK: - Right Command Toggle

    func testRightCommandPressRelease_toggles() {
        let now: CFAbsoluteTime = 1000.0
        let r1 = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        XCTAssertEqual(r1, .none)

        let r2 = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: [],
            toggleKey: .rightCommand, now: now + 0.2
        )
        XCTAssertEqual(r2, .toggle)
    }

    func testRightCommandTimeout_noToggle() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: [],
            toggleKey: .rightCommand, now: now + 0.6
        )
        XCTAssertEqual(r, .none)
    }

    func testKeyDownCancelsPending() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        XCTAssertEqual(detector.cancelOnKeyDown(), .none)

        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: [],
            toggleKey: .rightCommand, now: now + 0.1
        )
        XCTAssertEqual(r, .none)
    }

    // MARK: - Rollover Rescue (doc 35, issue #22)

    /// 억제 중이면 tap 판정이 살아 있는 동안 온 keyDown은 롤오버이므로 그 자리에서
    /// 토글하고, 뒤따르는 release가 다시 토글하지 않아야 한다.
    func testRollover_rescuesToggleOnceAndNotAgainOnRelease() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )

        let rescued = detector.cancelOnKeyDown(
            rescuePendingToggle: true, now: now + 0.04)
        XCTAssertEqual(rescued, .toggle)
        XCTAssertNil(detector.pendingKeyCode)

        let release = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: [],
            toggleKey: .rightCommand, now: now + 0.1
        )
        XCTAssertEqual(release, .none)
    }

    /// 0.5s를 넘겨 누르고 있었다면 tap이 아니므로 구제하지 않는다.
    func testRollover_expiredPendingIsNotRescued() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        XCTAssertEqual(
            detector.cancelOnKeyDown(rescuePendingToggle: true, now: now + 0.6),
            .none)
    }

    /// pending이 없으면(전환 키를 누른 적 없음) 억제 중이어도 구제할 것이 없다.
    func testRollover_noPendingIsNotRescued() {
        XCTAssertEqual(
            detector.cancelOnKeyDown(rescuePendingToggle: true, now: 1000.0),
            .none)
    }

    /// 억제가 꺼진(또는 폴백) 경로에서는 기존대로 취소만 한다.
    func testRollover_notRescuedWhenSuppressionOff() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        XCTAssertEqual(
            detector.cancelOnKeyDown(rescuePendingToggle: false, now: now + 0.04),
            .none)
    }

    // MARK: - Multi-modifier Guard

    func testMultiModifier_cancelsPending() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        // Shift 추가 → 다중 modifier
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.leftShift, flags: [.command, .shift],
            toggleKey: .rightCommand, now: now + 0.1
        )
        XCTAssertEqual(r, .none)
        XCTAssertNil(detector.pendingKeyCode)
    }

    // MARK: - 4-Key English Lock

    func testFourKeyEnglishLock() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.leftCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.leftOption, flags: [.command, .option],
            toggleKey: .rightCommand, now: now
        )
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightOption, flags: [.command, .option],
            toggleKey: .rightCommand, now: now
        )
        // 모두 해제
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.rightOption, flags: [],
            toggleKey: .rightCommand, now: now
        )
        XCTAssertEqual(r, .englishLockToggle)
    }

    func testFourKeyPartial_noLock() {
        let now: CFAbsoluteTime = 1000.0
        // 3키만
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.leftCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.leftOption, flags: [.command, .option],
            toggleKey: .rightCommand, now: now
        )
        // 해제
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.leftOption, flags: [],
            toggleKey: .rightCommand, now: now
        )
        XCTAssertEqual(r, .none)
    }

    func testFourKeyInterruptedByNonModifier_resets() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.leftCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        // Shift(4키 대상 아님) → 사이클 취소
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.leftShift, flags: [.command, .shift],
            toggleKey: .rightCommand, now: now
        )
        XCTAssertTrue(detector.fourKeysSeen.isEmpty)
    }

    // MARK: - Right Option Toggle

    func testRightOptionToggle() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightOption, flags: .option,
            toggleKey: .rightOption, now: now
        )
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.rightOption, flags: [],
            toggleKey: .rightOption, now: now + 0.1
        )
        XCTAssertEqual(r, .toggle)
    }

    // MARK: - Left/Right Shift Toggle

    func testLeftShiftToggle() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.leftShift, flags: .shift,
            toggleKey: .leftShift, now: now
        )
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.leftShift, flags: [],
            toggleKey: .leftShift, now: now + 0.1
        )
        XCTAssertEqual(r, .toggle)
    }

    func testRightShiftToggle() {
        let now: CFAbsoluteTime = 1000.0
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightShift, flags: .shift,
            toggleKey: .rightShift, now: now
        )
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.rightShift, flags: [],
            toggleKey: .rightShift, now: now + 0.1
        )
        XCTAssertEqual(r, .toggle)
    }

    // MARK: - ShiftSpace (flagsChanged에서는 no-op)

    func testShiftSpace_returnsNone() {
        let now: CFAbsoluteTime = 1000.0
        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.leftShift, flags: .shift,
            toggleKey: .shiftSpace, now: now
        )
        XCTAssertEqual(r, .none)
    }

    // MARK: - Double Tap Prevention

    func testDoubleTapWithoutRepress_noSecondToggle() {
        let now: CFAbsoluteTime = 1000.0
        // 첫 번째 tap → toggle
        let _ = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: .command,
            toggleKey: .rightCommand, now: now
        )
        let r1 = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: [],
            toggleKey: .rightCommand, now: now + 0.1
        )
        XCTAssertEqual(r1, .toggle)

        // 즉시 release 다시 → pending이 없으므로 toggle 안 됨
        let r2 = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: [],
            toggleKey: .rightCommand, now: now + 0.2
        )
        XCTAssertEqual(r2, .none)
    }
}
