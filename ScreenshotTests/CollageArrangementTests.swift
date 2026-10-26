import CoreGraphics
import Testing
@testable import Screenshot

struct CollageArrangementTests {
    @Test func screenshotsStartSideBySide() {
        let arrangement = CollageArrangement(sizes: [CGSize(width: 200, height: 100), CGSize(width: 100, height: 150)])

        #expect(arrangement.pieces.map(\.frame) == [
            CGRect(x: 0, y: 0, width: 200, height: 100),
            CGRect(x: 200, y: 0, width: 100, height: 150)
        ])
        #expect(arrangement.bounds == CGRect(x: 0, y: 0, width: 300, height: 150))
    }

    @Test(arguments: [
        // Close to the bottom left corner of the first piece: both edges snap.
        (CGPoint(x: 5, y: 104), CGRect(x: 0, y: 100, width: 100, height: 150)),
        // Too far from every edge: stays where it was dropped.
        (CGPoint(x: 40, y: 130), CGRect(x: 40, y: 130, width: 100, height: 150))
    ])
    func movedPieceSnapsToNearbyEdges(origin: CGPoint, expected: CGRect) {
        var arrangement = CollageArrangement(sizes: [CGSize(width: 200, height: 100), CGSize(width: 100, height: 150)])

        arrangement.move(imageIndex: 1, to: origin, snapDistance: 8)

        #expect(arrangement.pieces[1].frame == expected)
    }

    @Test func canvasStartsAtTheTopLeftOfAllPieces() {
        var arrangement = CollageArrangement(sizes: [CGSize(width: 200, height: 100), CGSize(width: 100, height: 150)])
        arrangement.move(imageIndex: 1, to: CGPoint(x: -50, y: -30), snapDistance: 0)
        arrangement.bringToFront(imageIndex: 0)

        #expect(arrangement.canvasPieces == [
            CollageArrangement.Piece(imageIndex: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 150)),
            CollageArrangement.Piece(imageIndex: 0, frame: CGRect(x: 50, y: 30, width: 200, height: 100))
        ])
    }
}
