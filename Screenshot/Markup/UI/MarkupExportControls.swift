import SwiftUI

/// Copy, Save and Share in the editor canvas context menu.
struct MarkupExportControls: View {
    let copy: () -> Void
    let save: () -> Void
    let share: () -> Void

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc", action: copy)
            .help("Copy")
        Button("Save", systemImage: "square.and.arrow.down", action: save)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save")
        Button("Share", systemImage: "square.and.arrow.up", action: share)
            .help("Share")
    }
}
