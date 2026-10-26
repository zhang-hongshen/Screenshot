import SwiftUI

/// Hosts the selection overlay and takes the very first click on it.
///
/// A capture usually starts while another app is active (from the menu bar or a global shortcut).
/// AppKit would spend the first click on an inactive app's window only on activating it, so the
/// user had to click a window twice to pick it.
final class CaptureHostingView: NSHostingView<CaptureView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
