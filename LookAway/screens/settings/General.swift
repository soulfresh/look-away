import ServiceManagement
import SwiftUI

struct General: View {
  /// The log file URL, if logging to a file is enabled
  var logFileURL: URL?

  @State private var launchAtLogin = false
  @State private var showError: Bool = false
  @State private var errorMessage: String = ""

  var body: some View {
    Form {
      Spacer()
      HStack {
        Spacer()

        Toggle("Launch at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            setLaunchAtLogin(enabled: newValue)
          }
          .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
          }

        Spacer()
      }
      Spacer()

      if let logFileURL = logFileURL {
        HStack {
          Spacer()
          Button("Show logs") {
            NSWorkspace.shared.open(logFileURL)
          }
          .buttonStyle(.link)
          .font(.caption)
          .foregroundStyle(.gray)
        }
      }
    }
    .padding()
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func setLaunchAtLogin(enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      // Revert the toggle if the operation failed
      launchAtLogin = !enabled
      errorMessage =
        "Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
      showError = true
    }
  }
}

#Preview {
  General(logFileURL: Logger.defaultLogFileURL())
    .frame(width: 400, height: 400)
}
