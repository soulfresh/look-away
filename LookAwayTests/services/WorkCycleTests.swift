import Clocks
import Combine
import Foundation
import Testing

@testable import LookAway

/// A class to hold the mutable interaction time value so it can be
/// changed between tests.
class InteractionTime {
  var value: TimeInterval

  init(value: TimeInterval) {
    self.value = value
  }
}

final class WorkCycleSpy: WorkCycle<TestClock<Duration>> {
  var cancelCallCount = 0

  override func cancel() {
    cancelCallCount += 1
    super.cancel()
  }
}

class WorkCycleTestContext {
  let clock: BreakClock = BreakClock()
  let interactionTime: InteractionTime
  let brk: WorkCycleSpy

  init(
    initialInteraction: TimeInterval = 10,
    inactivityThresholds: [ActivityThreshold] = [
      ActivityThreshold(
        event: .keyUp,
        threshold: 10
      )
    ],
    debug: Bool = false
  ) {
    // Create a mutable interaction value that can be referenced in our callback.
    let interactionTime = InteractionTime(value: initialInteraction)
    self.interactionTime = interactionTime

    brk = WorkCycleSpy(
      frequency: 100,
      duration: 50,
      logger: Logger(enabled: debug),
      inactivityThresholds: inactivityThresholds,
      clock: clock.clock,
      getSecondsSinceLastUserInteraction: { _ in interactionTime.value }
    )
  }

  func afterEach() async {
    brk.cancel()
    await clock.run()
  }
}

struct WorkCycleTests {
  @Test("Starts in the idle state.")
  func testInitialState() async {
    let test = WorkCycleTestContext()
    let breakInstance = test.brk

    #expect(breakInstance.phase == .idle)
    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.workLength == TimeSpan(value: 100))
    #expect(breakInstance.breakLength == TimeSpan(value: 50))
    #expect(breakInstance.cancelCallCount == 0)

    await test.afterEach()
  }

  @Test("Cancels the timer on destruction.")
  func testCancelOnDestruction() {}

  @Test("Should be able to start working.")
  func testStartWorking() async throws {
    let test = WorkCycleTestContext()
    let clock = test.clock
    let breakInstance = test.brk

    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startWorking()

    // Ensure the asynchronous task has started.
    await clock.tick()

    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .working(remaining: 100))
    #expect(breakInstance.isRunning == true)

    await clock.advanceBy(1)

    #expect(breakInstance.phase == .working(remaining: 99))

    await clock.advanceBy(100)

    // Should continue directly to the breaking phase since the user has
    // been inactive for at least the inactivity threshold.
    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)

    await test.afterEach()
  }

  @Test("Should wait for the user to become inactive before starting the break.")
  func testWaitingPhase() async throws {
    let test = WorkCycleTestContext(
      initialInteraction: 5,
      inactivityThresholds: [ActivityThreshold(event: .keyUp, threshold: 10)],
    )
    let clock = test.clock
    let breakInstance = test.brk

    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startWorking()

    // Ensure the asynchronous task has started.
    await clock.tick()

    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .working(remaining: 100))
    #expect(breakInstance.isRunning == true)

    await clock.advanceBy(1)

    #expect(breakInstance.phase == .working(remaining: 99))

    await clock.advanceBy(100)

    #expect(breakInstance.phase == .waiting)
    #expect(breakInstance.isRunning == true)

    // At this point the user activity has been detected and the inactivity timer
    // has been started with a 5 second wait because the last interaction was 5
    // seconds ago and our threshold is 10 seconds.
    await clock.advanceBy(5)

    #expect(breakInstance.phase == .waiting)
    #expect(breakInstance.isRunning == true)

    // Simulate the user becoming inactive by updating the callback.
    test.interactionTime.value = 11

    // Advance the clock enough for the timer to fire and re-check inactivity.
    await clock.advanceBy(5)

    // Now the break should start.
    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)
  }

  @Test("Should be able to restart the working phase with a given duration while it is running.")
  func testRestartWorking() async {
    let test = WorkCycleTestContext()
    let clock = test.clock
    let breakInstance = test.brk

    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startWorking()

    // Ensure the asynchronous task has started.
    await clock.tick()

    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .working(remaining: 100))
    #expect(breakInstance.isRunning == true)

    await clock.advanceBy(10)

    #expect(breakInstance.phase == .working(remaining: 90))

    breakInstance.startWorking(20)

    #expect(breakInstance.cancelCallCount == 2)

    await clock.tick()

    #expect(breakInstance.phase == .working(remaining: 20))
    #expect(breakInstance.isRunning == true)

    await test.afterEach()
  }

  @Test("Should be able to start a break.")
  func testStartBreak() async {
    let test = WorkCycleTestContext()
    let clock = test.clock
    let breakInstance = test.brk

    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startBreak()

    // Ensure the asynchronous task has started.
    await clock.tick()

    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)

    await clock.advanceBy(1)

    #expect(breakInstance.phase == .breaking(remaining: 49))

    await clock.advanceBy(50)

    #expect(breakInstance.phase == .finished)
    #expect(breakInstance.isRunning == false)

    await test.afterEach()
  }

  @Test("Should be able to transition from working to breaking to finished.")
  func testFullFlow() async {
    let test = WorkCycleTestContext()
    let clock = test.clock
    let breakInstance = test.brk

    breakInstance.startWorking()

    await clock.advanceBy(1)

    #expect(breakInstance.phase == .working(remaining: 99))

    await clock.advanceBy(100)

    #expect(breakInstance.phase == .breaking(remaining: 50))

    await clock.advanceBy(51)

    #expect(breakInstance.phase == .finished)
    #expect(breakInstance.isRunning == false)

    await test.afterEach()
  }

  @Test("Should be able to pause and resume.")
  func testPauseAndResume() async {
    let test = WorkCycleTestContext()
    let clock = test.clock
    let breakInstance = test.brk

    breakInstance.startWorking()

    #expect(breakInstance.cancelCallCount == 1)

    await clock.advanceBy(10)

    #expect(breakInstance.phase == .working(remaining: 90))

    breakInstance.pause()

    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)

    await clock.advanceBy(5)

    #expect(breakInstance.phase == .working(remaining: 90))

    breakInstance.resume()

    await clock.tick()

    #expect(breakInstance.isRunning == true)
    #expect(breakInstance.phase == .working(remaining: 90))

    await clock.advanceBy(5)

    #expect(breakInstance.phase == .working(remaining: 85))

    await test.afterEach()
  }

  @Test("Should be able to reset the break to the beginning.")
  func testReset() async {
    let test = WorkCycleTestContext()
    let clock = test.clock
    let breakInstance = test.brk

    breakInstance.startWorking()

    await clock.tick()
    await clock.advanceBy(10)

    #expect(breakInstance.phase == .working(remaining: 90))
    #expect(breakInstance.isRunning == true)

    breakInstance.reset()

    #expect(breakInstance.phase == .idle)

    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)

    await test.afterEach()
  }

  @Test("Should be able to cancel the timer task without affecting the phase.")
  func testCancelTimerTask() async {
    let test = WorkCycleTestContext()
    let clock = test.clock
    let breakInstance = test.brk

    breakInstance.startWorking()

    await clock.tick()
    await clock.advanceBy(10)

    #expect(breakInstance.phase == .working(remaining: 90))
    #expect(breakInstance.isRunning == true)

    breakInstance.cancel()

    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)

    await clock.advanceBy(5)

    #expect(breakInstance.phase == .working(remaining: 90))

    await test.afterEach()
  }
}
