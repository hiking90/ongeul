import Cocoa
import os

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private static let log = OSLog(
        subsystem: "io.github.hiking90.inputmethod.Ongeul",
        category: "UpdateChecker"
    )

    /// 자동 확인 최소 간격 (24시간)
    private static let minimumCheckInterval: TimeInterval = 24 * 60 * 60

    private static let releaseURL = URL(
        string: "https://api.github.com/repos/hiking90/ongeul/releases/latest"
    )!

    private var isChecking = false
    private var lastCheckDate: Date?

    /// 현재 앱 버전 (CFBundleShortVersionString)
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // MARK: - Public API

    /// 업데이트 확인
    /// - Parameter silent: true면 업데이트가 없을 때 UI를 표시하지 않음 (자동 확인용)
    func checkForUpdate(silent: Bool) {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { self.isChecking = false }

            do {
                let json = try await fetchReleaseJSON()

                self.lastCheckDate = Date()

                // JSON 파싱 + 버전 비교는 Rust에 위임
                guard let info = parseReleaseResponse(
                    json: json,
                    currentVersion: currentVersion
                ) else {
                    // 파싱 실패
                    os_log("Failed to parse release response",
                           log: Self.log, type: .error)
                    if !silent { showError() }
                    return
                }

                if info.isUpdateAvailable {
                    os_log("Update available: %{public}@ → %{public}@",
                           log: Self.log, type: .default,
                           self.currentVersion, info.latestVersion)
                    showUpdateAvailable(
                        current: currentVersion,
                        latest: info.latestVersion,
                        downloadURL: URL(string: info.downloadUrl)
                    )
                } else {
                    os_log("Up to date: %{public}@",
                           log: Self.log, type: .info, self.currentVersion)
                    if !silent { showUpToDate() }
                }
            } catch {
                os_log("Update check failed: %{public}@",
                       log: Self.log, type: .error, error.localizedDescription)
                if !silent { showError() }
            }
        }
    }

    /// 자동 확인: 최소 간격이 지났을 때만 실행
    func checkIfNeeded() {
        if let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < Self.minimumCheckInterval {
            os_log("Skipping auto-check: last check was %{public}.0f seconds ago",
                   log: Self.log, type: .debug,
                   Date().timeIntervalSince(lastCheck))
            return
        }
        checkForUpdate(silent: true)
    }

    // MARK: - Network (macOS native stack)

    private func fetchReleaseJSON() async throws -> String {
        var request = URLRequest(url: Self.releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return json
    }

    // MARK: - UI

    private func showUpdateAvailable(current: String, latest: String, downloadURL: URL?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.available.title", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("update.available.message", comment: ""),
            current, latest
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("update.download", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.later", comment: ""))

        let response = showAlertAboveAll(alert)

        if response == .alertFirstButtonReturn, let url = downloadURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.upToDate.title", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("update.upToDate.message", comment: ""),
            currentVersion
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("update.ok", comment: ""))
        showAlertAboveAll(alert)
    }

    private func showError() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update.error.title", comment: "")
        alert.informativeText = NSLocalizedString("update.error.message", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("update.ok", comment: ""))
        showAlertAboveAll(alert)
    }

    /// IME 프로세스에서 NSAlert를 최상위에 표시하는 헬퍼.
    /// InputMethod 프로세스는 일반 앱과 달리 NSApplication.mainWindow가 없으므로,
    /// 임시 키 윈도우를 생성하여 alert의 부모로 사용한다.
    @discardableResult
    private func showAlertAboveAll(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        let response = alert.runModal()

        window.orderOut(nil)
        return response
    }
}
