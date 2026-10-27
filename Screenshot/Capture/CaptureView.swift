import AppKit
import SwiftUI
import ScreenCaptureKit

/// The full-screen overlay on one display: window highlighting, region selection, and in-place markup.
struct CaptureView: View {
    let screenFrame: CGRect
    let detector: WindowDetector
    let selection: RegionSelection
    let state: CaptureState
    let isScrollingCapture: Bool

    @State private var windowMask: CGImage?
    @State private var markupBridge = MarkupEditorBridge()

    private var highlightedWindow: HighlightedWindow? {
        guard let window = detector.hoveredWindow else { return nil }
        return HighlightedWindow(window: window)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            if !state.isEditing {
                captureInteractionContent()
            }

            if state.isEditing {
                editingContent()
            }
        }
        .ignoresSafeArea()
        .coordinateSpace(name: "captureOverlay")
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            state.markupDocument?.handleDeleteKey() == true ? .handled : .ignored
        }
    }

    private func editingContent() -> some View {
        ZStack(alignment: .top) {
            if let rect = selection.captureRect,
               let current = selection.current {
                RegionSelectionView(
                    rect: rect,
                    current: current,
                    screenFrame: screenFrame,
                    isAdjusting: true
                )
                .opacity(state.windowMask == nil ? 1 : 0)
                if let mask = state.windowMask {
                    WindowEditingSelectionView(
                        frame: rect,
                        screenFrame: screenFrame,
                        mask: mask
                    )
                }
                markupEditor(capturedFrame: rect)
                selectionHandles(for: rect)
            }
        }
    }

    private func markupEditor(capturedFrame: CGRect) -> some View {
        GeometryReader { _ in
            if let document = state.markupDocument {
                let canvasFrame = overlayRect(from: capturedFrame)
                let editorFrame = MarkupEditorLayout.captureEditorFrame(for: canvasFrame)
                let toolbarCenter = MarkupEditorLayout.captureToolbarCenter(for: canvasFrame)

                HStack(spacing: 10) {
                    MarkupToolControls(bridge: markupBridge)
                    Divider()
                        .frame(height: 20)
                    ExtractTextButton(image: state.sourceImage)
                    MarkupExportControls(
                        copy: { export(.copy, document: document) },
                        save: { export(.save, document: document) },
                        share: { export(.share, document: document) }
                    )
                    Button("Done", systemImage: "checkmark") {
                        export(.finish, document: document)
                    }
                    .buttonStyle(.glassProminent)
                    .help("Copy and close")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .menuStyle(.button)
                .controlSize(.large)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .fixedSize()
                .position(toolbarCenter)

                MarkupCanvasView(
                    image: state.sourceImage,
                    pixelatedImage: state.pixelatedImage,
                    document: document,
                    bridge: markupBridge
                )
                .frame(width: editorFrame.width, height: editorFrame.height)
                .mask {
                    if let mask = state.windowMask {
                        Image(decorative: mask, scale: 1).resizable()
                    } else {
                        Rectangle()
                    }
                }
                .position(
                    x: editorFrame.midX,
                    y: editorFrame.midY
                )
            }
        }
    }

    private enum ExportAction {
        case copy
        case save
        case share
        case finish
    }

    private func export(_ action: ExportAction, document: MarkupDocument) {
        guard let rect = selection.captureRect else { return }
        let mask = state.windowMask
        switch action {
        case .copy: CaptureManager.shared.copyCapture(rect: rect, document: document, windowMask: mask)
        case .save: CaptureManager.shared.saveCapture(rect: rect, document: document, windowMask: mask)
        case .share: CaptureManager.shared.shareCapture(rect: rect, document: document, windowMask: mask)
        case .finish: CaptureManager.shared.finishEditing(rect: rect, document: document, windowMask: mask)
        }
    }

    private func selectionHandles(for rect: CGRect) -> some View {
        GeometryReader { _ in
            ForEach(Array(RegionSelection.Handle.allCases.enumerated()), id: \.offset) { _, handle in
                let point = ScreenCoordinates.overlayPoint(
                    fromAppKit: handle.location(in: rect),
                    on: screenFrame
                )
                Circle()
                    .fill(.clear)
                    .contentShape(Circle())
                    .frame(width: 22, height: 22)
                    .position(point)
                    .gesture(selectionGesture)
            }
        }
    }

    private func captureInteractionContent() -> some View {
        ZStack {
            if selection.rect == nil, let window = detector.hoveredWindow {
                WindowHighlightView(
                    frame: ScreenCoordinates.appKitRect(fromScreenCapture: window.frame),
                    screenFrame: screenFrame,
                    mask: windowMask
                )
            }

            if let rect = selection.rect, let current = selection.current {
                RegionSelectionView(
                    rect: rect,
                    current: current,
                    screenFrame: screenFrame,
                    isAdjusting: selection.interaction == nil
                )
            }

            if isScrollingCapture {
                VStack(spacing: 4) {
                    Text("Scrolling Capture")
                        .font(.headline)
                    Text("Click a window or drag a region")
                        .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 24)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .contentShape(.rect)
        .gesture(captureGesture)
        .task(id: highlightedWindow) {
            windowMask = nil
            guard let window = detector.hoveredWindow else { return }
            let windowFrame = ScreenCoordinates.appKitRect(fromScreenCapture: window.frame)
            guard windowFrame.intersects(screenFrame) else { return }
            // The window's own alpha channel gives its real shape, including rounded corners.
            windowMask = try? await ScreenCaptureService.captureWindow(window)
        }
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("captureOverlay"))
            .onChanged { value in
                state.windowMask = nil
                if selection.interaction == nil {
                    selection.begin(at: ScreenCoordinates.appKitPoint(
                        fromOverlay: value.startLocation,
                        on: screenFrame
                    ))
                }
                selection.update(to: ScreenCoordinates.appKitPoint(
                    fromOverlay: value.location,
                    on: screenFrame
                ))
            }
            .onEnded { _ in selection.end() }
    }

    private var captureGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = ScreenCoordinates.appKitPoint(
                    fromOverlay: value.startLocation,
                    on: screenFrame
                )
                if selection.interaction == nil {
                    selection.begin(at: start)
                }
                selection.update(
                    to: ScreenCoordinates.appKitPoint(
                        fromOverlay: value.location,
                        on: screenFrame
                    )
                )
            }
            .onEnded { value in
                let distance = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y
                )
                if isScrollingCapture {
                    if distance < 5, let window = detector.hoveredWindow {
                        selection.reset()
                        ScrollCaptureManager.shared.begin(window: window, windowMask: windowMask)
                        return
                    }
                    let interaction = selection.end()
                    guard interaction == .creating,
                          let rect = selection.captureRect else { return }
                    ScrollCaptureManager.shared.begin(region: rect)
                    return
                }

                let interaction = selection.end()

                if distance < 5,
                   interaction == .creating,
                   let window = detector.hoveredWindow {
                    selection.reset()
                    CaptureManager.shared.finishCapture(
                        window: window,
                        mask: windowMask
                    )
                }
            }
    }
}


extension CaptureView {

    private func overlayRect(from appKitRect: CGRect) -> CGRect {
        ScreenCoordinates.overlayRect(fromAppKit: appKitRect, on: screenFrame)
    }
}

/// The hovered window's identity and frame. `SCWindow` is not `Hashable`, and `.task(id:)` needs
/// a hashable value to restart the mask capture whenever the window or its frame changes.
private struct HighlightedWindow: Hashable {
    let windowID: CGWindowID
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(window: SCWindow) {
        windowID = window.windowID
        x = window.frame.origin.x
        y = window.frame.origin.y
        width = window.frame.width
        height = window.frame.height
    }
}
