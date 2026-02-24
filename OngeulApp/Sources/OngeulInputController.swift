import Cocoa
import InputMethodKit

@objc(OngeulInputController)
class OngeulInputController: IMKInputController {
    private let engine = HangulEngine()
    private var layoutLoaded = false

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

    // MARK: - Private: CapsLock → 한/영 전환

    private func handleFlagsChanged(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        // CapsLock keyCode == 57
        guard event.keyCode == 57 else { return false }

        let result = engine.toggleMode()
        applyResult(result, to: client)
        return true
    }

    // MARK: - Private: Key Processing

    private func handleKeyDown(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let modifiers = event.modifierFlags

        // 시스템 단축키 → flush 후 통과
        if modifiers.contains(.command) || modifiers.contains(.control) {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // Backspace
        if event.keyCode == 51 {
            let result = engine.backspace()
            applyResult(result, to: client)
            return result.handled
        }

        // Enter → flush 후 시스템 위임
        if event.keyCode == 36 {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // Space → flush 후 시스템 위임
        if event.keyCode == 49 {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // Escape → 조합 폐기
        if event.keyCode == 53 {
            engine.reset()
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
            return false
        }

        // 방향키 → flush 후 통과
        if [123, 124, 125, 126].contains(Int(event.keyCode)) {
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
        guard !layoutLoaded else { return }

        guard let url = Bundle.main.url(forResource: "2-standard", withExtension: "json5"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("[Ongeul] Failed to load keyboard layout file: 2-standard.json5")
            return
        }

        do {
            try engine.loadLayout(json: json)
            engine.setMode(mode: .korean)
            layoutLoaded = true
            NSLog("[Ongeul] Layout loaded: 2-standard")
        } catch {
            NSLog("[Ongeul] Failed to parse keyboard layout: \(error)")
        }
    }
}
