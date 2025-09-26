import CoreMediaIO
import Testing

@testable import LookAway

class MockCameraDeviceProvider: DeviceProviderProtocol {
  var devices: [CameraActivityMonitor.CameraInfo]
  var listeners: [Int: (Int) -> Void] = [:]

  init(devices: [CameraActivityMonitor.CameraInfo]? = nil) {
    self.devices = devices ?? []
  }

  func getCameraDevices() -> [Int] {
    return devices.map { $0.id }
  }

  func addListener(deviceID: Int, listener: @escaping (Int) -> Void) {
    listeners[deviceID] = listener
  }

  func removeListener(deviceID: Int) {
    listeners.removeValue(forKey: deviceID)
  }

  func stopListening() {
    self.listeners = [:]
  }

  func getDeviceProperty<T>(deviceID: Int, property: String, type: T.Type) -> T? {
    let device = devices.first { $0.id == deviceID }
    let result = device?[property]
    return result as? T
  }

  func emitEvent(deviceID: Int, newState: Bool) {
    // Update the device running state
    let index = devices.firstIndex(where: { $0.id == deviceID })
    if let index = index {
      devices[index].isRunning = newState
    }

    // Emit the update event
    if let listener = listeners[deviceID] {
      listener(newState ? 1 : 0)
    }
  }
}

class CameraConnectionSpy {
  var calls: [CameraActivityMonitor.ConnectedState] = []

  var callCount: Int {
    return calls.count
  }

  func callback(state: CameraActivityMonitor.ConnectedState) {
    calls.append(state)
  }
}

struct CameraActivityMonitorTestContext {
  let monitor: CameraActivityMonitor
  let deviceProvider: MockCameraDeviceProvider

  init(devices: [CameraActivityMonitor.CameraInfo]? = nil, debug: Bool = false) {
    let logger = Logger(enabled: debug)
    deviceProvider = MockCameraDeviceProvider(
      devices: devices
    )
    self.monitor = CameraActivityMonitor(
      logger: logger,
      deviceProvider: deviceProvider
    )
  }
}

struct CameraActivityMonitorTests {
  @Test("should be able to handle a device with no cameras.")
  func testNoCameras() async throws {
    let test = CameraActivityMonitorTestContext(devices: [])

    // Expect that the connected camera is discovered immediately
    #expect(test.monitor.isConnected == false)
    #expect(test.monitor.activeCameraCount == 0)
  }

  @Test("should determine the initial camera connection state when created.")
  func testInitialState() async throws {
    let test = CameraActivityMonitorTestContext(
      devices: [
        CameraActivityMonitor.CameraInfo(
          id: 0,
          uniqueID: "mock-uid-0",
          name: "Mock Camera",
          manufacturer: "Mock Manufacturer",
          isRunning: true,
          isVirtual: false,
          creator: "Mock",
          category: "Camera",
          type: "USB",
          modelID: "MockModel"
        )
      ],
      debug: false
    )

    // Expect that the connected camera is discovered immediately
    #expect(test.monitor.isConnected == true)
    #expect(test.monitor.activeCameraCount == 1)
    // No listeners should be registered until we start listening
    #expect(test.deviceProvider.listeners.count == 0)
  }

  @Test("should emit camera connection state changes when cameras start/stop recording video")
  func testCameraStateChanges() async throws {
    let test = CameraActivityMonitorTestContext(
      devices: [
        CameraActivityMonitor.CameraInfo(
          id: 0,
          uniqueID: "mock-uid-0",
          name: "Mock Camera 0",
          manufacturer: "Mock Manufacturer",
          isRunning: true,
          isVirtual: false,
          creator: "Mock",
          category: "Camera",
          type: "USB",
          modelID: "MockModel"
        ),
        CameraActivityMonitor.CameraInfo(
          id: 1,
          uniqueID: "mock-uid-1",
          name: "Mock Camera 1",
          manufacturer: "Mock Manufacturer",
          isRunning: false,
          isVirtual: false,
          creator: "Mock",
          category: "Camera",
          type: "USB",
          modelID: "MockModel"
        ),
      ],
      debug: false
    )

    let spy = CameraConnectionSpy()
    test.monitor.startListening(callback: spy.callback)

    #expect(test.monitor.isConnected == true)
    #expect(test.monitor.activeCameraCount == 1)
    #expect(spy.callCount == 0)
    #expect(test.deviceProvider.listeners.count == 2)

    // Simulate camera disconnect
    test.deviceProvider.emitEvent(deviceID: 0, newState: false)

    #expect(test.monitor.isConnected == false)
    #expect(test.monitor.activeCameraCount == 0)
    #expect(spy.callCount == 1)

    // Simulate camera connect
    test.deviceProvider.emitEvent(deviceID: 1, newState: true)

    #expect(test.monitor.isConnected == true)
    #expect(test.monitor.activeCameraCount == 1)
    #expect(spy.callCount == 2)
  }

  @Test("should be able to manually stop listening for connection changes.")
  func testStopListening() async throws {
    let test = CameraActivityMonitorTestContext(
      devices: [
        CameraActivityMonitor.CameraInfo(
          id: 0,
          uniqueID: "mock-uid-0",
          name: "Mock Camera 0",
          manufacturer: "Mock Manufacturer",
          isRunning: true,
          isVirtual: false,
          creator: "Mock",
          category: "Camera",
          type: "USB",
          modelID: "MockModel"
        ),
        CameraActivityMonitor.CameraInfo(
          id: 1,
          uniqueID: "mock-uid-1",
          name: "Mock Camera 1",
          manufacturer: "Mock Manufacturer",
          isRunning: true,
          isVirtual: false,
          creator: "Mock",
          category: "Camera",
          type: "USB",
          modelID: "MockModel"
        ),
      ],
      debug: false
    )

    let spy = CameraConnectionSpy()
    test.monitor.startListening(callback: spy.callback)

    #expect(test.monitor.isConnected == true)
    #expect(test.monitor.activeCameraCount == 2)
    #expect(spy.callCount == 0)
    #expect(test.deviceProvider.listeners.count == 2)

    test.monitor.stopListening()
    
    #expect(test.deviceProvider.listeners.isEmpty)
  }
}
