import Cocoa
import InputMethodKit
import Carbon
import os.log

private let log = OSLog(subsystem: "io.github.hiking90.inputmethod.Ongeul", category: "input")

// MARK: - Input Mode IDs
private enum InputModeID {
    static let korean  = "io.github.hiking90.inputmethod.Ongeul"
    static let english = "io.github.hiking90.inputmethod.Ongeul.English"

    static func from(_ mode: InputMode) -> String {
        mode == .korean ? korean : english
    }

    static func toMode(_ id: String) -> InputMode? {
        if id == korean { return .korean }
        if id == english { return .english }
        return nil
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
        let timer = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
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
    private let inputSourceLockCheckbox: NSButton
    private let toggleKeyTitles: [(ToggleKey, String)]

    private init() {
        toggleKeyTitles = [
            (.rightCommand, NSLocalizedString("prefs.toggleKey.rightCommand", comment: "")),
            (.rightOption,  NSLocalizedString("prefs.toggleKey.rightOption", comment: "")),
            (.leftShift,    NSLocalizedString("prefs.toggleKey.leftShift", comment: "")),
            (.rightShift,   NSLocalizedString("prefs.toggleKey.rightShift", comment: "")),
            (.shiftSpace,   NSLocalizedString("prefs.toggleKey.shiftSpace", comment: "")),
            (.capsLock,     NSLocalizedString("prefs.toggleKey.capsLock", comment: "")),
        ]

        panel = NSPanel(
            contentRect: .zero,
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
        // CapsLock 메뉴 항목에 tooltip 설정
        if let capsLockIndex = toggleKeyTitles.firstIndex(where: { $0.0 == .capsLock }),
           let menuItem = togglePopup.item(at: capsLockIndex) {
            menuItem.toolTip = NSLocalizedString("prefs.capsLockDelay", comment: "")
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
        settingsGrid.rowSpacing = 12
        settingsGrid.columnSpacing = 8
        settingsGrid.column(at: 0).xPlacement = .trailing
        settingsGrid.column(at: 1).xPlacement = .leading
        settingsGrid.setContentHuggingPriority(.required, for: .horizontal)
        settingsGrid.setContentHuggingPriority(.required, for: .vertical)

        // -- ESC → 영문 전환 --
        escapeCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("prefs.escapeToEnglish", comment: ""),
            target: nil, action: nil
        )

        // -- 입력기 고정 --
        inputSourceLockCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("prefs.inputSourceLock", comment: ""),
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
        let checkboxGroup = NSStackView(views: [escapeCheckbox, inputSourceLockCheckbox])
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

        // 콘텐츠에 맞게 패널 크기 자동 조절
        // 세로 NSStackView: fittingSize.height에는 상하 edgeInsets 포함, 좌우는 미포함
        container.layoutSubtreeIfNeeded()
        let fitting = container.fittingSize
        let insets = container.edgeInsets
        panel.setContentSize(NSSize(
            width: fitting.width + insets.left + insets.right,
            height: fitting.height
        ))

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
        inputSourceLockCheckbox.state = OngeulInputController.inputSourceLock ? .on : .off

        panel.center()
        panel.orderFrontRegardless()
    }

    @objc private func okClicked(_ sender: Any?) {
        let previousToggleKey = OngeulInputController.toggleKey
        let newToggleKey = toggleKeyTitles[togglePopup.indexOfSelectedItem].0
        OngeulInputController.toggleKey = newToggleKey

        // CapsLock 전환 키 변경 시 LED OFF 강제
        if previousToggleKey == .capsLock || newToggleKey == .capsLock {
            CapsLockSync.forceOff()
        }

        let newLayout: String
        switch layoutPopup.indexOfSelectedItem {
        case 1: newLayout = "3-390"
        case 2: newLayout = "3-final"
        default: newLayout = "2-standard"
        }
        OngeulInputController.savedLayoutId = newLayout
        OngeulInputController.escapeToEnglish = escapeCheckbox.state == .on
        OngeulInputController.inputSourceLock = inputSourceLockCheckbox.state == .on

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
    #if DEBUG
    static var coordinator: InputStateCoordinator = .init()
    #else
    static let coordinator = InputStateCoordinator()
    #endif
    private var coordinator: InputStateCoordinator { Self.coordinator }

    private var loadedLayoutId: String?
    private var toggleDetector = ToggleDetector()

    /// 합성 이벤트 마커 (CGEvent userData)
    private enum SyntheticEvent: Int64 {
        case enter = 0x4F6E_0001         // 기존 syntheticEnterMarker(0x4F6E6765)에서 변경
        case autoSwitch = 0x4F6E_0002    // Phase 3에서 사용

        static func from(_ event: NSEvent) -> SyntheticEvent? {
            guard let cgEvent = event.cgEvent else { return nil }
            return SyntheticEvent(rawValue: cgEvent.getIntegerValueField(.eventSourceUserData))
        }
    }

    // 현재 조합 중인 텍스트 (composedString 콜백용)
    private var currentComposingText: String?

    // Focus-steal correction
    private var focusStealWorkItem: DispatchWorkItem?
    private var focusStealReplayWorkItem: DispatchWorkItem?
    private var focusStealBuffering = false
    private var focusStealExpectingBackspace = 0  // 남은 backspace 수
    private var focusStealReplayPending = false   // async 리플레이 대기 중
    private var focusStealKeyBuffer: [String] = []

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
    private static let inputSourceLockKey = "inputSourceLock"

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

    fileprivate static var inputSourceLock: Bool {
        get {
            if UserDefaults.standard.object(forKey: inputSourceLockKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: inputSourceLockKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: inputSourceLockKey)
            if newValue {
                InputSourceLock.shared.start()
            } else {
                InputSourceLock.shared.stop()
            }
        }
    }

    private static var hasPromptedAccessibility = false
    private static var hasStartedInputSourceLock = false

    /// 현재 macOS TIS가 가리키는 Ongeul 모드를 반환. TIS가 Ongeul이 아니거나 조회 실패 시 nil.
    /// activateApp이 "사용자가 메뉴바에서 직접 전환"을 감지하는 힌트로 사용한다.
    private static func currentSystemInputMode() -> InputMode? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        let id = unsafeBitCast(
            TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
            to: CFString.self
        ) as String
        return InputModeID.toMode(id)
    }

    private var currentBundleId: String?

    /// currentBundleId의 English Lock 상태 캐시.
    /// KeyEventTap 콜백에서 매 키 이벤트마다 isCurrentAppLocked()가 호출되어
    /// UserDefaults dictionary lookup이 누적되는 것을 방지한다.
    /// activateApp 결과 적용 후, 그리고 toggleLock 후 갱신한다.
    private var cachedLockedForCurrentApp: Bool = false

    private func refreshLockCache() {
        cachedLockedForCurrentApp = currentBundleId.map { coordinator.isLocked($0) } ?? false
    }

    // MARK: - Lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        KeyEventTap.activeController = self

        // 이전 focus-steal 세션 초기화 (deactivateServer 없이 재호출되는 경우 대비)
        focusStealWorkItem?.cancel()
        focusStealWorkItem = nil
        focusStealReplayWorkItem?.cancel()
        focusStealReplayWorkItem = nil
        focusStealBuffering = false
        focusStealExpectingBackspace = 0
        focusStealReplayPending = false
        focusStealKeyBuffer = []

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

        if !Self.hasStartedInputSourceLock {
            Self.hasStartedInputSourceLock = true
            if Self.inputSourceLock {
                InputSourceLock.shared.start()
            }
        }

        // 놓친 notification 보조 확인 — Ongeul이 아닌 keyboard layout이면 복귀
        if Self.inputSourceLock {
            InputSourceLock.shared.verifyAndRecover(source: "activateServer")
        }

        loadLayoutIfNeeded()

        // 업데이트 확인 (guard 앞에 배치하여 early return에 영향받지 않도록)
        Task { @MainActor in
            UpdateChecker.shared.checkIfNeeded()
        }

        guard let bundleId = (sender as? (any IMKTextInput))?.bundleIdentifier() else { return }
        currentBundleId = bundleId

        // Pre-cache Chromium detection so deactivateServer always hits the cache.
        if Self.chromiumAppCache[bundleId] == nil {
            Self.chromiumAppCache[bundleId] = Self.isChromiumBased(bundleId: bundleId)
        }

        let effect = coordinator.activateApp(
            bundleId: bundleId,
            systemMode: Self.currentSystemInputMode()
        )
        refreshLockCache()
        if let client = sender as? (any IMKTextInput) {
            applyEffect(effect, to: client)
        }

        // 아이콘 동기화 — applyEffect의 modeChanged와 무관하게 항상 수행
        if let client = sender as? (any IMKTextInput) {
            let modeId = InputModeID.from(coordinator.mode)
            client.selectMode(modeId)
        }

        // CapsLock이 toggle key일 때 방어적 LED OFF
        // (다른 앱에서 CapsLock이 켜진 상태로 전환된 경우 대비)
        if Self.toggleKey == .capsLock && KeyEventTap.shared.isInstalled {
            CapsLockSync.forceOff()
        }

        // Focus-steal correction: 키 입력 시점에 한글 모드였고, English Lock이 아닌 경우만
        // handleKeyDown/deactivateServer에서 keyBuffer를 지우지 않으므로,
        // 정상 타이핑 중 누적된 오래된 키를 제거하여 false positive를 방지한다.
        let now = CFAbsoluteTimeGetCurrent()
        KeyEventTap.keyBuffer.removeAll { now - $0.timestamp > 0.2 }

        if KeyEventTap.keyBufferWasKoreanMode, !KeyEventTap.keyBuffer.isEmpty,
           !coordinator.isLocked(bundleId) {
            correctFocusSteal()
        } else {
            KeyEventTap.keyBuffer = []
        }
    }

    override func composedString(_ sender: Any!) -> Any! {
        return (currentComposingText ?? "") as NSString
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? (any IMKTextInput) else { return }
        let result = coordinator.flush()
        applyResult(result, to: client)
    }

    override func deactivateServer(_ sender: Any!) {
        focusStealWorkItem?.cancel()
        focusStealWorkItem = nil
        focusStealReplayWorkItem?.cancel()
        focusStealReplayWorkItem = nil
        focusStealBuffering = false
        focusStealExpectingBackspace = 0
        focusStealReplayPending = false
        focusStealKeyBuffer = []

        // keyBuffer는 activateServer에서만 정리 (focus-steal 증거 보존)

        if KeyEventTap.activeController === self {
            KeyEventTap.activeController = nil
        }
        let flushResult = coordinator.deactivate(for: currentBundleId)
        if let client = sender as? (any IMKTextInput) {
            if flushResult.committed != nil && !clientAutoCommitsMarkedText {
                applyResult(flushResult, to: client)
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

        let updateItem = NSMenuItem(
            title: NSLocalizedString("menu.checkForUpdate", comment: ""),
            action: #selector(checkForUpdate(_:)),
            keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let helpItem = NSMenuItem(
            title: NSLocalizedString("menu.help", comment: ""),
            action: #selector(openHelp(_:)),
            keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        return menu
    }

    @objc private func checkForUpdate(_ sender: Any?) {
        Task { @MainActor in
            UpdateChecker.shared.checkForUpdate(silent: false)
        }
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

        // CapsLock 전환 (CGEventTap 미설치 폴백)
        if Self.toggleKey == .capsLock && event.keyCode == KeyCode.capsLock {
            // capsLockOn=true (press)만 처리. release/echo는 무시.
            guard event.modifierFlags.contains(.capsLock) else { return false }
            CapsLockSync.forceOff()  // LED OFF 유지 (locked 상태와 무관)
            guard !isCurrentAppLocked() else { return false }
            guard let effect = coordinator.toggleMode(for: currentBundleId)
            else { return false }
            applyEffect(effect, to: client)
            return false  // flagsChanged는 소비하지 않음
        }

        let action = toggleDetector.handleFlagsChanged(
            keyCode: event.keyCode,
            flags: event.modifierFlags,
            toggleKey: Self.toggleKey
        )
        switch action {
        case .none:
            return false
        case .toggle:
            guard let effect = coordinator.toggleMode(for: currentBundleId)
            else { return false }
            applyEffect(effect, to: client)
            return true
        case .englishLockToggle:
            guard let bundleId = currentBundleId else { return false }
            let effect = coordinator.toggleLock(for: bundleId)
            refreshLockCache()
            applyEffect(effect, to: client)
            return true
        }
    }

    // MARK: - Private: Toggle / Lock / Vim Escape (KeyEventTap entry points)

    func performToggleFromTap() {
        guard let client: any IMKTextInput = self.client(),
              let effect = coordinator.toggleMode(for: currentBundleId)
        else { return }
        applyEffect(effect, to: client)
    }

    func performVimEscapeFromTap() {
        guard let client: any IMKTextInput = self.client() else { return }
        applyResult(coordinator.flush(), to: client)
        if let effect = coordinator.escapeToEnglish(
            for: currentBundleId, enabled: Self.escapeToEnglish
        ) {
            applyEffect(effect, to: client)
        }
    }

    func performEnglishLockToggleFromTap() {
        guard let client: any IMKTextInput = self.client(),
              let bundleId = currentBundleId
        else { return }
        let effect = coordinator.toggleLock(for: bundleId)
        refreshLockCache()
        applyEffect(effect, to: client)

        // Lock 토글은 modeChanged=false이므로 아이콘 별도 동기화
        let modeId = InputModeID.from(coordinator.mode)
        client.selectMode(modeId)
    }

    /// KeyEventTap에서 호출: 현재 앱이 English Lock 상태인지 반환.
    /// 매 키 이벤트마다 호출되므로 캐시된 값을 반환한다.
    /// 캐시 갱신: activateServer/toggleLock 직후.
    func isCurrentAppLocked() -> Bool {
        cachedLockedForCurrentApp
    }

    // MARK: - Input Mode Management

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        // kTSMDocumentInputModePropertyTag = 'imim' = 0x696D696D
        guard tag == 0x696D696D,
              let modeId = value as? String
        else {
            super.setValue(value, forTag: tag, client: sender)
            return
        }

        let targetMode: InputMode = (modeId == InputModeID.english) ? .english : .korean

        // re-entrancy 방지: 이미 동일 모드면 무시
        guard coordinator.mode != targetMode else { return }

        // English Lock 상태면 외부 변경 거부 → 강제로 English 아이콘 복원
        // 사용자에게 잠금 상태임을 시각적으로 알림 (왜 안 바뀌는지 명확히)
        if let bundleId = currentBundleId, coordinator.isLocked(bundleId) {
            (sender as? (any IMKTextInput))?.selectMode(InputModeID.english)
            LockOverlay.shared.show(locked: true)
            return
        }

        // 내부 상태 동기화 + 조합 중 문자 flush
        if let result = coordinator.setModeFromExternal(targetMode, for: currentBundleId),
           let client = sender as? (any IMKTextInput) {
            applyResult(result, to: client)
        }
    }

    // MARK: - Private: Focus-Steal Correction

    /// 포커스 탈취 교정:
    /// 입력창이 없는 상태에서 앱이 키를 가로채 영문을 삽입한 경우를 교정한다.
    /// 1. activateServer에서 버퍼 키 감지 → 10ms 타이머 시작, 키 버퍼링 모드 진입
    /// 2. 10ms 동안 handleKeyDown의 키를 focusStealKeyBuffer에 저장 (엔진 처리 안 함)
    /// 3. 10ms 후 synthetic backspace 전송 → 시스템이 영문자 삭제
    /// 4. handleKeyDown에서 backspace 수신 → 버퍼 키를 엔진에 전달하여 한글 조합
    private func correctFocusSteal() {
        // 이전 focus-steal 세션의 잔여 상태 초기화 (재진입 방지)
        focusStealWorkItem?.cancel()
        focusStealWorkItem = nil
        focusStealBuffering = false
        focusStealExpectingBackspace = 0
        focusStealReplayPending = false
        focusStealKeyBuffer = []

        let buffer = KeyEventTap.keyBuffer
        KeyEventTap.keyBuffer = []

        guard let firstKey = buffer.first else { return }

        let elapsed = CFAbsoluteTimeGetCurrent() - firstKey.timestamp
        guard elapsed < 0.5 else {
            os_log("focusSteal: skip — elapsed=%.3f > 0.5", log: log, type: .debug, elapsed)
            return
        }

        // 한글 모드 강제 (activateApp이 복원한 모드와 무관)
        if coordinator.mode != .korean {
            if let client = self.client() {
                let flushResult = coordinator.forceKoreanForReplay()
                applyResult(flushResult, to: client)
            } else {
                _ = coordinator.forceKoreanForReplay()
            }
        }

        // 아이콘 동기화 — 한글 모드로 강제 전환되었으므로
        if let client = self.client() {
            client.selectMode(InputModeID.korean)
        }

        focusStealBuffering = true
        focusStealKeyBuffer = buffer.map { $0.character }
        let preKeyCount = buffer.count

        os_log("focusSteal: buffering %d keys, elapsed=%.3f", log: log, type: .debug,
               preKeyCount, elapsed)

        // 10ms 후 backspace 전송
        // 대기 중 추가로 타이핑된 키를 keyBuffer에서 확인하여 backspace 수를 보정한다.
        // - handleKeyDown을 거친 키: focusStealKeyBuffer에 추가됨 (앱에 미삽입, return true)
        // - handleKeyDown을 거치지 않은 키: 앱에 직접 삽입됨 → 추가 backspace 필요
        focusStealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.focusStealWorkItem = nil
            self.focusStealBuffering = false

            // CGEventTap에 기록된 후발 키 확인
            let lateKeys = KeyEventTap.keyBuffer
            KeyEventTap.keyBuffer = []

            // handleKeyDown 버퍼링 가드에서 소비된 키 수
            let imeConsumed = self.focusStealKeyBuffer.count - preKeyCount
            // 앱에 직접 입력된 키 수 (IME를 거치지 않은 키)
            let appInserted = max(0, lateKeys.count - imeConsumed)

            if appInserted > 0 {
                // 앱에 입력된 키는 시간순으로 lateKeys 앞부분에 위치
                // (IME 활성화 전 → 앱 직접 입력, IME 활성화 후 → handleKeyDown 소비)
                let appKeys = lateKeys.prefix(appInserted).map { $0.character }
                self.focusStealKeyBuffer.insert(contentsOf: appKeys, at: preKeyCount)
            }

            let totalBackspaces = preKeyCount + appInserted
            self.focusStealExpectingBackspace = totalBackspaces

            os_log("focusSteal: sending %d backspaces (pre=%d late=%d)",
                   log: log, type: .debug, totalBackspaces, preKeyCount, appInserted)

            let src = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<totalBackspaces {
                if let down = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.backspace, keyDown: true) {
                    down.post(tap: .cghidEventTap)
                }
                if let up = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.backspace, keyDown: false) {
                    up.post(tap: .cghidEventTap)
                }
            }
        }
        focusStealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: workItem)
    }

    // MARK: - Private: Key Processing

    private func handleKeyDown(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        // Focus-steal synthetic backspace: 시스템에 위임하여 영문자 삭제 후
        // 마지막 backspace에서 버퍼의 모든 키를 엔진에 전달
        if event.keyCode == KeyCode.backspace, focusStealExpectingBackspace > 0 {
            focusStealExpectingBackspace -= 1
            if focusStealExpectingBackspace == 0 {
                // async 리플레이 예약. 버퍼 캡처를 async 시점까지 지연하여,
                // backspace 소비 후 ~ async 실행 전에 도착하는 키도 포함시킨다.
                // 예약 사이에 deactivateServer가 발생하면 work item을 cancel하여
                // 다른 앱의 client로 키가 흘러가는 것을 방지한다.
                focusStealReplayPending = true
                let targetBundleId = currentBundleId
                focusStealReplayWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.focusStealReplayWorkItem = nil
                    self.focusStealReplayPending = false
                    let keys = self.focusStealKeyBuffer
                    self.focusStealKeyBuffer = []
                    // 활성 앱이 바뀌었으면 리플레이 포기 (잘못된 client에 키가 가는 것 방지)
                    guard !keys.isEmpty,
                          self.currentBundleId == targetBundleId,
                          let client: any IMKTextInput = self.client()
                    else { return }
                    for key in keys {
                        let result = self.coordinator.processKey(key: key)
                        self.applyResult(result, to: client)
                    }
                }
                focusStealReplayWorkItem = workItem
                DispatchQueue.main.async(execute: workItem)
            }
            return false
        }

        // Focus-steal 버퍼링: 엔진 처리 없이 키만 저장
        // 세 가지 타이밍을 모두 커버한다:
        //   1. focusStealBuffering: 타이머 대기 중 (correctFocusSteal 후 10ms 이내)
        //   2. focusStealExpectingBackspace > 0: synthetic backspace 소비 대기 중
        //   3. focusStealReplayPending: backspace 모두 소비 후 async 리플레이 대기 중
        if focusStealBuffering || focusStealExpectingBackspace > 0 || focusStealReplayPending {
            if let keyLabel = keyLabelFromEvent(event) {
                focusStealKeyBuffer.append(keyLabel)
            }
            return true
        }

        // keyBuffer는 activateServer에서만 정리한다.
        // handleKeyDown/deactivateServer가 activateServer보다 먼저 실행되어
        // focus-steal 증거를 파괴하는 것을 방지.

        // 합성 이벤트 → 시스템에 통과 (routeKeyDown 진입 전, cancelOnKeyDown 전에 가드)
        if let synthetic = SyntheticEvent.from(event) {
            switch synthetic {
            case .enter, .autoSwitch: return false
            }
        }

        toggleDetector.cancelOnKeyDown()

        let action = routeKeyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            modifiers: event.modifierFlags,
            engineMode: coordinator.mode,
            toggleKey: Self.toggleKey
        )
        return executeAction(action, event: event, client: client)
    }

    private func executeAction(
        _ action: KeyDownAction,
        event: NSEvent,
        client: any IMKTextInput
    ) -> Bool {
        switch action {
        case .shiftSpaceToggle:
            guard let effect = coordinator.toggleMode(for: currentBundleId)
            else { return false }
            applyEffect(effect, to: client)
            return true

        case .passToSystem:
            return false

        case .flushAndPassToSystem:
            applyResult(coordinator.flush(), to: client)
            return false

        case .backspace:
            let result = coordinator.backspace()
            applyResult(result, to: client)
            return result.handled

        case .enter:
            let hadComposing = currentComposingText != nil
            let result = coordinator.flush()
            applyResult(result, to: client)
            if hadComposing, AXIsProcessTrusted() {
                postSyntheticKey(event: event, marker: .enter)
                return true
            }
            return false

        case .space:
            applyResult(coordinator.flush(), to: client)
            return false

        case .escape:
            applyResult(coordinator.flush(), to: client)
            if let effect = coordinator.escapeToEnglish(
                for: currentBundleId, enabled: Self.escapeToEnglish
            ) {
                applyEffect(effect, to: client)
            }
            return false

        case .processKey(let label):
            let result = coordinator.processKey(key: label)
            applyResult(result, to: client)
            return result.handled

        case .flushUnknownKey:
            applyResult(coordinator.flush(), to: client)
            return false
        }
    }

    /// 키를 합성하여 재전송 (Enter 합성 및 자동전환 후 boundary key 재전송 공용)
    private func postSyntheticKey(event: NSEvent, marker: SyntheticEvent) {
        let keyCode = event.keyCode
        let originalFlags = event.cgEvent?.flags ?? []
        DispatchQueue.main.async {
            let src = CGEventSource(stateID: .hidSystemState)
            for keyDown in [true, false] {
                if let ev = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) {
                    ev.flags = originalFlags
                    ev.setIntegerValueField(.eventSourceUserData, value: marker.rawValue)
                    ev.post(tap: .cghidEventTap)
                }
            }
        }
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

    private func applyEffect(_ effect: StateEffect, to client: any IMKTextInput) {
        if let result = effect.processResult {
            applyResult(result, to: client)
        }
        if effect.modeChanged {
            os_log("mode → %{public}@", log: log, type: .default,
                   coordinator.mode == .korean ? "korean" : "english")

            // 메뉴바 아이콘 동기화
            let modeId = InputModeID.from(coordinator.mode)
            client.selectMode(modeId)
        }
        switch effect.lockOverlay {
        case .show(let locked):
            os_log("lock overlay: %{public}@", log: log, type: .default,
                   locked ? "locked" : "unlocked")
            LockOverlay.shared.show(locked: locked)
        case .hide:
            LockOverlay.shared.hide()
        case nil:
            break
        }
    }

    // MARK: - Private: Layout Loading

    private func loadLayoutIfNeeded() {
        let desiredLayoutId = Self.savedLayoutId
        guard loadedLayoutId != desiredLayoutId else { return }

        let isInitialLoad = (loadedLayoutId == nil)

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
            if let flushResult = try coordinator.loadLayout(json: json, isInitialLoad: isInitialLoad),
               let client = self.client() {
                applyResult(flushResult, to: client)
            }
            loadedLayoutId = desiredLayoutId
        } catch {
            os_log("Failed to parse layout: %{public}@", log: log, type: .error, String(describing: error))
        }
    }
}
