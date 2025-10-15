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
  private let logFileURL: URL?

  init(enabled: Bool = true, level: LogLevel = .debug, logToFile: Bool = true) {
    self.dateFormatter = DateFormatter()
    self.dateFormatter.dateFormat = "mm:ss.SSSS"
    self.enabled = enabled

    if logToFile,
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    {
      let dir = appSupport.appendingPathComponent("LookAway", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      self.logFileURL = dir.appendingPathComponent("app.log")
    } else {
      self.logFileURL = nil
    }
  }

  private func timeStamp() -> String {
    let now = Date()
    return dateFormatter.string(from: now)
  }

  private func prefix() -> String {
    "[\(self.timeStamp())] ".grey()
  }

  private func writeToFile(_ message: String) {
    guard let url = logFileURL else { return }
    let data = (message + "\n").data(using: .utf8)!
    if FileManager.default.fileExists(atPath: url.path) {
      if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
      }
    } else {
      try? data.write(to: url)
    }
  }

  func error(_ message: String) {
    guard enabled, logLevel <= .error else { return }
    let logMsg = self.prefix() + "ERROR: \(message)".red()
    queue.async {
      print(logMsg)
      self.writeToFile(logMsg)
    }
  }

  func warn(_ message: String) {
    guard enabled, logLevel <= .warn else { return }
    let logMsg = self.prefix() + "WARN: \(message)".yellow()
    queue.async {
      print(logMsg)
      self.writeToFile(logMsg)
    }
  }

  func log(_ message: String) {
    guard enabled, logLevel <= .info else { return }
    let logMsg = self.prefix() + message
    queue.async {
      print(logMsg)
      self.writeToFile(logMsg)
    }
  }

  func debug(_ message: String) {
    guard enabled, logLevel <= .debug else { return }
    let logMsg = self.prefix() + message.grey()
    queue.async {
      print(logMsg)
      self.writeToFile(logMsg)
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
      let logMsg = "\(label): \(String(format: "%.3f", duration * 1000)) ms"
      print(logMsg)
      self.writeToFile(logMsg)
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
