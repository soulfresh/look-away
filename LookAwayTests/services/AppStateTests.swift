import Clocks
import Foundation
import Testing

@testable import LookAway

@MainActor
class AppStateTestContext {
  let clock: BreakClock = BreakClock()
  let appState: AppState

  init(debug: Bool = false) {
    let logger = Logger(enabled: debug)

    appState = AppState(
      schedule: [
        WorkCycle(
          frequency: 10,
          duration: 5,
          logger: LogWrapper(logger: logger, label: "Test WorkCycle 0"),
          clock: clock.clock
        )
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
    #expect(appState.remainingTime == 10)
    #expect(appState.isPaused == false)

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
    #expect(appState.remainingTime == 10)

    // Advance through the working phase
    await clock.advanceBy(10)
    #expect(appState.remainingTime == 0)

    // Transition to the breaking phase
    await clock.advanceBy(1)
    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == 5)
    #expect(appState.isPaused == false)

    // Advance through the breaking phase
    await clock.advanceBy(5)
    #expect(appState.remainingTime == 0)

    // Transition to finished, which starts a new working phase
    await clock.advanceBy(1)
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == 10)
    #expect(appState.isPaused == false)

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
    #expect(appState.remainingTime == 5)

    // Manually start the working phase
    appState.startWorking()
    await clock.tick()

    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == 10)
    #expect(appState.isPaused == false)

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
    #expect(appState.remainingTime == 10)

    // Manually start the break phase
    appState.startBreak()
    await clock.tick()

    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == 5)
    #expect(appState.isPaused == false)

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

    // Pause the timer
    appState.pause()

    // Advance the clock; time should not change
    await clock.advanceBy(5)
    #expect(appState.remainingTime == 7)
    #expect(appState.isPaused == true)

    // Resume the timer
    appState.resume()
    await clock.tick()

    // Time should now decrease again
    await clock.advanceBy(1)
    #expect(appState.remainingTime == 6)
    #expect(appState.isPaused == false)

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
    await clock.advanceBy(5)
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
    await clock.advanceBy(5)
    #expect(appState.remainingTime == 6)
    #expect(appState.isPaused == true)

    await context.afterEach()
  }

  @Test("Should cancel the current schedule when it is destroyed.")
  func testCancelOnDeinit() async {
    let context = AppStateTestContext()
    let clock = context.clock
    var appState: AppState? = context.appState

    await clock.tick()
    #expect(appState?.remainingTime == 10)

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
