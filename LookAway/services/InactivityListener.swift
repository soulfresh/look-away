import AsyncAlgorithms
import Clocks
import Foundation

class InactivityListener<ClockType: Clock<Duration>> {
  private let logger: Logging
  private var cameraIsActive: Bool
  private var microphoneIsActive: Bool
  private let cameraMonitor: CameraActivityMonitor
  private let microphoneMonitor: MicrophoneActivityMonitor
  private let userActivityMonitor: UserActivityMonitor<ClockType>

  init(
    logger: Logging,
    inactivityThresholds: [ActivityThreshold]? = nil,
    clock: ClockType? = nil,
    cameraProvider: CameraDeviceProvider? = nil,
    microphoneProvider: AudioDeviceProvider? = nil
  ) {
    self.logger = logger
    self.cameraMonitor = CameraActivityMonitor(
      logger: LogWrapper(
        logger: logger, label: "Camera"
      ),
      deviceProvider: cameraProvider,
    )
    self.microphoneMonitor = MicrophoneActivityMonitor(
      logger: LogWrapper(
        logger: logger, label: "Microphone"
      ),
      deviceProvider: microphoneProvider
    )
    self.userActivityMonitor = UserActivityMonitor<ClockType>(
      logger: LogWrapper(logger: logger, label: "UserActivity"),
      thresholds: inactivityThresholds,
      clock: clock
    )
    self.cameraIsActive = cameraMonitor.isConnected
    self.microphoneIsActive = microphoneMonitor.isConnected
  }

  func waitForInactivity() async throws {
    // Ensure monitors are stopped when this function exits, whether normally or via cancellation
    defer {
      cameraMonitor.stopListening()
      microphoneMonitor.stopListening()
    }

    // Create AsyncStreams to receive camera and microphone connection state changes
    let cameraStateChanged = AsyncStream<Bool> { continuation in
      cameraMonitor.startListening { state in
        let isActive = state == .connected
        self.cameraIsActive = isActive
        continuation.yield(isActive)
      }
      // Immediately yield the current camera state so we don't miss the initial state
      continuation.yield(self.cameraMonitor.isConnected)
    }

    let microphoneStateChanged = AsyncStream<Bool> { continuation in
      microphoneMonitor.startListening { state in
        let isActive = state == .connected
        self.microphoneIsActive = isActive
        continuation.yield(isActive)
      }
      // Immediately yield the current microphone state so we don't miss the initial state
      continuation.yield(self.microphoneMonitor.isConnected)
    }

    // Combine both streams to monitor any A/V device changes
    for await (cameraActive, micActive) in combineLatest(cameraStateChanged, microphoneStateChanged)
    {
      try Task.checkCancellation()

      let anyAVDeviceActive = cameraActive || micActive

      if !anyAVDeviceActive {
        try await userActivityMonitor.waitForInactivity()
        // Double-check A/V devices are still off after inactivity
        if !self.cameraIsActive && !self.microphoneIsActive {
          logger.log("User is inactive and all A/V devices are disconnected.")
          return
        }
      }
      // If any A/V device is active, keep waiting for disconnect
    }

    // If we exited the loop due to cancellation, throw so callers know we didn't
    // complete normally (i.e., user did not become inactive)
    try Task.checkCancellation()
  }
}
