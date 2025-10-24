import SwiftUI
import ServiceManagement

struct General: View {
  @State private var launchAtLogin = false
  @State private var showError: Bool = false
  @State private var errorMessage: String = ""

  var body: some View {
    Form {
      Toggle("Launch at login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, newValue in
          setLaunchAtLogin(enabled: newValue)
        }
        .onAppear {
          launchAtLogin = SMAppService.mainApp.status == .enabled
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
      errorMessage = "Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
      showError = true
    }
  }
}

#Preview {
  General()
}
