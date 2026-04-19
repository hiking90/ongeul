import Cocoa
import Carbon
import InputMethodKit

// CLI: --enable-input-sources
// 설치 스크립트(.pkg postinstall 및 install.sh)에서 호출하여 Ongeul 한/영 입력 소스를 활성화.
// 런타임 중 자동 등록은 하지 않으므로, 설치 시점에만 이 경로로 등록된다.
if CommandLine.arguments.contains("--enable-input-sources") {
    // 최초 설치 직후 TIS 데이터베이스가 아직 번들을 스캔하지 않았을 수 있다.
    // TISRegisterInputSource로 강제 등록하여 이후 TISCreateInputSourceList에서 찾게 한다.
    let registerErr = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    if registerErr != noErr {
        // paramErr(-50) 등은 이미 등록된 경우에도 발생할 수 있으므로 경고만.
        FileHandle.standardError.write(Data("Ongeul: TISRegisterInputSource warning: err=\(registerErr)\n".utf8))
    }

    let ids = [
        "io.github.hiking90.inputmethod.Ongeul",
        "io.github.hiking90.inputmethod.Ongeul.English",
    ]
    var exitCode: Int32 = 0
    for id in ids {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first
        else {
            FileHandle.standardError.write(Data("Ongeul: input source not found: \(id)\n".utf8))
            exitCode = 1
            continue
        }
        let err = TISEnableInputSource(source)
        if err != noErr {
            FileHandle.standardError.write(Data("Ongeul: TISEnableInputSource(\(id)) failed: err=\(err)\n".utf8))
            exitCode = Int32(err)
        }
    }
    exit(exitCode)
}

let connectionName = Bundle.main.infoDictionary!["InputMethodConnectionName"] as! String
let bundleIdentifier = Bundle.main.bundleIdentifier!

let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)

NSApplication.shared.run()
