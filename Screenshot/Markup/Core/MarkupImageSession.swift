import AppKit
import Foundation
import Observation
import os

/// Applies both raster brushes continuously and groups each drag into one undo step.
@MainActor
@Observable
final class MarkupImageSession {
    var brushSize = MarkupBrushSize.medium
    var brushDiameter: CGFloat { brushSize.diameter }
    private(set) var sourceImage: NSImage?
    private(set) var acceptedImage: NSImage?
    private(set) var isProcessing = false
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeStrokeID: UUID?
    @ObservationIgnored private var pending: [MarkupBrushWork] = []
    @ObservationIgnored private var cachedPatches: [TextErasurePatch] = []
    @ObservationIgnored private var repairSource: CGImage?
    @ObservationIgnored private var currentPixels: CGImage?
    private static let logger = Logger(subsystem: "com.zhanghongshen.Screenshot", category: "Brush")
    @ObservationIgnored private let undoManager = UndoManager()
    @ObservationIgnored private var mosaicSource: CGImage?
    @ObservationIgnored private var cachedMosaic: CGImage?
    @ObservationIgnored private var cachedMosaicBlockSize: CGFloat?

    init() {
        undoManager.groupsByEvent = false
    }

    var hasPendingChanges: Bool { isProcessing }
    var currentImage: NSImage? { acceptedImage ?? sourceImage }

    func setSourceIfNeeded(_ image: NSImage) {
        if sourceImage == nil { sourceImage = image }
    }

    func beginStroke(tool: MarkupTool = .eraseText) {
        guard sourceImage != nil, activeStrokeID == nil else { return }
        let work = MarkupBrushWork(tool: tool)
        pending.append(work)
        activeStrokeID = work.id
        isProcessing = true
    }

    func append(_ stroke: MarkupBrushStroke) {
        guard !stroke.points.isEmpty,
              let index = pending.firstIndex(where: { $0.id == activeStrokeID }) else { return }
        pending[index].strokes.append(stroke)
        startProcessing()
    }

    func endStroke() {
        guard let index = pending.firstIndex(where: { $0.id == activeStrokeID }) else { return }
        pending[index].hasEnded = true
        activeStrokeID = nil
        startProcessing()
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        if let work = pending.first, work.hasChanges {
            recordStrokeUndo(
                previous: work.previousImage, tool: work.tool, mosaicSource: work.previousMosaicSource
            )
        }
        pending.removeAll()
        activeStrokeID = nil
        isProcessing = false
    }

    func apply(_ image: NSImage) {
        acceptedImage = image
        currentPixels = nil
    }

    func recordStrokeUndo(previous: NSImage?, tool: MarkupTool = .eraseText, mosaicSource: CGImage? = nil) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in target.restore(previous, mosaicSource: mosaicSource) }
        undoManager.setActionName(String(localized: tool == .blur ? "Mosaic" : "Erase Text"))
        undoManager.endUndoGrouping()
        updateHistory()
    }

    func undo() {
        guard !hasPendingChanges else { return }
        undoManager.undo()
        updateHistory()
    }

    func redo() {
        guard !hasPendingChanges else { return }
        undoManager.redo()
        updateHistory()
    }

    private func startProcessing() {
        guard task == nil else { return }
        let token = generation
        task = Task { [weak self] in
            await self?.processPending(token: token)
        }
    }

    private func processPending(token: UUID) async {
        do {
            while !pending.isEmpty {
                try Task.checkCancellation()
                if !pending[0].hasStarted {
                    pending[0].previousImage = acceptedImage
                    pending[0].previousMosaicSource = mosaicSource
                    pending[0].hasStarted = true
                    guard let image = currentImage else { throw CocoaError(.coderInvalidValue) }
                    let pixels = try pixelsForCurrentImage()
                    if pending[0].tool == .blur {
                        let source = mosaicSource ?? pixels
                        mosaicSource = source
                        let radius = pending[0].strokes.first?.radius ?? brushDiameter / 2
                        let pixelScale = CGFloat(pixels.width) / max(1, image.size.width)
                        let blockSize = max(1, (radius * pixelScale / 2).rounded())
                        if cachedMosaic == nil || cachedMosaicBlockSize != blockSize {
                            let mosaic = try await MosaicRenderer.pixelatedImage(source, blockSize: blockSize)
                            try Task.checkCancellation()
                            guard generation == token else { return }
                            cachedMosaic = mosaic
                            cachedMosaicBlockSize = blockSize
                        }
                        pending[0].mosaic = cachedMosaic
                        repairSource = nil
                        cachedPatches.removeAll()
                    } else {
                        mosaicSource = nil
                        cachedMosaic = nil
                        cachedMosaicBlockSize = nil
                        if repairSource == nil { repairSource = pixels }
                    }
                }
                if pending[0].strokes.isEmpty {
                    if pending[0].hasEnded {
                        let completed = pending.removeFirst()
                        if completed.hasChanges {
                            recordStrokeUndo(
                                previous: completed.previousImage,
                                tool: completed.tool,
                                mosaicSource: completed.previousMosaicSource
                            )
                        }
                        continue
                    }
                    task = nil
                    return
                }
                let strokes = pending[0].strokes
                pending[0].strokes.removeAll(keepingCapacity: true)
                guard let image = currentImage else { throw CocoaError(.coderInvalidValue) }
                let pixels = try pixelsForCurrentImage()
                let scale = CGSize(
                    width: CGFloat(pixels.width) / image.size.width,
                    height: CGFloat(pixels.height) / image.size.height
                )
                let scaledStrokes = strokes.map { $0.scaled(by: scale) }
                let result: CGImage?
                if let mosaic = pending[0].mosaic {
                    result = try await MosaicRenderer.apply(mosaic, along: scaledStrokes, to: pixels)
                } else if let repairSource {
                    let imageSize = image.size
                    let strokeID = pending[0].id
                    let update = try await TextEraser.erase(
                        in: pixels, source: repairSource, strokes: scaledStrokes, cachedPatches: cachedPatches
                    ) { [weak self] result in
                        await self?.applyProgress(result, imageSize: imageSize, strokeID: strokeID, token: token)
                    }
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    cachedPatches = update.cachedPatches
                    result = update.image
                } else {
                    throw CocoaError(.coderInvalidValue)
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                if let result, currentPixels !== result {
                    apply(NSImage(cgImage: result, size: image.size))
                    currentPixels = result
                    pending[0].hasChanges = true
                }
                // Keep accepting samples and give SwiftUI a turn to display each batch.
                try await Task.sleep(for: .milliseconds(16))
            }
            isProcessing = false
            task = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == token else { return }
            cancel()
            Self.logger.error("Brush edit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyProgress(_ pixels: CGImage, imageSize: CGSize, strokeID: UUID, token: UUID) {
        guard generation == token, pending.first?.id == strokeID else { return }
        apply(NSImage(cgImage: pixels, size: imageSize))
        currentPixels = pixels
        pending[0].hasChanges = true
    }

    private func pixelsForCurrentImage() throws -> CGImage {
        if let currentPixels { return currentPixels }
        guard let image = currentImage else { throw CocoaError(.coderInvalidValue) }
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.coderInvalidValue)
        }
        currentPixels = pixels
        return pixels
    }

    private func restore(_ image: NSImage?, mosaicSource: CGImage?) {
        let previous = acceptedImage
        let previousMosaicSource = self.mosaicSource
        undoManager.registerUndo(withTarget: self) { target in
            target.restore(previous, mosaicSource: previousMosaicSource)
        }
        acceptedImage = image
        currentPixels = nil
        repairSource = nil
        cachedPatches.removeAll()
        self.mosaicSource = mosaicSource
        cachedMosaic = nil
        cachedMosaicBlockSize = nil
    }

    private func updateHistory() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}

/// Samples and source pixels for one drag, including samples arriving during image processing.
private struct MarkupBrushWork {
    let id = UUID()
    let tool: MarkupTool
    var strokes: [MarkupBrushStroke] = []
    var previousImage: NSImage?
    var previousMosaicSource: CGImage?
    var mosaic: CGImage?
    var hasStarted = false
    var hasEnded = false
    var hasChanges = false
}
