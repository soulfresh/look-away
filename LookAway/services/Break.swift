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
  
  /// The timer used to track progress through the break phases.
  var timerTask: Task<Void, Never>? {
    didSet {
      // Keep the isRunning published state up-to-date.
      isRunning = timerTask != nil
    }
  }
//  private var timerTask: Task<Void, Never>?

  /// The current phase of the break cycle, published for observers.
  @Published private(set) var phase: Phase = .idle
  /// Whether or not the timer is currently running.
  @Published private(set) var isRunning: Bool = false
//  var isRunning: Bool {
//    timerTask != nil
//  }
  
  /// How often the break repeats in seconds.
  let frequency: TimeInterval

  /// How long the break lasts in seconds.
  let duration: TimeInterval

  /// Provides an interface for measuring code execution timing.
  private let logger: Logger
    
  private let clock: any Clock<Duration>

  /// - Parameter frequency: The frequency of the break in seconds.
  /// - Parameter duration: The duration of the break in seconds.
  /// - Parameter logger
  /// - Parameter clock: The clock to use for time-based operations, defaults to `ContinuousClock`. This is useful for controlling the timing of the break in tests or different environments.
  init(
    frequency: TimeInterval,
    duration: TimeInterval,
    logger: Logger,
    clock: any Clock<Duration> = ContinuousClock(),
  ) {
    self.frequency = frequency
    self.duration = duration
    self.logger = logger
    self.clock = clock
  }

  deinit {
    logger.log("Deinitializing Break instance")
    // Ensure all tasks are cancelled.
    cancel()
  }

  /// Starts the working phase of the break flow.
  /// - Parameter workingDuration: Optional duration for the working phase.
  func startWorking(_ workingDuration: TimeInterval? = nil) {
    logger.log("Starting working phase with duration: \(workingDuration ?? frequency)")

    runTask(
      operation: {
        self.logger.log("Running working phase")
        // Start with the working phase.
        try await self.runPhase(
          duration: workingDuration ?? self.frequency,
          phase: Phase.working
        )
        self.logger.log("Starting break")
        // Then move to the breaking phase.
        try await self.runPhase(
          duration: self.duration,
          phase: Phase.breaking
        )
        self.logger.log("Break complete")
        // Finally, set the phase to finished.
        self.phase = Phase.finished
        self.cancel()
      },
      errorHandler: { error in
        self.logger.log("Error in working phase: \(error)")
        self.phase = Phase.idle
        self.cancel()
      }
    )
  }

  /// Advances into the break phase if we are in any other phase.
  ///
  /// - Parameter breakingDuration: Optional duration for the breaking phase.
  func startBreak(_ breakingDuration: TimeInterval? = nil) {
    logger.log("Starting break phase with duration: \(breakingDuration ?? duration)")

    runTask(
      operation: {
        self.logger.log("Running break phase")
        // Transition directly to the breaking phase.
        try await self.runPhase(
          duration: breakingDuration ?? self.duration,
          phase: Phase.breaking
        )
        self.logger.log("Break complete")
        // After breaking, set the phase to finished.
        self.phase = Phase.finished
        self.cancel()
      },
      errorHandler: { error in
        self.logger.log("Error in working phase: \(error)")
        self.phase = Phase.idle
        self.cancel()
      }
    )
  }

  /// Pause the break wherever we are in the cycle.
  func pause() {
    logger.log("Pausing break timer task")
    // Cancelling the current task will retain the current time remaining value
    // in the current phase so we can easily resume later.
    cancel()
  }

  /// Resume the break from where it left off.
  func resume() {
    logger.log("Resuming break timer task")
    // If we are already running, do nothing.
    guard !isRunning else { return }
//    guard timerTask == nil else { return }

    switch phase {
    case .working(let remaining):
      startWorking(remaining)
    case .breaking(let remaining):
      startBreak(remaining)
    case .idle, .finished: break
    // TODO What do we do if the phase is idle or completed?
    // - do nothing?
    // - start the working phase?
    }
  }

  /// Reset the break to its initial state. This will cancel the timer and reset all state.
  func reset() {
    logger.log("Resetting this Break")
    cancel()
    phase = .idle
  }

  /// Cancels the timer task for this break without changing the phase which would cause a binding update in `AppState`.
  func cancel() {
    logger.log("Cancelling break timer task")
    timerTask?.cancel()
    timerTask = nil
  }

  /// A helper function to run a specific phase of the break cycle for a given duration.
  private func runPhase(duration: TimeInterval, phase update: (TimeInterval) -> Phase)
    async throws
  {
    var remaining = duration
    while remaining >= 0 {
      // Throw an error if the task is cancelled.
      try Task.checkCancellation()

      // Update the published phase with the remaining time.
      self.phase = update(remaining)
      logger.log("Phase updated to: \(self.phase) with remaining time: \(remaining) seconds")

      // TODO Task has a sleep method. Do we still need Clock? Would we be able
      // to mock Task.sleep in tests?
      try await clock.sleep(for: .seconds(1))
      remaining -= 1
    }
  }

  /// Starts a new timer task, ensuring that only one timer is running at a time.
  private func runTask(
    operation: @escaping () async throws -> Void,
    errorHandler: @escaping (Error) -> Void
  ) {
    cancel()

    timerTask = Task {
      do {
        try await operation()
      } catch is CancellationError {
        // If the task was cancelled, we simply exit without doing anything. This allows the task timer to stop without us handling it as an error.
      } catch {
        errorHandler(error)
      }
    }
  }

}
