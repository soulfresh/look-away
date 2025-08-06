import Combine
import Foundation

/// Global application state manager. Used to coordinate when the app is
/// blocking system interaction and provides global state such as the remaining
/// time for the current break.
@MainActor
class AppState: ObservableObject {
  /// Whether or not to show the settings window.
  @Published var showSettings: Bool = false
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

  /// The number of times the user has skipped a break
  @Published private(set) var skipped: Int = 0
  /// The number of times the current work cycle has been delayed. This gets
  /// reset when the work cycle advances.
  @Published private(set) var delayed: Int = 0
  /// The total number of work cycles STARTED
  @Published private(set) var count: Int = 0

  /// Gets the current index of the work cycle in the schedule.
  var index: Int {
    (count - 1) % schedule.count
  }

  /// The number of fully completed breaks (ie. they were not ended prematurely).
  var completed: Int {
    count - 1 - skipped
  }

  /// A timer that can be used for performance measurements.
  public let logger: Logging

  /// The schedule of work cycles that the application will follow.
  private var schedule: [WorkCycle]

  /// The current work cycle that the application is following.
  private var cycle: WorkCycle? {
    schedule.getElement(at: index)
  }

  /// Cancellables that will be cleaned up when AppState is destroyed.
  private var cancellables = Set<AnyCancellable>()

  /**
   * - Parameter schedule: The schedule of work cycles to follow.
   * - Parameter logger: A logger to use for debugging and performance measurements.
   */
  init(
    schedule _schedule: [WorkCycle],
    logger: Logging,
  ) {
    self.logger = logger
    self.schedule = _schedule

    logger.log("Initialized with \(_schedule.count) work cycles.")
    // Start the first work cycle a bit later.
    Task {
      self.logger.log("Kicking off the first work cycle.")
      // TODO We have to set _cycleIndex to -1 to get this to advance to index
      // 0. Is there a cleaner way to do that. Feels brittle
      self.startNextWorkCycle()
    }
  }

  /// Pause the current work cycle.
  func pause() {
    cycle?.pause()
  }

  /// Resume the current work cycle.
  func resume() {
    cycle?.resume()
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
    cycle?.startBreak(breakDuration)
  }

  /// Rewind to the working phase of the current work cycle in our schedule.
  ///
  /// - Parameter duration The amount of time to work for before restarting the
  ///     current break phase.
  func delay(_ duration: TimeInterval) {
    guard let cycle = cycle else { return }

    logger.time("close-windows")
    delayed += 1
    // Keep the current work cycle but rewind to the working phase.
    cycle.startWorking(duration)
  }

  /// Skip the current break and immediately start the working phase of the next
  /// work cycle.
  func skip() {
    logger.time("close-windows")
    skipped += 1
    // Advance to the next work cycle.
    startNextWorkCycle()
  }

  /// Start the next work cycle. This will enter into the working portion of
  /// that cycle.
  private func startNextWorkCycle(_ workingDuration: TimeInterval? = nil) {
    guard schedule.count > 0 else {
      // TODO Warning
      logger.error("No work cycles in the schedule. Cannot start next work cycle.")
      return
    }

    logger.time("close-windows")
    logger.log("Shutting down the current work cycle.")

    // Stop listening to the old work cycle.
    cancellables.forEach { $0.cancel() }
    cancellables.removeAll()

    // Reset all work cycles to idle.
    schedule.forEach { $0.reset() }

    // Reset the delayed counter
    delayed = 0

    // Advance to the next work cycle in the schedule.
    count += 1

    // This should never happen given the guard at the beginning of this function.
    guard let c = cycle else {
      logger.error("Unable to get the current work cycle at index \(count) of \(schedule.count).")
      return
    }

    // Watch for changes in the new work cycle and update the "blocking" state.
    c.$phase
      .receive(on: DispatchQueue.main)
      .sink { [weak self] phase in
        self?.onWorkCyclePhaseChange(phase)
      }
      .store(in: &cancellables)

    // Watch for changes in the work cycle's `isRunning` state and publish that as `isPaused`.
    c.$isRunning
      // Map to the inverse of `isRunning`
      .map { !$0 }
      .receive(on: DispatchQueue.main)
      .assign(to: &$isPaused)

    logger.log("Starting work cycle \(count) [index: \(index)] \(c)")
    // Start working in the new cycle.
    c.startWorking(workingDuration)
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
      // Track the number of breaks that were fully completed.
      // completed += 1
      // Start the next work cycle in the schedule.
      Task {
        self.startNextWorkCycle()
      }
    }
  }

  /// Stop the current work cycle immediately. This is used to stop timers
  /// without any side effects during shutdown.
  func cancelTimer() {
    cycle?.cancel()
  }
}
