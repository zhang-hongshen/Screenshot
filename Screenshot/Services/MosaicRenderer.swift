import CoreGraphics
import Foundation

/// Draws fixed mosaic blocks only beneath the continuous square brush footprint.
nonisolated enum MosaicRenderer {
    @concurrent
    static func pixelatedImage(_ image: CGImage, blockSize: CGFloat) async throws -> CGImage {
        let blockWidth = max(1, Int(blockSize.rounded()))
        let width = image.width
        let height = image.height
        guard let context = TextEraser.bitmapContext(width: width, height: height),
              let data = context.data else { throw CocoaError(.coderInvalidValue) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        for top in stride(from: 0, to: height, by: blockWidth) {
            try Task.checkCancellation()
            let bottom = min(height, top + blockWidth)
            for left in stride(from: 0, to: width, by: blockWidth) {
                let right = min(width, left + blockWidth)
                var red = 0
                var green = 0
                var blue = 0
                var alpha = 0
                for row in top..<bottom {
                    for column in left..<right {
                        let offset = row * context.bytesPerRow + column * 4
                        red += Int(pixels[offset])
                        green += Int(pixels[offset + 1])
                        blue += Int(pixels[offset + 2])
                        alpha += Int(pixels[offset + 3])
                    }
                }
                let count = (bottom - top) * (right - left)
                let averageRed = UInt8(red / count)
                let averageGreen = UInt8(green / count)
                let averageBlue = UInt8(blue / count)
                let averageAlpha = UInt8(alpha / count)
                for row in top..<bottom {
                    for column in left..<right {
                        let offset = row * context.bytesPerRow + column * 4
                        pixels[offset] = averageRed
                        pixels[offset + 1] = averageGreen
                        pixels[offset + 2] = averageBlue
                        pixels[offset + 3] = averageAlpha
                    }
                }
            }
        }
        guard let result = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return result
    }

    @concurrent
    static func apply(
        _ mosaic: CGImage,
        along strokes: [MarkupBrushStroke],
        to image: CGImage
    ) async throws -> CGImage {
        try Task.checkCancellation()
        guard let result = TextEraser.applying(
            [TextErasurePatch(rect: CGRect(x: 0, y: 0, width: image.width, height: image.height), image: mosaic)],
            along: strokes, to: image
        ) else { throw CocoaError(.coderInvalidValue) }
        return result
    }
}
