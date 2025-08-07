import Foundation
import SwiftUI

let PICKER_WIDTH = 90.0
let TEXTFIELD_WIDTH = 45.0

/// Shows a number input and a picker for time units in order to specify
/// a single time duration.
struct DurationForm: View {
  @Binding var timeSpan: TimeSpan
  @Binding var editable: Bool
  var label: String
  var options: [TimeUnit]
  var pluralized: Bool = true
  var suffix = ""

  var body: some View {
    HStack(spacing: 0) {
      if editable {
        TextField(label, value: $timeSpan.value, format: .number)
          .frame(
            minWidth: TEXTFIELD_WIDTH,
            maxWidth: TEXTFIELD_WIDTH * 2,
            alignment: .leading
          )
        Picker("", selection: $timeSpan.unit) {
          ForEach(options) { unit in
            Text(pluralized ? unit.pluralized(for: timeSpan.value) : unit.rawValue).tag(unit)
          }
        }
        .focusable()
//        .keyboardShortcut(.space)
        .frame(width: PICKER_WIDTH)

        if !suffix.isEmpty {
          Text(suffix)
            .padding(.leading, 8)

        }
      } else {
        Text(
          "\(label) \(timeSpan.value, format: .number) \(pluralized ? timeSpan.unit.pluralized(for: timeSpan.value) : timeSpan.unit.rawValue) \(suffix)"
        )
        .foregroundColor(.mint)
      }
    }
  }
}

#Preview {
  Form {
    VStack(alignment: .leading, spacing: 10) {
      DurationForm(
        timeSpan: .constant(TimeSpan(value: 5, unit: .second)),
        editable: .constant(true),
        label: "Take a",
        options: [TimeUnit.second, TimeUnit.minute],
      )
      DurationForm(
        timeSpan: .constant(TimeSpan(value: 15, unit: .minute)),
        editable: .constant(true),
        label: "Take a",
        options: [TimeUnit.minute, TimeUnit.hour]
      )
      DurationForm(
        timeSpan: .constant(TimeSpan(value: 2, unit: .hour)),
        editable: .constant(true),
        label: "Take a",
        options: [TimeUnit.minute, TimeUnit.hour],
        suffix: "break"
      )
      DurationForm(
        timeSpan: .constant(TimeSpan(value: 2, unit: .hour)),
        editable: .constant(false),
        label: "Take a",
        options: [TimeUnit.minute, TimeUnit.hour]
      )
    }.padding(20)
  }
}
