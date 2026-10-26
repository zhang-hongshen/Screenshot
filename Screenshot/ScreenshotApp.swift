import KeyboardShortcuts
import SwiftUI

/// The app lives in the menu bar: no Dock icon, just a menu, global shortcuts,
/// the Settings window and the markup editor window.
@main
struct ScreenshotApp: App {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

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
        MenuBarExtra("Screenshot", image: "MenuBarIcon") {
            Button("Capture") {
                CaptureManager.shared.start()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Scrolling Capture") {
                ScrollCaptureManager.shared.start()
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Open Latest Capture") {
                openWindow(id: "markup-editor")
            }
            .disabled(CaptureResultManager.shared.latestImage == nil)

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
        }

        Settings {
            SettingsView()
        }

        WindowGroup("Screenshot", id: "markup-editor") {
            if let image = CaptureResultManager.shared.latestImage {
                MarkupEditorView(image: image)
                    // A new screenshot gets a new editor with its own markup.
                    .id(ObjectIdentifier(image))
                    .frame(minWidth: 820, minHeight: 460)
            }
        }
        .windowResizability(.contentMinSize)

        WindowGroup("Combine Screenshots", id: "collage") {
            let images = CaptureResultManager.shared.previewImages
            if images.count >= 2 {
                CollageEditorView(images: images)
                    // Screenshots added or closed in the preview start a fresh arrangement.
                    .id(images.map(ObjectIdentifier.init))
                    .frame(minWidth: 640, minHeight: 480)
            }
        }
        .windowResizability(.contentMinSize)
    }
}
