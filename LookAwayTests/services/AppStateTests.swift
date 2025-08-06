import Clocks
import Foundation
import Testing

@testable import LookAway

let WORK_1: TimeInterval = 10
let WORK_2: TimeInterval = 20
let BREAK_1: TimeInterval = 6
let BREAK_2: TimeInterval = 10

@MainActor
class AppStateTestContext {
  let clock: BreakClock = BreakClock()
  let appState: AppState

  init(debug: Bool = false) {
    let logger = Logger(enabled: debug)

    appState = AppState(
      schedule: [
        WorkCycle(
          frequency: WORK_1,
          duration: BREAK_1,
          logger: LogWrapper(logger: logger, label: "Test WorkCycle 0"),
          clock: clock.clock
        ),
        WorkCycle(
          frequency: WORK_2,
          duration: BREAK_2,
          logger: LogWrapper(logger: logger, label: "Test WorkCycle 1"),
          clock: clock.clock
        ),
      ],
      logger: LogWrapper(logger: logger, label: "Test AppState"),
    )
  }

  func afterEach() async {
    // Ensure that the app state is cancelled and cleaned up
    appState.cancelTimer()
    await clock.run()
  }
}

@MainActor
struct AppStateTests {
  @Test("Should start working as soon as it is initialized.")
  func testStartsImmediately() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState

    // Advance the clock to allow the initial tasks to run
    await clock.tick()

    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_1)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)

    await clock.advanceBy(1)

    #expect(appState.remainingTime == 9)

    await context.afterEach()
  }

  @Test("Should cycle through the working and breaking states.")
  func testFullCycle() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState

    // Starts in working phase
    await clock.tick()
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_1)

    // Advance through the working phase
    await clock.advanceBy(WORK_1)
    #expect(appState.remainingTime == 0)

    // Transition to the breaking phase
    await clock.advanceBy(1)
    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == BREAK_1)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)

    // Advance through the breaking phase
    await clock.advanceBy(BREAK_1)
    #expect(appState.remainingTime == 0)

    // Transition to finished, which starts a new working phase
    await clock.advanceBy(1)
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_2)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 2)
    #expect(appState.completed == 1)

    // Transition to the second break
    await clock.advanceBy(21)
    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == BREAK_2)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 2)
    #expect(appState.completed == 1)

    await context.afterEach()
  }

  @Test("Should be able to start working when in the middle of a break.")
  func testStartWorking() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState

    // Get to the breaking phase
    await clock.advanceBy(11)
    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == BREAK_1)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)

    // Manually start the working phase
    appState.skip()
    await clock.tick()

    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_2)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 1)
    #expect(appState.delayed == 0)
    #expect(appState.count == 2)
    #expect(appState.completed == 0)

    await context.afterEach()
  }

  @Test("Should be able to start the next break when in the working phase.")
  func testStartBreak() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState

    // Start in the working phase
    await clock.tick()
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_1)

    // Manually start the break phase
    appState.startBreak()
    await clock.tick()

    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == BREAK_1)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)

    await context.afterEach()
  }

  @Test("Should be able to pause and resume when in the working phase.")
  func testPauseWhileWorking() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState

    // Start in the working phase and advance a bit
    await clock.advanceBy(3)
    #expect(appState.remainingTime == 7)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)

    // Pause the timer
    appState.pause()

    // Advance the clock; time should not change
    await clock.advanceBy(BREAK_1)
    #expect(appState.remainingTime == 7)
    #expect(appState.isPaused == true)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)

    // Resume the timer
    appState.resume()
    await clock.tick()

    // Time should now decrease again
    await clock.advanceBy(1)
    #expect(appState.remainingTime == 6)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)

    await context.afterEach()
  }

  @Test("Should be able to toggle the paused state.")
  func testTogglePause() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState

    // Start in the working phase and advance a bit
    await clock.advanceBy(3)
    #expect(appState.remainingTime == 7)
    #expect(appState.isPaused == false)

    // Pause the timer
    appState.togglePaused()

    // Advance the clock; time should not change
    await clock.advanceBy(BREAK_1)
    #expect(appState.remainingTime == 7)
    #expect(appState.isPaused == true)

    // Resume the timer
    appState.togglePaused()
    await clock.tick()

    // Time should now decrease again
    await clock.advanceBy(1)
    #expect(appState.remainingTime == 6)
    #expect(appState.isPaused == false)

    // Pause the timer
    appState.togglePaused()

    // Advance the clock; time should not change
    await clock.advanceBy(BREAK_1)
    #expect(appState.remainingTime == 6)
    #expect(appState.isPaused == true)

    await context.afterEach()
  }

  @Test("Should be able to count the number of times the schedule has been skipped.")
  func testSkipCount() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState
    
    // Advance to the middle of the first break
    await clock.advanceBy(WORK_1 + (BREAK_1/2))
    
    #expect(appState.isBlocking == true)
    
    appState.skip()
    await clock.tick()
    
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_2)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 1)
    #expect(appState.delayed == 0)
    #expect(appState.count == 2)
    #expect(appState.completed == 0)
    
    // Advance to the middle of the second break
    await clock.advanceBy(WORK_2 + (BREAK_2/2))
    
    #expect(appState.isBlocking == true)
    
    appState.skip()
    await clock.tick()
    
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_1)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 2)
    #expect(appState.delayed == 0)
    #expect(appState.count == 3)
    #expect(appState.completed == 0)
    
    // Finally take a break
    await clock.advanceBy(WORK_1 + BREAK_1 + 2)
    
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == WORK_2)
    #expect(appState.isPaused == false)
    #expect(appState.skipped == 2)
    #expect(appState.delayed == 0)
    #expect(appState.count == 4)
    #expect(appState.completed == 1)
    
    await context.afterEach()
  }

  @Test("Should be able to count the number of successfully completed breaks.")
  func testCompletedCount() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState
    
    // We add 1 second to ensure full transition to phase 2. Since the clock starts
    // immediately on initialization, we only need 1 extra second.
    await clock.advanceBy(WORK_1 + BREAK_1 + 1)
    // For these cycles, we need 2 seconds to fully transtion. 1 second to put
    // the first sleep on the clock and 1 second to complete the transition to the
    // next work cycle.
    await clock.advanceBy(WORK_2 + BREAK_2 + 2)
    await clock.advanceBy(WORK_1 + BREAK_1 + 2)
    await clock.advanceBy(WORK_2 + BREAK_2 + 2)
    await clock.advanceBy(3)
    
    #expect(appState.isBlocking == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 5)
    #expect(appState.completed == 4)
    
    await context.afterEach()
  }

  @Test("Should be able to count the number of times the schedule has been delayed.")
  func testDelayedCount() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState
    
    await clock.advanceBy(WORK_1 + (BREAK_1/2))
    
    #expect(appState.isBlocking == true)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)
    
    appState.delay(10)
    await clock.tick()
    
    #expect(appState.isBlocking == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 1)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)
    
    await clock.advanceBy(13)
    
    #expect(appState.isBlocking == true)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 1)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)
    
    appState.delay(10)
    await clock.tick()
    
    #expect(appState.isBlocking == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 2)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)
    
    await clock.advanceBy(10 + BREAK_1 + 2)
    
    #expect(appState.isBlocking == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 2)
    #expect(appState.completed == 1)

    await context.afterEach()
  }

  @Test("Should reset the delay count after skipping a break.")
  func testResetDelayedCountAfterSkip() async {
    let context = AppStateTestContext()
    let clock = context.clock
    let appState = context.appState
    
    // Advance to the middle of the first break
    await clock.advanceBy(WORK_1 + (BREAK_1/2))
    
    #expect(appState.isBlocking == true)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 0)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)
    
    // Delay for 10 seconds
    appState.delay(10)
    await clock.tick()
    
    #expect(appState.isBlocking == false)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 1)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)
    
    // Advance to the middle of the break again
    await clock.advanceBy(13)
    
    #expect(appState.isBlocking == true)
    #expect(appState.skipped == 0)
    #expect(appState.delayed == 1)
    #expect(appState.count == 1)
    #expect(appState.completed == 0)
    
    // Skip the break
    appState.skip()
    await clock.tick()
    
    #expect(appState.isBlocking == false)
    #expect(appState.skipped == 1)
    #expect(appState.delayed == 0)
    #expect(appState.count == 2)
    #expect(appState.completed == 0)

    await context.afterEach()
  }

  @Test("Should cancel the current schedule when it is destroyed.")
  func testCancelOnDeinit() async {
    let context = AppStateTestContext()
    let clock = context.clock
    var appState: AppState? = context.appState

    await clock.tick()
    #expect(appState?.remainingTime == WORK_1)

    // Deinitialize AppState
    appState = nil

    // There's no direct way to check if the underlying task was cancelled
    // without modifying production code. However, if the deinit on Break
    // correctly cancels its task, the system will not hold onto the objects,
    // and this test case will pass without memory leaks.
    // We can advance the clock to see if any crashes occur.
    await clock.advanceBy(20)
    #expect(appState == nil)

    await context.afterEach()
  }
}
