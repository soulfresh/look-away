import Foundation
import Combine

// This class will act as the single source of truth for shared application state.
class AppState: ObservableObject {
    @Published var isShowingPreview: Bool = false
    @Published var countdownLabel: String = ""

    // TODO Make this configurable
    let countdownDuration: TimeInterval = 15 * 60 // 15 minutes
    @Published var remainingTime: TimeInterval

    private var timerTask: Task<Void, Never>?
    private let clock: any Clock<Duration>

    init(clock: any Clock<Duration>) {
        self.clock = clock
        self.remainingTime = countdownDuration
        self.countdownLabel = TimeFormatter.format(duration: countdownDuration)
        self.timerTask = Task { @MainActor in
            await startCountdown()
        }
    }
    
    convenience init() {
        self.init(clock: ContinuousClock())
    }

    @MainActor
    func startCountdown() async {
        while !Task.isCancelled {
            updateLabel()

            if remainingTime <= 0 {
                print("Look Away")
                isShowingPreview = true
                // Reset the timer
                remainingTime = countdownDuration
            }

            do {
                try await clock.sleep(for: .seconds(1))
                remainingTime -= 1
            } catch {
                // The sleep was cancelled, so we can exit the loop.
                break
            }
        }
    }

    @MainActor
    func updateLabel() {
        countdownLabel = TimeFormatter.format(duration: remainingTime)
    }

    func cancelTimer() {
        timerTask?.cancel()
    }
}
