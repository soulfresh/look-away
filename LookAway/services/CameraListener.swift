import AVFoundation
import CoreMediaIO
import Foundation

class CameraListener {
  enum ConnectedState {
    case connected
    case disconnected
  }

  struct CameraInfo: CustomStringConvertible {
    let id: CMIODeviceID
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
  }

  private var logger: Logging

  /// A callback to emit connection state changes to.
  private var callback: ((ConnectedState) -> Void)?

  /// A list of active property listeners.
  private var propertyListeners: [CMIODeviceID: CMIOObjectPropertyListenerBlock] = [:]

  /// The last emitted connection state.
  private var lastState: ConnectedState = .disconnected
  
  private var devices: [CameraInfo] = []

  /// The number of cameras currently capturing video.
//  private var activeCameraCount: Int = 0
  var activeCameraCount: Int {
    devices.filter { $0.isRunning }.count
  }
  /// Whether there are any cameras currently capturing video.
  var isConnected: Bool {
    activeCameraCount > 0
  }

  init(
    logger: Logging,
  ) {
    self.logger = logger
  }

  deinit {
    stopListening()
  }

  /// Returns the list of all video devices as CameraInfo, or an empty array on error.
  private func getCameraDevices() -> [CameraInfo] {
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

    logger.log("Found \(devices.count) Core Media device(s): \(devices)")

    var cameraInfos: [CameraInfo] = []
    for deviceID in devices {
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
    logger.log("initialize cameras")
    stopListening()
    self.callback = callback
    
    devices = getCameraDevices()

    registerForCameraNotifications(cameras: devices)
  }

  func registerForCameraNotifications(cameras: [CameraInfo]) {
    // The property we want to observe on each device.
    var isRunningProp = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(
        kCMIODevicePropertyDeviceIsRunningSomewhere
      ),
      mScope: kCMIOObjectPropertyScopeWildcard,
      mElement: kCMIOObjectPropertyElementWildcard
    )

    // Add a property listener for each device.
    for device in cameras {
      logger.log("Adding property listener for device '\(device.identifier)'")

      let listenerBlock: CMIOObjectPropertyListenerBlock = {
        (inNumberAddresses, inAddresses) in
        self.logger.log("Property listener triggered for device '\(device.identifier)'")

        DispatchQueue.main.async {
          // TODO Instead of enumerating all devices, just update the
          // state of this one device?
          self.countActiveCameras()
        }
      }

      CMIOObjectAddPropertyListenerBlock(
        device.id,
        &isRunningProp,
        DispatchQueue.main,
        listenerBlock
      )
      propertyListeners[device.id] = listenerBlock
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
    logger.log("stopListening called, removing all property listeners")
    for (deviceID, listenerBlock) in propertyListeners {
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
        listenerBlock
      )
      logger.log("Removed property listener for device \(deviceID)")
    }
    propertyListeners = [:]
    lastState = .disconnected
  }
  
  private func getDeviceProperty<T>(
    deviceID: CMIODeviceID,
    propertySelector: CMIOObjectPropertySelector,
    scope: CMIOObjectPropertyScope = CMIOObjectPropertySelector(kCMIOObjectPropertyScopeGlobal),
    element: CMIOObjectPropertyElement = CMIOObjectPropertySelector(kCMIOObjectPropertyElementMain),
    type: T.Type
  ) -> T? {
    var prop = CMIOObjectPropertyAddress(
      mSelector: propertySelector,
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
    return buffer.bindMemory(to: type, capacity: 1).pointee
  }

  private func getDeviceName(deviceID: CMIODeviceID) -> String {
    if let cfStr: CFString = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
      type: CFString.self
    ) {
      return cfStr as String
    }
    return "Unknown"
  }

  private func getDeviceManufacturer(deviceID: CMIODeviceID) -> String {
    if let cfStr: CFString = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(kCMIOObjectPropertyManufacturer),
      type: CFString.self
    ) {
      return cfStr as String
    }
    return "Unknown"
  }

  private func getDeviceUuid(deviceID: CMIODeviceID) -> String {
    if let cfStr: CFString = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
      type: CFString.self
    ) {
      return cfStr as String
    }
    return "Unknown"
  }

  private func getDeviceIsRunning(deviceID: CMIODeviceID) -> Bool {
    if let isRunning: UInt32 = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(
        kCMIODevicePropertyDeviceIsRunningSomewhere
      ),
      type: UInt32.self
    ) {
      return isRunning > 0
    }
    return false
  }

  private func getDeviceCreator(deviceID: CMIODeviceID) -> String {
    if let creator: UInt32 = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(kCMIOObjectPropertyCreator),
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

  private func getDeviceCategory(deviceID: CMIODeviceID) -> String {
    if let category: String = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(
        kCMIOObjectPropertyElementCategoryName
      ),
      type: String.self
    ) {
      return category
    }
    return "Unknown"
  }

  private func getDeviceType(deviceID: CMIODeviceID) -> String {
    if let type: String = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(
        kCMIODevicePropertyAVCDeviceType
      ),
      type: String.self
    ) {
      return type
    }
    return "Unknown"
  }

  private func getDeviceModelId(deviceID: CMIODeviceID) -> String {
    if let type: String = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: CMIOObjectPropertySelector(
        kCMIODevicePropertyModelUID
      ),
      type: String.self
    ) {
      return type
    }
    return "Unknown"
  }
  
}
