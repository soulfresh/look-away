import SwiftUI
import UniformTypeIdentifiers

let PADDING: CGFloat = 8.0
let WORK_CYCLE_CONFIG_KEY = "schedule"

/// 4 quick eye breaks and 1 long break per hour
let DEFAULT_SCHEDULE: [WorkCycleConfig] = [
  WorkCycleConfig(
    frequency: TimeSpan(value: 15, unit: .minute),
    duration: TimeSpan(value: 10, unit: .second)
  ),
  WorkCycleConfig(
    frequency: TimeSpan(value: 15, unit: .minute),
    duration: TimeSpan(value: 10, unit: .second)
  ),
  WorkCycleConfig(
    frequency: TimeSpan(value: 15, unit: .minute),
    duration: TimeSpan(value: 10, unit: .second)
  ),
  WorkCycleConfig(
    frequency: TimeSpan(value: 15, unit: .minute),
    duration: TimeSpan(value: 5, unit: .minute)
  ),
]

struct LookAwaySettings: View {
  var appState: AppState
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

  init(_ state: AppState, _ logger: Logging) {
    appState = state
    
    let l = LogWrapper(
      logger: logger,
      label: "LookAwaySettings"
    )
    baseLogger = logger
    self.logger = l

    // Load the last saved schedule from disk.
    _schedule = State(initialValue: LookAwaySettings.loadSchedule(logger: l))

    // When the settings window is opened, pause the app state to prevent
    // the app from blocking user interaction while the settings are being edited.
    appState.pause()
  }

  var body: some View {
    let removable = Binding<Bool>(
      get: { schedule.count > 1 },
      set: { _ in }
    )

    List {
      ForEach($schedule) { cycle in
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
            cycle: cycle,
            onAdd: addWorkCycle,
            onRemove: removeWorkCycle,
            draggingEnabled: $isSorting,
            canBeRemoved: removable,
          )
        }
      }
      .onMove(perform: isSorting ? moveWorkCycle : nil)
    }
    .onDisappear {
      saveAppState()
    }
    .toolbar {
      ToolbarItem {
        Button(isSorting ? "Done" : "Reorder") {
          isSorting.toggle()
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
      frequency: cycle.frequency,
      duration: cycle.duration
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
    logger.log("Updating application schedule to \(schedule)")
    guard !schedule.isEmpty else {
      logger.error("Tried to save an empty schedule. Skipping save to disk.")
      return
    }

    // Save the current app state to disk.
    saveSchedule(schedule)

    logger.log("Starting new schedule...")
    // Update app state with the new schedule.
    appState.setSchedule(
      schedule.enumerated().map { i, config in
        WorkCycle(
          frequency: config.frequency,
          duration: config.duration,
          logger: LogWrapper(
            // TODO Initialize the view with the app logger and use that to initialize the work cycle logger
            logger: baseLogger,
            label: "WorkCycle \(i + 1)".blue()
          )
        )
      })
  }
  
  /// Get the last saved schedule or the default schedule.
  /// This is a static function so it can be called before the view
  /// is fully initialized.
  static func loadSchedule(logger: Logging) -> [WorkCycleConfig] {
    logger.log("Loading schedule from disk.")
    // Load the last saved schedule from disk.
    if let data = UserDefaults.standard.data(forKey: WORK_CYCLE_CONFIG_KEY) {
      do {
        return try JSONDecoder()
          .decode([WorkCycleConfig].self, from: data)
      } catch {
        logger.error("Failed to decode schedule data: \(error)")
      }
    }
    
    logger.log("No saved schedule found. Using default schedule.")
    return DEFAULT_SCHEDULE
  }
  
  /// Save the given schedule to disk.
  private func saveSchedule(_ schedule: [WorkCycleConfig]) {
    logger.log("Saving schedule to disk: \(schedule)")
    // Save the current app state to disk.
    if let data = try? JSONEncoder().encode(schedule) {
      UserDefaults.standard.set(data, forKey: WORK_CYCLE_CONFIG_KEY)
    } else {
      logger.error("Failed to encode schedule data: \(schedule)")
    }
  }
}

//struct PressActions: ViewModifier {
//  @State var pressed = false
//
//  var onPress: () -> Void
//  var onRelease: () -> Void
//
//  func body(content: Content) -> some View {
//    content
//      .simultaneousGesture(
//        DragGesture(minimumDistance: 0)
//          .onChanged({ _ in
//            if !pressed {
//              pressed = true
//              onPress()
//            }
//          })
//          .onEnded({ _ in
//            if pressed {
//              onRelease()
//            }
//          })
//      )
//  }
//}

#Preview {
  LookAwaySettings(
    AppState(
      schedule: [
        WorkCycle(
          frequency: TimeSpan(value: 10, unit: .minute),
          duration: TimeSpan(value: 5, unit: .minute),
          logger: Logger(),
        )
      ],
      logger: Logger()
    ),
    Logger()
  )
}
