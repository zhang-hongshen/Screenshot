import SwiftUI

/// The Settings window.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
                    .padding()
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                KeyboardSettingsView()
                    .padding()
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}

#Preview {
    SettingsView()
}
