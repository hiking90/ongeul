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
        let timer = Timer(timeInterval: 1.6, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self.panel.animator().alphaValue = 0
            })
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
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
        let timer = Timer(timeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                self.panel.animator().alphaValue = 0
            })
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.alphaValue = 0
    }
}

// MARK: - Preferences Panel (비활성화 패널 기반 설정)

private final class PreferencesPanel {
    static let shared = PreferencesPanel()

    private let panel: NSPanel
    private let togglePopup: NSPopUpButton
    private let layoutPopup: NSPopUpButton
    private let escapeCheckbox: NSButton
    private let indicatorCheckbox: NSButton
    private let toggleKeyTitles: [(ToggleKey, String)]

    private init() {
        toggleKeyTitles = [
            (.rightCommand, NSLocalizedString("prefs.toggleKey.rightCommand", comment: "")),
            (.rightOption,  NSLocalizedString("prefs.toggleKey.rightOption", comment: "")),
            (.leftShift,    NSLocalizedString("prefs.toggleKey.leftShift", comment: "")),
            (.rightShift,   NSLocalizedString("prefs.toggleKey.rightShift", comment: "")),
            (.shiftSpace,   NSLocalizedString("prefs.toggleKey.shiftSpace", comment: "")),
        ]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = NSLocalizedString("prefs.title", comment: "")
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hidesOnDeactivate = false

        // -- 한/영 전환 키 --
        let toggleLabel = NSTextField(labelWithString: NSLocalizedString("prefs.toggleKey.label", comment: ""))
        togglePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (_, title) in toggleKeyTitles {
            togglePopup.addItem(withTitle: title)
        }
        // -- 한글 자판 --
        let layoutLabel = NSTextField(labelWithString: NSLocalizedString("prefs.layout.label", comment: ""))
        layoutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        layoutPopup.addItem(withTitle: NSLocalizedString("prefs.layout.2standard", comment: ""))
        layoutPopup.addItem(withTitle: NSLocalizedString("prefs.layout.3_390", comment: ""))
        layoutPopup.addItem(withTitle: NSLocalizedString("prefs.layout.3final", comment: ""))

        // 라벨-팝업 그리드 (열 정렬)
        let settingsGrid = NSGridView(views: [
            [toggleLabel, togglePopup],
            [layoutLabel, layoutPopup],
        ])
        settingsGrid.rowSpacing = 8
        settingsGrid.columnSpacing = 8
        settingsGrid.column(at: 0).xPlacement = .trailing
        settingsGrid.column(at: 1).xPlacement = .leading

        // -- ESC → 영문 전환 --
        escapeCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("prefs.escapeToEnglish", comment: ""),
            target: nil, action: nil
        )

        // -- 한/영 인디케이터 표시 --
        indicatorCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("prefs.showModeIndicator", comment: ""),
            target: nil, action: nil
        )

        // -- 버전 및 개발자 정보 --
        let separator = NSBox()
        separator.boxType = .separator

        let linkTitle = NSAttributedString(string: "github.com/hiking90/ongeul", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ])
        let projectLink = NSButton(title: "", target: nil, action: #selector(openProjectPage(_:)))
        projectLink.attributedTitle = linkTitle
        projectLink.bezelStyle = .inline
        projectLink.isBordered = false

        // -- 버튼 --
        let cancelButton = NSButton(
            title: NSLocalizedString("prefs.cancel", comment: ""),
            target: nil, action: #selector(cancelClicked(_:))
        )
        cancelButton.keyEquivalent = "\u{1b}"  // Escape
        let okButton = NSButton(
            title: NSLocalizedString("prefs.ok", comment: ""),
            target: nil, action: #selector(okClicked(_:))
        )
        okButton.keyEquivalent = "\r"  // Enter
        let buttonRow = NSStackView(views: [cancelButton, okButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        // -- 헤더: 아이콘 + 앱 이름 --
        let headerGroup = NSStackView()
        headerGroup.orientation = .horizontal
        headerGroup.alignment = .centerY
        headerGroup.spacing = 8

        let iconView = NSImageView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let iconPath = Bundle.main.pathForImageResource("AppIcon"),
           let icon = NSImage(contentsOfFile: iconPath) {
            iconView.image = icon
        }
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let titleLabel = NSTextField(labelWithString: "온글(Ongeul)")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: "v\(version)")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor

        let titleGroup = NSStackView(views: [titleLabel, versionLabel])
        titleGroup.orientation = .vertical
        titleGroup.alignment = .leading
        titleGroup.spacing = 2

        headerGroup.addArrangedSubview(iconView)
        headerGroup.addArrangedSubview(titleGroup)

        // -- 전체 레이아웃 --
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        container.addArrangedSubview(headerGroup)

        // 그리드 + 체크박스를 하나의 설정 그룹으로 묶어 정렬
        let checkboxGroup = NSStackView(views: [escapeCheckbox, indicatorCheckbox])
        checkboxGroup.orientation = .vertical
        checkboxGroup.alignment = .leading
        checkboxGroup.spacing = 8

        let settingsGroup = NSStackView(views: [settingsGrid, checkboxGroup])
        settingsGroup.orientation = .vertical
        settingsGroup.alignment = .centerX
        settingsGroup.spacing = 12

        container.setCustomSpacing(20, after: headerGroup)
        container.addArrangedSubview(settingsGroup)
        container.addArrangedSubview(separator)
        container.addArrangedSubview(projectLink)
        container.addArrangedSubview(buttonRow)

        panel.contentView = container

        // target을 init 완료 후 설정 (self 참조)
        projectLink.target = self
        cancelButton.target = self
        okButton.target = self
    }

    func show() {
        // 현재 설정값 로드
        let currentToggleIndex = toggleKeyTitles.firstIndex { $0.0 == OngeulInputController.toggleKey } ?? 0
        togglePopup.selectItem(at: currentToggleIndex)

        switch OngeulInputController.savedLayoutId {
        case "3-390": layoutPopup.selectItem(at: 1)
        case "3-final": layoutPopup.selectItem(at: 2)
        default: layoutPopup.selectItem(at: 0)
        }

        escapeCheckbox.state = OngeulInputController.escapeToEnglish ? .on : .off
        indicatorCheckbox.state = OngeulInputController.showModeIndicator ? .on : .off

        panel.center()
        panel.orderFrontRegardless()
    }

    @objc private func okClicked(_ sender: Any?) {
        OngeulInputController.toggleKey = toggleKeyTitles[togglePopup.indexOfSelectedItem].0

        let newLayout: String
        switch layoutPopup.indexOfSelectedItem {
        case 1: newLayout = "3-390"
        case 2: newLayout = "3-final"
        default: newLayout = "2-standard"
        }
        OngeulInputController.savedLayoutId = newLayout
        OngeulInputController.escapeToEnglish = escapeCheckbox.state == .on
        OngeulInputController.showModeIndicator = indicatorCheckbox.state == .on

        os_log("Settings saved: toggleKey=%{public}@ layoutId=%{public}@ escapeToEnglish=%{public}d",
               log: log, type: .default,
               OngeulInputController.toggleKey.rawValue, newLayout, OngeulInputController.escapeToEnglish)

        KeyEventTap.toggleKey = OngeulInputController.toggleKey
        KeyEventTap.shared.install()

        panel.orderOut(nil)
    }

    @objc private func cancelClicked(_ sender: Any?) {
        panel.orderOut(nil)
    }

    @objc private func openProjectPage(_ sender: Any?) {
        if let url = URL(string: "https://github.com/hiking90/ongeul") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Input Controller

@objc(OngeulInputController)
class OngeulInputController: IMKInputController {
    private let engine = HangulEngine()
    private var loadedLayoutId: String?
    private var toggleDetector = ToggleDetector()

    // 모드 변경 시 KeyEventTap.currentInputMode를 동기화하는 wrapper
    private func setModeAndSync(_ mode: InputMode) {
        engine.setMode(mode: mode)
        KeyEventTap.currentInputMode = mode
    }
    private func toggleModeAndSync() -> ProcessResult {
        let result = engine.toggleMode()
        KeyEventTap.currentInputMode = engine.getMode()
        return result
    }

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
    private static let showModeIndicatorKey = "showModeIndicator"

    fileprivate static var toggleKey: ToggleKey {
        get {
            let raw = UserDefaults.standard.string(forKey: toggleKeyKey) ?? "rightCommand"
            return ToggleKey(rawValue: raw) ?? .rightCommand
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: toggleKeyKey)
        }
    }

    fileprivate static var savedLayoutId: String {
        get {
            UserDefaults.standard.string(forKey: layoutIdKey) ?? "2-standard"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: layoutIdKey)
        }
    }

    fileprivate static var escapeToEnglish: Bool {
        get {
            if UserDefaults.standard.object(forKey: escapeToEnglishKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: escapeToEnglishKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: escapeToEnglishKey) }
    }

    fileprivate static var showModeIndicator: Bool {
        get {
            if UserDefaults.standard.object(forKey: showModeIndicatorKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showModeIndicatorKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showModeIndicatorKey) }
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
        } else {
            KeyEventTap.toggleKey = Self.toggleKey
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
            setModeAndSync(.english)
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
                setModeAndSync(savedMode)
                currentMode = savedMode
            } else {
                // 최초 진입 앱: 영문 모드로 시작
                setModeAndSync(.english)
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

        // Focus-steal correction: 키 입력 시점의 모드 기준으로 판단
        let buf = KeyEventTap.keyBuffer
        os_log("focusSteal: activateServer end — bufSize=%d keyWasKorean=%d",
               log: log, type: .debug, buf.count, KeyEventTap.keyBufferWasKoreanMode)
        if KeyEventTap.keyBufferWasKoreanMode, !buf.isEmpty,
           let client = sender as? (any IMKTextInput) {
            correctFocusSteal(client: client)
        } else {
            KeyEventTap.keyBuffer = []
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

    @objc private func openHelp(_ sender: Any?) {
        if let url = URL(string: "https://hiking90.github.io/ongeul/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openPreferences(_ sender: Any?) {
        os_log("openPreferences called", log: log, type: .default)
        DispatchQueue.main.async {
            PreferencesPanel.shared.show()
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
        // CGEventTap이 설치되어 있으면 tap에서 이미 처리했으므로 스킵
        // (접근성 미허용 시에만 이 경로로 폴백)
        if KeyEventTap.shared.isInstalled { return false }

        let action = toggleDetector.handleFlagsChanged(
            keyCode: event.keyCode,
            flags: event.modifierFlags,
            toggleKey: Self.toggleKey
        )
        switch action {
        case .none:
            return false
        case .toggle:
            if let bundleId = currentBundleId, Self.englishLockStore.isLocked(bundleId) {
                return false  // 잠금 상태 → 시스템에 통과
            }
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
            setModeAndSync(previousMode)
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
            setModeAndSync(.english)
            os_log("English Lock ON: %{public}@ (was %{public}@)",
                   log: log, type: .default, bundleId,
                   currentMode == .korean ? "korean" : "english")
            LockOverlay.shared.show(locked: true)
        }
    }

    // MARK: - Private: Toggle (common)

    private func performToggle(source: String, client: any IMKTextInput) {
        if let bundleId = currentBundleId, Self.englishLockStore.isLocked(bundleId) { return }

        let result = toggleModeAndSync()
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

    func performEnglishLockToggleFromTap() {
        guard let client: any IMKTextInput = self.client() else { return }
        handleEnglishLockToggle(client: client)
    }

    /// KeyEventTap에서 호출: 현재 앱이 English Lock 상태인지 반환
    func isCurrentAppLocked() -> Bool {
        guard let bundleId = currentBundleId else { return false }
        return Self.englishLockStore.isLocked(bundleId)
    }

    // MARK: - Private: Mode Indicator

    private func showModeIndicator(client: any IMKTextInput) {
        guard Self.showModeIndicator else { return }
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

    // MARK: - Private: Focus-Steal Correction

    /// 포커스 탈취 교정: 입력창이 없는 상태에서 앱이 키를 직접 받아 영문을 삽입한 경우,
    /// synthetic backspace로 영문을 삭제하고 버퍼의 모든 키를 재전송하여 한글로 처리한다.
    ///
    /// replacementRange가 committed text에 대해 동작하지 않는 앱이 있으므로,
    /// synthetic 이벤트로 앱의 네이티브 동작을 활용한다.
    /// - backspace: 엔진에 composing이 없으므로 engine.backspace()→handled=false → 시스템이 삭제
    /// - key re-post: 엔진이 한글 모드이므로 정상적인 한글 처리 경로로 진입
    private func correctFocusSteal(client: any IMKTextInput) {
        let buffer = KeyEventTap.keyBuffer
        KeyEventTap.keyBuffer = []

        guard let firstKey = buffer.first else { return }

        let elapsed = CFAbsoluteTimeGetCurrent() - firstKey.timestamp
        os_log("correctFocusSteal: firstKey='%{public}@' elapsed=%.3f bufSize=%d",
               log: log, type: .debug, firstKey.character, elapsed, buffer.count)

        guard elapsed < 0.2 else {
            os_log("correctFocusSteal: skip — elapsed=%.3f > 0.2",
                   log: log, type: .debug, elapsed)
            return
        }

        let sel = client.selectedRange()
        guard sel.location != NSNotFound, sel.location > 0 else { return }

        // ObjC 예외 안전하게 텍스트 읽기: 첫 번째 키와 매칭
        let range = NSRange(location: sel.location - 1, length: 1)
        var clientText: String?
        let success = ObjCExceptionCatcher.performSafely {
            clientText = client.attributedSubstring(from: range)?.string
        }

        os_log("correctFocusSteal: sel=(%d,%d) clientText='%{public}@' success=%d",
               log: log, type: .debug, sel.location, sel.length,
               clientText ?? "(nil)", success)

        guard success, clientText == firstKey.character else { return }

        // 한글 모드로 전환 + per-app 저장
        if engine.getMode() != .korean {
            setModeAndSync(.korean)
        }
        if let bundleId = currentBundleId {
            Self.perAppModeStore.saveMode(.korean, for: bundleId)
        }
        // 엔진 flush (이전 필드에서의 composing 잔여 상태 제거)
        let _ = engine.flush()

        // 1) synthetic backspace → 시스템이 focus-steal 문자 삭제
        // 2) 버퍼의 모든 키를 순서대로 re-post → 한글 모드로 정상 처리
        let src = CGEventSource(stateID: .hidSystemState)
        let marker = KeyEventTap.focusStealMarker
        if let down = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.backspace, keyDown: true) {
            down.setIntegerValueField(.eventSourceUserData, value: marker)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.backspace, keyDown: false) {
            up.setIntegerValueField(.eventSourceUserData, value: marker)
            up.post(tap: .cghidEventTap)
        }
        for key in buffer {
            if let down = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: true) {
                down.flags = key.flags
                down.setIntegerValueField(.eventSourceUserData, value: marker)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: false) {
                up.flags = key.flags
                up.setIntegerValueField(.eventSourceUserData, value: marker)
                up.post(tap: .cghidEventTap)
            }
        }

        os_log("correctFocusSteal: posted backspace + %d keys (first='%{public}@')",
               log: log, type: .default, buffer.count, firstKey.character)
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
            if let bundleId = currentBundleId, Self.englishLockStore.isLocked(bundleId) {
                return false  // 잠금 상태 → Shift+Space를 시스템에 통과
            }
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

        // Escape → 조합 확정 (+ 옵션: 영문 전환)
        if event.keyCode == KeyCode.escape {
            let result = engine.flush()
            applyResult(result, to: client)
            if Self.escapeToEnglish && engine.getMode() == .korean {
                setModeAndSync(.english)
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
                setModeAndSync(.english)
            }
            loadedLayoutId = desiredLayoutId
        } catch {
            os_log("Failed to parse layout: %{public}@", log: log, type: .error, String(describing: error))
        }
    }
}
