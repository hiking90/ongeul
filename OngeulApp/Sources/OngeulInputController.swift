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

// MARK: - Mode Indicator (커서 근처 한/영 표시)

private final class ModeIndicator {
    static let shared = ModeIndicator()

    private let panel: NSPanel
    private let label: NSTextField
    private var hideTimer: Timer?

    private init() {
        let size = NSSize(width: 32, height: 24)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // IME 프로세스에서 다른 앱 위에 표시되려면 충분히 높은 윈도우 레벨 필요
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 4

        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.textColor = .labelColor
        label.frame = NSRect(origin: .zero, size: size)

        bg.addSubview(label)
        panel.contentView = bg
    }

    func show(mode: InputMode, cursorRect: NSRect) {
        label.stringValue = mode == .korean ? "한" : "A"

        // 커서 아래쪽에 표시
        let origin = NSPoint(
            x: cursorRect.origin.x,
            y: cursorRect.origin.y - panel.frame.height - 4
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        os_log("ModeIndicator: mode=%{public}@ origin=(%.0f, %.0f) cursorRect=(%.0f, %.0f, %.0f, %.0f)",
               log: log, type: .debug,
               mode == .korean ? "ko" : "en",
               origin.x, origin.y,
               cursorRect.origin.x, cursorRect.origin.y,
               cursorRect.size.width, cursorRect.size.height)

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                self.panel.orderOut(nil)
            })
        }
    }
}

// MARK: - Input Controller

@objc(OngeulInputController)
class OngeulInputController: IMKInputController {
    private let engine = HangulEngine()
    private var activeLayoutId: String = "2-standard"
    private var loadedLayoutId: String?
    private var rightCmdPending = false

    private static let defaultLayoutId = "2-standard"
    private static let modePrefix = "com.example.inputmethod.Ongeul."
    private static let imInputModeTag: Int = 0x696D696D // 'imim'
    private static let validLayoutIds: Set<String> = ["2-standard", "3-390", "3-final"]

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

    // MARK: - Input Mode Switching (setValue:forTag:client:)

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        super.setValue(value, forTag: tag, client: sender)

        guard tag == Self.imInputModeTag,
              let modeId = value as? String,
              modeId.hasPrefix(Self.modePrefix) else { return }

        let layoutId = String(modeId.dropFirst(Self.modePrefix.count))
        guard Self.validLayoutIds.contains(layoutId) else { return }

        // 이전 조합 flush (레이아웃 변경 시)
        if loadedLayoutId != nil && loadedLayoutId != layoutId {
            let result = engine.flush()
            if let client = self.client() {
                applyResult(result, to: client)
            }
        }

        activeLayoutId = layoutId
        loadLayoutIfNeeded()
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

        loadLayoutIfNeeded()

        if event.type == .flagsChanged {
            return handleFlagsChanged(event, client: client)
        }

        if event.type == .keyDown {
            return handleKeyDown(event, client: client)
        }

        return false
    }

    // MARK: - Private: Right Command → 한/영 전환

    private func handleFlagsChanged(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        if event.keyCode == KeyCode.rightCommand {
            if event.modifierFlags.contains(.command) {
                rightCmdPending = true
            } else if rightCmdPending {
                rightCmdPending = false
                let result = engine.toggleMode()
                applyResult(result, to: client)
                showModeIndicator(client: client)
                return true
            }
            return false
        }

        rightCmdPending = false
        return false
    }

    // MARK: - Private: Mode Indicator

    private func showModeIndicator(client: any IMKTextInput) {
        let selRange = client.selectedRange()
        var actualRange = NSRange()
        let cursorRect = client.firstRect(
            forCharacterRange: selRange,
            actualRange: &actualRange
        )
        guard cursorRect.origin.x.isFinite && cursorRect.origin.y.isFinite,
              cursorRect != .zero else {
            os_log("showModeIndicator: invalid cursorRect, selRange=(%d, %d)",
                   log: log, type: .debug, selRange.location, selRange.length)
            return
        }

        ModeIndicator.shared.show(mode: engine.getMode(), cursorRect: cursorRect)
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
        guard loadedLayoutId != activeLayoutId else { return }

        guard let url = Bundle.main.url(forResource: activeLayoutId, withExtension: "json5"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            os_log("Failed to load layout: %{public}@.json5", log: log, type: .error, activeLayoutId)
            return
        }

        do {
            try engine.loadLayout(json: json)
            engine.setMode(mode: .korean)
            loadedLayoutId = activeLayoutId
        } catch {
            os_log("Failed to parse layout: %{public}@", log: log, type: .error, String(describing: error))
        }
    }
}
