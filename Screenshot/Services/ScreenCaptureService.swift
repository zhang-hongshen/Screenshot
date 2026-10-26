import AppKit
import ScreenCaptureKit

/// Takes pictures of windows and screen regions with ScreenCaptureKit.
enum ScreenCaptureService {

    static func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.backgroundColor = .clear
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.captureResolution = .best

        let scale = max(1, CGFloat(filter.pointPixelScale))
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        try Task.checkCancellation()
        return image
    }

    /// Pass `content` when capturing the same region again and again: looking it up is slow.
    static func captureRegion(_ selection: CGRect, content: SCShareableContent? = nil) async throws -> CGImage {
        let content = if let content { content } else { try await SCShareableContent.current }
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let excludedApplications = content.applications.filter {
            $0.processID == currentProcessID
        }
        let displaysByID = Dictionary(
            uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) }
        )
        let screenParts = NSScreen.screens.compactMap { screen -> ScreenPart? in
            let intersection = selection.intersection(screen.frame)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0,
                  let id = ScreenCoordinates.displayID(for: screen),
                  let display = displaysByID[id] else { return nil }
            return ScreenPart(screen: screen, display: display, intersection: intersection)
        }
        guard !screenParts.isEmpty else { throw ScreenCaptureServiceError.noDisplay }

        let outputScale = screenParts.map { part in
            let filter = SCContentFilter(
                display: part.display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            return max(1, CGFloat(filter.pointPixelScale))
        }.max() ?? 1
        var pieces: [ScreenCaptureRegionCompositor.Piece] = []

        for part in screenParts {
            try Task.checkCancellation()
            let filter = SCContentFilter(
                display: part.display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let scale = max(1, CGFloat(filter.pointPixelScale))
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = ScreenCoordinates.sourceRect(
                for: part.intersection,
                on: part.screen
            )
            configuration.width = max(
                1,
                Int((part.intersection.width * scale).rounded())
            )
            configuration.height = max(
                1,
                Int((part.intersection.height * scale).rounded())
            )
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            pieces.append(ScreenCaptureRegionCompositor.Piece(
                appKitRect: part.intersection,
                image: image
            ))
        }

        return try ScreenCaptureRegionCompositor.compose(
            selection: selection,
            outputScale: outputScale,
            pieces: pieces
        )
    }
}

private extension ScreenCaptureService {
    struct ScreenPart {
        let screen: NSScreen
        let display: SCDisplay
        let intersection: CGRect
    }
}

private enum ScreenCaptureServiceError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "The selected region does not intersect an available display."
        }
    }
}
