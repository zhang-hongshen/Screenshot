import ScreenCaptureKit

/// Finds the frontmost window under the pointer, several times a second, while a capture is being chosen.
@MainActor
@Observable
final class WindowDetector {
    private(set) var hoveredWindow: SCWindow?

    @ObservationIgnored private var windowsByID: [CGWindowID: SCWindow] = [:]

    func run() async {
        defer {
            hoveredWindow = nil
            windowsByID.removeAll(keepingCapacity: true)
        }

        var iteration = 0
        while !Task.isCancelled {
            if iteration.isMultiple(of: 8) {
                await refreshWindows()
            }
            detectHoveredWindow()
            iteration += 1
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                break
            }
        }
    }

    private func refreshWindows() async {
        guard let content = try? await SCShareableContent.current else {
            windowsByID.removeAll(keepingCapacity: true)
            hoveredWindow = nil
            return
        }

        windowsByID = Dictionary(uniqueKeysWithValues: content.windows.lazy
            .filter { $0.isOnScreen }
            .map { ($0.windowID, $0) })
    }

    private func detectHoveredWindow() {
        let mouse = ScreenCoordinates.screenCapturePoint(fromAppKit: NSEvent.mouseLocation)
        let currentProcessID = ProcessInfo.processInfo.processIdentifier

        let window: SCWindow? = Self.frontToBackWindowIDs().lazy.compactMap { id -> SCWindow? in
            guard let window = self.windowsByID[id],
                  window.owningApplication?.processID != currentProcessID,
                  window.frame.width >= 40,
                  window.frame.height >= 40,
                  window.frame.contains(mouse) else { return nil }
            return window
        }.first

        let windowChanged = window?.windowID != hoveredWindow?.windowID
            || window?.frame != hoveredWindow?.frame
        guard windowChanged else { return }
        hoveredWindow = window
    }

    private static func frontToBackWindowIDs() -> [CGWindowID] {
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return windowInfo.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0 else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
    }
}
