import Foundation
import SwiftUI

/// Provides the form to configure a single work cycle.
struct WorkCycleForm: View {
  @Binding var workCycle: WorkCycleConfig
  @Binding var editable: Bool

  init(workCycle: Binding<WorkCycleConfig>, editable: Binding<Bool>) {
    self._workCycle = workCycle
    self._editable = editable
  }

  var body: some View {
    HStack(spacing: 0) {
      DurationForm(
        timeSpan: $workCycle.breakLength,
        editable: $editable,
        label: "Take a",
        options: [TimeUnit.second, TimeUnit.minute],
        pluralized: false,
        suffix: "break"
      )
      .padding(.trailing, 30)

      DurationForm(
        timeSpan: $workCycle.workLength,
        editable: $editable,
        label: "after",
        options: [TimeUnit.minute, TimeUnit.hour]
      )
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
            workLength: TimeSpan(value: 15, unit: .minute),
            breakLength: TimeSpan(value: 30, unit: .second),
          )
        ),
        editable: .constant(true)
      )

      Text("summarized:").padding(.top, 20)
        .foregroundStyle(.secondary)
      WorkCycleForm(
        workCycle: .constant(
          WorkCycleConfig(
            workLength: TimeSpan(value: 15, unit: .minute),
            breakLength: TimeSpan(value: 30, unit: .second),
          )
        ),
        editable: .constant(false)
      )
    }
    //  .border(Color.blue)
    .padding(20)
  }
}
