import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import PaperKit

/// Turns a screenshot plus its markup and blur regions into the final image.
@MainActor
final class MarkupRenderer {
    static let shared = MarkupRenderer()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    func pixelatedImage(for image: NSImage) -> NSImage {
        guard let data = image.tiffRepresentation,
              let input = CIImage(data: data) else { return image }

        let filter = CIFilter.pixellate()
        filter.inputImage = input
        filter.scale = 14
        guard let output = filter.outputImage,
              let cgImage = imageContext.createCGImage(output, from: input.extent) else { return image }
        return NSImage(cgImage: cgImage, size: image.size)
    }

    func renderedImage(
        image: NSImage,
        pixelatedImage: NSImage,
        snapshot: MarkupSnapshot,
        maskImage: NSImage? = nil
    ) async -> NSImage? {
        guard let baseCGImage = cgImage(from: image),
              let pixelatedCGImage = cgImage(from: pixelatedImage) else { return nil }

        let outputScale = imageScale(for: image)
        let pixelWidth = max(1, Int((image.size.width * outputScale).rounded()))
        let pixelHeight = max(1, Int((image.size.height * outputScale).rounded()))
        guard let context = bitmapContext(width: pixelWidth, height: pixelHeight) else { return nil }

        let bounds = CGRect(origin: .zero, size: image.size)
        context.scaleBy(x: outputScale, y: outputScale)
        context.draw(baseCGImage, in: bounds)
        drawRedactions(snapshot.redactions, pixelatedCGImage: pixelatedCGImage, in: bounds, context: context)

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

    private func drawRedactions(
        _ redactions: [RedactionRegion],
        pixelatedCGImage: CGImage,
        in bounds: CGRect,
        context: CGContext
    ) {
        for redaction in redactions {
            let rect = CGRect(
                x: redaction.rect.minX,
                y: bounds.height - redaction.rect.maxY,
                width: redaction.rect.width,
                height: redaction.rect.height
            )
            context.saveGState()
            context.clip(to: rect)
            context.draw(pixelatedCGImage, in: bounds)
            context.restoreGState()
        }
    }

    private func apply(maskImage: NSImage, to image: CGImage, size: CGSize) -> CGImage? {
        guard let mask = cgImage(from: maskImage),
              let context = bitmapContext(width: image.width, height: image.height) else {
            return nil
        }

        let pixelRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.clip(to: pixelRect, mask: mask)
        context.draw(image, in: pixelRect)
        return context.makeImage()
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private func imageScale(for image: NSImage) -> CGFloat {
        guard image.size.width > 0 else { return 1 }
        let pixelsWide = image.representations.first?.pixelsWide ?? Int(image.size.width)
        return max(1, CGFloat(pixelsWide) / image.size.width)
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
