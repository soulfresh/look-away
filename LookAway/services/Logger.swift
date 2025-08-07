import Foundation

enum LogLevel: Int, Comparable {
  case error = 10
  case warn = 7
  case info = 5
  case debug = 0

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

protocol Logging {
  func error(_ message: String)
  func warn(_ message: String)
  func log(_ message: String)
  func debug(_ message: String)
  func time(_ label: String)
  func timeEnd(_ label: String)
}

class Logger: Logging {
  private var enabled: Bool
  private var logLevel: LogLevel = .debug
  private let queue = DispatchQueue(label: "com.lookaway.performanceTimer")
  private var timers: [String: Date] = [:]
  private let dateFormatter: DateFormatter

  init(enabled: Bool = true) {
    self.dateFormatter = DateFormatter()
    self.dateFormatter.dateFormat = "mm:ss.SSSS"
    self.enabled = enabled
  }

  private func timeStamp() -> String {
    let now = Date()
    return dateFormatter.string(from: now)
  }
  
  private func prefix() -> String {
    "[\(self.timeStamp())] ".grey()
  }

  func error(_ message: String) {
    guard enabled, logLevel <= .error else { return }
    queue.async {
      print(self.prefix() + "ERROR: \(message)".red())
    }
  }

  func warn(_ message: String) {
    guard enabled, logLevel <= .warn else { return }
    queue.async {
      print(self.prefix() + "WARN: \(message)".yellow())
    }
  }

  func log(_ message: String) {
    guard enabled, logLevel <= .info else { return }
    queue.async {
      print(self.prefix() + message)
    }
  }

  func debug(_ message: String) {
    guard enabled, logLevel <= .debug else { return }
    queue.async {
      print(self.prefix() + message.grey())
    }
  }
  
  func time(_ label: String) {
    // Allow adding timers so that if logs get enabled before `timeEnd` we
    // can still print that duration.
    let startTime = Date()
    queue.async {
      // If the label already exists, we update the start time.
      self.timers[label] = startTime
    }
  }

  func timeEnd(_ label: String) {
    let endTime = Date()
    queue.async {
      // Whether or not logging is enabled, make sure to remove this timer
      defer { self.timers.removeValue(forKey: label) }

      // If logging is disabled, skip the print but ensure the timer is removed.
      guard self.enabled, self.logLevel >= .info else { return }
      guard let startTime = self.timers[label] else { return }

      let duration = endTime.timeIntervalSince(startTime)

      print("\(label): \(String(format: "%.3f", duration * 1000)) ms")
    }
  }
}

/// Allows for logging with a specific label, which can be useful for
/// grouping/identifiying logs from different parts of the application or
/// different tasks.
class LogWrapper: Logging {
  private let logger: Logging
  private let label: String

  init(logger: Logging, label: String) {
    self.logger = logger
    self.label = label.blue()
  }

  func time(_ id: String) {
    logger.time(id)
  }

  func timeEnd(_ id: String) {
    logger.timeEnd(id)
  }

  func log(_ message: String) {
    logger.log("\(label): \(message)")
  }

  func debug(_ message: String) {
    logger.debug("\(label): \(message)")
  }

  func warn(_ message: String) {
    logger.warn("\(label): \(message)")
  }

  func error(_ message: String) {
    logger.error("\(label): \(message)")
  }
}
