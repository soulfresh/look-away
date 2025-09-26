import Foundation
import Clocks

class InactivityListener<ClockType: Clock<Duration>> {
  private let logger: Logging
  private var cameraIsActive: Bool
  private let cameraMonitor: CameraActivityMonitor
  private let userActivityMonitor: UserActivityMonitor<ClockType>

  init(
    logger: Logging,
    inactivityThresholds: [ActivityThreshold]? = nil,
    clock: ClockType? = nil,
    cameraProvider: DeviceProviderProtocol? = nil,
  ) {
    self.logger = logger
    self.cameraMonitor = CameraActivityMonitor(
      logger: LogWrapper(
        logger: logger, label: "Camera"
      ),
      deviceProvider: cameraProvider,
    )
    self.userActivityMonitor = UserActivityMonitor<ClockType>(
      logger: LogWrapper(logger: logger, label: "UserActivity"),
      thresholds: inactivityThresholds,
      clock: clock
    )
    self.cameraIsActive = cameraMonitor.isConnected
  }

  func waitForInactivity() async throws {
    // Create an AsyncStream to receive camera connection state changes
    let cameraStateChanged = AsyncStream<Bool> { continuation in
      cameraMonitor.startListening { state in
        let isActive = state == .connected
        self.cameraIsActive = isActive
        continuation.yield(isActive)
      }
      // Immediately yield the current camera state so we don't miss the initial state
      continuation.yield(self.cameraMonitor.isConnected)
    }

    for await isActive in cameraStateChanged {
      if !isActive {
        try await userActivityMonitor.waitForInactivity()
        // Double-check camera is still off after inactivity
        if !self.cameraIsActive {
          logger.log("User is inactive and all A/V devices are disconnected.")
          cameraMonitor.stopListening()
          return
        }
      }
      // If camera is active, keep waiting for disconnect
    }
  }
}
