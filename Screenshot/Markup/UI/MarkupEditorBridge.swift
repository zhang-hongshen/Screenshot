import AppKit
import Observation
import PaperKit
import SwiftUI

/// Owns the PaperKit markup controller for one editor and the toolbar's choices
/// (tool, pen, colour, width), and applies those choices to PaperKit.
@MainActor
@Observable
final class MarkupEditorBridge: NSObject {
    var tool = MarkupTool.select {
        didSet { applyTool() }
    }
    var ink = MarkupInk.pen {
        didSet { tool = .draw }
    }
    var color = Color.red {
        didSet { applyTool() }
    }
    var lineWidth = MarkupLineWidth.regular {
        didSet { applyTool() }
    }

    @ObservationIgnored let markupController: PaperMarkupViewController
    /// PaperKit's insert actions take its toolbar as the sender. Screenshot shows its own
    /// SwiftUI toolbar instead, so this one is never on screen.
    @ObservationIgnored private let paperKitToolbar: MarkupToolbarViewController
    @ObservationIgnored weak var document: MarkupDocument? {
        didSet {
            if document !== oldValue { applyTool() }
        }
    }

    @ObservationIgnored private let zoomRange: ClosedRange<CGFloat> = 0.5...4
    @ObservationIgnored private let zoomStep: CGFloat = 1.2

    override init() {
        let featureSet = FeatureSet.latest
        markupController = PaperMarkupViewController(supportedFeatureSet: featureSet)
        paperKitToolbar = MarkupToolbarViewController(supportedFeatureSet: featureSet)
        super.init()
        markupController.zoomRange = zoomRange
        applyTool()
    }

    // MARK: - Inserting

    func insert(_ shape: ShapeConfiguration.Shape) {
        tool = .select
        markupController.markupToolbarViewController(paperKitToolbar, insertNewShape: shape)
    }

    func insertLine(withArrow hasArrow: Bool) {
        tool = .select
        markupController.markupToolbarViewController(
            paperKitToolbar,
            insertNewLineWithStartMarker: false,
            endMarker: hasArrow
        )
    }

    func insertTextBox() {
        tool = .select
        markupController.markupToolbarViewControllerInsertNewTextbox(paperKitToolbar)
    }

    // MARK: - Zooming

    func zoomIn() {
        zoom(by: zoomStep)
    }

    func zoomOut() {
        zoom(by: 1 / zoomStep)
    }

    private func zoom(by factor: CGFloat) {
        guard let document else { return }
        let currentFrame = markupController.contentVisibleFrame.width > 0
            && markupController.contentVisibleFrame.height > 0
            ? markupController.contentVisibleFrame
            : document.contentVisibleFrame
        let visibleFrame = MarkupContentLayout.zoomedVisibleFrame(
            currentVisibleFrame: currentFrame,
            zoomFactor: factor,
            imageSize: document.imageSize,
            minZoom: zoomRange.lowerBound,
            maxZoom: zoomRange.upperBound
        )
        markupController.setContentVisibleFrame(visibleFrame, animated: true)
        document.contentVisibleFrame = visibleFrame
    }

    // MARK: - Applying the tool

    /// Blur regions are Screenshot's own overlay, so PaperKit stops taking input while Blur is chosen.
    private func applyTool() {
        document?.isRedactionMode = tool == .blur
        markupController.isEditable = tool != .blur
        let drawingTool = ink.tool(color: NSColor(color), width: lineWidth)
        paperKitToolbar.selectedDrawingTool = drawingTool
        switch tool {
        case .select:
            markupController.indirectPointerTouchMode = .selection
        case .draw:
            markupController.drawingTool = drawingTool
            markupController.indirectPointerTouchMode = .drawing
        case .blur:
            break
        }
    }
}
