//
//  ContentView.swift
//  LookAway
//
//  Created by robert marc wren on 5/30/25.
//

import SwiftUI

struct ContentView: View {
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
                    NSApp.keyWindow?.close()
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
    ContentView()
}
