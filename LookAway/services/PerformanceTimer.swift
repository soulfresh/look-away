import Foundation

class PerformanceTimer {
  private let queue = DispatchQueue(label: "com.lookaway.performanceTimer")
  private var timers: [String: Date] = [:]

  func time(_ label: String) {
    let startTime = Date()
    queue.async {
      // If the label already exists, we update the start time.
      self.timers[label] = startTime
    }
  }

  func timeEnd(_ label: String) {
    let endTime = Date()
    queue.async {
      guard let startTime = self.timers[label] else { return }
      
      let duration = endTime.timeIntervalSince(startTime)
      print("\(label): \(String(format: "%.3f", duration * 1000)) ms")
      self.timers.removeValue(forKey: label)
    }
  }
}

