import CoreGraphics
import Testing
@testable import Screenshot

struct MarkupContentLayoutTests {
    @Test func visibleFrameCentersWideImageInSquareViewport() {
        let frame = MarkupContentLayout.centeredVisibleFrame(
            imageSize: CGSize(width: 800, height: 400),
            viewportSize: CGSize(width: 600, height: 600),
            contentInset: 0
        )

        #expect(frame == CGRect(x: 0, y: -200, width: 800, height: 800))
    }

    @Test func visibleFrameCentersWideImageInNarrowViewport() {
        let frame = MarkupContentLayout.centeredVisibleFrame(
            imageSize: CGSize(width: 800, height: 400),
            viewportSize: CGSize(width: 300, height: 600),
            contentInset: 0
        )

        #expect(frame == CGRect(x: 0, y: -600, width: 800, height: 1_600))
    }

    @Test func visibleFrameCentersImageInWideViewport() {
        let frame = MarkupContentLayout.centeredVisibleFrame(
            imageSize: CGSize(width: 800, height: 400),
            viewportSize: CGSize(width: 1_200, height: 300),
            contentInset: 0
        )

        #expect(frame == CGRect(x: -400, y: 0, width: 1_600, height: 400))
    }

    @Test func visibleFrameLeavesViewportInsetAroundImage() {
        let frame = MarkupContentLayout.centeredVisibleFrame(
            imageSize: CGSize(width: 800, height: 400),
            viewportSize: CGSize(width: 1_000, height: 600),
            contentInset: 50
        )

        #expect(abs(frame.minX - -44.444) < 0.001)
        #expect(abs(frame.minY - -66.667) < 0.001)
        #expect(abs(frame.width - 888.889) < 0.001)
        #expect(abs(frame.height - 533.333) < 0.001)
    }

    @Test func visibleFrameUsesDefaultEditorInsetAroundImage() {
        let viewportSize = CGSize(width: 1_000, height: 600)
        let imageSize = CGSize(width: 800, height: 400)
        let frame = MarkupContentLayout.centeredVisibleFrame(
            imageSize: imageSize,
            viewportSize: viewportSize
        )

        let scale = viewportSize.width / frame.width
        let horizontalMargin = (viewportSize.width - imageSize.width * scale) / 2
        let verticalMargin = (viewportSize.height - imageSize.height * scale) / 2

        #expect(horizontalMargin >= 31.9)
        #expect(verticalMargin >= 31.9)
    }

    @Test func zoomedVisibleFrameKeepsTheSameCenter() {
        let frame = MarkupContentLayout.zoomedVisibleFrame(
            currentVisibleFrame: CGRect(x: -50, y: -190, width: 900, height: 540),
            zoomFactor: 1.2,
            imageSize: CGSize(width: 800, height: 400),
            minZoom: 0.5,
            maxZoom: 4
        )

        #expect(frame == CGRect(x: 25, y: -145, width: 750, height: 450))
    }

}
