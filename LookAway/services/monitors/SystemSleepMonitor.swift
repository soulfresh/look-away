import Combine
import Foundation
import IOKit.pwr_mgt

// IOKit message constants
let kIOMessageSystemWillSleep: UInt32 = 0x0001_0001
let kIOMessageCanSystemSleep: UInt32 = 0x0001_0002
let kIOMessageSystemWillPowerOn: UInt32 = 0x0001_0003
let kIOMessageSystemHasPoweredOn: UInt32 = 0x0001_0004

protocol DistributedNotificationCenterProtocol {
  func addObserver(
    forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> NSObjectProtocol
  func removeObserver(_ observer: Any)
}

extension DistributedNotificationCenter: DistributedNotificationCenterProtocol {}

class SystemSleepMonitor {
  typealias CancelCallback = () -> Void

  enum SleepState {
    case awake
    case sleeping
  }

  private var logger: Logging

  /// The callback used to emit sleep state changes.
  private var callback: ((SleepState) -> Void)?
  /// The object used to listen for distributed notification events.
  private let notificationCenter: DistributedNotificationCenterProtocol
  /// The object used to listen for camera events.
//  private let cameraListener: CameraMonitor
  /// The list of callbacks that can be used to cancel listeners.
  private var cancellables: [CancelCallback] = []

  private(set) var isScreenLocked: Bool = false
//  private(set) var isCameraInUse: Bool = false
  // Track the number of active camera connections
//  private var activeCameraCount: Int = 0
//  var isCameraInUse_old: Bool {
//    return activeCameraCount > 0
//  }
//  private(set) var isMicrophoneInUse: Bool = false
  private(set) var isSystemSleeping: Bool = false

  /// Whether or not the system is considered to be sleeping. The system is
  /// considered "sleeping" if any of the sleep flags are true.
  var isSleeping: Bool {
    return isScreenLocked || isSystemSleeping
//    return isScreenLocked || isCameraInUse || isMicrophoneInUse || isSystemSleeping
  }
  
  private var lastState: SleepState = .awake

  init(
    logger: Logging,
    notificationCenter: DistributedNotificationCenterProtocol =
      DistributedNotificationCenter.default()
  ) {
    self.logger = logger
    self.notificationCenter = notificationCenter
//    self.cameraListener = CameraMonitor(logger: logger)
  }

  /// Start listening for system sleep/wake events. These will include events
  /// like screen lock, video or audio recording, etc.
  func startListening(callback: @escaping (SleepState) -> Void) {
    stopListening()

    self.callback = callback
    logger.log("Starting system sleep listener")

    cancellables.append(listenForScreenLock())
//    cancellables.append(listenForCameraUsage())
//    cancellables.append(listenForCameraUsage_old())
    // Screen lock notifications seem to capture the events we need already
    // but keeping this in case we need to bring it back.
    // cancellables.append(listenForSystemSleep())
  }

  private func emitCurrentState() {
    let nextState = isSleeping ? SleepState.sleeping : SleepState.awake
    // Only emit if the state has changed.
    if (nextState != lastState) {
      logger.log("System sleep state changed: \(nextState)")
      lastState = nextState
      // Emit the sleeping state based on the `isSleeping` computed property
      callback?(nextState)
    } else {
      logger.debug("System sleep state unchanged: \(nextState)")
    }
  }

  /// Listen for the screen to lock/unlock. This handles:
  /// - Screen lock
  /// - Screensaver
  /// - System sleep
  func listenForScreenLock() -> () -> Void {
    // Listen for screen lock/unlock
    let lockObserver = notificationCenter.addObserver(
      forName: NSNotification.Name("com.apple.screenIsLocked"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.logger.log("Received com.apple.screenIsLocked")
      self?.isScreenLocked = true
      self?.emitCurrentState()
    }

    let unlockObserver = notificationCenter.addObserver(
      forName: NSNotification.Name("com.apple.screenIsUnlocked"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.logger.log("Received com.apple.screenIsUnlocked")
      self?.isScreenLocked = false
      self?.emitCurrentState()
    }

    return { [weak self] in
      self?.notificationCenter.removeObserver(lockObserver)
      self?.notificationCenter.removeObserver(unlockObserver)
      self?.isScreenLocked = false
    }
  }

  /// Listen for the camera usage.
//  func listenForCameraUsage() -> () -> Void {
//    // TODO This is happening before the first WorkCycle is initialized and
//    // if the camera is in use when the listener starts, the initial WorkCycle
//    // is not paused.
//    // TODO Do we want to handle camera disconnect events differently from
//    // lock screen? If the user is in a long meeting, it might be better
//    // to immediately put them in a brake. I should probably implement the
//    // camera listener directly inside of BreakSchedule so we can treat it
//    // that way.
//    cameraListener
//      .startListening { [weak self] (state) in
//        self?.logger.log("Received camera state change: \(state)")
//        self?.isCameraInUse = state == .connected
//        self?.emitCurrentState()
//    }
//    
//    return { [weak self] in
//      self?.cameraListener.stopListening()
//    }
//  }
//  
//  /// Listen for the camera usage.
//  func listenForCameraUsage_old() -> () -> Void {
//    DistributedNotificationCenter.default().addObserver(
//        forName: nil,
//        object: nil,
//        queue: .main
//    ) { notification in
//        print("Received distributed notification: \(notification.name.rawValue)")
//    }
//
//    let lockObserver = notificationCenter.addObserver(
//      forName: NSNotification.Name(
//        "com.apple.camera.avfoundation.videodevice.wasConnected"
//      ),
//      object: nil,
//      queue: .main
//    ) { [weak self] _ in
//      guard let self = self else { return }
//      self.logger.log("Received com.apple.camera.avfoundation.videodevice.wasConnected")
//      self.activeCameraCount += 1
//      self.emitCurrentState()
//    }
//
//    let unlockObserver = notificationCenter.addObserver(
//      forName: NSNotification.Name(
//        "com.apple.camera.avfoundation.videodevice.wasDisconnected"
//      ),
//      object: nil,
//      queue: .main
//    ) { [weak self] _ in
//      guard let self = self else { return }
//      self.logger.log("Received com.apple.camera.avfoundation.videodevice.wasDisconnected")
//      self.activeCameraCount = max(0, self.activeCameraCount - 1)
//      self.emitCurrentState()
//    }
//
//    return { [weak self] in
//      self?.notificationCenter.removeObserver(lockObserver)
//      self?.notificationCenter.removeObserver(unlockObserver)
//      // Reset camera state when listener is removed
//      self?.activeCameraCount = 0
//    }
//  }

  /// Listen for system sleep/wake notifications via IOKit.
  ///
  /// The screen lock notifications seem to already cover the cases we need but
  /// I'm keeping this in case we need it in the future.
  func listenForSystemSleep() -> () -> Void {
    let refCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

    var sleepNotifier: IONotificationPortRef?
    var sleepNotifierObject: io_object_t = 0

    let port = IORegisterForSystemPower(
      refCon,  // refcon
      &sleepNotifier,  // thePortRef
      { (refCon, service, messageType, messageArgument) in
        print("Received IOKit message: \(messageType)")

        let mySelf = Unmanaged<SystemSleepMonitor>.fromOpaque(refCon!).takeUnretainedValue()

        switch messageType {
        case UInt32(kIOMessageSystemWillSleep):  //, UInt32(kIOMessageCanSystemSleep):
          // TODO We need to acknowledge the sleep to allow the system to sleep immediately.
          mySelf.logger.log("IOKit: System is going to sleep")
          mySelf.isSystemSleeping = true
          mySelf.emitCurrentState()
        case UInt32(kIOMessageSystemHasPoweredOn):  //, UInt32(kIOMessageSystemWillPowerOn)
          mySelf.logger.log("IOKit: System is awake")
          mySelf.isSystemSleeping = false
          mySelf.emitCurrentState()
        default:
          break
        }
      },
      &sleepNotifierObject  // notifier
    )

    if port == 0 {
      logger.error("Failed to register for system power notifications")
    }

    return { [weak self] in
      IONotificationPortDestroy(sleepNotifier)
      self?.isSystemSleeping = false
    }
  }

  func stopListening() {
    // Run all cancel callbacks to clean up listeners.
    cancellables.forEach { $0() }
    cancellables.removeAll()

    callback = nil
    logger.log("Stopped system sleep listener")
  }

  deinit {
    stopListening()
  }
}
