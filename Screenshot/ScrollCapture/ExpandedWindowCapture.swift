import ScreenCaptureKit

/// Automatic scrolling capture: scrolls through every scroll area of a window and returns the
/// window as it would look on an endless screen. See `ExpandedWindowComposer` for the layout.
enum ExpandedWindowCapture {
    /// `progress` receives the picture after each finished area, for the live thumbnail.
    static func capture(_ window: SCWindow, progress: (CGImage) -> Void) async throws -> CGImage {
        let areas = ScrollArea.areas(in: window)
        guard !areas.isEmpty else { throw ExpandedWindowCaptureError.noScrollAreas }

        let windowImage = try await ScreenCaptureService.captureWindow(window)
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
}

private enum ExpandedWindowCaptureError: LocalizedError {
    case noScrollAreas

    var errorDescription: String? {
        "This window has no scroll areas that Screenshot can scroll. Scroll it yourself instead."
    }
}
