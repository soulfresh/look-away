import SwiftUI

/// Blend two colors once the percentage is above 50%.
func blendColors(percent: CGFloat, color1: Color, color2: Color) -> Color {
  if percent <= 0.5 {
    return color1
  }
  let blendAmount = (percent - 0.5) * 2.0  // Maps 0.5...1.0 to 0...1
  // Convert Color to NSColor and ensure sRGB color space
  let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor.black
  let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor.black
  var r1: CGFloat = 0
  var g1: CGFloat = 0
  var b1: CGFloat = 0
  var a1: CGFloat = 0
  var r2: CGFloat = 0
  var g2: CGFloat = 0
  var b2: CGFloat = 0
  var a2: CGFloat = 0
  nsColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
  nsColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
  let r = r1 + (r2 - r1) * blendAmount
  let g = g1 + (g2 - g1) * blendAmount
  let b = b1 + (b2 - b1) * blendAmount
  let a = a1 + (a2 - a1) * blendAmount
  return Color(red: r, green: g, blue: b, opacity: a)
}

/// Represents the state of the AppIcon.
enum AppIconState {
  case running
  case waiting
  case paused
}

/// Provides the App Icon that can be used to show the current cycle progress.
struct AppIcon: View {
  var size: CGFloat
  var percent: CGFloat
  var state: AppIconState
  var color: Color = .red

  @State private var pulseOpacity: Double = 1.0
  private let minPulseOpacity: Double = 0.5
  private let pulseDuration: Double = 0.8

  var body: some View {
    ZStack {
      Image(
        systemName: "timelapse",
        variableValue: CGFloat(
          min(1.0, max(0.0, percent))
        )
      )
      .font(.system(size: size * 0.57, weight: .black))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(
        blendColors(percent: percent, color1: Color.primary, color2: color)
      )
      
      Image("LookAwayEye")
        .font(.system(size: size * 0.7, weight: .medium))
      
      if state == .paused {
        Image(
          systemName: "line.diagonal"
        )
        .font(.system(size: size, weight: .light))
        .foregroundStyle(.primary)
      }
    }
    .frame(width: size)
    .opacity(state == .waiting ? pulseOpacity : 1.0)
    .onAppear {
      if state == .waiting {
        withAnimation(
          Animation
            .easeInOut(duration: pulseDuration)
            .repeatForever(autoreverses: true)
        ) {
          pulseOpacity = minPulseOpacity
        }
      } else {
        pulseOpacity = 1.0
      }
    }
    .onChange(of: state) {
 _,
 newState in
      if newState == .waiting {
        withAnimation(
          Animation
            .easeInOut(duration: pulseDuration)
            .repeatForever(autoreverses: true)
        ) {
          pulseOpacity = minPulseOpacity
        }
      } else {
        withAnimation { pulseOpacity = 1.0 }
      }
    }
  }
}

#Preview {
  VStack(spacing: 10) {
    HStack {
      AppIcon(size: 18, percent: 1.0, state: .running)
      AppIcon(size: 18, percent: 0.75, state: .running)
      AppIcon(size: 18, percent: 0.5, state: .running)
      AppIcon(size: 18, percent: 0.0, state: .running)
    }
    HStack {
      AppIcon(size: 18, percent: 1.0, state: .paused)
      AppIcon(size: 18, percent: 0.75, state: .paused)
      AppIcon(size: 18, percent: 0.5, state: .paused)
      AppIcon(size: 18, percent: 0.0, state: .paused)
    }
    HStack {
      AppIcon(size: 18, percent: 1.0, state: .waiting)
      AppIcon(size: 18, percent: 0.75, state: .waiting)
      AppIcon(size: 18, percent: 0.5, state: .waiting)
      AppIcon(size: 18, percent: 0.0, state: .waiting)
    }
  }
  .padding()
}
