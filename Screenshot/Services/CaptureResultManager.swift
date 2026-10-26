import SwiftUI

/// Keeps the latest finished screenshot and the floating preview in the corner of the screen.
///
/// Normal screenshots pile up in the preview so several can be combined into a collage.
/// `@Observable` lets the preview and the editor windows redraw when the screenshots change.
@Observable
final class CaptureResultManager {
    static let shared = CaptureResultManager()
    static let maximumPreviewCount = 6

    private(set) var latestImage: NSImage?
    /// The screenshots shown in the corner, oldest first.
    private(set) var previewImages: [NSImage] = []
    /// False while the preview shows a scrolling capture, which is never combined.
    private(set) var canCombinePreview = false
    @ObservationIgnored private var previewWindow: CapturePreviewWindow?
    @ObservationIgnored private var previewScreen: NSScreen?

    /// Adds a normal screenshot to the preview, next to the ones already there.
    func addToPreview(_ image: NSImage, takenAt frame: CGRect) {
        if !canCombinePreview {
            previewImages = []
        }
        previewImages = Array((previewImages + [image]).suffix(Self.maximumPreviewCount))
        canCombinePreview = true
        latestImage = image
        showPreviewWindow(on: ScreenCoordinates.screenContainingMost(ofAppKitRect: frame))
    }

    /// Shows a scrolling capture on its own.
    func showPreview(of image: NSImage, takenAt frame: CGRect) {
        previewImages = [image]
        canCombinePreview = false
        latestImage = image
        showPreviewWindow(on: ScreenCoordinates.screenContainingMost(ofAppKitRect: frame))
    }

    /// Makes `image` the one the markup editor shows and takes it out of the preview.
    func openInEditor(_ image: NSImage) {
        latestImage = image
        removeFromPreview(image)
    }

    func removeFromPreview(_ image: NSImage) {
        previewImages.removeAll { $0 === image }
        if previewImages.isEmpty {
            dismissPreview()
        } else {
            showPreviewWindow(on: previewScreen)
        }
    }

    /// The finished collage replaces the screenshots it was made from.
    func openCollageInEditor(_ collage: NSImage) {
        dismissPreview()
        latestImage = collage
    }

    func dismissPreview() {
        previewWindow?.close()
        previewWindow = nil
        previewImages = []
    }

    func discard() {
        dismissPreview()
        latestImage = nil
    }

    /// Fits the panel to the thumbnails, keeping it in the bottom right corner of the screen.
    private func showPreviewWindow(on screen: NSScreen?) {
        guard let screen else { return }
        previewScreen = screen
        let margin: CGFloat = 20
        let contentSize = CapturePreviewView.size(
            for: previewImages,
            showsCombineButton: canCombinePreview
        )
        let size = CGSize(
            width: contentSize.width,
            height: min(contentSize.height, screen.visibleFrame.height - 2 * margin)
        )
        let frame = CGRect(
            origin: CGPoint(
                x: screen.visibleFrame.maxX - size.width - margin,
                y: screen.visibleFrame.minY + margin
            ),
            size: size
        )

        if let previewWindow {
            previewWindow.setFrame(frame, display: true)
        } else {
            let window = CapturePreviewWindow(contentRect: frame)
            window.contentView = NSHostingView(rootView: CapturePreviewView(manager: self))
            previewWindow = window
        }
        previewWindow?.makeKeyAndOrderFront(nil)
    }
}
