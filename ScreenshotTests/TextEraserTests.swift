import CoreGraphics
import Foundation
import Testing
@testable import Screenshot

/// Verifies background reconstruction independently of Vision's text detection.
struct TextEraserTests {
    @Test(arguments: [0, 1, 2, 3])
    func reconstructsBackgroundAndPreservesRules(style: Int) throws {
        let width = 120
        let height = 96
        let rect = CGRect(x: 28, y: 24, width: 38, height: 24)
        var background = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: Int
                switch style {
                case 1: value = 100 + y
                case 2: value = 80 + (x % 6) * 8 + (y % 6) * 6
                case 3: value = 70 + y / 2
                default: value = 180
                }
                let isRule = y == 35 || x == 48
                let isIcon = x < 12 && y < 12
                let offset = (y * width + x) * 4
                for channel in 0..<3 { background[offset + channel] = UInt8(isRule || isIcon ? 10 : value) }
                background[offset + 3] = style == 3 ? 160 : 255
            }
        }
        var text = background
        for y in 28..<44 {
            for x in 32..<61 where x % 7 < 3 {
                let offset = (y * width + x) * 4
                for channel in 0..<3 { text[offset + channel] = 10 }
            }
        }
        let image = try makeImage(text, width: width, height: height)
        let result = try TextEraser.repair(image: image, textRects: [rect], selection: rect)
        let output = try #require(result.dataProvider?.data) as Data
        // The synthetic texture repeats every six pixels, so a matching donor is exact.
        let greatestError = background.indices.map { abs(Int(output[$0]) - Int(background[$0])) }.max() ?? 0
        #expect(greatestError <= 1)
    }

    @Test func changesOnlySelectedPixels() throws {
        let width = 80
        let height = 80
        var pixels = [UInt8](repeating: 220, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        for y in 25..<45 {
            for x in 25..<45 {
                for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = 0 }
            }
        }
        let selection = CGRect(x: 30, y: 20, width: 10, height: 30)
        let image = try makeImage(pixels, width: width, height: height)
        let repaired = try TextEraser.repair(
            image: image, textRects: [CGRect(x: 20, y: 20, width: 30, height: 30)], selection: selection
        )
        let output = try #require(repaired.dataProvider?.data) as Data
        var changed = false
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if selection.contains(CGPoint(x: x, y: y)) {
                    if output[offset] != pixels[offset] { changed = true }
                } else {
                    for channel in 0..<4 { #expect(output[offset + channel] == pixels[offset + channel]) }
                }
            }
        }
        #expect(changed)
    }

    @Test(arguments: [16, 32, 64, 96])
    func cachedRepairsAccumulateWhileRespectingBrushSize(diameter: Int) async throws {
        let width = 256
        let height = 128
        var original = [UInt8](repeating: 220, count: width * height * 4)
        for index in stride(from: 3, to: original.count, by: 4) { original[index] = 255 }
        let background = original
        for center in [64, 192] {
            for y in 44..<84 {
                for x in (center - 20)..<(center + 20) {
                    for channel in 0..<3 { original[(y * width + x) * 4 + channel] = 0 }
                }
            }
        }
        let source = try makeImage(original, width: width, height: height)
        let patch = TextErasurePatch(
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            image: try makeImage(background, width: width, height: height)
        )
        let first = MarkupBrushStroke(points: [CGPoint(x: 64, y: 64)], radius: CGFloat(diameter) / 2)
        let second = MarkupBrushStroke(points: [CGPoint(x: 192, y: 64)], radius: CGFloat(diameter) / 2)
        let progress = ErasureProgress()
        let firstUpdate = try await TextEraser.erase(
            in: source, source: source, strokes: [first], cachedPatches: [patch]
        ) { _ in
            await progress.record()
        }
        #expect(await progress.count == 1)
        let firstImage = try #require(firstUpdate.image)
        let firstPixels = try #require(firstImage.dataProvider?.data) as Data
        #expect(firstPixels[(64 * width + 64) * 4] == 220)
        #expect(firstPixels[(64 * width + 192) * 4] == 0)
        let secondUpdate = try await TextEraser.erase(
            in: firstImage, source: source, strokes: [second], cachedPatches: firstUpdate.cachedPatches
        )
        let result = try #require(secondUpdate.image)
        let output = try #require(result.dataProvider?.data) as Data
        #expect(output[(64 * width + 64) * 4] == 220)
        #expect(output[(64 * width + 192) * 4] == 220)
        var changedOutsideBrushes = false
        for y in 0..<height {
            for x in 0..<width {
                // Antialiasing can affect a pixel whose square intersects the circular brush.
                let nearestY = min(max(64, CGFloat(y)), CGFloat(y + 1))
                let firstX = min(max(64, CGFloat(x)), CGFloat(x + 1))
                let secondX = min(max(192, CGFloat(x)), CGFloat(x + 1))
                let distance = min(hypot(firstX - 64, nearestY - 64), hypot(secondX - 192, nearestY - 64))
                if distance > CGFloat(diameter) / 2 + 0.1,
                   output[(y * width + x) * 4] != original[(y * width + x) * 4] {
                    changedOutsideBrushes = true
                }
            }
        }
        #expect(!changedOutsideBrushes)
        #expect(secondUpdate.cachedPatches.count == 1)
    }

    @Test func patchPlacementPreservesTransparency() throws {
        let width = 40
        let height = 30
        let original = [UInt8](repeating: 160, count: width * height * 4)
        let rect = CGRect(x: 8, y: 3, width: 12, height: 9)
        let patchPixels = [UInt8](repeating: 80, count: 12 * 9 * 4)
        let image = try makeImage(original, width: width, height: height)
        let patch = try makeImage(patchPixels, width: 12, height: 9)
        let result = try #require(TextEraser.applying(
            [TextErasurePatch(rect: rect, image: patch)],
            along: [MarkupBrushStroke(points: [CGPoint(x: 20, y: 15)], radius: 100)],
            to: image
        ))
        let output = try #require(result.dataProvider?.data) as Data
        for y in 0..<height {
            for x in 0..<width {
                let expected: UInt8 = rect.contains(CGPoint(x: x, y: y)) ? 80 : 160
                for channel in 0..<4 { #expect(output[(y * width + x) * 4 + channel] == expected) }
            }
        }
    }

    private func makeImage(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}

/// Counts partial repairs emitted before the whole brush batch finishes.
private actor ErasureProgress {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
