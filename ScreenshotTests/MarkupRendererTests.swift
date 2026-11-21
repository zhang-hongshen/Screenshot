import AppKit
import PaperKit
import Testing
@testable import Screenshot

/// Checks that mosaic brush exports preserve density and leave pixels outside the stroke unchanged.
struct MarkupRendererTests {
    @MainActor
    @Test(arguments: [1, 2])
    func mosaicExport(scale: Int) async throws {
        let size = CGSize(width: 120, height: 100)
        let context = try #require(CGContext(
            data: nil,
            width: 120 * scale,
            height: 100 * scale,
            bitsPerComponent: 8,
            bytesPerRow: 120 * scale * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for x in stride(from: 0, to: context.width, by: 4 * scale) {
            context.fill(CGRect(x: x, y: 0, width: 2 * scale, height: context.height))
        }
        let source = try #require(context.makeImage())
        let image = NSImage(cgImage: source, size: size)
        let document = MarkupDocument(imageSize: size)
        let session = document.imageEdits
        session.setSourceIfNeeded(image)
        session.beginStroke(tool: .blur)
        session.append(MarkupBrushStroke(
            points: [CGPoint(x: 25, y: 25), CGPoint(x: 45, y: 25)], radius: 15, isSquare: true
        ))
        let firstImage = try await waitForImage(session, previous: nil)
        #expect(!session.canUndo)
        session.append(MarkupBrushStroke(
            points: [CGPoint(x: 45, y: 25), CGPoint(x: 75, y: 25)], radius: 15, isSquare: true
        ))
        let paintedImage = try await waitForImage(session, previous: firstImage)
        #expect(session.isProcessing)
        session.endStroke()
        for _ in 0..<200 where session.hasPendingChanges {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!session.hasPendingChanges)
        #expect(session.canUndo)
        session.undo()
        #expect(session.currentImage === image)
        #expect(!session.canUndo)
        session.redo()
        #expect(session.currentImage === paintedImage)
        session.beginStroke(tool: .blur)
        session.append(MarkupBrushStroke(
            points: [CGPoint(x: 25, y: 25), CGPoint(x: 75, y: 25)], radius: 15, isSquare: true
        ))
        let repaintedImage = try await waitForImage(session, previous: paintedImage)
        session.endStroke()
        for _ in 0..<200 where session.hasPendingChanges {
            try await Task.sleep(for: .milliseconds(10))
        }
        let paintedPixels = try MarkupRenderer.shared.imagePixels(for: paintedImage)
        let repaintedPixels = try MarkupRenderer.shared.imagePixels(for: repaintedImage)
        let fullBounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        #expect(try pixels(paintedPixels, in: fullBounds) == pixels(repaintedPixels, in: fullBounds))
        let exported = try #require(await MarkupRenderer.shared.renderedImage(
            image: image,
            snapshot: document.snapshot()
        ))
        let data = try #require(exported.tiffRepresentation)
        let output = try #require(NSBitmapImageRep(data: data)?.cgImage)
        #expect(output.width == source.width)
        #expect(output.height == source.height)
        #expect(exported.size == size)

        let selected = CGRect(x: 12 * scale, y: 12 * scale, width: 76 * scale, height: 26 * scale)
        let untouched = CGRect(x: 12 * scale, y: 60 * scale, width: 76 * scale, height: 26 * scale)
        #expect(try pixels(output, in: selected) != pixels(source, in: selected))
        #expect(try pixels(output, in: untouched) == pixels(source, in: untouched))
    }

    @Test func mosaicUsesExactBlockAverages() async throws {
        let context = try #require(CGContext(
            data: nil, width: 10, height: 6, bitsPerComponent: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 6))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 6))
        let source = try #require(context.makeImage())
        let mosaic = try await MosaicRenderer.pixelatedImage(source, blockSize: 4)
        let data = try #require(mosaic.dataProvider?.data) as Data
        for row in 0..<6 {
            for column in 0..<10 {
                let offset = row * mosaic.bytesPerRow + column * 4
                #expect(data[offset] == (column < 4 ? 127 : 0))
                #expect(data[offset + 3] == 255)
            }
        }
    }

    @MainActor
    private func waitForImage(_ session: MarkupImageSession, previous: NSImage?) async throws -> NSImage {
        for _ in 0..<200 where session.acceptedImage === previous {
            try await Task.sleep(for: .milliseconds(10))
        }
        let image = try #require(session.acceptedImage)
        #expect(image !== previous)
        return image
    }

    private func pixels(_ image: CGImage, in rect: CGRect) throws -> Data {
        let crop = try #require(image.cropping(to: rect))
        let context = try #require(CGContext(
            data: nil,
            width: crop.width,
            height: crop.height,
            bitsPerComponent: 8,
            bytesPerRow: crop.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let data = try #require(context.data)
        return Data(bytes: data, count: context.bytesPerRow * context.height)
    }
}
