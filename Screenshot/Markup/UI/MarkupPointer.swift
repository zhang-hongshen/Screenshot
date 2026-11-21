import AppKit
import SwiftUI

/// Uses AppKit window tracking to replace the pointer across native and SwiftUI editor controls.
struct MarkupPointer: NSViewRepresentable {
    let tool: MarkupTool?
    let diameter: CGFloat

    func makeNSView(context: Context) -> MarkupPointerView {
        MarkupPointerView()
    }

    func updateNSView(_ view: MarkupPointerView, context: Context) {
        view.update(tool: tool, diameter: diameter)
    }

    static func dismantleNSView(_ view: MarkupPointerView, coordinator: ()) {
        view.disconnect()
    }
}

/// Tracks the editor's AppKit frame because canvas-only pointer styles do not cover native toolbar controls.
final class MarkupPointerView: NSView {
    private var tool: MarkupTool?
    private var isEnabled: Bool { tool == .blur || tool == .eraseText }
    private var diameter: CGFloat?
    private var toolCursor: NSCursor?
    private var trackingArea: NSTrackingArea?
    private weak var trackingView: NSView?
    private weak var cursorWindow: NSWindow?
    private var isShowingCursor = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if cursorWindow !== window { stopTracking() }
        startTrackingIfNeeded()
        showCursor()
    }

    func update(tool: MarkupTool?, diameter: CGFloat) {
        guard self.tool != tool || self.diameter != diameter || cursorWindow !== window else { return }
        if self.tool != tool || self.diameter != diameter {
            self.diameter = diameter
            toolCursor = nil
        }
        self.tool = tool
        if isEnabled {
            if toolCursor == nil, let tool {
                toolCursor = MarkupToolCursor.cursor(tool: tool, diameter: diameter)
            }
            startTrackingIfNeeded()
            if let window, window.frame.contains(NSEvent.mouseLocation) {
                showCursor()
            }
        } else {
            stopTracking()
        }
    }

    func disconnect() {
        tool = nil
        stopTracking()
    }

    override func mouseEntered(with event: NSEvent) { showCursor() }
    override func cursorUpdate(with event: NSEvent) {
        if isEnabled { showCursor() } else { super.cursorUpdate(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if cursorWindow?.frame.contains(NSEvent.mouseLocation) != true {
            isShowingCursor = false
        }
    }

    private func startTrackingIfNeeded() {
        guard isEnabled, cursorWindow == nil, let window,
              let frameView = window.contentView?.superview else { return }
        if toolCursor == nil, let tool, let diameter {
            toolCursor = MarkupToolCursor.cursor(tool: tool, diameter: diameter)
        }
        guard toolCursor != nil else { return }
        cursorWindow = window
        trackingView = frameView
        window.disableCursorRects()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate,
                      .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self
        )
        frameView.addTrackingArea(area)
        trackingArea = area
    }

    private func stopTracking() {
        if let trackingArea { trackingView?.removeTrackingArea(trackingArea) }
        trackingArea = nil
        restoreCursor()
        if let cursorWindow {
            cursorWindow.enableCursorRects()
            if let contentView = cursorWindow.contentView {
                cursorWindow.invalidateCursorRects(for: contentView)
            }
        }
        cursorWindow = nil
        trackingView = nil
    }

    private func showCursor() {
        guard isEnabled, let cursorWindow, cursorWindow.isKeyWindow,
              cursorWindow.frame.contains(NSEvent.mouseLocation), let toolCursor else { return }
        toolCursor.set()
        isShowingCursor = true
    }

    private func restoreCursor() {
        guard isShowingCursor else { return }
        NSCursor.arrow.set()
        isShowingCursor = false
    }
}
