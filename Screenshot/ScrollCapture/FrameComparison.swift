import Accelerate
import CoreGraphics

/// Cheap whole-frame comparisons on small gray copies: has the picture settled, and what changed.
nonisolated enum FrameComparison {
    /// A gray copy of a frame whose longer side is at most `maximumSide` pixels.
    /// Making one costs a few milliseconds, so keep it when the frame is compared again.
    struct SmallFrame {
        /// Size of the original frame, to turn small-frame positions back into frame pixels.
        let frameWidth: Int
        let frameHeight: Int
        let width: Int
        let height: Int
        /// Gray values row by row, top row first.
        let pixels: [Float]

        init?(_ image: CGImage, maximumSide: Int = 320) {
            let scale = min(1, Double(maximumSide) / Double(max(image.width, image.height)))
            let width = max(2, Int((Double(image.width) * scale).rounded()))
            let height = max(2, Int((Double(image.height) * scale).rounded()))
            guard let small = image.smallGrayCopy(width: width, height: height),
                  let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ),
                  let data = context.data else { return nil }
            // With `bytesPerRow` equal to `width` the rows have no padding, so the buffer is the picture.
            context.draw(small, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height)
            self.frameWidth = image.width
            self.frameHeight = image.height
            self.width = width
            self.height = height
            self.pixels = vDSP.integerToFloatingPoint(bytes, floatingPointType: Float.self)
        }
    }

    static func isStable(_ first: CGImage, _ second: CGImage) -> Bool {
        guard first.width == second.width, first.height == second.height,
              let first = SmallFrame(first),
              let second = SmallFrame(second) else { return false }
        return vDSP.meanMagnitude(vDSP.subtract(first.pixels, second.pixels)) <= 1.5
    }

    /// The parts of the picture that differ between two frames of the same size, in frame pixels.
    /// Nearby changes are merged, so one scrolled list becomes one rectangle.
    static func changedRegions(from previous: SmallFrame, to current: SmallFrame) -> [CGRect] {
        guard previous.width == current.width, previous.height == current.height else { return [] }
        let width = current.width
        let height = current.height
        let differences = vDSP.subtract(previous.pixels, current.pixels)
        let changed = differences.map { abs($0) >= 10 }

        var boxes = connectedBoxes(of: changed, width: width, height: height)
        mergeNearbyBoxes(&boxes, distanceX: max(2, width / 32), distanceY: max(2, height / 32))

        let scaleX = CGFloat(current.frameWidth) / CGFloat(width)
        let scaleY = CGFloat(current.frameHeight) / CGFloat(height)
        return boxes.map { box in
            CGRect(x: box.minX * scaleX, y: box.minY * scaleY, width: box.width * scaleX, height: box.height * scaleY)
                .integral
                .intersection(CGRect(x: 0, y: 0, width: current.frameWidth, height: current.frameHeight))
        }
    }

    /// Bounding boxes of groups of touching changed pixels. Tiny groups (noise, a caret) are dropped.
    private static func connectedBoxes(of changed: [Bool], width: Int, height: Int) -> [CGRect] {
        var visited = [Bool](repeating: false, count: changed.count)
        var boxes: [CGRect] = []
        let minimumPixels = max(4, changed.count / 20_000)
        var queue: [Int] = []
        queue.reserveCapacity(changed.count)

        func visit(_ index: Int) {
            if changed[index] && !visited[index] {
                visited[index] = true
                queue.append(index)
            }
        }

        for start in changed.indices where changed[start] && !visited[start] {
            queue.removeAll(keepingCapacity: true)
            visit(start)
            var cursor = 0
            var minX = width, minY = height, maxX = 0, maxY = 0
            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                let x = index % width
                let y = index / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x + 1)
                maxY = max(maxY, y + 1)
                if x > 0 { visit(index - 1) }
                if x < width - 1 { visit(index + 1) }
                if y > 0 { visit(index - width) }
                if y < height - 1 { visit(index + width) }
            }
            if queue.count >= minimumPixels {
                boxes.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            }
        }
        return boxes
    }

    private static func mergeNearbyBoxes(_ boxes: inout [CGRect], distanceX: Int, distanceY: Int) {
        var didMerge = true
        while didMerge {
            didMerge = false
            search: for first in boxes.indices {
                for second in boxes.indices where second > first {
                    let grown = boxes[first].insetBy(dx: -CGFloat(distanceX), dy: -CGFloat(distanceY))
                    if grown.intersects(boxes[second]) {
                        boxes[first] = boxes[first].union(boxes[second])
                        boxes.remove(at: second)
                        didMerge = true
                        break search
                    }
                }
            }
        }
    }
}
