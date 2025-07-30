import SwiftUI

/// The root view for the UI that is displayed when the app is blocking user interaction.
///
/// This view is responsible for rendering the user interface that appears on the
/// full-screen preview windows.
struct ContentView: View {
  @EnvironmentObject var appState: AppState

  var body: some View {
    HStack {
      Spacer()
      VStack {
        Spacer()
        Image(systemName: "globe")
          .imageScale(.large)
          .foregroundStyle(.tint)
        Text("Look away from the COMPUTER!")
        Button("Close") {
          appState.isBlocking = false
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
  ContentView().environmentObject(AppState())
}
