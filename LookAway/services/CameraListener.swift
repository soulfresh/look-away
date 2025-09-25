import AVFoundation
import CoreMediaIO
import Foundation

class CameraListener {
  enum ConnectedState {
    case connected
    case disconnected
  }

  private var logger: Logging

  /// A callback to emit connection state changes to.
  private var callback: ((ConnectedState) -> Void)?

  /// A list of active property listeners.
  private var propertyListeners: [CMIOObjectPropertyAddress] = []

  /// The last emitted connection state.
  private var lastState: ConnectedState = .disconnected

  /// The number of cameras currently capturing video.
  private var activeCameraCount: Int = 0
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

  func startListening(callback: @escaping (ConnectedState) -> Void) {
    stopListening()
    self.callback = callback

    var props: [CMIOObjectPropertyAddress] = []

    // The property for getting the device list.
    var deviceListProp = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )

    // Get the list of all video devices.
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

    // The property we want to observe on each device.
    var isRunningProp = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(
        kCMIODevicePropertyDeviceIsRunningSomewhere
      ),
      mScope: kCMIOObjectPropertyScopeWildcard,
      mElement: kCMIOObjectPropertyElementWildcard
    )

    // Add a property listener for each device.
    for device in devices {
      props.append(isRunningProp)
      CMIOObjectAddPropertyListener(
        device,
        &isRunningProp,
        propertyListener,
        Unmanaged.passUnretained(self).toOpaque()
      )
    }

    propertyListeners = props

    // Perform an initial check of the camera state.
    updateCameraState()
  }

  func updateCameraState() {
    var activeCount = 0

    // Get the list of all video devices.
    var dataSize: UInt32 = 0
    var devices: [CMIODeviceID] = []
    var prop = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var err = CMIOObjectGetPropertyDataSize(
      CMIOObjectID(kCMIOObjectSystemObject),
      &prop,
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
        &prop,
        0,
        nil,
        dataSize,
        &dataUsed,
        &devices
      )
    }

    // Check if each device is running.
    for device in devices {
      var isRunning: UInt32 = 0
      var dataUsed: UInt32 = 0
      var isRunningProp = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(
          kCMIODevicePropertyDeviceIsRunningSomewhere
        ),
        mScope: kCMIOObjectPropertyScopeWildcard,
        mElement: kCMIOObjectPropertyElementWildcard
      )
      dataSize = UInt32(MemoryLayout<UInt32>.size)
      err = CMIOObjectGetPropertyData(
        device, &isRunningProp, 0, nil, dataSize, &dataUsed, &isRunning)
      if err == kCMIOHardwareNoError && isRunning > 0 {
        activeCount += 1
      }
    }

    activeCameraCount = activeCount
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
    for var prop in propertyListeners {
      CMIOObjectRemovePropertyListener(
        CMIOObjectID(kCMIOObjectSystemObject),
        &prop,
        propertyListener,
        Unmanaged.passUnretained(self).toOpaque()
      )
    }
    propertyListeners = []
    activeCameraCount = 0
    lastState = .disconnected
  }
}

@convention(c)
func propertyListener(
  objectID: CMIOObjectID,
  numInAddresses: UInt32,
  inAddresses: UnsafePointer<CMIOObjectPropertyAddress>,
  clientData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let clientData = clientData else {
    return OSStatus(kCMIOHardwareBadPropertySizeError)
  }

  let listener = Unmanaged<CameraListener>.fromOpaque(clientData).takeUnretainedValue()

  DispatchQueue.main.async {
    listener.updateCameraState()
  }

  return noErr
}
