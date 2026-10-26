import AppKit
import Testing
@testable import Screenshot

struct MarkupContentViewControllerTests {
    @MainActor
    @Test func contentControllerHostsRedactionOverlayAboveNativeMarkupView() {
        let bridge = MarkupEditorBridge()
        let controller = MarkupContentViewController(bridge: bridge)
        let image = NSImage(size: CGSize(width: 120, height: 80))
        let document = MarkupDocument(imageSize: image.size)

        controller.loadViewIfNeeded()
        controller.update(image: image, pixelatedImage: nil, document: document)

        #expect(controller.view.subviews.count == 2)
        let topSubviewName = controller.view.subviews.last.map { String(describing: type(of: $0)) } ?? ""
        #expect(topSubviewName.contains("Redaction"))
    }
}
