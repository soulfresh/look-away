import SwiftUI

struct ScoreText: View {
  let title: String
  let score: Int
  /// Whether a higher score represents a good thing.
  let positive: Bool

  init(title: String, score: Int, positive: Bool = true) {
    self.title = title
    self.score = score
    self.positive = positive
  }

  var body: some View {
    let color: Color =
      score == 0
      ? Color.gray
      : positive
        ? Color.theme.success
        : Color.theme.error
    HStack(spacing: 0) {
      Text("\(title): ")
        .foregroundStyle(Color.gray.opacity(0.3))
      Text("\(score)")
        .foregroundStyle(color.opacity(0.3))
    }
    .font(.system(size: 11))
  }
}

#Preview {
  VStack {
    ScoreText(title: "Good", score: 42, positive: true)
    ScoreText(title: "Bad", score: 7, positive: false)
  }
  .padding()
}
