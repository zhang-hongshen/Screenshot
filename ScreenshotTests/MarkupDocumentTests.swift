import CoreGraphics
import Testing
@testable import Screenshot

struct MarkupDocumentTests {
    @MainActor
    @Test func redactionCreationNormalizesDragRect() {
        let document = MarkupDocument(imageSize: CGSize(width: 400, height: 300))

        document.addRedaction(from: CGPoint(x: 120, y: 90), to: CGPoint(x: 40, y: 20))

        #expect(document.redactions.count == 1)
        #expect(document.redactions[0].rect == CGRect(x: 40, y: 20, width: 80, height: 70))
    }

    @MainActor
    @Test func selectedRedactionsCanBeDeleted() throws {
        let document = MarkupDocument(imageSize: CGSize(width: 400, height: 300))
        document.addRedaction(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 120))
        let id = try #require(document.redactions.first?.id)

        document.selectedRedactionIDs = [id]
        document.deleteSelectedRedactions()

        #expect(document.redactions.isEmpty)
        #expect(document.selectedRedactionIDs.isEmpty)
    }


    @MainActor
    @Test func deleteKeyIsHandledOnlyForSelectedBlurRegions() {
        let document = MarkupDocument(imageSize: CGSize(width: 400, height: 300))

        #expect(document.handleDeleteKey() == false)

        document.addRedaction(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 80))
        #expect(document.handleDeleteKey() == false)
        #expect(document.redactions.count == 1)

        document.isRedactionMode = true
        #expect(document.handleDeleteKey() == true)
        #expect(document.redactions.isEmpty)
    }
}
