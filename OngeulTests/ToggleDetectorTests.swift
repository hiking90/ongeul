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
        detector.cancelOnKeyDown()

        let r = detector.handleFlagsChanged(
            keyCode: KeyCode.rightCommand, flags: [],
            toggleKey: .rightCommand, now: now + 0.1
        )
        XCTAssertEqual(r, .none)
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
