import CoreGraphics

/// Gives a stitched picture the same rounded corners as the captured window.
///
/// The window's alpha mask is resized like a nine-slice image: the corners keep their exact
/// pixels and only the straight edges and the middle stretch.
enum WindowMask {
    static func apply(_ mask: CGImage, to image: CGImage) -> CGImage? {
        guard let resizedMask = resized(mask, width: image.width, height: image.height),
              let context = makeContext(width: image.width, height: image.height) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        context.setBlendMode(.destinationIn)
        context.draw(resizedMask, in: bounds)
        return context.makeImage()
    }

    private static func resized(_ source: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let context = makeContext(width: width, height: height) else { return nil }

        let cornerWidth = min(64, source.width / 2, width / 2)
        let cornerHeight = min(64, source.height / 2, height / 2)
        let sourceWidths = [cornerWidth, source.width - cornerWidth * 2, cornerWidth]
        let sourceHeights = [cornerHeight, source.height - cornerHeight * 2, cornerHeight]
        let targetWidths = [cornerWidth, width - cornerWidth * 2, cornerWidth]
        let targetHeights = [cornerHeight, height - cornerHeight * 2, cornerHeight]

        var sourceY = 0
        var targetY = 0
        for row in 0..<3 {
            var sourceX = 0
            var targetX = 0
            for column in 0..<3 {
                let sourceRect = CGRect(x: sourceX, y: sourceY, width: sourceWidths[column], height: sourceHeights[row])
                let targetRect = CGRect(x: targetX, y: targetY, width: targetWidths[column], height: targetHeights[row])
                if !sourceRect.isEmpty, !targetRect.isEmpty, let piece = source.cropping(to: sourceRect) {
                    // Crops count rows from the top, drawing counts from the bottom.
                    let flipped = CGRect(x: targetRect.minX, y: CGFloat(height) - targetRect.maxY, width: targetRect.width, height: targetRect.height)
                    context.draw(piece, in: flipped)
                }
                sourceX += sourceWidths[column]
                targetX += targetWidths[column]
            }
            sourceY += sourceHeights[row]
            targetY += targetHeights[row]
        }
        return context.makeImage()
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
