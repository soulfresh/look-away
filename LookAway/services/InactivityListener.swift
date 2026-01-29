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
    // Create continuations that we can control from the cancellation handler
    var cameraContinuation: AsyncStream<Bool>.Continuation?
    var microphoneContinuation: AsyncStream<Bool>.Continuation?
    
    // Create AsyncStreams to receive camera and microphone connection state changes
    let cameraStateChanged = AsyncStream<Bool> { continuation in
      cameraContinuation = continuation
      cameraMonitor.startListening { state in
        let isActive = state == .connected
        self.cameraIsActive = isActive
        continuation.yield(isActive)
      }
      // Immediately yield the current camera state so we don't miss the initial state
      continuation.yield(self.cameraMonitor.isConnected)
    }

    let microphoneStateChanged = AsyncStream<Bool> { continuation in
      microphoneContinuation = continuation
      microphoneMonitor.startListening { state in
        let isActive = state == .connected
        self.microphoneIsActive = isActive
        continuation.yield(isActive)
      }
      // Immediately yield the current microphone state so we don't miss the initial state
      continuation.yield(self.microphoneMonitor.isConnected)
    }

    // Wrap the stream iteration in a cancellation handler to ensure cleanup
    try await withTaskCancellationHandler {
      // Merge both streams to monitor any A/V device changes
      for await (cameraActive, micActive) in merge(cameraStateChanged, microphoneStateChanged) {
        // Check if the task has been cancelled (e.g., system going to sleep)
        try Task.checkCancellation()

        let anyAVDeviceActive = cameraActive || micActive

        if !anyAVDeviceActive {
          try await userActivityMonitor.waitForInactivity()
          // Double-check A/V devices are still off after inactivity
          if !self.cameraIsActive && !self.microphoneIsActive {
            logger.log("User is inactive and all A/V devices are disconnected.")
            cameraMonitor.stopListening()
            microphoneMonitor.stopListening()
            return
          }
        }
        // If any A/V device is active, keep waiting for disconnect
      }
    } onCancel: {
      // When the task is cancelled, finish the streams and cleanup
      logger.log("InactivityListener task was cancelled.")
      cameraContinuation?.finish()
      microphoneContinuation?.finish()
      cameraMonitor.stopListening()
      microphoneMonitor.stopListening()
    }
  }

  /// Merges two AsyncStreams into a single stream of tuples
  private func merge<T>(_ stream1: AsyncStream<T>, _ stream2: AsyncStream<T>) -> AsyncStream<(T, T)>
  {
    AsyncStream { continuation in
      var value1: T? = nil
      var value2: T? = nil

      Task {
        for await value in stream1 {
          value1 = value
          if let v1 = value1, let v2 = value2 {
            continuation.yield((v1, v2))
          }
        }
      }

      Task {
        for await value in stream2 {
          value2 = value
          if let v1 = value1, let v2 = value2 {
            continuation.yield((v1, v2))
          }
        }
      }
    }
  }
}
