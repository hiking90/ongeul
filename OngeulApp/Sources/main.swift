import Cocoa
import Carbon
import InputMethodKit

// CLI: --register-input-sources
// .pkg postinstall이 최초 설치 때 호출한다. 이 호출이 없으면 로그아웃 전까지 TIS 목록에 Ongeul이 없다.
// 등록만 하고 활성화는 하지 않는다. tsInputModeDefaultStateKey=false인 입력 모드에는
// TISEnableInputSource가 err=0만 반환하고 상태를 바꾸지 않는다 (macOS 15.7.7, 26.6.2에서 측정).
if CommandLine.arguments.contains("--register-input-sources") {
    let err = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    if err != noErr {
        FileHandle.standardError.write(Data("Ongeul: TISRegisterInputSource failed: err=\(err)\n".utf8))
    }
    exit(err == noErr ? 0 : 1)
}

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String else {
    fatalError("Info.plist missing required key 'InputMethodConnectionName'")
}
guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
    fatalError("Bundle has no identifier")
}

let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)

NSApplication.shared.run()
