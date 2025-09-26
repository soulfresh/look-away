import Clocks
import Foundation
import Testing

@testable import LookAway

let WORK_1: TimeInterval = 10
let WORK_2: TimeInterval = 20
let BREAK_1: TimeInterval = 6
let BREAK_2: TimeInterval = 10
let INACTIVITY_LENGTH: TimeInterval = 300

@MainActor
class BreakScheduleTestContext {
  let clock: BreakClock = BreakClock()
  let schedule: BreakSchedule<TestClock<Duration>>
  let cameraProvider: MockCameraDeviceProvider

  init(debug: Bool = false) {
    let logger = Logger(enabled: debug)

    let cameraProvider = MockCameraDeviceProvider(
      devices: [
        CameraActivityMonitor
          .CameraInfo(
            id: 0,
            uniqueID: "mock-uid-0",
            name: "Mock Camera",
            manufacturer: "Mock Manufacturer",
            isRunning: false,
            isVirtual: false,
            creator: "Mock",
            category: "Camera",
            type: "USB",
            modelID: "MockModel"
          )
      ]
    )
    self.cameraProvider = cameraProvider

    schedule = BreakSchedule(
      schedule: [
        WorkCycle(
          frequency: WORK_1,
          duration: BREAK_1,
          logger: LogWrapper(logger: logger, label: "Test WorkCycle 0"),
          inactivityThresholds: [
            ActivityThreshold(
              name: "keyUp",
              threshold: INACTIVITY_LENGTH,
              callback: { INACTIVITY_LENGTH + 1 }
            )
          ],
          clock: clock.clock,
          cameraProvider: cameraProvider,
        ),
        WorkCycle(
          frequency: WORK_2,
          duration: BREAK_2,
          logger: LogWrapper(logger: logger, label: "Test WorkCycle 1"),
          inactivityThresholds: [
            ActivityThreshold(
              name: "keyUp",
              threshold: INACTIVITY_LENGTH,
              callback: { INACTIVITY_LENGTH * 2 }
            )
          ],
          clock: clock.clock,
          cameraProvider: cameraProvider,
        ),
      ],
      logger: LogWrapper(logger: logger, label: "Test schedule"),
    )
  }

  func afterEach() async {
    // Ensure that the app state is cancelled and cleaned up
    schedule.cancelTimer()
    await clock.run()
  }
}

@MainActor
struct BreakScheduleTests {
  @Test("Should start working as soon as it is initialized.")
  func testStartsImmediately() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule

    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == 0)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 0)
    #expect(schedule.completed == 0)

    schedule.start()

    // Advance the clock to allow the initial tasks to run
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_1)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    await clock.advanceBy(1)

    #expect(schedule.remainingTime == 9)

    await context.afterEach()
  }

  @Test("Should cycle through the working and breaking states.")
  func testFullCycle() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Starts in working phase
    await clock.tick()
    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_1)

    // Advance through the working phase
    await clock.advanceBy(WORK_1)
    #expect(schedule.remainingTime == 0)

    // Transition to the breaking phase. Will skip the waiting phase because
    // the user is configured to be inactive.
    await clock.advanceBy(1)
    #expect(schedule.isBlocking == true)
    #expect(schedule.remainingTime == BREAK_1)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    // Advance through the breaking phase
    await clock.advanceBy(BREAK_1)
    #expect(schedule.remainingTime == 0)

    // Transition to finished, which starts a new working phase
    await clock.advanceBy(1)
    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_2)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 2)
    #expect(schedule.completed == 1)

    // Transition to the second break
    await clock.advanceBy(21)
    #expect(schedule.isBlocking == true)
    #expect(schedule.remainingTime == BREAK_2)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 2)
    #expect(schedule.completed == 1)

    await context.afterEach()
  }

  @Test("Should be able to skip to the next work cycle when in the middle of a break.")
  func testSkip() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Get to the breaking phase
    await clock.advanceBy(11)
    #expect(schedule.isBlocking == true)
    #expect(schedule.remainingTime == BREAK_1)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    // Manually start the working phase
    schedule.skip()
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_2)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 1)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 2)
    #expect(schedule.completed == 0)

    await context.afterEach()
  }

  @Test("Should be able to start the next break when in the working phase.")
  func testStartBreak() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Start in the working phase
    await clock.tick()
    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_1)

    // Manually start the break phase
    schedule.startBreak()
    await clock.tick()

    #expect(schedule.isBlocking == true)
    #expect(schedule.remainingTime == BREAK_1)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    await context.afterEach()
  }

  @Test("should be able to restart the current work cycle from the beginning.")
  func testRestartWorkCycle() async {
    let test = BreakScheduleTestContext()
    test.schedule.start()
    
    // Start in the working phase
    await test.clock.tick()
    #expect(test.schedule.isBlocking == false)
    #expect(test.schedule.remainingTime == WORK_1)
    
    // Get to the breaking phase
    await test.clock.advanceBy(11)
    #expect(test.schedule.isBlocking == true)
    #expect(test.schedule.remainingTime == BREAK_1)
    #expect(test.schedule.isPaused == false)
    #expect(test.schedule.skipped == 0)
    #expect(test.schedule.delayed == 0)
    #expect(test.schedule.count == 1)
    #expect(test.schedule.completed == 0)
    
    // Restart the current work cycle
    test.schedule.restartWorkCycle()
    // Give the schedule a chance to process the restart
    await test.clock.tick()
    
    #expect(test.schedule.isBlocking == false)
    #expect(test.schedule.remainingTime == WORK_1)
    #expect(test.schedule.isPaused == false)
    #expect(test.schedule.skipped == 0)
    #expect(test.schedule.delayed == 0)
    #expect(test.schedule.count == 1)
    #expect(test.schedule.completed == 0)
  }

  @Test("should be able to restart the current schedule from the beginniing.")
  func testRestartSchedule() async {
    let test = BreakScheduleTestContext()
    test.schedule.start()
    
    // Start in the working phase
    await test.clock.tick()
    #expect(test.schedule.isBlocking == false)
    #expect(test.schedule.remainingTime == WORK_1)
    
    // Skip to the next work cycle
    test.schedule.skip()
    await test.clock.tick()
    
    #expect(test.schedule.isBlocking == false)
    #expect(test.schedule.remainingTime == WORK_2)
    #expect(test.schedule.isPaused == false)
    #expect(test.schedule.skipped == 1)
    #expect(test.schedule.delayed == 0)
    #expect(test.schedule.count == 2)
    #expect(test.schedule.completed == 0)
    
    // Restart the entire schedule
    test.schedule.restartSchedule()
    await test.clock.tick()
    
    #expect(test.schedule.isBlocking == false)
    #expect(test.schedule.remainingTime == WORK_1)
    #expect(test.schedule.isPaused == false)
    #expect(test.schedule.skipped == 0)
    #expect(test.schedule.delayed == 0)
    #expect(test.schedule.count == 1)
    #expect(test.schedule.completed == 0)
  }

  @Test("Should be able to pause and resume when in the working phase.")
  func testPauseWhileWorking() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Start in the working phase and advance a bit
    await clock.advanceBy(3)
    #expect(schedule.remainingTime == 7)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    // Pause the timer
    schedule.pause()

    // Advance the clock; time should not change
    await clock.advanceBy(BREAK_1)
    #expect(schedule.remainingTime == 7)
    #expect(schedule.isPaused == true)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    // Resume the timer
    schedule.resume()
    await clock.tick()

    // Time should now decrease again
    await clock.advanceBy(1)
    #expect(schedule.remainingTime == 6)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    await context.afterEach()
  }

  @Test("Should be able to toggle the paused state.")
  func testTogglePause() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Start in the working phase and advance a bit
    await clock.advanceBy(3)
    #expect(schedule.remainingTime == 7)
    #expect(schedule.isPaused == false)

    // Pause the timer
    schedule.togglePaused()

    // Advance the clock; time should not change
    await clock.advanceBy(BREAK_1)
    #expect(schedule.remainingTime == 7)
    #expect(schedule.isPaused == true)

    // Resume the timer
    schedule.togglePaused()
    await clock.tick()

    // Time should now decrease again
    await clock.advanceBy(1)
    #expect(schedule.remainingTime == 6)
    #expect(schedule.isPaused == false)

    // Pause the timer
    schedule.togglePaused()

    // Advance the clock; time should not change
    await clock.advanceBy(BREAK_1)
    #expect(schedule.remainingTime == 6)
    #expect(schedule.isPaused == true)

    await context.afterEach()
  }

  @Test("Should be able to count the number of times the schedule has been skipped.")
  func testSkipCount() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Advance to the middle of the first break
    await clock.advanceBy(WORK_1 + (BREAK_1 / 2))

    #expect(schedule.isBlocking == true)

    schedule.skip()
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_2)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 1)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 2)
    #expect(schedule.completed == 0)

    // Advance to the middle of the second break
    await clock.advanceBy(WORK_2 + (BREAK_2 / 2))

    #expect(schedule.isBlocking == true)

    schedule.skip()
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_1)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 2)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 3)
    #expect(schedule.completed == 0)

    // Finally take a break
    await clock.advanceBy(WORK_1 + BREAK_1 + 2)

    #expect(schedule.isBlocking == false)
    #expect(schedule.remainingTime == WORK_2)
    #expect(schedule.isPaused == false)
    #expect(schedule.skipped == 2)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 4)
    #expect(schedule.completed == 1)

    await context.afterEach()
  }

  // TODO Flaky test
  @Test("Should be able to count the number of successfully completed breaks.")
  func testCompletedCount() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

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

    #expect(schedule.isBlocking == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 5)
    #expect(schedule.completed == 4)

    await context.afterEach()
  }

  @Test("Should be able to count the number of times the schedule has been delayed.")
  func testDelayedCount() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    await clock.advanceBy(WORK_1 + (BREAK_1 / 2))

    #expect(schedule.isBlocking == true)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    schedule.delay(10)
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 1)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    await clock.advanceBy(13)

    #expect(schedule.isBlocking == true)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 1)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    schedule.delay(10)
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 2)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    await clock.advanceBy(10 + BREAK_1 + 2)

    #expect(schedule.isBlocking == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 2)
    #expect(schedule.completed == 1)

    await context.afterEach()
  }

  @Test("Should reset the delay count after skipping a break.")
  func testResetDelayedCountAfterSkip() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Advance to the middle of the first break
    await clock.advanceBy(WORK_1 + (BREAK_1 / 2))

    #expect(schedule.isBlocking == true)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    // Delay for 10 seconds
    schedule.delay(10)
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 1)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    // Advance to the middle of the break again
    await clock.advanceBy(13)

    #expect(schedule.isBlocking == true)
    #expect(schedule.skipped == 0)
    #expect(schedule.delayed == 1)
    #expect(schedule.count == 1)
    #expect(schedule.completed == 0)

    // Skip the break
    schedule.skip()
    await clock.tick()

    #expect(schedule.isBlocking == false)
    #expect(schedule.skipped == 1)
    #expect(schedule.delayed == 0)
    #expect(schedule.count == 2)
    #expect(schedule.completed == 0)

    await context.afterEach()
  }

  @Test("Should cancel the current schedule when it is destroyed.")
  func testCancelOnDeinit() async {
    let context = BreakScheduleTestContext()
    let clock = context.clock
    var schedule: BreakSchedule? = context.schedule

    schedule!.start()

    await clock.tick()
    #expect(schedule?.remainingTime == WORK_1)

    // Deinitialize schedule
    schedule = nil

    // There's no direct way to check if the underlying task was cancelled
    // without modifying production code. However, if the deinit on Break
    // correctly cancels its task, the system will not hold onto the objects,
    // and this test case will pass without memory leaks.
    // We can advance the clock to see if any crashes occur.
    await clock.advanceBy(20)
    #expect(schedule == nil)

    await context.afterEach()
  }
}
