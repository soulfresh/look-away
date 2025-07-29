//
//  LookAwayApp.swift
//  LookAway
//
//  Created by robert marc wren on 5/30/25.
//

import SwiftUI

@main
struct LookAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // To provide a popover like window see
        // https://developer.apple.com/documentation/swiftui/menubarextra
        MenuBarExtra {
            Button("Preview") {
                appDelegate.openPreviewWindow()
            }
            Divider()
            Button("Quit LookAway") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        } label: {
            MenuBarLabelView(appDelegate: appDelegate)
        }
    }
}

// TODO Move this into its own file?
struct MenuBarLabelView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Text(appDelegate.countdownLabel)
        Image(systemName: "eye")
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var previewWindows: [NSWindow] = []
    private var timerTask: Task<Void, Never>?
    // TODO Make this configurable
    let countdownDuration: TimeInterval = 15 * 60 // 15 minutes
    @Published var remainingTime: TimeInterval
    @Published var countdownLabel: String = ""

    private let clock: any Clock<Duration>

    init(clock: any Clock<Duration>) {
        self.clock = clock
        self.remainingTime = countdownDuration
        self.countdownLabel = TimeFormatter.format(duration: countdownDuration)
        super.init()
    }
    
    override convenience init() {
        self.init(clock: ContinuousClock())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        timerTask = Task {
            await startCountdown()
        }
    }

    @MainActor
    func startCountdown() async {
        while !Task.isCancelled {
            updateLabel()

            if remainingTime <= 0 {
                print("Look Away")
                // Reset the timer
                remainingTime = countdownDuration
            }

            do {
                try await clock.sleep(for: .seconds(1))
                remainingTime -= 1
            } catch {
                // The sleep was cancelled, so we can exit the loop.
                break
            }
        }
    }

    @MainActor
    func updateLabel() {
        countdownLabel = TimeFormatter.format(duration: remainingTime)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Invalidate the timer task when the application is about to terminate.
        timerTask?.cancel()
    }

    @MainActor
    @objc func openPreviewWindow() {
        // If the windows haven't been created yet, create one for each screen.
        if previewWindows.isEmpty {
            for screen in NSScreen.screens {
                let contentView = ContentView()
                let window = KeyWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.level = .floating
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: contentView)
                previewWindows.append(window)
            }
        }

        // Show all the windows.
        for window in previewWindows {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
