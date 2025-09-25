import Clocks
import Quartz
import Testing

@testable import LookAway

class UserActivityMonitorTestContext {
  let clock: TestClock = TestClock()
  let listener: UserActivityMonitor<TestClock<Duration>>

  init(
    thresholds: [ActivityThreshold] = [],
    getSecondsSinceLastUserInteraction: @escaping UserInteractionCallback = { _ in 10 },
    debug: Bool = false
  ) {
    let logger = Logger(enabled: debug)

    listener = UserActivityMonitor(
      logger: logger,
      thresholds: thresholds,
      getSecondsSinceLastUserInteraction: getSecondsSinceLastUserInteraction,
      clock: clock
    )
  }

  func afterEach() async {
    await clock.run()
  }
}

class UserActivityMonitorCallbackSpy {
  private(set) var calls: [CGEventType] = []
  var interactionTime: TimeInterval = 0
  
  var callCount: Int {
    return calls.count
  }
  
  func callback(type: CGEventType) -> TimeInterval {
    calls.append(type)
    return interactionTime
  }
  
  func clear() {
    calls = []
  }
}

struct UserActivityMonitorTests {
  @Test("Should skip inactivity tracking if no thresholds are configured.")
  func skipInactivityTracking() async throws {
    let spy = UserActivityMonitorCallbackSpy()

    let test = UserActivityMonitorTestContext(
      thresholds: [],
      getSecondsSinceLastUserInteraction: spy.callback,
      debug: true
    )

    try await test.listener.waitForInactivity()

    #expect(spy.callCount == 0)

    await test.afterEach()
  }

  @Test("Should wait for inactivity before returning.")
  func waitForInactivity() async throws {
    // Create an inactivity listener with a couple thresholds.
    let spy = UserActivityMonitorCallbackSpy()
    spy.interactionTime = 0
    let thresholds = [
      ActivityThreshold(event: .keyUp, threshold: 5),
      ActivityThreshold(event: .leftMouseUp, threshold: 10),
    ]
    let test = UserActivityMonitorTestContext(
      thresholds: thresholds,
      getSecondsSinceLastUserInteraction: spy.callback,
      debug: true
    )

    print("Starting test")
    var didFinish = false
    Task {
      print("Starting inactivity listener")
      try await test.listener.waitForInactivity()
      print("Inactivity listener finished")
      didFinish = true
    }

    // Start the activity listener
    await test.clock.advance(by: .seconds(1))

    // Validate that the spy was called for each threshold.
    #expect(spy.callCount == 2)
    #expect(spy.calls.contains(.keyUp))
    #expect(spy.calls.contains(.leftMouseUp))
    #expect(didFinish == false)

    spy.clear()
    
    // Advance the clock to trigger the thresholds.
    await test.clock.advance(by: .seconds(10))
    
    #expect(spy.callCount == 2)
    #expect(spy.calls.contains(.keyUp))
    #expect(spy.calls.contains(.leftMouseUp))
    #expect(didFinish == false)

    // Mimic the user becoming inactive.
    spy.interactionTime = 11
    
    spy.clear()
    
    // Advance to the next inactivity check
    await test.clock.advance(by: .seconds(10))
    
    #expect(spy.callCount == 2)
    #expect(spy.calls.contains(.keyUp))
    #expect(spy.calls.contains(.leftMouseUp))
    #expect(didFinish == true)
  }
}
