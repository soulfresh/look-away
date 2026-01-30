import KeyboardShortcuts
import SwiftUI

struct Shortcuts: View {
  var body: some View {
    Form {
      KeyboardShortcuts.Recorder(
        "Pause/Resume LookAway:",
        name: .togglePause
      )
      KeyboardShortcuts.Recorder(
        "Start Next Break:",
        name: .takeBreak
      )
    }
    .padding()
  }
}

#Preview {
  Shortcuts()
}
