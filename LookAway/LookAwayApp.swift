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
    Button("Settings") {
      appState.showSettings = true
    }
    Divider()
    Button("Quit LookAway") {
      NSApplication.shared.terminate(nil)
    }
  }
}

/// The AppDelegate class manages the application lifecycle and provides the main window management.
/// The AppDelegate is required because SwiftUI does not provide an easy way to create system menu bar applications at this time.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  /**
   * The AppState object that holds the state of the application.
   */
  let appState: AppState

  let logger: Logging
  var settingsWindow: NSWindow?
  /// The list of windows that block user interaction with the system when in the blocking state.
  var blockerWindows: [NSWindow] = []
  /// The cancellables used to manage Combine subscriptions. When this gets deallocated, all subscriptions are cancelled.
  private var cancellables = Set<AnyCancellable>()
  /// The event monitor used to listen for global key events.
  //  private var eventMonitor: Any?

  /// The default presentation options given to the application when it starts. These are used to restore the application to its original state when the blocking windows are closed since the blocking state will change the presentation options to disable system features like app switching and Mission Control.
  private var defaultPresentationOptions: NSApplication.PresentationOptions = []

  override init() {
    let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    let logger = Logger(enabled: !isTesting)
    self.logger = LogWrapper(logger: logger, label: "LookAwayApp".red())
    self.logger.log("initialized")

    self.appState = AppState(
      schedule: [
        WorkCycle(
          frequency: 10,
          duration: 5,
          logger: LogWrapper(logger: logger, label: "WorkCycle 1".blue()),
        ),
        WorkCycle(
          frequency: 5,
          duration: 3,
          logger: LogWrapper(logger: logger, label: "WorkCycle 2".green()),
        ),
      ],
      logger: LogWrapper(logger: logger, label: "AppState".magenta())
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Store the default presentation options so we can restore them later.
    self.defaultPresentationOptions = NSApplication.shared.presentationOptions

    // Toggle the blocking windows on AppState.isBlocking changes.
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

    // Toggle the settings window on AppState.showSettings changes.
    appState.$showSettings
      .removeDuplicates()
      .sink { [weak self] isShowing in
        if isShowing {
          self?.openSettingsWindow()
        } else {
          self?.settingsWindow?.close()
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

  func openSettingsWindow() {
    logger.log("Opening settings window")
    if settingsWindow == nil {
      settingsWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [.closable, .titled, .resizable],
        backing: .buffered,
        defer: false
      )

      guard let win = settingsWindow else {
        logger.error("Failed to create settings window")
        return
      }

      win.contentView = NSHostingView(rootView: LookAwaySettings())
      win.title = "LookAway Settings"
      win.center()
      win.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
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
        let contentView = LookAwayContent()
          .environmentObject(appState)

        let window = BlockingWindow(
          screen: screen,
          contentView: NSHostingView(rootView: contentView),
          appState: self.appState,
          // Prevent the blocking windows from actually blocking the
          // screen so you don't end up locked out of your computer.
          // debug: true
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
    logger.timeEnd("close-windows")
  }
}
