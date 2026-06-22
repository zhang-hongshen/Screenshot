import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class CaptureManager {
    static let shared = CaptureManager()

    private var overlayWindows: [CaptureOverlayWindow] = []
    private var transitionWindow: CaptureOverlayWindow?
    private var previewWindow: CapturePreviewWindow?
    private var editorWindow: AnnotationEditorWindow?
    private var latestCaptureImage: NSImage?
    private var latestCaptureFrame: CGRect?
    private var overlayDetector: WindowDetector?
    private var regionSelection: RegionSelection?
    private var overlayDetectionTask: Task<Void, Never>?
    private var escapeMonitor: Any?
    private var captureTask: Task<Void, Never>?
    private var captureID: UUID?
    private let annotationService = AnnotationEditorService()

    var hasActiveCapture: Bool {
        !overlayWindows.isEmpty || transitionWindow != nil || captureTask != nil
    }

    func start() {
        guard !ScrollCaptureManager.shared.isActive else { return }
        if previewWindow != nil || editorWindow != nil || latestCaptureImage != nil {
            discardActiveCapture()
        }
        guard overlayWindows.isEmpty,
              transitionWindow == nil,
              captureTask == nil else { return }
        discardReopenableCapture()
        captureID = nil

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let detector = WindowDetector()
        let selection = RegionSelection()
        overlayDetector = detector
        regionSelection = selection
        overlayDetectionTask = Task { await detector.run() }
        installKeyboardMonitor()

        overlayWindows = screens.map { screen in
            let window = CaptureOverlayWindow(screen: screen)
            window.contentView = NSHostingView(rootView: CaptureOverlayView(
                screenFrame: screen.frame,
                detector: detector,
                selection: selection,
                state: window.overlayState,
                isScrollingCapture: false
            ))
            window.orderFrontRegardless()
            return window
        }

        let mouseLocation = NSEvent.mouseLocation
        let keyWindow = zip(screens, overlayWindows)
            .first { $0.0.frame.contains(mouseLocation) }?.1
            ?? overlayWindows.first
        keyWindow?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        captureTask?.cancel()
        captureTask = nil
        captureID = nil
        closeOverlayAfterCurrentEvent()
    }

    func finishAnnotation() {
        let windows = overlayWindows
        overlayWindows.removeAll()
        stopCaptureInteraction()
        windows.forEach { $0.close() }
    }

    func reopenLastCapture() {
        guard overlayWindows.isEmpty,
              transitionWindow == nil,
              captureTask == nil,
              editorWindow == nil,
              let image = latestCaptureImage else { return }
        presentEditor(image: image)
    }

    func prepareForNewCapture() {
        discardActiveCapture()
    }

    func presentCompletedCapture(image: NSImage, frame: CGRect) {
        latestCaptureImage = image
        latestCaptureFrame = frame
        presentEditor(image: image)
    }

    /// Takes ownership of the operation before the overlay's SwiftUI hierarchy is destroyed.
    func finishCapture(window: SCWindow, mask: CGImage?) {
        enterEditing(
            frame: ScreenCoordinates.appKitRect(fromScreenCapture: window.frame),
            windowMask: mask
        )
    }

    func finishCapture(rect: CGRect) {
        guard rect.width >= 2, rect.height >= 2 else { return }
        enterEditing(frame: rect, windowMask: nil)
    }

    func copyCapture(rect: CGRect, annotations: [Annotation], windowMask: CGImage?) {
        export(.copy, rect: rect, annotations: annotations, windowMask: windowMask)
    }

    func saveCapture(rect: CGRect, annotations: [Annotation], windowMask: CGImage?) {
        export(.save, rect: rect, annotations: annotations, windowMask: windowMask)
    }

    func shareCapture(rect: CGRect, annotations: [Annotation], windowMask: CGImage?) {
        export(.share, rect: rect, annotations: annotations, windowMask: windowMask)
    }

    func finishEditing(rect: CGRect, annotations: [Annotation], windowMask: CGImage?) {
        export(.finish, rect: rect, annotations: annotations, windowMask: windowMask)
    }

    /// Captures the window without its shadow so the overlay can use the real alpha
    /// channel instead of approximating the window shape with a fixed corner radius.
    func captureHighlightMask(for window: SCWindow) async throws -> CGImage {
        try await ScreenCaptureService.captureWindow(window)
    }

    private func enterEditing(frame: CGRect, windowMask: CGImage?) {
        guard captureTask == nil, let selection = regionSelection else { return }
        selection.set(rect: frame)

        let windows = overlayWindows
        let mouseLocation = NSEvent.mouseLocation
        guard let retainedWindow = windows.first(where: { $0.frame.contains(mouseLocation) })
                ?? windows.first else { return }

        overlayDetectionTask?.cancel()
        overlayDetectionTask = nil
        overlayDetector = nil
        overlayWindows = [retainedWindow]
        windows.forEach { $0.orderOut(nil) }
        windows.filter { $0 !== retainedWindow }.forEach { $0.close() }

        let id = UUID()
        captureID = id
        captureTask = Task { [weak self, weak retainedWindow] in
            guard let self, let retainedWindow else { return }
            defer {
                if captureID == id {
                    captureTask = nil
                    captureID = nil
                }
            }

            do {
                try await Task.sleep(for: .milliseconds(100))
                let cgImage = try await ScreenCaptureService.captureRegion(frame)
                try Task.checkCancellation()
                let image = NSImage(cgImage: cgImage, size: frame.size)
                retainedWindow.overlayState.pixelatedImage = annotationService
                    .pixelatedImage(for: image)
                retainedWindow.overlayState.windowMask = windowMask
                retainedWindow.overlayState.isEditing = true
                retainedWindow.makeKeyAndOrderFront(nil)
                installKeyboardMonitor()
            } catch is CancellationError {
                return
            } catch {
                retainedWindow.makeKeyAndOrderFront(nil)
                presentError(error)
            }
        }
    }

    private func export(
        _ action: ExportAction,
        rect: CGRect,
        annotations: [Annotation],
        windowMask: CGImage?
    ) {
        guard captureTask == nil, !overlayWindows.isEmpty else { return }

        let id = UUID()
        let windows = overlayWindows
        captureID = id
        windows.forEach { $0.orderOut(nil) }

        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if captureID == id {
                    captureTask = nil
                    captureID = nil
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
                let cgImage = try await ScreenCaptureService.captureRegion(rect)
                try Task.checkCancellation()
                let image = NSImage(cgImage: cgImage, size: rect.size)
                let pixelatedImage = annotationService.pixelatedImage(for: image)
                let maskImage = windowMask.map { NSImage(cgImage: $0, size: rect.size) }
                guard let result = annotationService.renderedImage(
                    image: image,
                    pixelatedImage: pixelatedImage,
                    annotations: annotations,
                    maskImage: maskImage
                ) else {
                    windows.first?.makeKeyAndOrderFront(nil)
                    return
                }

                if action != .finish {
                    windows.first?.makeKeyAndOrderFront(nil)
                }

                switch action {
                case .copy:
                    annotationService.copy(image: result)
                case .save:
                    if annotationService.save(image: result) {
                        finishAnnotation()
                        showPreview(image: result, frame: rect)
                    }
                case .share:
                    annotationService.share(image: result)
                case .finish:
                    annotationService.copy(image: result)
                    finishAnnotation()
                    showPreview(image: result, frame: rect)
                }
            } catch is CancellationError {
                return
            } catch {
                windows.first?.makeKeyAndOrderFront(nil)
                presentError(error)
            }
        }
    }

    private func showPreview(image: NSImage, frame: CGRect) {
        previewWindow?.close()
        latestCaptureImage = image
        latestCaptureFrame = frame

        let screen = NSScreen.screens.max {
            $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
        } ?? NSScreen.main
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

    private func openEditor() {
        previewWindow?.close()
        previewWindow = nil
        guard let image = latestCaptureImage else { return }
        presentEditor(image: image)
    }

    private func presentEditor(image: NSImage) {
        if let editorWindow {
            editorWindow.makeKeyAndOrderFront(nil)
            return
        }
        let screen = latestCaptureFrame.flatMap { captureFrame in
            NSScreen.screens.max {
                $0.frame.intersection(captureFrame).area < $1.frame.intersection(captureFrame).area
            }
        } ?? NSScreen.main
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
                    action: .finish,
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
        action: ExportAction,
        image: NSImage,
        pixelatedImage: NSImage,
        annotations: [Annotation]
    ) {
        guard let result = annotationService.renderedImage(
            image: image,
            pixelatedImage: pixelatedImage,
            annotations: annotations
        ) else { return }

        switch action {
        case .save:
            guard annotationService.save(image: result) else { return }
        case .finish:
            annotationService.copy(image: result)
        case .copy, .share:
            return
        }

        let frame = latestCaptureFrame ?? editorWindow?.frame ?? .zero
        editorWindow?.close()
        editorWindow = nil
        showPreview(image: result, frame: frame)
    }

    private func dismissPreview() {
        previewWindow?.close()
        previewWindow = nil
    }

    /// AppKit can still be dispatching the keyboard or mouse event that requested
    /// dismissal. Hide immediately, then tear down the window on the next run-loop turn.
    private func closeOverlayAfterCurrentEvent() {
        let windows = overlayWindows + [transitionWindow].compactMap { $0 }
        overlayWindows.removeAll()
        transitionWindow = nil
        previewWindow?.close()
        previewWindow = nil
        stopCaptureInteraction()
        windows.forEach { $0.orderOut(nil) }

        DispatchQueue.main.async {
            windows.forEach { $0.close() }
        }
    }

    private func stopCaptureInteraction() {
        overlayDetectionTask?.cancel()
        overlayDetectionTask = nil
        overlayDetector = nil
        regionSelection?.reset()
        regionSelection = nil
        removeKeyboardMonitor()
    }

    private func discardReopenableCapture() {
        editorWindow?.close()
        editorWindow = nil
        latestCaptureImage = nil
        latestCaptureFrame = nil
    }

    private func discardActiveCapture() {
        captureTask?.cancel()
        captureTask = nil
        captureID = nil
        previewWindow?.close()
        previewWindow = nil
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
        discardReopenableCapture()
        stopCaptureInteraction()
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 36, 76:
                if self?.overlayWindows.first?.overlayState.isEditing == true {
                    return event
                }
                guard let rect = self?.regionSelection?.captureRect else { return event }
                self?.finishCapture(rect: rect)
                return nil
            case 53:
                self?.dismiss()
                return nil
            case 51, 117:
                guard self?.overlayWindows.first?.overlayState.isEditing == true else {
                    return event
                }
                return self?.overlayWindows.first?.overlayState.deleteSelection?() == true
                    ? nil
                    : event
            case 0:
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard modifiers == .command,
                      self?.overlayWindows.first?.overlayState.isEditing == true else {
                    return event
                }
                return self?.overlayWindows.first?.overlayState.selectAllAnnotations?() == true
                    ? nil
                    : event
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        guard let escapeMonitor else { return }
        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }

    private func presentError(_ error: Error) {
        NSApp.activate()
        let nsError = error as NSError
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to capture the screen"
        alert.informativeText = "\(error.localizedDescription)\n\(nsError.domain) (\(nsError.code))"
        alert.runModal()
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}

private enum ExportAction: Equatable {
    case copy
    case save
    case share
    case finish
}
