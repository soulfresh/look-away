import SwiftUI

/**
 * The icon for our app in the system menu.
 */
struct MenuBarLabelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Text(appState.countdownLabel)
        Image(systemName: "eye")
    }
}
