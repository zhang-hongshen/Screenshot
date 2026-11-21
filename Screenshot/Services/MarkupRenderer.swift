import AppKit
import CoreGraphics
import PaperKit

/// Flattens the brush-edited screenshot and PaperKit markup into the final image.
@MainActor
final class MarkupRenderer {
    static let shared = MarkupRenderer()

    func renderedImage(
        image: NSImage,
        snapshot: MarkupSnapshot,
        maskImage: NSImage? = nil
    ) async -> NSImage? {
        let image = snapshot.editedImage ?? image
        guard let baseCGImage = try? imagePixels(for: image) else { return nil }

        let outputScale = CGFloat(baseCGImage.width) / max(1, image.size.width)
        let pixelWidth = max(1, Int((image.size.width * outputScale).rounded()))
        let pixelHeight = max(1, Int((image.size.height * outputScale).rounded()))
        guard let context = bitmapContext(width: pixelWidth, height: pixelHeight) else { return nil }

        let bounds = CGRect(origin: .zero, size: image.size)
        context.scaleBy(x: outputScale, y: outputScale)
        context.draw(baseCGImage, in: bounds)

        context.saveGState()
        context.translateBy(x: 0, y: image.size.height)
        context.scaleBy(x: 1, y: -1)
        await snapshot.markup.draw(in: context, frame: bounds)
        context.restoreGState()

        guard let rendered = context.makeImage() else { return nil }
        let finalImage = maskImage
            .flatMap { apply(maskImage: $0, to: rendered, size: image.size) }
            ?? rendered
        return NSImage(cgImage: finalImage, size: image.size)
    }

    private func apply(maskImage: NSImage, to image: CGImage, size: CGSize) -> CGImage? {
        guard let mask = try? imagePixels(for: maskImage),
              let context = bitmapContext(width: image.width, height: image.height) else {
            return nil
        }

        let pixelRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.clip(to: pixelRect, mask: mask)
        context.draw(image, in: pixelRect)
        return context.makeImage()
    }

    func imagePixels(for image: NSImage) throws -> CGImage {
        // TIFF preserves native density; a proposed point rect can rasterize Retina images at 1×.
        guard let data = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: data)?.cgImage,
              let context = CGContext(
                data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
                bytesPerRow: source.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else { throw CocoaError(.coderInvalidValue) }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let pixels = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return pixels
    }

    private func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
