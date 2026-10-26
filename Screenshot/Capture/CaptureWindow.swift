import AppKit
import Observation

/// Per-overlay state that switches the overlay from selecting to editing.
@Observable
final class CaptureState {
    var isEditing = false
    var windowMask: CGImage?
    var sourceImage: NSImage?
    var pixelatedImage: NSImage?
    var markupDocument: MarkupDocument?
}

/// One borderless overlay window per display, above everything including full-screen apps.
/// A custom `NSWindow` is needed because SwiftUI windows cannot use the screen-saver level.
final class CaptureWindow: NSWindow {
    let overlayState = CaptureState()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }
}
