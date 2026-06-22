import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class ScrollCaptureManager {
    static let shared = ScrollCaptureManager()

    private var overlayWindows: [CaptureOverlayWindow] = []
    private var backdropWindows: [CaptureOverlayWindow] = []
    private var controlWindow: ScrollCaptureControlWindow?
    private var thumbnailWindow: ScrollCaptureThumbnailWindow?
    private var detector: WindowDetector?
    private var selection: RegionSelection?
    private var detectionTask: Task<Void, Never>?
    private var selectionKeyMonitor: Any?
    private var scrollEventMonitor: Any?
    private var scrollKeyMonitor: Any?
    private var captureTask: Task<Void, Never>?
    private var captureTaskID: UUID?
    private var stitcher = ScrollCaptureStitcher()
    private var captureFrame: CGRect?
    private var captureWindow: SCWindow?
    private var windowMask: CGImage?
    private var captureScale: CGFloat = 1
    private var hasManualScrollInput = false
    private var hasInitialFrame = false

    var isActive: Bool {
        !overlayWindows.isEmpty
            || !backdropWindows.isEmpty
            || controlWindow != nil
            || captureTask != nil
    }

    func start() {
        guard !isActive, !CaptureManager.shared.hasActiveCapture else { return }
        CaptureResultManager.shared.discard()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let detector = WindowDetector()
        let selection = RegionSelection()
        self.detector = detector
        self.selection = selection
        detectionTask = Task { await detector.run() }
        installSelectionKeyboardMonitor()

        overlayWindows = screens.map { screen in
            let window = CaptureOverlayWindow(screen: screen)
            window.contentView = NSHostingView(rootView: CaptureOverlayView(
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
        let keyWindow = zip(screens, overlayWindows)
            .first { $0.0.frame.contains(mouseLocation) }?.1
            ?? overlayWindows.first
        keyWindow?.makeKeyAndOrderFront(nil)
    }

    func begin(window: SCWindow, windowMask: CGImage?) {
        let frame = ScreenCoordinates.appKitRect(fromScreenCapture: window.frame)
        guard frame.width >= 2,
              frame.height >= 2,
              controlWindow == nil,
              captureTask == nil else { return }

        let windows = overlayWindows
        overlayWindows.removeAll()
        backdropWindows = windows
        let controlWindow = makeControlWindow(for: frame)
        windows.forEach { window in
            let screenFrame = window.frame
            window.contentView = NSHostingView(rootView: ScrollCaptureBackdropView(
                captureFrame: frame,
                captureMask: windowMask,
                controlFrame: controlWindow.frame,
                screenFrame: screenFrame
            ))
            window.ignoresMouseEvents = true
            window.orderFrontRegardless()
        }
        stopSelectionInteraction()

        captureFrame = frame
        captureWindow = window
        captureScale = 1
        stitcher = ScrollCaptureStitcher()
        hasManualScrollInput = false
        self.windowMask = windowMask
        hasInitialFrame = false

        self.controlWindow = controlWindow
        controlWindow.orderFrontRegardless()
        installScrollMonitors()

        let taskID = UUID()
        captureTaskID = taskID
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { clearCaptureTask(ifMatching: taskID) }
            do {
                let result = try await captureAndAppendFrame()
                guard result == .appended else {
                    throw ScrollCaptureError.cannotCreateCapture
                }
                hasInitialFrame = true
            } catch is CancellationError {
                return
            } catch {
                cancel()
                CaptureErrorPresenter.present(error)
            }
        }
    }

    func finish() {
        guard let frame = captureFrame,
              let image = makeOutputImage() else {
            cancel()
            return
        }

        let scale = max(1, captureScale)
        let result = NSImage(
            cgImage: image,
            size: CGSize(
                width: CGFloat(image.width) / scale,
                height: CGFloat(image.height) / scale
            )
        )
        tearDown()
        CaptureResultManager.shared.presentCompletedCapture(image: result, frame: frame)
    }

    func cancel() {
        tearDown()
    }

    func captureHighlightMask(for window: SCWindow) async throws -> CGImage {
        try await ScreenCaptureService.captureWindow(window)
    }

    private func makeControlWindow(for captureFrame: CGRect) -> ScrollCaptureControlWindow {
        let window = ScrollCaptureControlWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        let contentView = NSHostingView(rootView: ScrollCaptureControlView(
            state: window.controlState,
            finish: { [weak self] in self?.finish() },
            cancel: { [weak self] in self?.cancel() }
        ))
        window.contentView = contentView
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        let size = CGSize(
            width: ceil(fittingSize.width),
            height: ceil(fittingSize.height)
        )
        window.setFrame(controlFrame(for: captureFrame, size: size), display: false)
        return window
    }

    private func installSelectionKeyboardMonitor() {
        removeSelectionKeyboardMonitor()
        selectionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
    }

    private func removeSelectionKeyboardMonitor() {
        guard let selectionKeyMonitor else { return }
        NSEvent.removeMonitor(selectionKeyMonitor)
        self.selectionKeyMonitor = nil
    }

    private func installScrollMonitors() {
        removeScrollMonitors()
        scrollEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleScrollEvent(event)
            }
        }
        scrollKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            Task { @MainActor [weak self] in
                switch event.keyCode {
                case 53:
                    self?.cancel()
                case 49, 116, 121, 123, 124, 125, 126:
                    self?.hasManualScrollInput = true
                    self?.scheduleFrameCapture()
                default:
                    break
                }
            }
        }
    }

    private func handleScrollEvent(_ event: NSEvent) {
        guard abs(event.scrollingDeltaX) > 0 || abs(event.scrollingDeltaY) > 0 else { return }
        hasManualScrollInput = true
        scheduleFrameCapture()
    }

    private func removeScrollMonitors() {
        if let scrollEventMonitor {
            NSEvent.removeMonitor(scrollEventMonitor)
            self.scrollEventMonitor = nil
        }
        if let scrollKeyMonitor {
            NSEvent.removeMonitor(scrollKeyMonitor)
            self.scrollKeyMonitor = nil
        }
    }

    private func scheduleFrameCapture() {
        guard hasInitialFrame else { return }
        captureTask?.cancel()
        let taskID = UUID()
        captureTaskID = taskID
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { clearCaptureTask(ifMatching: taskID) }
            do {
                try await Task.sleep(for: .milliseconds(250))
                _ = try await captureStableFrame()
            } catch is CancellationError {
                return
            } catch {
                CaptureErrorPresenter.present(error)
            }
        }
    }

    private func clearCaptureTask(ifMatching taskID: UUID) {
        guard captureTaskID == taskID else { return }
        captureTask = nil
        captureTaskID = nil
    }

    private func captureAndAppendFrame() async throws -> ScrollCaptureStitcher.AppendResult {
        guard let frame = captureFrame,
              let controlWindow else {
            throw ScrollCaptureError.cannotCreateCapture
        }

        let image = try await captureSelectedWindow()
        try Task.checkCancellation()
        if stitcher.frameCount == 0 {
            captureScale = CGFloat(image.width) / max(1, frame.width)
        }
        let result = stitcher.append(image)
        let state = controlWindow.controlState
        state.canFinish = stitcher.frameCount > 0
        if hasManualScrollInput {
            updatePreview(state: state)
        }
        return result
    }

    private func captureStableFrame() async throws -> ScrollCaptureStitcher.AppendResult {
        var previous = try await captureSelectedWindow()
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            let current = try await captureSelectedWindow()
            if ScrollCaptureStitcher.framesAreStable(previous, current) {
                return appendStableFrame(current)
            }
            previous = current
        }
        return .noOverlap
    }

    private func appendStableFrame(_ image: CGImage) -> ScrollCaptureStitcher.AppendResult {
        let result = stitcher.append(image)
        guard let state = controlWindow?.controlState else { return result }
        state.canFinish = stitcher.frameCount > 0
        updatePreview(state: state)
        return result
    }

    private func captureSelectedWindow() async throws -> CGImage {
        guard let captureWindow else {
            throw ScrollCaptureError.windowUnavailable
        }
        return try await captureHighlightMask(for: captureWindow)
    }

    private func stopSelectionInteraction() {
        detectionTask?.cancel()
        detectionTask = nil
        detector = nil
        selection?.reset()
        selection = nil
        removeSelectionKeyboardMonitor()
    }

    private func tearDown() {
        captureTask?.cancel()
        captureTask = nil
        captureTaskID = nil
        removeScrollMonitors()
        stopSelectionInteraction()
        controlWindow?.close()
        controlWindow = nil
        thumbnailWindow?.close()
        thumbnailWindow = nil
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
        backdropWindows.forEach { $0.close() }
        backdropWindows.removeAll()
        captureFrame = nil
        captureWindow = nil
        windowMask = nil
        captureScale = 1
        stitcher = ScrollCaptureStitcher()
        hasManualScrollInput = false
        hasInitialFrame = false
    }

    private func updatePreview(state: ScrollCaptureControlState) {
        guard let image = makeOutputImage(),
              let captureFrame,
              hasManualScrollInput else { return }
        let scale = max(1, captureScale)
        let preview = NSImage(
            cgImage: image,
            size: CGSize(
                width: CGFloat(image.width) / scale,
                height: CGFloat(image.height) / scale
            )
        )
        state.previewImage = preview
        let frame = thumbnailFrame(for: captureFrame, imageSize: preview.size)
        if let thumbnailWindow {
            thumbnailWindow.setFrame(frame, display: true, animate: true)
        } else {
            let window = ScrollCaptureThumbnailWindow(contentRect: frame)
            window.contentView = NSHostingView(rootView: ScrollCaptureThumbnailView(state: state))
            thumbnailWindow = window
            window.orderFrontRegardless()
        }
    }

    private func makeOutputImage() -> CGImage? {
        guard let image = stitcher.makeImage() else { return nil }
        guard let windowMask else { return image }
        return imageApplyingWindowMask(image, sourceMask: windowMask) ?? image
    }

    private func imageApplyingWindowMask(_ image: CGImage, sourceMask: CGImage) -> CGImage? {
        guard let mask = resizedWindowMask(sourceMask, width: image.width, height: image.height),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        context.setBlendMode(.destinationIn)
        context.draw(mask, in: bounds)
        return context.makeImage()
    }

    private func resizedWindowMask(_ source: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let capWidth = min(64, source.width / 2, width / 2)
        let capHeight = min(64, source.height / 2, height / 2)
        let sourceWidths = [capWidth, source.width - capWidth * 2, capWidth]
        let sourceHeights = [capHeight, source.height - capHeight * 2, capHeight]
        let destinationWidths = [capWidth, width - capWidth * 2, capWidth]
        let destinationHeights = [capHeight, height - capHeight * 2, capHeight]

        var sourceY = 0
        var destinationY = 0
        for row in 0..<3 {
            var sourceX = 0
            var destinationX = 0
            for column in 0..<3 {
                let sourceRect = CGRect(
                    x: sourceX,
                    y: sourceY,
                    width: sourceWidths[column],
                    height: sourceHeights[row]
                )
                if sourceRect.width > 0,
                   sourceRect.height > 0,
                   destinationWidths[column] > 0,
                   destinationHeights[row] > 0,
                   let piece = source.cropping(to: sourceRect) {
                    context.draw(piece, in: CGRect(
                        x: destinationX,
                        y: destinationY,
                        width: destinationWidths[column],
                        height: destinationHeights[row]
                    ))
                }
                sourceX += sourceWidths[column]
                destinationX += destinationWidths[column]
            }
            sourceY += sourceHeights[row]
            destinationY += destinationHeights[row]
        }
        return context.makeImage()
    }

    private func controlFrame(for captureFrame: CGRect, size: CGSize) -> CGRect {
        let available = screenContainingMost(of: captureFrame)?.visibleFrame ?? captureFrame
        let inset: CGFloat = 10
        let gap: CGFloat = 10
        let fitsInside = captureFrame.width >= size.width + inset * 2
            && captureFrame.height >= size.height + inset * 2

        if fitsInside {
            return CGRect(
                x: captureFrame.midX - size.width / 2,
                y: captureFrame.maxY - size.height - inset,
                width: size.width,
                height: size.height
            )
        }

        let aboveSpace = available.maxY - captureFrame.maxY - gap
        let belowSpace = captureFrame.minY - available.minY - gap
        let centeredX = captureFrame.midX - size.width / 2
        if aboveSpace >= size.height {
            return CGRect(x: centeredX, y: captureFrame.maxY + gap, width: size.width, height: size.height)
        }
        if belowSpace >= size.height {
            return CGRect(x: centeredX, y: captureFrame.minY - gap - size.height, width: size.width, height: size.height)
        }
        if aboveSpace >= belowSpace {
            return CGRect(x: centeredX, y: captureFrame.maxY + gap, width: size.width, height: size.height)
        }
        return CGRect(x: centeredX, y: captureFrame.minY - gap - size.height, width: size.width, height: size.height)
    }

    private func thumbnailFrame(for captureFrame: CGRect, imageSize: CGSize) -> CGRect {
        let available = screenContainingMost(of: captureFrame)?.visibleFrame ?? captureFrame
        let gap: CGFloat = 12
        let aspect = max(0.01, imageSize.width / max(1, imageSize.height))
        let rightSpace = max(0, available.maxX - captureFrame.maxX - gap)
        let leftSpace = max(0, captureFrame.minX - available.minX - gap)
        let placeRight = rightSpace >= 80 || rightSpace >= leftSpace
        let space = placeRight ? rightSpace : leftSpace
        let width = min(140, max(56, space))
        let height = min(440, max(96, width / aspect))
        let x = placeRight
            ? captureFrame.maxX + gap
            : captureFrame.minX - gap - width
        let y = min(
            max(available.minY, captureFrame.midY - height / 2),
            available.maxY - height
        )
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func screenContainingMost(of frame: CGRect) -> NSScreen? {
        NSScreen.screens.max {
            $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
        } ?? NSScreen.main
    }

}

private enum ScrollCaptureError: LocalizedError {
    case windowUnavailable
    case cannotCreateCapture

    var errorDescription: String? {
        switch self {
        case .windowUnavailable:
            "The selected window is no longer available for capture."
        case .cannotCreateCapture:
            "The scrolling screenshot could not be created."
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}
