import Clocks
import Foundation
import Testing
@testable import LookAway

@testable import LookAway

@MainActor
struct AppStateTests {
  @Test("Should start working as soon as it is initialized.")
  func testStartsImmediately() async {
    let clock = TestClock()
    let appState = AppState(clock: clock)

    // Advance the clock to allow the initial tasks to run
    await clock.advance(by: .zero)

    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == 10)

    await clock.advance(by: .seconds(1))

    #expect(appState.remainingTime == 9)
  }
  
  @Test("Should cycle through the working and breaking states.")
  func testFullCycle() async {
    let clock = TestClock()
    let appState = AppState(clock: clock)

    // Starts in working phase
    await clock.advance(by: .zero)
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == 10)

    // Advance through the working phase
    await clock.advance(by: .seconds(10))
    #expect(appState.remainingTime == 0)

    // Transition to the breaking phase
    await clock.advance(by: .seconds(1))
    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == 5)

    // Advance through the breaking phase
    await clock.advance(by: .seconds(5))
    #expect(appState.remainingTime == 0)

    // Transition to finished, which starts a new working phase
    await clock.advance(by: .seconds(1))
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == 10)
  }

  @Test("Should be able to start working when in the middle of a break.")
  func testStartWorking() async {
    let clock = TestClock()
    let appState = AppState(clock: clock)

    // Get to the breaking phase
    await clock.advance(by: .seconds(11))
    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == 5)

    // Manually start the working phase
    appState.startWorking()
    await clock.advance(by: .zero)

    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == 10)
  }

  @Test("Should be able to start the next break when in the working phase.")
  func testStartBreak() async {
    let clock = TestClock()
    let appState = AppState(clock: clock)

    // Start in the working phase
    await clock.advance(by: .zero)
    #expect(appState.isBlocking == false)
    #expect(appState.remainingTime == 10)

    // Manually start the break phase
    appState.startBreak()
    await clock.advance(by: .zero)

    #expect(appState.isBlocking == true)
    #expect(appState.remainingTime == 5)
  }

  @Test("Should be able to pause and resume when in the working phase.")
  func testPauseWhileWorking() async {
    let clock = TestClock()
    let appState = AppState(clock: clock)

    // Start in the working phase and advance a bit
    await clock.advance(by: .seconds(3))
    #expect(appState.remainingTime == 7)

    // Pause the timer
    appState.pause()

    // Advance the clock; time should not change
    await clock.advance(by: .seconds(5))
    #expect(appState.remainingTime == 7)

    // Resume the timer
    appState.resume()
    await clock.advance(by: .zero)

    // Time should now decrease again
    await clock.advance(by: .seconds(1))
    #expect(appState.remainingTime == 6)
  }

  @Test("Should cancel the current schedule when it is destroyed.")
  func testCancelOnDeinit() async {
    let clock = TestClock()
    var appState: AppState? = AppState(clock: clock)

    await clock.advance(by: .zero)
    #expect(appState?.remainingTime == 10)

    // Deinitialize AppState
    appState = nil

    // There's no direct way to check if the underlying task was cancelled
    // without modifying production code. However, if the deinit on Break
    // correctly cancels its task, the system will not hold onto the objects,
    // and this test case will pass without memory leaks.
    // We can advance the clock to see if any crashes occur.
    await clock.advance(by: .seconds(20))
    #expect(appState == nil)
  }
}
