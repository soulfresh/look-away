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

  /// The current index in the schedule (0-based).
  private(set) var index: Int = -1

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
    reset(to: .appStart)

    printSchedule()
  }

  enum ResetType {
    /// Reset the entire state as if the app just started. This will reset the
    /// break counts.
    case appStart
    /// Reset to the start of the schedule, but keep the break counts.
    case scheduleStart
    /// Reset to the start of the current work cycle.
    case cycleStart
  }

  /// Reset the state to start from the beginning. You will need to call start()
  /// to begin the first work cycle.
  func reset(to: ResetType) {
    switch to {
    case .appStart:
      logger.log("Reset break schedule state.")
      count = 0  // must be reset in order to start at the beginning of the schedule
      index = -1  // will be set to 0 when the first cycle starts
      skipped = 0  // must be reset because count was reset
      delayed = 0  // will be reset in startNextWorkCycle anyway
    case .scheduleStart:
      logger.log("Reset to start of schedule.")
      count = -1  // must be reset in order to start at the beginning of the
    case .cycleStart:
      // Don't reset count - we want to stay on the current work cycle
      logger.log("Reset to start of current work cycle.")
    }

    remainingTime = 0  // will be reset once the first cycle phase changes
    phaseLength = 0  // will be reset once the first cycle phase changes
    isBlocking = false  // will be reset once the first cycle phase changes
    isPaused = false
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
      startWorkCycle()
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

  /// Restart the entire schedule from the beginning.
  func restartSchedule(from: ResetType) {
    reset(to: from)
    startWorkCycle()
  }

  /// Restart the current work cycle from the beginning of the working phase.
  func restartWorkCycle() {
    reset(to: .cycleStart)
    cycle?.startWorking()
  }

  /// Start the break portion of the current work cycle.
  func startBreak(_ breakDuration: TimeInterval? = nil) {
    cycle?.startBreak(breakDuration)
  }

  /// Start the break at the given index in the schedule.
  func startBreak(at newIndex: Int) {
    startWorkCycle(atIndex: newIndex, startInBreak: true)
  }

  /// Start the next "long" break. This will find the longest break in the schedule
  /// and advance to the next work cycle that has that break length. If we are in the
  /// work or break cycle of a "longest break", then we either start or continue the current break.
  func startLongBreak() {
    // Find the longest break in the schedule.
    let longestBreakLength =
      schedule
      .map { $0.breakLength.seconds }
      .max()

    guard let longestBreakLength = longestBreakLength else {
      logger.warn("Unable to find the longest break in the schedule. \(schedule)")
      return
    }

    // Find the next break in the schedule (including the current one) that has
    // a break length equal to the longest break length.
    // Search starting from current index, wrapping around.
    let scheduleCount = schedule.count
    for offset in 0..<scheduleCount {
      // If we are currently in a break, look for the next cycle after this one.
      // Otherwise, consider the current cycle as well. It's possible that
      // we are already taking the longest break, in which case we should
      // just end up staing in this break.
      let start = isBlocking ? 1 : 0
      let searchIndex = (start + index + offset) % scheduleCount
      if schedule[searchIndex].breakLength.seconds == longestBreakLength {
        // Found the next work cycle with the longest break.
        // Jump to this cycle and start its break.
        // index = searchIndex
        // logger.log("Starting long break at cycle \(count) [index: \(index)]")
        startBreak(at: searchIndex)
        return
      }
    }

    logger.warn("We are already in the longest break. No action taken.")
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
    startWorkCycle()
  }

  /// Start a work cycle at the specified index, or the next work cycle if no
  /// index is provided.
  ///
  /// - Parameter atIndex: The index in the schedule to jump to. If nil, advances
  ///     to the next work cycle.
  /// - Parameter startInBreak: If true, starts the cycle in the break phase.
  ///     Otherwise, starts in the working phase.
  private func startWorkCycle(atIndex: Int? = nil, startInBreak: Bool = false) {
    guard schedule.count > 0 else {
      logger.warn("No work cycles in the schedule. Cannot start next work cycle.")
      return
    }

    logger.log("Next Work Cycle: Shutting down the current work cycle.")

    // Stop listening to the old work cycle.
    cancellables.forEach { $0.cancel() }
    cancellables.removeAll()

    // Reset all work cycles to idle.
    schedule.forEach { $0.reset() }

    // Reset the delayed counter
    delayed = 0

    // Advance to the specified or next work cycle in the schedule.
    count += 1
    if let atIndex = atIndex {
      index = atIndex % schedule.count
    } else {
      index = (index + 1) % schedule.count
    }

    // This should never happen given the guard at the beginning of this function.
    guard let c = cycle else {
      logger.error("Unable to get the current work cycle at index \(index) of \(schedule.count).")
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
    // Start the cycle in the appropriate phase.
    if startInBreak {
      c.startBreak()
    } else {
      c.startWorking()
    }
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
        self.startWorkCycle()
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
        logger.log("Different day: resetting state.")
        restartSchedule(from: .appStart)
      } else {
        logger.log("Same day: starting schedule from beginning.")
        restartSchedule(from: .scheduleStart)
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
