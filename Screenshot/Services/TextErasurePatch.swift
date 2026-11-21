import CoreGraphics

/// A cached text-free tile; a missing image records that Vision found no text in this tile.
nonisolated struct TextErasurePatch {
    let rect: CGRect
    let image: CGImage?
}
