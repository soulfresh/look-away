import Combine
import Foundation

/// Represents a single break in a user's schedule.
///
/// This class is a self-contained state machine that manages its own timer
/// and publishes its current phase.
class Break: ObservableObject {
    /// The different phases a break can be in.
    enum Phase {
        case idle
        case working(remaining: TimeInterval)
        case breaking(remaining: TimeInterval)
        case finished
    }

    /// The current phase of the break cycle, published for observers.
    @Published var phase: Phase = .idle

    /// How often the break repeats in seconds.
    let frequency: TimeInterval

    /// How long the break lasts in seconds.
    let duration: TimeInterval

    private var timerTask: Task<Void, Never>?
    private let clock: any Clock<Duration>

    init(
        frequency: TimeInterval, duration: TimeInterval,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.frequency = frequency
        self.duration = duration
        self.clock = clock
    }

    /// Starts the working phase of the break flow.
    @MainActor
    func startWorking() {
        // Ensure we don't start multiple timers.
        guard timerTask == nil else { return }

        timerTask = Task {
            defer {
                // TODO Ensure this happens if
                // - task is cancelled
                // - task finishes normally
                // - task throws an error
                Task { @MainActor in self.timerTask = nil }
            }

            do {
                // Start with the working phase.
                try await runPhase(duration: frequency, phase: Phase.working)
                // Then move to the breaking phase.
                try await runPhase(duration: duration, phase: Phase.breaking)
                // Finally, set the phase to finished.
                self.phase = .finished
            } catch {
                self.phase = .idle
            }
        }
    }

    /// Advances into the break phase if we are in any other phase.
    func startBreak() {
        // TODO Handle both idle and working phases. If completed, do nothing?
    }

    /// Pause the break wherever we are in the cycle.
    func pause() {}
    /// Resume the break from where it left off.
    func resume() {
        // TODO What do we do if the phase is idle or completed?
        // - do nothing?
        // - start the working phase?
    }
    /// Reset the break to its initial state. This will cancel the timer and reset all state.
    func reset() {}

    /// Cancels the timer task for this break.
    // TODO Use reset instead?
    func cancel() {
        // TODO Test that this is moved into the .idle phase
        timerTask?.cancel()
    }

    /// A helper function to run a specific phase of the break cycle for a given duration.
    @MainActor
    private func runPhase(duration: TimeInterval, phase update: (TimeInterval) -> Phase)
        async throws
    {
        var remaining = duration
        while remaining >= 0 {
            try Task.checkCancellation()

            // Update the published phase with the remaining time.
            self.phase = update(remaining)

            try await clock.sleep(for: .seconds(1))
            remaining -= 1
        }
    }
}

/// The single source of truth for all shared application state.
///
/// This class coordinates the application's state, such as window visibility,
/// and observes the active `Break` to update the UI.
class AppState: ObservableObject {
    /**
     * When `true`, the application will display the blocking windows that
     * prevent interactions with the rest of the system.
     */
    @Published var isBlocking: Bool = false

    /// The remaining time displayed in the menu bar, driven by the active break.
    @Published var remainingTime: TimeInterval = 0

    // For now, the schedule contains a single, hardcoded break.
    private let schedule: Break
    private var cancellables = Set<AnyCancellable>()

    /**
     * - Parameter clock: The clock to use for time-based operations.
     */
    init(clock: any Clock<Duration> = ContinuousClock()) {
        // TODO: Make this schedule user-configurable.
        let initialBreak = Break(frequency: 10, duration: 5, clock: clock)
        self.schedule = initialBreak

        // Subscribe to the break's phase changes.
        self.schedule.$phase
            .sink { [weak self] newPhase in
                self?.handleBreakPhaseChange(newPhase)
            }
            .store(in: &cancellables)

        // Start the break cycle.
        Task { @MainActor in
            self.schedule.startWorking()
        }
    }

    /// Pause the current break cycle.
    func pause() { }
    /// Resume the current break cycle.
    func resume() { }
    /// Start the break portion of the current break cycle.
    func startBreak() {}
    /** Start the next break cycle. This will enter into the working portion of
     * that cycle.
     */
    func startWorking() {}

    /// Updates the AppState based on the current phase of the active break.
    private func handleBreakPhaseChange(_ phase: Break.Phase) {
        switch phase {
        case .idle:
            isBlocking = false
            remainingTime = 0
        case .working(let remaining):
            isBlocking = false
            remainingTime = remaining
        case .breaking(let remaining):
            isBlocking = true
            remainingTime = remaining
        case .finished:
            isBlocking = false
            // Here you would typically start the next break in the schedule.
            // For now, we'll just restart the current one for continuous looping.
            Task { @MainActor in
                self.schedule.startWorking()
            }
        }
    }

    func cancelTimer() {
        schedule.cancel()
    }
}
