import ApplicationServices
import ScreenCaptureKit

enum ScrollAxis {
    case vertical
    case horizontal
}

/// One scrollable part of another app's window, such as a sidebar list or a document view.
///
/// An area is moved through its Accessibility scroll bars when it has them, because a scroll bar
/// reports exactly where it is. A scrolling box of a web page (the page, a table, a log) is moved
/// with JavaScript, just as exactly. Other areas (Chrome's page when JavaScript is off) get
/// scroll-wheel events.
struct ScrollArea {
    /// A scrolling box of a web page. Its end stays where it was when the capture started, so a
    /// feed that loads more while it is scrolled is not followed.
    struct WebScroller {
        let page: WebPage
        let index: Int
        /// Largest scroll offset in CSS pixels when the capture started.
        let maximum: CGPoint
    }

    /// Visible content in screen coordinates with a top-left origin, without the scroll bars.
    let frame: CGRect
    let verticalScrollBar: AXUIElement?
    let horizontalScrollBar: AXUIElement?
    var webScroller: WebScroller?

    /// Whether the area reports and sets its own scroll position, so no wheel events are needed.
    var canSetPosition: Bool {
        verticalScrollBar != nil || horizontalScrollBar != nil || webScroller != nil
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
        if let webScroller {
            guard let area = try? webScroller.page.area(webScroller.index) else { return nil }
            let maximum = axis == .vertical ? webScroller.maximum.y : webScroller.maximum.x
            let offset = axis == .vertical ? area.scrollTop : area.scrollLeft
            return maximum > 0 ? min(1, offset / maximum) : nil
        }
        guard let bar = scrollBar(along: axis),
              let value = bar.number(of: kAXValueAttribute) else { return nil }
        let range = Self.range(of: bar)
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    func setPosition(_ position: Double, along axis: ScrollAxis) {
        let clamped = min(max(position, 0), 1)
        if let webScroller {
            guard var offset = try? webScroller.page.area(webScroller.index).scrollOffset else { return }
            switch axis {
            case .vertical: offset.y = (clamped * webScroller.maximum.y).rounded()
            case .horizontal: offset.x = (clamped * webScroller.maximum.x).rounded()
            }
            try? webScroller.page.scroll(area: webScroller.index, to: offset)
            return
        }
        guard let bar = scrollBar(along: axis) else { return }
        let range = Self.range(of: bar)
        bar.setNumber(range.lowerBound + clamped * (range.upperBound - range.lowerBound), for: kAXValueAttribute)
    }

    /// Scrolls with the wheel as one trackpad swipe. Positive `points` reveal content below or to the right.
    ///
    /// A browser keeps a swipe on the view it began in, so a table that reaches its end mid-swipe
    /// does not hand the rest to the page around it. Each event is routed by window number, so the
    /// user's pointer stays where it is.
    func scrollWheel(by points: Double, along axis: ScrollAxis, in window: SCWindow) {
        guard let processID = window.owningApplication?.processID else { return }
        let partCount = 4
        let part = Int32(clamping: Int((-points / Double(partCount)).rounded()))
        let phases: [(CGScrollPhase, Int32)] = [(.began, part)]
            + Array(repeating: (.changed, part), count: partCount - 1)
            + [(.ended, 0)]
        for (phase, delta) in phases {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: axis == .vertical ? delta : 0,
                wheel2: axis == .horizontal ? delta : 0,
                wheel3: 0
            ) else { return }
            event.location = CGPoint(x: frame.midX, y: frame.midY)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowID))
            event.postToPid(processID)
        }
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

    /// The page view of a browser window in screen coordinates with a top-left origin: the scroll
    /// area around the largest web area. A web area's own frame is the whole page in Safari.
    static func webViewportFrame(in window: SCWindow) -> CGRect? {
        guard let windowElement = element(of: window) else { return nil }
        var visitedCount = 0
        var webAreas: [AXUIElement] = []
        collectWebAreas(in: windowElement, into: &webAreas, visitedCount: &visitedCount)
        let frames = webAreas.compactMap { webArea in
            webArea.parent.flatMap { $0.role == kAXScrollAreaRole ? $0.frame : nil } ?? webArea.frame
        }
        return frames.max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func collectWebAreas(in element: AXUIElement, into webAreas: inout [AXUIElement], visitedCount: inout Int) {
        visitedCount += 1
        guard visitedCount < 3_000 else { return }
        if element.role == "AXWebArea" {
            webAreas.append(element)
            return
        }
        for child in element.children {
            collectWebAreas(in: child, into: &webAreas, visitedCount: &visitedCount)
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
            return [ScrollArea(frame: frame, verticalScrollBar: nil, horizontalScrollBar: nil)]
        }
        return []
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
