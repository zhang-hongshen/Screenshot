import CoreGraphics

/// Positions of the in-place editor and its toolbar around the selected region.
enum MarkupEditorLayout {
    static let floatingToolbarHeight: CGFloat = 44

    static func redactionOverlayFrame(for contentSize: CGSize) -> CGRect {
        CGRect(origin: .zero, size: contentSize)
    }

    static func captureEditorFrame(for canvasFrame: CGRect) -> CGRect {
        canvasFrame
    }

    static func captureToolbarCenter(
        for canvasFrame: CGRect,
        toolbarHeight: CGFloat = floatingToolbarHeight
    ) -> CGPoint {
        CGPoint(
            x: canvasFrame.midX,
            y: canvasFrame.minY - toolbarHeight / 2
        )
    }
}
