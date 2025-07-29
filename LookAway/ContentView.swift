//
//  ContentView.swift
//  LookAway
//
//  Created by robert marc wren on 5/30/25.
//

import SwiftUI

struct ContentView: View {
    // This view now gets the AppState from the environment.
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
                Button("Close") {
                    // This button now changes the state on the central AppState object.
                    appState.isShowingPreview = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
            }
            Spacer()
        }
        .padding()
    }
}

#Preview {
    // We need to provide a dummy AppState for the preview to work.
    ContentView().environmentObject(AppState())
}
