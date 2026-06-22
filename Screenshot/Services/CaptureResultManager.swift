import AppKit
import SwiftUI

@MainActor
final class CaptureResultManager {
    static let shared = CaptureResultManager()

    private var previewWindow: CapturePreviewWindow?
    private var editorWindow: AnnotationEditorWindow?
    private var latestImage: NSImage?
    private var latestFrame: CGRect?
    private let annotationService = AnnotationEditorService()

    var hasCapture: Bool {
        previewWindow != nil || editorWindow != nil || latestImage != nil
    }

    func reopen() {
        guard editorWindow == nil, let latestImage else { return }
        presentEditor(image: latestImage)
    }

    func presentCompletedCapture(image: NSImage, frame: CGRect) {
        latestImage = image
        latestFrame = frame
        presentEditor(image: image)
    }

    func showPreview(image: NSImage, frame: CGRect) {
        previewWindow?.close()
        latestImage = image
        latestFrame = frame

        let screen = screenContainingMost(of: frame)
        guard let screen else { return }

        let width: CGFloat = 360
        let aspectRatio = image.size.width / max(1, image.size.height)
        let imageHeight = min(220, max(120, width / max(0.1, aspectRatio)))
        let size = CGSize(width: width, height: imageHeight + 24)
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - size.width - 20,
            y: screen.visibleFrame.minY + 20
        )
        let window = CapturePreviewWindow(contentRect: CGRect(origin: origin, size: size))
        window.contentView = NSHostingView(rootView: CapturePreviewView(
            image: image,
            openEditor: { [weak self] in self?.openEditor() },
            dismiss: { [weak self] in self?.dismissPreview() }
        ))
        previewWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func dismissPreview() {
        previewWindow?.close()
        previewWindow = nil
    }

    func discard() {
        dismissPreview()
        editorWindow?.close()
        editorWindow = nil
        latestImage = nil
        latestFrame = nil
    }

    func pixelatedImage(for image: NSImage) -> NSImage {
        annotationService.pixelatedImage(for: image)
    }

    func renderedImage(
        image: NSImage,
        pixelatedImage: NSImage,
        annotations: [Annotation],
        maskImage: NSImage? = nil
    ) -> NSImage? {
        annotationService.renderedImage(
            image: image,
            pixelatedImage: pixelatedImage,
            annotations: annotations,
            maskImage: maskImage
        )
    }

    func copy(image: NSImage) {
        annotationService.copy(image: image)
    }

    func save(image: NSImage) -> Bool {
        annotationService.save(image: image)
    }

    func share(image: NSImage) {
        annotationService.share(image: image)
    }

    private func openEditor() {
        dismissPreview()
        guard let latestImage else { return }
        presentEditor(image: latestImage)
    }

    private func presentEditor(image: NSImage) {
        if let editorWindow {
            editorWindow.makeKeyAndOrderFront(nil)
            return
        }
        let screen = latestFrame.flatMap(screenContainingMost(of:)) ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let size = CGSize(
            width: min(1200, visibleFrame.width * 0.8),
            height: min(900, visibleFrame.height * 0.8)
        )
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        let pixelatedImage = annotationService.pixelatedImage(for: image)
        let window = AnnotationEditorWindow(contentRect: CGRect(origin: origin, size: size))
        window.contentView = NSHostingView(rootView: AnnotationEditorView(
            image: image,
            pixelatedImage: pixelatedImage,
            commandState: window.commandState,
            copy: { [weak self] annotations in
                self?.annotationService.copy(
                    image: image,
                    pixelatedImage: pixelatedImage,
                    annotations: annotations
                )
            },
            finish: { [weak self] annotations in
                self?.completeEditor(
                    image: image,
                    pixelatedImage: pixelatedImage,
                    annotations: annotations
                )
            }
        ))
        window.onClose = { [weak self, weak window] in
            guard self?.editorWindow === window else { return }
            self?.editorWindow = nil
        }
        editorWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func completeEditor(
        image: NSImage,
        pixelatedImage: NSImage,
        annotations: [Annotation]
    ) {
        guard let result = annotationService.renderedImage(
            image: image,
            pixelatedImage: pixelatedImage,
            annotations: annotations
        ) else { return }

        annotationService.copy(image: result)
        let frame = latestFrame ?? editorWindow?.frame ?? .zero
        editorWindow?.close()
        editorWindow = nil
        showPreview(image: result, frame: frame)
    }

    private func screenContainingMost(of frame: CGRect) -> NSScreen? {
        NSScreen.screens.max {
            $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
        } ?? NSScreen.main
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}
