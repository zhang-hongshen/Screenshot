import ScreenCaptureKit

/// Automatic scrolling capture: scrolls through every scroll area of a window and returns the
/// window as it would look on an endless screen. See `ExpandedWindowComposer` for the layout.
///
/// In a browser that allows JavaScript from Apple Events, the page itself lists its scrolling boxes
/// (see `WebPage`). Each box inside the page (a table, a log) is captured on its own and drawn into
/// the page at full size, the way the window grows around its areas; then the grown page goes into
/// the window. Other windows, and browsers without JavaScript, are read through Accessibility.
enum ExpandedWindowCapture {
    /// `progress` receives the picture after each finished area, for the live thumbnail.
    static func capture(_ window: SCWindow, progress: (CGImage) -> Void) async throws -> CGImage {
        let windowImage = try await ScreenCaptureService.captureWindow(window)
        if let page = WebPage(window: window),
           let layout = try? page.layout(),
           let viewport = ScrollArea.webViewportFrame(in: window) {
            return try await capturePage(page, layout: layout, viewport: viewport, window: window, windowImage: windowImage, progress: progress)
        }

        var areas = ScrollArea.areas(in: window)
        if areas.isEmpty {
            // Chrome builds the tree of a web page a moment after it was first asked for.
            try await Task.sleep(for: .milliseconds(500))
            areas = ScrollArea.areas(in: window)
        }
        guard !areas.isEmpty else { throw ExpandedWindowCaptureError.noScrollAreas }

        let windowImageSize = CGSize(width: windowImage.width, height: windowImage.height)
        var expandedAreas: [ExpandedArea] = []
        var result = windowImage

        for area in areas {
            var areaCapture = ScrollAreaCapture(area: area, window: window, windowImageSize: windowImageSize)
            guard let content = try await areaCapture.run() else { continue }
            try Task.checkCancellation()
            expandedAreas.append(ExpandedArea(rect: areaCapture.cropRect, content: content))
            result = ExpandedWindowComposer.compose(window: windowImage, areas: expandedAreas) ?? result
            progress(result)
        }
        return result
    }

    // MARK: - Web pages

    /// `viewport` is where the page is shown on screen (top-left origin), scroll bar included.
    private static func capturePage(
        _ page: WebPage,
        layout: WebPage.Layout,
        viewport: CGRect,
        window: SCWindow,
        windowImage: CGImage,
        progress: (CGImage) -> Void
    ) async throws -> CGImage {
        guard let pageLayout = layout.areas.first else { throw ExpandedWindowCaptureError.noScrollAreas }
        let pointsPerCSSPixel = viewport.width / max(1, layout.viewportWidth)
        let pixelsPerPoint = CGFloat(windowImage.width) / max(1, window.frame.width)
        let pixelsPerCSSPixel = pointsPerCSSPixel * pixelsPerPoint
        let windowImageSize = CGSize(width: windowImage.width, height: windowImage.height)
        let pageStart = pageLayout.scrollOffset
        defer { try? page.scroll(area: 0, to: pageStart) }

        /// The screen frame of a box, given in CSS pixels relative to the viewport.
        func screenFrame(of rect: CGRect) -> CGRect {
            CGRect(
                x: viewport.minX + rect.minX * pointsPerCSSPixel,
                y: viewport.minY + rect.minY * pointsPerCSSPixel,
                width: rect.width * pointsPerCSSPixel,
                height: rect.height * pointsPerCSSPixel
            )
        }
        let pageFrame = screenFrame(of: pageLayout.rect)

        // Boxes directly inside the page, each scrolled into the middle of the viewport first.
        // Their rects are in pixels of the page's content, measured from its top-left corner.
        var boxes: [ExpandedArea] = []
        for (index, box) in layout.areas.enumerated() where box.parent == 0 {
            let documentTop = box.y + pageLayout.scrollTop
            let documentLeft = box.x + pageLayout.scrollLeft
            let pageOffset = try page.scroll(area: 0, to: CGPoint(
                x: max(0, documentLeft - max(0, (pageLayout.width - box.width) / 2)),
                y: max(0, documentTop - max(0, (pageLayout.height - box.height) / 2))
            )).scrollOffset
            let visible = try page.area(index).rect.intersection(pageLayout.rect)
            guard visible.width >= 40, visible.height >= 40 else { continue }

            let area = ScrollArea(
                frame: screenFrame(of: visible),
                verticalScrollBar: nil,
                horizontalScrollBar: nil,
                webScroller: ScrollArea.WebScroller(
                    page: page,
                    index: index,
                    maximum: CGPoint(x: box.maximumLeft, y: box.maximumTop)
                )
            )
            var areaCapture = ScrollAreaCapture(area: area, window: window, windowImageSize: windowImageSize)
            guard let content = try await areaCapture.run() else { continue }
            try Task.checkCancellation()
            let rectInPage = CGRect(
                x: (visible.minX + pageOffset.x) * pixelsPerCSSPixel,
                y: (visible.minY + pageOffset.y) * pixelsPerCSSPixel,
                width: areaCapture.cropRect.width,
                height: areaCapture.cropRect.height
            ).integral
            boxes.append(ExpandedArea(rect: rectInPage, content: content))
        }

        let pageArea = ScrollArea(
            frame: pageFrame,
            verticalScrollBar: nil,
            horizontalScrollBar: nil,
            webScroller: ScrollArea.WebScroller(
                page: page,
                index: 0,
                maximum: CGPoint(x: pageLayout.maximumLeft, y: pageLayout.maximumTop)
            )
        )
        var pageCapture = ScrollAreaCapture(area: pageArea, window: window, windowImageSize: windowImageSize)
        guard let pageImage = try await pageCapture.run() else { throw ExpandedWindowCaptureError.noScrollAreas }
        let grownPage = ExpandedWindowComposer.compose(window: pageImage, areas: boxes) ?? pageImage
        let result = ExpandedWindowComposer.compose(
            window: windowImage,
            areas: [ExpandedArea(rect: pageCapture.cropRect, content: grownPage)]
        ) ?? windowImage
        progress(result)
        return result
    }
}

private enum ExpandedWindowCaptureError: LocalizedError {
    case noScrollAreas

    var errorDescription: String? {
        "This window has no scroll areas that Screenshot can scroll. Scroll it yourself instead."
    }
}
