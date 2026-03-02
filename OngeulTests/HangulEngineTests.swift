/// HangulEngine UniFFI 바인딩 테스트 (Phase A)
///
/// Rust 엔진을 Swift 측에서 직접 호출하여 UniFFI 바인딩 경계를 검증한다.
/// IMKServer 없이 HangulEngine API만 테스트.
import XCTest

class HangulEngineTests: XCTestCase {
    /// 프로젝트 루트의 layouts 디렉토리 경로.
    /// #filePath → OngeulTests/HangulEngineTests.swift → ../../ongeul-automata/layouts
    static let layoutsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("ongeul-automata/layouts")

    var engine: HangulEngine!

    override func setUp() {
        engine = HangulEngine()
        let layoutURL = Self.layoutsDir.appendingPathComponent("2-standard.json5")
        let layoutJson = try! String(contentsOf: layoutURL)
        try! engine.loadLayout(json: layoutJson)
        engine.setMode(mode: .korean)
    }

    // MARK: - 기본 한글 조합

    func testHangulWord() {
        // "한글" = ㅎ(g) + ㅏ(k) + ㄴ(s) + ㄱ(r) + ㅡ(m) + ㄹ(f)
        let r1 = engine.processKey(key: "g")
        XCTAssertEqual(r1.composing, "ㅎ")

        let r2 = engine.processKey(key: "k")
        XCTAssertEqual(r2.composing, "하")

        let r3 = engine.processKey(key: "s")
        XCTAssertEqual(r3.composing, "한")

        let r4 = engine.processKey(key: "r")  // 종성 분리
        XCTAssertEqual(r4.committed, "한")
        XCTAssertEqual(r4.composing, "ㄱ")

        let r5 = engine.processKey(key: "m")
        XCTAssertEqual(r5.composing, "그")

        let r6 = engine.processKey(key: "f")
        XCTAssertEqual(r6.composing, "글")
    }

    // MARK: - 백스페이스

    func testBackspace() {
        let _ = engine.processKey(key: "g")  // ㅎ
        let _ = engine.processKey(key: "k")  // 하
        let _ = engine.processKey(key: "s")  // 한

        let r = engine.backspace()
        XCTAssertEqual(r.composing, "하")
    }

    func testBackspaceToEmpty() {
        let _ = engine.processKey(key: "g")  // ㅎ
        let r = engine.backspace()
        XCTAssertNil(r.composing)
    }

    // MARK: - 모드 전환

    func testModeToggle() {
        let _ = engine.processKey(key: "g")  // ㅎ 조합 중
        let r = engine.toggleMode()
        XCTAssertEqual(r.committed, "ㅎ")    // flush
        XCTAssertEqual(engine.getMode(), .english)
    }

    func testModeToggleBackToKorean() {
        engine.setMode(mode: .english)
        XCTAssertEqual(engine.getMode(), .english)

        let r = engine.toggleMode()
        XCTAssertNil(r.committed)
        XCTAssertEqual(engine.getMode(), .korean)
    }

    // MARK: - Flush

    func testFlush() {
        let _ = engine.processKey(key: "g")
        let _ = engine.processKey(key: "k")
        let r = engine.flush()
        XCTAssertEqual(r.committed, "하")
        XCTAssertNil(r.composing)
    }

    func testFlushEmpty() {
        let r = engine.flush()
        XCTAssertNil(r.committed)
    }

    // MARK: - 겹받침

    func testDoubleJongseongSplit() {
        // ㄱ(r) + ㅏ(k) + ㅂ(q) + ㅅ(t) + ㅣ(l) → "갑" + "시"
        let _ = engine.processKey(key: "r")
        let _ = engine.processKey(key: "k")
        let _ = engine.processKey(key: "q")
        let _ = engine.processKey(key: "t")
        let r = engine.processKey(key: "l")
        XCTAssertTrue(r.committed?.hasSuffix("갑") ?? false)
        XCTAssertEqual(r.composing, "시")
    }

    // MARK: - 겹모음

    func testDoubleVowel() {
        // ㄱ(r) + ㅗ(h) + ㅏ(k) = 과
        let _ = engine.processKey(key: "r")
        let _ = engine.processKey(key: "h")
        let r = engine.processKey(key: "k")
        XCTAssertEqual(r.composing, "과")
    }

    // MARK: - Reset

    func testReset() {
        let _ = engine.processKey(key: "g")
        let _ = engine.processKey(key: "k")
        engine.reset()
        // reset 후 조합 폐기, 새로운 입력은 깨끗한 상태
        let r = engine.processKey(key: "r")
        XCTAssertEqual(r.composing, "ㄱ")
    }

    // MARK: - 3벌식 레이아웃

    func testThreeBeolsik390() {
        let layoutURL = Self.layoutsDir.appendingPathComponent("3-390.json5")
        let layoutJson = try! String(contentsOf: layoutURL)

        let engine390 = HangulEngine()
        try! engine390.loadLayout(json: layoutJson)
        engine390.setMode(mode: .korean)

        // 390: ㅎ(m) + ㅏ(f) + ㄴ종(s) = "한"
        let _ = engine390.processKey(key: "m")  // 초성 ㅎ
        let _ = engine390.processKey(key: "f")  // 중성 ㅏ
        let r = engine390.processKey(key: "s")  // 종성 ㄴ
        XCTAssertEqual(r.composing, "한")
    }

    func testThreeBeolsikFinal() {
        let layoutURL = Self.layoutsDir.appendingPathComponent("3-final.json5")
        let layoutJson = try! String(contentsOf: layoutURL)

        let engineFinal = HangulEngine()
        try! engineFinal.loadLayout(json: layoutJson)
        engineFinal.setMode(mode: .korean)

        // Final: ㅎ(m) + ㅏ(f) + ㄴ종(s) = "한"
        let _ = engineFinal.processKey(key: "m")  // 초성 ㅎ
        let _ = engineFinal.processKey(key: "f")  // 중성 ㅏ
        let r = engineFinal.processKey(key: "s")  // 종성 ㄴ
        XCTAssertEqual(r.composing, "한")
    }
}
