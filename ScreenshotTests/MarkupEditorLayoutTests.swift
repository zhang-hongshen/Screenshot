import CoreGraphics
import Testing
@testable import Screenshot

struct MarkupEditorLayoutTests {
    @Test func standaloneEditorOverlayUsesFullEditorContentArea() {
        let contentSize = CGSize(width: 640, height: 360)

        let frame = MarkupEditorLayout.redactionOverlayFrame(for: contentSize)

        #expect(frame == CGRect(origin: .zero, size: contentSize))
    }

    @Test func captureOverlayEditorFrameMatchesSelectedCanvas() {
        let canvasFrame = CGRect(x: 24, y: 48, width: 320, height: 200)

        let frame = MarkupEditorLayout.captureEditorFrame(for: canvasFrame)

        #expect(frame == canvasFrame)
    }
}
