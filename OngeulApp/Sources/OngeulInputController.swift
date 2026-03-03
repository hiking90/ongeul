import Cocoa
import InputMethodKit
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "input")

// MARK: - Mode Indicator (커서 근처 한/영 표시)

private final class ModeIndicator {
    static let shared = ModeIndicator()

    private let panel: NSPanel
    private let label: NSTextField
    private var hideTimer: Timer?

    private init() {
        let size = NSSize(width: 24, height: 20)
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

        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        bg.layer?.cornerRadius = 5
        bg.layer?.masksToBounds = true

        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        label.alignment = .center
        label.textColor = .white
        // 수직 가운데 정렬: 폰트 높이를 고려하여 y 오프셋 조정
        let labelHeight: CGFloat = 14
        label.frame = NSRect(
            x: 0,
            y: (size.height - labelHeight) / 2,
            width: size.width,
            height: labelHeight
        )

        bg.addSubview(label)
        panel.contentView = bg
    }

    func show(mode: InputMode, cursorRect: NSRect) {
        label.stringValue = mode == .korean ? "한" : "A"

        // 커서 아래쪽에 표시하되, 화면 밖이면 위쪽에 표시
        let gap: CGFloat = 4
        let belowY = cursorRect.origin.y - panel.frame.height - gap
        let aboveY = cursorRect.origin.y + cursorRect.size.height + gap

        let screen = NSScreen.main?.frame ?? .zero
        let y = belowY >= screen.minY ? belowY : aboveY

        // 커서 중앙 아래(또는 위)에 배치
        let x = max(screen.minX, cursorRect.origin.x - panel.frame.width / 2)

        let origin = NSPoint(x: x, y: y)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        os_log("ModeIndicator: mode=%{public}@ origin=(%.0f, %.0f) cursorRect=(%.0f, %.0f, %.0f, %.0f)",
               log: log, type: .default,
               mode == .korean ? "ko" : "en",
               origin.x, origin.y,
               cursorRect.origin.x, cursorRect.origin.y,
               cursorRect.size.width, cursorRect.size.height)

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
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

// MARK: - Lock Overlay (화면 중앙 잠금 표시)

private final class LockOverlay {
    static let shared = LockOverlay()

    private let panel: NSPanel
    private let imageView: NSImageView
    private var hideTimer: Timer?

    private init() {
        let size = NSSize(width: 80, height: 80)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        bg.layer?.cornerRadius = 16
        bg.layer?.masksToBounds = true

        imageView = NSImageView(frame: NSRect(x: 16, y: 16, width: 48, height: 48))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .white

        bg.addSubview(imageView)
        panel.contentView = bg
    }

    func show(locked: Bool) {
        let symbolName = locked ? "lock.fill" : "lock.open.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        let screen = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let x = screen.midX - panel.frame.width / 2
        let y = screen.midY - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                self.panel.orderOut(nil)
            })
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
    }
}

// MARK: - Input Controller

@objc(OngeulInputController)
class OngeulInputController: IMKInputController {
    private let engine = HangulEngine()
    private var loadedLayoutId: String?
    private var toggleDetector = ToggleDetector()

    // 합성 Enter 재진입 감지용 CGEvent userData 매직 넘버 (design/24 참조)
    private static let syntheticEnterMarker: Int64 = 0x4F6E6765  // "Onge"

    // 현재 조합 중인 텍스트 (composedString 콜백용)
    private var currentComposingText: String?

    #if DEBUG
    /// 테스트에서 Bundle.main 대신 사용할 레이아웃 디렉토리 URL
    var testLayoutsURL: URL?
    #endif

    // Chromium-based apps auto-commit marked text on focus loss via their
    // renderer process (resignFirstResponder → Blur → ImeFinishComposingText).
    // Detected at runtime by looking for "*Helper (Renderer).app" inside the
    // app bundle — the multi-process renderer helper unique to Chromium.
    private static var chromiumAppCache: [String: Bool] = [:]

    private var clientAutoCommitsMarkedText: Bool {
        guard let bundleId = currentBundleId else { return false }
        if let cached = Self.chromiumAppCache[bundleId] {
            return cached
        }
        let result = Self.isChromiumBased(bundleId: bundleId)
        Self.chromiumAppCache[bundleId] = result
        return result
    }

    private static func isChromiumBased(bundleId: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(
                where: { $0.bundleIdentifier == bundleId }),
              let bundleURL = app.bundleURL else {
            return false
        }
        let frameworksPath = bundleURL.appendingPathComponent("Contents/Frameworks").path
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: frameworksPath) else {
            return false
        }
        // Chromium apps place renderer helpers directly in Contents/Frameworks/
        // (Electron) or inside *.framework/Helpers/ (Chrome, Edge, Brave, etc.)
        if contents.contains(where: { $0.hasSuffix("Helper (Renderer).app") }) {
            return true
        }
        for name in contents where name.hasSuffix(".framework") {
            let helpersPath = (frameworksPath as NSString).appendingPathComponent(name)
            // Check versioned and unversioned Helpers paths
            for sub in ["Helpers", "Versions/Current/Helpers"] {
                let dir = (helpersPath as NSString).appendingPathComponent(sub)
                if let helpers = try? FileManager.default.contentsOfDirectory(atPath: dir),
                   helpers.contains(where: { $0.hasSuffix("Helper (Renderer).app") }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Settings (UserDefaults)

    private static let toggleKeyKey = "toggleKey"
    private static let layoutIdKey = "layoutId"
    private static let escapeToEnglishKey = "escapeToEnglish"

    private static var toggleKey: ToggleKey {
        get {
            let raw = UserDefaults.standard.string(forKey: toggleKeyKey) ?? "rightCommand"
            return ToggleKey(rawValue: raw) ?? .rightCommand
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: toggleKeyKey)
        }
    }

    private static var savedLayoutId: String {
        get {
            UserDefaults.standard.string(forKey: layoutIdKey) ?? "2-standard"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: layoutIdKey)
        }
    }

    private static var escapeToEnglish: Bool {
        get {
            if UserDefaults.standard.object(forKey: escapeToEnglishKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: escapeToEnglishKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: escapeToEnglishKey) }
    }

    // MARK: - Per-App Mode Store

    private static let perAppModeStore = PerAppModeStore()
    private static let englishLockStore = EnglishLockStore()

    private static var hasPromptedAccessibility = false
    private static var activeAppBundleId: String?   // 현재 활성 앱
    private var currentBundleId: String?

    // MARK: - Lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        KeyEventTap.activeController = self

        if !AXIsProcessTrusted() {
            if !Self.hasPromptedAccessibility {
                Self.hasPromptedAccessibility = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
            }
        } else if Self.toggleKey == .shiftSpace {
            KeyEventTap.shared.install()
        }
        loadLayoutIfNeeded()

        guard let bundleId = (sender as? (any IMKTextInput))?.bundleIdentifier() else { return }
        currentBundleId = bundleId

        // Pre-cache Chromium detection so deactivateServer always hits the cache.
        if Self.chromiumAppCache[bundleId] == nil {
            Self.chromiumAppCache[bundleId] = Self.isChromiumBased(bundleId: bundleId)
        }

        let isAppSwitch = (bundleId != Self.activeAppBundleId)
        if isAppSwitch {
            LockOverlay.shared.hide()
        }

        // English Lock 우선 체크
        if Self.englishLockStore.isLocked(bundleId) {
            engine.setMode(mode: .english)
            if isAppSwitch {
                os_log("activateServer: appSwitch to LOCKED %{public}@",
                       log: log, type: .default, bundleId)
                LockOverlay.shared.show(locked: true)
                Self.activeAppBundleId = bundleId
            } else {
                os_log("activateServer: fieldSwitch in LOCKED %{public}@",
                       log: log, type: .default, bundleId)
            }
        } else {
            let currentMode: InputMode
            if let savedMode = Self.perAppModeStore.savedMode(for: bundleId) {
                engine.setMode(mode: savedMode)
                currentMode = savedMode
            } else {
                // 최초 진입 앱: 영문 모드로 시작
                engine.setMode(mode: .english)
                currentMode = .english
            }
            Self.perAppModeStore.saveMode(currentMode, for: bundleId)

            if isAppSwitch {
                let prevMode = Self.activeAppBundleId.flatMap { Self.perAppModeStore.savedMode(for: $0) }
                os_log("activateServer: appSwitch to %{public}@ mode=%{public}@ (prev=%{public}@)",
                       log: log, type: .default, bundleId,
                       currentMode == .korean ? "korean" : "english",
                       prevMode.map { $0 == .korean ? "korean" : "english" } ?? "none")

                if let prevMode, currentMode != prevMode,
                   let client = sender as? (any IMKTextInput) {
                    showModeIndicator(client: client)
                }
                Self.activeAppBundleId = bundleId
            } else {
                os_log("activateServer: fieldSwitch in %{public}@ mode=%{public}@",
                       log: log, type: .default, bundleId,
                       currentMode == .korean ? "korean" : "english")
            }
        }
    }

    override func composedString(_ sender: Any!) -> Any! {
        return (currentComposingText ?? "") as NSString
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? (any IMKTextInput) else { return }
        let result = engine.flush()
        applyResult(result, to: client)
    }

    override func deactivateServer(_ sender: Any!) {
        if KeyEventTap.activeController === self {
            KeyEventTap.activeController = nil
        }
        if let bundleId = currentBundleId {
            let mode = engine.getMode()
            Self.perAppModeStore.saveMode(mode, for: bundleId)
            os_log("deactivateServer: save mode=%{public}@ for bundleId=%{public}@",
                   log: log, type: .default,
                   mode == .korean ? "korean" : "english", bundleId)
        }
        if let client = sender as? (any IMKTextInput) {
            let result = engine.flush()
            // Chromium-based apps auto-commit marked text on focus loss via
            // their renderer process. Calling insertText would duplicate it.
            if result.committed != nil && !clientAutoCommitsMarkedText {
                applyResult(result, to: client)
            }
        }
        super.deactivateServer(sender)
    }

    // MARK: - Menu

    override func menu() -> NSMenu! {
        os_log("menu() called", log: log, type: .default)
        let menu = NSMenu()

        let prefsItem = NSMenuItem(
            title: NSLocalizedString("menu.preferences", comment: ""),
            action: #selector(openPreferences(_:)),
            keyEquivalent: "")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let helpItem = NSMenuItem(
            title: NSLocalizedString("menu.help", comment: ""),
            action: #selector(openHelp(_:)),
            keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        return menu
    }

    @objc private func openProjectPage(_ sender: Any?) {
        if let url = URL(string: "https://github.com/hiking90/ongeul") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openHelp(_ sender: Any?) {
        if let url = URL(string: "https://hiking90.github.io/ongeul/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openPreferences(_ sender: Any?) {
        os_log("openPreferences called", log: log, type: .default)
        // 메뉴가 닫힌 후 다음 런루프에서 실행
        DispatchQueue.main.async {
            // IME 프로세스는 백그라운드 앱이므로 윈도우 표시를 위해 활성화 정책 변경
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("prefs.title", comment: "")
            alert.alertStyle = .informational
            if let iconPath = Bundle.main.pathForImageResource("AppIcon"),
               let icon = NSImage(contentsOfFile: iconPath) {
                alert.icon = icon
            }
            alert.addButton(withTitle: NSLocalizedString("prefs.ok", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("prefs.cancel", comment: ""))

            // -- Accessory View: Combo Box (NSPopUpButton) --
            let container = NSStackView()
            container.orientation = .vertical
            container.alignment = .centerX
            container.spacing = 12

            // 한/영 전환 키
            let toggleLabel = NSTextField(labelWithString: NSLocalizedString("prefs.toggleKey.label", comment: ""))
            let togglePopup = NSPopUpButton(frame: .zero, pullsDown: false)
            let toggleKeyTitles: [(ToggleKey, String)] = [
                (.rightCommand, NSLocalizedString("prefs.toggleKey.rightCommand", comment: "")),
                (.rightOption,  NSLocalizedString("prefs.toggleKey.rightOption", comment: "")),
                (.leftShift,    NSLocalizedString("prefs.toggleKey.leftShift", comment: "")),
                (.rightShift,   NSLocalizedString("prefs.toggleKey.rightShift", comment: "")),
                (.shiftSpace,   NSLocalizedString("prefs.toggleKey.shiftSpace", comment: "")),
            ]
            for (_, title) in toggleKeyTitles {
                togglePopup.addItem(withTitle: title)
            }
            let currentToggleIndex = toggleKeyTitles.firstIndex { $0.0 == Self.toggleKey } ?? 0
            togglePopup.selectItem(at: currentToggleIndex)

            let toggleRow = NSStackView(views: [toggleLabel, togglePopup])
            toggleRow.orientation = .horizontal
            toggleRow.spacing = 8

            // 한글 자판
            let layoutLabel = NSTextField(labelWithString: NSLocalizedString("prefs.layout.label", comment: ""))
            let layoutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            layoutPopup.addItem(withTitle: NSLocalizedString("prefs.layout.2standard", comment: ""))
            layoutPopup.addItem(withTitle: NSLocalizedString("prefs.layout.3_390", comment: ""))
            layoutPopup.addItem(withTitle: NSLocalizedString("prefs.layout.3final", comment: ""))
            switch Self.savedLayoutId {
            case "3-390": layoutPopup.selectItem(at: 1)
            case "3-final": layoutPopup.selectItem(at: 2)
            default: layoutPopup.selectItem(at: 0)
            }

            let layoutRow = NSStackView(views: [layoutLabel, layoutPopup])
            layoutRow.orientation = .horizontal
            layoutRow.spacing = 8

            // ESC → 영문 전환
            let escapeCheckbox = NSButton(
                checkboxWithTitle: NSLocalizedString("prefs.escapeToEnglish", comment: ""),
                target: nil, action: nil
            )
            escapeCheckbox.state = Self.escapeToEnglish ? .on : .off

            container.addArrangedSubview(toggleRow)
            container.addArrangedSubview(layoutRow)
            container.addArrangedSubview(escapeCheckbox)

            // 버전 및 개발자 정보
            let separator = NSBox()
            separator.boxType = .separator
            container.addArrangedSubview(separator)

            let aboutGroup = NSStackView()
            aboutGroup.orientation = .vertical
            aboutGroup.alignment = .centerX
            aboutGroup.spacing = 4

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            let aboutLabel = NSTextField(labelWithString: "Ongeul v\(version)  —  hiking90")
            aboutLabel.font = NSFont.systemFont(ofSize: 12)
            aboutLabel.textColor = .secondaryLabelColor
            aboutLabel.alignment = .center
            aboutGroup.addArrangedSubview(aboutLabel)

            let linkTitle = NSAttributedString(string: "github.com/hiking90/ongeul", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand,
            ])
            let projectLink = NSButton(title: "", target: self, action: #selector(self.openProjectPage(_:)))
            projectLink.attributedTitle = linkTitle
            projectLink.bezelStyle = .inline
            projectLink.isBordered = false
            aboutGroup.addArrangedSubview(projectLink)

            container.addArrangedSubview(aboutGroup)

            // accessoryView에 명시적 크기 설정
            let size = container.fittingSize
            container.frame = NSRect(origin: .zero, size: size)
            alert.accessoryView = container

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 확인 → 저장
                Self.toggleKey = toggleKeyTitles[togglePopup.indexOfSelectedItem].0
                let newLayout: String
                switch layoutPopup.indexOfSelectedItem {
                case 1: newLayout = "3-390"
                case 2: newLayout = "3-final"
                default: newLayout = "2-standard"
                }
                Self.savedLayoutId = newLayout
                Self.escapeToEnglish = escapeCheckbox.state == .on
                os_log("Settings saved: toggleKey=%{public}@ layoutId=%{public}@ escapeToEnglish=%{public}d",
                       log: log, type: .default,
                       Self.toggleKey.rawValue, newLayout, Self.escapeToEnglish)

                // Shift+Space 선택 시 CGEventTap 설치/해제
                if Self.toggleKey == .shiftSpace {
                    KeyEventTap.shared.install()
                } else {
                    KeyEventTap.shared.uninstall()
                }
            }

            // 다이얼로그 닫힌 후 원래 정책으로 복원
            NSApp.setActivationPolicy(.prohibited)
        }
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

    // MARK: - Private: Modifier Key Handling (ToggleDetector에 위임)

    private func handleFlagsChanged(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let action = toggleDetector.handleFlagsChanged(
            keyCode: event.keyCode,
            flags: event.modifierFlags,
            toggleKey: Self.toggleKey
        )
        switch action {
        case .none:
            return false
        case .toggle:
            performToggle(source: "flagsChanged", client: client)
            return true
        case .englishLockToggle:
            handleEnglishLockToggle(client: client)
            return true
        }
    }

    // MARK: - Private: English Lock Toggle

    private func handleEnglishLockToggle(client: any IMKTextInput) {
        guard let bundleId = currentBundleId else { return }

        if Self.englishLockStore.isLocked(bundleId) {
            // 해제: 저장된 이전 모드 복원
            let previousMode = Self.englishLockStore.removeLock(for: bundleId) ?? .korean
            engine.setMode(mode: previousMode)
            Self.perAppModeStore.saveMode(previousMode, for: bundleId)
            os_log("English Lock OFF: %{public}@ → restore %{public}@",
                   log: log, type: .default, bundleId,
                   previousMode == .korean ? "korean" : "english")
            LockOverlay.shared.show(locked: false)
        } else {
            // 잠금: 현재 모드 저장 → 영어 강제
            let currentMode = engine.getMode()
            Self.englishLockStore.addLock(for: bundleId, previousMode: currentMode)
            // 한글 조합 중이면 flush로 확정
            if currentMode == .korean {
                let result = engine.flush()
                applyResult(result, to: client)
            }
            engine.setMode(mode: .english)
            os_log("English Lock ON: %{public}@ (was %{public}@)",
                   log: log, type: .default, bundleId,
                   currentMode == .korean ? "korean" : "english")
            LockOverlay.shared.show(locked: true)
        }
    }

    // MARK: - Private: Toggle (common)

    private func performToggle(source: String, client: any IMKTextInput) {
        if let bundleId = currentBundleId, Self.englishLockStore.isLocked(bundleId) { return }

        let result = engine.toggleMode()
        applyResult(result, to: client)
        let newMode = engine.getMode()
        os_log("toggleMode (%{public}@) → %{public}@", log: log, type: .default,
               source, newMode == .korean ? "korean" : "english")
        if let bundleId = currentBundleId {
            Self.perAppModeStore.saveMode(newMode, for: bundleId)
        }
        showModeIndicator(client: client)
    }

    func performToggleFromTap() {
        guard let client: any IMKTextInput = self.client() else { return }
        performToggle(source: "CGEventTap", client: client)
    }

    // MARK: - Private: Mode Indicator

    private func showModeIndicator(client: any IMKTextInput) {
        var rect = cursorRect(from: client)

        // cursorRect가 .zero를 반환했거나, 화면 밖 좌표인 경우 → 화면 하단 중앙
        let point = NSPoint(x: rect.origin.x, y: rect.origin.y)
        let isOnScreen = NSScreen.screens.contains { $0.frame.contains(point) }
        if rect == .zero || !isOnScreen {
            let screen = NSScreen.main?.visibleFrame
                ?? NSScreen.screens.first?.visibleFrame ?? .zero
            rect = NSRect(x: screen.midX, y: screen.minY + 80, width: 0, height: 16)
        }

        ModeIndicator.shared.show(mode: engine.getMode(), cursorRect: rect)
    }

    private func cursorRect(from client: any IMKTextInput) -> NSRect {
        var lineHeightRect = NSRect.zero
        let selRange = client.selectedRange()
        let index = selRange.location != NSNotFound ? selRange.location : 0
        os_log("cursorRect: selectedRange=(%d, %d) index=%d",
               log: log, type: .debug, selRange.location, selRange.length, index)

        let success = ObjCExceptionCatcher.performSafely {
            client.attributes(forCharacterIndex: index, lineHeightRectangle: &lineHeightRect)
        }

        if success, isValidRect(lineHeightRect) {
            os_log("cursorRect: rect=(%.0f, %.0f, %.0f, %.0f)",
                   log: log, type: .debug,
                   lineHeightRect.origin.x, lineHeightRect.origin.y,
                   lineHeightRect.size.width, lineHeightRect.size.height)
            return lineHeightRect
        }

        // index 0으로 재시도 (OpenVanilla 방식)
        if index != 0 {
            let retrySuccess = ObjCExceptionCatcher.performSafely {
                client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)
            }
            if retrySuccess, isValidRect(lineHeightRect) {
                os_log("cursorRect: fallback index=0 rect=(%.0f, %.0f, %.0f, %.0f)",
                       log: log, type: .debug,
                       lineHeightRect.origin.x, lineHeightRect.origin.y,
                       lineHeightRect.size.width, lineHeightRect.size.height)
                return lineHeightRect
            }
        }

        os_log("cursorRect: failed, returning .zero", log: log, type: .debug)
        return .zero
    }

    private func isValidRect(_ rect: NSRect) -> Bool {
        guard rect.origin.x.isFinite && rect.origin.y.isFinite else { return false }
        if rect.size.height > 0 { return true }
        return false
    }

    // MARK: - Private: Key Processing

    private func handleKeyDown(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let modifiers = event.modifierFlags

        // 키 입력 → modifier tap 판정 취소 + 4키 사이클 취소
        toggleDetector.cancelOnKeyDown()

        // Shift+Space → 한/영 전환 (shiftSpace 모드일 때)
        if Self.toggleKey == .shiftSpace
            && event.keyCode == KeyCode.space
            && modifiers.contains(.shift)
            && !modifiers.contains(.option)
            && !modifiers.contains(.command)
            && !modifiers.contains(.control) {
            performToggle(source: "IMK", client: client)
            return true
        }

        // 영문 모드: 전환 키 외 모든 키를 시스템에 위임 (ABC와 동일한 동작)
        if engine.getMode() == .english {
            return false
        }

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

        // Enter — 토큰 필드 조합 글자 중복 방지 (design/24-token-field-enter-duplicate.md)
        //
        // 문제: NSTokenField 등에서 조합 중 Enter를 누르면 insertText("동")과 Enter가
        //       같은 이벤트 사이클에서 처리되어, 토큰 [홍길동] 생성 후 "동"이 중복 입력됨.
        //
        // 해결: 접근성 권한이 있으면 insertText로 조합을 확정한 뒤, 원본 Enter를 소비하고
        //       합성 Enter를 다음 런루프에서 .cghidEventTap으로 재전달한다.
        //       CGEvent의 eventSourceUserData 필드에 매직 넘버를 삽입하여 재진입을 감지하고,
        //       합성 Enter는 엔진 처리를 건너뛰고 바로 시스템에 전달된다.
        //       접근성 권한이 없으면 기존 방식(insertText + return false)으로 폴백한다.
        if event.keyCode == KeyCode.enter {
            if let cgEvent = event.cgEvent,
               cgEvent.getIntegerValueField(.eventSourceUserData) == Self.syntheticEnterMarker {
                os_log("Enter: synthetic (userData), passing to system", log: log, type: .debug)
                return false
            }

            let result = engine.flush()
            if result.committed != nil {
                applyResult(result, to: client)
                if AXIsProcessTrusted() {
                    let originalFlags = event.cgEvent?.flags ?? []
                    DispatchQueue.main.async {
                        let src = CGEventSource(stateID: .hidSystemState)
                        if let down = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.enter, keyDown: true) {
                            down.flags = originalFlags
                            down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEnterMarker)
                            down.post(tap: .cghidEventTap)
                        }
                        if let up = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.enter, keyDown: false) {
                            up.flags = originalFlags
                            up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEnterMarker)
                            up.post(tap: .cghidEventTap)
                        }
                    }
                    os_log("Enter: flushed, posting synthetic Enter via cghidEventTap", log: log, type: .debug)
                    return true
                }
                os_log("Enter: flushed, no accessibility — fallback to return false", log: log, type: .debug)
            }
            return false
        }

        // Space → flush 후 시스템 위임
        if event.keyCode == KeyCode.space {
            let result = engine.flush()
            applyResult(result, to: client)
            return false
        }

        // Escape → 조합 폐기 (+ 옵션: 영문 전환)
        if event.keyCode == KeyCode.escape {
            engine.reset()
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
            if Self.escapeToEnglish && engine.getMode() == .korean {
                engine.setMode(mode: .english)
                if let bundleId = currentBundleId {
                    Self.perAppModeStore.saveMode(.english, for: bundleId)
                }
                showModeIndicator(client: client)
            }
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
        guard let chars = event.characters else { return nil }
        return keyLabel(
            characters: chars,
            capsLock: event.modifierFlags.contains(.capsLock),
            shift: event.modifierFlags.contains(.shift)
        )
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
            currentComposingText = composing
            let styled = NSAttributedString(string: composing, attributes: [
                .underlineStyle: 0,
                .backgroundColor: NSColor.clear,
            ])
            client.setMarkedText(
                styled,
                selectionRange: NSRange(location: composing.count, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        } else {
            currentComposingText = nil
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }
    }

    // MARK: - Private: Layout Loading

    private func loadLayoutIfNeeded() {
        let desiredLayoutId = Self.savedLayoutId
        guard loadedLayoutId != desiredLayoutId else { return }

        // 재로드 시 현재 조합 flush
        if loadedLayoutId != nil {
            if let client = self.client() {
                let result = engine.flush()
                applyResult(result, to: client)
            }
        }

        let url: URL?
        #if DEBUG
        if let testURL = testLayoutsURL {
            url = testURL.appendingPathComponent("\(desiredLayoutId).json5")
        } else {
            url = Bundle.main.url(forResource: desiredLayoutId, withExtension: "json5")
        }
        #else
        url = Bundle.main.url(forResource: desiredLayoutId, withExtension: "json5")
        #endif

        guard let url, let json = try? String(contentsOf: url, encoding: .utf8) else {
            os_log("Failed to load layout: %{public}@.json5", log: log, type: .error, desiredLayoutId)
            return
        }

        do {
            try engine.loadLayout(json: json)
            // 초기 로드일 때만 영문 모드로 설정, 재로드 시 현재 모드 유지
            if loadedLayoutId == nil {
                engine.setMode(mode: .english)
            }
            loadedLayoutId = desiredLayoutId
        } catch {
            os_log("Failed to parse layout: %{public}@", log: log, type: .error, String(describing: error))
        }
    }
}
