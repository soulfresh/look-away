import Foundation
import Quartz

typealias UserInteractionCallback = () -> TimeInterval

/// Watches for user inactivity and notifies when the user has been inactive for the desired duration.
class InactivityListener<ClockType: Clock<Duration>> {
  private let logger: Logging
  private let duration: TimeInterval
  private let clock: ClockType
  private let getSecondsSinceLastUserInteraction: UserInteractionCallback

  init(
    duration: TimeInterval,
    logger: Logging,
    /// A callback that can be used to determine the number of seconds since the
    /// last user activity. Allows you to mock CGEventSource for testing.
    getSecondsSinceLastUserInteraction: UserInteractionCallback? = nil,
    clock: ClockType? = nil
  ) {
    self.duration = duration
    self.logger = logger
    self.getSecondsSinceLastUserInteraction =
      getSecondsSinceLastUserInteraction ?? {
        CGEventSource.secondsSinceLastEventType(
          .combinedSessionState,
          eventType: .keyUp
        )
      }
    self.clock = clock ?? ContinuousClock() as! ClockType
  }

  func waitForInactivity() async throws {
    while true {
      if Task.isCancelled {
        logger.log("InactivityListener task was cancelled.")
        throw CancellationError()
      }
      let secondsSinceLastKey = getSecondsSinceLastUserInteraction()
      let timeRemaining = duration - secondsSinceLastKey
      logger.log("Checking for user inactivity: last keyUp \(secondsSinceLastKey) seconds (threshold: \(duration))")
      
      if timeRemaining <= 0 {
        logger.log("User inactivity detected")
        return
      }
      
      logger.log("User activity detected. Sleeping for \(timeRemaining) seconds")
      try await clock.sleep(until: clock.now.advanced(by: .seconds(timeRemaining)), tolerance: .zero)
    }
  }
}
