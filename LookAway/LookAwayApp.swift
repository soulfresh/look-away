//
//  LookAwayApp.swift
//  LookAway
//
//  Created by robert marc wren on 5/30/25.
//

import SwiftUI
import Combine

@main
struct LookAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // To provide a popover like window see
        // https://developer.apple.com/documentation/swiftui/menubarextra
        MenuBarExtra {
            Button("Preview") {
                // This button now changes the state on the central AppState object.
                appDelegate.appState.isShowingPreview = true
            }
            Divider()
            Button("Quit LookAway") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        } label: {
            // Pass the AppState directly to the initializer.
            MenuBarLabelView(appState: appDelegate.appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // The AppDelegate now owns the AppState.
    let appState = AppState()
    
    var previewWindows: [NSWindow] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Subscribe to changes in AppState.isShowingPreview and react accordingly.
        appState.$isShowingPreview
            .removeDuplicates()
            .sink { [weak self] isShowing in
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

    @MainActor
    func showPreviewWindows() {
        // If the windows haven't been created yet, create one for each screen.
        if previewWindows.isEmpty {
            for screen in NSScreen.screens {
                // The ContentView will get the AppState from the environment.
                let contentView = ContentView().environmentObject(appState)
                let window = KeyWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.level = .screenSaver
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: contentView)
                // Give the window a reference to the AppState to handle the Escape key
                window.appState = self.appState
                previewWindows.append(window)
            }
        }

        // Show all the windows.
        for window in previewWindows {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func closePreviewWindows() {
        for window in previewWindows {
            window.close()
        }
        previewWindows.removeAll()
    }
}
