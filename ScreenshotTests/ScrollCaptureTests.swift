import CoreGraphics
import Foundation
import Testing
@testable import Screenshot

struct ScrollCaptureTests {
    @Test(arguments: [
        (width: 800, height: 600, step: 330, isHorizontal: false),
        (width: 1400, height: 900, step: 517, isHorizontal: false),
        (width: 700, height: 500, step: 301, isHorizontal: true),
    ])
    func stitcherRebuildsScrolledContentExactly(width: Int, height: Int, step: Int, isHorizontal: Bool) {
        let steps = 4
        let source = isHorizontal
            ? Pattern(width: width + step * steps, height: height)
            : Pattern(width: width, height: height + step * steps)

        var stitcher = ScrollCaptureStitcher()
        for index in 0...steps {
            let offset = index * step
            let frame = isHorizontal
                ? source.crop(x: offset, y: 0, width: width, height: height)
                : source.crop(x: 0, y: offset, width: width, height: height)
            #expect(stitcher.append(frame.image) == .appended)
        }

        let result = Pattern(stitcher.makeImage()!)
        #expect(result == source)
    }

    /// Content scrolled up slides in under a translucent toolbar (Liquid Glass). The toolbar is kept
    /// once, from the topmost frame, instead of being repeated over every newly revealed strip.
    @Test func stitcherKeepsTranslucentToolbarOnce() throws {
        let document = Pattern(width: 400, height: 2000)
        let label = Pattern(width: 60, height: 20)
        let barHeight = 40

        func frame(offset: Int) -> Pattern {
            var frame = document.crop(x: 0, y: offset, width: 400, height: 600)
            frame.paste(frame.crop(x: 0, y: 0, width: 400, height: barHeight).frosted(), x: 0, y: 0)
            frame.paste(label, x: 170, y: 10)
            return frame
        }

        var stitcher = ScrollCaptureStitcher()
        for offset in [1000, 880, 760, 640] {
            #expect(stitcher.append(frame(offset: offset).image) == .appended)
        }

        let result = Pattern(stitcher.makeImage()!)
        try #require(result.height == barHeight + 920)
        #expect(result.crop(x: 0, y: 0, width: 400, height: barHeight) == frame(offset: 640).crop(x: 0, y: 0, width: 400, height: barHeight))
        #expect(result.crop(x: 0, y: barHeight, width: 400, height: 920) == document.crop(x: 0, y: 680, width: 400, height: 920))
    }

    /// Content scrolled down passes behind a translucent bar under it (the fade above a chat's
    /// input field). The bar shows what was behind it at the end, not the first screen's last lines.
    @Test func stitcherTakesBottomBarFromLastFrame() throws {
        let document = Pattern(width: 400, height: 2000)
        let barHeight = 40

        func frame(offset: Int) -> Pattern {
            var frame = document.crop(x: 0, y: offset, width: 400, height: 600)
            frame.paste(frame.crop(x: 0, y: 600 - barHeight, width: 400, height: barHeight).frosted(), x: 0, y: 600 - barHeight)
            return frame
        }

        var stitcher = ScrollCaptureStitcher()
        for offset in [0, 120, 240, 360] {
            #expect(stitcher.append(frame(offset: offset).image) == .appended)
        }

        let result = Pattern(stitcher.makeImage()!)
        try #require(result.height == 960)
        #expect(result.crop(x: 0, y: 0, width: 400, height: 920) == document.crop(x: 0, y: 0, width: 400, height: 920))
        #expect(result.crop(x: 0, y: 920, width: 400, height: barHeight) == frame(offset: 360).crop(x: 0, y: 560, width: 400, height: barHeight))
    }

    /// A "scroll to bottom" button floats over the content near the bottom. It is shown once, where
    /// the capture ended, instead of being repeated over every newly revealed strip.
    @Test func stitcherKeepsFloatingButtonOnce() {
        let document = Pattern(width: 400, height: 2000)
        let button = Pattern(width: 40, height: 30, gray: 200)
        let offsets = [0, 120, 240, 360, 480]

        func frame(offset: Int) -> Pattern {
            var frame = document.crop(x: 0, y: offset, width: 400, height: 600)
            frame.paste(button, x: 180, y: 520)
            return frame
        }

        var stitcher = ScrollCaptureStitcher()
        for offset in offsets {
            #expect(stitcher.append(frame(offset: offset).image) == .appended)
        }

        var expected = document.crop(x: 0, y: 0, width: 400, height: 1080)
        expected.paste(button, x: 180, y: 1000)
        #expect(Pattern(stitcher.makeImage()!) == expected)
    }

    /// A sidebar and a document scrolled one after the other end up side by side at full length,
    /// with the toolbar above them and the status bar moved below the longer one.
    @Test func canvasShowsEveryScrolledPaneAtFullLength() {
        let toolbar = Pattern(width: 800, height: 50)
        let statusBar = Pattern(width: 800, height: 30)
        let sidebar = Pattern(width: 200, height: 1300)
        let document = Pattern(width: 596, height: 2600)
        let viewportHeight = 420

        func window(sidebarOffset: Int, documentOffset: Int) -> CGImage {
            var window = Pattern(width: 800, height: 50 + viewportHeight + 30)
            window.paste(toolbar, x: 0, y: 0)
            window.paste(sidebar.crop(x: 0, y: sidebarOffset, width: 200, height: viewportHeight), x: 0, y: 50)
            window.paste(document.crop(x: 0, y: documentOffset, width: 596, height: viewportHeight), x: 204, y: 50)
            window.paste(statusBar, x: 0, y: 50 + viewportHeight)
            return window.image
        }

        var canvas = ScrollCaptureCanvas()
        canvas.add(window(sidebarOffset: 0, documentOffset: 0))
        for documentOffset in [260, 520, 780, 1040, 1300, 1560, 1820, 2080, 2180] {
            canvas.add(window(sidebarOffset: 0, documentOffset: documentOffset))
        }
        for sidebarOffset in [300, 600, 880] {
            canvas.add(window(sidebarOffset: sidebarOffset, documentOffset: 2180))
        }

        let result = Pattern(canvas.makeImage()!)
        #expect(result.width == 800)
        #expect(result.height == 50 + 2600 + 30)
        #expect(result.crop(x: 0, y: 0, width: 800, height: 50) == toolbar)
        #expect(result.crop(x: 204, y: 50, width: 596, height: 2600) == document)
        #expect(result.crop(x: 0, y: 50, width: 200, height: 1300) == sidebar)
        #expect(result.crop(x: 0, y: result.height - 30, width: 800, height: 30) == statusBar)
    }

    /// A sidebar longer than the chat beside it grows the window where the chat grows, so the
    /// input field under the chat keeps its size instead of being stretched.
    @Test func composerGrowsLongerSidebarWhereDocumentGrows() {
        let insertions = ExpandedWindowComposer.insertions(
            for: [(start: 50, end: 400, needed: 2000), (start: 50, end: 470, needed: 2500)],
            isPlain: { _ in true }
        )
        #expect(insertions == [ExpandedWindowComposer.Insertion(position: 400, length: 2500)])
    }

    /// A sparse view (two columns of icons on a white page, like Finder) is one area, not one per
    /// column of icons, and the sidebar beside it is not stretched.
    /// Frames as Chrome reports them for a log box at (0, 100, 600, 200) and a table at the same place.
    @Test(arguments: [
        (children: [CGRect(x: 2, y: 102, width: 580, height: 16), CGRect(x: 2, y: 299, width: 580, height: 1)], scrolls: true),
        (children: [CGRect(x: 0, y: 100, width: 2000, height: 1500)], scrolls: true),
        (children: [CGRect(x: 2, y: 102, width: 580, height: 16), CGRect(x: 2, y: 120, width: 580, height: 16)], scrolls: false),
    ])
    func webBoxIsFoundFromClippedChildren(children: [CGRect], scrolls: Bool) {
        let box = CGRect(x: 0, y: 100, width: 600, height: 200)
        #expect(ScrollArea.clipsContent(frame: box, childFrames: children) == scrolls)
    }

    /// Lines of a log box at (0, 100, 600, 200): one squeezed above, two on screen, two squeezed below.
    @Test(arguments: [
        (axis: ScrollAxis.vertical, forward: true, target: 3 as Int?),
        (axis: ScrollAxis.vertical, forward: false, target: 0 as Int?),
        (axis: ScrollAxis.horizontal, forward: true, target: nil as Int?),
    ])
    func revealShowsTheNextHiddenItem(axis: ScrollAxis, forward: Bool, target: Int?) {
        let items = [
            CGRect(x: 2, y: 100, width: 580, height: 1),
            CGRect(x: 2, y: 120, width: 580, height: 16),
            CGRect(x: 2, y: 140, width: 580, height: 16),
            CGRect(x: 2, y: 299, width: 580, height: 1),
            CGRect(x: 2, y: 299, width: 580, height: 1),
        ]
        let box = CGRect(x: 0, y: 100, width: 600, height: 200)
        #expect(ScrollArea.revealTarget(itemFrames: items, visible: box, axis: axis, forward: forward) == target)
    }

    @Test func canvasTreatsSparseViewAsOneArea() {
        let toolbar = Pattern(width: 800, height: 50)
        let sidebar = Pattern(width: 200, height: 420)
        let labels = Pattern(width: 80, height: 2600)
        var document = Pattern(width: 596, height: 2600, gray: 255)
        for top in stride(from: 20, to: 2500, by: 130) {
            for left in [100, 400] {
                document.paste(Pattern(width: 64, height: 64, gray: 90), x: left + 8, y: top)
                document.paste(labels.crop(x: 0, y: top + left / 10, width: 80, height: 14), x: left, y: top + 72)
            }
        }
        let viewportHeight = 420

        func window(documentOffset: Int) -> CGImage {
            var window = Pattern(width: 800, height: 50 + viewportHeight)
            window.paste(toolbar, x: 0, y: 0)
            window.paste(sidebar, x: 0, y: 50)
            window.paste(Pattern(width: 4, height: viewportHeight, gray: 128), x: 200, y: 50)
            window.paste(document.crop(x: 0, y: documentOffset, width: 596, height: viewportHeight), x: 204, y: 50)
            return window.image
        }

        var canvas = ScrollCaptureCanvas()
        canvas.add(window(documentOffset: 0))
        for documentOffset in stride(from: 90, through: 2180, by: 90) {
            canvas.add(window(documentOffset: documentOffset))
        }
        canvas.add(window(documentOffset: 2180))

        let result = Pattern(canvas.makeImage()!)
        #expect(result.width == 800)
        #expect(result.height == 50 + 2600)
        #expect(result.crop(x: 0, y: 0, width: 800, height: 50) == toolbar)
        #expect(result.crop(x: 204, y: 50, width: 596, height: 2600) == document)
        #expect(result.crop(x: 0, y: 50, width: 200, height: viewportHeight) == sidebar)
    }
}

/// A picture made of random gray blocks, so every position looks different, like real content.
private struct Pattern: Equatable {
    let width: Int
    let height: Int
    private var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        var generator = SeededGenerator(seed: UInt64(width * 31 + height))
        let blockColumns = width / 12 + 1
        let blocks = (0..<(blockColumns * (height / 12 + 1))).map { _ in UInt8.random(in: 0...255, using: &generator) }
        pixels = []
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let gray = blocks[(y / 12) * blockColumns + x / 12]
                pixels += [gray, gray, gray, 255]
            }
        }
    }

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        pixels = Array(UnsafeBufferPointer(start: bytes, count: width * height * 4))
    }

    /// A picture of one gray.
    init(width: Int, height: Int, gray: UInt8) {
        self.init(width: width, height: height, pixels: Array(repeating: [gray, gray, gray, 255], count: width * height).flatMap { $0 })
    }

    private init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    var image: CGImage {
        CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    func crop(x: Int, y: Int, width: Int, height: Int) -> Pattern {
        var cropped: [UInt8] = []
        for row in y..<(y + height) {
            let start = (row * self.width + x) * 4
            cropped += pixels[start..<(start + width * 4)]
        }
        return Pattern(width: width, height: height, pixels: cropped)
    }

    /// The picture seen through frosted glass: faded towards gray, but still following what is under it.
    func frosted() -> Pattern {
        let faded = pixels.enumerated().map { index, value in
            index % 4 == 3 ? value : UInt8((Int(value) + 2 * 128) / 3)
        }
        return Pattern(width: width, height: height, pixels: faded)
    }

    mutating func paste(_ other: Pattern, x: Int, y: Int) {
        for row in 0..<other.height {
            let source = row * other.width * 4
            let target = ((y + row) * width + x) * 4
            pixels.replaceSubrange(target..<(target + other.width * 4), with: other.pixels[source..<(source + other.width * 4)])
        }
    }
}

/// Makes the test pictures the same on every run (SplitMix64, which has no repeating patterns).
private struct SeededGenerator: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
