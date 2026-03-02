/// Phase B PoC: IMKServer + OngeulInputController 테스트 프로세스 내 동작 검증
///
/// 결과 요약:
///   - IMKServer 생성: 가능 (connection 등록 경고 있으나 예외 없음)
///   - Controller init(server:delegate:client:): 불가능 — client가 XPC 프록시(NSDistantObject)여야 하며,
///     일반 NSObject를 전달하면 `abort()`로 프로세스가 크래시함 (ObjC @try/@catch로도 잡을 수 없음)
///   - 결론: Phase B (MockInputClient + IMKServer 통합 테스트) 접근 불가
///           → 우선순위 6 (비즈니스 로직 추출 + 단위 테스트)으로 전환
import XCTest
import InputMethodKit

// MARK: - MockInputClient

class MockInputClient: NSObject, IMKTextInput {
    var committedText = ""
    var currentMarkedText = ""
    var markedCount = 0

    func insertText(_ string: Any!, replacementRange: NSRange) {
        committedText += (string as? String)
            ?? (string as? NSAttributedString)?.string
            ?? ""
        currentMarkedText = ""
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        currentMarkedText = (string as? String)
            ?? (string as? NSAttributedString)?.string
            ?? ""
        markedCount += 1
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! { nil }
    func length() -> Int { 0 }
    func validAttributesForMarkedText() -> [Any]! { [] }

    func attributes(forCharacterIndex index: Int,
                    lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable : Any]! {
        lineRect?.pointee = .zero
        return [:]
    }

    func bundleIdentifier() -> String! { "com.test.IMKPoC" }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}

    func characterIndex(for point: NSPoint, tracking: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int { 0 }
    func supportsUnicode() -> Bool { true }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ tag: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "com.test.IMKPoC.unique" }
    func string(from range: NSRange, actualRange: NSRangePointer?) -> String! { "" }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
}

// MARK: - PoC Tests

class IMKServerPoCTests: XCTestCase {

    /// PoC 1: IMKServer를 테스트 프로세스에서 생성할 수 있는가?
    func testPoC1_IMKServerCreation() {
        let uniqueName = "OngeulPoC_\(Int.random(in: 0..<0x10000))"
        var server: IMKServer?

        let success = ObjCExceptionCatcher.performSafely {
            server = IMKServer(name: uniqueName, bundleIdentifier: "io.github.hiking90.inputmethod.Ongeul")
        }

        // IMKServer는 생성되지만 _createConnection이 실패 로그를 남김 (테스트 프로세스는 등록된 IME가 아니므로).
        // 중요한 것: 예외 없이 반환됨.
        XCTAssertTrue(success, "IMKServer 생성 시 예외가 발생하지 않아야 한다")
    }

    /// PoC 2: init(server:delegate:client:)는 MockInputClient로 불가능.
    /// NSInvalidArgumentException 후 abort() → 프로세스 크래시.
    /// ObjCExceptionCatcher로도 잡을 수 없으므로 실행하지 않고 기록만 남긴다.
    func testPoC2_ControllerInitWithMockClient_SKIPPED() {
        // 이 테스트는 실행하면 프로세스가 크래시하므로 의도적으로 스킵.
        // 검증 결과: IMKInputController.init(server:delegate:client:)는
        // client가 NSDistantObject(XPC 프록시)여야 하며,
        // 일반 NSObject(MockInputClient)를 전달하면
        // "unexpected client proxy of class ..." 예외 후 abort()됨.
        //
        // Phase B (MockInputClient + IMKServer 통합 테스트) 접근 불가.
    }

    /// PoC 3: IMK 인프라 없이 OngeulInputController 기본 init 후 handle() 호출.
    func testPoC3_ControllerDefaultInitAndHandle() {
        var controller: OngeulInputController?

        let initSuccess = ObjCExceptionCatcher.performSafely {
            controller = OngeulInputController()
        }

        XCTAssertTrue(initSuccess, "OngeulInputController 기본 init은 예외 없이 동작해야 한다")
        guard initSuccess, let controller else { return }

        let client = MockInputClient()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil,
            characters: "g", charactersIgnoringModifiers: "g",
            isARepeat: false, keyCode: 0x05
        )!

        var handled = false
        let handleSuccess = ObjCExceptionCatcher.performSafely {
            handled = controller.handle(event, client: client)
        }

        // 레이아웃이 로드되지 않은 상태(Bundle.main에 없음)이므로
        // 엔진이 영문 모드이거나 키를 처리하지 못할 수 있다.
        // 핵심: 크래시 없이 반환되는가?
        XCTAssertTrue(handleSuccess, "handle() 호출이 예외 없이 동작해야 한다")
        print("PoC 3: handle() success=\(handleSuccess), handled=\(handled)")
        print("PoC 3: committed='\(client.committedText)' marked='\(client.currentMarkedText)'")
    }
}
