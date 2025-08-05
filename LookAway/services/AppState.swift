import Combine
import Foundation

/// Global application state manager. Used to coordinate when the app is
/// blocking system interaction and provides global state such as the remaining
/// time for the current break.
@MainActor
class AppState: ObservableObject {
  /**
   * When `true`, the application will display the blocking windows that
   * prevent interactions with the rest of the system.
   */
  @Published private(set) var isBlocking: Bool = false
  /// Whether the break scheduling is currently paused.
  @Published private(set) var isPaused: Bool = false

  /// The remaining time displayed in the menu bar, driven by the active work
  /// cycle.
  @Published private(set) var remainingTime: TimeInterval = 0

  /// A timer that can be used for performance measurements.
  public let logger: Logger

  /// The schedule of work cycles that the application will follow.
  private var schedule: WorkCycle

  /// Cancellables that will be cleaned up when AppState is destroyed.
  private var cancellables = Set<AnyCancellable>()

  /**
   * - Parameter clock: The clock to use for time-based operations.
   * - Parameter debug
   */
  init(clock: any Clock<Duration> = ContinuousClock(), debug: Bool = false) {
    self.logger = Logger(enabled: debug)

    // TODO: Make this schedule user-configurable.
    self.schedule = WorkCycle(
      frequency: 10,
      duration: 5,
      logger: logger,
      clock: clock
    )

    // Watch for changes in the work cycle and update the "blocking" state.
    schedule.$phase
      .receive(on: DispatchQueue.main)
      .sink { [weak self] phase in
        self?.onWorkCyclePhaseChange(phase)
      }
      .store(in: &cancellables)

    // Watch for changes in the work cycle's `isRunning` state and publish that as `isPaused`.
    schedule.$isRunning
      // Map to the inverse of `isRunning`
      .map { !$0 }
      .receive(on: DispatchQueue.main)
      .assign(to: &$isPaused)

    // Start the first work cycle.
    Task {
      self.schedule.startWorking()
    }
  }

  /// Pause the current work cycle.
  func pause() {
    schedule.pause()
  }

  /// Resume the current work cycle.
  func resume() {
    schedule.resume()
  }

  /// Toggle whether the schedule is currently paused.
  func togglePaused() {
    if isPaused {
      resume()
    } else {
      pause()
    }
  }

  /// Start the break portion of the current work cycle.
  func startBreak(_ breakDuration: TimeInterval? = nil) {
    schedule.startBreak(breakDuration)
  }

  /// Start the next work cycle. This will enter into the working portion of
  /// that cycle.
  func startWorking(_ workingDuration: TimeInterval? = nil) {
    schedule.startWorking(workingDuration)
  }

  /// Rewind to the working phase of the current work cycle in our schedule.
  ///
  /// - Parameter duration The amount of time to work for before restarting the
  ///     current break phase.
  func delay(_ duration: TimeInterval) {
    logger.time("close-windows")
    startWorking(duration)
  }

  /// Skip the current break and immediately start the working phase of the next
  /// work cycle.
  func skip() {
    logger.time("close-windows")
    // TODO Advance to the next work cycle.
    startWorking()
  }

  /// Updates the AppState based on the current phase of the active work cycle.
  private func onWorkCyclePhaseChange(_ phase: WorkCycle.Phase) {
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
      remainingTime = 0
      // Here you would typically start the next work cycle in the schedule.
      // For now, we'll just restart the current one for continuous looping.
      Task {
        self.schedule.startWorking()
      }
    }
  }

  func cancelTimer() {
    schedule.cancel()
  }
}
