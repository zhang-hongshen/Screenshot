import KeyboardShortcuts
import SwiftUI

/// Lets the user change the global capture shortcuts.
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture", name: .capture)
            KeyboardShortcuts.Recorder("Scrolling Capture", name: .scrollingCapture)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    ShortcutsSettingsView()
}
