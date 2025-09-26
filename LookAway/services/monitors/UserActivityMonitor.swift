import Foundation
import Quartz

/// A callback that will return the number of seconds since some user interaction.
typealias UserInteractionCallback = () -> TimeInterval

/// Configures an event type that can be used to detect user inactivity.
struct ActivityThreshold {
  // For debugging purposes
  let name: String
  /// The length of time that it takes for this indicator to be considered inactive.
  let threshold: TimeInterval
  let callback: UserInteractionCallback
}

private func gcEventSourceCallback(for type: CGEventType) -> UserInteractionCallback {
  return {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
  }
}

/// Watches for user inactivity and notifies when the user has been inactive for the desired duration.
class UserActivityMonitor<ClockType: Clock<Duration>> {
  private let logger: Logging
  private let clock: ClockType
  private let thresholds: [ActivityThreshold]

  init(
    logger: Logging,
    thresholds: [ActivityThreshold]? = nil,
    clock: ClockType? = nil
  ) {
    self.logger = logger
    self.thresholds =
      thresholds ?? [
        ActivityThreshold(
          name: "keyUp",
          threshold: 5,
          callback: gcEventSourceCallback(for: .keyUp)
        ),
        //        ActivityThreshold(
        //          name: "mouseMoved",
        //          threshold: 5,
        //          callback: gcEventSourceCallback(for: .mouseMoved)
        //        ),
        ActivityThreshold(
          name: "leftMouseUp",
          threshold: 4,
          callback: gcEventSourceCallback(for: .leftMouseUp)
        ),
        ActivityThreshold(
          name: "rightMouseUp",
          threshold: 4,
          callback: gcEventSourceCallback(for: .rightMouseUp)
        ),
        ActivityThreshold(
          name: "otherMouseUp",
          threshold: 4,
          callback: gcEventSourceCallback(for: .otherMouseUp)
        ),
      ]
    self.clock = clock ?? ContinuousClock() as! ClockType
  }

  struct InactivityResult {
    let indicator: ActivityThreshold
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
        let lastActivity = $0.callback()
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
