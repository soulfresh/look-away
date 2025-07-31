import SwiftUI

/// A custom `NSWindow` subclass used to block user interactions with other applications.
class KeyWindow: NSWindow {
  var appState: AppState?

  /// - Parameter screen: The screen on which the window will be displayed.
  /// - Parameter contentView: The SwiftUI view that will be displayed in the window.
  /// - Parameter appState: The shared application state that will be observed.
  /// - Parameter debug: If `true`, the window won't cover the screen so we don't get locked out of the system.
  init(
    screen: NSScreen,
    contentView: NSHostingView<some View>,
    appState: AppState,
    debug: Bool
  ) {
    self.appState = appState

    let styleMask: NSWindow.StyleMask = debug ? [.closable, .titled] : [.borderless]
    let level: NSWindow.Level = debug ? .floating : .screenSaver

    super.init(
      contentRect: debug ? NSRect(x: 0, y: 0, width: 600, height: 600) : screen.frame,
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )

    self.level = level
    self.isReleasedWhenClosed = false
    self.contentView = contentView
  }

  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return true
  }

  override func keyDown(with event: NSEvent) {
    // If the Escape key was pressed, hide the preview windows.
    if event.keyCode == 53 {
      print("--- Escape key pressed ---")
      appState?.startWorking()
    } else {
      // Pass other key events to the superclass.
      super.keyDown(with: event)
    }
  }
}
