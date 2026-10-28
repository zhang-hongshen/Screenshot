import Accelerate
import CoreGraphics

/// Joins overlapping frames of one scrolling view into one picture.
///
/// Scrolling moves content straight up/down or left/right. Each frame is squeezed into a profile
/// (a few gray values per pixel row and per pixel column), and the move is found by sliding the new
/// profile along the previous one: first roughly, then to the exact pixel. Only the newly revealed
/// strip of each frame is kept. Edges that never move (sticky headers, toolbars inside the area)
/// are found from the first move and kept once. Small things floating over the content (a "scroll
/// to bottom" button) are kept once too: content is taken only after it has moved out from under them.
nonisolated struct ScrollCaptureStitcher {
    enum AppendResult: Equatable {
        case appended
        case unchanged
        case noOverlap
        case limitReached
    }

    private enum Axis {
        case vertical
        case horizontal
    }

    /// Gray values of a frame squeezed across one axis: one line per pixel row (vertical) or
    /// column (horizontal), each made of `binCount` averaged values.
    private struct Profile {
        let lineCount: Int
        let binCount: Int
        /// `values[line * binCount + bin]`. Lines are stored one after another, so any run of
        /// lines is one contiguous slice that Accelerate can compare in a single call.
        let values: [Float]

        func lines(_ range: Range<Int>) -> ArraySlice<Float> {
            values[(range.lowerBound * binCount)..<(range.upperBound * binCount)]
        }
    }

    private struct Profiles {
        let rows: Profile
        let columns: Profile
        let coarseRows: Profile
        let coarseColumns: Profile

        func exact(along axis: Axis) -> Profile {
            axis == .vertical ? rows : columns
        }

        func coarse(along axis: Axis) -> Profile {
            axis == .vertical ? coarseRows : coarseColumns
        }
    }

    /// Newly revealed pixels of one frame, placed in content coordinates.
    private struct Piece {
        let image: CGImage
        let rect: CGRect
        /// Where the frame that revealed it sat, so its fixed edges can be cut off later.
        let frameOrigin: CGPoint
    }

    /// How far the last appended frame moved: positive y means the content moved up (scrolled down).
    private(set) var lastOffset: CGPoint?
    private var lastAxis = Axis.vertical

    private var firstFrame: CGImage?
    private var previousProfiles: Profiles?
    private var pieces: [Piece] = []
    /// Content position of the latest frame's top-left pixel.
    private var origin = CGPoint.zero
    /// Rows and columns at the edges that do not scroll, found from the first move along each axis.
    private var fixedEdges = Edges()
    private var hasVerticalEdges = false
    private var hasHorizontalEdges = false
    /// Lines covered by something floating over the content, in frame pixels along each axis.
    private var floatingRows: Range<Int>?
    private var floatingColumns: Range<Int>?
    /// The part of the latest frame left out because of floating things, replaced on every move,
    /// so they show once, where the capture ended.
    private var latestCoveredPieces: [Piece] = []

    private struct Edges {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var left: CGFloat = 0
        var right: CGFloat = 0
    }

    private enum Edge {
        case top
        case bottom
        case left
        case right
    }

    /// A fixed edge copied from the frame that reached furthest towards it.
    private struct EdgeStrip {
        let image: CGImage
        /// How far that frame sat towards the edge, in content pixels; the first frame sits at 0.
        let reach: CGFloat
    }

    /// A translucent bar shows the content behind it, so the bar under the content comes from the
    /// frame furthest down, not from the first one. Edges without a strip come from the first frame.
    private var edgeStrips: [Edge: EdgeStrip] = [:]

    private let maximumOutputDimension: CGFloat = 32_768
    private static let binCount = 64
    /// The rough search only needs the overall look of each line, so it uses fewer, wider bins.
    private static let coarseBinCount = 16
    private static let coarseFactor = 4
    private static let coarseCandidateCount = 3
    /// Largest mean gray difference (0–255) still accepted as the same content after moving.
    private static let maximumDifference: Float = 3
    /// Largest mean gray difference accepted when the move still explains almost all of the change.
    private static let maximumParallaxDifference: Float = 8
    /// Largest mean gray difference of a single line that still moved exactly with the content.
    private static let movedLineDifference: Float = 1
    /// Smallest gray difference that a floating thing makes against the content moving under it.
    private static let floatingDifference: Float = 2
    /// Fewer lines in a row than this that look floating are noise.
    private static let minimumFloatingRun = 4

    // MARK: - Appending

    mutating func append(_ image: CGImage) -> AppendResult {
        guard let profiles = Self.profiles(of: image) else { return .noOverlap }
        guard let firstFrame, let previousProfiles else {
            self.firstFrame = image
            self.previousProfiles = profiles
            return .appended
        }
        guard image.width == firstFrame.width, image.height == firstFrame.height else { return .noOverlap }

        let changedRows = Self.changedLines(previousProfiles.rows, profiles.rows)
        let changedColumns = Self.changedLines(previousProfiles.columns, profiles.columns)
        guard let rowBand = Self.band(of: changedRows),
              let columnBand = Self.band(of: changedColumns) else { return .unchanged }

        // People usually keep scrolling along the same axis, so that axis is tried first
        // and the other one only when the first does not line up.
        let axes: [Axis] = lastAxis == .horizontal ? [.horizontal, .vertical] : [.vertical, .horizontal]
        var move: (axis: Axis, offset: Int)?
        var isStill = false
        for axis in axes {
            let band: Range<Int>
            switch axis {
            case .vertical: band = hasVerticalEdges ? scrollingRange(along: .vertical, size: image.height) : rowBand
            case .horizontal: band = hasHorizontalEdges ? scrollingRange(along: .horizontal, size: image.width) : columnBand
            }
            let lastMove = axis == .vertical ? lastOffset?.y : lastOffset?.x
            guard let found = Self.bestMove(from: previousProfiles, to: profiles, along: axis, band: band, lastMove: lastMove),
                  let stillDifference = Self.difference(
                      previousProfiles.exact(along: axis),
                      profiles.exact(along: axis),
                      band: band,
                      shift: 0
                  ) else { continue }
            // A video or animation changes pixels in place; when the frames match better
            // unmoved, nothing scrolled along this axis, and a 1-pixel "move" would repeat a line.
            if stillDifference <= found.difference {
                isStill = true
                continue
            }
            if Self.isScroll(difference: found.difference, stillDifference: stillDifference) {
                move = (axis, found.offset)
                break
            }
        }
        guard let move else { return isStill ? .unchanged : .noOverlap }

        var updated = self
        updated.learnFixedEdges(
            along: move.axis,
            offset: move.offset,
            rowBand: rowBand,
            columnBand: columnBand,
            previous: previousProfiles,
            current: profiles
        )
        updated.learnFloatingLines(along: move.axis, offset: move.offset, previous: previousProfiles, current: profiles)
        let previousOrigin = origin
        switch move.axis {
        case .vertical: updated.origin.y += CGFloat(move.offset)
        case .horizontal: updated.origin.x += CGFloat(move.offset)
        }
        updated.addPieces(of: image, previousOrigin: previousOrigin)
        updated.keepEdgeStrips(of: image)
        let size = updated.outputSize
        guard size.width <= maximumOutputDimension, size.height <= maximumOutputDimension else {
            return .limitReached
        }

        self = updated
        self.previousProfiles = profiles
        lastAxis = move.axis
        lastOffset = move.axis == .vertical
            ? CGPoint(x: 0, y: move.offset)
            : CGPoint(x: move.offset, y: 0)
        return .appended
    }

    /// The first move along an axis shows which edges stay put; they are kept once, from the first frame.
    private mutating func learnFixedEdges(
        along axis: Axis,
        offset: Int,
        rowBand: Range<Int>,
        columnBand: Range<Int>,
        previous: Profiles,
        current: Profiles
    ) {
        switch axis {
        case .vertical where !hasVerticalEdges:
            let band = Self.movingBand(previous.rows, current.rows, changedBand: rowBand, shift: offset)
            fixedEdges.top = CGFloat(band.lowerBound)
            fixedEdges.bottom = CGFloat(current.rows.lineCount - band.upperBound)
            hasVerticalEdges = true
        case .horizontal where !hasHorizontalEdges:
            let band = Self.movingBand(previous.columns, current.columns, changedBand: columnBand, shift: offset)
            fixedEdges.left = CGFloat(band.lowerBound)
            fixedEdges.right = CGFloat(current.columns.lineCount - band.upperBound)
            hasHorizontalEdges = true
        default:
            break
        }
    }

    /// The changed lines that really moved with the content. A translucent bar over the content
    /// (a Liquid Glass toolbar) changes too, as the content slides under it, but its lines do not
    /// line up after the move, so it is left out and kept once, like an opaque bar.
    private static func movingBand(_ previous: Profile, _ current: Profile, changedBand: Range<Int>, shift: Int) -> Range<Int> {
        // A line moved when the content it shows now sat `shift` lines further in the previous frame,
        // or when what it showed before sits `shift` lines back now. Near an edge only one of the
        // two exists, which is enough to tell a bar from content entering the view.
        func moved(_ line: Int) -> Bool {
            var comparisons: [Float] = []
            if let difference = lineDifference(current, line, previous, line + shift) {
                comparisons.append(difference)
            }
            if let difference = lineDifference(previous, line, current, line - shift) {
                comparisons.append(difference)
            }
            // Blurred content looks much like the sharp content it covers, so only lines that
            // are almost exactly the same count as moved.
            return comparisons.contains { $0 <= movedLineDifference }
        }
        // Bars are short. A longer run of lines that did not move is a picture changing on its own
        // (a video, a parallax card), which is part of the content.
        let longestBar = changedBand.count / 4
        let runLength = 16
        var start = changedBand.lowerBound
        var run = 0
        for line in changedBand.prefix(longestBar + runLength) {
            run = moved(line) ? run + 1 : 0
            if run == runLength {
                start = line - runLength + 1
                break
            }
        }
        var end = changedBand.upperBound
        run = 0
        for line in changedBand.suffix(longestBar + runLength).reversed() where line >= start {
            run = moved(line) ? run + 1 : 0
            if run == runLength {
                end = line + runLength
                break
            }
        }
        return start..<end
    }

    /// A floating thing may appear only after scrolling began (or fade in), so it is looked for on
    /// every move, and the lines it ever covered are remembered.
    private mutating func learnFloatingLines(along axis: Axis, offset: Int, previous: Profiles, current: Profiles) {
        let band = scrollingRange(along: axis, size: current.exact(along: axis).lineCount)
        guard let found = Self.floatingLines(previous.exact(along: axis), current.exact(along: axis), band: band, shift: offset) else {
            return
        }
        let known = axis == .vertical ? floatingRows : floatingColumns
        let lines = known.map { min($0.lowerBound, found.lowerBound)..<max($0.upperBound, found.upperBound) } ?? found
        // Floating buttons are small and sit near an edge. Anything bigger is content changing on its own.
        guard lines.count <= band.count / 4, Self.lines(band, awayFrom: lines).count >= band.count / 2 else { return }
        switch axis {
        case .vertical: floatingRows = lines
        case .horizontal: floatingColumns = lines
        }
    }

    /// Lines where something stays put while the content moves under it: some of their values
    /// match the previous frame in place, but not after the move.
    private static func floatingLines(_ previous: Profile, _ current: Profile, band: Range<Int>, shift: Int) -> Range<Int>? {
        func isFloating(_ line: Int) -> Bool {
            let now = current.lines(line..<(line + 1))
            let before = previous.lines(line..<(line + 1))
            // What the line shows now against what it showed before the move, or, near the edge
            // where content enters, what it showed before against where that content went.
            let moved: [Float]
            if (0..<previous.lineCount).contains(line + shift) {
                moved = vDSP.absolute(vDSP.subtract(now, previous.lines((line + shift)..<(line + shift + 1))))
            } else if (0..<current.lineCount).contains(line - shift) {
                moved = vDSP.absolute(vDSP.subtract(before, current.lines((line - shift)..<(line - shift + 1))))
            } else {
                return false
            }
            let still = vDSP.absolute(vDSP.subtract(now, before))
            return zip(still, moved).contains { still, moved in moved >= floatingDifference && still * 4 <= moved }
        }

        var found: Range<Int>?
        var runStart: Int?
        // One line past the band closes the last run.
        for line in band.lowerBound...band.upperBound {
            if line < band.upperBound, isFloating(line) {
                runStart = runStart ?? line
                continue
            }
            if let start = runStart, line - start >= minimumFloatingRun {
                found = (found?.lowerBound ?? start)..<line
            }
            runStart = nil
        }
        return found
    }

    /// The part of `span` on the far side of `floating`: the floating lines and the stretch
    /// between them and the nearer end are left out.
    private static func lines(_ span: Range<Int>, awayFrom floating: Range<Int>?) -> Range<Int> {
        guard let floating else { return span }
        let before = span.lowerBound..<min(max(span.lowerBound, floating.lowerBound), span.upperBound)
        let after = max(min(span.upperBound, floating.upperBound), span.lowerBound)..<span.upperBound
        return before.count >= after.count ? before : after
    }

    /// Mean gray difference between one line of each profile, or nil when a line is outside its profile.
    private static func lineDifference(_ first: Profile, _ firstLine: Int, _ second: Profile, _ secondLine: Int) -> Float? {
        guard (0..<first.lineCount).contains(firstLine), (0..<second.lineCount).contains(secondLine) else { return nil }
        let firstValues = first.lines(firstLine..<(firstLine + 1))
        let secondValues = second.lines(secondLine..<(secondLine + 1))
        return vDSP.sumOfMagnitudes(vDSP.subtract(firstValues, secondValues)) / Float(firstValues.count)
    }

    /// Keeps the parts of the frame's scrolling area that the previous frame did not show.
    private mutating func addPieces(of image: CGImage, previousOrigin: CGPoint) {
        let uncovered = uncoveredRect(of: image)
        let current = uncovered.offsetBy(dx: origin.x, dy: origin.y)
        let previous = uncovered.offsetBy(dx: previousOrigin.x, dy: previousOrigin.y)
        pieces += Self.subtract(previous, from: current).compactMap { piece(of: image, at: $0) }
        latestCoveredPieces = Self.subtract(uncovered, from: scrollingRect(of: image)).compactMap { local in
            piece(of: image, at: local.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    /// Keeps the frame's fixed edges that sit further towards their side than any frame before.
    private mutating func keepEdgeStrips(of image: CGImage) {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let middleHeight = height - fixedEdges.top - fixedEdges.bottom
        let strips: [(edge: Edge, rect: CGRect, reach: CGFloat)] = [
            (.top, CGRect(x: 0, y: 0, width: width, height: fixedEdges.top), -origin.y),
            (.bottom, CGRect(x: 0, y: height - fixedEdges.bottom, width: width, height: fixedEdges.bottom), origin.y),
            (.left, CGRect(x: 0, y: fixedEdges.top, width: fixedEdges.left, height: middleHeight), -origin.x),
            (.right, CGRect(x: width - fixedEdges.right, y: fixedEdges.top, width: fixedEdges.right, height: middleHeight), origin.x),
        ]
        for strip in strips where !strip.rect.isEmpty && strip.reach > edgeStrips[strip.edge]?.reach ?? 0 {
            if let copy = Self.copy(of: image, cropping: strip.rect) {
                edgeStrips[strip.edge] = EdgeStrip(image: copy, reach: strip.reach)
            }
        }
    }

    /// A copy of the latest frame's pixels at `rect`, given in content coordinates.
    private func piece(of image: CGImage, at rect: CGRect) -> Piece? {
        let local = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        guard let copy = Self.copy(of: image, cropping: local) else { return nil }
        return Piece(image: copy, rect: rect, frameOrigin: origin)
    }

    // MARK: - Result

    /// Where the latest frame sits in `makeImage()`, in pixels with a top-left origin.
    var latestFrameRect: CGRect? {
        frameRect(at: origin)
    }

    /// Where the first frame sits in `makeImage()`, in pixels with a top-left origin.
    var firstFrameRect: CGRect? {
        frameRect(at: .zero)
    }

    private func frameRect(at frameOrigin: CGPoint) -> CGRect? {
        guard let firstFrame else { return nil }
        let content = contentBounds()
        return CGRect(
            x: frameOrigin.x - content.minX + fixedEdges.left,
            y: frameOrigin.y - content.minY + fixedEdges.top,
            width: CGFloat(firstFrame.width),
            height: CGFloat(firstFrame.height)
        )
    }

    /// The stitched picture. A `scale` below 1 makes a smaller copy, for live previews.
    func makeImage(scale: CGFloat = 1) -> CGImage? {
        guard let firstFrame else { return nil }
        if pieces.isEmpty && scale == 1 { return firstFrame }

        let size = outputSize
        guard let context = Self.makeContext(width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up))) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = scale == 1 ? .none : .medium

        let content = contentBounds()
        let edges = fixedEdges
        let frameWidth = CGFloat(firstFrame.width)
        let frameHeight = CGFloat(firstFrame.height)
        func outputPoint(of contentPoint: CGPoint) -> CGPoint {
            CGPoint(x: contentPoint.x - content.minX + edges.left, y: contentPoint.y - content.minY + edges.top)
        }

        // Areas that end before others show the scroll view's own background.
        let corner = CGRect(x: frameWidth - edges.right - 1, y: frameHeight - edges.bottom - 1, width: 1, height: 1)
        Self.draw(firstFrame, cropping: corner, in: CGRect(origin: .zero, size: size), context: context, canvasHeight: size.height)

        let scrolling = scrollingRect(of: firstFrame)
        Self.draw(firstFrame, cropping: scrolling, at: outputPoint(of: scrolling.origin), context: context, canvasHeight: size.height)
        // Content that was clear of floating things wins over the latest frame's covered part.
        for piece in latestCoveredPieces + pieces {
            let visible = piece.rect.intersection(scrolling.offsetBy(dx: piece.frameOrigin.x, dy: piece.frameOrigin.y))
            guard !visible.isEmpty else { continue }
            let local = visible.offsetBy(dx: -piece.rect.minX, dy: -piece.rect.minY)
            Self.draw(piece.image, cropping: local, at: outputPoint(of: visible.origin), context: context, canvasHeight: size.height)
        }

        // Fixed edges come last, so they stay on top like in the real window.
        let middleHeight = frameHeight - edges.top - edges.bottom
        let fixedParts: [(edge: Edge, source: CGRect, destination: CGPoint)] = [
            (.top, CGRect(x: 0, y: 0, width: frameWidth, height: edges.top), .zero),
            (.bottom, CGRect(x: 0, y: frameHeight - edges.bottom, width: frameWidth, height: edges.bottom),
             CGPoint(x: 0, y: edges.top + content.height)),
            (.left, CGRect(x: 0, y: edges.top, width: edges.left, height: middleHeight), CGPoint(x: 0, y: edges.top)),
            (.right, CGRect(x: frameWidth - edges.right, y: edges.top, width: edges.right, height: middleHeight),
             CGPoint(x: edges.left + content.width, y: edges.top)),
        ]
        for part in fixedParts where !part.source.isEmpty {
            // A side strip kept before the top and bottom edges were known has the wrong height.
            if let strip = edgeStrips[part.edge],
               CGFloat(strip.image.width) == part.source.width, CGFloat(strip.image.height) == part.source.height {
                let whole = CGRect(x: 0, y: 0, width: strip.image.width, height: strip.image.height)
                Self.draw(strip.image, cropping: whole, at: part.destination, context: context, canvasHeight: size.height)
            } else {
                Self.draw(firstFrame, cropping: part.source, at: part.destination, context: context, canvasHeight: size.height)
            }
        }
        return context.makeImage()
    }

    /// Size of `makeImage()` in pixels.
    var outputSize: CGSize {
        let content = contentBounds()
        return CGSize(
            width: fixedEdges.left + content.width + fixedEdges.right,
            height: fixedEdges.top + content.height + fixedEdges.bottom
        )
    }

    /// Everything the scrolling part has shown, in content coordinates.
    private func contentBounds() -> CGRect {
        guard let firstFrame else { return .zero }
        let scrolling = scrollingRect(of: firstFrame)
        var bounds = scrolling
        for piece in latestCoveredPieces + pieces {
            let visible = piece.rect.intersection(scrolling.offsetBy(dx: piece.frameOrigin.x, dy: piece.frameOrigin.y))
            if !visible.isEmpty {
                bounds = bounds.union(visible)
            }
        }
        return bounds
    }

    private func scrollingRect(of image: CGImage) -> CGRect {
        CGRect(
            x: fixedEdges.left,
            y: fixedEdges.top,
            width: CGFloat(image.width) - fixedEdges.left - fixedEdges.right,
            height: CGFloat(image.height) - fixedEdges.top - fixedEdges.bottom
        )
    }

    /// The scrolling part of a frame without the lines under floating things.
    private func uncoveredRect(of image: CGImage) -> CGRect {
        let rows = Self.lines(scrollingRange(along: .vertical, size: image.height), awayFrom: floatingRows)
        let columns = Self.lines(scrollingRange(along: .horizontal, size: image.width), awayFrom: floatingColumns)
        return CGRect(x: columns.lowerBound, y: rows.lowerBound, width: columns.count, height: rows.count)
    }

    private func scrollingRange(along axis: Axis, size: Int) -> Range<Int> {
        switch axis {
        case .vertical: Int(fixedEdges.top)..<(size - Int(fixedEdges.bottom))
        case .horizontal: Int(fixedEdges.left)..<(size - Int(fixedEdges.right))
        }
    }

    // MARK: - Measuring the move

    /// A move is accepted when it leaves the frames nearly the same, or, on pages whose pictures
    /// move at their own speed (parallax cards in the App Store), when it explains almost all of the change.
    private static func isScroll(difference: Float, stillDifference: Float) -> Bool {
        difference <= maximumDifference
            || (difference <= maximumParallaxDifference && difference * 5 <= stillDifference)
    }

    /// Slides the current lines along the previous ones inside `band` and returns the best offset.
    /// An offset `s` means current line `y` shows what previous line `y + s` showed.
    /// `lastMove`, the previous offset along this axis, is always checked: scrolling rarely changes speed abruptly.
    private static func bestMove(
        from previousProfiles: Profiles,
        to currentProfiles: Profiles,
        along axis: Axis,
        band: Range<Int>,
        lastMove: CGFloat?
    ) -> (offset: Int, difference: Float)? {
        guard band.count >= 16 else { return nil }
        let previous = previousProfiles.exact(along: axis)
        let current = currentProfiles.exact(along: axis)
        let previousCoarse = previousProfiles.coarse(along: axis)
        let currentCoarse = currentProfiles.coarse(along: axis)
        let maximumShift = band.count * 85 / 100
        let minimumOverlap = max(8, band.count / 8)

        let coarseBand = (band.lowerBound / coarseFactor)..<(band.upperBound / coarseFactor)
        var coarseScores: [(shift: Int, score: Float)] = []
        for shift in -(maximumShift / coarseFactor)...(maximumShift / coarseFactor) where shift != 0 {
            guard coarseBand.count - abs(shift) >= minimumOverlap / coarseFactor,
                  let difference = difference(previousCoarse, currentCoarse, band: coarseBand, shift: shift) else { continue }
            // Repeating content (identical list rows) matches at several offsets; prefer the shortest move.
            coarseScores.append((shift, difference + Float(abs(shift)) * 0.0005))
        }

        // In a repeating grid (Finder icons) a wrong offset that happens to fall on a coarse line can
        // score better than the real one, which falls between two. So the best few guesses and the
        // last move are all checked exactly, skipping guesses right next to one already chosen.
        var centers: [Int] = []
        for candidate in coarseScores.sorted(by: { $0.score < $1.score }) where centers.count < coarseCandidateCount {
            if !centers.contains(where: { abs($0 - candidate.shift) <= 1 }) {
                centers.append(candidate.shift)
            }
        }
        if let lastMove, lastMove != 0 {
            centers.append(Int(lastMove) / coarseFactor)
        }

        var best: (offset: Int, difference: Float)?
        for center in centers.map({ $0 * coarseFactor }) {
            for shift in (center - coarseFactor - 1)...(center + coarseFactor + 1)
                where shift != 0 && abs(shift) <= maximumShift && band.count - abs(shift) >= minimumOverlap {
                guard let difference = difference(previous, current, band: band, shift: shift) else { continue }
                let isShorterTie = difference == best?.difference && abs(shift) < abs(best?.offset ?? 0)
                if difference < best?.difference ?? .infinity || isShorterTie {
                    best = (shift, difference)
                }
            }
        }
        return best
    }

    /// Mean gray difference between the overlapping lines of two profiles after moving by `shift`.
    private static func difference(_ previous: Profile, _ current: Profile, band: Range<Int>, shift: Int) -> Float? {
        let count = band.count - abs(shift)
        guard count > 0 else { return nil }
        let previousStart = band.lowerBound + max(shift, 0)
        let currentStart = band.lowerBound + max(-shift, 0)
        let previousLines = previous.lines(previousStart..<(previousStart + count))
        let currentLines = current.lines(currentStart..<(currentStart + count))
        return vDSP.sumOfMagnitudes(vDSP.subtract(previousLines, currentLines)) / Float(previousLines.count)
    }

    /// Lines that look different in the two frames when compared in place.
    private static func changedLines(_ previous: Profile, _ current: Profile) -> [Bool] {
        let differences = vDSP.subtract(previous.values, current.values)
        let bins = current.binCount
        return (0..<current.lineCount).map { line in
            vDSP.maximumMagnitude(differences[(line * bins)..<((line + 1) * bins)]) > 4
        }
    }

    /// From the first to the last changed line.
    private static func band(of changed: [Bool]) -> Range<Int>? {
        guard let first = changed.firstIndex(of: true),
              let last = changed.lastIndex(of: true) else { return nil }
        return first..<(last + 1)
    }

    // MARK: - Pixels

    private static func profiles(of frame: CGImage) -> Profiles? {
        // Two small gray pictures hold everything the profiles need: one squeezed sideways
        // (one row per pixel row) and one squeezed top to bottom (one column per pixel column).
        let width = frame.width
        let height = frame.height
        guard let rowImage = frame.smallGrayCopy(width: min(binCount, width), height: height),
              let columnImage = frame.smallGrayCopy(width: width, height: min(binCount, height)),
              let rows = profile(of: rowImage, along: .vertical, lineCount: height, binCount: binCount),
              let columns = profile(of: columnImage, along: .horizontal, lineCount: width, binCount: binCount),
              let coarseRows = profile(of: rowImage, along: .vertical, lineCount: max(1, height / coarseFactor), binCount: coarseBinCount),
              let coarseColumns = profile(of: columnImage, along: .horizontal, lineCount: max(1, width / coarseFactor), binCount: coarseBinCount)
        else { return nil }
        return Profiles(rows: rows, columns: columns, coarseRows: coarseRows, coarseColumns: coarseColumns)
    }

    /// Lets Core Graphics shrink a gray picture to `binCount` values across and `lineCount` lines,
    /// so each line of the profile is one row of the result, top line first.
    private static func profile(of image: CGImage, along axis: Axis, lineCount: Int, binCount: Int) -> Profile? {
        let length = axis == .vertical ? image.height : image.width
        let across = axis == .vertical ? image.width : image.height
        let bins = min(binCount, across)
        guard let context = makeGrayContext(width: bins, height: lineCount) else { return nil }

        let lineScale = CGFloat(lineCount) / CGFloat(length)
        let binScale = CGFloat(bins) / CGFloat(across)
        switch axis {
        case .vertical:
            context.scaleBy(x: binScale, y: lineScale)
        case .horizontal:
            // Flips the image over its diagonal, so its leftmost column becomes the top row.
            context.concatenate(CGAffineTransform(a: 0, b: -lineScale, c: -binScale, d: 0, tx: CGFloat(bins), ty: CGFloat(lineCount)))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard let data = context.data else { return nil }
        let pixels = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: lineCount * bins)
        let values = vDSP.integerToFloatingPoint(pixels, floatingPointType: Float.self)
        return Profile(lineCount: lineCount, binCount: bins, values: values)
    }

    /// The parts of `rect` outside `hole`, as up to four rectangles.
    private static func subtract(_ hole: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(hole)
        guard !overlap.isEmpty else { return [rect] }
        let parts = [
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
            CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
            CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height),
        ]
        return parts.filter { $0.width > 0 && $0.height > 0 }
    }

    /// A standalone copy, so the strip does not keep the whole frame in memory.
    private static func copy(of image: CGImage, cropping rect: CGRect) -> CGImage? {
        guard let crop = image.cropping(to: rect),
              let context = makeContext(width: crop.width, height: crop.height) else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return context.makeImage()
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Rows have no padding (`bytesPerRow` equals `width`), so the pixels can be read as one block.
    private static func makeGrayContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }

    private static func draw(_ image: CGImage, cropping source: CGRect, at point: CGPoint, context: CGContext, canvasHeight: CGFloat) {
        draw(image, cropping: source, in: CGRect(origin: point, size: source.size), context: context, canvasHeight: canvasHeight)
    }

    /// Draws part of `image` into a rectangle given with a top-left origin.
    private static func draw(_ image: CGImage, cropping source: CGRect, in destination: CGRect, context: CGContext, canvasHeight: CGFloat) {
        guard !destination.isEmpty, let cropped = image.cropping(to: source) else { return }
        let flipped = CGRect(
            x: destination.minX,
            y: canvasHeight - destination.maxY,
            width: destination.width,
            height: destination.height
        )
        context.draw(cropped, in: flipped)
    }
}
