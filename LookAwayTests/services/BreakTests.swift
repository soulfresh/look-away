import Testing
@testable import LookAway
import Combine
import Clocks

// Add Equatable conformance to Break.Phase for testing
extension Break.Phase: Equatable {
  public static func == (lhs: Break.Phase, rhs: Break.Phase) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle):
      return true
    case (.working(let lhsRemaining), .working(let rhsRemaining)):
      return lhsRemaining == rhsRemaining
    case (.breaking(let lhsRemaining), .breaking(let rhsRemaining)):
      return lhsRemaining == rhsRemaining
    case (.finished, .finished):
      return true
    default:
      return false
    }
  }
}

final class BreakSpy: Break {
  var cancelCallCount = 0
  
  override func cancel() {
    cancelCallCount += 1
    super.cancel()
  }
}

struct BreakTests {

    @Test("Starts in the idle state.")
    func testInitialState() {
      let clock = TestClock()
      let breakInstance = BreakSpy(
        frequency: 100,
        duration: 50,
        performance: PerformanceTimer(),
        clock: clock
      )

      #expect(breakInstance.phase == .idle)
      #expect(breakInstance.isRunning == false)
      #expect(breakInstance.frequency == 100)
      #expect(breakInstance.duration == 50)
      #expect(breakInstance.cancelCallCount == 0)
    }
  
  @Test("Cancels the timer on destruction.")
  func testCancelOnDestruction() { }
  
  @Test("Should be able to start working.")
  func testStartWorking() async {
    let clock = TestClock()
    let breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )
    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startWorking()
    
    // Ensure the asynchronous task has started.
    await clock.advance(by: .zero)
    
    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .working(remaining: 100))
    #expect(breakInstance.isRunning == true)
    
    await clock.advance(by: .seconds(1))
    
    #expect(breakInstance.phase == .working(remaining: 99))
    
    await clock.advance(by: .seconds(100))
    
    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)
  }
  
  @Test("Should be able to restart the working phase with a given duration while it is running.")
  func testRestartWorking() async {
    let clock = TestClock()
    let breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )
    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startWorking()
    
    // Ensure the asynchronous task has started.
    await clock.advance(by: .zero)
    
    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .working(remaining: 100))
    #expect(breakInstance.isRunning == true)
    
    await clock.advance(by: .seconds(10))
    
    #expect(breakInstance.phase == .working(remaining: 90))
    
    breakInstance.startWorking(20)
    
    #expect(breakInstance.cancelCallCount == 2)
    
    await clock.advance(by: .zero)
    
    #expect(breakInstance.phase == .working(remaining: 20))
    #expect(breakInstance.isRunning == true)
  }

  @Test("Should be able to start a break.")
  func testStartBreak() async {
    let clock = TestClock()
    let breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )
    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startBreak()
    
    // Ensure the asynchronous task has started.
    await clock.advance(by: .zero)
    
    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)
    
    await clock.advance(by: .seconds(1))
    
    #expect(breakInstance.phase == .breaking(remaining: 49))
    
    await clock.advance(by: .seconds(50))
    
    #expect(breakInstance.phase == .finished)
    #expect(breakInstance.isRunning == false)
  }
  
  @Test("Should be able to transition from working to breaking to finished.")
  func testFullFlow() async {
    let clock = TestClock()
    let breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )

    breakInstance.startWorking()
    
    await clock.advance(by: .seconds(1))
    
    #expect(breakInstance.phase == .working(remaining: 99))
    
    await clock.advance(by: .seconds(100))
    
    #expect(breakInstance.phase == .breaking(remaining: 50))
    
    await clock.advance(by: .seconds(51))
    
    #expect(breakInstance.phase == .finished)
    #expect(breakInstance.isRunning == false)
  }

  @Test("Should be able to pause and resume.")
  func testPauseAndResume() async {
    let clock = TestClock()
    let breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )

    breakInstance.startWorking()
    
    #expect(breakInstance.cancelCallCount == 1)

    await clock.advance(by: .seconds(10))
    
    #expect(breakInstance.phase == .working(remaining: 90))
    
    breakInstance.pause()
    
    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)
    
    await clock.advance(by: .seconds(5))
    
    #expect(breakInstance.phase == .working(remaining: 90))
    
    breakInstance.resume()
    
    await clock.advance(by: .zero)
    
    #expect(breakInstance.isRunning == true)
    #expect(breakInstance.phase == .working(remaining: 90))
    
    await clock.advance(by: .seconds(5))
    
    #expect(breakInstance.phase == .working(remaining: 85))
  }
  
  @Test("Should be able to reset the break to the beginning.")
  func testReset() async {
    // 1. Create a Break instance with a mock clock.
    let clock = TestClock()
    let breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )

    // 2. Start the working phase.
    breakInstance.startWorking()
    await clock.advance(by: .zero)

    // 4. Run the timer for several seconds.
    await clock.advance(by: .seconds(10))

    // 5. Expect that the current phase is "working" and that there is a timer task running.
    #expect(breakInstance.phase == .working(remaining: 90))
    #expect(breakInstance.isRunning == true)

    // 6. Reset the break.
    breakInstance.reset()

    // 7. Expect that the current phase is "idle" with no time remaining.
    #expect(breakInstance.phase == .idle)

    // 8. Expect that the timer task is nil.
    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)
  }
  
  @Test("Should be able to cancel the timer task without affecting the phase.")
  func testCancelTimerTask() async {
    // 1. Create a Break instance with a mock clock.
    let clock = TestClock()
    let breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )

    // 2. Start the working phase.
    breakInstance.startWorking()
    await clock.advance(by: .zero)

    // 3. Run the timer for several seconds.
    await clock.advance(by: .seconds(10))

    // 4. Expect that the current phase is still "working" and that there is a timer running.
    #expect(breakInstance.phase == .working(remaining: 90))
    #expect(breakInstance.isRunning == true)

    // 6. Cancel the timer task.
    breakInstance.cancel()

    // 7. Expect that the timer task is nil.
    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)

    // 8. Run the clock for a few more seconds.
    await clock.advance(by: .seconds(5))

    // 9. Expect that the current phase is still "working" and that the phase remaining time is unchanged.
    #expect(breakInstance.phase == .working(remaining: 90))
  }
}
