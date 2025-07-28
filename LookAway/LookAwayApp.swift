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
    var previewWindow: NSWindow?
    var timer: Timer?
    // TODO Make this configurable
    let countdownDuration: TimeInterval = 15 * 60 // 15 minutes
    @Published var remainingTime: TimeInterval = 15 * 60
    @Published var countdownLabel: String = "15:00"

    override init() {
        self.remainingTime = countdownDuration
        self.countdownLabel = TimeFormatter.format(duration: countdownDuration)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a timer but don't schedule it on the default run loop mode.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else { return }

            self.remainingTime -= 1

            if self.remainingTime <= 0 {
                print("Look Away")
                // Reset the timer
                self.remainingTime = self.countdownDuration
            }
            self.updateLabel()
        }
        self.timer = timer
        // Add the timer to the main run loop for the common modes. This ensures the timer continues to fire even when the menu is open.
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateLabel() {
        countdownLabel = TimeFormatter.format(duration: remainingTime)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Invalidate the timer when the application is about to terminate.
        timer?.invalidate()
    }

    @objc func openPreviewWindow() {
        if previewWindow == nil {
            let contentView = ContentView()
            previewWindow = NSWindow(
                contentRect: .zero,
                styleMask: [
                    .titled,
                    .closable,
                    .fullSizeContentView
                ],
                backing: .buffered,
                defer: false)
            previewWindow?.center()
            previewWindow?.level = .floating
            previewWindow?.isReleasedWhenClosed = false
            previewWindow?.contentView = NSHostingView(rootView: contentView)
        }
        previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
