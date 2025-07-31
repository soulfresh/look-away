import Combine
import SwiftUI

@main
struct LookAwayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  var body: some Scene {
    // To provide a popover like window see
    // https://developer.apple.com/documentation/swiftui/menubarextra
    MenuBarExtra {
      Button("Preview") {
        appDelegate.appState.startBreak()
      }
      Divider()
      Button("Quit LookAway") {
        NSApplication.shared.terminate(nil)
      }.keyboardShortcut("q")
    } label: {
      MenuBarLabelView(appState: appDelegate.appState)
    }
  }
}

/// The AppDelegate class manages the application lifecycle and provides the main window management.
/// The AppDelegate is required because SwiftUI does not provide an easy way to create system menu bar applications at this time.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  /**
   * The AppState object that holds the state of the application.
   */
  let appState = AppState()

  var previewWindows: [NSWindow] = []
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Subscribe to changes in AppState.isShowingPreview and react accordingly.
    appState.$isBlocking
      .removeDuplicates()
      .sink { [weak self] isShowing in
        // TODO Does this need to be in a task since we're already on the main thread?
        Task { @MainActor in
          if isShowing {
            self?.showPreviewWindows()
          } else {
            self?.closePreviewWindows()
          }
        }
      }
      .store(in: &cancellables)
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Cancel the timer task when the application is about to terminate.
    appState.cancelTimer()
  }

  /**
   * Shows the window blockers that cover the user's screen.
   */
  @MainActor
  func showPreviewWindows() {
    // If the windows haven't been created yet, create one for each screen.
    if previewWindows.isEmpty {
      for screen in NSScreen.screens {
        // The ContentView will get the AppState from the environment.
        let contentView = ContentView().environmentObject(appState)
        let window = KeyWindow(
          screen: screen,
          contentView: NSHostingView(rootView: contentView),
          appState: self.appState,
          debug: true
        )
        previewWindows.append(window)
      }
    }

    // Show all the windows.
    for window in previewWindows {
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  /**
   * Closes all window blockers, allowing the user access to their computer again.
   */
  @MainActor
  func closePreviewWindows() {
    for window in previewWindows {
      window.close()
    }
    previewWindows.removeAll()
  }
}
