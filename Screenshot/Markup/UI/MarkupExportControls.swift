import SwiftUI

/// Copy, Save and Share, shared by the window toolbar and the capture overlay.
struct MarkupExportControls: View {
    let copy: () -> Void
    let save: () -> Void
    let share: () -> Void

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc", action: copy)
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy")
        Button("Save", systemImage: "square.and.arrow.down", action: save)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save")
        Button("Share", systemImage: "square.and.arrow.up", action: share)
            .help("Share")
    }
}
