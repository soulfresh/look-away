import SwiftUI

/// A custom `NSWindow` subclass used to block user interactions with other applications.
class KeyWindow: NSWindow {
  var appState: AppState?

  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return true
  }

  override func keyDown(with event: NSEvent) {
    // If the Escape key was pressed, hide the preview windows.
    if event.keyCode == 53 {
      appState?.isBlocking = false
    } else {
      // Pass other key events to the superclass.
      super.keyDown(with: event)
    }
  }
}
