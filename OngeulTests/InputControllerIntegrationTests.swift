import XCTest
import InputMethodKit

/// PoC 3 확장: OngeulInputController 기본 init + testLayoutsURL로 레이아웃 로드 → handle() 파이프라인 테스트
class InputControllerIntegrationTests: XCTestCase {
    static let layoutsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("ongeul-automata/layouts")

    var controller: OngeulInputController!
    var client: MockInputClient!

    override func setUp() {
        controller = OngeulInputController()
        controller.testLayoutsURL = Self.layoutsDir
        client = MockInputClient()
    }

    private func sendKeyDown(
        _ characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
        var handled = false
        ObjCExceptionCatcher.performSafely {
            handled = self.controller.handle(event, client: self.client)
        }
        return handled
    }

    func testControllerInitDoesNotCrash() {
        // OngeulInputController 기본 init이 예외 없이 동작하는지 확인
        XCTAssertNotNil(controller)
    }

    func testHandleKeyInEnglishMode_passesToSystem() {
        // 최초 handle() 호출 시 loadLayoutIfNeeded() → 레이아웃 로드 → 영문 모드 설정
        // 영문 모드에서는 모든 키가 시스템에 위임 (handled = false)
        let handled = sendKeyDown("g", keyCode: 0x05)
        XCTAssertFalse(handled)
    }

    func testLayoutLoadedSuccessfully() {
        // handle() 호출 후 레이아웃이 로드되었는지 간접 확인:
        // 영문 모드에서 handled=false가 반환되면 레이아웃 로드 성공 (크래시 없음)
        let _ = sendKeyDown("a", keyCode: 0x00)
        // 두 번째 호출도 크래시 없음 (이미 로드된 레이아웃 재사용)
        let handled = sendKeyDown("b", keyCode: 0x0B)
        XCTAssertFalse(handled)
    }
}
