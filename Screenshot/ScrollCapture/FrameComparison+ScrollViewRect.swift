import Accelerate
import CoreGraphics

nonisolated extension FrameComparison {
    /// Grows `rect`, where content was seen moving by `offset`, to the whole scroll view that moved.
    ///
    /// Changed pixels only cover what is drawn (icons, text), not the empty space around it, so a
    /// sparse view like Finder's icon grid would split into several narrow areas. Lines next to
    /// `rect` join while they are plain background or moved by exactly `offset`. A line that stayed
    /// put with something drawn on it (a divider, a sidebar, a toolbar) is the scroll view's edge.
    static func scrollViewRect(around rect: CGRect, movedBy offset: CGPoint, from previous: CGImage, to current: CGImage) -> CGRect {
        let fullSize = max(current.width, current.height)
        guard let previousFrame = SmallFrame(previous, maximumSide: fullSize),
              let currentFrame = SmallFrame(current, maximumSide: fullSize) else { return rect }
        let previousPicture = GrayPicture(previousFrame)
        let currentPicture = GrayPicture(currentFrame)
        // Only vertical moves are handled; a horizontal move is the same after flipping over the diagonal.
        if offset.y != 0 {
            return grown(rect, shift: Int(offset.y), previous: previousPicture, current: currentPicture)
        }
        let grownFlipped = grown(
            flipped(rect),
            shift: Int(offset.x),
            previous: previousPicture.flipped(),
            current: currentPicture.flipped()
        )
        return flipped(grownFlipped)
    }

    /// Gray pixels row by row, top row first.
    private struct GrayPicture {
        let width: Int
        let height: Int
        let pixels: [Float]

        init(_ frame: SmallFrame) {
            self.init(width: frame.width, height: frame.height, pixels: frame.pixels)
        }

        private init(width: Int, height: Int, pixels: [Float]) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }

        func row(_ y: Int, columns: Range<Int>? = nil) -> ArraySlice<Float> {
            let columns = columns ?? 0..<width
            return pixels[(y * width + columns.lowerBound)..<(y * width + columns.upperBound)]
        }

        /// Columns become rows.
        func flipped() -> GrayPicture {
            var result = [Float](repeating: 0, count: pixels.count)
            vDSP_mtrans(pixels, 1, &result, 1, vDSP_Length(width), vDSP_Length(height))
            return GrayPicture(width: height, height: width, pixels: result)
        }
    }

    /// Gray levels two pixels may differ by and still count as the same.
    private static let tolerance: Float = 10

    /// Grows `rect` for a vertical move: current row `y` shows what previous row `y + shift` showed.
    private static func grown(_ rect: CGRect, shift: Int, previous: GrayPicture, current: GrayPicture) -> CGRect {
        var minX = max(0, Int(rect.minX))
        var maxX = min(current.width, Int(rect.maxX))
        var minY = max(0, Int(rect.minY))
        var maxY = min(current.height, Int(rect.maxY))
        guard minX < maxX, minY < maxY else { return rect }
        let background = mostCommonGray(onOutlineOf: minX..<maxX, minY..<maxY, in: current)

        // Columns are judged over the rows that changed. Comparing a row with the one it came from
        // only inside those rows keeps the toolbar and status bar out of the comparison.
        let rows = minY..<maxY
        var notBackground = [Float](repeating: 0, count: current.width)
        var changed = notBackground
        var notMoved = notBackground
        var comparedRows = 0
        for y in rows {
            let row = current.row(y)
            notBackground = vDSP.add(notBackground, mismatches(vDSP.add(-background, row), tolerance: 4))
            changed = vDSP.add(changed, mismatches(vDSP.subtract(row, previous.row(y)), tolerance: tolerance))
            if rows.contains(y + shift) {
                notMoved = vDSP.add(notMoved, mismatches(vDSP.subtract(row, previous.row(y + shift)), tolerance: tolerance))
                comparedRows += 1
            }
        }
        func columnFits(_ x: Int) -> Bool {
            belongsToScrollView(notBackground: notBackground[x], changed: changed[x], notMoved: notMoved[x], length: rows.count)
        }
        // The changes can reach past the scroll view (its scroll bar thumb moves too), so edge
        // columns that do not belong are cut off first.
        while minX < maxX && !columnFits(minX) { minX += 1 }
        while maxX > minX && !columnFits(maxX - 1) { maxX -= 1 }
        while minX > 0 && columnFits(minX - 1) { minX -= 1 }
        while maxX < current.width && columnFits(maxX) { maxX += 1 }

        let columns = minX..<maxX
        func rowFits(_ y: Int) -> Bool {
            let row = current.row(y, columns: columns)
            let partner = y + shift
            let hasPartner = partner >= 0 && partner < current.height
            return belongsToScrollView(
                notBackground: vDSP.sum(mismatches(vDSP.add(-background, row), tolerance: 4)),
                changed: vDSP.sum(mismatches(vDSP.subtract(row, previous.row(y, columns: columns)), tolerance: tolerance)),
                notMoved: hasPartner ? vDSP.sum(mismatches(vDSP.subtract(row, previous.row(partner, columns: columns)), tolerance: tolerance)) : nil,
                length: columns.count
            )
        }
        while minY > 0 && rowFits(minY - 1) { minY -= 1 }
        while maxY < current.height && rowFits(maxY) { maxY += 1 }

        guard minX < maxX else { return rect }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A line belongs to the scroll view when it is plain background; when it changed and the move
    /// explains the change (it leaves at most a tenth as many pixels wrong as changed); or when it did
    /// not change, looks the same after the move and is mostly background (the faint shadow beside an
    /// icon). A line that stayed put and is drawn along most of its length (a divider, a sidebar, a
    /// scroll bar track) is the scroll view's edge. All counts are pixels of a line of `length` pixels;
    /// `notMoved` is nil when the line it came from is outside the frame.
    private static func belongsToScrollView(notBackground: Float, changed: Float, notMoved: Float?, length: Int) -> Bool {
        if notBackground == 0 { return true }
        guard let notMoved else { return false }
        if changed == 0 {
            return notMoved == 0 && notBackground < Float(length) / 2
        }
        return notMoved * 10 <= changed
    }

    /// 1 where a difference is larger than `tolerance`, 0 elsewhere. Gray values are whole numbers,
    /// so "larger" means at least `tolerance + 1`, which the clip turns into exactly 1.
    private static func mismatches(_ differences: [Float], tolerance: Float) -> [Float] {
        vDSP.clip(vDSP.add(-tolerance, vDSP.absolute(differences)), to: 0...1)
    }

    /// The gray most pixels on the rectangle's outline have: the view's background.
    private static func mostCommonGray(onOutlineOf columns: Range<Int>, _ rows: Range<Int>, in picture: GrayPicture) -> Float {
        var counts = [Int](repeating: 0, count: 256)
        func count(_ x: Int, _ y: Int) {
            counts[Int(picture.pixels[y * picture.width + x])] += 1
        }
        for x in columns {
            count(x, rows.lowerBound)
            count(x, rows.upperBound - 1)
        }
        for y in rows {
            count(columns.lowerBound, y)
            count(columns.upperBound - 1, y)
        }
        let mostCommon = counts.indices.max { counts[$0] < counts[$1] } ?? 0
        return Float(mostCommon)
    }

    private static func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
    }
}
