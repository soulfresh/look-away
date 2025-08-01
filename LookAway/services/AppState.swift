import Combine
import Foundation

/// Global application state manager. Used to coordinate when the app is blocking system interaction and provides global state such as the remaining time for the current break.
@MainActor
class AppState: ObservableObject {
  /**
   * When `true`, the application will display the blocking windows that
   * prevent interactions with the rest of the system.
   */
  @Published private(set) var isBlocking: Bool = false
  @Published private(set) var isPaused: Bool = false

  /// The remaining time displayed in the menu bar, driven by the active break.
  @Published private(set) var remainingTime: TimeInterval = 0
  
  /// A timer that can be used for performance measurements.
  public let performance = PerformanceTimer()

  // For now, the schedule contains a single, hardcoded break.
  private var schedule: Break
  // Implicitely unwrapped optional so we can create it with a closer that captures `self` within `init`.
  //  private var schedule: Break!
  private var cancellables = Set<AnyCancellable>()

  /**
   * - Parameter clock: The clock to use for time-based operations.
   */
  init(clock: any Clock<Duration> = ContinuousClock()) {
    // TODO: Make this schedule user-configurable.
    self.schedule = Break(
      frequency: 10,
      duration: 5,
      performance: performance,
      clock: clock
    )

    // Watch for changes in the break phase and update the "blocking" state.
    schedule.$phase
      .receive(on: DispatchQueue.main)
      .sink { [weak self] phase in
        self?.handleBreakPhaseChange(phase)
      }
      .store(in: &cancellables)
    
    // Watch for changes in the break's `isRunning` state and publish that as `isPaused`.
    schedule.$isRunning
      // Map to the inverse of `isRunning`
      .map { !$0 }
      .receive(on: DispatchQueue.main)
      .assign(to: &$isPaused)

    // Start the break cycle.
    Task {
      self.schedule.startWorking()
    }
  }
  
  /// Pause the current break cycle.
  func pause() {
    schedule.pause()
  }

  /// Resume the current break cycle.
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

  /// Start the break portion of the current break cycle.
  func startBreak() {
    schedule.startBreak()
  }

  /// Start the next break cycle. This will enter into the working portion of
  /// that cycle.
  func startWorking() {
    schedule.startWorking()
  }

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
      remainingTime = 0
      // Here you would typically start the next break in the schedule.
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
