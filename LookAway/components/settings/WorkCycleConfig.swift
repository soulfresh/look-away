import Foundation

struct WorkCycleConfig: Identifiable, Codable {
  var id: UUID = UUID()
  var frequency: TimeSpan
  var duration: TimeSpan
}
