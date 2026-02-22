import Cocoa
import InputMethodKit

@objc(OngeulInputController)
class OngeulInputController: IMKInputController {

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? (any IMKTextInput) else {
            return false
        }

        // TODO: Rust 엔진 연동
        // let result = engine.processKey(keycode: UInt32(event.keyCode), modifiers: ...)

        return false
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
    }
}
