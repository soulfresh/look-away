import Combine
import Foundation

/// Global application state manager. Used to coordinate when the app is
/// blocking system interaction and provides global state such as the remaining
/// time for the current break.
@MainActor
class AppState: ObservableObject {
  /// Whether or not to show the settings window.
  @Published var showSettings: Bool = false
  
  /// The schedule instance used to manage work/break cycles.
  let schedule: BreakSchedule

  /**
   * - Parameter schedule: The schedule of work cycles to follow.
   * - Parameter logger: A logger to use for debugging and performance measurements.
   */
  init(
    schedule _schedule: [WorkCycle],
    logger: Logging,
  ) {
    self.schedule = BreakSchedule(schedule: _schedule, logger: logger)
      

    logger.log("Initialized with \(_schedule.count) work cycles.")
  }
}
