import SwiftUI

struct KeyHintButtonData {
  let title: String
  let key: String
  let color: Color?
  let action: () -> Void
}

/// The root view for the UI that is displayed when the app is blocking user interaction.
///
/// This view is responsible for rendering the user interface that appears on the
/// full-screen preview windows.
struct LookAwayContent: View {
  @EnvironmentObject var schedule: BreakSchedule<ContinuousClock>
  @State private var baseColor: Color = .blue
  @State private var showButtons: Bool = false
  @State private var shownButtonIndices: Set<Int> = []
  @State private var showBreakCounts: Bool = false

  var safeAreaTopInset: CGFloat = 0
  let colorGrid: MagneticWanderer.ColorGrid
  let columns: Int
  let rows: Int

  var buttonData: [KeyHintButtonData] {
    [
      KeyHintButtonData(title: "Delay 1min", key: "1", color: nil) {
        schedule.delay(60)
      },
      KeyHintButtonData(title: "Delay 5mins", key: "5", color: nil) {
        schedule.delay(60 * 5)
      },
      KeyHintButtonData(title: "Delay 10mins", key: "0", color: nil) {
        schedule.delay(60 * 10)
      },
      KeyHintButtonData(title: "Skip", key: "Esc", color: Color.theme.error) {
        schedule.skip()
      },
    ]
  }

  func showButtonsStaggered() {
    for i in buttonData.indices {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.08) {
        _ = shownButtonIndices.insert(i)
      }
    }
  }

  func hideButtons() {
    shownButtonIndices.removeAll()
  }

  var body: some View {
    ZStack {
      VStack {
        HStack(alignment: .top) {
          AppIcon(
            size: 26,
            percent: 1 - (schedule.remainingTime / schedule.phaseLength),
            state: .running,
            color: .success
          )
          .padding(.vertical, 10)
          Spacer()
          BreakCounts()
            // .blendMode(.difference)
            .opacity(showBreakCounts ? 1 : 0)
            .padding(.top, safeAreaTopInset + 10)
          Spacer()
          SystemTime()
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 20)

        Spacer()
      }

      HStack {
        CountDown().blendMode(.difference)
      }

      VStack {
        Spacer()

        HStack {
          ForEach(buttonData.indices, id: \.self) { i in
            AnimatedKeyHintButton(
              title: buttonData[i].title,
              key: buttonData[i].key,
              color: buttonData[i].color ?? .primary,
              action: buttonData[i].action,
              isVisible: shownButtonIndices.contains(i),
              offsetY: 10,
              duration: 0.2
            )
            if i == 2 { Spacer() }
          }
        }
      }
      .padding(20)
    }
    .onAppear {
      showButtons = true
      showButtonsStaggered()
      withAnimation(.easeOut(duration: 0.5).delay(2.0)) {
        showBreakCounts = true
      }
    }
    .background(
      ZStack {
        VisualEffectView(
          material: .hudWindow,
          blendingMode: .behindWindow,
        )
        .opacity(0.6)

        LinearGradient(
          gradient: Gradient(colors: [
            Color.black.opacity(0.0),
            Color.black.opacity(0.9),
          ]),
          startPoint: .top,
          endPoint: UnitPoint(x: 0.5, y: 0.8)
        )

        // NortherLights(
        //   baseColor: .constant(
        //     Color(
        //       hue: 0.55,
        //       saturation: 0.6,
        //       brightness: 0.3,
        //       // Colorize yellow by skip count
        //       // hue: lerp(2, 5, 0.5, 0.11, Double(schedule.delayed)),
        //       // saturation: 0.9,
        //       // brightness: lerp(2, 5, 0.2, 0.4, Double(schedule.delayed)),
        //       opacity: 1.0
        //     )
        //   ),
        //   colorRangeDegrees: .constant(25),
        // )
        // .opacity(0.90)

        MagneticWanderer.AnimatedMesh(colorGrid: colorGrid)
          .opacity(0.9)

      }
    )
  }
}

// Lerp function for color interpolation
func lerp(
  _ minIn: Double,
  _ maxIn: Double,
  _ maxOut: Double,
  _ minOut: Double,
  _ value: Double
) -> Double {
  if value <= minIn { return maxOut }
  if value >= maxIn { return minOut }
  let t = (value - minIn) / (maxIn - minIn)
  return maxOut + (minOut - maxOut) * t
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

struct AnimatedKeyHintButton: View {
  let title: String
  let key: String
  let color: Color
  let action: () -> Void
  let isVisible: Bool
  let offsetY: CGFloat
  let duration: Double

  @State private var shownOpacity: Bool = false
  @State private var shownOffset: Bool = false
  @State private var prevVisible: Bool = false

  var body: some View {
    KeyHintButton(title: title, key: key, color: color, action: action)
      .opacity(shownOpacity ? 1 : 0)
      .offset(y: shownOffset ? 0 : offsetY)
      .onChange(of: isVisible) { oldValue, newValue in
        if newValue {
          withAnimation(.linear(duration: duration)) {
            shownOpacity = true
          }
          withAnimation(.timingCurve(0.0, 0.0, 0.2, 1.0, duration: duration)) {
            shownOffset = true
          }
        } else {
          withAnimation(.easeIn(duration: duration)) {
            shownOpacity = false
          }
          withAnimation(.easeIn(duration: duration)) {
            shownOffset = false
          }
        }
        prevVisible = newValue
      }
      .onAppear {
        shownOpacity = isVisible
        shownOffset = isVisible
        prevVisible = isVisible
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
  LookAwayContent(
    colorGrid: MagneticWanderer.ColorStylePicker.pick(columns: 4, rows: 4),
    columns: 4,
    rows: 4
  )
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
