import SwiftUI

struct ActionButton<Label: View>: View {
  private var color: Color = .accentColor
  let action: () -> Void
  let label: () -> Label

  init(
    color: Color = .accentColor,
    action: @escaping () -> Void,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.color = color
    self.action = action
    self.label = label
  }

  var body: some View {
    Button(action: action) {
      label()
        .padding()
    }
    .buttonStyle(.plain)
    .foregroundColor(.white)
    .background(Color.black.opacity(0.1))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.5), lineWidth: 1)
    )
  }
}

extension ActionButton where Label == Text {
  init(_ title: String, action: @escaping () -> Void) {
    self.init(action: action) {
      Text(title)
    }
  }

  init(title: String, color: Color, action: @escaping () -> Void) {
    self.init(color: color, action: action) {
      Text(title)
    }
  }
}

#Preview {
  ActionButton(title: "Click Me", color: .accentColor) {
    print("Button clicked!")
  }
  .padding()
}
