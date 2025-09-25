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

struct SystemSleepListenerTestContext {
  let listener: SystemSleepMonitor
  let mockNotificationCenter: MockDistributedNotificationCenter

  init(debug: Bool = false) {
    let mockNC = MockDistributedNotificationCenter()
    listener = SystemSleepMonitor(logger: Logger(enabled: debug), notificationCenter: mockNC)
    mockNotificationCenter = mockNC
  }
}

struct SystemSleepListenerTests {

  @Test("should emit sleep/awake events when the screen locks")
  func testScreenLock() async throws {
    let test = SystemSleepListenerTestContext()

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

    // Simulate unlock event
    test.mockNotificationCenter.post(name: unlockName)
    #expect(spy.calls.last == .awake, "Should emit awake on unlock")

    spy.clear()

    // Stop listening
    test.listener.stopListening()

    // Simulate more events
    test.mockNotificationCenter.post(name: lockName)
    test.mockNotificationCenter.post(name: unlockName)

    // Assert no new calls recorded after stopping
    #expect(spy.callCount == 0, "Should not emit events after stopping listener")
  }

  @Test("should emit sleep/awake events when the camera is in use")
  func testCameraInUse() async throws {
    let test = SystemSleepListenerTestContext()

    let spy = Spy()
    test.listener.startListening(callback: spy.record)

    // Assert addObserver called for lock and unlock
    let connectedName = NSNotification.Name(
      "com.apple.camera.avfoundation.videodevice.wasConnected"
    )
    let disconnectedName = NSNotification.Name(
      "com.apple.camera.avfoundation.videodevice.wasDisconnected"
    )
    let observerNames = test.mockNotificationCenter.observers.map { $0.name }
    #expect(observerNames.contains(connectedName), "Should observe wasConnected")
    #expect(observerNames.contains(disconnectedName), "Should observe wasDisconnected")

    // Simulate lock event
    test.mockNotificationCenter.post(name: connectedName)
    #expect(spy.calls.last == .sleeping, "Should emit sleeping on camera in use")

    // Simulate unlock event
    test.mockNotificationCenter.post(name: disconnectedName)
    #expect(spy.calls.last == .awake, "Should emit awake on camera disconnected")

    spy.clear()

    // Stop listening
    test.listener.stopListening()

    // Simulate more events
    test.mockNotificationCenter.post(name: connectedName)
    test.mockNotificationCenter.post(name: disconnectedName)

    // Assert no new calls recorded after stopping
    #expect(spy.callCount == 0, "Should not emit events after stopping listener")
  }
  
  @Test("should correctly emit sleep/awake events if the user has multiple cameras")
  func testMultipleCameraSupport() async throws {
    let test = SystemSleepListenerTestContext()
    let spy = Spy()
    test.listener.startListening(callback: spy.record)

    let connectedName = NSNotification.Name(
      "com.apple.camera.avfoundation.videodevice.wasConnected"
    )
    let disconnectedName = NSNotification.Name(
      "com.apple.camera.avfoundation.videodevice.wasDisconnected"
    )

    // Simulate first camera connect
    test.mockNotificationCenter.post(name: connectedName)
    #expect(spy.calls.last == .sleeping, "Should emit sleeping on first camera connect")

    // Simulate second camera connect (should NOT emit again)
    test.mockNotificationCenter.post(name: connectedName)
    #expect(spy.callCount == 1, "Should not emit again on second camera connect")

    // Simulate first camera disconnect (should NOT emit awake yet)
    test.mockNotificationCenter.post(name: disconnectedName)
    #expect(spy.callCount == 1, "Should not emit awake until all cameras disconnected")

    // Simulate second camera disconnect (should emit awake)
    test.mockNotificationCenter.post(name: disconnectedName)
    #expect(spy.calls.last == .awake, "Should emit awake after all cameras disconnected")
    #expect(spy.callCount == 2, "Should emit awake only once after all disconnects")
  }
  
  @Test("should not emit duplicate sleep/awake events")
  func testDuplicateNotifications() async throws {
    let test = SystemSleepListenerTestContext()
    let spy = Spy()
    test.listener.startListening(callback: spy.record)

    let cameraConnected = NSNotification.Name("com.apple.camera.avfoundation.videodevice.wasConnected")
    let cameraDisconnected = NSNotification.Name("com.apple.camera.avfoundation.videodevice.wasDisconnected")
    let screenLocked = NSNotification.Name("com.apple.screenIsLocked")
    let screenUnlocked = NSNotification.Name("com.apple.screenIsUnlocked")

    // 1. Camera connect (should emit sleeping)
    test.mockNotificationCenter.post(name: cameraConnected)
    #expect(spy.calls.last == .sleeping, "Should emit sleeping on first camera connect")
    #expect(spy.callCount == 1, "Should emit only one event")

    // 2. Screen lock while already sleeping (should NOT emit again)
    test.mockNotificationCenter.post(name: screenLocked)
    #expect(spy.callCount == 1, "Should not emit duplicate sleeping event on screen lock")

    // 3. Redundant camera connect (should NOT emit again)
    test.mockNotificationCenter.post(name: cameraConnected)
    #expect(spy.callCount == 1, "Should not emit duplicate sleeping event on redundant camera connect")

    // 4. Unlock screen (still sleeping due to camera, should NOT emit)
    test.mockNotificationCenter.post(name: screenUnlocked)
    #expect(spy.callCount == 1, "Should not emit awake while still sleeping due to camera")

    // 5. Camera disconnect (should emit awake now)
    test.mockNotificationCenter.post(name: cameraDisconnected)
    #expect(spy.callCount == 1, "Should not emit because there is still one camera connected")

    // 6. Redundant camera disconnect (should NOT emit again)
    test.mockNotificationCenter.post(name: cameraDisconnected)
    #expect(spy.calls.last == .awake, "Should emit awake when all sleep triggers are cleared")
    #expect(spy.callCount == 2, "Should not emit duplicate awake event on redundant camera disconnect")

    // 7. Redundant screen unlock (should NOT emit again)
    test.mockNotificationCenter.post(name: screenUnlocked)
    #expect(spy.callCount == 2, "Should not emit duplicate awake event on redundant screen unlock")
  }
}
