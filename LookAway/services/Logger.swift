import Foundation

class Logger {
  private var enabled: Bool
  private let queue = DispatchQueue(label: "com.lookaway.performanceTimer")
  private var timers: [String: Date] = [:]
  
  init(enabled: Bool = true) {
    self.enabled = enabled
  }
  
  func log(_ message: String) {
    guard enabled else { return }
    let now = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "mm:ss.SSSS"
    queue.async {
      print("[\(formatter.string(from: now))] \(message)")
    }
  }

  func time(_ label: String) {
    guard enabled else { return }
    let startTime = Date()
    queue.async {
      // If the label already exists, we update the start time.
      self.timers[label] = startTime
    }
  }

  func timeEnd(_ label: String) {
    guard enabled else { return }
    let endTime = Date()
    queue.async {
      guard let startTime = self.timers[label] else { return }
      
      let duration = endTime.timeIntervalSince(startTime)
      print("\(label): \(String(format: "%.3f", duration * 1000)) ms")
      self.timers.removeValue(forKey: label)
    }
  }
}

