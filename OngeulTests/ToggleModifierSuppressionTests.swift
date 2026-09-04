import XCTest
import CoreGraphics

/// 전환 키(오른쪽 ⌘/⌥)의 modifier 억제 (doc 35, issue #22).
class ToggleModifierSuppressionTests: XCTestCase {

    private let rightCommandBit = CGEventFlags(
        rawValue: ToggleModifierSuppression.deviceRightCommand)
    private let leftCommandBit = CGEventFlags(
        rawValue: ToggleModifierSuppression.deviceLeftCommand)
    private let rightOptionBit = CGEventFlags(
        rawValue: ToggleModifierSuppression.deviceRightOption)
    private let leftOptionBit = CGEventFlags(
        rawValue: ToggleModifierSuppression.deviceLeftOption)

    // MARK: - suppressesModifier

    func testOnlyRightCommandAndOptionAreSuppressible() {
        XCTAssertTrue(ToggleKey.rightCommand.suppressesModifier)
        XCTAssertTrue(ToggleKey.rightOption.suppressesModifier)
        // Shift를 억제하면 그 Shift로 대문자를 못 친다.
        XCTAssertFalse(ToggleKey.leftShift.suppressesModifier)
        XCTAssertFalse(ToggleKey.rightShift.suppressesModifier)
        XCTAssertFalse(ToggleKey.shiftSpace.suppressesModifier)
        XCTAssertFalse(ToggleKey.capsLock.suppressesModifier)
        XCTAssertFalse(ToggleKey.hangulKey.suppressesModifier)
    }

    // MARK: - Right Command

    func testRightCommandAlone_stripsBothBits() {
        let flags: CGEventFlags = [.maskCommand, rightCommandBit]
        let result = ToggleModifierSuppression.apply(to: flags, toggleKey: .rightCommand)
        XCTAssertEqual(result, [])
    }

    /// 이슈 #22의 롤오버: 오른쪽 ⌘가 아직 눌린 채로 'a' keyDown이 도착한 상황.
    /// 앱에 ⌘가 전달되지 않아야 ⌘A가 발화하지 않는다.
    func testRollingOverKeyDown_hasNoCommandFlag() {
        let flags: CGEventFlags = [.maskCommand, rightCommandBit, .maskNonCoalesced]
        let result = ToggleModifierSuppression.apply(to: flags, toggleKey: .rightCommand)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.contains(.maskCommand))
        // 관계없는 비트는 보존
        XCTAssertTrue(result!.contains(.maskNonCoalesced))
    }

    func testLeftCommandAlsoDown_keepsGenericCommandMask() {
        let flags: CGEventFlags = [.maskCommand, leftCommandBit, rightCommandBit]
        let result = ToggleModifierSuppression.apply(to: flags, toggleKey: .rightCommand)
        XCTAssertNotNil(result)
        // 왼쪽 ⌘로 시작한 단축키가 죽으면 안 된다.
        XCTAssertTrue(result!.contains(.maskCommand))
        XCTAssertTrue(result!.contains(leftCommandBit))
        XCTAssertFalse(result!.contains(rightCommandBit))
    }

    func testLeftCommandOnly_noChange() {
        let flags: CGEventFlags = [.maskCommand, leftCommandBit]
        XCTAssertNil(ToggleModifierSuppression.apply(to: flags, toggleKey: .rightCommand))
    }

    func testNoModifier_noChange() {
        XCTAssertNil(ToggleModifierSuppression.apply(to: [], toggleKey: .rightCommand))
    }

    /// 오른쪽 ⌘가 전환 키여도 ⌥는 건드리지 않는다.
    func testRightOptionUntouchedWhenToggleIsRightCommand() {
        let flags: CGEventFlags = [.maskAlternate, rightOptionBit]
        XCTAssertNil(ToggleModifierSuppression.apply(to: flags, toggleKey: .rightCommand))
    }

    // MARK: - Right Option

    func testRightOptionAlone_stripsBothBits() {
        let flags: CGEventFlags = [.maskAlternate, rightOptionBit]
        let result = ToggleModifierSuppression.apply(to: flags, toggleKey: .rightOption)
        XCTAssertEqual(result, [])
    }

    func testLeftOptionAlsoDown_keepsGenericAlternateMask() {
        let flags: CGEventFlags = [.maskAlternate, leftOptionBit, rightOptionBit]
        let result = ToggleModifierSuppression.apply(to: flags, toggleKey: .rightOption)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains(.maskAlternate))
        XCTAssertFalse(result!.contains(rightOptionBit))
    }

    func testRightCommandUntouchedWhenToggleIsRightOption() {
        let flags: CGEventFlags = [.maskCommand, rightCommandBit]
        XCTAssertNil(ToggleModifierSuppression.apply(to: flags, toggleKey: .rightOption))
    }

    // MARK: - 억제 대상이 아닌 전환 키

    func testNonSuppressibleToggleKeys_neverChangeFlags() {
        let flags: CGEventFlags = [.maskCommand, rightCommandBit, .maskAlternate, rightOptionBit]
        for key in [ToggleKey.leftShift, .rightShift, .shiftSpace, .capsLock, .hangulKey] {
            XCTAssertNil(ToggleModifierSuppression.apply(to: flags, toggleKey: key),
                         "\(key) must not touch flags")
        }
    }

    // MARK: - 상수 (IOKit IOLLEvent.h NX_DEVICE*KEYMASK)

    func testDeviceMaskConstants() {
        XCTAssertEqual(ToggleModifierSuppression.deviceLeftCommand, 0x0000_0008)
        XCTAssertEqual(ToggleModifierSuppression.deviceRightCommand, 0x0000_0010)
        XCTAssertEqual(ToggleModifierSuppression.deviceLeftOption, 0x0000_0020)
        XCTAssertEqual(ToggleModifierSuppression.deviceRightOption, 0x0000_0040)
    }
}
