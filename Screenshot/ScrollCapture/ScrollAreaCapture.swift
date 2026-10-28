import ScreenCaptureKit

/// Scrolls one area from its start to its end and stitches everything it shows into one image.
///
/// Areas that scroll both ways are walked like a snake: top to bottom, one step right,
/// bottom to top, one step right, and so on, so every pair of neighbouring frames overlaps.
struct ScrollAreaCapture {
    let area: ScrollArea
    let window: SCWindow
    /// The area's pixels inside a full window capture (top-left origin).
    let cropRect: CGRect

    private let pixelsPerPoint: CGFloat
    private var stitcher = ScrollCaptureStitcher()
    /// Scroll-bar units per captured pixel, learned from the first successful step on each axis.
    private var unitsPerPixel: [ScrollAxis: Double] = [:]
    private var reachedSizeLimit = false

    init(area: ScrollArea, window: SCWindow, windowImageSize: CGSize) {
        self.area = area
        self.window = window
        pixelsPerPoint = windowImageSize.width / max(1, window.frame.width)
        cropRect = area.pixelRect(in: window, pixelsPerPoint: pixelsPerPoint)
            .intersection(CGRect(origin: .zero, size: windowImageSize))
    }

    /// Where the first frame sits in the image `run()` returns.
    var firstFrameRect: CGRect? {
        stitcher.firstFrameRect
    }

    /// Returns the full content of the area, or nil when it could not be captured.
    mutating func run() async throws -> CGImage? {
        guard !cropRect.isEmpty, area.canSetPosition || area.revealsItems else { return nil }
        let startVertical = area.position(along: .vertical)
        let startHorizontal = area.position(along: .horizontal)
        let startItem = area.firstVisibleItem()
        defer {
            if let startVertical { area.setPosition(startVertical, along: .vertical) }
            if let startHorizontal { area.setPosition(startHorizontal, along: .horizontal) }
            startItem?.performAction("AXScrollToVisible")
        }

        await scrollToStart()
        guard let firstFrame = try await stableWindowImage().cropping(to: cropRect),
              stitcher.append(firstFrame) == .appended else { return nil }

        var movesDown = true
        while !reachedSizeLimit {
            while try await step(along: .vertical, forward: movesDown) {}
            guard try await step(along: .horizontal, forward: true) else { break }
            movesDown.toggle()
        }
        return stitcher.makeImage()
    }

    // MARK: - Moving

    private func scrollToStart() async {
        if area.canSetPosition {
            area.setPosition(0, along: .vertical)
            area.setPosition(0, along: .horizontal)
        } else {
            area.revealStart()
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// Moves about half a screen along `axis` and stitches the new frame.
    /// Returns false at the end of the content.
    private mutating func step(along axis: ScrollAxis, forward: Bool) async throws -> Bool {
        let viewportPixels = axis == .vertical ? cropRect.height : cropRect.width
        var pixels = Double(viewportPixels) * 0.6

        // A step that jumps too far leaves no overlap to match, so go back and try a smaller one.
        for _ in 0..<3 {
            let before = area.position(along: axis)
            guard move(along: axis, pixels: forward ? pixels : -pixels) else { return false }
            try await Task.sleep(for: .milliseconds(120))

            let windowImage = try await stableWindowImage()
            guard let frame = windowImage.cropping(to: cropRect) else { throw ScrollAreaCaptureError.windowChanged }
            switch stitcher.append(frame) {
            case .appended:
                learnStepSize(along: axis, from: before)
                return true
            case .unchanged:
                return false
            case .limitReached:
                reachedSizeLimit = true
                return false
            case .noOverlap:
                // Only a scroll bar can go back exactly.
                guard let before else { return false }
                area.setPosition(before, along: axis)
                pixels /= 2
            }
        }
        return false
    }

    /// Returns false when the area is already at the end in that direction.
    private func move(along axis: ScrollAxis, pixels: Double) -> Bool {
        guard area.canSetPosition else {
            return area.revealNext(along: axis, forward: pixels > 0)
        }
        guard let position = area.position(along: axis) else { return false }
        if pixels > 0 && position >= 0.999 { return false }
        if pixels < 0 && position <= 0.001 { return false }

        // Until the first step is measured, guess that the content is five screens long.
        let viewportPixels = axis == .vertical ? cropRect.height : cropRect.width
        let units = unitsPerPixel[axis] ?? 1 / (5 * Double(viewportPixels))
        area.setPosition(position + pixels * units, along: axis)
        return true
    }

    private mutating func learnStepSize(along axis: ScrollAxis, from before: Double?) {
        guard let before,
              let after = area.position(along: axis),
              let offset = stitcher.lastOffset else { return }
        let movedPixels = abs(axis == .vertical ? offset.y : offset.x)
        guard movedPixels > 0 else { return }
        unitsPerPixel[axis] = abs(after - before) / Double(movedPixels)
    }

    // MARK: - Capturing

    /// Captures until two frames in a row look the same, so smooth scrolling has settled.
    private func stableWindowImage() async throws -> CGImage {
        var previous = try await ScreenCaptureService.captureWindow(window)
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(80))
            let current = try await ScreenCaptureService.captureWindow(window)
            guard current.width == previous.width, current.height == previous.height else {
                throw ScrollAreaCaptureError.windowChanged
            }
            if let previousFrame = previous.cropping(to: cropRect),
               let currentFrame = current.cropping(to: cropRect),
               FrameComparison.isStable(previousFrame, currentFrame) {
                return current
            }
            previous = current
        }
        return previous
    }
}

private enum ScrollAreaCaptureError: LocalizedError {
    case windowChanged

    var errorDescription: String? {
        "The window changed size while it was being captured."
    }
}
