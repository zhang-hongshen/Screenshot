import AppKit
import SwiftUI

/// Reads the text in the screenshot and copies it, shared by the window toolbar and the capture overlay.
struct ExtractTextButton: View {
    let image: NSImage?

    @State private var isRecognizing = false

    var body: some View {
        Button("Extract Text", systemImage: "text.viewfinder", action: extractText)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(image == nil || isRecognizing)
            .help(isRecognizing ? "Reading text…" : "Copy the text in the screenshot")
    }

    private func extractText() {
        guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        isRecognizing = true
        Task {
            defer { isRecognizing = false }
            do {
                let text = try await TextRecognizer.text(in: cgImage)
                if text.isEmpty {
                    NSSound.beep()
                } else {
                    ImageExportService.shared.copy(text)
                }
            } catch {
                NSSound.beep()
            }
        }
    }
}
