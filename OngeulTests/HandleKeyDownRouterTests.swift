import XCTest
import AppKit

class HandleKeyDownRouterTests: XCTestCase {

    func testShiftSpaceToggle() {
        let action = routeKeyDown(
            keyCode: KeyCode.space, characters: " ",
            modifiers: .shift, engineMode: .korean,
            toggleKey: .shiftSpace, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .shiftSpaceToggle)
    }

    func testShiftSpaceNotActiveForOtherToggleKey() {
        // rightCommand 모드에서 Shift+Space → shiftSpaceToggle이 아닌 space
        let action = routeKeyDown(
            keyCode: KeyCode.space, characters: " ",
            modifiers: .shift, engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        // Shift는 command/control이 아니므로 → space
        XCTAssertEqual(action, .space)
    }

    func testEnglishModePassthrough() {
        let action = routeKeyDown(
            keyCode: 0x05, characters: "g",
            modifiers: [], engineMode: .english,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .passToSystem)
    }

    func testCommandShortcut_flushAndPass() {
        let action = routeKeyDown(
            keyCode: 0x00, characters: "a",
            modifiers: .command, engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .flushAndPassToSystem)
    }

    func testControlShortcut_flushAndPass() {
        let action = routeKeyDown(
            keyCode: 0x00, characters: "a",
            modifiers: .control, engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .flushAndPassToSystem)
    }

    func testBackspace() {
        let action = routeKeyDown(
            keyCode: KeyCode.backspace, characters: nil,
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .backspace)
    }

    func testEnter() {
        let action = routeKeyDown(
            keyCode: KeyCode.enter, characters: "\r",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .enter(isSynthetic: false))
    }

    func testSyntheticEnter() {
        let action = routeKeyDown(
            keyCode: KeyCode.enter, characters: "\r",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: true
        )
        XCTAssertEqual(action, .enter(isSynthetic: true))
    }

    func testSpace() {
        let action = routeKeyDown(
            keyCode: KeyCode.space, characters: " ",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .space)
    }

    func testEscape() {
        let action = routeKeyDown(
            keyCode: KeyCode.escape, characters: "\u{1b}",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .escape)
    }

    func testArrowKeys() {
        for keyCode in [KeyCode.arrowLeft, KeyCode.arrowRight, KeyCode.arrowDown, KeyCode.arrowUp] {
            let action = routeKeyDown(
                keyCode: keyCode, characters: nil,
                modifiers: [], engineMode: .korean,
                toggleKey: .rightCommand, isSyntheticEnter: false
            )
            XCTAssertEqual(action, .flushAndPassToSystem, "Arrow key \(keyCode) should flush and pass")
        }
    }

    func testNormalKey() {
        let action = routeKeyDown(
            keyCode: 0x05, characters: "g",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .processKey(label: "g"))
    }

    func testUnknownKey_flushUnknown() {
        // characters가 nil → keyLabel이 nil → flushUnknownKey
        let action = routeKeyDown(
            keyCode: 0x72, characters: nil,
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand, isSyntheticEnter: false
        )
        XCTAssertEqual(action, .flushUnknownKey)
    }
}
