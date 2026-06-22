import AppKit
import SwiftUI

struct AnnotationEditorView: View {
    let image: NSImage
    let pixelatedImage: NSImage
    let commandState: AnnotationEditorCommandState
    let copy: ([Annotation]) -> Void
    let finish: ([Annotation]) -> Void

    @State private var editing = AnnotationEditingSession()
    @State private var selectionDrag: SelectionDrag?
    @State private var zoomScale: CGFloat = 1
    @State private var viewportSize: CGSize = .zero
    @State private var fittedCanvasSize: CGSize = .zero
    @State private var scrollPosition = ScrollPosition()

    private let canvasMargin: CGFloat = 28
    private let zoomLevels: [CGFloat] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    var body: some View {
        @Bindable var editing = editing

        return VStack(spacing: 0) {
            GeometryReader { proxy in
                let availableSize = CGSize(
                    width: max(0, proxy.size.width - canvasMargin * 2),
                    height: max(0, proxy.size.height - canvasMargin * 2)
                )
                let fittedSize = aspectFitSize(in: availableSize)
                let canvasSize = CGSize(
                    width: fittedSize.width * zoomScale,
                    height: fittedSize.height * zoomScale
                )
                ScrollView([.horizontal, .vertical]) {
                    AnnotationCanvas(
                        image: image,
                        pixelatedImage: pixelatedImage,
                        annotations: editing.allAnnotations,
                        selectedAnnotationIDs: editing.selectedAnnotationIDs,
                        selectionRect: editing.selectionRect
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .shadow(color: .black.opacity(0.24), radius: 16, y: 6)
                    .contentShape(Rectangle())
                    .gesture(annotationGesture(displaySize: canvasSize))
                    .overlay(alignment: .topLeading) {
                        if let textPosition = editing.textPosition {
                            let scale = canvasSize.width / max(1, image.size.width)
                            TextAnnotationInputView(
                                text: $editing.textDraft,
                                position: CGPoint(
                                    x: textPosition.x * scale,
                                    y: textPosition.y * scale
                                ),
                                fontSize: editing.fontSize * scale,
                                fontFamily: editing.fontFamily,
                                fontWeight: editing.fontWeight,
                                color: editing.color,
                                commit: editing.addText,
                                cancel: editing.cancelText
                            )
                        }
                    }
                    .padding(canvasMargin)
                    .frame(
                        minWidth: proxy.size.width,
                        minHeight: proxy.size.height,
                        alignment: .center
                    )
                }
                .scrollPosition($scrollPosition)
                .defaultScrollAnchor(.center)
                .onGeometryChange(for: CGSize.self) { geometry in
                    geometry.size
                } action: { size in
                    viewportSize = size
                    fittedCanvasSize = aspectFitSize(in: CGSize(
                        width: max(0, size.width - canvasMargin * 2),
                        height: max(0, size.height - canvasMargin * 2)
                    ))
                }
            }
        }
        .toolbar{
            AnnotationToolbar(
                selectedTool: $editing.selectedTool,
                selectedShape: $editing.selectedShape,
                color: $editing.color,
                lineWidth: $editing.lineWidth,
                fontFamily: $editing.fontFamily,
                fontSize: $editing.fontSize,
                fontWeight: $editing.fontWeight,
                canUndo: editing.document.canUndo,
                canRedo: editing.document.canRedo,
                undo: editing.undo,
                redo: editing.redo,
                zoomControls: AnnotationZoomControls(
                    scale: zoomScale,
                    canZoomOut: zoomScale > zoomLevels[0],
                    canZoomIn: zoomScale < zoomLevels[zoomLevels.count - 1],
                    zoomOut: zoomOut,
                    zoomIn: zoomIn
                ),
                copy: { copy(editing.document.annotations) },
                finish: { finish(editing.document.annotations) }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDeleteCommand { _ = editing.deleteSelection() }
        .onAppear(perform: installSelectAllHandler)
        .onDisappear { commandState.selectAllAnnotations = nil }
        .onChange(of: editing.color) { _, value in editing.updateSelectedColor(value) }
        .onChange(of: editing.lineWidth) { _, value in editing.updateSelectedLineWidth(value) }
        .onChange(of: editing.selectedShape) { _, value in editing.updateSelectedShape(value) }
        .onChange(of: editing.fontFamily) { _, value in editing.updateSelectedFontFamily(value) }
        .onChange(of: editing.fontSize) { _, value in editing.updateSelectedFontSize(value) }
        .onChange(of: editing.fontWeight) { _, value in editing.updateSelectedFontWeight(value) }
    }

    private func aspectFitSize(in available: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return available }
        let scale = min(
            available.width / image.size.width,
            available.height / image.size.height
        )
        return CGSize(
            width: image.size.width * max(0, scale),
            height: image.size.height * max(0, scale)
        )
    }

    private func imagePoint(_ point: CGPoint, displaySize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x * image.size.width / max(1, displaySize.width)), image.size.width),
            y: min(max(0, point.y * image.size.height / max(1, displaySize.height)), image.size.height)
        )
    }

    private func zoomOut() {
        guard let level = zoomLevels.last(where: { $0 < zoomScale }) else { return }
        setZoom(level)
    }

    private func zoomIn() {
        guard let level = zoomLevels.first(where: { $0 > zoomScale }) else { return }
        setZoom(level)
    }

    private func setZoom(_ newScale: CGFloat) {
        guard viewportSize.width > 0, viewportSize.height > 0,
              fittedCanvasSize.width > 0, fittedCanvasSize.height > 0 else {
            zoomScale = newScale
            return
        }

        let oldCanvasSize = scaledCanvasSize(for: zoomScale)
        let oldContentSize = contentSize(for: oldCanvasSize)
        let oldOrigin = canvasOrigin(canvasSize: oldCanvasSize, contentSize: oldContentSize)
        let oldOffset = scrollPosition.point ?? CGPoint(
            x: max(0, (oldContentSize.width - viewportSize.width) / 2),
            y: max(0, (oldContentSize.height - viewportSize.height) / 2)
        )
        let visibleCenter = CGPoint(
            x: oldOffset.x + viewportSize.width / 2,
            y: oldOffset.y + viewportSize.height / 2
        )
        let normalizedCenter = CGPoint(
            x: min(max(0, (visibleCenter.x - oldOrigin.x) / oldCanvasSize.width), 1),
            y: min(max(0, (visibleCenter.y - oldOrigin.y) / oldCanvasSize.height), 1)
        )

        zoomScale = newScale

        let newCanvasSize = scaledCanvasSize(for: newScale)
        let newContentSize = contentSize(for: newCanvasSize)
        let newOrigin = canvasOrigin(canvasSize: newCanvasSize, contentSize: newContentSize)
        let targetOffset = CGPoint(
            x: min(
                max(0, newOrigin.x + normalizedCenter.x * newCanvasSize.width - viewportSize.width / 2),
                max(0, newContentSize.width - viewportSize.width)
            ),
            y: min(
                max(0, newOrigin.y + normalizedCenter.y * newCanvasSize.height - viewportSize.height / 2),
                max(0, newContentSize.height - viewportSize.height)
            )
        )

        Task { @MainActor in
            await Task.yield()
            scrollPosition.scrollTo(point: targetOffset)
        }
    }

    private func scaledCanvasSize(for scale: CGFloat) -> CGSize {
        CGSize(width: fittedCanvasSize.width * scale, height: fittedCanvasSize.height * scale)
    }

    private func contentSize(for canvasSize: CGSize) -> CGSize {
        CGSize(
            width: max(viewportSize.width, canvasSize.width + canvasMargin * 2),
            height: max(viewportSize.height, canvasSize.height + canvasMargin * 2)
        )
    }

    private func canvasOrigin(canvasSize: CGSize, contentSize: CGSize) -> CGPoint {
        CGPoint(
            x: (contentSize.width - canvasSize.width) / 2,
            y: (contentSize.height - canvasSize.height) / 2
        )
    }

    private func annotationGesture(displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = imagePoint(value.startLocation, displaySize: displaySize)
                let current = imagePoint(value.location, displaySize: displaySize)
                let rect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
                switch editing.selectedTool {
                case .select:
                    updateSelectionDrag(
                        start: start,
                        current: current,
                        displaySize: displaySize,
                        marqueeRect: rect,
                        dragDistance: hypot(value.translation.width, value.translation.height)
                    )
                case .shape:
                    editing.draft = .shape(ShapeAnnotation(
                        type: editing.selectedShape,
                        rect: rect,
                        startPoint: start,
                        endPoint: current,
                        lineWidth: editing.lineWidth,
                        color: editing.color
                    ))
                case .blur:
                    editing.draft = .blur(BlurAnnotation(rect: rect))
                case .text:
                    break
                }
            }
            .onEnded { value in
                let end = imagePoint(value.location, displaySize: displaySize)
                let dragDistance = hypot(value.translation.width, value.translation.height)
                if editing.selectedTool == .select {
                    if let selectionDrag {
                        if dragDistance >= 3 {
                            editing.document.commitPreview(from: selectionDrag.originalAnnotations)
                        } else {
                            editing.document.preview(selectionDrag.originalAnnotations)
                        }
                        self.selectionDrag = nil
                    } else if let selectionRect = editing.selectionRect, dragDistance >= 3 {
                        editing.selectedAnnotationIDs = Set(editing.document.annotations.compactMap {
                            $0.selectionBounds.intersects(selectionRect)
                                ? $0.id
                                : nil
                        })
                    } else {
                        editing.selectedAnnotationIDs = annotation(at: end).map { Set([$0.id]) } ?? []
                    }
                    editing.selectionRect = nil
                } else if editing.selectedTool == .text, dragDistance < 8 {
                    editing.textPosition = end
                    editing.textDraft = ""
                } else if let draft = editing.draft, dragDistance >= 3 {
                    editing.document.add(draft)
                }
                editing.draft = nil
            }
    }

    private func installSelectAllHandler() {
        commandState.selectAllAnnotations = editing.selectAllAnnotations
    }

    private func updateSelectionDrag(
        start: CGPoint,
        current: CGPoint,
        displaySize: CGSize,
        marqueeRect: CGRect,
        dragDistance: CGFloat
    ) {
        guard dragDistance >= 3 else { return }

        if selectionDrag == nil {
            let handleTolerance = 12 * image.size.width / max(1, displaySize.width)
            let selectedBounds = selectionBounds(for: editing.selectedAnnotationIDs)
            let corner = selectedBounds.flatMap { bounds in
                ResizeCorner.allCases.first {
                    hypot($0.point(in: bounds).x - start.x, $0.point(in: bounds).y - start.y)
                        <= handleTolerance
                }
            }

            if let selectedBounds, let corner {
                selectionDrag = SelectionDrag(
                    mode: .resize(corner, selectedBounds),
                    annotationIDs: editing.selectedAnnotationIDs,
                    originalAnnotations: editing.document.annotations
                )
            } else if let hit = annotation(at: start) {
                let ids = editing.selectedAnnotationIDs.contains(hit.id)
                    ? editing.selectedAnnotationIDs
                    : Set([hit.id])
                editing.selectedAnnotationIDs = ids
                selectionDrag = SelectionDrag(
                    mode: .move,
                    annotationIDs: ids,
                    originalAnnotations: editing.document.annotations
                )
            } else {
                editing.selectionRect = marqueeRect
                return
            }
        }

        guard let selectionDrag else { return }
        let updated = selectionDrag.originalAnnotations.map { annotation in
            guard selectionDrag.annotationIDs.contains(annotation.id) else { return annotation }
            switch selectionDrag.mode {
            case .move:
                return annotation.translated(by: CGSize(
                    width: current.x - start.x,
                    height: current.y - start.y
                ))
            case .resize(let corner, let originalBounds):
                let anchor = corner.oppositePoint(in: originalBounds)
                let destination = CGRect(
                    x: min(anchor.x, current.x),
                    y: min(anchor.y, current.y),
                    width: max(4, abs(current.x - anchor.x)),
                    height: max(4, abs(current.y - anchor.y))
                )
                return annotation.resized(from: originalBounds, to: destination)
            }
        }
        editing.document.preview(updated)
    }

    private func annotation(at point: CGPoint) -> Annotation? {
        editing.document.annotations.last { $0.selectionBounds.contains(point) }
    }

    private func selectionBounds(for ids: Set<UUID>) -> CGRect? {
        let bounds = editing.document.annotations
            .filter { ids.contains($0.id) }
            .map(\.selectionBounds)
        guard let first = bounds.first else { return nil }
        return bounds.dropFirst().reduce(first) { $0.union($1) }
    }

}

private struct SelectionDrag {
    enum Mode {
        case move
        case resize(ResizeCorner, CGRect)
    }

    let mode: Mode
    let annotationIDs: Set<UUID>
    let originalAnnotations: [Annotation]
}

struct AnnotationCanvas: View {
    let image: NSImage
    let pixelatedImage: NSImage
    let annotations: [Annotation]
    let selectedAnnotationIDs: Set<UUID>
    let selectionRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / image.size.width
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: proxy.size.width, height: proxy.size.height)
                ForEach(annotations) { annotation in
                    switch annotation {
                    case .shape(let value): ShapeAnnotationView(shape: value.scaled(by: scale))
                    case .text(let value): TextAnnotationView(text: value.scaled(by: scale))
                    case .blur(let value): BlurAnnotationView(
                        blur: value.scaled(by: scale),
                        pixelatedImage: pixelatedImage,
                        canvasSize: proxy.size
                    )
                    }
                }
                ForEach(annotations.filter { selectedAnnotationIDs.contains($0.id) }) { annotation in
                    AnnotationSelectionOutline(
                        rect: scaled(annotation.selectionBounds, by: scale)
                    )
                }
                if let selectedBounds {
                    AnnotationResizeHandles(rect: scaled(selectedBounds, by: scale))
                }
                if let selectionRect {
                    AnnotationSelectionMarquee(
                        rect: scaled(selectionRect, by: scale)
                    )
                }
            }
            .clipped()
        }
    }

    private var selectedBounds: CGRect? {
        let bounds = annotations
            .filter { selectedAnnotationIDs.contains($0.id) }
            .map(\.selectionBounds)
        guard let first = bounds.first else { return nil }
        return bounds.dropFirst().reduce(first) { $0.union($1) }
    }

    private func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

}
