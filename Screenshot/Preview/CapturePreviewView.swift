import SwiftUI

/// The floating thumbnails of finished screenshots, newest at the bottom.
/// Clicking one opens it in the markup editor; two or more normal screenshots can be combined.
struct CapturePreviewView: View {
    let manager: CaptureResultManager

    @Environment(\.openWindow) private var openWindow

    private static let padding: CGFloat = 16
    private static let spacing: CGFloat = 8
    private static let combineButtonHeight: CGFloat = 32

    var body: some View {
        let width = Self.thumbnailWidth(count: manager.previewImages.count)
        VStack(spacing: Self.spacing) {
            ScrollView {
                VStack(spacing: Self.spacing) {
                    ForEach(manager.previewImages, id: \.self) { image in
                        CapturePreviewThumbnail(
                            image: image,
                            open: { open(image) },
                            close: { manager.removeFromPreview(image) }
                        )
                        .frame(width: width, height: Self.thumbnailHeight(for: image, width: width))
                    }
                }
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.bottom)

            if Self.showsCombineButton(count: manager.previewImages.count, canCombine: manager.canCombinePreview) {
                combineBar
                    .frame(height: Self.combineButtonHeight)
            }
        }
        .padding(Self.padding)
    }

    private var combineBar: some View {
        HStack {
            Button("Combine \(manager.previewImages.count)", systemImage: "square.grid.2x2") {
                openWindow(id: "collage")
            }
            .buttonStyle(.glassProminent)
            Spacer()
            Button("Close All", systemImage: "xmark") {
                manager.dismissPreview()
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
            .help("Close All")
        }
    }

    private func open(_ image: NSImage) {
        manager.openInEditor(image)
        openWindow(id: "markup-editor")
    }

    // MARK: - Size

    /// The panel's size, so `CaptureResultManager` can fit its window to the thumbnails.
    static func size(for images: [NSImage], showsCombineButton canCombine: Bool) -> CGSize {
        let width = thumbnailWidth(count: images.count)
        let thumbnailsHeight = images.reduce(CGFloat(0)) { $0 + thumbnailHeight(for: $1, width: width) }
            + spacing * CGFloat(max(0, images.count - 1))
        let combineHeight = showsCombineButton(count: images.count, canCombine: canCombine)
            ? spacing + combineButtonHeight
            : 0
        return CGSize(
            width: width + 2 * padding,
            height: thumbnailsHeight + combineHeight + 2 * padding
        )
    }

    /// A single screenshot gets a big thumbnail; a pile gets smaller ones so it fits on the screen.
    private static func thumbnailWidth(count: Int) -> CGFloat {
        count <= 1 ? 328 : 220
    }

    private static func thumbnailHeight(for image: NSImage, width: CGFloat) -> CGFloat {
        let aspectRatio = image.size.width / max(1, image.size.height)
        return min(200, max(80, width / max(0.1, aspectRatio)))
    }

    private static func showsCombineButton(count: Int, canCombine: Bool) -> Bool {
        canCombine && count >= 2
    }
}
