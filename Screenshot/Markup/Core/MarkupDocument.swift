import CoreGraphics
import Foundation
import Observation
import PaperKit

/// A rectangle of the screenshot that is shown pixelated, in image points.
struct RedactionRegion: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect

    init(id: UUID = UUID(), rect: CGRect) {
        self.id = id
        self.rect = rect.standardized
    }
}

/// Everything needed to render the markup later, taken at the moment the user exports.
struct MarkupSnapshot {
    let markup: PaperMarkup
    let redactions: [RedactionRegion]
}

/// The editable state of one screenshot: PaperKit markup plus the blur regions Screenshot adds on top.
@MainActor
@Observable
final class MarkupDocument {
    var markup: PaperMarkup
    var redactions: [RedactionRegion] = []
    var selectedRedactionIDs: Set<UUID> = []
    /// While true, drags draw blur regions instead of PaperKit markup.
    var isRedactionMode = false {
        didSet {
            if !isRedactionMode {
                selectedRedactionIDs.removeAll()
            }
        }
    }
    var contentVisibleFrame: CGRect

    let imageSize: CGSize

    private var imageBounds: CGRect {
        CGRect(origin: .zero, size: imageSize)
    }

    init(imageSize: CGSize, markup: PaperMarkup? = nil) {
        let bounds = CGRect(origin: .zero, size: imageSize)
        self.imageSize = imageSize
        self.markup = markup ?? PaperMarkup(bounds: bounds)
        self.contentVisibleFrame = bounds
    }

    func snapshot() -> MarkupSnapshot {
        MarkupSnapshot(markup: markup, redactions: redactions)
    }

    func addRedaction(from start: CGPoint, to end: CGPoint) {
        let rect = normalizedRect(from: start, to: end)
        guard rect.width >= 2, rect.height >= 2 else { return }
        let redaction = RedactionRegion(rect: rect)
        redactions.append(redaction)
        selectedRedactionIDs = [redaction.id]
    }

    func selectRedaction(id: UUID?) {
        selectedRedactionIDs = id.map { [$0] } ?? []
    }

    func deleteSelectedRedactions() {
        guard !selectedRedactionIDs.isEmpty else { return }
        redactions.removeAll { selectedRedactionIDs.contains($0.id) }
        selectedRedactionIDs.removeAll()
    }

    func handleDeleteKey() -> Bool {
        guard isRedactionMode, !selectedRedactionIDs.isEmpty else { return false }
        deleteSelectedRedactions()
        return true
    }

    func redaction(at point: CGPoint) -> RedactionRegion? {
        redactions.last { $0.rect.contains(point) }
    }

    func updateRedaction(id: UUID, rect: CGRect) {
        guard let index = redactions.firstIndex(where: { $0.id == id }) else { return }
        redactions[index].rect = rect.standardized.intersection(imageBounds)
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        .intersection(imageBounds)
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

    func imagePoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(
            x: visibleContentFrame.minX + point.x / max(0.0001, scaleX),
            y: visibleContentFrame.minY + point.y / max(0.0001, scaleY)
        )
        .clampedToMarkupBounds(CGRect(origin: .zero, size: imageSize))
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
