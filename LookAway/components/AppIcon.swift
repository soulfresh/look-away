import SwiftUI

/// Provides the App Icon that can be used to show the current cycle progress.
struct AppIcon: View {
  var percent: CGFloat
  
  var body: some View {
    Image(
      systemName: "timelapse",
      variableValue: CGFloat(
        min(1.0, max(0.0, percent))
      )
    )
    .imageScale(.large)
    .fontWeight(.black)
    .symbolRenderingMode(.palette)
    .foregroundStyle(Color.theme.primary)
  }
}
