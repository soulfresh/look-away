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
        MenuBarExtra("Look Away", systemImage: "eye") {
            Button("Preview") {
                appDelegate.openPreviewWindow()
            }
            Divider()
            Button("Quit LookAway") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {}

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
