import AppKit
import CoreGraphics
import Observation
import PaperKit

/// Everything needed to render the markup later, taken at the moment the user exports.
struct MarkupSnapshot {
    let markup: PaperMarkup
    var editedImage: NSImage? = nil
}

/// The editable state of one screenshot: PaperKit markup and destructive brush edits with undo.
@MainActor
@Observable
final class MarkupDocument {
    let imageEdits = MarkupImageSession()
    var markup: PaperMarkup
    var contentVisibleFrame: CGRect
    let imageSize: CGSize

    init(imageSize: CGSize, markup: PaperMarkup? = nil) {
        let bounds = CGRect(origin: .zero, size: imageSize)
        self.imageSize = imageSize
        self.markup = markup ?? PaperMarkup(bounds: bounds)
        self.contentVisibleFrame = bounds
    }

    func snapshot() -> MarkupSnapshot {
        MarkupSnapshot(markup: markup, editedImage: imageEdits.acceptedImage)
    }
}

/// Converts between view points and image points while the canvas is zoomed or scrolled.
struct MarkupCoordinateMapper {
    let viewSize: CGSize
    let visibleContentFrame: CGRect
    let imageSize: CGSize

    private var scaleX: CGFloat {
        viewSize.width / max(1, visibleContentFrame.width)
    }

    private var scaleY: CGFloat {
        viewSize.height / max(1, visibleContentFrame.height)
    }

    var imageDisplayFrame: CGRect {
        CGRect(
            x: -visibleContentFrame.minX * scaleX,
            y: -visibleContentFrame.minY * scaleY,
            width: imageSize.width * scaleX,
            height: imageSize.height * scaleY
        )
    }

    func imagePoint(fromView point: CGPoint, clampedToImage: Bool = true) -> CGPoint {
        let imagePoint = CGPoint(
            x: visibleContentFrame.minX + point.x / max(0.0001, scaleX),
            y: visibleContentFrame.minY + point.y / max(0.0001, scaleY)
        )
        return clampedToImage
            ? imagePoint.clampedToMarkupBounds(CGRect(origin: .zero, size: imageSize))
            : imagePoint
    }

    func viewRect(fromImage rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - visibleContentFrame.minX) * scaleX,
            y: (rect.minY - visibleContentFrame.minY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
}

private extension CGPoint {
    func clampedToMarkupBounds(_ bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, bounds.minX), bounds.maxX),
            y: min(max(y, bounds.minY), bounds.maxY)
        )
    }
}
