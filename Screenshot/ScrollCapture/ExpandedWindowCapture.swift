import ScreenCaptureKit

/// Automatic scrolling capture: scrolls through every scroll area of a window and returns the
/// window as it would look on an endless screen. See `ExpandedWindowComposer` for the layout.
///
/// A web page can hold boxes that scroll on their own (a table, a log). Each box is captured first
/// and drawn into the page at full size, the same way the window grows around its areas; then the
/// grown page goes into the window.
enum ExpandedWindowCapture {
    /// `progress` receives the picture after each finished area, for the live thumbnail.
    static func capture(_ window: SCWindow, progress: (CGImage) -> Void) async throws -> CGImage {
        var areas = ScrollArea.areas(in: window)
        if areas.isEmpty {
            // Chrome builds the tree of a web page a moment after it was first asked for.
            try await Task.sleep(for: .milliseconds(500))
            areas = ScrollArea.areas(in: window)
        }
        guard !areas.isEmpty else { throw ExpandedWindowCaptureError.noScrollAreas }

        let windowImage = try await ScreenCaptureService.captureWindow(window)
        let windowImageSize = CGSize(width: windowImage.width, height: windowImage.height)
        var expandedAreas: [ExpandedArea] = []
        var result = windowImage

        for area in areas {
            // Boxes come first, while the page still shows them where Accessibility found them.
            var boxes: [ExpandedArea] = []
            for box in area.innerAreas {
                var boxCapture = ScrollAreaCapture(area: box, window: window, windowImageSize: windowImageSize)
                guard let content = try await boxCapture.run() else { continue }
                try Task.checkCancellation()
                boxes.append(ExpandedArea(rect: boxCapture.cropRect, content: content))
            }

            var areaCapture = ScrollAreaCapture(area: area, window: window, windowImageSize: windowImageSize)
            guard let content = try await areaCapture.run() else { continue }
            try Task.checkCancellation()
            let grownContent = grow(content, of: areaCapture, around: boxes) ?? content
            expandedAreas.append(ExpandedArea(rect: areaCapture.cropRect, content: grownContent))
            result = ExpandedWindowComposer.compose(window: windowImage, areas: expandedAreas) ?? result
            progress(result)
        }
        return result
    }

    /// Draws each box (found in window pixels) at full size into the page's content, where the
    /// page's first frame showed it.
    private static func grow(_ content: CGImage, of areaCapture: ScrollAreaCapture, around boxes: [ExpandedArea]) -> CGImage? {
        guard !boxes.isEmpty, let firstFrame = areaCapture.firstFrameRect else { return nil }
        let boxesInContent = boxes.map { box in
            ExpandedArea(
                rect: box.rect.offsetBy(
                    dx: firstFrame.minX - areaCapture.cropRect.minX,
                    dy: firstFrame.minY - areaCapture.cropRect.minY
                ),
                content: box.content
            )
        }
        return ExpandedWindowComposer.compose(window: content, areas: boxesInContent)
    }
}

private enum ExpandedWindowCaptureError: LocalizedError {
    case noScrollAreas

    var errorDescription: String? {
        "This window has no scroll areas that Screenshot can scroll. Scroll it yourself instead."
    }
}
