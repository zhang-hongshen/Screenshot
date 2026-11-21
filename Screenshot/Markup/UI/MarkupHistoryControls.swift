import AppKit
import SwiftUI

/// Two independent history buttons; their parent provides the native toolbar or overlay grouping.
struct MarkupHistoryControls: View {
    let bridge: MarkupEditorBridge
    let document: MarkupDocument
    @Environment(\.undoManager) private var windowUndoManager

    var body: some View {
        Group {
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!canUndo || document.imageEdits.isProcessing)
                .help("Undo")
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!canRedo || document.imageEdits.isProcessing)
                .help("Redo")
        }
        .labelStyle(.iconOnly)
    }

    private var isBrush: Bool { bridge.tool == .eraseText || bridge.tool == .blur }
    private var paperUndoManager: UndoManager? {
        // PaperKit's delegate updates the document when edits or undo change its markup.
        _ = document.markup
        return bridge.markupController.undoManager ?? windowUndoManager
    }
    private var canUndo: Bool { isBrush ? document.imageEdits.canUndo : paperUndoManager?.canUndo == true }
    private var canRedo: Bool { isBrush ? document.imageEdits.canRedo : paperUndoManager?.canRedo == true }

    private func undo() {
        if isBrush { document.imageEdits.undo() } else { paperUndoManager?.undo() }
    }

    private func redo() {
        if isBrush { document.imageEdits.redo() } else { paperUndoManager?.redo() }
    }
}
