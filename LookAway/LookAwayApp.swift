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
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Look Away")
        }
        // Create the menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit LookAway", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem?.menu = menu
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
