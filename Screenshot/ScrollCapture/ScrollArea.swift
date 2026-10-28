import ApplicationServices
import ScreenCaptureKit

enum ScrollAxis {
    case vertical
    case horizontal
}

/// One scrollable part of another app's window, such as a sidebar list or a document view.
///
/// An area is moved through its Accessibility scroll bars when it has them, because a scroll bar
/// reports exactly where it is. Areas without scroll bars (Chrome's web pages and the scrolling
/// boxes inside them, such as a table or a log) are moved by asking the app to show an item that
/// is hidden past the edge (see `ScrollArea+Reveal.swift`). No input events are ever posted.
struct ScrollArea {
    /// Visible content in screen coordinates with a top-left origin, without the scroll bars.
    let frame: CGRect
    let verticalScrollBar: AXUIElement?
    let horizontalScrollBar: AXUIElement?
    /// The area's own element; areas without scroll bars are moved through the items inside it.
    var element: AXUIElement?
    /// Scrolling boxes inside a web page area (a table, a log), each captured on its own.
    var innerAreas: [ScrollArea] = []

    /// Whether the area reports and sets its own scroll position through scroll bars.
    var canSetPosition: Bool {
        verticalScrollBar != nil || horizontalScrollBar != nil
    }

    /// Where the area sits inside a capture of `window`, in pixels with a top-left origin.
    func pixelRect(in window: SCWindow, pixelsPerPoint: CGFloat) -> CGRect {
        CGRect(
            x: (frame.minX - window.frame.minX) * pixelsPerPoint,
            y: (frame.minY - window.frame.minY) * pixelsPerPoint,
            width: frame.width * pixelsPerPoint,
            height: frame.height * pixelsPerPoint
        ).integral
    }

    /// Scroll position from 0 (start) to 1 (end), or nil when the area has no scroll bar on `axis`.
    func position(along axis: ScrollAxis) -> Double? {
        guard let bar = scrollBar(along: axis),
              let value = bar.number(of: kAXValueAttribute) else { return nil }
        let range = Self.range(of: bar)
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    func setPosition(_ position: Double, along axis: ScrollAxis) {
        let clamped = min(max(position, 0), 1)
        guard let bar = scrollBar(along: axis) else { return }
        let range = Self.range(of: bar)
        bar.setNumber(range.lowerBound + clamped * (range.upperBound - range.lowerBound), for: kAXValueAttribute)
    }

    private func scrollBar(along axis: ScrollAxis) -> AXUIElement? {
        switch axis {
        case .vertical: verticalScrollBar
        case .horizontal: horizontalScrollBar
        }
    }

    private static func range(of bar: AXUIElement) -> ClosedRange<Double> {
        let minimum = bar.number(of: kAXMinValueAttribute) ?? 0
        let maximum = bar.number(of: kAXMaxValueAttribute) ?? 1
        return minimum...max(maximum, minimum + 0.000_1)
    }
}

// MARK: - Finding areas

extension ScrollArea {
    /// Whether the user has allowed Screenshot to read and scroll other apps.
    /// Passing `prompt: true` shows the system dialog that leads to System Settings.
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Finds every scroll area of `window`. An area inside another scrolling area is skipped,
    /// because the outer area already shows it while it scrolls.
    static func areas(in window: SCWindow) -> [ScrollArea] {
        guard let windowElement = element(of: window) else { return [] }
        var visitedCount = 0
        return areas(in: windowElement, visitedCount: &visitedCount).filter { area in
            area.frame.width >= 40 && area.frame.height >= 40
        }
    }

    /// The Accessibility element of `window`, found by its frame.
    private static func element(of window: SCWindow) -> AXUIElement? {
        guard let processID = window.owningApplication?.processID else { return nil }
        let application = AXUIElementCreateApplication(processID)
        // Chrome and Electron apps build the tree of their web content only when asked to.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return application.windows.first { element in
            guard let frame = element.frame else { return false }
            return abs(frame.minX - window.frame.minX) < 2
                && abs(frame.minY - window.frame.minY) < 2
                && abs(frame.width - window.frame.width) < 2
                && abs(frame.height - window.frame.height) < 2
        }
    }

    private static func areas(in element: AXUIElement, visitedCount: inout Int) -> [ScrollArea] {
        visitedCount += 1
        guard visitedCount < 3_000 else { return [] }

        let isScrollArea = element.role == kAXScrollAreaRole
        if isScrollArea, let area = ScrollArea(scrollBarsOf: element) {
            return [area]
        }

        var nestedAreas: [ScrollArea] = []
        for child in element.children {
            nestedAreas += areas(in: child, visitedCount: &visitedCount)
        }
        if !nestedAreas.isEmpty {
            return nestedAreas
        }

        if isScrollArea, let frame = element.frame {
            var area = ScrollArea(frame: frame, verticalScrollBar: nil, horizontalScrollBar: nil, element: element)
            if element.children.contains(where: { $0.role == "AXWebArea" }) {
                var boxVisitedCount = 0
                area.innerAreas = webBoxes(in: element, page: frame, visitedCount: &boxVisitedCount)
            }
            return [area]
        }
        return []
    }

    /// Boxes inside a web page that scroll on their own, such as a table or a log.
    ///
    /// Chrome shows no scroll bar or position for them, but it clips a box's content to the box:
    /// rows scrolled out of a log shrink to a line along its edge, and a table's columns reach past
    /// it. The page clips everything at its own edges the same way, so only boxes that are fully
    /// on screen count.
    private static func webBoxes(in element: AXUIElement, page: CGRect, visitedCount: inout Int) -> [ScrollArea] {
        visitedCount += 1
        guard visitedCount < 3_000 else { return [] }
        let children = element.children
        if let frame = element.frame,
           frame.width >= 40, frame.height >= 40,
           page.insetBy(dx: 1, dy: 1).contains(frame),
           clipsContent(frame: frame, childFrames: children.compactMap(\.frame)) {
            return [ScrollArea(frame: frame, verticalScrollBar: nil, horizontalScrollBar: nil, element: element)]
        }
        var boxes: [ScrollArea] = []
        for child in children {
            boxes += webBoxes(in: child, page: page, visitedCount: &visitedCount)
        }
        return boxes
    }

    /// Whether a child reaches past the box, or was squeezed to a line along one of its edges.
    nonisolated static func clipsContent(frame: CGRect, childFrames: [CGRect]) -> Bool {
        let tolerance: CGFloat = 2
        return childFrames.contains { child in
            let reachesPast = child.minX < frame.minX - tolerance || child.maxX > frame.maxX + tolerance
                || child.minY < frame.minY - tolerance || child.maxY > frame.maxY + tolerance
            let squeezedAtTopOrBottom = child.height <= 1
                && (abs(child.minY - frame.minY) <= tolerance || abs(child.maxY - frame.maxY) <= tolerance)
            let squeezedAtSide = child.width <= 1
                && (abs(child.minX - frame.minX) <= tolerance || abs(child.maxX - frame.maxX) <= tolerance)
            return reachesPast || squeezedAtTopOrBottom || squeezedAtSide
        }
    }

    /// Returns nil when the element has no scroll bar that can move.
    private init?(scrollBarsOf element: AXUIElement) {
        guard var frame = element.frame else { return nil }
        let vertical = element.element(of: kAXVerticalScrollBarAttribute).flatMap(Self.movableBar)
        let horizontal = element.element(of: kAXHorizontalScrollBarAttribute).flatMap(Self.movableBar)
        guard vertical != nil || horizontal != nil else { return nil }

        // Scroll bars sit on top of the content and flash while scrolling, so leave them out.
        if let bar = vertical?.frame, bar.minX > frame.minX {
            frame.size.width = min(frame.width, bar.minX - frame.minX)
        }
        if let bar = horizontal?.frame, bar.minY > frame.minY {
            frame.size.height = min(frame.height, bar.minY - frame.minY)
        }
        self.init(frame: frame, verticalScrollBar: vertical, horizontalScrollBar: horizontal)
    }

    /// Many scroll bars only report a value from 0 to 1 and no range, so a readable value is enough.
    private static func movableBar(_ bar: AXUIElement) -> AXUIElement? {
        bar.number(of: kAXValueAttribute) == nil ? nil : bar
    }
}
