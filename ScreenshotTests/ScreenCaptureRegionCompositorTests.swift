import AppKit
import CoreGraphics
import Foundation
import PaperKit
import Testing
@testable import Screenshot

struct ScreenCaptureRegionCompositorTests {
    @Test func regionCompositionPreservesTopToBottomImageOrientation() throws {
        let source = try makeTestImage(
            width: 2,
            height: 2,
            pixels: [
                rgba(255, 0, 0), rgba(255, 0, 0),
                rgba(0, 0, 255), rgba(0, 0, 255)
            ]
        )

        let output = try ScreenCaptureRegionCompositor.compose(
            selection: CGRect(x: 0, y: 0, width: 2, height: 2),
            outputScale: 1,
            pieces: [
                ScreenCaptureRegionCompositor.Piece(
                    appKitRect: CGRect(x: 0, y: 0, width: 2, height: 2),
                    image: source
                )
            ]
        )

        let pixels = try rgbaPixels(from: output)
        #expect(pixels[0] == rgba(255, 0, 0))
        #expect(pixels[2] == rgba(0, 0, 255))
    }

    @Test func regionCompositionPlacesHigherAppKitRectAtTopOfOutput() throws {
        let top = try makeTestImage(
            width: 2,
            height: 1,
            pixels: [rgba(255, 0, 0), rgba(255, 0, 0)]
        )
        let bottom = try makeTestImage(
            width: 2,
            height: 1,
            pixels: [rgba(0, 0, 255), rgba(0, 0, 255)]
        )

        let output = try ScreenCaptureRegionCompositor.compose(
            selection: CGRect(x: 0, y: 0, width: 2, height: 2),
            outputScale: 1,
            pieces: [
                ScreenCaptureRegionCompositor.Piece(
                    appKitRect: CGRect(x: 0, y: 1, width: 2, height: 1),
                    image: top
                ),
                ScreenCaptureRegionCompositor.Piece(
                    appKitRect: CGRect(x: 0, y: 0, width: 2, height: 1),
                    image: bottom
                )
            ]
        )

        let pixels = try rgbaPixels(from: output)
        #expect(pixels[0] == rgba(255, 0, 0))
        #expect(pixels[2] == rgba(0, 0, 255))
    }

    @MainActor
    @Test func markupRendererPreservesBaseImageOrientation() async throws {
        let source = try makeTestImage(
            width: 2,
            height: 2,
            pixels: [
                rgba(255, 0, 0), rgba(255, 0, 0),
                rgba(0, 0, 255), rgba(0, 0, 255)
            ]
        )
        let image = NSImage(cgImage: source, size: CGSize(width: 2, height: 2))
        let snapshot = MarkupSnapshot(
            markup: PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 2, height: 2)),
            redactions: []
        )

        let result = try #require(await MarkupRenderer.shared.renderedImage(
            image: image,
            pixelatedImage: image,
            snapshot: snapshot
        ))
        var rect = CGRect(x: 0, y: 0, width: 2, height: 2)
        let cgImage = try #require(result.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let pixels = try rgbaPixels(from: cgImage)

        #expect(pixels[0] == rgba(255, 0, 0))
        #expect(pixels[2] == rgba(0, 0, 255))
    }
}

private func rgba(_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8 = 255) -> [UInt8] {
    [red, green, blue, alpha]
}

private func makeTestImage(width: Int, height: Int, pixels: [[UInt8]]) throws -> CGImage {
    let flatPixels = pixels.flatMap { $0 }
    let data = Data(flatPixels)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return try #require(CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
}

private func rgbaPixels(from image: CGImage) throws -> [[UInt8]] {
    let data = try #require(image.dataProvider?.data)
    let bytePointer = try #require(CFDataGetBytePtr(data))
    var pixels: [[UInt8]] = []

    for y in 0..<image.height {
        for x in 0..<image.width {
            let index = y * image.bytesPerRow + x * 4
            pixels.append([
                bytePointer[index],
                bytePointer[index + 1],
                bytePointer[index + 2],
                bytePointer[index + 3]
            ])
        }
    }

    return pixels
}
