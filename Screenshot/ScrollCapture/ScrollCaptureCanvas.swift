import CoreGraphics

/// Collects the frames of a manual scrolling capture.
///
/// Every part of the picture that the user scrolls becomes its own area with its own stitcher.
/// A sidebar and a document can both be scrolled, in any direction and in any order, and the
/// result shows each of them at full length, as if the window sat on an endless screen.
nonisolated struct ScrollCaptureCanvas {
    /// What a new frame showed.
    enum Change {
        /// Some area moved and the new part was added.
        case scrolled
        /// Nothing scrolled: the picture has settled.
        case unchanged
        /// An area moved too far since its last frame to be matched, which happens when the
        /// user scrolls faster than frames can be taken.
        case movedTooFar
    }

    private struct Area {
        let rect: CGRect
        var stitcher = ScrollCaptureStitcher()
    }

    /// Scroll views reported by Accessibility, in frame pixels. When one of them contains a change,
    /// its exact bounds are used instead of the changed pixels' bounds.
    var knownScrollViewRects: [CGRect] = []

    /// The first frame. Everything outside the scrolled areas comes from it.
    private(set) var firstFrame: CGImage?
    private var previousFrame: CGImage?
    private var previousSmallFrame: FrameComparison.SmallFrame?
    private var areas: [Area] = []
    private var activeAreaIndex: Int?

    var hasScrolled: Bool {
        !areas.isEmpty
    }

    /// Adds a frame. Frames of another size (after the window was resized) are ignored.
    @discardableResult
    mutating func add(_ frame: CGImage) -> Change {
        let smallFrame = FrameComparison.SmallFrame(frame)
        guard let previousFrame, let previousSmallFrame else {
            firstFrame = frame
            self.previousFrame = frame
            self.previousSmallFrame = smallFrame
            return .scrolled
        }
        guard let smallFrame, frame.width == previousFrame.width, frame.height == previousFrame.height else {
            return .unchanged
        }

        let regions = FrameComparison.changedRegions(from: previousSmallFrame, to: smallFrame)
        // Nothing visible changed, so no area scrolled and the stitchers can be skipped. The previous
        // frame is kept, so a very slow scroll still adds up to a visible change a few frames later.
        guard !regions.isEmpty else { return .unchanged }

        var change = Change.unchanged
        for index in areas.indices {
            guard let crop = frame.cropping(to: areas[index].rect) else { continue }
            switch areas[index].stitcher.append(crop) {
            case .appended:
                activeAreaIndex = index
                if change == .unchanged { change = .scrolled }
            case .noOverlap:
                change = .movedTooFar
            case .unchanged, .limitReached:
                break
            }
        }

        // In a sparse view (an icon grid) every icon is a change of its own, and a single plain icon
        // can line up at a wrong offset. All new changes together carry enough detail, so they are
        // tried as one area first, then one by one, biggest first.
        let newRegions = regions.filter { region in !areas.contains { $0.rect.intersects(region) } }
        var candidates = newRegions.sorted { $0.width * $0.height > $1.width * $1.height }
        if newRegions.count > 1 {
            candidates.insert(newRegions.reduce(CGRect.null) { $0.union($1) }, at: 0)
        }
        for region in candidates where !areas.contains(where: { $0.rect.intersects(region) }) {
            guard let area = startArea(around: region, before: previousFrame, after: frame) else { continue }
            areas.append(area)
            activeAreaIndex = areas.count - 1
            if change == .unchanged { change = .scrolled }
        }
        self.previousFrame = frame
        self.previousSmallFrame = smallFrame
        return change
    }

    /// The finished picture. A `scale` below 1 makes a smaller copy, for the live preview.
    func makeImage(scale: CGFloat = 1) -> CGImage? {
        guard let firstFrame,
              let window = scale == 1 ? firstFrame : ExpandedWindowComposer.scaled(firstFrame, by: scale) else { return nil }
        var expandedAreas: [ExpandedArea] = []
        for area in areas {
            if let content = area.stitcher.makeImage(scale: scale) {
                expandedAreas.append(ExpandedArea(rect: Self.scaled(area.rect, by: scale), content: content))
            }
        }
        return ExpandedWindowComposer.compose(window: window, areas: expandedAreas) ?? window
    }

    /// The part of `makeImage()` that is on screen right now, in the area the user scrolled last.
    var latestVisibleRect: CGRect? {
        guard let firstFrame else { return nil }
        guard let activeAreaIndex,
              let frameRect = areas[activeAreaIndex].stitcher.latestFrameRect else {
            return CGRect(x: 0, y: 0, width: firstFrame.width, height: firstFrame.height)
        }
        let origin = ExpandedWindowComposer.origin(
            ofArea: activeAreaIndex,
            rects: areas.map(\.rect),
            contentSizes: areas.map(\.stitcher.outputSize),
            window: firstFrame
        )
        return frameRect.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// Keeps the change as a new area only when it really scrolled. A spinner, a blinking caret
    /// or a hover effect also changes pixels, but its two frames do not line up as a scroll.
    private func startArea(around change: CGRect, before: CGImage, after: CGImage) -> Area? {
        let bounds = CGRect(x: 0, y: 0, width: before.width, height: before.height)
        let knownRect = knownScrollViewRects.first { $0.intersects(change) }
        let rect = (knownRect ?? change).integral.intersection(bounds)
        guard rect.width >= 40, rect.height >= 40,
              let area = Self.scrolledArea(rect, before: before, after: after) else { return nil }

        guard knownRect == nil, let offset = area.stitcher.lastOffset else { return area }
        let scrollViewRect = FrameComparison.scrollViewRect(around: rect, movedBy: offset, from: before, to: after)
        return Self.scrolledArea(scrollViewRect, before: before, after: after) ?? area
    }

    /// An area holding both frames, or nil when they do not line up as a scroll.
    private static func scrolledArea(_ rect: CGRect, before: CGImage, after: CGImage) -> Area? {
        guard let beforeCrop = before.cropping(to: rect),
              let afterCrop = after.cropping(to: rect) else { return nil }
        var area = Area(rect: rect)
        _ = area.stitcher.append(beforeCrop)
        guard area.stitcher.append(afterCrop) == .appended else { return nil }
        return area
    }

    private static func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
    }
}
