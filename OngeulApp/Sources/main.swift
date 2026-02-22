import Cocoa
import InputMethodKit

let connectionName = Bundle.main.infoDictionary!["InputMethodConnectionName"] as! String
let bundleIdentifier = Bundle.main.bundleIdentifier!

let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)

NSApplication.shared.run()
