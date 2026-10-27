import CoreGraphics
import Vision

/// Finds the text in a screenshot with Vision, line by line, in reading order.
nonisolated enum TextRecognizer {
    /// One horizontal band of the image. Lines whose centre falls in its first `ownedHeight`
    /// rows belong to it; the rest overlaps the next strip, so a line cut at the strip's
    /// bottom edge is read whole by the next one.
    struct Strip: Equatable {
        let top: Int
        let height: Int
        let ownedHeight: Int
    }

    /// Vision shrinks a picture before reading it, so a long scrolling capture is read in
    /// roughly square strips; read in one piece its text would become too small to recognise.
    static let minimumStripHeight = 1000
    static let stripOverlap = 200

    @concurrent
    static func text(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        var lines: [String] = []
        for strip in strips(imageWidth: image.width, imageHeight: image.height) {
            let stripRect = CGRect(x: 0, y: strip.top, width: image.width, height: strip.height)
            guard let stripImage = image.cropping(to: stripRect) else { continue }

            for observation in try await request.perform(on: stripImage) {
                // Vision measures from the bottom left, as a fraction of the strip.
                let centerFromTop = (1 - observation.boundingBox.cgRect.midY) * CGFloat(strip.height)
                if centerFromTop < CGFloat(strip.ownedHeight) {
                    lines.append(observation.transcript)
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func strips(imageWidth: Int, imageHeight: Int) -> [Strip] {
        let stripHeight = max(imageWidth, minimumStripHeight)
        let step = stripHeight - stripOverlap
        var strips: [Strip] = []
        var top = 0
        while top + stripHeight < imageHeight {
            strips.append(Strip(top: top, height: stripHeight, ownedHeight: step))
            top += step
        }
        strips.append(Strip(top: top, height: imageHeight - top, ownedHeight: imageHeight - top))
        return strips
    }
}
