import PaperKit
import SwiftUI

/// The markup tools: Select / Draw / Blur, pen, colour, shapes and text.
///
/// The body is a plain list of controls without a container, so a window toolbar
/// shows each one as its own native item, and the capture overlay lays them out in a row.
struct MarkupToolControls: View {
    @Bindable var bridge: MarkupEditorBridge

    var body: some View {
        Picker("Tool", selection: $bridge.tool) {
            Label("Select", systemImage: "cursorarrow").tag(MarkupTool.select)
            Label("Draw", systemImage: "pencil.tip").tag(MarkupTool.draw)
            Label("Blur", systemImage: "checkerboard.rectangle").tag(MarkupTool.blur)
        }
        .pickerStyle(.segmented)
        .help("Select, draw or blur")

        Menu {
            Picker("Pen", selection: $bridge.ink) {
                ForEach(MarkupInk.allCases, id: \.self) { ink in
                    Label(ink.title, systemImage: ink.systemImage).tag(ink)
                }
            }
            .pickerStyle(.inline)

            Picker("Line Width", selection: $bridge.lineWidth) {
                ForEach(MarkupLineWidth.allCases, id: \.self) { width in
                    Text(width.title).tag(width)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(bridge.ink.title, systemImage: bridge.ink.systemImage)
        }
        .help("Pen and line width")

        ColorPicker("Color", selection: $bridge.color, supportsOpacity: false)
            .labelsHidden()
            .help("Color")

        Menu {
            Button("Rectangle", systemImage: "rectangle") { bridge.insert(.rectangle) }
            Button("Rounded Rectangle", systemImage: "app") { bridge.insert(.roundedRectangle) }
            Button("Oval", systemImage: "circle") { bridge.insert(.ellipse) }
            Button("Star", systemImage: "star") { bridge.insert(.star) }
            Button("Speech Bubble", systemImage: "bubble.left") { bridge.insert(.chatBubble) }
            Divider()
            Button("Line", systemImage: "line.diagonal") { bridge.insertLine(withArrow: false) }
            Button("Arrow", systemImage: "arrow.up.right") { bridge.insertLine(withArrow: true) }
        } label: {
            Label("Shapes", systemImage: "square.on.circle")
        }
        .help("Insert a shape")

        Button("Text", systemImage: "character.textbox", action: bridge.insertTextBox)
            .help("Insert a text box")
    }
}
