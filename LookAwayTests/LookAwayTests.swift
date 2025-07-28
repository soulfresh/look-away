//
//  LookAwayTests.swift
//  LookAwayTests
//
//  Created by robert marc wren on 5/30/25.
//

import Testing
import Foundation
@testable import LookAway

struct LookAwayTests {

    @Test("Properties are initialized correctly")
    func testRemainingTime_isInitialized() {
        // given
        let appDelegate = AppDelegate()

        // then
        #expect(appDelegate.remainingTime == 15 * 60)
        #expect(appDelegate.remainingTime == appDelegate.countdownDuration)
        #expect(appDelegate.countdownLabel == "15:00")
    }

    @Test("Timer is created after applicationDidFinishLaunching")
    func testTimer_isCreated() {
        // given
        let appDelegate = AppDelegate()

        // when
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        // then
        #expect(appDelegate.timer != nil)
    }
}
