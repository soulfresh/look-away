import Foundation
import Combine

/**
 * The single source of truth for all shared application state.
 *
 * This class manages the application's data and state, such as timers
 * and window visibility. It is an `ObservableObject`
 * so that SwiftUI views can subscribe to its changes.
 */
class AppState: ObservableObject {
    /**
     * When `true`, the application will display the blocking windows that
     * prevent interactions with the rest of the system.
     */
    @Published var isBlocking: Bool = false
    
    /**
     * A formatted string representing the time remaining on the countdown timer (e.g., "14:59").
     */
    @Published var countdownLabel: String = ""

    /// The total duration of the countdown in seconds.
    let countdownDuration: TimeInterval = 15 * 60 // 15 minutes
    
    /// The remaining time on the countdown timer in seconds.
    @Published var remainingTime: TimeInterval

    private var timerTask: Task<Void, Never>?
    private let clock: any Clock<Duration>

    /**
     * - Parameter clock: The clock to use for time-based operations.
     */
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

    /**
     * Starts the clocks used to manage the user's schedules.
     */
    @MainActor
    func startCountdown() async {
        while !Task.isCancelled {
            updateLabel()

            if remainingTime <= 0 {
                print("Look Away")
                isBlocking = true
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
    internal func updateLabel() {
        countdownLabel = TimeFormatter.format(duration: remainingTime)
    }

    func cancelTimer() {
        timerTask?.cancel()
    }
}
