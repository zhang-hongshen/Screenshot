import CoreGraphics
import Observation

/// The rectangle the user drags out, moves and resizes, in global AppKit coordinates.
@MainActor
@Observable
final class RegionSelection {
    private(set) var rect: CGRect?
    private(set) var current: CGPoint?
    private(set) var interaction: Interaction?

    private var initialPoint: CGPoint?
    private var initialRect: CGRect?

    var captureRect: CGRect? {
        guard let rect, rect.width >= 2, rect.height >= 2 else { return nil }
        return rect
    }

    func set(rect: CGRect) {
        self.rect = rect
        current = CGPoint(x: rect.maxX, y: rect.minY)
        interaction = nil
        initialPoint = nil
        initialRect = nil
    }

    func begin(at point: CGPoint) {
        current = point
        initialPoint = point
        initialRect = rect

        if let rect, let handle = Handle.nearest(to: point, in: rect) {
            interaction = .resizing(handle)
        } else if let rect, rect.contains(point) {
            interaction = .moving
        } else {
            rect = CGRect(origin: point, size: .zero)
            initialRect = rect
            interaction = .creating
        }
    }

    func update(to point: CGPoint) {
        guard let interaction, let initialPoint, let initialRect else { return }
        current = point

        switch interaction {
        case .creating:
            rect = CGRect(
                x: min(initialPoint.x, point.x),
                y: min(initialPoint.y, point.y),
                width: abs(point.x - initialPoint.x),
                height: abs(point.y - initialPoint.y)
            )
        case .moving:
            rect = initialRect.offsetBy(
                dx: point.x - initialPoint.x,
                dy: point.y - initialPoint.y
            )
        case .resizing(let handle):
            rect = handle.resized(rect: initialRect, to: point)
        }
    }

    @discardableResult
    func end() -> Interaction? {
        let completedInteraction = interaction
        interaction = nil
        initialPoint = nil
        initialRect = nil

        if captureRect == nil {
            reset()
        }
        return completedInteraction
    }

    func reset() {
        rect = nil
        current = nil
        interaction = nil
        initialPoint = nil
        initialRect = nil
    }
}

extension RegionSelection {
    enum Interaction: Equatable {
        case creating
        case moving
        case resizing(Handle)
    }

    enum Handle: CaseIterable {
        case bottomLeft
        case bottom
        case bottomRight
        case left
        case right
        case topLeft
        case top
        case topRight

        static func nearest(to point: CGPoint, in rect: CGRect) -> Handle? {
            let hitRadius: CGFloat = 8
            return allCases.first { handle in
                let location = handle.location(in: rect)
                return abs(location.x - point.x) <= hitRadius
                    && abs(location.y - point.y) <= hitRadius
            }
        }

        func location(in rect: CGRect) -> CGPoint {
            switch self {
            case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
            case .bottom: CGPoint(x: rect.midX, y: rect.minY)
            case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
            case .left: CGPoint(x: rect.minX, y: rect.midY)
            case .right: CGPoint(x: rect.maxX, y: rect.midY)
            case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
            case .top: CGPoint(x: rect.midX, y: rect.maxY)
            case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }

        func resized(rect: CGRect, to point: CGPoint) -> CGRect {
            var minX = rect.minX
            var maxX = rect.maxX
            var minY = rect.minY
            var maxY = rect.maxY

            switch self {
            case .bottomLeft:
                minX = point.x
                minY = point.y
            case .bottom:
                minY = point.y
            case .bottomRight:
                maxX = point.x
                minY = point.y
            case .left:
                minX = point.x
            case .right:
                maxX = point.x
            case .topLeft:
                minX = point.x
                maxY = point.y
            case .top:
                maxY = point.y
            case .topRight:
                maxX = point.x
                maxY = point.y
            }

            return CGRect(
                x: min(minX, maxX),
                y: min(minY, maxY),
                width: abs(maxX - minX),
                height: abs(maxY - minY)
            )
        }
    }
}
