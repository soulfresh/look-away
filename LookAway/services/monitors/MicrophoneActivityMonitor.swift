import AVFoundation
import CoreAudio
import Foundation

protocol AudioDeviceProvider {
  func getMicrophoneDevices() -> [Int]
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

class CoreAudioDeviceProvider: AudioDeviceProvider {
  private let logger: Logging

  private static let propertyMap: [String: AudioObjectPropertySelector] = [
    "name": AudioObjectPropertySelector(kAudioObjectPropertyName),
    "manufacturer": AudioObjectPropertySelector(kAudioObjectPropertyManufacturer),
    "uuid": AudioObjectPropertySelector(kAudioDevicePropertyDeviceUID),
    "isRunning": AudioObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
    "modelUID": AudioObjectPropertySelector(kAudioDevicePropertyModelUID),
    "transportType": AudioObjectPropertySelector(kAudioDevicePropertyTransportType),
  ]

  private static func selector(for name: String) -> AudioObjectPropertySelector? {
    return propertyMap[name]
  }

  /// A list of active property listeners.
  private var propertyListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]

  init(logger: Logging) { self.logger = logger }

  func getMicrophoneDevices() -> [Int] {
    var deviceListProp = AudioObjectPropertyAddress(
      mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
      mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
      mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
    var dataSize: UInt32 = 0
    var devices: [AudioDeviceID] = []
    var err = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &deviceListProp,
      0,
      nil,
      &dataSize
    )
    if err == noErr {
      let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
      devices = [AudioDeviceID](repeating: 0, count: deviceCount)
      err = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &deviceListProp,
        0,
        nil,
        &dataSize,
        &devices
      )
    }

    // Filter for input devices only (microphones)
    let inputDevices = devices.filter { deviceID in
      var inputStreamsProp = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
      )
      var streamDataSize: UInt32 = 0
      let streamErr = AudioObjectGetPropertyDataSize(
        deviceID,
        &inputStreamsProp,
        0,
        nil,
        &streamDataSize
      )
      return streamErr == noErr && streamDataSize > 0
    }

    return inputDevices.map { Int($0) }
  }

  func addListener(
    deviceID id: Int,
    listener: @escaping (Int) -> Void
  ) {
    let deviceID = AudioDeviceID(id)

    // Register with CoreAudio (production only)
    var isRunningProp = AudioObjectPropertyAddress(
      mSelector: AudioObjectPropertySelector(
        kAudioDevicePropertyDeviceIsRunningSomewhere
      ),
      mScope: kAudioObjectPropertyScopeWildcard,
      mElement: kAudioObjectPropertyElementWildcard
    )

    let listenerBlock: AudioObjectPropertyListenerBlock = {
      (inNumberAddresses, inAddresses) in

      // TODO We're forcing the update onto the main thread but it's
      // possible that `MicrophoneMonitor` will not be running on the main
      // thread. How should we properly handle threading here?
      // - custom dispatch queue?
      // - @MainActor for MicrophoneMonitor?
      // - other mechanism?
      DispatchQueue.main.async {
        // TODO Instead of enumerating all devices, just update the
        // state of this one device?
        listener(Int(deviceID))
      }
    }

    AudioObjectAddPropertyListenerBlock(
      deviceID,
      &isRunningProp,
      DispatchQueue.main,
      listenerBlock
    )
    propertyListeners[deviceID] = listenerBlock
  }

  func removeListener(deviceID id: Int) {
    let deviceID = AudioDeviceID(id)

    // Unregister with CoreAudio (production only)
    var isRunningProp = AudioObjectPropertyAddress(
      mSelector: AudioObjectPropertySelector(
        kAudioDevicePropertyDeviceIsRunningSomewhere
      ),
      mScope: kAudioObjectPropertyScopeWildcard,
      mElement: kAudioObjectPropertyElementWildcard
    )
    AudioObjectRemovePropertyListenerBlock(
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
    let deviceID = AudioDeviceID(id)
    guard let property = CoreAudioDeviceProvider.selector(for: _property) else {
      // TODO throw or warn?
      return nil
    }
    let scope = AudioObjectPropertySelector(kAudioObjectPropertyScopeGlobal)
    let element = AudioObjectPropertySelector(kAudioObjectPropertyElementMain)

    var prop = AudioObjectPropertyAddress(
      mSelector: property,
      mScope: scope,
      mElement: element
    )
    var dataSize: UInt32 = 0
    let dataSizeErr = AudioObjectGetPropertyDataSize(deviceID, &prop, 0, nil, &dataSize)
    if dataSizeErr != noErr || dataSize == 0 {
      return nil
    }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: 1)
    defer { buffer.deallocate() }
    let dataErr = AudioObjectGetPropertyData(deviceID, &prop, 0, nil, &dataSize, buffer)
    if dataErr != noErr {
      return nil
    }
    if type == Bool.self {
      let value = buffer.bindMemory(to: UInt32.self, capacity: 1).pointee
      return (value != 0) as? T
    }
    if type == UInt32.self {
      return buffer.bindMemory(to: UInt32.self, capacity: 1).pointee as? T
    }
    return buffer.bindMemory(to: type, capacity: 1).pointee
  }
}

class MicrophoneActivityMonitor {
  enum ConnectedState {
    case connected
    case disconnected
  }

  struct MicrophoneInfo: CustomStringConvertible {
    let id: Int
    let uniqueID: String
    let name: String
    let manufacturer: String
    var isRunning: Bool
    let modelUID: String
    let transportType: String

    var identifier: String {
      return "\(name)[\(id)]"
    }

    var description: String {
      return """
        [Microphone \(id)] {
          name: \(name),
          isRunning: \(isRunning),
          uniqueID: \(uniqueID),
          manufacturer: \(manufacturer),
          modelUID: \(modelUID),
          transportType: \(transportType)
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
      case "modelUID": return modelUID
      case "transportType": return transportType
      default: return nil
      }
    }
  }

  private var logger: Logging

  /// A callback to emit connection state changes to.
  private var callback: ((ConnectedState) -> Void)?

  /// The last emitted connection state.
  private var lastState: ConnectedState? = nil

  /// The list of microphone devices.
  private(set) var devices: [MicrophoneInfo] = []

  /// Filters used to ignore certain microphones by name or unique ID.
  private var filter: [String]

  /// The number of microphones currently capturing audio.
  var activeMicrophoneCount: Int {
    devices.filter { $0.isRunning }.count
  }
  /// Whether there are any microphones currently capturing audio.
  var isConnected: Bool {
    activeMicrophoneCount > 0
  }

  private let deviceProvider: AudioDeviceProvider

  init(
    logger: Logging,
    filter: [String] = [
      // These devices are always running when connected so we cannot use them
      // to deterimine if the user is actively using a microphone.
      "Universal Audio"
    ],
    deviceProvider: AudioDeviceProvider? = nil
  ) {
    self.logger = logger
    self.filter = filter
    self.deviceProvider = deviceProvider ?? CoreAudioDeviceProvider(logger: logger)

    logger.log("Initializing microphone state")
    // Get the initial microphone state so we can check it synchronously
    // if we need to.
    devices = getMicrophoneDevices()
    logger.log("Initial active microphones: \(activeMicrophoneCount)")
  }

  deinit {
    stopListening()
  }

  /// Returns the list of all audio input devices as MicrophoneInfo, or an empty array on error.
  private func getMicrophoneDevices() -> [MicrophoneInfo] {
    let microphones = deviceProvider.getMicrophoneDevices()
    logger.log("Found \(microphones.count) microphone devices: \(microphones)")

    var microphoneInfos: [MicrophoneInfo] = []

    for deviceID in microphones {
      let name = getDeviceName(deviceID: deviceID)
      let manufacturer = getDeviceManufacturer(deviceID: deviceID)
      let uniqueID = getDeviceUuid(deviceID: deviceID)
      let running = getDeviceIsRunning(deviceID: deviceID)
      let modelUID = getDeviceModelUID(deviceID: deviceID)
      let transportType = getDeviceTransportType(deviceID: deviceID)

      let mic = MicrophoneInfo(
        id: deviceID,
        uniqueID: uniqueID,
        name: name,
        manufacturer: manufacturer,
        isRunning: running,
        modelUID: modelUID,
        transportType: transportType
      )

      guard
        !filter.contains(where: { term in
          name.contains(term) || manufacturer.contains(term)
        })
      else {
        logger.log("Ignoring microphone: \(mic)")
        continue
      }

      microphoneInfos.append(mic)
    }
    logger.debug("Device Details:")
    microphoneInfos.forEach { info in
      logger.log("\(info)")
    }

    return microphoneInfos
  }

  /// Start listening to the "isRunningSomewhere" property on all microphone devices
  /// and emit the initial microphone connection state.
  func startListening(callback: @escaping (ConnectedState) -> Void) {
    // TODO What happens if a microphone is connected after we start listening? We
    // currently would not add a new property listener for it.
    logger.log("start microphone monitoring")
    self.callback = callback

    stopListening()

    logger.log("refreshing device list")
    devices = getMicrophoneDevices()

    // TODO There is one limitation with our current approach: if a new
    // microphone is connected after we start listening, we will not add a
    // property listener for it. We should probably listen for device
    // additions/removals and update our list of devices and property
    // listeners accordingly.

    // Add a property listener for each device.
    for device in devices {
      logger.log("Registering for '\(device.identifier)' notifications")

      deviceProvider.addListener(
        deviceID: device.id,
        listener: { [weak self] _ in self?.countActiveMicrophones() },
      )
    }
  }

  /// Count the number of active microphones and emit the current state if it has changed.
  func countActiveMicrophones() {
    logger.debug("updating microphone running states")

    // Check if each known device is running.
    for (index, device) in devices.enumerated() {
      devices[index].isRunning = getDeviceIsRunning(deviceID: device.id)
    }

    logger.log("Active microphones: \(activeMicrophoneCount)")
    emitCurrentState()
  }

  private func emitCurrentState() {
    let nextState =
      isConnected
      ? ConnectedState.connected
      : ConnectedState.disconnected

    // Only emit if the state has changed.
    if nextState != lastState {
      logger.log("Microphone connection state changed: \(nextState)")
      lastState = nextState
      // Emit the connected state based
      callback?(nextState)
    } else {
      logger.debug("Microphone connection state unchanged: \(nextState)")
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

  func getDeviceModelUID(deviceID: Int) -> String {
    if let modelUID: String = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "modelUID",
      type: String.self
    ) {
      return modelUID
    }
    return "Unknown"
  }

  func getDeviceTransportType(deviceID: Int) -> String {
    if let transportType: UInt32 = getDeviceProperty(
      deviceID: deviceID,
      propertySelector: "transportType",
      type: UInt32.self
    ) {
      // Convert the transport type to a readable string
      let chars = [
        Character(UnicodeScalar((transportType >> 24) & 0xFF)!),
        Character(UnicodeScalar((transportType >> 16) & 0xFF)!),
        Character(UnicodeScalar((transportType >> 8) & 0xFF)!),
        Character(UnicodeScalar(transportType & 0xFF)!),
      ]
      return String(chars)
    }
    return "Unknown"
  }
}
