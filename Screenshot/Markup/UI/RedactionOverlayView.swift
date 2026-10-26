import AppKit
import SwiftUI

/// Draws the blur regions above the markup and, in Blur mode, lets the user add, move and resize them.
struct RedactionOverlayView: View {
    @Bindable var document: MarkupDocument
    let pixelatedImage: NSImage?

    @State private var drag: RedactionDrag?
    @State private var draftRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let mapper = MarkupCoordinateMapper(
                viewSize: proxy.size,
                visibleContentFrame: document.contentVisibleFrame,
                imageSize: document.imageSize
            )

            ZStack(alignment: .topLeading) {
                RedactionCanvas(
                    redactions: document.redactions,
                    draftRect: draftRect,
                    pixelatedImage: pixelatedImage,
                    mapper: mapper
                )
                .allowsHitTesting(false)

                ForEach(document.redactions) { redaction in
                    let rect = mapper.viewRect(fromImage: redaction.rect)
                    MarkupSelectionOutline(rect: rect)
                        .opacity(document.isRedactionMode ? 1 : 0)
                    if document.selectedRedactionIDs.contains(redaction.id), document.isRedactionMode {
                        MarkupResizeHandles(rect: rect)
                    }
                }

                if let draftRect {
                    MarkupSelectionMarquee(rect: mapper.viewRect(fromImage: draftRect))
                }

                if document.isRedactionMode {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(redactionGesture(mapper: mapper))
                }
            }
            .clipped()
        }
    }

    private func redactionGesture(mapper: MarkupCoordinateMapper) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = mapper.imagePoint(fromView: value.startLocation)
                let current = mapper.imagePoint(fromView: value.location)

                if drag == nil {
                    drag = beginDrag(at: start, mapper: mapper)
                }

                switch drag {
                case .create(let origin):
                    draftRect = normalizedRect(from: origin, to: current)
                case .move(let ids, let originals, let origin):
                    for id in ids {
                        guard let original = originals[id] else { continue }
                        document.updateRedaction(
                            id: id,
                            rect: original.offsetBy(
                                dx: current.x - origin.x,
                                dy: current.y - origin.y
                            )
                        )
                    }
                case .resize(let id, let original, let corner):
                    let anchor = corner.oppositePoint(in: original)
                    document.updateRedaction(id: id, rect: normalizedRect(from: anchor, to: current))
                case nil:
                    break
                }
            }
            .onEnded { value in
                if case .create(let origin) = drag {
                    let current = mapper.imagePoint(fromView: value.location)
                    document.addRedaction(from: origin, to: current)
                }
                draftRect = nil
                drag = nil
            }
    }

    private func beginDrag(at point: CGPoint, mapper: MarkupCoordinateMapper) -> RedactionDrag {
        let handleTolerance = max(
            4,
            document.contentVisibleFrame.width / max(1, mapper.viewSize.width) * 12
        )

        if let selected = document.redactions.first(where: { document.selectedRedactionIDs.contains($0.id) }),
           let corner = ResizeCorner.allCases.first(where: {
               let handle = $0.point(in: selected.rect)
               return hypot(handle.x - point.x, handle.y - point.y) <= handleTolerance
           }) {
            return .resize(id: selected.id, original: selected.rect, corner: corner)
        }

        if let hit = document.redaction(at: point) {
            document.selectRedaction(id: hit.id)
            let originals = Dictionary(uniqueKeysWithValues: document.redactions.map { ($0.id, $0.rect) })
            return .move(ids: [hit.id], originals: originals, origin: point)
        }

        document.selectRedaction(id: nil)
        return .create(origin: point)
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

private struct RedactionCanvas: View {
    let redactions: [RedactionRegion]
    let draftRect: CGRect?
    let pixelatedImage: NSImage?
    let mapper: MarkupCoordinateMapper

    var body: some View {
        Canvas { context, _ in
            let imageFrame = mapper.imageDisplayFrame
            let visibleRedactions = redactions.map(\.rect) + [draftRect].compactMap { $0 }

            guard let pixelatedImage else {
                for rect in visibleRedactions {
                    let displayRect = mapper.viewRect(fromImage: rect)
                    context.fill(Path(displayRect), with: .color(.black.opacity(0.24)))
                }
                return
            }

            let image = Image(nsImage: pixelatedImage)
            for rect in visibleRedactions {
                let displayRect = mapper.viewRect(fromImage: rect)
                var clipped = context
                clipped.clip(to: Path(displayRect))
                clipped.draw(image, in: imageFrame)
            }
        }
    }
}

/// What the current drag does, decided when it starts.
private enum RedactionDrag {
    case create(origin: CGPoint)
    case move(ids: Set<UUID>, originals: [UUID: CGRect], origin: CGPoint)
    case resize(id: UUID, original: CGRect, corner: ResizeCorner)
}
