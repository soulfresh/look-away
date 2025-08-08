import SwiftUI

struct KeyHintButton: View {
  let title: String
  let key: String
  let color: Color
  let action: () -> Void

  init(
    title: String,
    key: String,
    color: Color = .accentColor,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.key = key
    self.color = color
    self.action = action
  }

  var body: some View {
    ActionButton(color: color, action: action) {
      HStack {
        Text(title)
        HStack(spacing: 0) {

          Text("[")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.2))
          Text(key)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.6))
          Text("]")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.2))
        }
      }
    }
  }
}

#Preview {
  KeyHintButton(title: "Press", key: "K", action: {})
    .padding()
}
