import SwiftUI

/// The buttons shown while a scrolling capture is running.
struct ScrollCaptureControlView: View {
    let state: ScrollCaptureControlState

    var body: some View {
        HStack(spacing: 8) {
            if state.showsAutomaticControl {
                Button(state.isAutomaticScrolling ? "Stop Auto" : "Auto") {
                    ScrollCaptureManager.shared.toggleAutomaticScrolling()
                }
                .disabled(!state.canFinish)
            }
            Button("Cancel", role: .cancel) {
                ScrollCaptureManager.shared.cancel()
            }
            Button("Finish", action: finish)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!state.canFinish)
        }
        .controlSize(.large)
        .padding(8)
        .background(.regularMaterial, in: Capsule())
    }

    private func finish() {
        if !ScrollCaptureManager.shared.finish() {
            ScrollCaptureManager.shared.cancel()
        }
    }
}
