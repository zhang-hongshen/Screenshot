import AppKit
import PencilKit

/// What a drag on the canvas does.
enum MarkupTool: Hashable {
    case select
    case draw
    case blur
}

/// The pens offered in the toolbar.
enum MarkupInk: CaseIterable, Hashable {
    case pen
    case marker
    case pencil
    case eraser

    var title: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Highlighter"
        case .pencil: "Pencil"
        case .eraser: "Eraser"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .pencil: "pencil"
        case .eraser: "eraser"
        }
    }

    func tool(color: NSColor, width: MarkupLineWidth) -> PKTool {
        let inkType: PKInkingTool.InkType
        switch self {
        case .pen: inkType = .pen
        case .marker: inkType = .marker
        case .pencil: inkType = .pencil
        case .eraser: return PKEraserTool(.vector)
        }
        let range = inkType.validWidthRange
        let lineWidth = min(max(inkType.defaultWidth * width.factor, range.lowerBound), range.upperBound)
        return PKInkingTool(inkType, color: color, width: lineWidth)
    }
}

/// Stroke widths offered in the toolbar, relative to each pen's natural width.
enum MarkupLineWidth: CaseIterable, Hashable {
    case thin
    case regular
    case thick

    var title: String {
        switch self {
        case .thin: "Thin"
        case .regular: "Regular"
        case .thick: "Thick"
        }
    }

    var factor: CGFloat {
        switch self {
        case .thin: 0.5
        case .regular: 1
        case .thick: 2.5
        }
    }
}
