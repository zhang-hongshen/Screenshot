import CoreGraphics

/// Positions of the in-place editor and its toolbar around the selected region.
enum MarkupEditorLayout {
    static let floatingToolbarHeight: CGFloat = 44

    static func captureEditorFrame(for canvasFrame: CGRect) -> CGRect {
        canvasFrame
    }

    static func captureToolbarCenter(
        for canvasFrame: CGRect,
        toolbarSize: CGSize,
        availableFrame: CGRect
    ) -> CGPoint {
        let gap: CGFloat = 8
        let halfWidth = toolbarSize.width / 2
        let halfHeight = toolbarSize.height / 2
        let above = canvasFrame.minY - gap - halfHeight
        let below = canvasFrame.maxY + gap + halfHeight
        let preferredY = above - halfHeight >= availableFrame.minY ? above : below

        return CGPoint(
            x: min(max(canvasFrame.midX, availableFrame.minX + halfWidth), availableFrame.maxX - halfWidth),
            y: min(max(preferredY, availableFrame.minY + halfHeight), availableFrame.maxY - halfHeight)
        )
    }
}
