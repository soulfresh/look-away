import Foundation

enum TimeUnit: String, CaseIterable, Identifiable, Codable, Equatable {
  case second
  case minute
  case hour

  var id: Self { self }

  func pluralized<T: Numeric & Comparable>(for value: T) -> String {
    if value == 1 {
      return self.rawValue
    }
    return self.rawValue + "s"
  }

  /// Converts a `TimeInterval` (in seconds) to this unit.
  func fromSeconds(_ seconds: TimeInterval) -> Double {
    switch self {
    case .second: return seconds
    case .minute: return seconds / 60
    case .hour: return seconds / 3600
    }
  }

  /// Converts a value from this unit to a `TimeInterval` (in seconds).
  func toSeconds(_ value: Double) -> TimeInterval {
    switch self {
    case .second: return value
    case .minute: return value * 60
    case .hour: return value * 3600
    }
  }
}

struct TimeSpan: CustomStringConvertible, Equatable, Codable {
  var value: TimeInterval
  var unit: TimeUnit = .second

  /// The time span represented in seconds.
  var seconds: TimeInterval {
    return unit.toSeconds(value)
  }

  var description: String {
    "TimeSpan(\(value) \(unit.pluralized(for: value)))"
  }
  
  public static func == (lhs: TimeSpan, rhs: TimeSpan) -> Bool {
    return lhs.seconds == rhs.seconds
  }
}
