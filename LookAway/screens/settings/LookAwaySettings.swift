import SwiftUI
import UniformTypeIdentifiers

struct LookAwaySettings: View {
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
  }

  var body: some View {
    TabView {
      General()
        .tabItem {
          Label("General", systemImage: "gear")
        }

      Schedule(state: appState, storage: storage, logger: baseLogger)
        .tabItem {
          Label("Schedule", systemImage: "clock")
        }

      Shortcuts()
        .tabItem {
          Label("Shortcuts", systemImage: "info.circle")
        }
    }
    .onAppear {
      // Pause the schedule when the settings window is opened.
      appState.schedule.pause()
    }
    .onDisappear {
      // Resume the schedule when the settings window is closed.
      // This ensures the schedule resumes regardless of which tab was visited.
      appState.schedule.resume()
    }
  }
}

#Preview {
  LookAwaySettings(
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
