import SwiftUI

struct ActionButton<Label: View>: View {
  private var color: Color = .accentColor
  let action: () -> Void
  let label: () -> Label

  init(
    color: Color = .accentColor,
    action: @escaping () -> Void,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.color = color
    self.action = action
    self.label = label
  }

  var body: some View {
    Button(action: action) {
      label()
        .padding()
    }
    .buttonStyle(.plain)
    .foregroundColor(.white)
    .background(Color.black.opacity(0.1))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.5), lineWidth: 1)
    )
  }
}

extension ActionButton where Label == Text {
  init(_ title: String, action: @escaping () -> Void) {
    self.init(action: action) {
      Text(title)
    }
  }

  init(title: String, color: Color, action: @escaping () -> Void) {
    self.init(color: color, action: action) {
      Text(title)
    }
  }
}

struct KeyHintButton: View {
  let title: String
  let key: String
  let color: Color
  let action: () -> Void

  init(
    title: String,
    key: String,
    color: Color = .accentColor,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.key = key
    self.color = color
    self.action = action
  }

  var body: some View {
    ActionButton(color: color, action: action) {
      HStack {
        Text(title)
        HStack(spacing: 0) {

          Text("[")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.2))
          Text(key)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.6))
          Text("]")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.2))
        }
      }
    }
  }
}

/// The root view for the UI that is displayed when the app is blocking user interaction.
///
/// This view is responsible for rendering the user interface that appears on the
/// full-screen preview windows.
struct LookAwayContent: View {
  @EnvironmentObject var appState: AppState

  var body: some View {
    VStack {

      HStack {
        VStack {
          Spacer()

          HStack(spacing: 0) {
            let timeString =
              TimeFormatter
              .format(duration: appState.remainingTime)

            ForEach(Array(timeString.enumerated()), id: \.offset) { index, char in
              Text(String(char))
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(
                  index < 2 && appState.remainingTime <= 60
                    ? Color.theme.border.opacity(0.7)
                    : index == 2
                      ? Color.theme.border.opacity(0.7)
                      : Color.accentColor.opacity(0.7)
                )
                .frame(width: char == ":" ? 20 : 50, alignment: .center)
            }
          }

          AppIcon(percent: 1 - (appState.remainingTime / appState.phaseLength))

          Spacer()

          HStack {
            KeyHintButton(title: "Delay 1min", key: "1") {
              appState.delay(60)
            }
            KeyHintButton(title: "Delay 5mins", key: "5") {
              appState.delay(60 * 5)
            }
            KeyHintButton(title: "Delay 10mins", key: "0") {
              appState.delay(60 * 10)
            }

            Spacer()

            KeyHintButton(
              title: "Skip",
              key: "Esc",
              color: Color.theme.error,
              action: {
                appState.skip()
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
