import PaperKit
import SwiftUI

/// The markup tools: Select / Draw / Blur, pen, colour, shapes and text.
struct MarkupToolControls: View {
    @Bindable var bridge: MarkupEditorBridge

    var body: some View {
        HStack(spacing: 12) {
            toolPicker
            penMenu
            ColorPicker("Color", selection: $bridge.color, supportsOpacity: false)
                .labelsHidden()
                .fixedSize()
                .help("Color")
            shapesMenu
            Button("Text", systemImage: "character.textbox", action: bridge.insertTextBox)
                .help("Insert a text box")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .menuStyle(.button)
        .fixedSize()
    }

    private var toolPicker: some View {
        Picker("Markup Mode", selection: $bridge.tool) {
            Label("Select", systemImage: "cursorarrow").tag(MarkupTool.select)
            Label("Draw", systemImage: "pencil.tip").tag(MarkupTool.draw)
            Label("Blur", systemImage: "checkerboard.rectangle").tag(MarkupTool.blur)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Select, draw or blur")
    }

    private var penMenu: some View {
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
    }

    private var shapesMenu: some View {
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
    }
}
