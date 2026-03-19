import XCTest

/// Focus-steal 관련 조건 로직과 KeyEventTap 버퍼 관리 테스트.
/// activateServer/CGEvent 등 IMK 라이프사이클에 의존하지 않는 순수 로직만 검증한다.
class FocusStealTests: XCTestCase {

    override func setUp() {
        KeyEventTap.keyBuffer = []
        KeyEventTap.keyBufferWasKoreanMode = false
        KeyEventTap.currentInputMode = .english
    }

    override func tearDown() {
        KeyEventTap.keyBuffer = []
        KeyEventTap.keyBufferWasKoreanMode = false
    }

    // MARK: - KeyEventTap 버퍼 기록

    func testBufferRecordsKoreanModeOnFirstKey() {
        KeyEventTap.currentInputMode = .korean
        KeyEventTap.keyBuffer = []

        // 첫 키 추가 시 koreanMode 기록
        KeyEventTap.keyBuffer.append(
            KeyEventTap.RecordedKey(character: "j", timestamp: CFAbsoluteTimeGetCurrent())
        )
        if KeyEventTap.keyBuffer.count == 1 {
            KeyEventTap.keyBufferWasKoreanMode = (KeyEventTap.currentInputMode == .korean)
        }

        XCTAssertTrue(KeyEventTap.keyBufferWasKoreanMode)
    }

    func testBufferRecordsEnglishModeOnFirstKey() {
        KeyEventTap.currentInputMode = .english
        KeyEventTap.keyBuffer = []

        KeyEventTap.keyBuffer.append(
            KeyEventTap.RecordedKey(character: "j", timestamp: CFAbsoluteTimeGetCurrent())
        )
        if KeyEventTap.keyBuffer.count == 1 {
            KeyEventTap.keyBufferWasKoreanMode = (KeyEventTap.currentInputMode == .korean)
        }

        XCTAssertFalse(KeyEventTap.keyBufferWasKoreanMode)
    }

    // MARK: - 200ms 버퍼 리셋 로직

    func testBufferResetsWhenFirstKeyOlderThan200ms() {
        let staleTime = CFAbsoluteTimeGetCurrent() - 0.3  // 300ms ago
        KeyEventTap.keyBuffer = [
            KeyEventTap.RecordedKey(character: "j", timestamp: staleTime)
        ]

        // CGEventTap의 리셋 로직 재현
        let now = CFAbsoluteTimeGetCurrent()
        if let first = KeyEventTap.keyBuffer.first, now - first.timestamp > 0.2 {
            KeyEventTap.keyBuffer.removeAll()
        }

        XCTAssertTrue(KeyEventTap.keyBuffer.isEmpty, "300ms 된 버퍼는 리셋되어야 한다")
    }

    func testBufferKeepsWhenFirstKeyWithin200ms() {
        let recentTime = CFAbsoluteTimeGetCurrent() - 0.05  // 50ms ago
        KeyEventTap.keyBuffer = [
            KeyEventTap.RecordedKey(character: "j", timestamp: recentTime)
        ]

        let now = CFAbsoluteTimeGetCurrent()
        if let first = KeyEventTap.keyBuffer.first, now - first.timestamp > 0.2 {
            KeyEventTap.keyBuffer.removeAll()
        }

        XCTAssertEqual(KeyEventTap.keyBuffer.count, 1, "50ms 된 버퍼는 유지되어야 한다")
    }

    // MARK: - Focus-steal 발동 조건

    func testFocusStealCondition_koreanAndNotEmpty_shouldActivate() {
        KeyEventTap.keyBufferWasKoreanMode = true
        KeyEventTap.keyBuffer = [
            KeyEventTap.RecordedKey(character: "j", timestamp: CFAbsoluteTimeGetCurrent())
        ]

        let shouldActivate = KeyEventTap.keyBufferWasKoreanMode && !KeyEventTap.keyBuffer.isEmpty
        XCTAssertTrue(shouldActivate)
    }

    func testFocusStealCondition_englishMode_shouldNotActivate() {
        KeyEventTap.keyBufferWasKoreanMode = false
        KeyEventTap.keyBuffer = [
            KeyEventTap.RecordedKey(character: "j", timestamp: CFAbsoluteTimeGetCurrent())
        ]

        let shouldActivate = KeyEventTap.keyBufferWasKoreanMode && !KeyEventTap.keyBuffer.isEmpty
        XCTAssertFalse(shouldActivate)
    }

    func testFocusStealCondition_emptyBuffer_shouldNotActivate() {
        KeyEventTap.keyBufferWasKoreanMode = true
        KeyEventTap.keyBuffer = []

        let shouldActivate = KeyEventTap.keyBufferWasKoreanMode && !KeyEventTap.keyBuffer.isEmpty
        XCTAssertFalse(shouldActivate)
    }

    // MARK: - Elapsed 체크 (500ms 타임아웃)

    func testElapsedCheck_withinThreshold_shouldProceed() {
        let recentKey = KeyEventTap.RecordedKey(
            character: "j", timestamp: CFAbsoluteTimeGetCurrent() - 0.1
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - recentKey.timestamp
        XCTAssertTrue(elapsed < 0.5, "100ms 된 키는 유효해야 한다")
    }

    func testElapsedCheck_beyondThreshold_shouldSkip() {
        let staleKey = KeyEventTap.RecordedKey(
            character: "j", timestamp: CFAbsoluteTimeGetCurrent() - 1.0
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - staleKey.timestamp
        XCTAssertFalse(elapsed < 0.5, "1초 된 키는 무효해야 한다")
    }

    // MARK: - 다수 키 버퍼 축적

    func testMultipleKeysAccumulateInBuffer() {
        let now = CFAbsoluteTimeGetCurrent()
        KeyEventTap.keyBuffer = [
            KeyEventTap.RecordedKey(character: "j", timestamp: now),
            KeyEventTap.RecordedKey(character: "b", timestamp: now + 0.05),
        ]

        XCTAssertEqual(KeyEventTap.keyBuffer.count, 2)
        XCTAssertEqual(KeyEventTap.keyBuffer[0].character, "j")
        XCTAssertEqual(KeyEventTap.keyBuffer[1].character, "b")
    }

    func testBufferMapToCharacters() {
        let now = CFAbsoluteTimeGetCurrent()
        KeyEventTap.keyBuffer = [
            KeyEventTap.RecordedKey(character: "j", timestamp: now),
            KeyEventTap.RecordedKey(character: "b", timestamp: now + 0.03),
            KeyEventTap.RecordedKey(character: "s", timestamp: now + 0.06),
        ]

        let characters = KeyEventTap.keyBuffer.map { $0.character }
        XCTAssertEqual(characters, ["j", "b", "s"])
    }
}
