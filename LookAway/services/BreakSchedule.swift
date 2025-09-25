import Combine
import Foundation

@MainActor
class BreakSchedule<ClockType: Clock<Duration>>: ObservableObject {
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
  /// The length of the currently active phase of the current work cycle.
  @Published private(set) var phaseLength: TimeInterval = 0

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
    max(0, count - 1 - skipped)
  }

  /// A timer that can be used for performance measurements.
  public let logger: Logging

  /// The schedule of work cycles that the application will follow.
  private var schedule: [WorkCycle<ClockType>]

  /// The current work cycle that the application is following.
  private var cycle: WorkCycle<ClockType>? {
    schedule.getElement(at: index)
  }

  /// Listener for system sleep/wake events.
  private var sleepListener: SystemSleepMonitor
  /// The last time that the system went to sleep.
  private var lastSleep: Date = Date()

  /// Cancellables that will be cleaned up when AppState is destroyed.
  private var cancellables = Set<AnyCancellable>()

  /**
   * - Parameter schedule: The schedule of work cycles to follow.
   * - Parameter logger: A logger to use for debugging and performance measurements.
   */
  init(
    schedule _schedule: [WorkCycle<ClockType>],
    logger: Logging,
  ) {
    self.logger = logger
    self.schedule = _schedule

    self.sleepListener = SystemSleepMonitor(
      logger: LogWrapper(
        logger: logger, label: "SleepListener"
      )
    )

    self.sleepListener.startListening { state in
      self.onSleepStateChange(state)
    }

    logger.log("Initialized with \(_schedule.count) work cycles.")
  }

  deinit {
    self.sleepListener.stopListening()
  }

  /// Set a new schedule of work cycles. This will fully reset the state and
  /// you will need to call `start()` to begin the first work cycle.
  func setSchedule(_ schedule: [WorkCycle<ClockType>]) {
    // This will also reset the `isPaused` state when `startNextWorkCycle` is
    // called because none of the new WorkCycles have been paused yet.
    self.schedule = schedule

    // Reset trackers:
    reset()
    
    printSchedule()
  }
  
  /// Reset the state to start from the beginning. You will need to call start()
  /// to begin the first work cycle.
  func reset() {
    logger.log("Resetting the break schedule state.")
    count = 0  // must be reset in order to start at the beginning of the schedule
    skipped = 0  // must be reset because count was reset
    delayed = 0  // will be reset in startNextWorkCycle anyway
    remainingTime = 0  // will be reset once the first cycle phase changes
    phaseLength = 0  // will be reset once the first cycle phase changes
    isBlocking = false  // will be reset once the first cycle phase changes
  }

  /// Print the current schedule to the console.
  func printSchedule() {
    logger.log("Current schedule:")
    for (index, cycle) in schedule.enumerated() {
      logger.log("  \(index + 1): \(cycle)")
    }
  }

  /// Start the work cycle. If the work cycle has already been started, this will
  /// do nothing. This function is intended to be called when the app starts or when
  /// the schedule is changed.
  func start() {
    if count == 0 {
      // Start the first work cycle.
      logger.log("Kicking off the first work cycle.")
      startNextWorkCycle()
    } else {
      logger.warn(
        "AppState already started with \(count) work cycles. Skipping this start request.")
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

    delayed += 1
    // Keep the current work cycle but rewind to the working phase.
    cycle.startWorking(duration)
  }

  /// Skip the current break and immediately start the working phase of the next
  /// work cycle.
  func skip() {
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
    logger.log("Skipped: \(skipped), Delayed: \(delayed), Completed: \(completed)")
    // Start working in the new cycle.
    c.startWorking(workingDuration)
  }

  /// Updates the AppState based on the current phase of the active work cycle.
  private func onWorkCyclePhaseChange(_ phase: WorkCycle<ClockType>.Phase) {
    switch phase {
    case .idle:
      isBlocking = false
      remainingTime = 0
      phaseLength = 0
    case .working(let remaining):
      isBlocking = false
      remainingTime = remaining
      phaseLength = cycle!.workLength.seconds
    case .waiting:
      isBlocking = false
      remainingTime = 0
      phaseLength = 0
    case .breaking(let remaining):
      isBlocking = true
      remainingTime = remaining
      phaseLength = cycle!.breakLength.seconds
    case .finished:
      isBlocking = false
      remainingTime = 0
      phaseLength = 0
      // Track the number of breaks that were fully completed.
      // completed += 1
      // Start the next work cycle in the schedule.
      Task {
        self.startNextWorkCycle()
      }
    }
  }

  /// Handle changes in the system sleep state (screen locked, system sleep, etc).
  private func onSleepStateChange(_ state: SystemSleepMonitor.SleepState) {
    let now = Date()

    switch state {
    case .awake:
      logger.log("System woke up from sleep.")
      let calendar = Calendar.current
      let isBeforeToday =
        calendar.compare(
          lastSleep,
          to: now,
          toGranularity: .day
        ) == .orderedAscending
      if isBeforeToday {
        logger.log("Different day: resetting the work cycle.")
        reset()
        start()
      } else {
        logger.log("Same day: continuing the last work cycle.")
        // TODO Start from the beginning of the break schedule or
        // restart the current work cycle rather than picking back up
        // in the middle of a work cycle
        resume()
      }
    case .sleeping:
      logger.log("System is going to sleep. Pausing the work cycle.")
      lastSleep = now
      pause()
    }
  }

  /// Stop the current work cycle immediately. This is used to stop timers
  /// without any side effects during shutdown.
  func cancelTimer() {
    cycle?.cancel()
  }
}
