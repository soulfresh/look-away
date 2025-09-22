import SwiftUI

/// The button/icon for our app in the system menu.
struct MenuBarIconButton: View {
  @ObservedObject var schedule: BreakSchedule

  var body: some View {
    Image(
      // MenuBarExtra only allows a single `Image` but we want to render
      // several layers to create our icon. To make that work, we render the
      // AppIcon to a bitmap.
      nsImage: AppIcon(
        size: 18,
        percent: 1 - (schedule.remainingTime / schedule.phaseLength),
        state: schedule.isPaused ? .paused : .running
      )
      .asImage(size: CGSize(width: 18, height: 18))
    )
  }
}

/// A helper to render a SwiftUI view to a bitmap.
extension View {
  func asImage(size: CGSize) -> NSImage {
    let hostingView = NSHostingView(rootView: self.frame(width: size.width, height: size.height))
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded() // Ensure layout
    guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
      // Return a blank image if bitmap creation fails
      let blank = NSImage(size: size)
      blank.lockFocus()
      NSColor.clear.set()
      NSRect(origin: .zero, size: size).fill()
      blank.unlockFocus()
      return blank
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
    let image = NSImage(size: size)
    image.addRepresentation(bitmapRep)
    return image
  }
}

#Preview {
  let schedule = [
    WorkCycle(
      frequency: 10,
      duration: 5,
      logger: Logger()
    )
  ]
  MenuBarIconButton(
    schedule: BreakSchedule(
      schedule: schedule,
      logger: Logger()
    )
  )
  .padding(40)
}
