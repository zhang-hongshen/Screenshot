import AppKit

/// Draws screenshots where the user arranged them. Space no screenshot covers stays transparent.
enum CollageRenderer {
    static func image(of images: [NSImage], arrangement: CollageArrangement) -> NSImage? {
        let cgImages = images.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let canvasSize = arrangement.bounds.size
        guard !cgImages.isEmpty, cgImages.count == images.count,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(canvasSize.width),
                height: Int(canvasSize.height),
                bitsPerComponent: 8,
                bytesPerRow: Int(canvasSize.width) * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        for piece in arrangement.canvasPieces {
            // The arrangement's origin is at the top left, Core Graphics' at the bottom left.
            let frame = piece.frame
            let flippedY = canvasSize.height - frame.maxY
            context.draw(
                cgImages[piece.imageIndex],
                in: CGRect(x: frame.minX, y: flippedY, width: frame.width, height: frame.height)
            )
        }
        guard let collage = context.makeImage() else { return nil }

        // Keep the Retina density of the sharpest screenshot, so the editor shows it at the usual size.
        let pixelsPerPoint = zip(images, cgImages).map { image, cgImage in
            CGFloat(cgImage.width) / max(1, image.size.width)
        }.max() ?? 1
        let pointSize = CGSize(
            width: canvasSize.width / pixelsPerPoint,
            height: canvasSize.height / pixelsPerPoint
        )
        return NSImage(cgImage: collage, size: pointSize)
    }
}
