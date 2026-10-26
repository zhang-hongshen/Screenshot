import AppKit
import Observation

/// What the scrolling-capture panels show. `@Observable` makes the SwiftUI views
/// redraw whenever one of these properties changes.
@Observable
final class ScrollCaptureControlState {
    var canFinish = false
    var showsAutomaticControl = false
    var isAutomaticScrolling = false
    /// True after a frame moved too far from the previous one to be joined.
    var isScrollingTooFast = false
    var previewImage: NSImage?
    /// The part of the preview that is on screen now, in preview image pixels.
    var previewVisibleRect: CGRect?
}

/// The floating panel with the Auto, Cancel and Finish buttons.
///
/// An `NSPanel` is needed because it must float above the screen-saver-level backdrop
/// and take clicks without activating Screenshot and pulling focus from the scrolled app.
final class ScrollCaptureControlWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        isReleasedWhenClosed = false
    }
}
