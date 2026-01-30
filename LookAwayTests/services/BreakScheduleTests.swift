import Clocks
import Foundation
import Testing

@testable import LookAway

let WORK_1: TimeInterval = 10
let WORK_2: TimeInterval = 20
let BREAK_1: TimeInterval = 6
let BREAK_2: TimeInterval = 10
let INACTIVITY_LENGTH: TimeInterval = 300

class MockSleepNotificationCenter: DistributedNotificationCenterProtocol {
  struct Observer {
    let name: NSNotification.Name?
    let block: @Sendable (Notification) -> Void
  }
  var observers: [Observer] = []

  func addObserver(
    forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> NSObjectProtocol {
    let observer = Observer(name: name, block: block)
    observers.append(observer)
    return observers.count - 1 as NSNumber
  }

  func removeObserver(_ observer: Any) {}

  func post(name: NSNotification.Name) {
    for obs in observers where obs.name == name {
      obs.block(Notification(name: name))
    }
  }

  func simulateSleep() {
    post(name: NSNotification.Name("com.apple.screenIsLocked"))
  }

  func simulateWake() {
    post(name: NSNotification.Name("com.apple.screenIsUnlocked"))
  }
}

@MainActor
class BreakScheduleTestContext {
  let clock: BreakClock = BreakClock()
  let schedule: BreakSchedule<TestClock<Duration>>
  let cameraProvider: MockCameraDeviceProvider
  let microphoneProvider: MockAudioDeviceProvider
  let sleepNotificationCenter: MockSleepNotificationCenter
  let sleepMonitor: SystemSleepMonitor

  init(
    workCycles: [(work: TimeInterval, break: TimeInterval)]? = nil,
    waitForInactivity: Bool = true,
    debug: Bool = false
  ) {
    let logger = Logger(enabled: debug)

    let sleepNotificationCenter = MockSleepNotificationCenter()
    self.sleepNotificationCenter = sleepNotificationCenter
    self.sleepMonitor = SystemSleepMonitor(
      logger: LogWrapper(logger: logger, label: "Test SleepMonitor"),
      notificationCenter: sleepNotificationCenter
    )

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

    let microphoneProvider = MockAudioDeviceProvider(
      devices: [
        MicrophoneActivityMonitor
          .MicrophoneInfo(
            id: 0,
            uniqueID: "mock-uid-0",
            name: "Mock Microphone",
            manufacturer: "Mock Manufacturer",
            isRunning: false,
            modelUID: "MockModel",
            transportType: "USB"
          )
      ]
    )
    self.microphoneProvider = microphoneProvider

    // Create work cycles from the provided configuration or use defaults
    let cycles: [(work: TimeInterval, break: TimeInterval)] =
      workCycles ?? [
        (work: WORK_1, break: BREAK_1),
        (work: WORK_2, break: BREAK_2),
      ]

    // Capture clock property before using it in closure
    let testClock = clock.clock

    let workCycleSchedule = cycles.enumerated().map { index, config in
      WorkCycle(
        frequency: config.work,
        duration: config.break,
        logger: LogWrapper(logger: logger, label: "Test WorkCycle \(index)"),
        inactivityThresholds: [
          ActivityThreshold(
            name: "keyUp",
            threshold: INACTIVITY_LENGTH,
            callback: { INACTIVITY_LENGTH * TimeInterval(index + 1) }
          )
        ],
        clock: testClock,
        cameraProvider: cameraProvider,
        microphoneProvider: microphoneProvider,
        waitForInactivity: waitForInactivity,
      )
    }

    schedule = BreakSchedule(
      schedule: workCycleSchedule,
      logger: LogWrapper(logger: logger, label: "Test schedule"),
      sleepMonitor: sleepMonitor
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
    test.schedule.restartSchedule(from: .appStart)
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

  @Test("Should be able to start the break at a specific index in the schedule.")
  func testStartAtIndex() async {
    // Create a schedule with 5 work cycles with different break lengths
    // Work: [5, 5, 5, 5, 5], Break: [2, 4, 6, 8, 10]
    let context = BreakScheduleTestContext(
      workCycles: [
        (work: 5, break: 2),  // index 0
        (work: 5, break: 4),  // index 1
        (work: 5, break: 6),  // index 2 - start here
        (work: 5, break: 8),  // index 3
        (work: 5, break: 10),  // index 4 - longest break
      ]
    )

    // Start the schedule
    context.schedule.start()
    await context.clock.tick()

    // Verify we start at index 0 in working phase
    #expect(context.schedule.index == 0)
    #expect(context.schedule.count == 1)
    #expect(context.schedule.isBlocking == false)
    #expect(context.schedule.remainingTime == 5)

    // Advance to index 2 (middle of schedule)
    // Cycle 0: work(5) + transition(1) + break(2) + transition(1) = 9 seconds
    await context.clock.advanceBy(9)
    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 2)

    // Cycle 1: work(5) + transition(1) + break(4) + transition(1) = 11 seconds
    await context.clock.advanceBy(11)
    #expect(context.schedule.index == 2)
    #expect(context.schedule.count == 3)

    // Tick to ensure we're in the working phase of cycle 2
    await context.clock.tick()
    #expect(context.schedule.isBlocking == false)
    #expect(context.schedule.remainingTime == 5)

    // Now jump to index 4 and start its break
    context.schedule.startBreak(at: 4)
    await context.clock.tick()

    #expect(context.schedule.index == 4)
    #expect(context.schedule.count == 4)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 10)

    // Test wrap-around: jump to index 1 (earlier in the schedule)
    context.schedule.startBreak(at: 1)
    await context.clock.tick()

    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 5)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 4)

    // Test wrap-around to beginning: jump to index 0
    context.schedule.startBreak(at: 0)
    await context.clock.tick()

    #expect(context.schedule.index == 0)
    #expect(context.schedule.count == 6)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 2)

    await context.afterEach()
  }

  @Test(
    "Should be able to start the longest break in the schedule when all breaks have different lengths."
  )
  func testStartLongestBreak() async {
    // Create a schedule with 5 work cycles where the longest break is NOT in the middle
    // Work: [5, 5, 5, 5, 5], Break: [2, 4, 6, 10, 8]
    // Index 3 has the longest break (10 seconds)
    let context = BreakScheduleTestContext(
      workCycles: [
        (work: 5, break: 2),  // index 0
        (work: 5, break: 4),  // index 1
        (work: 5, break: 6),  // index 2 - start here (middle, short break)
        (work: 5, break: 8),  // index 3
        (work: 5, break: 10),  // index 4 - longest break
      ],
      // Timing of the inactivity tracker is non-deterministic, making it hard to test
      waitForInactivity: false,
      debug: false
    )

    // Start the schedule
    context.schedule.start()

    // Verify we start at index 0
    #expect(context.schedule.index == 0)
    #expect(context.schedule.count == 1)
    #expect(context.schedule.isBlocking == false)

    // Advance to index 2 (middle of schedule) and get into the break phase
    // Cycle 0: work(5) + transition(1) + break(2) + transition(1) = 9 seconds
    await context.clock.advanceBy(9)
    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 2)

    // Cycle 1: work(5) + transition(1) + break(4) + transition(1) = 11 seconds
    await context.clock.advanceBy(11)
    #expect(context.schedule.index == 2)
    #expect(context.schedule.count == 3)

    // Advance through the work phase to get into the break phase of cycle 2
    await context.clock.advanceBy(6)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 6)  // Currently in a 6-second break

    // Call startLongBreak - should jump to index 3 (10-second break)
    context.schedule.startLongBreak()
    await context.clock.tick()

    #expect(context.schedule.index == 4)
    #expect(context.schedule.count == 4)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 10)  // Now in the longest break

    await context.afterEach()
  }

  @Test(
    "Should find the longest break at the beginning of the schedule when all breaks have different lengths."
  )
  func testStartLongestBreakWrapping() async {
    // Create a schedule with 5 work cycles where the longest break is NOT in the middle
    // Work: [5, 5, 5, 5, 5], Break: [2, 4, 6, 10, 8]
    // Index 3 has the longest break (10 seconds)
    let context = BreakScheduleTestContext(
      workCycles: [
        (work: 5, break: 2),  // index 0
        (work: 5, break: 10),  // index 1 - longest break
        (work: 5, break: 4),  // index 2 - start here (middle, short break)
        (work: 5, break: 6),  // index 3
        (work: 5, break: 8),  // index 4
      ],
      // Timing of the inactivity tracker is non-deterministic, making it hard to test
      waitForInactivity: false,
      debug: false
    )

    // Start the schedule
    context.schedule.start()
    await context.clock.tick()

    // Verify we start at index 0
    #expect(context.schedule.index == 0)
    #expect(context.schedule.count == 1)
    #expect(context.schedule.isBlocking == false)

    // Advance to index 2 (middle of schedule) and get into the break phase
    // Cycle 0: work(5) + transition(1) + break(2) + transition(1) = 9 seconds
    await context.clock.advanceBy(9)
    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 2)

    // Cycle 1: work(5) + transition(1) + break(10) + transition(1) = 17 seconds
    await context.clock.advanceBy(17)
    #expect(context.schedule.index == 2)
    #expect(context.schedule.count == 3)

    // Advance through the work phase to get into the break phase of cycle 2
    await context.clock.advanceBy(6)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 4)  // Currently in a 6-second break

    // Call startLongBreak - should jump to index 3 (10-second break)
    context.schedule.startLongBreak()
    await context.clock.tick()

    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 4)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 10)  // Now in the longest break

    await context.afterEach()
  }

  @Test(
    "Should be able to start the longest break in the schedule when all breaks have the same length."
  )
  func testStartLongestBreakSameLength() async {
    // Create a schedule where all breaks have the same length
    // Work: [5, 5, 5, 5, 5], Break: [8, 8, 8, 8, 8]
    let context = BreakScheduleTestContext(
      workCycles: [
        (work: 5, break: 8),  // index 0
        (work: 5, break: 8),  // index 1 - start here
        (work: 5, break: 8),  // index 2
        (work: 5, break: 8),  // index 3
        (work: 5, break: 8),  // index 4
      ],
      waitForInactivity: false,
      debug: false
    )

    // Start the schedule
    context.schedule.start()
    await context.clock.tick()

    // Verify we start at index 0
    #expect(context.schedule.index == 0)
    #expect(context.schedule.count == 1)
    #expect(context.schedule.isBlocking == false)

    // Advance to index 1 (second work cycle)
    // Cycle 0: work(5) + transition(1) + break(8) + transition(1) = 15 seconds
    await context.clock.advanceBy(15)
    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 2)
    #expect(context.schedule.isBlocking == false)
    #expect(context.schedule.remainingTime == 5)

    // Call startLongBreak while in working phase - should start the break for current cycle (index 1)
    // Since all breaks are the same length, it should use the current cycle's break
    context.schedule.startLongBreak()
    await context.clock.tick()

    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 3)  // Count increments because startBreak(at:) calls startNextWorkCycle
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 8)  // Break length for current cycle

    await context.afterEach()
  }

  @Test(
    "Should be able to start the longest break in the schedule when multiple breaks share the longest length."
  )
  func testStartLongestBreakMultipleSameLength() async {
    // Create a schedule with multiple breaks sharing the longest length
    // Work: [5, 5, 5, 5, 5], Break: [2, 10, 4, 6, 10]
    // Indices 1 and 4 both have the longest break (10 seconds)
    // We'll start at index 2, so it should find index 4 first (wrapping past index 2, 3, and finding 4)
    let context = BreakScheduleTestContext(
      workCycles: [
        (work: 5, break: 2),  // index 0
        (work: 5, break: 10),  // index 1 - longest break (first)
        (work: 5, break: 4),  // index 2 - start here (middle, short break)
        (work: 5, break: 6),  // index 3
        (work: 5, break: 10),  // index 4 - longest break (second)
      ],
      waitForInactivity: false,
      debug: false
    )

    // Start the schedule
    context.schedule.start()
    await context.clock.tick()

    // Verify we start at index 0
    #expect(context.schedule.index == 0)
    #expect(context.schedule.count == 1)
    #expect(context.schedule.isBlocking == false)

    // Advance to index 2 (middle of schedule) and get into the break phase
    // Cycle 0: work(5) + transition(1) + break(2) + transition(1) = 9 seconds
    await context.clock.advanceBy(9)
    #expect(context.schedule.index == 1)
    #expect(context.schedule.count == 2)

    // Cycle 1: work(5) + transition(1) + break(10) + transition(1) = 17 seconds
    await context.clock.advanceBy(17)
    #expect(context.schedule.index == 2)
    #expect(context.schedule.count == 3)

    // Advance through the work phase to get into the break phase of cycle 2
    // work(5) + transition(1) = 6 seconds
    await context.clock.advanceBy(6)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 4)  // Currently in a 4-second break

    // Call startLongBreak - should search from index 2 and find the next longest break
    // Search order: 3, 4, 0, 1, 2
    // Should find index 4 (10-second break) before wrapping around to index 1
    context.schedule.startLongBreak()
    await context.clock.tick()

    #expect(context.schedule.index == 4)
    #expect(context.schedule.count == 4)
    #expect(context.schedule.isBlocking == true)
    #expect(context.schedule.remainingTime == 10)  // Now in the longest break

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

  @Test("Should reset to the beginning of the current work cycle when the system goes to sleep.")
  func testSleepResetsWorkCycle() async {
    // Use waitForInactivity: false for deterministic timing through the break phase
    let context = BreakScheduleTestContext(waitForInactivity: false)
    let clock = context.clock
    let schedule = context.schedule
    schedule.start()

    // Verify initial state
    #expect(schedule.isBlocking == false)
    #expect(schedule.count == 1)

    // Advance to the break phase: work(WORK_1) + transition(1) = WORK_1 + 1 seconds
    await clock.advanceBy(WORK_1 + 1)
    #expect(schedule.isBlocking == true)
    #expect(schedule.remainingTime == BREAK_1)
    #expect(schedule.count == 1)

    // Simulate system sleep
    context.sleepNotificationCenter.simulateSleep()
    await Task.yield()  // Allow main actor dispatch to complete

    // Verify blocking windows are removed (the main behavior we want to test)
    #expect(schedule.isBlocking == false)
    // Verify we're still on the same work cycle
    #expect(schedule.count == 1)
    // Verify remaining time is reset to 0 (ready to restart when waking)
    #expect(schedule.remainingTime == 0)

    await context.afterEach()
  }
}
