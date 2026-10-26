import SwiftUI

/// The standalone markup window for the latest finished screenshot.
struct MarkupEditorView: View {
    let image: NSImage

    /// `@State` keeps the same document and PaperKit bridge alive while SwiftUI redraws this view.
    @State private var document: MarkupDocument
    @State private var markupBridge = MarkupEditorBridge()
    @State private var pixelatedImage: NSImage?
    @Environment(\.dismissWindow) private var dismissWindow

    init(image: NSImage) {
        self.image = image
        _document = State(initialValue: MarkupDocument(imageSize: image.size))
    }

    var body: some View {
        MarkupCanvasView(
            image: image,
            pixelatedImage: pixelatedImage,
            document: document,
            bridge: markupBridge
        )
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                MarkupToolControls(bridge: markupBridge)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass", action: markupBridge.zoomOut)
                    .keyboardShortcut("-", modifiers: .command)
                Button("Zoom In", systemImage: "plus.magnifyingglass", action: markupBridge.zoomIn)
                    .keyboardShortcut("+", modifiers: .command)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                MarkupExportControls(
                    copy: { export { ImageExportService.shared.copy($0) } },
                    save: { export { ImageExportService.shared.save($0) } },
                    share: { export { ImageExportService.shared.share($0) } }
                )
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Done", systemImage: "checkmark", action: finish)
                    .buttonStyle(.glassProminent)
                    .help("Copy and close")
            }
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            document.handleDeleteKey() ? .handled : .ignored
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Pixelating the whole image takes a moment, so do it once instead of on every redraw.
            pixelatedImage = MarkupRenderer.shared.pixelatedImage(for: image)
        }
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
        let pixelatedImage = pixelatedImage ?? MarkupRenderer.shared.pixelatedImage(for: image)
        Task {
            let result = await MarkupRenderer.shared.renderedImage(
                image: image,
                pixelatedImage: pixelatedImage,
                snapshot: snapshot
            )
            if let result {
                action(result)
            }
        }
    }
}
