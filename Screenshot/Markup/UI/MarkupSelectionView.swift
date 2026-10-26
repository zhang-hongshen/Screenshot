import SwiftUI

/// Outline around a blur region.
struct MarkupSelectionOutline: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

/// Dashed rectangle shown while a new blur region is being dragged out.
struct MarkupSelectionMarquee: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.08))
            .overlay {
                Rectangle()
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

/// Corner handles of the selected blur region.
struct MarkupResizeHandles: View {
    let rect: CGRect

    var body: some View {
        ForEach(ResizeCorner.allCases, id: \.self) { corner in
            Circle()
                .fill(.background)
                .stroke(Color.accentColor, lineWidth: 1.5)
                .frame(width: 9, height: 9)
                .position(corner.point(in: rect))
                .allowsHitTesting(false)
        }
    }
}

/// A corner of a rectangle that can be dragged to resize it.
enum ResizeCorner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    func oppositePoint(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: CGPoint(x: rect.minX, y: rect.minY)
        }
    }
}
