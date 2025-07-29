//
//  LookAwayTests.swift
//  LookAwayTests
//
//  Created by robert marc wren on 5/30/25.
//

import Testing
import Foundation
import Clocks
@testable import LookAway

struct LookAwayTests {

    @Test("Properties are initialized correctly")
    func testRemainingTime_isInitialized() {
        let appDelegate = AppDelegate()

        #expect(appDelegate.remainingTime == 15 * 60)
        #expect(appDelegate.remainingTime == appDelegate.countdownDuration)
        #expect(appDelegate.countdownLabel == "15:00")
    }
    
    @Test("Timer tick decreases remaining time and updates label")
    func testTimerTick_decreasesTime() async {
        // Create a clock that we can control manually
        let clock = TestClock()
        // Inject our test clock into the AppDelegate
        let appDelegate = AppDelegate(clock: clock)
        let initialTime = appDelegate.countdownDuration

        // This starts the countdown task
        await appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        // The label should be updated immediately on start
        #expect(appDelegate.countdownLabel == "15:00")

        // Advance the clock by 1 second. This will cause the `sleep` in the
        // countdown loop to complete instantly.
        await clock.advance(by: .seconds(1))

        // The time should have decreased by 1 and the label updated
        #expect(appDelegate.remainingTime == initialTime - 1)
        #expect(appDelegate.countdownLabel == "14:59")

        // Clean up the task to prevent it from running after the test.
        await appDelegate.applicationWillTerminate(Notification(name: .init("test")))
    }
}
