import SwiftUI

/// Provides a single row in the work cycle form. This includes
/// the work cycle form, add/remove buttons, and a drag handle.
struct WorkCycleFormRow: View {
  @Binding var cycle: WorkCycleConfig
  var onAdd: (_ id: UUID) -> Void
  var onRemove: (_ id: UUID) -> Void
  @Binding var draggingEnabled: Bool
  @Binding var canBeRemoved: Bool
  var isBeingDragged: Bool = false

  var body: some View {
    let editable = Binding<Bool>(
      get: { !draggingEnabled },
      set: { draggingEnabled = !$0 }
    )

    HStack {
      WorkCycleForm(
        workCycle: $cycle,
        editable: editable,
      )
      .padding(.vertical, PADDING)

      Spacer()

      if draggingEnabled {
        Image(
          systemName: "line.horizontal.3",
        )
        .foregroundColor(.secondary)
        .padding(PADDING)
      } else {
        Button(action: {
          onAdd(cycle.id)
        }) {
          Image(systemName: "plus.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.theme.success)

        Button(action: {
          onRemove(cycle.id)
        }) {
          Image(systemName: "minus.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.theme.error)
        .disabled(!canBeRemoved)
      }
    }
    // .onHover { hovering in
    //   if hovering {
    //     NSCursor.openHand.push()
    //   } else {
    //     NSCursor.pop()
    //   }
    // }
    .opacity(isBeingDragged ? 0.3 : 1.0)
  }
}

#Preview {
  Form {
    VStack(alignment: .leading, spacing: 0) {
      Text("default:")
      WorkCycleFormRow(
        cycle: .constant(
          WorkCycleConfig(
            workLength: TimeSpan(value: 30, unit: .minute),
            breakLength: TimeSpan(value: 10, unit: .second),
          )
        ),
        onAdd: { _ in },
        onRemove: { _ in },
        draggingEnabled: .constant(false),
        canBeRemoved: .constant(false),
      )

      Text("removeable:").padding(.top, 16)
      WorkCycleFormRow(
        cycle: .constant(
          WorkCycleConfig(
            workLength: TimeSpan(value: 30, unit: .minute),
            breakLength: TimeSpan(value: 10, unit: .second),
          )),
        onAdd: { _ in },
        onRemove: { _ in },
        draggingEnabled: .constant(false),
        canBeRemoved: .constant(true),
      )

      Text("draggable:").padding(.top, 16)
      WorkCycleFormRow(
        cycle: .constant(
          WorkCycleConfig(
            workLength: TimeSpan(value: 30, unit: .second),
            breakLength: TimeSpan(value: 10, unit: .minute),
          )),
        onAdd: { _ in },
        onRemove: { _ in },
        draggingEnabled: .constant(true),
        canBeRemoved: .constant(true),
      )

      Text("dragging:").padding(.top, 16)
      WorkCycleFormRow(
        cycle: .constant(
          WorkCycleConfig(
            workLength: TimeSpan(value: 30, unit: .second),
            breakLength: TimeSpan(value: 10, unit: .minute),
          )),
        onAdd: { _ in },
        onRemove: { _ in },
        draggingEnabled: .constant(true),
        canBeRemoved: .constant(true),
        isBeingDragged: true
      )

    }
    .padding()
  }
}
