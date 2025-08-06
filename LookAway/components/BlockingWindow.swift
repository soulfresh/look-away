import Carbon
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

    let w = 600.0

    //    print(
    //      "\(screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] ?? "Unknown screen") - \(screen.frame)"
    //    )
    //    print("Creating screen at \(screen.frame.minX + (screen.frame.width - w)/2) x \(screen.frame.minY + (screen.frame.height - w)/2)")

    super.init(
      contentRect: debug
        ? NSRect(
          x: screen.frame.minX + (screen.frame.width - w) / 2,
          y: screen.frame.minY + (screen.frame.height - w) / 2,
          width: w,
          height: w
        ) : screen.frame,
      styleMask: debug ? [.closable, .titled] : [.borderless],
      backing: .buffered,
      defer: false
    )

    // Make sure we cover every desktop
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    // Make sure we cover the entire screen
    self.level = debug ? .floating : .screenSaver
    self.isReleasedWhenClosed = false
    // Assign the window contents
    self.contentView = contentView
  }

  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return true
  }

  enum KeyCodes: String {
    case escape = "\u{1B}"
  }

  override func keyDown(with event: NSEvent) {
    let key = event.charactersIgnoringModifiers?.lowercased()
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    //    print("Escape: \(kVK_Escape)")
    //    print("Key: \(key)")
    //    print("Matches? \(key == KeyCodes.escape.rawValue)")
    let delay = { (duration: TimeInterval) in
      self.appState?.logger.time("close-windows")
      // TODO This will advance to the next break in our schedule but we really want to rewind to the working phase of the current break in our schedule.
      self.appState?.delay(duration)
    }
    let skip = { () in
      self.appState?.logger.time("close-windows")
      self.appState?.skip()
    }

    switch (key, flags) {
    case (" ", []):
      delay(30)
    case ("1", []):
      delay(60)
    case ("2", []):
      delay(60 * 2)
    case ("3", []):
      delay(60 * 3)
    case ("4", []):
      delay(60 * 4)
    case ("5", []):
      delay(60 * 5)
    case ("6", []):
      delay(60 * 6)
    case ("7", []):
      delay(60 * 7)
    case ("8", []):
      delay(60 * 8)
    case ("9", []):
      delay(60 * 9)
    case ("0", []):
      delay(60 * 10)
    case (KeyCodes.escape.rawValue, []):
      skip()
    default:
      // Pass other key events to the superclass.
      super.keyDown(with: event)
    }
  }
}
