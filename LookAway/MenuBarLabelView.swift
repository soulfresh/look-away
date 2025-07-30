import SwiftUI

/// The icon for our app in the system menu.
struct MenuBarLabelView: View {
  @ObservedObject var appState: AppState

  var body: some View {
    Text(TimeFormatter.format(duration: appState.remainingTime))
    Image(systemName: "eye")
  }
}
