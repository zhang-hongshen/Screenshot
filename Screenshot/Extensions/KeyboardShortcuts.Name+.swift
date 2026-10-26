import AppKit
import KeyboardShortcuts

/// The global shortcuts. KeyboardShortcuts stores the user's choice in UserDefaults under these names.
extension KeyboardShortcuts.Name {
    static let capture = Self("capture", initial: .init(.one, modifiers: .command))
    static let scrollingCapture = Self("scrollingCapture", initial: .init(.two, modifiers: .command))
}
