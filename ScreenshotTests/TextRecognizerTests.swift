import Testing
@testable import Screenshot

struct TextRecognizerTests {
    @Test(arguments: [
        // Short enough to read in one piece.
        (800, 900, [TextRecognizer.Strip(top: 0, height: 900, ownedHeight: 900)]),
        // A long chat: overlapping strips, each owning the rows up to where the next one starts.
        (1000, 2600, [
            TextRecognizer.Strip(top: 0, height: 1000, ownedHeight: 800),
            TextRecognizer.Strip(top: 800, height: 1000, ownedHeight: 800),
            TextRecognizer.Strip(top: 1600, height: 1000, ownedHeight: 1000)
        ])
    ])
    func longImagesAreReadInOverlappingStrips(width: Int, height: Int, expected: [TextRecognizer.Strip]) {
        #expect(TextRecognizer.strips(imageWidth: width, imageHeight: height) == expected)
    }
}
