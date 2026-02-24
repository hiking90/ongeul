import Cocoa
import InputMethodKit
import os.log

private let log = OSLog(subsystem: "com.example.inputmethod.Ongeul", category: "input")

private enum KeyCode {
    static let enter: UInt16      = 36
    static let space: UInt16      = 49
    static let backspace: UInt16  = 51
    static let escape: UInt16     = 53
    static let rightCommand: UInt16 = 54
    static let capsLock: UInt16   = 57
    static let arrowLeft: UInt16  = 123
    static let arrowRight: UInt16 = 124
    static let arrowDown: UInt16  = 125
    static let arrowUp: UInt16    = 126
}

@objc(OngeulInputController)
class OngeulInputController: IMKInputController {
    private let engine = HangulEngine()
    private var loadedLayoutId: String?
    private var rightCmdPending = false

    /// menu()에서 self를 강하게 유지하여 메뉴 액션 시점에 컨트롤러가 해제되지 않도록 한다.
    private static var menuOwner: OngeulInputController?

    private static let defaultLayoutId = "2-standard"
    private static let layoutKey = "selectedLayoutId"
    private static let layouts: [(id: String, name: String)] = [
        ("2-standard", "두벌식 표준"),
        ("3-390", "세벌식 390"),
        ("3-final", "세벌식 최종"),
    ]

    private var currentLayoutId: String {
        UserDefaults.standard.string(forKey: Self.layoutKey) ?? Self.defaultLayoutId
    }

    // MARK: - Lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        loadLayoutIfNeeded()
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = sender as? (any IMKTextInput) {
            let result = engine.flush()
            applyResult(result, to: client)
        }
        super.deactivateServer(sender)
    }

    // MARK: - Key Event Handling

    override func recognizedEvents(_ sender: Any!) -> Int {
        let events: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        return Int(events.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event,
              let client = sender as? (any IMKTextInput) else {
            return false
        }

        if event.type == .flagsChanged {
            return handleFlagsChanged(event, client: client)
        }

        if event.type == .keyDown {
            return handleKeyDown(event, client: client)
        }

        return false
    }

    // MARK: - Menu: 자판 선택

    override func menu() -> NSMenu! {
        Self.menuOwner = self
        let menu = NSMenu(title: "Ongeul")
        for layout in Self.layouts {
            let item = NSMenuItem(
                title: layout.name,
                action: #selector(selectLayout(_:)),
                keyEquivalent: ""
            )
            item.representedObject = layout.id
            item.target = self
            item.state = (layout.id == currentLayoutId) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let layoutId = sender.representedObject as? String,
              layoutId != currentLayoutId else { return }

        // 현재 조합 flush
        let flushResult = engine.flush()
        if let client = self.client() {
            applyResult(flushResult, to: client)
        }

        // 새 레이아웃 로드
        guard let url = Bundle.main.url(forResource: layoutId, withExtension: "json5"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("[Ongeul] Failed to load layout file: \(layoutId).json5")
            return
        }

        do {
            try engine.loadLayout(json: json)
            engine.setMode(mode: .korean)
            loadedLayoutId = layoutId
            UserDefaults.standard.set(layoutId, forKey: Self.layoutKey)
            NSLog("[Ongeul] Layout switched to: \(layoutId)")
        } catch {
            NSLog("[Ongeul] Failed to parse layout: \(error)")
        }
    }

    // MARK: - Private: Right Command → 한/영 전환

    private func handleFlagsChanged(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        os_log("flagsChanged: keyCode=%{public}d flags=0x%{public}lx", log: log, type: .default, event.keyCode, event.modifierFlags.rawValue)

        if event.keyCode == KeyCode.rightCommand {
            if event.modifierFlags.contains(.command) {
                // Right Command 눌림 → 탭 후보 등록
                rightCmdPending = true
            } else if rightCmdPending {
                // Right Command 단독 탭 → 한영 전환
                rightCmdPending = false
                let result = engine.toggleMode()
                let newMode = engine.getMode()
                os_log("toggleMode → mode=%{public}@ committed=%{public}@", log: log, type: .default,
                       String(describing: newMode), result.committed ?? "(nil)")
                applyResult(result, to: client)
                return true
            }
            return false
        }

        // 다른 modifier 변경 → 탭 후보 취소
        rightCmdPending = false
        return false
    }

    // MARK: - Private: Key Processing

    private func handleKeyDown(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let modifiers = event.modifierFlags

        // 키 입력 → Right Command 단독 탭 취소 (Cmd+C 등 단축키 사용)
        rightCmdPending = false

        // 시스템 단축키 → flush 후 통과
        if modifiers.contains(.command) || modifiers.contains(.control) {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // Backspace
        if event.keyCode == KeyCode.backspace {
            let result = engine.backspace()
            applyResult(result, to: client)
            return result.handled
        }

        // Enter → flush 후 시스템 위임
        if event.keyCode == KeyCode.enter {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // Space → flush 후 시스템 위임
        if event.keyCode == KeyCode.space {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // Escape → 조합 폐기
        if event.keyCode == KeyCode.escape {
            engine.reset()
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
            return false
        }

        // 방향키 → flush 후 통과
        let arrowKeys: [UInt16] = [KeyCode.arrowLeft, KeyCode.arrowRight, KeyCode.arrowDown, KeyCode.arrowUp]
        if arrowKeys.contains(event.keyCode) {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // 일반 키 → Rust 엔진에 위임
        guard let keyLabel = keyLabelFromEvent(event) else {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        let result = engine.processKey(key: keyLabel)
        applyResult(result, to: client)
        return result.handled
    }

    // MARK: - Private: Key Label Conversion

    private func keyLabelFromEvent(_ event: NSEvent) -> String? {
        guard let chars = event.characters, !chars.isEmpty else {
            return nil
        }

        let ch = chars.first!

        if ch.isASCII && (ch.isLetter || ch.isNumber || ch.isPunctuation || ch.isSymbol) {
            return String(ch)
        }

        return nil
    }

    // MARK: - Private: Result Application

    private func applyResult(_ result: ProcessResult, to client: any IMKTextInput) {
        if let committed = result.committed {
            client.insertText(
                committed as NSString,
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }

        if let composing = result.composing {
            client.setMarkedText(
                composing as NSString,
                selectionRange: NSRange(location: composing.count, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        } else if result.committed != nil {
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }
    }

    // MARK: - Private: Layout Loading

    private func loadLayoutIfNeeded() {
        let layoutId = currentLayoutId
        guard loadedLayoutId != layoutId else { return }

        guard let url = Bundle.main.url(forResource: layoutId, withExtension: "json5"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("[Ongeul] Failed to load keyboard layout file: \(layoutId).json5")
            return
        }

        do {
            try engine.loadLayout(json: json)
            engine.setMode(mode: .korean)
            loadedLayoutId = layoutId
            NSLog("[Ongeul] Layout loaded: \(layoutId)")
        } catch {
            NSLog("[Ongeul] Failed to parse keyboard layout: \(error)")
        }
    }
}
