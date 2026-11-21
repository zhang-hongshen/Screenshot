import CoreGraphics
import Foundation

/// Applies prepared tiles only under the brush and finds the tiles touched by incoming samples.
extension TextEraser {
    nonisolated private static let tileSize = 256

    nonisolated static func applying(
        _ patches: [TextErasurePatch],
        along strokes: [MarkupBrushStroke],
        to image: CGImage
    ) -> CGImage? {
        guard patches.contains(where: { $0.image != nil }),
              let context = bitmapContext(
                width: image.width, height: image.height, colorSpace: image.colorSpace
              ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        let coverage = CGMutablePath()
        for stroke in strokes { coverage.addPath(stroke.coverage) }
        context.addPath(ScreenCoordinates.drawingPath(fromImage: coverage, imageHeight: CGFloat(image.height)))
        context.clip()
        context.setBlendMode(.copy)
        for patch in patches {
            guard let pixels = patch.image else { continue }
            context.draw(pixels, in: ScreenCoordinates.drawingRect(
                fromImage: patch.rect, imageHeight: CGFloat(image.height)
            ))
        }
        return context.makeImage()
    }

    nonisolated static func tileRects(
        for strokes: [MarkupBrushStroke], imageWidth: Int, imageHeight: Int
    ) -> [CGRect] {
        let bounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let columns = (imageWidth + tileSize - 1) / tileSize
        var visited: Set<Int> = []
        var rects: [CGRect] = []
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            var previous = first
            for point in stroke.points {
                let distance = hypot(point.x - previous.x, point.y - previous.y)
                let steps = max(1, Int(ceil(distance / CGFloat(tileSize / 2))))
                for step in 0..<steps {
                    let start = CGPoint(
                        x: previous.x + (point.x - previous.x) * CGFloat(step) / CGFloat(steps),
                        y: previous.y + (point.y - previous.y) * CGFloat(step) / CGFloat(steps)
                    )
                    let end = CGPoint(
                        x: previous.x + (point.x - previous.x) * CGFloat(step + 1) / CGFloat(steps),
                        y: previous.y + (point.y - previous.y) * CGFloat(step + 1) / CGFloat(steps)
                    )
                    let rect = CGRect(
                        x: min(start.x, end.x), y: min(start.y, end.y),
                        width: abs(end.x - start.x), height: abs(end.y - start.y)
                    ).insetBy(dx: -stroke.radius, dy: -stroke.radius).intersection(bounds)
                    guard !rect.isNull, !rect.isEmpty else { continue }
                    let firstColumn = Int(rect.minX) / tileSize
                    let lastColumn = min(imageWidth - 1, Int(ceil(rect.maxX)) - 1) / tileSize
                    let firstRow = Int(rect.minY) / tileSize
                    let lastRow = min(imageHeight - 1, Int(ceil(rect.maxY)) - 1) / tileSize
                    for row in firstRow...lastRow {
                        for column in firstColumn...lastColumn {
                            guard visited.insert(row * columns + column).inserted else { continue }
                            rects.append(CGRect(
                                x: column * tileSize, y: row * tileSize, width: tileSize, height: tileSize
                            ).intersection(bounds))
                        }
                    }
                }
                previous = point
            }
        }
        return rects
    }

}
