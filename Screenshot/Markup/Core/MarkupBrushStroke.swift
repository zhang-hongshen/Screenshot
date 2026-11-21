import CoreGraphics

/// The footprint along one continuous mosaic or text-erasing stroke, in image points.
nonisolated struct MarkupBrushStroke: Equatable, Sendable {
    let points: [CGPoint]
    let radius: CGFloat
    var isSquare = false

    var coverage: CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        if isSquare {
            var previous = first
            for point in points {
                let distance = max(abs(point.x - previous.x), abs(point.y - previous.y))
                let steps = max(1, Int(ceil(distance)))
                for step in 0...steps {
                    let fraction = CGFloat(step) / CGFloat(steps)
                    let center = CGPoint(
                        x: previous.x + (point.x - previous.x) * fraction,
                        y: previous.y + (point.y - previous.y) * fraction
                    )
                    path.addRect(CGRect(
                        x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
                    ))
                }
                previous = point
            }
            return path
        }
        if points.count == 1 {
            path.addEllipse(in: CGRect(
                x: first.x - radius, y: first.y - radius,
                width: radius * 2, height: radius * 2
            ))
            return path
        }
        path.addLines(between: points)
        return path.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }

    func scaled(by scale: CGSize) -> MarkupBrushStroke {
        MarkupBrushStroke(
            points: points.map { CGPoint(x: $0.x * scale.width, y: $0.y * scale.height) },
            radius: radius * max(scale.width, scale.height),
            isSquare: isSquare
        )
    }

}
