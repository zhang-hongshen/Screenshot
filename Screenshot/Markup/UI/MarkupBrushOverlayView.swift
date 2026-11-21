import SwiftUI

/// Sends every pointer sample to the shared raster-edit queue while the mouse is held down.
struct MarkupBrushOverlayView: View {
    let document: MarkupDocument
    let tool: MarkupTool
    @State private var previousPoint: CGPoint?
    @State private var strokeRadius: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let mapper = MarkupCoordinateMapper(
                viewSize: proxy.size,
                visibleContentFrame: document.contentVisibleFrame,
                imageSize: document.imageSize
            )
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = mapper.imagePoint(fromView: value.location, clampedToImage: false)
                            if previousPoint == nil {
                                document.imageEdits.beginStroke(tool: tool)
                                strokeRadius = document.imageEdits.brushDiameter / 2
                                    * document.contentVisibleFrame.width / max(1, proxy.size.width)
                            }
                            let start = previousPoint
                                ?? mapper.imagePoint(fromView: value.startLocation, clampedToImage: false)
                            document.imageEdits.append(MarkupBrushStroke(
                                points: start == point ? [point] : [start, point],
                                radius: strokeRadius ?? document.imageEdits.brushDiameter / 2,
                                isSquare: tool == .blur
                            ))
                            previousPoint = point
                        }
                        .onEnded { value in
                            let point = mapper.imagePoint(fromView: value.location, clampedToImage: false)
                            if let previousPoint, let strokeRadius, previousPoint != point {
                                document.imageEdits.append(MarkupBrushStroke(
                                    points: [previousPoint, point], radius: strokeRadius, isSquare: tool == .blur
                                ))
                            }
                            document.imageEdits.endStroke()
                            previousPoint = nil
                            strokeRadius = nil
                        }
                )
            .clipped()
        }
        .onDisappear { document.imageEdits.endStroke() }
    }
}
