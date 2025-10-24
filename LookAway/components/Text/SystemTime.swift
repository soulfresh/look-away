import SwiftUI

struct SystemTime: View {
  @State private var currentTime: String
  @State private var clock: any Clock<Duration>

  static func getTime() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = DateFormatter.dateFormat(
      fromTemplate: "j:mm", options: 0, locale: Locale.current)
    return formatter.string(from: Date())
  }

  init(clock: any Clock<Duration> = ContinuousClock()) {
    self.clock = clock
    self._currentTime = State(initialValue: SystemTime.getTime())
  }

  var body: some View {
    Text(currentTime)
      .font(.system(size: 14))
      .foregroundStyle(Color.primary.opacity(0.8))
      .task {
        updateTime()
        while !Task.isCancelled {
          do {
            try await clock.sleep(for: .seconds(60))
            updateTime()
          } catch {
            break
          }
        }
      }
  }

  func updateTime() {
    currentTime = SystemTime.getTime()
  }
}

#Preview {
  SystemTime().padding()
}
