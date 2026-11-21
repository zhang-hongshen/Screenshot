import AppKit
import CoreGraphics
import Testing
@testable import Screenshot

struct MarkupDocumentTests {
    @MainActor
    @Test func brushHistory() throws {
        let document = MarkupDocument(imageSize: CGSize(width: 40, height: 40))
        let session = document.imageEdits
        let context = try #require(CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let pixels = try #require(context.makeImage())
        let original = NSImage(cgImage: pixels, size: document.imageSize)
        let first = NSImage(cgImage: pixels, size: original.size)
        let second = NSImage(cgImage: pixels, size: original.size)
        session.setSourceIfNeeded(original)
        #expect(document.snapshot().editedImage == nil)
        session.apply(first)
        session.recordStrokeUndo(previous: nil)
        #expect(document.snapshot().editedImage === first)
        session.apply(second)
        session.apply(first)
        session.apply(second)
        session.recordStrokeUndo(previous: first, tool: .blur)
        session.undo()
        #expect(session.currentImage === first)
        session.undo()
        #expect(session.currentImage === original)
        session.redo()
        #expect(session.currentImage === first)
        session.redo()
        #expect(session.currentImage === second)
        session.undo()
        session.apply(first)
        session.recordStrokeUndo(previous: first)
        #expect(!session.canRedo)
    }

}
