import CoreGraphics
import Foundation

/// Joins the per-display pieces of a region that spans several displays into one picture.
enum ScreenCaptureRegionCompositor {
    struct Piece {
        let appKitRect: CGRect
        let image: CGImage
    }

    static func compose(
        selection: CGRect,
        outputScale: CGFloat,
        pieces: [Piece]
    ) throws -> CGImage {
        let pixelWidth = max(1, Int((selection.width * outputScale).rounded()))
        let pixelHeight = max(1, Int((selection.height * outputScale).rounded()))
        let bytesPerRow = pixelWidth * 4

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ScreenCaptureRegionCompositorError.cannotCreateCanvas
        }

        context.interpolationQuality = .high
        for piece in pieces {
            context.draw(piece.image, in: drawRect(
                for: piece.appKitRect,
                in: selection,
                outputScale: outputScale
            ))
        }

        guard let image = context.makeImage() else {
            throw ScreenCaptureRegionCompositorError.noImage
        }
        return image
    }

    private static func drawRect(
        for appKitRect: CGRect,
        in selection: CGRect,
        outputScale: CGFloat
    ) -> CGRect {
        CGRect(
            x: (appKitRect.minX - selection.minX) * outputScale,
            y: (appKitRect.minY - selection.minY) * outputScale,
            width: appKitRect.width * outputScale,
            height: appKitRect.height * outputScale
        )
    }
}

/// Joins the per-display pieces of a region that spans several displays into one picture.
enum ScreenCaptureRegionCompositorError: LocalizedError {
    case cannotCreateCanvas
    case noImage

    var errorDescription: String? {
        switch self {
        case .cannotCreateCanvas:
            "The combined screenshot canvas could not be created."
        case .noImage:
            "The screenshot compositor did not produce an image."
        }
    }
}
