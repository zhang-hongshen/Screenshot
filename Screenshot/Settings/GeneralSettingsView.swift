import ServiceManagement
import SwiftUI

/// General preferences.
struct GeneralSettingsView: View {
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at Login", isOn: $opensAtLogin)
            .toggleStyle(.checkbox)
            .onChange(of: opensAtLogin) { _, opensAtLogin in
                do {
                    if opensAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Show what macOS actually did, for example when the user blocked it in System Settings.
                    self.opensAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 420, height: 220)
}
