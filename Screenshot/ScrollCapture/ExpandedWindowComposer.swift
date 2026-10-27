import CoreGraphics

/// The full content of one scroll area and where its visible part sits in the window image.
nonisolated struct ExpandedArea {
    /// Visible part of the area in window-image pixels, top-left origin.
    let rect: CGRect
    /// Everything the area can show, at least as large as `rect`.
    let content: CGImage
}

/// Draws a window as if it sat on an endless screen: every scroll area is shown at its
/// full content size, and the rest of the window grows around it.
///
/// The window grows by repeating one row (or column) of pixels next to the bottom (or right) edge
/// of the areas, just like a real window that gets taller. Areas beside each other share that
/// growth, so a short sidebar next to a long document ends in empty background, not stretched text.
/// Parts of the window outside the areas (a sidebar that was not scrolled) are stretched too, so the
/// repeated row is the lowest one in the area's height that is plain there, not one through text.
nonisolated enum ExpandedWindowComposer {
    static func compose(window: CGImage, areas: [ExpandedArea]) -> CGImage? {
        let (rowInsertions, columnInsertions) = insertions(
            rects: areas.map(\.rect),
            contentSizes: areas.map { CGSize(width: $0.content.width, height: $0.content.height) },
            window: window
        )
        let width = window.width + columnInsertions.reduce(0) { $0 + $1.length }
        let height = window.height + rowInsertions.reduce(0) { $0 + $1.length }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .none

        // 1. The window itself, stretched at every insertion.
        let columns = segments(length: window.width, insertions: columnInsertions)
        let rows = segments(length: window.height, insertions: rowInsertions)
        for row in rows {
            for column in columns {
                let source = CGRect(x: column.source, y: row.source, width: column.sourceLength, height: row.sourceLength)
                let destination = CGRect(x: column.destination, y: row.destination, width: column.length, height: row.length)
                draw(window, cropping: source, in: destination, context: context, canvasHeight: height)
            }
        }

        // 2. Each area at full size, on its own background so shorter areas end cleanly.
        for area in areas {
            let minX = map(Int(area.rect.minX), through: columnInsertions)
            let minY = map(Int(area.rect.minY), through: rowInsertions)
            let maxX = map(Int(area.rect.maxX), through: columnInsertions)
            let maxY = map(Int(area.rect.maxY), through: rowInsertions)
            let background = CGRect(
                x: area.content.width - 1,
                y: area.content.height - 1,
                width: 1,
                height: 1
            )
            draw(area.content, cropping: background, in: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), context: context, canvasHeight: height)

            let content = CGRect(x: 0, y: 0, width: area.content.width, height: area.content.height)
            context.saveGState()
            context.clip(to: flipped(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), canvasHeight: height))
            draw(area.content, cropping: content, in: content.offsetBy(dx: CGFloat(minX), dy: CGFloat(minY)), context: context, canvasHeight: height)
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// Where the top-left corner of `rects[index]` ends up in the composed image of `window`.
    static func origin(ofArea index: Int, rects: [CGRect], contentSizes: [CGSize], window: CGImage) -> CGPoint {
        let (rowInsertions, columnInsertions) = insertions(rects: rects, contentSizes: contentSizes, window: window)
        return CGPoint(
            x: map(Int(rects[index].minX), through: columnInsertions),
            y: map(Int(rects[index].minY), through: rowInsertions)
        )
    }

    /// A smaller copy, for live previews.
    static func scaled(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Insertions

    private static func insertions(
        rects: [CGRect],
        contentSizes: [CGSize],
        window: CGImage
    ) -> (rows: [Insertion], columns: [Insertion]) {
        let pixels = WindowPixels(window)
        let rows = insertions(
            for: zip(rects, contentSizes).map { rect, size in
                (start: Int(rect.minY), end: Int(rect.maxY), needed: Int(size.height) - Int(rect.height))
            },
            isPlain: { position in pixels?.isPlain(insertingAt: position, vertically: true, outside: rects) ?? false }
        )
        let columns = insertions(
            for: zip(rects, contentSizes).map { rect, size in
                (start: Int(rect.minX), end: Int(rect.maxX), needed: Int(size.width) - Int(rect.width))
            },
            isPlain: { position in pixels?.isPlain(insertingAt: position, vertically: false, outside: rects) ?? false }
        )
        return (rows, columns)
    }

    /// Extra pixels added after `position` along one axis.
    struct Insertion: Equatable {
        let position: Int
        let length: Int
    }

    /// Chooses where the window grows so every area gets the room it needs, while areas that sit
    /// beside each other share the same growth. Inside each area's span the window grows at the last
    /// position where `isPlain` says repeating the line leaves no stripes, or at the span's end.
    static func insertions(
        for spans: [(start: Int, end: Int, needed: Int)],
        isPlain: (Int) -> Bool
    ) -> [Insertion] {
        var result: [Insertion] = []
        for span in spans.sorted(by: { $0.end < $1.end }) where span.needed > 0 {
            let inSpan = result.indices.filter { result[$0].position > span.start && result[$0].position <= span.end }
            let alreadyAdded = inSpan.reduce(0) { $0 + result[$1].length }
            guard span.needed > alreadyAdded else { continue }
            // A longer sidebar beside a document grows the window where the document already grows,
            // like a real window whose scroll views get taller. The last plain line in the sidebar's
            // span may lie in a bar under the document (a chat's input field), which must keep its size.
            if let index = inSpan.last {
                result[index] = Insertion(position: result[index].position, length: result[index].length + span.needed - alreadyAdded)
            } else {
                let position = stride(from: span.end, to: span.start + 1, by: -1).first(where: isPlain) ?? span.end
                result.append(Insertion(position: position, length: span.needed))
            }
        }
        return result
    }

    /// Where a window pixel ends up once the insertions before it are added.
    static func map(_ position: Int, through insertions: [Insertion]) -> Int {
        position + insertions.filter { $0.position <= position }.reduce(0) { $0 + $1.length }
    }

    // MARK: - Drawing

    private struct Segment {
        let source: Int
        let sourceLength: Int
        let destination: Int
        let length: Int
    }

    /// Splits one axis into copied runs and stretched single lines.
    private static func segments(length: Int, insertions: [Insertion]) -> [Segment] {
        var segments: [Segment] = []
        var source = 0
        var destination = 0
        for insertion in insertions.sorted(by: { $0.position < $1.position }) {
            let position = min(max(insertion.position, 1), length)
            if position > source {
                segments.append(Segment(source: source, sourceLength: position - source, destination: destination, length: position - source))
                destination += position - source
                source = position
            }
            // Repeat the last line before the insertion point.
            segments.append(Segment(source: position - 1, sourceLength: 1, destination: destination, length: insertion.length))
            destination += insertion.length
        }
        if length > source {
            segments.append(Segment(source: source, sourceLength: length - source, destination: destination, length: length - source))
        }
        return segments
    }

    /// Draws part of `image` into a rectangle given with a top-left origin.
    private static func draw(_ image: CGImage, cropping source: CGRect, in destination: CGRect, context: CGContext, canvasHeight: Int) {
        guard !destination.isEmpty, let cropped = image.cropping(to: source) else { return }
        context.draw(cropped, in: flipped(destination, canvasHeight: canvasHeight))
    }

    /// Converts a top-left rectangle to Core Graphics' bottom-left space.
    private static func flipped(_ rect: CGRect, canvasHeight: Int) -> CGRect {
        CGRect(x: rect.minX, y: CGFloat(canvasHeight) - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Plain lines

    /// The window's pixels, to find a line that can be repeated without leaving stripes.
    private struct WindowPixels {
        let width: Int
        let height: Int
        /// Four bytes per pixel, row by row, top row first.
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            let width = image.width
            let height = image.height
            // Drawing in the image's own colour space copies the pixels without colour matching.
            let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace : CGColorSpace(name: CGColorSpace.sRGB)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let didDraw = bytes.withUnsafeMutableBytes { buffer in
                guard let colorSpace,
                      let context = CGContext(
                        data: buffer.baseAddress,
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: width * 4,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard didDraw else { return nil }
            self.width = width
            self.height = height
            self.bytes = bytes
        }

        /// Whether repeating the line before `position` blends into the line at `position` everywhere
        /// outside `rects` (the areas are drawn over the repeated part anyway).
        func isPlain(insertingAt position: Int, vertically: Bool, outside rects: [CGRect]) -> Bool {
            let length = vertically ? height : width
            let across = vertically ? width : height
            guard position >= 2, position <= length else { return false }
            let repeated = position - 1
            let next = position < length ? position : position - 2
            for index in 0..<across {
                let point = vertically ? CGPoint(x: index, y: repeated) : CGPoint(x: repeated, y: index)
                if rects.contains(where: { $0.contains(point) }) { continue }
                let first = vertically ? (repeated * width + index) * 4 : (index * width + repeated) * 4
                let second = vertically ? (next * width + index) * 4 : (index * width + next) * 4
                for channel in 0..<4 where abs(Int(bytes[first + channel]) - Int(bytes[second + channel])) > 8 {
                    return false
                }
            }
            return true
        }
    }
}
