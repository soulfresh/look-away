import Foundation
import SwiftUI

/// Provides the form to configure a single work cycle.
struct WorkCycleForm: View {
  @Binding var workCycle: WorkCycleConfig
  @Binding var editable: Bool

  @State private var duration: TimeSpan
  @State private var frequency: TimeSpan

  init(workCycle: Binding<WorkCycleConfig>, editable: Binding<Bool>) {
    self._workCycle = workCycle
    self._editable = editable
    self._duration = State(initialValue: workCycle.wrappedValue.duration)
    self._frequency = State(initialValue: workCycle.wrappedValue.frequency)
    print("frequency: \(frequency), duration: \(duration)")
  }

  var body: some View {
    HStack(spacing: 0) {
      DurationForm(
        timeSpan: $duration,
        editable: $editable,
        label: "Take a",
        options: [TimeUnit.second, TimeUnit.minute],
        pluralized: false,
        suffix: "break"
      )
      .padding(.trailing, 30)

      DurationForm(
        timeSpan: $frequency,
        editable: $editable,
        label: "after",
        options: [TimeUnit.minute, TimeUnit.hour])
    }
  }
}

#Preview {
  Form {
    VStack(alignment: .leading, spacing: 0) {
      Text("editable:")
        .foregroundStyle(.secondary)
      WorkCycleForm(
        workCycle: .constant(
          WorkCycleConfig(
            frequency: TimeSpan(value: 15, unit: .minute),
            duration: TimeSpan(value: 30, unit: .second),
          )
        ),
        editable: .constant(true)
      )

      Text("summarized:").padding(.top, 20)
        .foregroundStyle(.secondary)
      WorkCycleForm(
        workCycle: .constant(
          WorkCycleConfig(
            frequency: TimeSpan(value: 15, unit: .minute),
            duration: TimeSpan(value: 30, unit: .second),
          )
        ),
        editable: .constant(false)
      )
    }
    //  .border(Color.blue)
    .padding(20)
  }
}
