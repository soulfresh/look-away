//
//  LookAwayApp.swift
//  LookAway
//
//  Created by robert marc wren on 5/30/25.
//

import SwiftUI

// A custom NSWindow subclass that can become the key window,
// which is necessary for borderless windows to receive keyboard events.
class KeyWindow: NSWindow {
    // Add a reference to the AppState to communicate back.
    var appState: AppState?

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    // Handle keyboard events directly in the window.
    override func keyDown(with event: NSEvent) {
        // Check if the Escape key was pressed.
        if event.keyCode == 53 { // 53 is the key code for Escape
            // Change the state to close the windows.
            appState?.isShowingPreview = false
        } else {
            // Pass other key events to the superclass.
            super.keyDown(with: event)
        }
    }
}
