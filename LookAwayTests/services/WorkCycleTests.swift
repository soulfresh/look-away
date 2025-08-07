import Clocks
import Combine
import Foundation
import Testing

@testable import LookAway

final class WorkCycleSpy: WorkCycle {
  var cancelCallCount = 0

  override func cancel() {
    cancelCallCount += 1
    super.cancel()
  }
}

class WorkCycleTestContext {
  let clock: BreakClock = BreakClock()
  let brk: WorkCycleSpy

  init(debug: Bool = false) {
    brk = WorkCycleSpy(
      frequency: 100,
      duration: 50,
      logger: Logger(enabled: debug),
      clock: clock.clock
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
    #expect(breakInstance.frequency == TimeSpan(value: 100))
    #expect(breakInstance.duration == TimeSpan(value: 50))
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

    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)

    await test.afterEach()
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
