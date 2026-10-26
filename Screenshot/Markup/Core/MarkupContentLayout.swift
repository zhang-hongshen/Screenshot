import CoreGraphics

/// Where the canvas looks at the image: centered with a margin, and how zooming changes that.
enum MarkupContentLayout {
    static let defaultContentInset: CGFloat = 32

    static func centeredVisibleFrame(
        imageSize: CGSize,
        viewportSize: CGSize,
        contentInset: CGFloat = defaultContentInset
    ) -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        guard imageSize.width > 0,
              imageSize.height > 0,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return imageBounds
        }

        let inset = sanitizedContentInset(contentInset, viewportSize: viewportSize)
        let availableViewportSize = CGSize(
            width: max(1, viewportSize.width - inset * 2),
            height: max(1, viewportSize.height - inset * 2)
        )
        let scale = min(
            availableViewportSize.width / imageSize.width,
            availableViewportSize.height / imageSize.height
        )
        guard scale.isFinite, scale > 0 else { return imageBounds }

        let visibleSize: CGSize
        visibleSize = CGSize(
            width: viewportSize.width / scale,
            height: viewportSize.height / scale
        )

        return CGRect(
            x: (imageSize.width - visibleSize.width) / 2,
            y: (imageSize.height - visibleSize.height) / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )
    }

    static func zoomedVisibleFrame(
        currentVisibleFrame: CGRect,
        zoomFactor: CGFloat,
        imageSize: CGSize,
        minZoom: CGFloat,
        maxZoom: CGFloat
    ) -> CGRect {
        guard currentVisibleFrame.width > 0,
              currentVisibleFrame.height > 0,
              zoomFactor.isFinite,
              zoomFactor > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return currentVisibleFrame
        }

        let currentZoom = min(
            imageSize.width / currentVisibleFrame.width,
            imageSize.height / currentVisibleFrame.height
        )
        guard currentZoom.isFinite, currentZoom > 0 else { return currentVisibleFrame }

        let lowerBound = max(0.0001, minZoom)
        let upperBound = max(lowerBound, maxZoom)
        let targetZoom = min(max(currentZoom * zoomFactor, lowerBound), upperBound)
        let resizeRatio = currentZoom / targetZoom
        let visibleSize = CGSize(
            width: currentVisibleFrame.width * resizeRatio,
            height: currentVisibleFrame.height * resizeRatio
        )

        return CGRect(
            x: currentVisibleFrame.midX - visibleSize.width / 2,
            y: currentVisibleFrame.midY - visibleSize.height / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )
    }

    private static func sanitizedContentInset(_ inset: CGFloat, viewportSize: CGSize) -> CGFloat {
        guard inset.isFinite, inset > 0 else { return 0 }
        let maximumInset = max(0, min(viewportSize.width, viewportSize.height) / 2 - 1)
        return min(inset, maximumInset)
    }
}
