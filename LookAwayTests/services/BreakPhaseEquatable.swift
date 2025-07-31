import Foundation

/// Allows comparing the `Break.Phase` enum for equality.
extension Break.Phase: Equatable {
  public static func == (lhs: Break.Phase, rhs: Break.Phase) -> Bool {
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
