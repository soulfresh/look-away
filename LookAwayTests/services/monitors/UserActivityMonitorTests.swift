import Clocks
import Quartz
import Testing

@testable import LookAway

class UserActivityMonitorTestContext {
  let clock: TestClock = TestClock()
  let listener: UserActivityMonitor<TestClock<Duration>>

  init(
    thresholds: [ActivityThreshold] = [],
    debug: Bool = false
  ) {
    let logger = Logger(enabled: debug)

    listener = UserActivityMonitor(
      logger: logger,
      thresholds: thresholds,
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
      ActivityThreshold(
        name: "keyUp",
        threshold: 5,
        callback: { spy.callback(type: .keyUp) }
      ),
      ActivityThreshold(
        name: "leftMouseUp",
        threshold: 10,
        callback: { spy.callback(type: .leftMouseUp) }
      ),
    ]
    let test = UserActivityMonitorTestContext(
      thresholds: thresholds,
      debug: true
    )

    var didFinish = false
    Task {
      try await test.listener.waitForInactivity()
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
