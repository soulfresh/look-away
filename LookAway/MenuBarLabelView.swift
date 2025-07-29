import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Text(appState.countdownLabel)
        Image(systemName: "eye")
    }
}
