import AppKit
import ScreenCaptureKit
import SwiftUI

/// Runs a normal (window or region) capture: shows the selection overlay on every screen,
/// switches to in-place markup once something is selected, and exports the result.
@MainActor
final class CaptureManager {
    static let shared = CaptureManager()

    private enum ExportAction {
        case copy
        case save
        case share
        case finish
    }

    private let detector = WindowDetector()
    private let selection = RegionSelection()
    private var overlayWindows: [CaptureWindow] = []
    private var detectionTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var keyMonitor: Any?

    var hasActiveCapture: Bool {
        !overlayWindows.isEmpty || captureTask != nil
    }

    // MARK: - Selecting

    func start() {
        guard !ScrollCaptureManager.shared.isActive else { return }
        guard overlayWindows.isEmpty, captureTask == nil else { return }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        detectionTask = Task { await detector.run() }
        installKeyMonitor()

        overlayWindows = screens.map { screen in
            let window = CaptureWindow(screen: screen)
            window.contentView = NSHostingView(rootView: CaptureView(
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
        let windowUnderPointer = overlayWindows.first { $0.frame.contains(mouseLocation) }
        (windowUnderPointer ?? overlayWindows.first)?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        captureTask?.cancel()
        captureTask = nil
        // AppKit may still be delivering the event that asked us to close,
        // so hide the windows now and close them on the next turn of the run loop.
        let windows = overlayWindows
        overlayWindows = []
        stopSelecting()
        for window in windows {
            window.orderOut(nil)
        }
        Task {
            for window in windows {
                window.close()
            }
        }
    }

    func finishCapture(window: SCWindow, mask: CGImage?) {
        enterEditing(frame: ScreenCoordinates.appKitRect(fromScreenCapture: window.frame), windowMask: mask)
    }

    func finishCapture(rect: CGRect) {
        guard rect.width >= 2, rect.height >= 2 else { return }
        enterEditing(frame: rect, windowMask: nil)
    }

    // MARK: - Editing

    func copyCapture(rect: CGRect, document: MarkupDocument, windowMask: CGImage?) {
        export(.copy, rect: rect, snapshot: document.snapshot(), windowMask: windowMask)
    }

    func saveCapture(rect: CGRect, document: MarkupDocument, windowMask: CGImage?) {
        export(.save, rect: rect, snapshot: document.snapshot(), windowMask: windowMask)
    }

    func shareCapture(rect: CGRect, document: MarkupDocument, windowMask: CGImage?) {
        export(.share, rect: rect, snapshot: document.snapshot(), windowMask: windowMask)
    }

    func finishEditing(rect: CGRect, document: MarkupDocument, windowMask: CGImage?) {
        export(.finish, rect: rect, snapshot: document.snapshot(), windowMask: windowMask)
    }

    /// Keeps the overlay on the screen under the pointer, captures the selection without the
    /// overlay in it, and turns that overlay into the markup editor.
    private func enterEditing(frame: CGRect, windowMask: CGImage?) {
        guard captureTask == nil else { return }
        selection.set(rect: frame)

        let mouseLocation = NSEvent.mouseLocation
        guard let editingWindow = overlayWindows.first(where: { $0.frame.contains(mouseLocation) })
                ?? overlayWindows.first else { return }
        detectionTask?.cancel()
        for window in overlayWindows {
            window.orderOut(nil)
            if window !== editingWindow {
                window.close()
            }
        }
        overlayWindows = [editingWindow]

        captureTask = Task {
            defer { captureTask = nil }
            do {
                // Give the window server a moment to remove the hidden overlay from the screen.
                try await Task.sleep(for: .milliseconds(100))
                let cgImage = try await ScreenCaptureService.captureRegion(frame)
                try Task.checkCancellation()
                let image = NSImage(cgImage: cgImage, size: frame.size)

                let state = editingWindow.overlayState
                state.sourceImage = image
                state.pixelatedImage = MarkupRenderer.shared.pixelatedImage(for: image)
                state.markupDocument = MarkupDocument(imageSize: frame.size)
                state.windowMask = windowMask
                state.isEditing = true
                editingWindow.makeKeyAndOrderFront(nil)
            } catch is CancellationError {
                return
            } catch {
                editingWindow.makeKeyAndOrderFront(nil)
                CaptureErrorPresenter.present(error)
            }
        }
    }

    /// Captures the selected part of the screen again (so it shows what is there now),
    /// draws the markup on top, and copies, saves, shares or finishes with it.
    private func export(_ action: ExportAction, rect: CGRect, snapshot: MarkupSnapshot, windowMask: CGImage?) {
        guard captureTask == nil, let editingWindow = overlayWindows.first else { return }
        editingWindow.orderOut(nil)

        captureTask = Task {
            defer { captureTask = nil }
            do {
                try await Task.sleep(for: .milliseconds(100))
                let cgImage = try await ScreenCaptureService.captureRegion(rect)
                try Task.checkCancellation()
                let image = NSImage(cgImage: cgImage, size: rect.size)
                let result = await MarkupRenderer.shared.renderedImage(
                    image: image,
                    pixelatedImage: MarkupRenderer.shared.pixelatedImage(for: image),
                    snapshot: snapshot,
                    maskImage: windowMask.map { NSImage(cgImage: $0, size: rect.size) }
                )
                guard let result else {
                    editingWindow.makeKeyAndOrderFront(nil)
                    return
                }

                switch action {
                case .copy:
                    editingWindow.makeKeyAndOrderFront(nil)
                    ImageExportService.shared.copy(result)
                case .save:
                    editingWindow.makeKeyAndOrderFront(nil)
                    if ImageExportService.shared.save(result) {
                        closeEditor()
                        CaptureResultManager.shared.addToPreview(result, takenAt: rect)
                    }
                case .share:
                    editingWindow.makeKeyAndOrderFront(nil)
                    ImageExportService.shared.share(result)
                case .finish:
                    ImageExportService.shared.copy(result)
                    closeEditor()
                    CaptureResultManager.shared.addToPreview(result, takenAt: rect)
                }
            } catch is CancellationError {
                return
            } catch {
                editingWindow.makeKeyAndOrderFront(nil)
                CaptureErrorPresenter.present(error)
            }
        }
    }

    private func closeEditor() {
        let windows = overlayWindows
        overlayWindows = []
        stopSelecting()
        for window in windows {
            window.close()
        }
    }

    // MARK: - Cleaning up

    private func stopSelecting() {
        detectionTask?.cancel()
        detectionTask = nil
        selection.reset()
        removeKeyMonitor()
    }

    /// Return captures the selected region, Escape cancels. While editing, Return is left to the editor.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case KeyCode.returnKey, KeyCode.keypadEnter:
                let isEditing = overlayWindows.first?.overlayState.isEditing == true
                guard !isEditing, let rect = selection.captureRect else { return event }
                finishCapture(rect: rect)
                return nil
            case KeyCode.escape:
                dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}
