import PaperKit
import SwiftUI

/// The markup tools, including the text eraser, pen, colour, shapes and text.
struct MarkupToolControls: View {
    @Bindable var bridge: MarkupEditorBridge

    var body: some View {
        HStack(spacing: 12) {
            toolPicker
            if bridge.tool == .blur || bridge.tool == .eraseText, let session = bridge.document?.imageEdits {
                MarkupBrushControls(session: session)
            }
            penMenu
            MarkupColorWell(color: $bridge.color)
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
            Label("Select", systemImage: MarkupTool.select.systemImage).tag(MarkupTool.select)
            Label("Draw", systemImage: MarkupTool.draw.systemImage).tag(MarkupTool.draw)
            Label("Mosaic", systemImage: MarkupTool.blur.systemImage).tag(MarkupTool.blur)
            Label("Erase Text", systemImage: MarkupTool.eraseText.systemImage).tag(MarkupTool.eraseText)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Select, draw, mosaic or erase text")
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
