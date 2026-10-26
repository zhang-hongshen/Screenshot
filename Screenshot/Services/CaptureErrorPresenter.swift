import AppKit

/// Shows capture failures, such as a missing Screen Recording permission, in an alert.
@MainActor
enum CaptureErrorPresenter {
    static func present(_ error: Error) {
        NSApp.activate()
        let nsError = error as NSError
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to capture the screen"
        alert.informativeText = "\(error.localizedDescription)\n\(nsError.domain) (\(nsError.code))"
        alert.runModal()
    }
}
