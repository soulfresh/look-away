import SwiftUI

/// The root view for the UI that is displayed when the app is blocking user interaction.
///
/// This view is responsible for rendering the user interface that appears on the
/// full-screen preview windows.
struct LookAwayContent: View {
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

        Button("Skip (Esc)") {
          appState.skip()
        }
        Button("Delay 1min (1)") {
          appState.delay(60)
        }
        Button("Delay 5mins (5)") {
          appState.delay(60 * 5)
        }
        Button("Delay 10mins (0)") {
          appState.delay(60 * 10)
        }

        Spacer()
      }
      Spacer()
    }
    .padding()
  }
}

#Preview {
  LookAwayContent().environmentObject(
    AppState(
      schedule: [
        WorkCycle(
          frequency: 10,
          duration: 5,
          logger: Logger()
        )
      ],
      logger: Logger()
    ))
}
