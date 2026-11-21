import SwiftUI

/// The standalone markup window for the latest finished screenshot.
struct MarkupEditorView: View {
    let image: NSImage

    /// `@State` keeps the same document and PaperKit bridge alive while SwiftUI redraws this view.
    @State private var document: MarkupDocument
    @State private var markupBridge = MarkupEditorBridge()
    @Environment(\.dismissWindow) private var dismissWindow

    init(image: NSImage) {
        self.image = image
        _document = State(initialValue: MarkupDocument(imageSize: image.size))
    }

    var body: some View {
        MarkupCanvasView(
            image: image,
            document: document,
            bridge: markupBridge
        )
        .contextMenu {
            MarkupExportControls(
                copy: copy,
                save: { export { ImageExportService.shared.save($0) } },
                share: { export { ImageExportService.shared.share($0) } }
            )
            .disabled(document.imageEdits.hasPendingChanges)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass", action: markupBridge.zoomOut)
                    .keyboardShortcut("-", modifiers: .command)
                Button("Zoom In", systemImage: "plus.magnifyingglass", action: markupBridge.zoomIn)
                    .keyboardShortcut("+", modifiers: .command)
            }
            ToolbarItem(placement: .principal) {
                MarkupToolControls(bridge: markupBridge)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                MarkupHistoryControls(bridge: markupBridge, document: document)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                ExtractTextButton(image: document.imageEdits.currentImage ?? image)
                    .disabled(document.imageEdits.hasPendingChanges)
                Button("Copy", systemImage: "doc.on.doc", action: copy)
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(document.imageEdits.hasPendingChanges)
                    .help("Copy")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Done", systemImage: "checkmark", action: finish)
                    .disabled(document.imageEdits.hasPendingChanges)
                    .buttonStyle(.glassProminent)
                    .help("Copy and close")
            }
        }
        .onDisappear { document.imageEdits.cancel() }
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            MarkupPointer(
                tool: markupBridge.tool,
                diameter: document.imageEdits.brushDiameter
            )
        }
    }

    private func copy() {
        export { ImageExportService.shared.copy($0) }
    }

    private func finish() {
        export { image in
            ImageExportService.shared.copy(image)
            dismissWindow()
        }
    }

    /// Renders the screenshot with its markup, then passes the result on.
    private func export(_ action: @escaping (NSImage) -> Void) {
        let snapshot = document.snapshot()
        Task {
            let result = await MarkupRenderer.shared.renderedImage(
                image: image,
                snapshot: snapshot
            )
            if let result {
                action(result)
            }
        }
    }
}
