import AVFoundation
import CoreMediaIO
import Foundation

protocol CameraDeviceProvider {
  func getCameraDevices() -> [Int]
  func addListener(
    deviceID: Int,
    listener: @escaping (Int) -> Void
  )
  func removeListener(deviceID: Int)
  func stopListening()
  func getDeviceProperty<T>(
    deviceID: Int,
    property: String,
    type: T.Type
  ) -> T?
}

class CoreMediaIODeviceProvider: CameraDeviceProvider {
  private let logger: Logging

  private static let propertyMap: [String: CMIOObjectPropertySelector] = [
    "name": CMIOObjectPropertySelector(kCMIOObjectPropertyName),
    "manufacturer": CMIOObjectPropertySelector(kCMIOObjectPropertyManufacturer),
    "uuid": CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
    "isRunning": CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
    "creator": CMIOObjectPropertySelector(kCMIOObjectPropertyCreator),
    "category": CMIOObjectPropertySelector(kCMIOObjectPropertyElementCategoryName),
    "type": CMIOObjectPropertySelector(kCMIODevicePropertyAVCDeviceType),
    "modelID": CMIOObjectPropertySelector(kCMIODevicePropertyModelUID),
  ]

  private static func selector(for name: String) -> CMIOObjectPropertySelector? {
    return propertyMap[name]
  }

  /// A list of active property listeners.
  private var propertyListeners: [CMIODeviceID: CMIOObjectPropertyListenerBlock] = [:]

  init(logger: Logging) { self.logger = logger }

  func getCameraDevices() -> [Int] {
    var deviceListProp = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var dataSize: UInt32 = 0
    var devices: [CMIODeviceID] = []
    var err = CMIOObjectGetPropertyDataSize(
      CMIOObjectID(kCMIOObjectSystemObject),
      &deviceListProp,
      0,
      nil,
      &dataSize
    )
    if err == kCMIOHardwareNoError {
      let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
      devices = [CMIODeviceID](repeating: 0, count: deviceCount)
      var dataUsed: UInt32 = 0
      err = CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &deviceListProp,
        0,
        nil,
        dataSize,
        &dataUsed,
        &devices
      )
    }
    return devices.map { Int($0) }
  }

  func addListener(
    deviceID id: Int,
    listener: @escaping (Int) -> Void
  ) {
    let deviceID = CMIODeviceID(id)

    // Register with CoreMediaIO (production only)
    var isRunningProp = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(
        kCMIODevicePropertyDeviceIsRunningSomewhere
      ),
      mScope: kCMIOObjectPropertyScopeWildcard,
      mElement: kCMIOObjectPropertyElementWildcard
    )

    let listenerBlock: CMIOObjectPropertyListenerBlock = {
      (inNumberAddresses, inAddresses) in

      // TODO We're forcing the update onto the main thread but it's
      // possible that `CameraMonitor` will not be running on the main
      // thread. How should we properly handle threading here?
      // - custom dispatch queue?
      // - @MainActor for CameraMonitor?
      // - other mechanism?
      DispatchQueue.main.async {
        // TODO Instead of enumerating all devices, just update the
        // state of this one device?
        listener(Int(deviceID))
      }
    }

    CMIOObjectAddPropertyListenerBlock(
      deviceID,
      &isRunningProp,
      DispatchQueue.main,
      listenerBlock
    )
    propertyListeners[deviceID] = listenerBlock
  }

  func removeListener(deviceID id: Int) {
    let deviceID = CMIODeviceID(id)

    // Unregister with CoreMediaIO (production only)
    var isRunningProp = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(
        kCMIODevicePropertyDeviceIsRunningSomewhere
      ),
      mScope: kCMIOObjectPropertyScopeWildcard,
      mElement: kCMIOObjectPropertyElementWildcard
    )
    CMIOObjectRemovePropertyListenerBlock(
      deviceID,
      &isRunningProp,
      DispatchQueue.main,
      propertyListeners[deviceID]!
    )
    propertyListeners[deviceID] = nil
  }

  func stopListening() {
    for device in propertyListeners.keys {
      removeListener(deviceID: Int(device))
    }
    propertyListeners.removeAll()
  }

  func getDeviceProperty<T>(
    deviceID id: Int,
    property _property: String,
    type: T.Type
  ) -> T? {
    let deviceID = CMIODeviceID(id)
    guard let property = CoreMediaIODeviceProvider.selector(for: _property) else {
      // TODO throw or warn?
      return nil
    }
    let scope = CMIOObjectPropertySelector(kCMIOObjectPropertyScopeGlobal)
    let element = CMIOObjectPropertySelector(kCMIOObjectPropertyElementMain)

    var prop = CMIOObjectPropertyAddress(
      mSelector: property,
      mScope: scope,
      mElement: element
    )
    var dataSize: UInt32 = 0
    let dataSizeErr = CMIOObjectGetPropertyDataSize(deviceID, &prop, 0, nil, &dataSize)
    if dataSizeErr != kCMIOHardwareNoError || dataSize == 0 {
      return nil
    }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: 1)
    defer { buffer.deallocate() }
    var dataUsed: UInt32 = 0
    let dataErr = CMIOObjectGetPropertyData(deviceID, &prop, 0, nil, dataSize, &dataUsed, buffer)
    if dataErr != kCMIOHardwareNoError {
      return nil
    }
    if type == Bool.self {
      let value = buffer.bindMemory(to: UInt32.self, capacity: 1).pointee
      return (value != 0) as? T
    }
    return buffer.bindMemory(to: type, capacity: 1).pointee
  }
}

class CameraActivityMonitor {
  enum ConnectedState {
    case connected
    case disconnected
  }

  struct CameraInfo: CustomStringConvertible {
    let id: Int
    let uniqueID: String
    let name: String
    let manufacturer: String
    var isRunning: Bool
    let isVirtual: Bool
    let creator: String
    let category: String
    let type: String
    let modelID: String

    var identifier: String {
      return "\(name)[\(id)]"
    }

    var description: String {
      return """
        [Camera \(id)] {
          name: \(name),
          isRunning: \(isRunning),
          uniqueID: \(uniqueID),
          manufacturer: \(manufacturer),
          isVirtual: \(isVirtual),
          creator: \(creator),
          category: \(category),
          type: \(type),
          modelID: \(modelID)
        }
        """
    }

    subscript(key: String) -> Any? {
      switch key {
      case "id": return id
      case "uniqueID": return uniqueID
      case "name": return name
      case "manufacturer": return manufacturer
      case "isRunning": return isRunning
      case "isVirtual": return isVirtual
      case "creator": return creator
      case "category": return category
      case "type": return type
      case "modelID": return modelID
      default: return nil
      }
    }
  }

  private var logger: Logging

  /// A callback to emit connection state changes to.
  private var callback: ((ConnectedState) -> Void)?

  /// The last emitted connection state.
  private var lastState: ConnectedState? = nil

  private(set) var devices: [CameraInfo] = []

  /// The number of cameras currently capturing video.
  var activeCameraCount: Int {
    devices.filter { $0.isRunning }.count
  }
  /// Whether there are any cameras currently capturing video.
  var isConnected: Bool {
    activeCameraCount > 0
  }

  private let deviceProvider: CameraDeviceProvider

  init(
    logger: Logging,
    deviceProvider: CameraDeviceProvider? = nil
  ) {
    self.logger = logger
    self.deviceProvider = deviceProvider ?? CoreMediaIODeviceProvider(logger: logger)

    logger.log("Initializing camera state")
    // Get the initial camera state so we can check it synchronously
    // if we need to.
    devices = getCameraDevices()
    logger.log("Initial active cameras: \(activeCameraCount)")
  }

  deinit {
    stopListening()
  }

  /// Returns the list of all video devices as CameraInfo, or an empty array on error.
  private func getCameraDevices() -> [CameraInfo] {
    let cameras = deviceProvider.getCameraDevices()
    logger.log("Found \(cameras.count) camera devices: \(cameras)")

    var cameraInfos: [CameraInfo] = []

    for deviceID in cameras {
      let name = getDeviceName(deviceID: deviceID)
      let manufacturer = getDeviceManufacturer(deviceID: deviceID)
      let uniqueID = getDeviceUuid(deviceID: deviceID)
      let running = getDeviceIsRunning(deviceID: deviceID)
      let creator = getDeviceCreator(deviceID: deviceID)
      let category = getDeviceCategory(deviceID: deviceID)
      let type = getDeviceType(deviceID: deviceID)
      let modelID = getDeviceModelId(deviceID: deviceID)

      // Determine if device is a camera (not a microphone)
      // For now, include all devices; you may want to filter by model or name
      let isVirtual = false  //name.contains("Virtual")

      cameraInfos.append(
        CameraInfo(
          id: deviceID,
          uniqueID: uniqueID,
          name: name,
          manufacturer: manufacturer,
          isRunning: running,
          isVirtual: isVirtual,
          creator: creator,
          category: category,
          type: type,
          modelID: modelID
        )
      )
    }
    logger.debug("Device Details:")
    cameraInfos.forEach { info in
      logger.log("\(info)")
    }

    return cameraInfos
  }

  /// Start listening to the "isRunningSomewhere" property on all camera devices
  /// and emit the initial camera connection state.
  func startListening(callback: @escaping (ConnectedState) -> Void) {
    // TODO What happens if a camera is connected after we start listening? We
    // currently would not add a new property listener for it.
    logger.log("start camera monitoring")
    self.callback = callback

    stopListening()

    logger.log("refreshing device list")
    devices = getCameraDevices()

    // TODO There is one limitation with our current approach: if a new
    // camera is connected after we start listening, we will not add a
    // property listener for it. We should probably listen for device
    // additions/removals and update our list of devices and property
    // listeners accordingly.

    // Add a property listener for each device.
    for device in devices {
      logger.log("Registering for '\(device.identifier)' notifications")

      deviceProvider.addListener(
        deviceID: device.id,
        listener: { [weak self] _ in self?.countActiveCameras() },
      )
    }
  }

  /// Count the number of active cameras and emit the current state if it has changed.
  func countActiveCameras() {
    logger.debug("updating camera running states")

    // Check if each known device is running.
    for (index, device) in devices.enumerated() {
      devices[index].isRunning = getDeviceIsRunning(deviceID: device.id)
    }

    logger.log("Active cameras: \(activeCameraCount)")
    emitCurrentState()
  }

  private func emitCurrentState() {
    let nextState =
      isConnected
      ? ConnectedState.connected
      : ConnectedState.disconnected

    // Only emit if the state has changed.
    if nextState != lastState {
      logger.log("Camera connection state changed: \(nextState)")
      lastState = nextState
      // Emit the connected state based
      callback?(nextState)
    } else {
      logger.debug("Camera connection state unchanged: \(nextState)")
    }
  }

  func stopListening() {
    logger.log("removing all property listeners")
    deviceProvider.stopListening()
    lastState = nil
  }

  private func getDeviceProperty<T>(
    deviceID: Int,
    propertySelector: String,
    type: T.Type
  ) -> T? {
    let out = deviceProvider.getDeviceProperty(
      deviceID: deviceID,
      property: propertySelector,
      type: type
    )
    return out
  }

  func getDeviceName(deviceID: Int) -> String {
    if let cfStr: CFString = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "name",
      type: CFString.self
    ) {
      return cfStr as String
    }
    return "Unknown"
  }

  func getDeviceManufacturer(deviceID: Int) -> String {
    if let cfStr: CFString = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "manufacturer",
      type: CFString.self
    ) {
      return cfStr as String
    }
    return "Unknown"
  }

  func getDeviceUuid(deviceID: Int) -> String {
    if let cfStr: CFString = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "uuid",
      type: CFString.self
    ) {
      return cfStr as String
    }
    return "Unknown"
  }

  func getDeviceIsRunning(deviceID: Int) -> Bool {
    if let isRunning: Bool = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "isRunning",
      type: Bool.self
    ) {
      return isRunning
    }
    return false
  }

  func getDeviceCreator(deviceID: Int) -> String {
    if let creator: UInt32 = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "creator",
      type: UInt32.self
    ) {
      let chars = [
        Character(UnicodeScalar((creator >> 24) & 0xFF)!),
        Character(UnicodeScalar((creator >> 16) & 0xFF)!),
        Character(UnicodeScalar((creator >> 8) & 0xFF)!),
        Character(UnicodeScalar(creator & 0xFF)!),
      ]
      return String(chars)
    }
    return "Unknown"
  }

  func getDeviceCategory(deviceID: Int) -> String {
    if let category: String = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "category",
      type: String.self
    ) {
      return category
    }
    return "Unknown"
  }

  func getDeviceType(deviceID: Int) -> String {
    if let type: String = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "type",
      type: String.self
    ) {
      return type
    }
    return "Unknown"
  }

  func getDeviceModelId(deviceID: Int) -> String {
    if let type: String = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "modelID",
      type: String.self
    ) {
      return type
    }
    return "Unknown"
  }
}
