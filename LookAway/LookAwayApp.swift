import AVFoundation
import Carbon
import Combine
import Darwin
import KeyboardShortcuts
import SwiftUI

struct Environment {
  static var isDebug: Bool {
    #if DEBUG
      return true
    #else
      return false
    #endif
  }

  static var isPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }

  static var isTesting: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }
}

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
        .environmentObject(appDelegate.appState.schedule)
    } label: {
      MenuBarIconButton(schedule: appDelegate.appState.schedule)
    }
  }
}

/// The system menu bar dropdown shown when the user clicks our app icon in the menu bar.
struct AppMenu: View {
  @EnvironmentObject var appState: AppState
  @EnvironmentObject var schedule: BreakSchedule<ContinuousClock>

  var body: some View {
    Button(schedule.isPaused ? "Resume" : "Pause") {
      schedule.togglePaused()
    }
    // TODO Get the shortcut from KeyboardShortcuts somehow
    .keyboardShortcut("p", modifiers: [.command, .option, .control])
    Button("Take a Break") {
      schedule.startBreak()
    }
    .keyboardShortcut("b", modifiers: [.command, .option, .control])
    Divider()
    Button("Settings") {
      appState.showSettings = true
    }
    Divider()
    Button("Quit") {
      NSApplication.shared.terminate(nil)
    }
    Divider()
    Text(
      "Next: \(TimeFormatter.format(duration: schedule.remainingTime))"
    )
  }
}

/// The AppDelegate class manages the application lifecycle and provides the main window management.
/// The AppDelegate is required because SwiftUI does not provide an easy way to create system menu bar applications at this time.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
  /**
   * The AppState object that holds the state of the application.
   */
  let appState: AppState
  let storage: Storage
  let logger: Logger
  var settingsWindow: NSWindow?
  /// The list of windows that block user interaction with the system when in the blocking state.
  var blockerWindows: [NSWindow] = []
  /// The application that was active before the blocker windows were shown.
  private var previouslyActiveApp: NSRunningApplication?
  /// The cancellables used to manage Combine subscriptions. When this gets deallocated, all subscriptions are cancelled.
  private var cancellables = Set<AnyCancellable>()

  /// The default presentation options given to the application when it starts. These are used to restore the application to its original state when the blocking windows are closed since the blocking state will change the presentation options to disable system features like app switching and Mission Control.
  private var defaultPresentationOptions: NSApplication.PresentationOptions = []
  /// The audio player used to play a sound when the blocking windows are closed.
  var closeSound: AVAudioPlayer?

  override init() {
    let logger = Logger(
      enabled: !Environment.isTesting,
      logToFile:
        Environment.isDebug)
    self.logger = logger

    storage = Storage(
      logger: LogWrapper(logger: logger, label: "Storage".cyan()),
      debug: Environment.isDebug
    )

    let config = storage.loadSchedule()

    self.appState = AppState(
      schedule: config.enumerated().map { index, cycle in
        WorkCycle(
          frequency: cycle.workLength,
          duration: cycle.breakLength,
          logger: LogWrapper(logger: logger, label: "WorkCycle \(index + 1)".blue())
        )
      },
      logger: LogWrapper(logger: logger, label: "AppState".magenta())
    )

    self.logger.log("initialized")

    if !Environment.isPreview {
      appState.schedule.start()
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Store the default presentation options so we can restore them later.
    self.defaultPresentationOptions = NSApplication.shared.presentationOptions

    // Create the audio player for the close sound
    if let url = Bundle.main.url(forResource: "Bottle", withExtension: "aiff") {
      do {
        closeSound = try AVAudioPlayer(contentsOf: url)
      } catch {
        logger.error("Failed to create close sound: \(error)")
      }
    } else {
      logger.error("Bottle.aiff not found in bundle.")
    }

    // Toggle the blocking windows on AppState.schedule.isBlocking changes.
    appState.schedule.$isBlocking
      .removeDuplicates()
      .dropFirst()
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
          // If we ever want to programmatically close the settings window,
          // we can do that here.
          // } else {
          //  self?.settingsWindow?.close()
        }
      }
      .store(in: &cancellables)

    // Initialize the global hotkeys
    KeyboardShortcuts.onKeyUp(for: .togglePause) { [weak self] in
      self?.appState.schedule.togglePaused()
    }
    KeyboardShortcuts.onKeyUp(for: .takeBreak) { [weak self] in
      self?.appState.schedule.startBreak()
    }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Cancel the timer task when the application is about to terminate.
    appState.schedule.cancelTimer()
  }

  func openSettingsWindow() {
    logger.log("Opening settings window")
    guard settingsWindow == nil else {
      logger.warn("Settings window already exists")
      return
    }

    settingsWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
      styleMask: [.closable, .titled, .resizable],
      backing: .buffered,
      defer: false
    )

    guard let win = settingsWindow else {
      logger.error("Failed to create settings window")
      return
    }

    // Don't allow the system to auto-release the window when closed.
    // Instead we will handle the close event to remove the reference to the window
    // which should in turn release it when there are no more references to it.
    win.isReleasedWhenClosed = false
    win.delegate = self
    win.contentView = NSHostingView(
      rootView: LookAwaySettings(
        state: appState,
        storage: storage,
        logger: logger
      )
    )
    win.title = "LookAway Settings"
    win.center()
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // This receives close events for all windows, including our blockers
  func windowWillClose(_ notification: Notification) {
    if (notification.object as? NSWindow) == settingsWindow {
      logger.log("Closing settings window `\(settingsWindow?.title ?? "Unknown")`")

      // Clear the reference to the settings window so it can be deallocated
      // and we can re-create it again later.
      settingsWindow = nil

      // Keep the app state in sync. This MUST happen last so the `showSettings`
      // binding doesn't try to call close the window again.
      appState.showSettings = false
    }
  }

  /**
   * Shows the window blockers that cover the user's screen.
   */
  func openScreenBlockers() {
    // Store the previously active application so we can restore it later.
    previouslyActiveApp = NSWorkspace.shared.frontmostApplication

    // Set presentation options to disable system features like app switching and Mission Control.
    let restrictiveOptions: NSApplication.PresentationOptions = [
      .hideDock,
      .hideMenuBar,
      .disableAppleMenu,
      .disableProcessSwitching,
      .disableHideApplication,
    ]
    NSApplication.shared.presentationOptions = restrictiveOptions

    let columns = 4
    let rows = 4
    // Pick a color style for this blocking session (shared across all screens)
    let colorGrid = MagneticWanderer.ColorStylePicker.pick(columns: columns, rows: rows)

    // Create a window blocker for each screen.
    if blockerWindows.isEmpty {
      for screen in NSScreen.screens {
        // Get the top safe area inset (for the notch, if present)
        let safeAreaTopInset: CGFloat
        if #available(macOS 12.0, *) {
          safeAreaTopInset = screen.safeAreaInsets.top
        } else {
          safeAreaTopInset = 0
        }

        // The ContentView will get the AppState from the environment.
        let contentView = LookAwayContent(
          safeAreaTopInset: safeAreaTopInset,
          colorGrid: colorGrid,
          columns: columns,
          rows: rows
        )
        .environmentObject(appState)
        .environmentObject(appState.schedule)

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
    closeSound?.play()

    // Restore the default presentation options.
    NSApplication.shared.presentationOptions = defaultPresentationOptions

    for window in blockerWindows {
      window.close()
    }
    blockerWindows.removeAll()

    // Restore focus to the previously active application.
    if let app = previouslyActiveApp {
      //      app.activate(options: .activateIgnoringOtherApps)
      app.activate(options: .activateAllWindows)
      previouslyActiveApp = nil
    }

    logger.log("Closed all blocker windows")
  }
}
