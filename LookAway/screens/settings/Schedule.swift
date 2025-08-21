import SwiftUI

struct Schedule: View {
  var appState: AppState
  var storage: Storage
  /// The logger used to create work cycle loggers
  var baseLogger: Logging
  /// The logger used to log events in this view.
  var logger: Logging

  /// The temporary schedule being edited by the user. When the view
  /// is removed, this schedule will be saved to disk and converted
  /// to a `WorkCycle` schedule and applied to the app state.
  @State var schedule: [WorkCycleConfig]
  /// Whether or not the user is reordering the schedule.
  @State private var isSorting = false

  init(state: AppState, storage: Storage, logger: Logging) {
    appState = state
    self.storage = storage

    let l = LogWrapper(
      logger: logger,
      label: "LookAwaySettings"
    )
    baseLogger = logger
    self.logger = l

    // Load the last saved schedule from disk.
    _schedule = State(initialValue: storage.loadSchedule())

    // When the settings window is opened, pause the app state to prevent
    // the app from blocking user interaction while the settings are being edited.
    appState.schedule.pause()
  }

  var body: some View {
    let removable = Binding<Bool>(
      get: { schedule.count > 1 },
      set: { _ in }
    )

    List {
      ForEach(schedule.indices, id: \.self) { index in
        let cycleBinding = Binding<WorkCycleConfig>(
          get: { schedule[index] },
          set: { updatedCycle in
            schedule[index] = updatedCycle
            // Force SwiftUI to recognize the change by re-assigning the array
            schedule = schedule
          }
        )
        // TODO: I was hoping that wrapping the `List` with a `Form` would allow
        // users to tab between all rows as a single form. However,
        // doing that treats each row as a separate form and breaks the
        // default text field styling. For now I've wrapped each row in a
        // `Form` in order to maintain the default label styling.
        //
        // At some point I'll either need to ask how to
        // resolve this on a SwiftUI forum or implement some custom
        // behavior to acheive the following:
        // - Each input should be focusable across rows
        // - Each Picker should be focusable and openable with the keyboard
        // - Each +/- button should be focusable and triggerable with the keyboard
        Form {
          WorkCycleFormRow(
            cycle: cycleBinding,
            onAdd: addWorkCycle,
            onRemove: removeWorkCycle,
            draggingEnabled: $isSorting,
            canBeRemoved: removable,
          )
        }
      }
      .onMove(perform: isSorting ? moveWorkCycle : nil)
    }
    .onChange(of: schedule) { _, _ in
      logger.log("Schedule changed, saving to disk...")

      for (index, cycle) in schedule.enumerated() {
        logger.log("  \(index + 1): \(cycle)")
      }
    }
    .onDisappear {
      saveAppState()
    }
    .toolbar {
      ToolbarItem {
        Button(action: {
          isSorting.toggle()
        }) {
          Image(
            systemName: isSorting ? "checkmark" : "arrow.up.arrow.down",
          )
          .imageScale(.small)
          Text(isSorting ? "Done" : "Reorder")
        }
      }
    }
  }

  private func addWorkCycle(basedOn id: UUID) {
    let index = schedule.firstIndex(where: { $0.id == id })

    // TODO Create a generic one instead
    guard let index = index else {
      logger.error("No work cycle found with id \(id)")
      return
    }

    let cycle = schedule[index]

    // TODO I don't think these are getting unique ids. That or searching for
    // the cycle by id isn't returning the correct one.
    let newCycle = WorkCycleConfig(
      workLength: cycle.workLength,
      breakLength: cycle.breakLength
    )
    schedule.insert(newCycle, at: index + 1)
  }

  private func removeWorkCycle(id: UUID) {
    schedule.removeAll { $0.id == id }
  }

  private func moveWorkCycle(from source: IndexSet, to destination: Int) {
    schedule.move(fromOffsets: source, toOffset: destination)
  }

  private func saveAppState() {
    logger.log("Updating application schedule")
    guard !schedule.isEmpty else {
      logger.error("Tried to save an empty schedule. Skipping save to disk.")
      return
    }

    // Save the current app state to disk.
    storage.saveSchedule(schedule)

    logger.log("Starting new schedule...")
    // Update app state with the new schedule.
    appState.schedule.setSchedule(
      schedule.enumerated().map { i, config in
        WorkCycle(
          frequency: config.workLength,
          duration: config.breakLength,
          logger: LogWrapper(
            // TODO Initialize the view with the app logger and use that to initialize the work cycle logger
            logger: baseLogger,
            label: "WorkCycle \(i + 1)".blue()
          )
        )
      })

    // Start the new schedule.
    appState.schedule.start()
  }
}

#Preview {
  Schedule(
    state: AppState(
      schedule: [
        WorkCycle(
          frequency: TimeSpan(value: 10, unit: .minute),
          duration: TimeSpan(value: 5, unit: .minute),
          logger: Logger(),
        )
      ],
      logger: Logger()
    ),
    storage: Storage(logger: Logger()),
    logger: Logger()
  )
}
