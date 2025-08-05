import Foundation

/// Allows comparing the `Break.Phase` enum for equality.
extension WorkCycle.Phase: Equatable {
  public static func == (lhs: WorkCycle.Phase, rhs: WorkCycle.Phase) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle):
      return true
    case (.working(let lhsRemaining), .working(let rhsRemaining)):
      return lhsRemaining == rhsRemaining
    case (.breaking(let lhsRemaining), .breaking(let rhsRemaining)):
      return lhsRemaining == rhsRemaining
    case (.finished, .finished):
      return true
    default:
      return false
    }
  }
}
