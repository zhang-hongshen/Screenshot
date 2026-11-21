import AppKit
import PaperKit
import SwiftUI

/// The editing canvas: the screenshot, PaperKit markup, and the blur overlay above it.
struct MarkupCanvasView: View {
    let image: NSImage?
    let document: MarkupDocument
    let bridge: MarkupEditorBridge

    var body: some View {
        PaperMarkupCanvasView(
            image: document.imageEdits.currentImage ?? image,
            document: document,
            bridge: bridge
        )
        .allowsHitTesting(bridge.tool == .select || bridge.tool == .draw)
        .overlay {
            if bridge.tool == .blur || bridge.tool == .eraseText {
                MarkupBrushOverlayView(document: document, tool: bridge.tool)
                    .id(bridge.tool)
            }
        }
    }
}

/// Wraps PaperKit because its macOS canvas is only available as an AppKit view controller.
private struct PaperMarkupCanvasView: NSViewControllerRepresentable {
    let image: NSImage?
    let document: MarkupDocument
    let bridge: MarkupEditorBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSViewController(context: Context) -> MarkupContentViewController {
        let controller = MarkupContentViewController(bridge: bridge)
        bridge.markupController.delegate = context.coordinator
        context.coordinator.document = document
        controller.update(image: image, document: document)
        return controller
    }

    func updateNSViewController(_ controller: MarkupContentViewController, context: Context) {
        bridge.markupController.delegate = context.coordinator
        context.coordinator.document = document
        controller.update(image: image, document: document)
    }

    static func dismantleNSViewController(
        _ controller: MarkupContentViewController,
        coordinator: Coordinator
    ) {
        controller.detachMarkupController()
    }

    final class Coordinator: NSObject, PaperMarkupViewController.Delegate {
        weak var document: MarkupDocument?

        init(document: MarkupDocument) {
            self.document = document
        }

        func paperMarkupViewControllerDidChangeMarkup(_ controller: PaperMarkupViewController) {
            guard let markup = controller.markup else { return }
            document?.markup = markup
        }

        func paperMarkupViewControllerDidChangeContentVisibleFrame(_ controller: PaperMarkupViewController) {
            document?.contentVisibleFrame = controller.contentVisibleFrame
        }

        func paperMarkupViewControllerDidChangeSelection(_ controller: PaperMarkupViewController) {}

        func paperMarkupViewControllerDidBeginDrawing(_ controller: PaperMarkupViewController) {}
    }
}

/// Hosts the screenshot inside PaperKit, whose canvas requires an AppKit view controller.
final class MarkupContentViewController: NSViewController {
    private let bridge: MarkupEditorBridge
    private let imageView = NSImageView()
    private let emptyContentView = NSView()
    private weak var currentDocument: MarkupDocument?
    private var currentImageSize: CGSize?
    private var lastCenteredImageSize: CGSize?
    private var lastCenteredViewportSize: CGSize?
    private var installed = false

    init(bridge: MarkupEditorBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installMarkupControllerIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        centerContentIfNeeded()
    }

    func update(image: NSImage?, document: MarkupDocument) {
        installMarkupControllerIfNeeded()
        if let image { document.imageEdits.setSourceIfNeeded(image) }
        currentDocument = document
        bridge.document = document

        if bridge.markupController.markup != document.markup {
            bridge.markupController.markup = document.markup
        }

        if let image {
            let imageSizeChanged = currentImageSize != image.size
            currentImageSize = image.size
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.frame = CGRect(origin: .zero, size: image.size)
            configureImageViewAppearance()
            if bridge.markupController.contentView !== imageView {
                bridge.markupController.contentView = imageView
            }
            centerContentIfNeeded(force: imageSizeChanged)
        } else if bridge.markupController.contentView !== emptyContentView {
            currentImageSize = nil
            lastCenteredImageSize = nil
            lastCenteredViewportSize = nil
            emptyContentView.wantsLayer = true
            emptyContentView.layer?.backgroundColor = NSColor.clear.cgColor
            bridge.markupController.contentView = emptyContentView
        }

        let visibleFrame = bridge.markupController.contentVisibleFrame
        if visibleFrame.width > 0, visibleFrame.height > 0 {
            document.contentVisibleFrame = visibleFrame
        }
    }

    func detachMarkupController() {
        guard bridge.markupController.parent === self else { return }
        bridge.markupController.view.removeFromSuperview()
        bridge.markupController.removeFromParent()
        installed = false
    }

    private func installMarkupControllerIfNeeded() {
        guard !installed, isViewLoaded else { return }
        installed = true

        addChild(bridge.markupController)
        let markupView = bridge.markupController.view
        markupView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(markupView)
        NSLayoutConstraint.activate([
            markupView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            markupView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            markupView.topAnchor.constraint(equalTo: view.topAnchor),
            markupView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureImageViewAppearance() {
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        guard let layer = imageView.layer else { return }
        layer.backgroundColor = NSColor.clear.cgColor
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: imageView.bounds.size), transform: nil)
    }

    private func centerContentIfNeeded(force: Bool = false) {
        guard let imageSize = currentImageSize else { return }

        let viewportSize = bridge.markupController.view.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        guard force
            || imageSize != lastCenteredImageSize
            || viewportSize != lastCenteredViewportSize else {
            return
        }

        let visibleFrame = MarkupContentLayout.centeredVisibleFrame(
            imageSize: imageSize,
            viewportSize: viewportSize
        )
        bridge.markupController.setContentVisibleFrame(visibleFrame, animated: false)
        currentDocument?.contentVisibleFrame = visibleFrame
        lastCenteredImageSize = imageSize
        lastCenteredViewportSize = viewportSize
    }
}
