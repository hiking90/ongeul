import XCTest

class KeyLabelConverterTests: XCTestCase {

    // MARK: - 일반 문자

    func testNormalLowercaseLetter() {
        XCTAssertEqual(keyLabel(characters: "g", capsLock: false, shift: false), "g")
    }

    func testShiftUppercaseLetter() {
        XCTAssertEqual(keyLabel(characters: "G", capsLock: false, shift: true), "G")
    }

    // MARK: - CapsLock 보정

    func testCapsLockNoShift_lowercased() {
        // CapsLock ON → OS가 대문자 'G'를 보내지만, 한글 모드에서는 소문자로 변환
        XCTAssertEqual(keyLabel(characters: "G", capsLock: true, shift: false), "g")
    }

    func testCapsLockWithShift_uppercased() {
        // CapsLock + Shift → OS가 소문자 'g'를 보내지만, Shift 우선으로 대문자
        XCTAssertEqual(keyLabel(characters: "g", capsLock: true, shift: true), "G")
    }

    // MARK: - 숫자 / 기호

    func testNumber() {
        XCTAssertEqual(keyLabel(characters: "1", capsLock: false, shift: false), "1")
    }

    func testPunctuation() {
        XCTAssertEqual(keyLabel(characters: ";", capsLock: false, shift: false), ";")
    }

    func testSymbol() {
        XCTAssertEqual(keyLabel(characters: "=", capsLock: false, shift: false), "=")
    }

    // MARK: - 비ASCII / 빈 문자열

    func testNonASCII_returnsNil() {
        XCTAssertNil(keyLabel(characters: "\u{1234}", capsLock: false, shift: false))
    }

    func testEmpty_returnsNil() {
        XCTAssertNil(keyLabel(characters: "", capsLock: false, shift: false))
    }

    // MARK: - 특수 키 (control 문자)

    func testControlCharacter_returnsNil() {
        // Tab, ESC 등 제어 문자
        XCTAssertNil(keyLabel(characters: "\t", capsLock: false, shift: false))
    }
}
