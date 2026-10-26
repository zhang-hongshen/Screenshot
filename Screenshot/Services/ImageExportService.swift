import AppKit
import UniformTypeIdentifiers

/// Sends a finished screenshot to the pasteboard, a PNG file, or the system share menu.
@MainActor
final class ImageExportService {
    static let shared = ImageExportService()

    /// The share menu disappears if nothing keeps a reference to it while it is open.
    private var sharingPicker: NSSharingServicePicker?

    func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    /// Asks where to save and writes a PNG. Returns false when the user cancels or writing fails.
    @discardableResult
    func save(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot.png"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }

    func share(_ image: NSImage) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [image])
        sharingPicker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
