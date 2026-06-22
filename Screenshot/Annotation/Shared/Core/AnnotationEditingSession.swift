import Observation
import SwiftUI

@MainActor
@Observable
final class AnnotationEditingSession {
    var selectedTool: AnnotationTool = .select
    var selectedShape: ShapeType = .rectangle
    var draft: Annotation?
    var color: Color = .red
    var lineWidth: CGFloat = 4
    var fontFamily = "Helvetica"
    var fontSize: CGFloat = 24
    var fontWeight: Font.Weight = .regular
    var textDraft = ""
    var textPosition: CGPoint?
    var selectedAnnotationIDs: Set<UUID> = []
    var selectionRect: CGRect?

    let document = AnnotationDocument()

    var allAnnotations: [Annotation] {
        document.annotations + (draft.map { [$0] } ?? [])
    }

    func addText() {
        let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let textPosition, !text.isEmpty else {
            self.textPosition = nil
            return
        }
        document.add(.text(TextAnnotation(
            text: text,
            position: textPosition,
            fontSize: fontSize,
            fontFamily: fontFamily,
            fontWeight: fontWeight,
            color: color
        )))
        self.textPosition = nil
    }

    func cancelText() {
        textDraft = ""
        textPosition = nil
    }

    @discardableResult
    func deleteSelection() -> Bool {
        guard textPosition == nil, !selectedAnnotationIDs.isEmpty else { return false }
        document.remove(ids: selectedAnnotationIDs)
        selectedAnnotationIDs.removeAll()
        return true
    }

    @discardableResult
    func selectAllAnnotations() -> Bool {
        guard selectedTool == .select,
              textPosition == nil,
              !document.annotations.isEmpty else { return false }
        selectedAnnotationIDs = Set(document.annotations.map(\.id))
        return true
    }

    func undo() {
        document.undo()
        pruneSelection()
    }

    func redo() {
        document.redo()
        pruneSelection()
    }

    func updateSelectedColor(_ value: Color) {
        updateSelection { $0.applyingColor(value) }
    }

    func updateSelectedLineWidth(_ value: CGFloat) {
        updateSelection { $0.applyingLineWidth(value) }
    }

    func updateSelectedShape(_ value: ShapeType) {
        updateSelection { $0.applyingShapeType(value) }
    }

    func updateSelectedFontFamily(_ value: String) {
        updateSelection { $0.applyingFontFamily(value) }
    }

    func updateSelectedFontSize(_ value: CGFloat) {
        updateSelection { $0.applyingFontSize(value) }
    }

    func updateSelectedFontWeight(_ value: Font.Weight) {
        updateSelection { $0.applyingFontWeight(value) }
    }

    private func pruneSelection() {
        let existingIDs = Set(document.annotations.map(\.id))
        selectedAnnotationIDs.formIntersection(existingIDs)
    }

    private func updateSelection(transform: (Annotation) -> Annotation) {
        guard !selectedAnnotationIDs.isEmpty else { return }
        document.update(ids: selectedAnnotationIDs, transform: transform)
    }
}
