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
  /// The list of callbacks that can be used to cancel listeners.
  private var cancellables: [CancelCallback] = []

  private(set) var isScreenLocked: Bool = false
  private(set) var isSystemSleeping: Bool = false

  /// Whether or not the system is considered to be sleeping. The system is
  /// considered "sleeping" if any of the sleep flags are true.
  var isSleeping: Bool {
    return isScreenLocked || isSystemSleeping
  }

  private var lastState: SleepState = .awake

  init(
    logger: Logging,
    notificationCenter: DistributedNotificationCenterProtocol =
      DistributedNotificationCenter.default()
  ) {
    self.logger = logger
    self.notificationCenter = notificationCenter
  }

  /// Start listening for system sleep/wake events. These will include events
  /// like screen lock, video or audio recording, etc.
  func startListening(callback: @escaping (SleepState) -> Void) {
    stopListening()

    self.callback = callback
    logger.log("Starting system sleep listener")

    cancellables.append(listenForScreenLock())

    // Screen lock notifications seem to capture the events we need already
    // but keeping this in case we need to bring it back.
    // cancellables.append(listenForSystemSleep())
  }

  private func emitCurrentState() {
    let nextState = isSleeping ? SleepState.sleeping : SleepState.awake
    // Only emit if the state has changed.
    if nextState != lastState {
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
