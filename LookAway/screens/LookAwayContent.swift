import SwiftUI

/// The root view for the UI that is displayed when the app is blocking user interaction.
///
/// This view is responsible for rendering the user interface that appears on the
/// full-screen preview windows.
struct LookAwayContent: View {
  @EnvironmentObject var appState: AppState

  var body: some View {
    VStack {

      HStack {
        AppIcon(
          percent: 1 - (
            appState.schedule.remainingTime / appState.schedule.phaseLength
          )
        )
        Spacer()
        BreakCounts(appState: appState)
        Spacer()
      }
      .padding([.leading, .vertical])

      HStack {
        VStack {
          Spacer()

          CountDown(appState: appState)

          Spacer()

          HStack {
            KeyHintButton(title: "Delay 1min", key: "1") {
              appState.schedule.delay(60)
            }
            KeyHintButton(title: "Delay 5mins", key: "5") {
              appState.schedule.delay(60 * 5)
            }
            KeyHintButton(title: "Delay 10mins", key: "0") {
              appState.schedule.delay(60 * 10)
            }

            Spacer()

            KeyHintButton(
              title: "Skip",
              key: "Esc",
              color: Color.theme.error,
              action: {
                appState.schedule.skip()
              })
          }

        }
      }
      .padding(20)
    }
    .background(
      LinearGradient(
        gradient: Gradient(colors: [
          Color.theme.background.opacity(0.1),
          Color.theme.background.opacity(0.6),
        ]),
        startPoint: .top,
        endPoint: .bottom,
      )
    )
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

struct BreakCounts: View {
  let appState: AppState
  
  var body: some View {
    HStack {
      ScoreText(title: "Completed", score: appState.schedule.completed)
        .padding(.trailing, 20)
      ScoreText(
        title: "Delayed",
        score: appState.schedule.delayed,
        positive: false
      )
        .padding(.trailing, 20)
      ScoreText(
        title: "Skipped",
        score: appState.schedule.skipped,
        positive: false
      )
    }
  }
}

struct CountDown: View {
  let appState: AppState
  
  var body: some View {
    HStack(spacing: 0) {
      let timeString =
      TimeFormatter
        .format(duration: appState.schedule.remainingTime)
      
      ForEach(Array(timeString.enumerated()), id: \.offset) { index, char in
        Text(String(char))
          .font(.system(size: 80, weight: .thin))
          .foregroundStyle(
            index < 2 && appState.schedule.remainingTime <= 60
            ? Color.theme.border.opacity(0.7)
            : index == 2
            ? Color.theme.border.opacity(0.7)
            : Color.accentColor.opacity(0.7)
          )
          .frame(width: char == ":" ? 20 : 50, alignment: .center)
      }
    }
  }
}
