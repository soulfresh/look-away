import Foundation
import Quartz

typealias UserInteractionCallback = (_: CGEventType) -> TimeInterval

/// Configures an event type that can be used to detect user inactivity.
struct InactivityIndicator {
  let event: CGEventType
  /// The length of time that it takes for this indicator to be considered inactive.
  let threshold: TimeInterval
}

/// Watches for user inactivity and notifies when the user has been inactive for the desired duration.
class InactivityListener<ClockType: Clock<Duration>> {
  private let logger: Logging
  private let clock: ClockType
  private let getSecondsSinceLastUserInteraction: UserInteractionCallback
  private let thresholds: [InactivityIndicator]

  init(
    logger: Logging,
    thresholds: [InactivityIndicator]? = nil,
    /// A callback that can be used to determine the number of seconds since the
    /// last user activity. Allows you to mock CGEventSource for testing.
    getSecondsSinceLastUserInteraction: UserInteractionCallback? = nil,
    clock: ClockType? = nil
  ) {
    self.logger = logger
    self.thresholds = thresholds ?? [
      InactivityIndicator(event: .keyUp, threshold: 5),
//      InactivityIndicator(event: .mouseMoved, threshold: 5),
      InactivityIndicator(event: .leftMouseUp, threshold: 4),
      InactivityIndicator(event: .rightMouseUp, threshold: 4),
      InactivityIndicator(event: .otherMouseUp, threshold: 4),
    ]
    self.getSecondsSinceLastUserInteraction =
      getSecondsSinceLastUserInteraction ?? { type in
        CGEventSource.secondsSinceLastEventType(
          .combinedSessionState,
          eventType: type
        )
      }
    self.clock = clock ?? ContinuousClock() as! ClockType
  }

  struct InactivityResult {
    let indicator: InactivityIndicator
    let lastActivity: TimeInterval
    let timeRemaining: TimeInterval
    let isInactive: Bool
  }

  func waitForInactivity() async throws {
    // If there are no thresholds, skip activity tracking.
    if thresholds.isEmpty {
      logger.warn("No inactivity thresholds configured, skipping inactivity tracking.")
      return
    }
    
    while true {
      if Task.isCancelled {
        logger.log("InactivityListener task was cancelled.")
        throw CancellationError()
      }
      
      let measurements = thresholds.map {
        let lastActivity = getSecondsSinceLastUserInteraction($0.event)
        return InactivityResult(
          indicator: $0,
          lastActivity: lastActivity,
          timeRemaining: $0.threshold - lastActivity,
          isInactive: lastActivity >= $0.threshold,
        )
      }
      
      if measurements.allSatisfy({ $0.isInactive }) {
        logger.log("User inactivity detected")
        return
      }

      // Get the largest time remaining across all indicators.
      let timeRemaining = measurements.map { $0.timeRemaining }.max()!
        
      logger.log("User activity detected. Sleeping for \(timeRemaining) seconds")
      try await clock.sleep(
        until: clock.now.advanced(by: .seconds(timeRemaining)), tolerance: .zero)
    }
  }
}
