import Testing
import Foundation
import Clocks
@testable import LookAway

struct AppStateTests {

    @Test("Properties are initialized correctly")
    func testInitialization() {
        let appState = AppState()

        #expect(appState.remainingTime == 15 * 60)
        #expect(appState.remainingTime == appState.countdownDuration)
        #expect(appState.countdownLabel == "15:00")
    }

    @Test("Timer tick decreases remaining time and updates label")
    func testTimerTick_decreasesTime() async {
        // Create a clock that we can control manually
        let clock = TestClock()
        // Inject our test clock into the AppState
        let appState = AppState(clock: clock)
        let initialTime = appState.countdownDuration

        // The label should be updated immediately on start
        #expect(appState.countdownLabel == "15:00")

        // Advance the clock by 1 second. This will cause the `sleep` in the
        // countdown loop to complete instantly.
        await clock.advance(by: .seconds(1))

        // The time should have decreased by 1 and the label updated
        #expect(appState.remainingTime == initialTime - 1)
        #expect(appState.countdownLabel == "14:59")

        // Clean up the task to prevent it from running after the test.
        appState.cancelTimer()
    }
}
