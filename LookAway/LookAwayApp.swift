import Carbon
import Combine
import SwiftUI

@main
struct LookAwayApp: App {
  /// Manages the application lifecycle and provides the main window management.
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // To provide a popover like window see
    // https://developer.apple.com/documentation/swiftui/menubarextra
    MenuBarExtra {
      AppMenu()
        .environmentObject(appDelegate.appState)
    } label: {
      MenuBarButton(appState: appDelegate.appState)
    }
  }
}

/// The button/icon for our app in the system menu.
struct MenuBarButton: View {
  @ObservedObject var appState: AppState

  var body: some View {
    Text(TimeFormatter.format(duration: appState.remainingTime))
    Image(systemName: "eye")
  }
}

/// The system menu bar dropdown shown when the user clicks our app icon in the menu bar.
struct AppMenu: View {
  @EnvironmentObject var appState: AppState

  var body: some View {
    Button(appState.isPaused ? "Resume" : "Pause") {
      appState.togglePaused()
    }
    Button("Take a Break") {
      appState.startBreak()
    }
    Divider()
    Button("Quit LookAway") {
      NSApplication.shared.terminate(nil)
    }.keyboardShortcut("q")
  }
}

/// The AppDelegate class manages the application lifecycle and provides the main window management.
/// The AppDelegate is required because SwiftUI does not provide an easy way to create system menu bar applications at this time.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  /**
   * The AppState object that holds the state of the application.
   */
  var appState = AppState()

  /// The list of windows that block user interaction with the system when in the blocking state.
  var blockerWindows: [NSWindow] = []
  /// The cancellables used to manage Combine subscriptions. When this gets deallocated, all subscriptions are cancelled.
  private var cancellables = Set<AnyCancellable>()
  /// The event monitor used to listen for global key events.
  //  private var eventMonitor: Any?

  /// The default presentation options given to the application when it starts. These are used to restore the application to its original state when the blocking windows are closed since the blocking state will change the presentation options to disable system features like app switching and Mission Control.
  private var defaultPresentationOptions: NSApplication.PresentationOptions = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Store the default presentation options so we can restore them later.
    self.defaultPresentationOptions = NSApplication.shared.presentationOptions

    // Subscribe to changes in AppState.isShowingPreview and react accordingly.
    appState.$isBlocking
      .removeDuplicates()
      .sink { [weak self] isShowing in
        if isShowing {
          self?.openScreenBlockers()
        } else {
          self?.closeScreenBlockers()
        }
      }
      .store(in: &cancellables)

    /* Will require Accessibility permissions.
       Don't forget to comment in the `applicationWillTerminate` code.
    // Listen to system wide key events so users can manipulate the app even when it does not have focus.
    eventMonitor =
      NSEvent
      .addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        if event.modifierFlags.contains(.option) &&
            event.modifierFlags.contains(.command) &&
            event.modifierFlags.contains(.control) &&
            event.modifierFlags.contains(.shift) &&
            event.keyCode == kVK_Space {
          print("--- Option + Command + X pressed ---")
          self?.appState.togglePaused()
        }
      }
     */
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Cancel the timer task when the application is about to terminate.
    appState.cancelTimer()

    // Remove the global event monitor.
//    if let eventMonitor = eventMonitor {
//      NSEvent.removeMonitor(eventMonitor)
//    }
  }

  /**
   * Shows the window blockers that cover the user's screen.
   */
  func openScreenBlockers() {
    // Set presentation options to disable system features like app switching and Mission Control.
    let restrictiveOptions: NSApplication.PresentationOptions = [
      .hideDock,
      .hideMenuBar,
      .disableAppleMenu,
      .disableProcessSwitching,
      .disableHideApplication,
    ]
    NSApplication.shared.presentationOptions = restrictiveOptions

    // Create a window blocker for each screen.
    if blockerWindows.isEmpty {
      for screen in NSScreen.screens {
        // The ContentView will get the AppState from the environment.
        let contentView = ContentView()
          .environmentObject(appState)

        let window = BlockingWindow(
          screen: screen,
          contentView: NSHostingView(rootView: contentView),
          appState: self.appState,
          //          debug: true
        )
        blockerWindows.append(window)
      }
    }

    // Show all the windows.
    for window in blockerWindows {
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  /**
   * Closes all window blockers, allowing the user access to their computer again.
   */
  func closeScreenBlockers() {
    // Restore the default presentation options.
    NSApplication.shared.presentationOptions = defaultPresentationOptions

    for window in blockerWindows {
      window.close()
    }
    blockerWindows.removeAll()
    appState.logger.timeEnd("close-windows")
  }
}
