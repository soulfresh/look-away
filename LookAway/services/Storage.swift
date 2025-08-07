import Foundation

/// Service for managing the app's persistent storage.
struct Storage {
  private let WORK_CYCLE_CONFIG_KEY = "schedule"
  
  /// 4 quick eye breaks and 1 long break per hour
  private let DEFAULT_SCHEDULE: [WorkCycleConfig] = [
    WorkCycleConfig(
      frequency: TimeSpan(value: 15, unit: .minute),
      duration: TimeSpan(value: 10, unit: .second)
    ),
    WorkCycleConfig(
      frequency: TimeSpan(value: 15, unit: .minute),
      duration: TimeSpan(value: 10, unit: .second)
    ),
    WorkCycleConfig(
      frequency: TimeSpan(value: 15, unit: .minute),
      duration: TimeSpan(value: 10, unit: .second)
    ),
    WorkCycleConfig(
      frequency: TimeSpan(value: 15, unit: .minute),
      duration: TimeSpan(value: 5, unit: .minute)
    ),
  ]
  
  private var logger: Logging
  
  init(logger: Logging) {
    self.logger = logger
  }
  
  /// Get the last saved schedule or the default schedule.
  /// This is a static function so it can be called before the view
  /// is fully initialized.
  func loadSchedule() -> [WorkCycleConfig] {
    logger.log("Loading schedule from disk.")
    // Load the last saved schedule from disk.
    if let data = UserDefaults.standard.data(forKey: WORK_CYCLE_CONFIG_KEY) {
      do {
        return try JSONDecoder()
          .decode([WorkCycleConfig].self, from: data)
      } catch {
        logger.error("Failed to decode schedule data: \(error)")
      }
    }
    
    logger.log("No saved schedule found. Using default schedule.")
    return DEFAULT_SCHEDULE
  }
  
  /// Save the given schedule to disk.
  func saveSchedule(_ schedule: [WorkCycleConfig]) {
    logger.log("Saving schedule to disk: \(schedule)")
    // Save the current app state to disk.
    if let data = try? JSONEncoder().encode(schedule) {
      UserDefaults.standard.set(data, forKey: WORK_CYCLE_CONFIG_KEY)
    } else {
      logger.error("Failed to encode schedule data: \(schedule)")
    }
  }
}
