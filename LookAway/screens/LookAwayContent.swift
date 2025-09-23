import SwiftUI

/// The root view for the UI that is displayed when the app is blocking user interaction.
///
/// This view is responsible for rendering the user interface that appears on the
/// full-screen preview windows.
struct LookAwayContent: View {
  @EnvironmentObject var schedule: BreakSchedule<ContinuousClock>
  var safeAreaTopInset: CGFloat = 0

  var body: some View {
    VStack {
      HStack {
        AppIcon(
          size: 26,
          percent: 1 - (schedule.remainingTime / schedule.phaseLength),
          state: .running,
          color: .success
        )
        Spacer()
        BreakCounts()
        Spacer()
      }
      .padding([.leading, .vertical])
      .padding(.top, safeAreaTopInset)

      HStack {
        VStack {
          Spacer()

          CountDown()

          Spacer()

          HStack {
            KeyHintButton(title: "Delay 1min", key: "1") {
              schedule.delay(60)
            }
            KeyHintButton(title: "Delay 5mins", key: "5") {
              schedule.delay(60 * 5)
            }
            KeyHintButton(title: "Delay 10mins", key: "0") {
              schedule.delay(60 * 10)
            }

            Spacer()

            KeyHintButton(
              title: "Skip",
              key: "Esc",
              color: Color.theme.error,
              action: {
                schedule.skip()
              })
          }
        }
      }
      .padding(20)
    }
    .background(
      ZStack {
        VisualEffectView(
          material: .hudWindow,
          blendingMode: .behindWindow,
        )
        LinearGradient(
          gradient: Gradient(colors: [
            Color.theme.background.opacity(0.7),
            Color.theme.background.opacity(0.95),
          ]),
          startPoint: .top,
          endPoint: .bottom
        )
      }
    )
  }
}

struct BreakCounts: View {
  @EnvironmentObject var schedule: BreakSchedule<ContinuousClock>

  var body: some View {
    HStack {
      ScoreText(title: "Completed", score: schedule.completed)
        .padding(.trailing, 20)
      ScoreText(
        title: "Delayed",
        score: schedule.delayed,
        positive: false
      )
      .padding(.trailing, 20)
      ScoreText(
        title: "Skipped",
        score: schedule.skipped,
        positive: false
      )
    }
  }
}

struct CountDown: View {
  @EnvironmentObject var schedule: BreakSchedule<ContinuousClock>

  var body: some View {
    HStack(spacing: 0) {
      let timeString =
        TimeFormatter
        .format(duration: schedule.remainingTime)

      ForEach(Array(timeString.enumerated()), id: \.offset) { index, char in
        Text(String(char))
          .font(.system(size: 80, weight: .thin))
          .foregroundStyle(
            index < 2 && schedule.remainingTime <= 60
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

#Preview {
  let schedule = [
    WorkCycle<ContinuousClock>(
      frequency: 10,
      duration: 5,
      logger: Logger()
    )
  ]
  LookAwayContent()
    .environmentObject(
      AppState(
        schedule: schedule,
        logger: Logger()
      )
    )
    .environmentObject(
      BreakSchedule(
        schedule: schedule,
        logger: Logger()
      )
    )
}
