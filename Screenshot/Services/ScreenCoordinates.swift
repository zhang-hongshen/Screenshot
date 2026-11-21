import AppKit

/// Converts between AppKit (bottom-left origin), ScreenCaptureKit (top-left origin) and overlay coordinates.
enum ScreenCoordinates {
    nonisolated static func imageRect(fromVision rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * imageSize.width,
            y: (1 - rect.maxY) * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    nonisolated static func drawingPath(fromImage path: CGPath, imageHeight: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: 0, y: imageHeight).scaledBy(x: 1, y: -1)
        return path.copy(using: &transform) ?? path
    }

    nonisolated static func drawingRect(fromImage rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(fromScreenCapture rect: CGRect) -> CGRect {
        guard let screen = screenContainingMost(screenCaptureRect: rect),
              let displayBounds = displayBounds(for: screen) else { return rect }

        return CGRect(
            x: screen.frame.minX + rect.minX - displayBounds.minX,
            y: screen.frame.maxY - (rect.maxY - displayBounds.minY),
            width: rect.width,
            height: rect.height
        )
    }

    static func screenCapturePoint(fromAppKit point: CGPoint) -> CGPoint {
        guard let screen = screen(containing: point),
              let displayBounds = displayBounds(for: screen) else { return point }

        return CGPoint(
            x: displayBounds.minX + point.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - point.y
        )
    }

    static func screenCaptureRect(fromAppKit rect: CGRect) -> CGRect {
        guard let screen = screenContainingMost(ofAppKitRect: rect),
              let displayBounds = displayBounds(for: screen) else { return rect }

        return CGRect(
            x: displayBounds.minX + rect.minX - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func screenContainingMost(ofAppKitRect rect: CGRect) -> NSScreen? {
        screenContainingMost(of: rect) { screen in
            screen.frame.intersection(rect)
        }
    }

    static func appKitPoint(fromOverlay point: CGPoint, on screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + point.x,
            y: screenFrame.maxY - point.y
        )
    }

    static func overlayPoint(fromAppKit point: CGPoint, on screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: point.x - screenFrame.minX,
            y: screenFrame.maxY - point.y
        )
    }

    static func overlayRect(fromAppKit rect: CGRect, on screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Returns a ScreenCaptureKit source rectangle local to `screen`.
    /// Both ScreenCaptureKit source rectangles and this result use a top-left origin.
    static func sourceRect(for appKitRect: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(
            x: appKitRect.minX - screen.frame.minX,
            y: screen.frame.maxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }
}

private extension ScreenCoordinates {
    static func displayBounds(for screen: NSScreen) -> CGRect? {
        displayID(for: screen).map { CGDisplayBounds($0) }
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    static func screenContainingMost(screenCaptureRect rect: CGRect) -> NSScreen? {
        screenContainingMost(of: rect) { screen in
            guard let displayBounds = displayBounds(for: screen) else { return .null }
            return displayBounds.intersection(rect)
        }
    }

    static func screenContainingMost(
        of rect: CGRect,
        intersection: (NSScreen) -> CGRect
    ) -> NSScreen? {
        NSScreen.screens.max {
            intersection($0).safeArea < intersection($1).safeArea
        } ?? NSScreen.main
    }
}

private extension CGRect {
    var safeArea: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}
