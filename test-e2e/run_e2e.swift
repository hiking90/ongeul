#!/usr/bin/env swift
// test-e2e/run_e2e.swift
// CGEvent 기반 E2E 테스트 러너
//
// Ongeul IME의 전체 파이프라인을 실제 키 주입 + AXUIElement 결과 검증으로 테스트한다.
// Accessibility 권한(TCC) + GUI 세션이 필요하므로 Tart VM 또는 SIP 비활성화 환경에서 실행.
//
// 사용법:
//   swift test-e2e/run_e2e.swift
//
// 전제 조건:
//   - Ongeul이 설치되어 활성 입력 소스로 설정
//   - /usr/bin/swift에 Accessibility 권한 부여
//   - GUI 세션 (데스크톱 로그인 상태)

import Cocoa
import ApplicationServices
import Carbon

// MARK: - macOS Virtual Key Codes (US QWERTY)

let charToKeyCode: [Character: (keyCode: CGKeyCode, shift: Bool)] = [
    // Row 1: number row
    "`": (0x32, false), "~": (0x32, true),
    "1": (0x12, false), "!": (0x12, true),
    "2": (0x13, false), "@": (0x13, true),
    "3": (0x14, false), "#": (0x14, true),
    "4": (0x15, false), "$": (0x15, true),
    "5": (0x17, false), "%": (0x17, true),
    "6": (0x16, false), "^": (0x16, true),
    "7": (0x1A, false), "&": (0x1A, true),
    "8": (0x1C, false), "*": (0x1C, true),
    "9": (0x19, false), "(": (0x19, true),
    "0": (0x1D, false), ")": (0x1D, true),
    "-": (0x1B, false), "_": (0x1B, true),
    "=": (0x18, false), "+": (0x18, true),

    // Row 2: QWERTY
    "q": (0x0C, false), "Q": (0x0C, true),
    "w": (0x0D, false), "W": (0x0D, true),
    "e": (0x0E, false), "E": (0x0E, true),
    "r": (0x0F, false), "R": (0x0F, true),
    "t": (0x11, false), "T": (0x11, true),
    "y": (0x10, false), "Y": (0x10, true),
    "u": (0x20, false), "U": (0x20, true),
    "i": (0x22, false), "I": (0x22, true),
    "o": (0x1F, false), "O": (0x1F, true),
    "p": (0x23, false), "P": (0x23, true),
    "[": (0x21, false), "{": (0x21, true),
    "]": (0x1E, false), "}": (0x1E, true),
    "\\": (0x2A, false), "|": (0x2A, true),

    // Row 3: ASDF
    "a": (0x00, false), "A": (0x00, true),
    "s": (0x01, false), "S": (0x01, true),
    "d": (0x02, false), "D": (0x02, true),
    "f": (0x03, false), "F": (0x03, true),
    "g": (0x05, false), "G": (0x05, true),
    "h": (0x04, false), "H": (0x04, true),
    "j": (0x26, false), "J": (0x26, true),
    "k": (0x28, false), "K": (0x28, true),
    "l": (0x25, false), "L": (0x25, true),
    ";": (0x29, false), ":": (0x29, true),
    "'": (0x27, false), "\"": (0x27, true),

    // Row 4: ZXCV
    "z": (0x06, false), "Z": (0x06, true),
    "x": (0x07, false), "X": (0x07, true),
    "c": (0x08, false), "C": (0x08, true),
    "v": (0x09, false), "V": (0x09, true),
    "b": (0x0B, false), "B": (0x0B, true),
    "n": (0x2D, false), "N": (0x2D, true),
    "m": (0x2E, false), "M": (0x2E, true),
    ",": (0x2B, false), "<": (0x2B, true),
    ".": (0x2F, false), ">": (0x2F, true),
    "/": (0x2C, false), "?": (0x2C, true),

    // Special
    " ": (0x31, false),
]

let kKeyCodeEnter: CGKeyCode     = 36
let kKeyCodeSpace: CGKeyCode     = 49
let kKeyCodeBackspace: CGKeyCode = 51
let kKeyCodeEscape: CGKeyCode    = 53
let kKeyCodeRightCommand: CGKeyCode = 54

// MARK: - Key Injection

/// 단일 키 이벤트 주입 (keyDown + keyUp)
func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .combinedSessionState)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = flags
    keyDown?.post(tap: .cghidEventTap)

    usleep(10_000)  // 10ms 간격

    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = flags
    keyUp?.post(tap: .cghidEventTap)

    usleep(30_000)  // 30ms 대기 (IME 처리 시간)
}

/// 문자열의 각 문자를 키 이벤트로 변환하여 순차 입력
func typeKeys(_ keys: String) {
    for char in keys {
        guard let mapping = charToKeyCode[char] else {
            print("  WARNING: No keyCode mapping for '\(char)', skipping")
            continue
        }
        let flags: CGEventFlags = mapping.shift ? .maskShift : []
        simulateKeyPress(keyCode: mapping.keyCode, flags: flags)
    }
}

/// Enter 키 (한글 조합 확정 + 줄바꿈)
func pressEnter() {
    simulateKeyPress(keyCode: kKeyCodeEnter)
}

/// 백스페이스 N회
func pressBackspace(count: Int = 1) {
    for _ in 0..<count {
        simulateKeyPress(keyCode: kKeyCodeBackspace)
    }
}

/// ESC 키
func pressEscape() {
    simulateKeyPress(keyCode: kKeyCodeEscape)
}

/// Shift+Space (모드 전환 — KeyEventTap이 가로챔)
func pressShiftSpace() {
    simulateKeyPress(keyCode: kKeyCodeSpace, flags: .maskShift)
}

/// Right Command 탭 (modifier tap 모드 전환)
func tapRightCommand() {
    let source = CGEventSource(stateID: .combinedSessionState)

    // flagsChanged: Right Command down
    let flagDown = CGEvent(keyboardEventSource: source, virtualKey: kKeyCodeRightCommand, keyDown: true)
    flagDown?.flags = .maskCommand
    flagDown?.post(tap: .cghidEventTap)
    usleep(30_000)

    // flagsChanged: Right Command up (다른 키 없이 릴리스 → modifier tap)
    let flagUp = CGEvent(keyboardEventSource: source, virtualKey: kKeyCodeRightCommand, keyDown: false)
    flagUp?.flags = []
    flagUp?.post(tap: .cghidEventTap)
    usleep(100_000)  // modifier tap 인식 대기
}

/// Cmd+A (전체 선택)
func selectAll() {
    simulateKeyPress(keyCode: 0x00, flags: .maskCommand)  // Cmd+A
}

/// Delete (선택 삭제)
func deleteSelection() {
    simulateKeyPress(keyCode: kKeyCodeBackspace)
}

/// 텍스트 필드 내용 초기화 (Cmd+A → Delete)
func clearTextField() {
    selectAll()
    usleep(50_000)
    deleteSelection()
    usleep(100_000)
}

// MARK: - AXUIElement Result Verification

/// 지정된 앱의 포커스된 텍스트 필드 값 읽기
func getFocusedTextFieldValue(pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)

    var focusedElement: AnyObject?
    let focusResult = AXUIElementCopyAttributeValue(
        app, kAXFocusedUIElementAttribute as CFString, &focusedElement
    )
    guard focusResult == .success, let element = focusedElement else {
        return nil
    }

    var value: AnyObject?
    let valueResult = AXUIElementCopyAttributeValue(
        element as! AXUIElement, kAXValueAttribute as CFString, &value
    )
    guard valueResult == .success else { return nil }

    return value as? String
}

/// 예상 값이 될 때까지 폴링 대기
func waitForValue(pid: pid_t, expected: String, timeout: TimeInterval = 3.0) -> (success: Bool, actual: String?) {
    let start = CFAbsoluteTimeGetCurrent()
    var lastValue: String? = nil

    while CFAbsoluteTimeGetCurrent() - start < timeout {
        lastValue = getFocusedTextFieldValue(pid: pid)
        if let val = lastValue, val.contains(expected) {
            return (true, val)
        }
        usleep(100_000)  // 100ms 폴링 간격
    }
    return (false, lastValue)
}

/// 텍스트 필드 값이 정확히 일치하는지 확인 (줄바꿈 제거 후 비교)
func waitForExactValue(pid: pid_t, expected: String, timeout: TimeInterval = 3.0) -> (success: Bool, actual: String?) {
    let start = CFAbsoluteTimeGetCurrent()
    var lastValue: String? = nil

    while CFAbsoluteTimeGetCurrent() - start < timeout {
        lastValue = getFocusedTextFieldValue(pid: pid)
        if let val = lastValue {
            // TextEdit는 Enter 후 줄바꿈을 추가하므로 트리밍
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == expected {
                return (true, trimmed)
            }
        }
        usleep(100_000)
    }
    return (false, lastValue?.trimmingCharacters(in: .whitespacesAndNewlines))
}

// MARK: - Input Source Management

/// Ongeul 입력 소스 활성화
func activateOngeul() -> Bool {
    let properties = [kTISPropertyBundleID: "io.github.hiking90.inputmethod.Ongeul"] as CFDictionary
    guard let sources = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
          let ongeul = sources.first else {
        print("ERROR: Ongeul input source not found. Is it installed and enabled?")
        return false
    }

    let status = TISSelectInputSource(ongeul)
    if status != noErr {
        print("ERROR: TISSelectInputSource failed with status \(status)")
        return false
    }

    usleep(500_000)  // 입력 소스 전환 대기
    return true
}

/// 현재 활성 입력 소스 이름 반환
func currentInputSourceName() -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return "<unknown>"
    }
    if let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
        return Unmanaged<CFString>.fromOpaque(name).takeUnretainedValue() as String
    }
    return "<unknown>"
}

// MARK: - TextEdit Management

/// TextEdit 실행 및 새 문서 열기, PID 반환
func launchTextEdit() -> pid_t? {
    let workspace = NSWorkspace.shared
    let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true

    var resultPID: pid_t? = nil
    let semaphore = DispatchSemaphore(value: 0)

    workspace.openApplication(at: textEditURL, configuration: config) { app, error in
        if let app = app {
            resultPID = app.processIdentifier
        } else if let error = error {
            print("ERROR: Failed to launch TextEdit: \(error)")
        }
        semaphore.signal()
    }
    semaphore.wait()

    // TextEdit 초기화 대기
    sleep(2)

    // 새 문서 (Cmd+N) — 서식 없는 텍스트 모드 보장
    simulateKeyPress(keyCode: 0x2D, flags: .maskCommand)  // Cmd+N
    sleep(1)

    return resultPID
}

/// TextEdit 종료
func quitTextEdit(pid: pid_t) {
    let app = NSRunningApplication(processIdentifier: pid)
    // 저장하지 않고 닫기: Cmd+W → Cmd+Delete (Don't Save)
    simulateKeyPress(keyCode: 0x0D, flags: .maskCommand)  // Cmd+W
    usleep(500_000)
    // "Don't Save" 버튼 — Cmd+D 또는 Cmd+Delete
    simulateKeyPress(keyCode: 0x02, flags: .maskCommand)  // Cmd+D (Don't Save)
    usleep(300_000)
    app?.terminate()
}

// MARK: - Test Framework

var totalTests = 0
var passedTests = 0
var failedTests = 0
var failedNames: [String] = []

func runTest(_ name: String, pid: pid_t, _ body: (pid_t) -> Bool) {
    totalTests += 1
    print("  [\(totalTests)] \(name)...", terminator: " ")

    // 테스트 전 텍스트 필드 초기화
    clearTextField()
    usleep(200_000)

    let result = body(pid)
    if result {
        passedTests += 1
        print("PASS")
    } else {
        failedTests += 1
        failedNames.append(name)
        print("FAIL")
    }
}

// MARK: - Test Cases

func testHangulWord(pid: pid_t) -> Bool {
    // "한글" = g(ㅎ) + k(ㅏ) + s(ㄴ) + r(ㄱ) + m(ㅡ) + f(ㄹ) + Enter
    typeKeys("gksrmf")
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "한글")
    if !success { print("expected '한글', got '\(actual ?? "nil")'") }
    return success
}

func testDoubleJongseongSplit(pid: pid_t) -> Bool {
    // "갑시" = r(ㄱ) + k(ㅏ) + q(ㅂ) + t(ㅅ) + l(ㅣ) + Enter
    typeKeys("rkqtl")
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "갑시")
    if !success { print("expected '갑시', got '\(actual ?? "nil")'") }
    return success
}

func testDoubleVowel(pid: pid_t) -> Bool {
    // "과" = r(ㄱ) + h(ㅗ) + k(ㅏ) + Enter
    typeKeys("rhk")
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "과")
    if !success { print("expected '과', got '\(actual ?? "nil")'") }
    return success
}

func testModeToggleRightCommand(pid: pid_t) -> Bool {
    // 한글 모드에서 "가" 입력 → Right Command 탭 → 영문 "ab" 입력
    typeKeys("rk")           // "가" 조합
    tapRightCommand()        // 모드 전환 (한→영) — flush "가"
    usleep(200_000)
    typeKeys("ab")           // 영문 입력
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "가ab")
    if !success { print("expected '가ab', got '\(actual ?? "nil")'") }
    return success
}

func testBackspace(pid: pid_t) -> Bool {
    // g(ㅎ) + k(ㅏ) + s(ㄴ) = "한" → Backspace → "하" → Enter
    typeKeys("gks")
    usleep(100_000)
    pressBackspace()
    usleep(100_000)
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "하")
    if !success { print("expected '하', got '\(actual ?? "nil")'") }
    return success
}

func testShiftSpaceToggle(pid: pid_t) -> Bool {
    // 한글 모드 → Shift+Space → 영문 모드 → "ab" → Enter
    pressShiftSpace()        // 모드 전환 (한→영)
    usleep(300_000)
    typeKeys("ab")
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "ab")
    if !success { print("expected 'ab', got '\(actual ?? "nil")'") }

    // 영문→한글로 복원
    pressShiftSpace()
    usleep(300_000)

    return success
}

func testEscapeToEnglish(pid: pid_t) -> Bool {
    // 한글 모드에서 "가" 조합 → ESC → 영문 "ab" → Enter
    typeKeys("rk")           // "가" 조합
    pressEscape()            // ESC → flush "가" + 영문 전환
    usleep(200_000)
    typeKeys("ab")           // 영문 입력
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "가ab")
    if !success { print("expected '가ab', got '\(actual ?? "nil")'") }

    // 한글 모드 복원 (ESC→영문 설정이 켜져 있을 때)
    tapRightCommand()
    usleep(200_000)

    return success
}

func testContinuousSentence(pid: pid_t) -> Bool {
    // "나는" = s(ㄴ) + k(ㅏ) + s(ㄴ) + m(ㅡ) + s(ㄴ)
    // Space로 단어 구분
    // "한글" = g(ㅎ) + k(ㅏ) + s(ㄴ) + r(ㄱ) + m(ㅡ) + f(ㄹ)
    typeKeys("sksms")       // "나는" (ㄴㅏㄴㅡㄴ)
    simulateKeyPress(keyCode: kKeyCodeSpace)  // 공백 (flush + space)
    usleep(100_000)
    typeKeys("gksrmf")      // "한글"
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "나는 한글")
    if !success { print("expected '나는 한글', got '\(actual ?? "nil")'") }
    return success
}

func testEmptyBackspaceThenInput(pid: pid_t) -> Bool {
    // 빈 상태에서 백스페이스 5회 → "한" 입력 → Enter
    pressBackspace(count: 5)
    usleep(100_000)
    typeKeys("gks")         // "한"
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "한")
    if !success { print("expected '한', got '\(actual ?? "nil")'") }
    return success
}

func testDoubleConsonant(pid: pid_t) -> Bool {
    // 쌍자음 "빠" = Q(ㅃ) + k(ㅏ) + Enter
    typeKeys("Qk")
    pressEnter()
    usleep(200_000)

    let (success, actual) = waitForExactValue(pid: pid, expected: "빠")
    if !success { print("expected '빠', got '\(actual ?? "nil")'") }
    return success
}

// MARK: - Preflight Checks

func preflightChecks() -> Bool {
    var ok = true

    // 1. Accessibility 권한 확인
    if !AXIsProcessTrusted() {
        print("FATAL: Accessibility permission not granted for this process.")
        print("       Grant access to /usr/bin/swift in System Settings → Privacy → Accessibility")
        print("       Or run (SIP disabled):")
        print("         sudo sqlite3 \"/Library/Application Support/com.apple.TCC/TCC.db\" \\")
        print("           \"INSERT OR REPLACE INTO access VALUES('kTCCServiceAccessibility','/usr/bin/swift',1,2,3,1,NULL,NULL,NULL,'UNUSED',NULL,0,CAST(strftime('%s','now') AS INTEGER));\"")
        ok = false
    } else {
        print("  Accessibility: granted")
    }

    // 2. Ongeul 입력 소스 확인
    let properties = [kTISPropertyBundleID: "io.github.hiking90.inputmethod.Ongeul"] as CFDictionary
    if let sources = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
       !sources.isEmpty {
        print("  Ongeul input source: found")
    } else {
        print("FATAL: Ongeul input source not found.")
        print("       Install with: ./scripts/install.sh")
        print("       Then add in System Settings → Keyboard → Input Sources")
        ok = false
    }

    return ok
}

// MARK: - Main

print("=== Ongeul E2E Test Runner ===")
print("")
print("Preflight checks:")

guard preflightChecks() else {
    print("")
    print("Preflight checks failed. Aborting.")
    exit(1)
}
print("")

// Ongeul 활성화
print("Activating Ongeul input source...")
guard activateOngeul() else {
    exit(1)
}
print("  Active input source: \(currentInputSourceName())")
print("")

// TextEdit 실행
print("Launching TextEdit...")
guard let textEditPID = launchTextEdit() else {
    print("ERROR: Failed to launch TextEdit")
    exit(1)
}
print("  TextEdit PID: \(textEditPID)")
print("")

// 테스트 실행
print("Running E2E tests:")
print("")

runTest("한글 단어 '한글' 조합", pid: textEditPID, testHangulWord)
runTest("겹받침 분리 '갑시'", pid: textEditPID, testDoubleJongseongSplit)
runTest("겹모음 '과'", pid: textEditPID, testDoubleVowel)
runTest("쌍자음 '빠'", pid: textEditPID, testDoubleConsonant)
runTest("Right Command 탭 모드 전환", pid: textEditPID, testModeToggleRightCommand)
runTest("백스페이스 '한' → '하'", pid: textEditPID, testBackspace)
runTest("Shift+Space 모드 전환", pid: textEditPID, testShiftSpaceToggle)
runTest("ESC → 영문 전환", pid: textEditPID, testEscapeToEnglish)
runTest("연속 한글 문장 '나는 한글'", pid: textEditPID, testContinuousSentence)
runTest("빈 상태 백스페이스 후 입력", pid: textEditPID, testEmptyBackspaceThenInput)

// 정리
print("")
print("Cleaning up...")
quitTextEdit(pid: textEditPID)
sleep(1)

// 결과 요약
print("")
print("=== Results ===")
print("  Total:  \(totalTests)")
print("  Passed: \(passedTests)")
print("  Failed: \(failedTests)")
if !failedNames.isEmpty {
    print("")
    print("  Failed tests:")
    for name in failedNames {
        print("    - \(name)")
    }
}
print("")

exit(failedTests > 0 ? 1 : 0)
