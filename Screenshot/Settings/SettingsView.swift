import SwiftUI

/// The Settings window.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutsSettingsView()
                    .padding()
            }
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
                    .padding()
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}

#Preview {
    SettingsView()
}
