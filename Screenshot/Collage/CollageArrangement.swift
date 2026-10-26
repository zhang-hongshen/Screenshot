import CoreGraphics

/// Where the user has put each screenshot of a collage, in pixels with the origin at the top left.
/// Screenshots keep their size; the collage is the smallest rectangle around all of them.
nonisolated struct CollageArrangement: Equatable {
    struct Piece: Equatable {
        /// Index into the screenshots the arrangement was made for.
        let imageIndex: Int
        var frame: CGRect
    }

    /// In drawing order: the last piece is on top.
    private(set) var pieces: [Piece]

    /// Starts with the screenshots side by side, tops aligned.
    init(sizes: [CGSize]) {
        var x: CGFloat = 0
        pieces = sizes.enumerated().map { index, size in
            defer { x += size.width }
            return Piece(imageIndex: index, frame: CGRect(origin: CGPoint(x: x, y: 0), size: size))
        }
    }

    var bounds: CGRect {
        pieces.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// The pieces' frames moved so the collage starts at zero, ready for drawing.
    var canvasPieces: [Piece] {
        let bounds = bounds
        return pieces.map { piece in
            Piece(imageIndex: piece.imageIndex, frame: piece.frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY))
        }
    }

    /// Puts the piece showing `imageIndex` on top, so the one being dragged is never hidden.
    mutating func bringToFront(imageIndex: Int) {
        guard let index = pieces.firstIndex(where: { $0.imageIndex == imageIndex }) else { return }
        pieces.append(pieces.remove(at: index))
    }

    /// Moves a piece's top left corner to `origin`. An edge closer than `snapDistance` to an edge
    /// of another piece jumps onto it, so pieces line up and touch without a hairline gap.
    mutating func move(imageIndex: Int, to origin: CGPoint, snapDistance: CGFloat) {
        guard let index = pieces.firstIndex(where: { $0.imageIndex == imageIndex }) else { return }
        let proposed = CGRect(origin: origin, size: pieces[index].frame.size)
        let others = pieces.filter { $0.imageIndex != imageIndex }.map(\.frame)

        let dx = Self.smallestSnap(
            edges: [proposed.minX, proposed.maxX],
            targets: others.flatMap { [$0.minX, $0.maxX] },
            within: snapDistance
        )
        let dy = Self.smallestSnap(
            edges: [proposed.minY, proposed.maxY],
            targets: others.flatMap { [$0.minY, $0.maxY] },
            within: snapDistance
        )
        pieces[index].frame = proposed.offsetBy(dx: dx, dy: dy)
    }

    private static func smallestSnap(edges: [CGFloat], targets: [CGFloat], within distance: CGFloat) -> CGFloat {
        var best: CGFloat = 0
        var bestDistance = distance
        for edge in edges {
            for target in targets where abs(target - edge) <= bestDistance {
                best = target - edge
                bestDistance = abs(best)
            }
        }
        return best
    }
}
