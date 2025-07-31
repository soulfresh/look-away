import SwiftUI

/// A custom `NSWindow` subclass used to block user interactions with other applications.
class BlockingWindow: NSWindow {
  var appState: AppState?

  /// - Parameter screen: The screen on which the window will be displayed.
  /// - Parameter contentView: The SwiftUI view that will be displayed in the window.
  /// - Parameter appState: The shared application state that will be observed.
  /// - Parameter debug: If `true`, the window won't cover the screen so we don't get locked out of the system.
  init(
    screen: NSScreen,
    contentView: NSHostingView<some View>,
    appState: AppState,
    debug: Bool = false
  ) {
    self.appState = appState

    let styleMask: NSWindow.StyleMask = debug ? [.closable, .titled] : [.borderless]
    let level: NSWindow.Level = debug ? .floating : .screenSaver
    let w = 600.0

//    print(
//      "\(screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] ?? "Unknown screen") - \(screen.frame)"
//    )
//    print("Creating screen at \(screen.frame.minX + (screen.frame.width - w)/2) x \(screen.frame.minY + (screen.frame.height - w)/2)")
    super.init(
      contentRect: debug ? NSRect(
        x: screen.frame.minX + (screen.frame.width - w)/2,
        y: screen.frame.minY + (screen.frame.height - w)/2,
        width: w,
        height: w
      ) : screen.frame,
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
      appState?.performance.time("close-windows")
      appState?.startWorking()
    } else {
      // Pass other key events to the superclass.
      super.keyDown(with: event)
    }
  }
}
