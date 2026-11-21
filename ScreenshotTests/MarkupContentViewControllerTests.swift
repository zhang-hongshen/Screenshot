import AppKit
import Testing
@testable import Screenshot

struct MarkupContentViewControllerTests {
    @MainActor
    @Test func contentControllerHostsNativeMarkupView() {
        let bridge = MarkupEditorBridge()
        let controller = MarkupContentViewController(bridge: bridge)
        let image = NSImage(size: CGSize(width: 120, height: 80))
        let document = MarkupDocument(imageSize: image.size)

        controller.loadViewIfNeeded()
        controller.update(image: image, document: document)

        #expect(controller.view.subviews.count == 1)
        #expect(bridge.markupController.parent === controller)
    }
}
