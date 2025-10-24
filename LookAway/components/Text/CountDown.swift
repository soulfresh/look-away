import SwiftUI

struct CountDown: View {
  @EnvironmentObject var schedule: BreakSchedule<ContinuousClock>

  var body: some View {
    HStack(spacing: 0) {
      let timeString =
        TimeFormatter.format(duration: schedule.remainingTime)

      ForEach(Array(timeString.enumerated()), id: \.offset) { index, char in
        Text(String(char))
          .font(.system(size: 80, weight: .thin))
          // .foregroundStyle(
          //   index < 2 && schedule.remainingTime <= 60
          //     ? Color.theme.border.opacity(0.7)
          //     : index == 2
          //       ? Color.theme.border.opacity(0.7)
          //       : Color.accentColor.opacity(0.7)
          // )
          .foregroundStyle(
            index < 2 && schedule.remainingTime <= 60
              ? Color.primary.opacity(0.3)
              : index == 2
                ? Color.primary.opacity(0.2)
                : Color.primary.opacity(1.0)
          )
          .frame(width: char == ":" ? 20 : 50, alignment: .center)
      }
    }
  }
}

#Preview {
  CountDown()
}
