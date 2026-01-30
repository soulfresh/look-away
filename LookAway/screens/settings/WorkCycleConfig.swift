import Foundation

struct WorkCycleConfig: Identifiable, Codable, Equatable, CustomStringConvertible {
  var id: UUID = UUID()
  var workLength: TimeSpan
  var breakLength: TimeSpan

  var description: String {
    return "WorkCycleConfig(\(workLength) -> \(breakLength))"
  }
}
