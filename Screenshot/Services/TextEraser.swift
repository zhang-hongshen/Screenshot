import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Removes detected text pixels locally, interpolating smooth backgrounds or borrowing nearby texture.
nonisolated enum TextEraser {
    private static let contextMargin: CGFloat = 80
    private static let textPadding: CGFloat = 2
    private static let textHeightPaddingFraction: CGFloat = 0.15
    private static let minimumStrokeContrast = 12
    private static let ruleColorTolerance = 16
    private static let ruleExtension = 4
    private static let textureSampleCount: CGFloat = 200
    private static let textureSampleMargin: CGFloat = 3
    private static let minimumTextureSamples = 8
    private static let smoothBackgroundTolerance = 6
    private static let patchSearchRadius = 72
    private static let patchSearchStep = 6

    private static let maximumCachedTiles = 32

    /// Incremental image changes and reusable repairs for the next brush movement.
    struct Update {
        let image: CGImage?
        let cachedPatches: [TextErasurePatch]
    }

    @concurrent
    static func erase(
        in image: CGImage,
        source: CGImage,
        strokes: [MarkupBrushStroke],
        cachedPatches: [TextErasurePatch],
        onUpdate: (@Sendable (CGImage) async -> Void)? = nil
    ) async throws -> Update {
        var cache = cachedPatches
        var currentImage = image
        var result: CGImage?
        for rect in tileRects(for: strokes, imageWidth: source.width, imageHeight: source.height) {
            try Task.checkCancellation()
            let patch: TextErasurePatch
            if let index = cache.firstIndex(where: { $0.rect == rect }) {
                patch = cache.remove(at: index)
            } else {
                patch = try await prepare(in: source, rect: rect)
            }
            cache.append(patch)
            if cache.count > maximumCachedTiles { cache.removeFirst() }
            if let updated = applying([patch], along: strokes, to: currentImage) {
                try Task.checkCancellation()
                currentImage = updated
                result = updated
                await onUpdate?(updated)
            }
        }
        try Task.checkCancellation()
        return Update(image: result, cachedPatches: cache)
    }

    private static func prepare(in image: CGImage, rect: CGRect) async throws -> TextErasurePatch {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let contextRect = rect.insetBy(dx: -contextMargin, dy: -contextMargin).intersection(bounds)
        guard let crop = image.cropping(to: contextRect) else {
            return TextErasurePatch(rect: rect, image: nil)
        }
        let input = try visionInput(for: crop)
        let request = DetectTextRectanglesRequest()
        var boxes: [CGRect] = []
        for observation in try await request.perform(on: input) {
            try Task.checkCancellation()
            let textRect = ScreenCoordinates.imageRect(
                fromVision: observation.boundingBox.cgRect,
                imageSize: CGSize(width: crop.width, height: crop.height)
            )
            // The detector can omit an end glyph; brush clipping still limits the actual repair.
            let horizontalPadding = max(textPadding, textRect.height)
            let verticalPadding = max(textPadding, (textRect.height * textHeightPaddingFraction).rounded(.up))
            boxes.append(textRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding).integral)
        }

        let localSelection = rect.offsetBy(dx: -contextRect.minX, dy: -contextRect.minY)
        guard boxes.contains(where: { $0.intersects(localSelection) }) else {
            return TextErasurePatch(rect: rect, image: nil)
        }
        // Include neighbouring text in the mask so it cannot become a texture donor.
        let repaired = try repair(
            image: crop, textRects: boxes, selection: CGRect(origin: .zero, size: contextRect.size)
        )
        return TextErasurePatch(rect: rect, image: repaired.cropping(to: localSelection))
    }

    private static func visionInput(for image: CGImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attributes, &buffer
        ) == kCVReturnSuccess, let buffer else { throw CocoaError(.coderInvalidValue) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { throw CocoaError(.coderInvalidValue) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    /// Detected rectangles only constrain the search; a pixel mask protects background and continuous rules.
    static func repair(
        image: CGImage,
        textRects: [CGRect],
        selection: CGRect
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = bitmapContext(width: width, height: height, data: bytes.baseAddress) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { throw CocoaError(.coderInvalidValue) }
        let original = pixels
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let selected = selection.intersection(bounds)
        var mask = [Bool](repeating: false, count: width * height)
        var regions: [CGRect] = []
        for textRect in textRects {
            try Task.checkCancellation()
            let rect = textRect.integral.intersection(bounds)
            guard rect.width > 0, rect.height > 0 else { continue }
            regions.append(rect)
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    guard selected.contains(point) else { continue }
                    let estimate = background(atX: x, y: y, rect: rect, pixels: original, width: width, height: height)
                    let offset = (y * width + x) * 4
                    var difference = 0
                    for channel in 0..<4 {
                        difference = max(difference, abs(Int(original[offset + channel]) - estimate[channel]))
                    }
                    if difference > minimumStrokeContrast,
                       !isRule(x: x, y: y, rect: rect, pixels: original, width: width, height: height) {
                        mask[y * width + x] = true
                    }
                }
            }
        }
        // Include antialiasing around strokes, without extending into neighbouring content or rules.
        let strokes = mask
        for rect in regions {
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) where !mask[y * width + x] {
                    let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    guard selected.contains(point) else { continue }
                    var touchesStroke = false
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let adjacentX = min(width - 1, max(0, x + dx))
                            let adjacentY = min(height - 1, max(0, y + dy))
                            if strokes[adjacentY * width + adjacentX] { touchesStroke = true }
                        }
                    }
                    if touchesStroke,
                       !isRule(x: x, y: y, rect: rect, pixels: original, width: width, height: height) {
                        mask[y * width + x] = true
                    }
                }
            }
        }
        for rect in regions {
            try Task.checkCancellation()
            let donor = try textureOffset(rect: rect, pixels: original, mask: mask, width: width, height: height)
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) where mask[y * width + x] {
                    let offset = (y * width + x) * 4
                    if let donor {
                        let source = ((y + donor.y) * width + x + donor.x) * 4
                        for channel in 0..<4 { pixels[offset + channel] = original[source + channel] }
                    } else {
                        let estimate = background(
                            atX: x, y: y, rect: rect, pixels: original, width: width, height: height
                        )
                        for channel in 0..<4 { pixels[offset + channel] = UInt8(clamping: estimate[channel]) }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let result = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw CocoaError(.coderInvalidValue) }
        return result
    }

    private static func background(
        atX x: Int, y: Int, rect: CGRect, pixels: [UInt8], width: Int, height: Int
    ) -> [Int] {
        let top = max(0, Int(rect.minY) - 1)
        let bottom = min(height - 1, Int(rect.maxY))
        let fraction = Double(y - top) / Double(max(1, bottom - top))
        return (0..<4).map { channel in
            let first = Double(pixels[(top * width + x) * 4 + channel])
            let last = Double(pixels[(bottom * width + x) * 4 + channel])
            return Int((first + (last - first) * fraction).rounded())
        }
    }

    private static func isRule(
        x: Int, y: Int, rect: CGRect, pixels: [UInt8], width: Int, height: Int
    ) -> Bool {
        let center = (y * width + x) * 4
        // A table rule continues beyond both ends of the text box with the same colour.
        for horizontal in [true, false] {
            let lower = horizontal ? Int(rect.minX) - ruleExtension : Int(rect.minY) - ruleExtension
            let upper = horizontal ? Int(rect.maxX) + ruleExtension : Int(rect.maxY) + ruleExtension
            guard lower >= 0, upper < (horizontal ? width : height) else { continue }
            var matches = true
            for position in lower...upper {
                let offset = (horizontal ? y * width + position : position * width + x) * 4
                for channel in 0..<4
                    where abs(Int(pixels[offset + channel]) - Int(pixels[center + channel])) > ruleColorTolerance {
                    matches = false
                    break
                }
                if !matches { break }
            }
            if matches { return true }
        }
        return false
    }

    /// Chooses an unmasked nearby patch by its agreement with the surviving background pixels.
    private static func textureOffset(
        rect: CGRect, pixels: [UInt8], mask: [Bool], width: Int, height: Int
    ) throws -> (x: Int, y: Int)? {
        let sampleStep = max(1, Int(sqrt(rect.width * rect.height / textureSampleCount)))
        var samples: [(x: Int, y: Int)] = []
        var interpolationErrors: [Int] = []
        let sampleRect = rect.insetBy(dx: -textureSampleMargin, dy: -textureSampleMargin).intersection(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        for y in stride(from: Int(sampleRect.minY), to: Int(sampleRect.maxY), by: sampleStep) {
            for x in stride(from: Int(sampleRect.minX), to: Int(sampleRect.maxX), by: sampleStep)
                where !mask[y * width + x] {
                samples.append((x, y))
                let estimate = background(atX: x, y: y, rect: rect, pixels: pixels, width: width, height: height)
                var error = 0
                for channel in 0..<3 {
                    error += abs(Int(pixels[(y * width + x) * 4 + channel]) - estimate[channel])
                }
                interpolationErrors.append(error / 3)
            }
        }
        guard samples.count >= minimumTextureSamples else { return nil }
        interpolationErrors.sort()
        guard interpolationErrors[interpolationErrors.count / 2] > smoothBackgroundTolerance else { return nil }
        var best: (x: Int, y: Int)?
        var bestError = Double.greatestFiniteMagnitude
        for dy in stride(from: -patchSearchRadius, through: patchSearchRadius, by: patchSearchStep) {
            try Task.checkCancellation()
            for dx in stride(from: -patchSearchRadius, through: patchSearchRadius, by: patchSearchStep) {
                guard abs(dx) >= Int(rect.width) || abs(dy) >= Int(rect.height),
                      sampleRect.minX + CGFloat(dx) >= 0, sampleRect.maxX + CGFloat(dx) <= CGFloat(width),
                      sampleRect.minY + CGFloat(dy) >= 0,
                      sampleRect.maxY + CGFloat(dy) <= CGFloat(height) else { continue }
                var error = 0
                var isClean = true
                for y in Int(rect.minY)..<Int(rect.maxY) {
                    for x in Int(rect.minX)..<Int(rect.maxX) where mask[(y + dy) * width + x + dx] {
                        isClean = false
                        break
                    }
                    if !isClean { break }
                }
                guard isClean else { continue }
                for sample in samples {
                    let first = (sample.y * width + sample.x) * 4
                    let second = ((sample.y + dy) * width + sample.x + dx) * 4
                    for channel in 0..<4 { error += abs(Int(pixels[first + channel]) - Int(pixels[second + channel])) }
                }
                let score = Double(error) / Double(samples.count * 4)
                if score < bestError {
                    bestError = score
                    best = (dx, dy)
                }
            }
        }
        return best
    }

    static func bitmapContext(
        width: Int,
        height: Int,
        data: UnsafeMutableRawPointer? = nil,
        colorSpace: CGColorSpace? = nil
    ) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
