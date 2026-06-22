import AppKit
import SwiftUI
import ScreenCaptureKit

struct CaptureOverlayView: View {
    let screenFrame: CGRect
    let detector: WindowDetector
    let selection: RegionSelection
    let state: CaptureOverlayState
    let isScrollingCapture: Bool

    @State private var windowMask: CGImage?
    @State private var selectedTool: AnnotationTool = .select
    @State private var selectedShape: ShapeType = .rectangle
    @State private var document = AnnotationDocument()
    @State private var draft: Annotation?
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var fontFamily = "Helvetica"
    @State private var fontSize: CGFloat = 24
    @State private var fontWeight: Font.Weight = .regular
    @State private var textDraft = ""
    @State private var textPosition: CGPoint?
    @State private var selectedAnnotationIDs: Set<UUID> = []
    @State private var annotationSelectionRect: CGRect?

    var body: some View {
        captureContent
            .onDeleteCommand { _ = deleteSelection() }
            .onAppear(perform: installKeyboardHandlers)
            .onDisappear {
                state.deleteSelection = nil
                state.selectAllAnnotations = nil
            }
    }

    private var captureContent: some View {
        ZStack(alignment: .top) {
            Color.clear

            if !state.isEditing {
                captureInteractionContent
            }

            if state.isEditing {
                editingContent
            }
        }
        .ignoresSafeArea()
        .coordinateSpace(name: "captureOverlay")
    }

    private var allAnnotations: [Annotation] {
        document.annotations + (draft.map { [$0] } ?? [])
    }

    private var editingContent: some View {
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
                annotationCanvas(capturedFrame: rect)
                selectionHandles(for: rect)
                annotationToolbar(capturedFrame: rect)
            }
        }
    }

    private func annotationCanvas(capturedFrame: CGRect) -> some View {
        GeometryReader { _ in
            let canvasFrame = overlayRect(from: capturedFrame)
            LiveAnnotationCanvas(
                pixelatedImage: state.pixelatedImage,
                annotations: allAnnotations,
                selectedAnnotationIDs: selectedAnnotationIDs,
                selectionRect: annotationSelectionRect
            )
            .frame(width: canvasFrame.width, height: canvasFrame.height)
            .mask {
                if let mask = state.windowMask {
                    Image(decorative: mask, scale: 1).resizable()
                } else {
                    Rectangle()
                }
            }
            .contentShape(Rectangle())
            .gesture(annotationGesture(canvasSize: canvasFrame.size))
            .overlay(alignment: .topLeading) {
                if let textPosition {
                    TextAnnotationInputView(
                        text: $textDraft,
                        position: textPosition,
                        fontSize: fontSize,
                        fontFamily: fontFamily,
                        fontWeight: fontWeight,
                        color: color,
                        commit: addText,
                        cancel: cancelText
                    )
                }
            }
            .position(x: canvasFrame.midX, y: canvasFrame.midY)
        }
    }

    private func annotationToolbar(capturedFrame: CGRect) -> some View {
        GeometryReader { proxy in
            let canvasFrame = overlayRect(from: capturedFrame)
            AnnotationToolbar(
                selectedTool: $selectedTool,
                selectedShape: $selectedShape,
                color: $color,
                lineWidth: $lineWidth,
                fontFamily: $fontFamily,
                fontSize: $fontSize,
                fontWeight: $fontWeight,
                canUndo: document.canUndo,
                canRedo: document.canRedo,
                undo: document.undo,
                redo: document.redo,
                zoomControls: nil,
                copy: {
                    guard let rect = selection.captureRect else { return }
                    CaptureManager.shared.copyCapture(
                        rect: rect,
                        annotations: document.annotations,
                        windowMask: state.windowMask
                    )
                },
                finish: {
                    guard let rect = selection.captureRect else { return }
                    CaptureManager.shared.finishEditing(
                        rect: rect,
                        annotations: document.annotations,
                        windowMask: state.windowMask
                    )
                }
            )
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 8, y: 3)
            .fixedSize()
            .position(toolbarPosition(for: canvasFrame, in: proxy.size))
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

    private func overlayRect(from appKitRect: CGRect) -> CGRect {
        CGRect(
            x: appKitRect.minX - screenFrame.minX,
            y: screenFrame.maxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private func toolbarPosition(for canvasFrame: CGRect, in available: CGSize) -> CGPoint {
        let horizontalMargin: CGFloat = 24
        let verticalMargin: CGFloat = 32
        let x = min(
            max(canvasFrame.midX, horizontalMargin),
            max(horizontalMargin, available.width - horizontalMargin)
        )
        let above = canvasFrame.minY - verticalMargin
        let below = canvasFrame.maxY + verticalMargin
        let y = above >= verticalMargin
            ? above
            : min(below, max(verticalMargin, available.height - verticalMargin))
        return CGPoint(x: x, y: y)
    }

    private func annotationPoint(_ point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), canvasSize.width),
            y: min(max(0, point.y), canvasSize.height)
        )
    }

    private func annotationGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = annotationPoint(value.startLocation, canvasSize: canvasSize)
                let current = annotationPoint(value.location, canvasSize: canvasSize)
                let rect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
                switch selectedTool {
                case .select:
                    annotationSelectionRect = rect
                case .shape:
                    draft = .shape(ShapeAnnotation(
                        type: selectedShape,
                        rect: rect,
                        startPoint: start,
                        endPoint: current,
                        lineWidth: lineWidth,
                        color: color
                    ))
                case .blur:
                    draft = .blur(BlurAnnotation(rect: rect))
                case .text:
                    break
                }
            }
            .onEnded { value in
                let end = annotationPoint(value.location, canvasSize: canvasSize)
                let dragDistance = hypot(value.translation.width, value.translation.height)
                if selectedTool == .select {
                    if let annotationSelectionRect, dragDistance >= 3 {
                        selectedAnnotationIDs = Set(document.annotations.compactMap {
                            $0.selectionBounds.intersects(annotationSelectionRect)
                                ? $0.id
                                : nil
                        })
                    } else {
                        selectedAnnotationIDs.removeAll()
                    }
                    annotationSelectionRect = nil
                } else if selectedTool == .text, dragDistance < 8 {
                    textPosition = end
                    textDraft = ""
                } else if let draft, dragDistance >= 3 {
                    document.add(draft)
                }
                draft = nil
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

    private func addText() {
        let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let position = textPosition, !text.isEmpty else {
            textPosition = nil
            return
        }
        document.add(.text(TextAnnotation(
            text: text,
            position: position,
            fontSize: fontSize,
            fontFamily: fontFamily,
            fontWeight: fontWeight,
            color: color
        )))
        textPosition = nil
    }

    private func cancelText() {
        textDraft = ""
        textPosition = nil
    }

    @discardableResult
    private func deleteSelection() -> Bool {
        guard textPosition == nil, !selectedAnnotationIDs.isEmpty else { return false }
        document.remove(ids: selectedAnnotationIDs)
        selectedAnnotationIDs.removeAll()
        return true
    }

    private func installKeyboardHandlers() {
        let selectedIDs = $selectedAnnotationIDs
        let activeTool = $selectedTool
        let activeTextPosition = $textPosition
        let document = document

        state.deleteSelection = {
            let ids = selectedIDs.wrappedValue
            guard activeTextPosition.wrappedValue == nil, !ids.isEmpty else { return false }
            document.remove(ids: ids)
            selectedIDs.wrappedValue.removeAll()
            return true
        }

        state.selectAllAnnotations = {
            guard activeTool.wrappedValue == .select,
                  activeTextPosition.wrappedValue == nil,
                  !document.annotations.isEmpty else { return false }
            selectedIDs.wrappedValue = Set(document.annotations.map(\.id))
            return true
        }
    }

    private var captureInteractionContent: some View {
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
                    Text("Select a scrollable window")
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
        .task(id: highlightedWindowID) {
            windowMask = nil
            guard let window = detector.hoveredWindow else { return }
            let windowFrame = ScreenCoordinates.appKitRect(fromScreenCapture: window.frame)
            guard windowFrame.intersects(screenFrame) else { return }
            if isScrollingCapture {
                windowMask = try? await ScrollCaptureManager.shared.captureHighlightMask(for: window)
            } else {
                windowMask = try? await CaptureManager.shared.captureHighlightMask(for: window)
            }
        }
    }

    private var highlightedWindowID: HighlightedWindowID? {
        guard let window = detector.hoveredWindow else { return nil }
        return HighlightedWindowID(window: window)
    }

    private var captureGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isScrollingCapture else { return }
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
                    guard distance < 5, let window = detector.hoveredWindow else { return }
                    ScrollCaptureManager.shared.begin(window: window, windowMask: windowMask)
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

private struct LiveAnnotationCanvas: View {
    let pixelatedImage: NSImage?
    let annotations: [Annotation]
    let selectedAnnotationIDs: Set<UUID>
    let selectionRect: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(annotations) { annotation in
                switch annotation {
                case .shape(let value):
                    ShapeAnnotationView(shape: value)
                case .text(let value):
                    TextAnnotationView(text: value)
                case .blur(let value):
                    if let pixelatedImage {
                        Image(nsImage: pixelatedImage)
                            .resizable()
                            .interpolation(.none)
                            .mask(alignment: .topLeading) {
                                Rectangle()
                                    .frame(
                                        width: value.rect.width,
                                        height: value.rect.height
                                    )
                                    .offset(
                                        x: value.rect.minX,
                                        y: value.rect.minY
                                    )
                            }
                    }
                }
            }
            ForEach(annotations.filter { selectedAnnotationIDs.contains($0.id) }) { annotation in
                AnnotationSelectionOutline(rect: annotation.selectionBounds)
            }
            if let selectionRect {
                AnnotationSelectionMarquee(rect: selectionRect)
            }
        }
        .clipped()
    }
}

private struct HighlightedWindowID: Hashable {
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
