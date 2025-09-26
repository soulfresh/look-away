import Foundation
import Testing

@testable import LookAway

class Spy {
  var calls: [SystemSleepMonitor.SleepState] = []
  var callCount: Int {
    calls.count
  }

  func record(_ state: SystemSleepMonitor.SleepState) {
    calls.append(state)
  }

  func clear() {
    calls.removeAll()
  }
}

class MockDistributedNotificationCenter: DistributedNotificationCenterProtocol {
  struct Observer {
    let name: NSNotification.Name?
    let block: @Sendable (Notification) -> Void
  }
  var observers: [Observer] = []
  var removedObservers: [NSObjectProtocol] = []

  func addObserver(
    forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> NSObjectProtocol {
    let observer = Observer(name: name, block: block)
    observers.append(observer)
    // Use the array index as a token
    return observers.count - 1 as NSNumber
  }

  func removeObserver(_ observer: Any) {
    removedObservers.append(observer as! NSObjectProtocol)
  }

  // Helper to simulate notification
  func post(name: NSNotification.Name) {
    for obs in observers where obs.name == name {
      obs.block(Notification(name: name))
    }
  }
}

struct SystemSleepMonitorTestContext {
  let listener: SystemSleepMonitor
  let mockNotificationCenter: MockDistributedNotificationCenter

  init(debug: Bool = false) {
    let mockNC = MockDistributedNotificationCenter()
    listener = SystemSleepMonitor(logger: Logger(enabled: debug), notificationCenter: mockNC)
    mockNotificationCenter = mockNC
  }
}

struct SystemSleepMonitorTests {

  @Test("should emit sleep/awake events when the screen locks")
  func testScreenLock() async throws {
    let test = SystemSleepMonitorTestContext()

    let spy = Spy()
    test.listener.startListening(callback: spy.record)

    // Assert addObserver called for lock and unlock
    let lockName = NSNotification.Name("com.apple.screenIsLocked")
    let unlockName = NSNotification.Name("com.apple.screenIsUnlocked")
    let observerNames = test.mockNotificationCenter.observers.map { $0.name }
    #expect(observerNames.contains(lockName), "Should observe screenIsLocked")
    #expect(observerNames.contains(unlockName), "Should observe screenIsUnlocked")

    // Simulate lock event
    test.mockNotificationCenter.post(name: lockName)
    #expect(spy.calls.last == .sleeping, "Should emit sleeping on lock")
    #expect(spy.callCount == 1, "Should emit one event after lock")

    // Simulate a second lock event
    test.mockNotificationCenter.post(name: lockName)
    #expect(spy.callCount == 1, "Should not emit duplicate events")

    // Simulate unlock event
    test.mockNotificationCenter.post(name: unlockName)
    #expect(spy.calls.last == .awake, "Should emit awake on unlock")
    #expect(spy.callCount == 2)
    
    // Simulate a second unlock event
    test.mockNotificationCenter.post(name: unlockName)
    #expect(spy.callCount == 2, "Should not emit duplicate events")

    spy.clear()

    // Stop listening
    test.listener.stopListening()

    // Simulate more events
    test.mockNotificationCenter.post(name: lockName)
    test.mockNotificationCenter.post(name: unlockName)

    // Assert no new calls recorded after stopping
    #expect(spy.callCount == 0, "Should not emit events after stopping listener")
  }
}
