import XCTest
import AppKit

class HandleKeyDownRouterTests: XCTestCase {

    func testShiftSpaceToggle() {
        let action = routeKeyDown(
            keyCode: KeyCode.space, characters: " ",
            modifiers: .shift, engineMode: .korean,
            toggleKey: .shiftSpace
        )
        XCTAssertEqual(action, .shiftSpaceToggle)
    }

    func testShiftSpaceNotActiveForOtherToggleKey() {
        // rightCommand 모드에서 Shift+Space → shiftSpaceToggle이 아닌 space
        let action = routeKeyDown(
            keyCode: KeyCode.space, characters: " ",
            modifiers: .shift, engineMode: .korean,
            toggleKey: .rightCommand
        )
        // Shift는 command/control이 아니므로 → space
        XCTAssertEqual(action, .space)
    }

    func testEnglishModePassthrough() {
        let action = routeKeyDown(
            keyCode: 0x05, characters: "g",
            modifiers: [], engineMode: .english,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .passToSystem)
    }

    func testCommandShortcut_flushAndPass() {
        let action = routeKeyDown(
            keyCode: 0x00, characters: "a",
            modifiers: .command, engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .flushAndPassToSystem)
    }

    func testControlShortcut_flushAndPass() {
        let action = routeKeyDown(
            keyCode: 0x00, characters: "a",
            modifiers: .control, engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .flushAndPassToSystem)
    }

    func testBackspace() {
        let action = routeKeyDown(
            keyCode: KeyCode.backspace, characters: nil,
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .backspace)
    }

    func testEnter() {
        let action = routeKeyDown(
            keyCode: KeyCode.enter, characters: "\r",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .enter)
    }

    func testSpace() {
        let action = routeKeyDown(
            keyCode: KeyCode.space, characters: " ",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .space)
    }

    func testEscape() {
        let action = routeKeyDown(
            keyCode: KeyCode.escape, characters: "\u{1b}",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .escape)
    }

    func testControlLeftBracket_escape() {
        let action = routeKeyDown(
            keyCode: KeyCode.leftBracket, characters: "\u{1b}",
            modifiers: .control, engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .escape)
    }

    func testControlLeftBracket_englishMode_passToSystem() {
        let action = routeKeyDown(
            keyCode: KeyCode.leftBracket, characters: "\u{1b}",
            modifiers: .control, engineMode: .english,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .passToSystem)
    }

    func testArrowKeys() {
        for keyCode in [KeyCode.arrowLeft, KeyCode.arrowRight, KeyCode.arrowDown, KeyCode.arrowUp] {
            let action = routeKeyDown(
                keyCode: keyCode, characters: nil,
                modifiers: [], engineMode: .korean,
                toggleKey: .rightCommand
            )
            XCTAssertEqual(action, .flushAndPassToSystem, "Arrow key \(keyCode) should flush and pass")
        }
    }

    func testNumpadDigits_flushAndPass() {
        // 3벌식에서 numpad 숫자가 한글로 변환되지 않도록 시스템에 위임되어야 한다.
        // kVK_ANSI_Keypad0..9 키코드 + .numericPad 플래그
        let numpadDigits: [(UInt16, String)] = [
            (0x52, "0"), (0x53, "1"), (0x54, "2"), (0x55, "3"), (0x56, "4"),
            (0x57, "5"), (0x58, "6"), (0x59, "7"), (0x5B, "8"), (0x5C, "9"),
        ]
        for (keyCode, char) in numpadDigits {
            let action = routeKeyDown(
                keyCode: keyCode, characters: char,
                modifiers: .numericPad, engineMode: .korean,
                toggleKey: .rightCommand
            )
            XCTAssertEqual(action, .flushAndPassToSystem,
                "Numpad key \(keyCode) (\(char)) should flush and pass")
        }
    }

    func testNumpadOperators_flushAndPass() {
        // kVK_ANSI_Keypad{Decimal, Multiply, Plus, Clear, Divide, Minus, Equals}
        let numpadOps: [(UInt16, String)] = [
            (0x41, "."), (0x43, "*"), (0x45, "+"), (0x47, ""),
            (0x4B, "/"), (0x4E, "-"), (0x51, "="),
        ]
        for (keyCode, char) in numpadOps {
            let action = routeKeyDown(
                keyCode: keyCode, characters: char,
                modifiers: .numericPad, engineMode: .korean,
                toggleKey: .rightCommand
            )
            XCTAssertEqual(action, .flushAndPassToSystem,
                "Numpad operator \(keyCode) should flush and pass")
        }
    }

    func testNumpadEnter_stillEnter() {
        // 키패드 Enter는 기존대로 .enter로 라우팅되어야 한다.
        let action = routeKeyDown(
            keyCode: KeyCode.numpadEnter, characters: "\u{03}",
            modifiers: .numericPad, engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .enter)
    }

    func testMainRowDigit_stillProcessed() {
        // 일반 숫자행의 "1"은 .numericPad 플래그가 없으므로 엔진으로 전달되어야 한다.
        // (3벌식에서 한글로 변환되는 정상 경로)
        let action = routeKeyDown(
            keyCode: 0x12, characters: "1",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .processKey(label: "1"))
    }

    func testNormalKey() {
        let action = routeKeyDown(
            keyCode: 0x05, characters: "g",
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .processKey(label: "g"))
    }

    func testUnknownKey_flushUnknown() {
        // characters가 nil → keyLabel이 nil → flushUnknownKey
        let action = routeKeyDown(
            keyCode: 0x72, characters: nil,
            modifiers: [], engineMode: .korean,
            toggleKey: .rightCommand
        )
        XCTAssertEqual(action, .flushUnknownKey)
    }
}
