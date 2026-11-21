import SwiftUI

/// The named size menu shared by mosaic and text-erasing brushes.
struct MarkupBrushControls: View {
    @Bindable var session: MarkupImageSession

    var body: some View {
        Menu {
            Picker("Brush Size", selection: $session.brushSize) {
                ForEach(MarkupBrushSize.allCases, id: \.self) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(session.brushSize.title)
        }
        .help("Brush size")
    }
}
