import AppKit

// A custom NSWindow subclass that can become the key window,
// which is necessary for borderless windows to receive keyboard events.
class KeyWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}
