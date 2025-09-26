import Testing
import Clocks

@testable import LookAway

struct InactivityListenerTestContext {
  let clock: TestClock<Duration>
  let listener: InactivityListener<TestClock<Duration>>
  let cameraProvider: MockCameraDeviceProvider
  let lastUserInteraction: InteractionTime

  init(
    interactionThreshold: Double = 10,
    lastInteraction: Double = 5,
    cameras: [CameraActivityMonitor.CameraInfo] = [
      CameraActivityMonitor.CameraInfo(
        id: 0,
        uniqueID: "mock-uid-0",
        name: "Mock Camera",
        manufacturer: "Mock Manufacturer",
        isRunning: false,
        isVirtual: false,
        creator: "Mock",
        category: "Camera",
        type: "USB",
        modelID: "MockModel"
      )
    ],
    debug: Bool = false
  ) {
    let logger = Logger(enabled: debug)
    let clock = TestClock()
    self.clock = clock
    
    let interactionTime = InteractionTime(value: lastInteraction)
    self.lastUserInteraction = interactionTime
    
    self.cameraProvider = MockCameraDeviceProvider(
      devices: cameras
    )
    self.listener = InactivityListener(
      logger: logger,
      inactivityThresholds: [
        ActivityThreshold(
          name: "keyUp",
          threshold: interactionThreshold,
          callback: { interactionTime.value },
        )
      ],
      clock: clock,
      cameraProvider: cameraProvider,
    )
  }
}

struct InactivityListenerTests {

  @Test("should be able to listen for user inactivity events when cameras never turn on")
  func testInactivity() async throws {
    let test = InactivityListenerTestContext(
      interactionThreshold: 10,
      lastInteraction: 5,
    )

    var didFinish = false
    let task = Task {
      try await test.listener.waitForInactivity()
      didFinish = true
    }
    
    // Verify the task is still running
    #expect(didFinish == false)
    
    // Advance time by the activity threshold
    await test.clock.advance(by: .seconds(10))
    
    // Verify the task is still running
    #expect(didFinish == false)
    
    // Simulate user inactivity
    test.lastUserInteraction.value = 20
    
    await test.clock.advance(by: .seconds(10))
    
    #expect(didFinish == true)
    
    task.cancel()
  }

  @Test("should handle systems with no cameras")
  func testNoCameras() async throws {
    let test = InactivityListenerTestContext(
      interactionThreshold: 10,
      lastInteraction: 5,
      cameras: []
    )

    var didFinish = false
    let task = Task {
      try await test.listener.waitForInactivity()
      didFinish = true
    }
    
    #expect(didFinish == false)
    
    // User will report as having interacted recently
    await test.clock.advance(by: .seconds(10))

    #expect(didFinish == false)
    
    // Simulate user inactivity
    test.lastUserInteraction.value = 20
    
    await test.clock.advance(by: .seconds(10))
    
    #expect(didFinish == true)

    task.cancel()
  }

  @Test("should hande the case that the camera is active when monitoring starts")
  func testCameraActiveAtStart() async throws {
    let test = InactivityListenerTestContext(
      interactionThreshold: 10,
      lastInteraction: 5,
      cameras: [
        CameraActivityMonitor.CameraInfo(
          id: 0,
          uniqueID: "mock-uid-0",
          name: "Mock Camera",
          manufacturer: "Mock Manufacturer",
          isRunning: true,
          isVirtual: false,
          creator: "Mock",
          category: "Camera",
          type: "USB",
          modelID: "MockModel"
        )
      ]
    )

    var didFinish = false
    let task = Task {
      try await test.listener.waitForInactivity()
      didFinish = true
    }
    
    #expect(didFinish == false)

    // It doesn't matter how long we wait if the carmera is running
    await test.clock.advance(by: .seconds(20))
    
    #expect(didFinish == false)
    
    test.lastUserInteraction.value = 11
    test.cameraProvider.emitEvent(deviceID: 0, newState: false)
    
    // Now when we advance past the threshold, it should finish
    await test.clock.advance(by: .seconds(10))
    
    #expect(didFinish == true)

    task.cancel()
  }

  @Test("should handle complex scenarios of camera and user activity")
  func testComplexScenarios() async throws {
    let test = InactivityListenerTestContext(
      interactionThreshold: 10,
      lastInteraction: 5,
    )

    var didFinish = false
    let task = Task {
      try await test.listener.waitForInactivity()
      didFinish = true
    }
    
    #expect(didFinish == false)
    
    // User is typing
    await test.clock.advance(by: .seconds(10))
    #expect(didFinish == false)

    // Camera turns on
    test.cameraProvider.emitEvent(deviceID: 0, newState: true)
    await test.clock.advance(by: .seconds(10))
    
    #expect(didFinish == false)

    // User stops typing
    test.lastUserInteraction.value = 20
    await test.clock.advance(by: .seconds(10))
    
    #expect(didFinish == false)
    
    // Camera disconnects while user clicks around
    test.lastUserInteraction.value = 5
    test.cameraProvider.emitEvent(deviceID: 0, newState: false)
    await test.clock.advance(by: .seconds(10))

    #expect(didFinish == false)
    
    // User stops clicking
    test.lastUserInteraction.value = 20
    await test.clock.advance(by: .seconds(10))
    
    // Verify that inactivity triggers after threshold
    #expect(didFinish == true)

    task.cancel()
  }
}
