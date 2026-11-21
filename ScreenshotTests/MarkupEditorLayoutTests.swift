import CoreGraphics
import Testing
@testable import Screenshot

struct MarkupEditorLayoutTests {
    @Test func captureOverlayEditorFrameMatchesSelectedCanvas() {
        let canvasFrame = CGRect(x: 24, y: 48, width: 320, height: 200)

        let frame = MarkupEditorLayout.captureEditorFrame(for: canvasFrame)

        #expect(frame == canvasFrame)
    }

    @Test func captureToolbarStaysInsideUsableScreen() {
        let availableFrame = CGRect(x: 8, y: 40, width: 984, height: 720)
        let toolbarSize = CGSize(width: 600, height: 44)
        let cases: [(CGRect, CGPoint)] = [
            (CGRect(x: 300, y: 200, width: 400, height: 200), CGPoint(x: 500, y: 170)),
            (CGRect(x: 300, y: 40, width: 400, height: 200), CGPoint(x: 500, y: 270)),
            (CGRect(x: 0, y: 200, width: 100, height: 200), CGPoint(x: 308, y: 170)),
            (CGRect(x: 900, y: 200, width: 100, height: 200), CGPoint(x: 692, y: 170)),
            (CGRect(x: 0, y: 0, width: 1000, height: 800), CGPoint(x: 500, y: 738))
        ]

        for (canvasFrame, expectedCenter) in cases {
            let center = MarkupEditorLayout.captureToolbarCenter(
                for: canvasFrame,
                toolbarSize: toolbarSize,
                availableFrame: availableFrame
            )
            #expect(center == expectedCenter)
            let toolbarFrame = CGRect(
                x: center.x - toolbarSize.width / 2,
                y: center.y - toolbarSize.height / 2,
                width: toolbarSize.width,
                height: toolbarSize.height
            )
            #expect(availableFrame.contains(toolbarFrame))
        }
    }

}
