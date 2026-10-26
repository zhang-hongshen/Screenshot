import SwiftUI

/// Dims everything outside the selected region and shows its size and handles.
struct RegionSelectionView: View {
    let rect: CGRect
    let current: CGPoint
    let screenFrame: CGRect
    let isAdjusting: Bool

    var body: some View {
        GeometryReader { geometry in
            Color.black.opacity(0.45)
                .mask {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addRect(overlayRect)
                    }
                    .fill(.black, style: FillStyle(eoFill: true))
                }

            Rectangle()
                .stroke(.white, lineWidth: 2)
                .frame(width: overlayRect.width, height: overlayRect.height)
                .position(x: overlayRect.midX, y: overlayRect.midY)

            if isAdjusting {
                ForEach(Array(RegionSelection.Handle.allCases.enumerated()), id: \.offset) { _, handle in
                    let point = ScreenCoordinates.overlayPoint(
                        fromAppKit: handle.location(in: rect),
                        on: screenFrame
                    )

                    Circle()
                        .fill(.white)
                        .stroke(.black.opacity(0.5), lineWidth: 1)
                        .frame(width: 8, height: 8)
                        .position(point)
                }
            }

            if screenFrame.contains(current) {
                let point = ScreenCoordinates.overlayPoint(
                    fromAppKit: current,
                    on: screenFrame
                )

                Text(dimensionText)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .position(
                        x: min(max(point.x + 60, 60), geometry.size.width - 60),
                        y: min(max(point.y + 24, 24), geometry.size.height - 24)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var dimensionText: String {
        let dimensions = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        return isAdjusting ? "\(dimensions)  ·  Return to capture" : dimensions
    }

    private var overlayRect: CGRect {
        ScreenCoordinates.overlayRect(fromAppKit: rect, on: screenFrame)
    }
}
