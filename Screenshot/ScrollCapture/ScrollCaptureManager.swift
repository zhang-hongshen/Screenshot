import AppKit
import ScreenCaptureKit
import SwiftUI

/// Runs a scrolling capture from start to finish: picking a window or region, watching the user
/// scroll, collecting settled frames, and showing the finished picture as a floating preview.
///
/// Screenshot never moves the pointer. The user scrolls the app normally (vertically,
/// horizontally, in any scroll area). While they scroll, frames are taken back to back, so
/// neighbouring frames always overlap, and a live preview shows the picture growing.
@MainActor
final class ScrollCaptureManager {
    static let shared = ScrollCaptureManager()

    private enum Source {
        case window(SCWindow)
        case region(CGRect)
    }

    private let detector = WindowDetector()
    private let selection = RegionSelection()
    private let state = ScrollCaptureControlState()

    private var selectionWindows: [CaptureWindow] = []
    private var backdropWindows: [CaptureWindow] = []
    private var controlWindow: ScrollCaptureControlWindow?
    private var thumbnailWindow: ScrollCaptureThumbnailWindow?
    private var eventMonitors: [Any] = []
    private var detectionTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var lastPreviewTime = ContinuousClock.now
    private var isPreviewOutdated = false

    private var source: Source?
    private var captureFrame = CGRect.zero
    private var windowMask: CGImage?
    private var pixelsPerPoint: CGFloat = 1
    private var canvas = ScrollCaptureCanvas()
    #if DEBUG
    private var frameRecorder: ScrollCaptureFrameRecorder?
    #endif
    private var automaticResult: CGImage?
    /// Displays and apps for region captures. Looking them up takes long and they do not change
    /// during a capture, so it happens once.
    private var shareableContent: SCShareableContent?

    var isActive: Bool {
        !selectionWindows.isEmpty || controlWindow != nil
    }

    // MARK: - Selecting

    func start() {
        guard !isActive, !CaptureManager.shared.hasActiveCapture else { return }
        CaptureResultManager.shared.discard()
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        detectionTask = Task { await detector.run() }
        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape else { return event }
            self?.cancel()
            return nil
        }
        eventMonitors.append(escapeMonitor as Any)

        selectionWindows = screens.map { screen in
            let window = CaptureWindow(screen: screen)
            window.contentView = NSHostingView(rootView: CaptureView(
                screenFrame: screen.frame,
                detector: detector,
                selection: selection,
                state: window.overlayState,
                isScrollingCapture: true
            ))
            window.orderFrontRegardless()
            return window
        }
        let mouseLocation = NSEvent.mouseLocation
        let windowUnderPointer = selectionWindows.first { $0.frame.contains(mouseLocation) }
        (windowUnderPointer ?? selectionWindows.first)?.makeKeyAndOrderFront(nil)
    }

    func begin(window: SCWindow, windowMask: CGImage?) {
        let frame = ScreenCoordinates.appKitRect(fromScreenCapture: window.frame)
        begin(source: .window(window), frame: frame, windowMask: windowMask)
    }

    func begin(region frame: CGRect) {
        begin(source: .region(frame), frame: frame, windowMask: nil)
    }

    private func begin(source: Source, frame: CGRect, windowMask: CGImage?) {
        guard frame.width >= 2, frame.height >= 2, controlWindow == nil else { return }
        self.source = source
        self.captureFrame = frame
        self.windowMask = windowMask
        canvas = ScrollCaptureCanvas()
        automaticResult = nil
        state.canFinish = false
        state.isAutomaticScrolling = false
        state.isScrollingTooFast = false
        state.previewImage = nil
        state.previewVisibleRect = nil
        if case .window = source {
            state.showsAutomaticControl = true
        } else {
            state.showsAutomaticControl = false
        }

        detectionTask?.cancel()
        selection.reset()
        removeEventMonitors()

        let controlWindow = makeControlWindow()
        self.controlWindow = controlWindow
        backdropWindows = selectionWindows
        selectionWindows = []
        for window in backdropWindows {
            window.contentView = NSHostingView(rootView: ScrollCaptureBackdropView(
                captureFrame: frame,
                captureMask: windowMask,
                controlFrame: controlWindow.frame,
                screenFrame: window.frame
            ))
            window.ignoresMouseEvents = true
            window.orderFrontRegardless()
        }
        controlWindow.orderFrontRegardless()

        installScrollMonitors()
        lastPreviewTime = .now - .seconds(1)
        watchFrames()
    }

    // MARK: - Finishing

    func cancel() {
        tearDown()
    }

    func finish() -> Bool {
        guard let image = automaticResult ?? canvas.makeImage() else { return false }
        let result = makeNSImage(image)
        let frame = captureFrame
        tearDown()
        CaptureResultManager.shared.showPreview(of: result, takenAt: frame)
        return true
    }

    private func tearDown() {
        detectionTask?.cancel()
        frameTask?.cancel()
        frameTask = nil
        automaticTask?.cancel()
        automaticTask = nil
        removeEventMonitors()
        selection.reset()
        controlWindow?.close()
        controlWindow = nil
        thumbnailWindow?.close()
        thumbnailWindow = nil
        for window in selectionWindows + backdropWindows {
            window.close()
        }
        selectionWindows = []
        backdropWindows = []
        source = nil
        shareableContent = nil
        windowMask = nil
        canvas = ScrollCaptureCanvas()
        automaticResult = nil
    }

    // MARK: - Manual scrolling

    /// Watches scrolling input, without consuming or changing it, only to leave Auto mode and for Escape.
    /// Manual capture itself never relies on input: it watches the picture, so dragging a scroll bar
    /// counts as much as a scroll wheel.
    private func installScrollMonitors() {
        let scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            Task { @MainActor in self?.userDidScroll() }
        }
        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            Task { @MainActor in self?.userDidPress(keyCode: keyCode) }
        }
        let localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape else { return event }
            self?.cancel()
            return nil
        }
        eventMonitors += [scrollMonitor as Any, keyMonitor as Any, localKeyMonitor as Any]
    }

    /// Scrolling by hand while Auto runs, or after it finished, goes back to manual capture.
    private func userDidScroll() {
        guard automaticTask != nil || automaticResult != nil else { return }
        stopAutomaticScrolling()
        automaticResult = nil
        watchFrames()
    }

    private func userDidPress(keyCode: UInt16) {
        if keyCode == KeyCode.escape {
            cancel()
        } else if KeyCode.scrolling.contains(keyCode) {
            userDidScroll()
        }
    }

    private func removeEventMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors = []
    }

    /// Takes frames until the user presses Finish, however they scroll (wheel, trackpad, scroll bar,
    /// keyboard). While the picture moves, frames are taken back to back so neighbouring frames
    /// always overlap; while it stands still, a little less often to save power.
    /// The next frame is taken while the current one is being stitched, so neither waits for the other.
    private func watchFrames() {
        guard frameTask == nil else { return }
        frameTask = Task {
            do {
                var frame = try await currentFrame()
                var change = ScrollCaptureCanvas.Change.scrolled
                while true {
                    let pause: Duration = change == .unchanged ? .milliseconds(50) : .zero
                    async let nextFrame = currentFrame(after: pause)
                    change = await add(frame)
                    try Task.checkCancellation()
                    frame = try await nextFrame
                }
            } catch is CancellationError {
                return
            } catch {
                CaptureErrorPresenter.present(error)
                cancel()
            }
        }
    }

    private func add(_ frame: CGImage) async -> ScrollCaptureCanvas.Change {
        if canvas.firstFrame == nil {
            pixelsPerPoint = CGFloat(frame.width) / max(1, captureFrame.width)
            canvas.knownScrollViewRects = knownScrollViewRects()
            #if DEBUG
            frameRecorder = ScrollCaptureFrameRecorder()
            #endif
        }
        #if DEBUG
        frameRecorder?.save(frame)
        #endif
        let update = await Self.adding(frame, to: canvas)
        guard !Task.isCancelled else { return .unchanged }

        canvas = update.canvas
        state.canFinish = true
        state.isScrollingTooFast = update.change == .movedTooFar
        if update.change != .unchanged {
            isPreviewOutdated = true
        }
        // Drawing the preview takes longer as the picture grows, so while scrolling it is redrawn
        // at most ten times a second, and once more when the picture stands still.
        let isPreviewDue = update.change == .unchanged || ContinuousClock.now - lastPreviewTime > .milliseconds(100)
        if isPreviewOutdated && isPreviewDue {
            await updatePreview()
        }
        return update.change
    }

    /// Stitching takes several milliseconds per frame, so it runs off the main thread.
    @concurrent
    nonisolated private static func adding(
        _ frame: CGImage,
        to canvas: ScrollCaptureCanvas
    ) async -> (canvas: ScrollCaptureCanvas, change: ScrollCaptureCanvas.Change) {
        var canvas = canvas
        let change = canvas.add(frame)
        return (canvas, change)
    }

    private func updatePreview() async {
        guard let firstFrame = canvas.firstFrame else { return }
        lastPreviewTime = .now
        isPreviewOutdated = false
        let scale = min(1, Self.previewPixelWidth / CGFloat(firstFrame.width))
        let preview = await Self.preview(of: canvas, scale: scale)
        guard !Task.isCancelled, let image = preview.image else { return }
        showPreview(image, visibleRect: preview.visibleRect.map { rect in
            CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        })
    }

    @concurrent
    nonisolated private static func preview(
        of canvas: ScrollCaptureCanvas,
        scale: CGFloat
    ) async -> (image: CGImage?, visibleRect: CGRect?) {
        (canvas.makeImage(scale: scale), canvas.latestVisibleRect)
    }

    /// Exact scroll-view bounds from Accessibility, when the user has already allowed it.
    /// Without permission the canvas finds the scrolled areas from the pixels alone.
    private func knownScrollViewRects() -> [CGRect] {
        guard case .window(let window) = source,
              ScrollArea.isAccessibilityTrusted(prompt: false) else { return [] }
        return ScrollArea.areas(in: window).map { $0.pixelRect(in: window, pixelsPerPoint: pixelsPerPoint) }
    }

    private func currentFrame(after pause: Duration = .zero) async throws -> CGImage {
        if pause > .zero {
            try await Task.sleep(for: pause)
        }
        switch source {
        case .window(let window):
            return try await ScreenCaptureService.captureWindow(window)
        case .region(let frame):
            if shareableContent == nil {
                shareableContent = try await SCShareableContent.current
            }
            return try await ScreenCaptureService.captureRegion(frame, content: shareableContent)
        case nil:
            throw CancellationError()
        }
    }

    // MARK: - Automatic scrolling

    func toggleAutomaticScrolling() {
        if automaticTask != nil {
            stopAutomaticScrolling()
            watchFrames()
            return
        }
        guard case .window(let window) = source else { return }
        // Shows the system prompt the first time; the user can press Auto again after allowing it.
        guard ScrollArea.isAccessibilityTrusted(prompt: true) else { return }

        frameTask?.cancel()
        frameTask = nil
        state.isAutomaticScrolling = true
        automaticTask = Task {
            do {
                let image = try await ExpandedWindowCapture.capture(window) { image in
                    showPreview(image, visibleRect: nil)
                }
                automaticResult = image
                showPreview(image, visibleRect: nil)
            } catch is CancellationError {
                return
            } catch {
                CaptureErrorPresenter.present(error)
            }
            automaticTask = nil
            state.isAutomaticScrolling = false
        }
    }

    private func stopAutomaticScrolling() {
        automaticTask?.cancel()
        automaticTask = nil
        state.isAutomaticScrolling = false
    }

    // MARK: - Panels

    private func makeNSImage(_ image: CGImage) -> NSImage {
        let masked = windowMask.flatMap { WindowMask.apply($0, to: image) } ?? image
        let size = CGSize(
            width: CGFloat(masked.width) / pixelsPerPoint,
            height: CGFloat(masked.height) / pixelsPerPoint
        )
        return NSImage(cgImage: masked, size: size)
    }

    /// Preview pixels across; about twice the panel's width in points, for Retina screens.
    private static let previewPixelWidth: CGFloat = 480

    private func showPreview(_ image: CGImage, visibleRect: CGRect?) {
        state.previewImage = NSImage(cgImage: image, size: .zero)
        state.previewVisibleRect = visibleRect
        guard thumbnailWindow == nil else { return }
        let window = ScrollCaptureThumbnailWindow(contentRect: thumbnailFrame())
        window.contentView = NSHostingView(rootView: ScrollCaptureThumbnailView(state: state))
        window.orderFrontRegardless()
        thumbnailWindow = window
    }

    private func makeControlWindow() -> ScrollCaptureControlWindow {
        let window = ScrollCaptureControlWindow(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let contentView = NSHostingView(rootView: ScrollCaptureControlView(state: state))
        window.contentView = contentView
        contentView.layoutSubtreeIfNeeded()
        let size = CGSize(
            width: ceil(contentView.fittingSize.width),
            height: ceil(contentView.fittingSize.height)
        )
        window.setFrame(controlFrame(for: size), display: false)
        return window
    }

    /// Centers the buttons just above the capture, or just below it, so they never cover
    /// what is being captured. Only when neither fits (a full-screen window) do they go inside.
    private func controlFrame(for size: CGSize) -> CGRect {
        let screen = ScreenCoordinates.screenContainingMost(ofAppKitRect: captureFrame)?.visibleFrame ?? captureFrame
        let inset: CGFloat = 10
        var x = captureFrame.midX - size.width / 2
        x = min(max(screen.minX + inset, x), screen.maxX - inset - size.width)

        let spaceAbove = screen.maxY - captureFrame.maxY - inset
        let spaceBelow = captureFrame.minY - screen.minY - inset
        if spaceAbove >= size.height {
            return CGRect(x: x, y: captureFrame.maxY + inset, width: size.width, height: size.height)
        }
        if spaceBelow >= size.height {
            return CGRect(x: x, y: captureFrame.minY - inset - size.height, width: size.width, height: size.height)
        }
        return CGRect(x: x, y: captureFrame.maxY - size.height - inset, width: size.width, height: size.height)
    }

    /// Places the preview beside the capture, as tall as the capture, on the right when there is room.
    private func thumbnailFrame() -> CGRect {
        let screen = ScreenCoordinates.screenContainingMost(ofAppKitRect: captureFrame)?.visibleFrame ?? captureFrame
        let gap: CGFloat = 12
        let spaceRight = max(0, screen.maxX - captureFrame.maxX - gap * 2)
        let spaceLeft = max(0, captureFrame.minX - screen.minX - gap * 2)
        let placesRight = spaceRight >= 160 || spaceRight >= spaceLeft
        let width = min(240, max(160, placesRight ? spaceRight : spaceLeft))
        let height = min(screen.height - gap * 2, max(240, captureFrame.height))
        var x = placesRight ? captureFrame.maxX + gap : captureFrame.minX - gap - width
        x = min(max(screen.minX + gap, x), screen.maxX - gap - width)
        let y = min(max(screen.minY + gap, captureFrame.midY - height / 2), screen.maxY - gap - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
