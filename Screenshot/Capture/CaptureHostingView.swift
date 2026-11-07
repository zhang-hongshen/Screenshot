import Observation
import SwiftUI

/// Uses AppKit to accept the first click and show a camera cursor over a capturable window.
///
/// A capture usually starts while another app is active (from the menu bar or a global shortcut).
/// AppKit would spend the first click on an inactive app's window only on activating it, so the
/// user had to click a window twice to pick it.
final class CaptureHostingView: NSHostingView<CaptureView> {
    private static let cameraCursor: NSCursor = {
        let size = NSSize(width: 32, height: 32)
        let symbol = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Capture window")?
            .withSymbolConfiguration(.init(paletteColors: [.black]))
        let image = NSImage(size: size, flipped: false) { _ in
            let badge = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 30, height: 30), xRadius: 7, yRadius: 7)
            NSColor.white.setFill()
            badge.fill()
            NSColor.black.setStroke()
            badge.lineWidth = 1
            badge.stroke()
            symbol?.draw(in: NSRect(x: 5, y: 7, width: 22, height: 18))
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 16, y: 16))
    }()

    override func resetCursorRects() {
        super.resetCursorRects()
        let showsCamera = withObservationTracking {
            !rootView.state.isEditing
                && rootView.selection.rect == nil
                && rootView.detector.hoveredWindow != nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                window?.invalidateCursorRects(for: self)
            }
        }
        if showsCamera {
            addCursorRect(bounds, cursor: Self.cameraCursor)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
