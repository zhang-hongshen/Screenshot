import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct ScreenshotApp: App {
    @Environment(\.openSettings) private var openSettings

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)

        KeyboardShortcuts.onKeyUp(for: .capture) {
            CaptureManager.shared.start()
        }
        KeyboardShortcuts.onKeyUp(for: .scrollingCapture) {
            ScrollCaptureManager.shared.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Button("Capture") {
                CaptureManager.shared.start()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Scrolling Capture") {
                ScrollCaptureManager.shared.start()
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Open Lastest Capture") {
                CaptureManager.shared.reopenLastCapture()
            }

            Divider()

            Button("Settings") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "macwindow")
        }

        Settings {
            SettingsView()
        }
    }
}
