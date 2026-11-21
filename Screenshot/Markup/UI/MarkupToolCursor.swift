import AppKit
import SwiftUI

/// Renders mosaic blocks or the eraser symbol as the actual AppKit pointer.
struct MarkupToolCursor: View {
    let tool: MarkupTool
    let diameter: CGFloat

    var body: some View {
        Group {
            if tool == .blur {
                Canvas { context, size in
                    let shades: [Double] = [
                        0.25, 0.75, 0.45, 0.90,
                        0.60, 0.35, 0.85, 0.50,
                        0.80, 0.55, 0.20, 0.70,
                        0.40, 0.90, 0.65, 0.30
                    ]
                    let cellSize = size.width / 4
                    for row in 0..<4 {
                        for column in 0..<4 {
                            let rect = CGRect(
                                x: CGFloat(column) * cellSize,
                                y: CGFloat(row) * cellSize,
                                width: cellSize,
                                height: cellSize
                            )
                            context.fill(Path(rect), with: .color(Color(white: shades[row * 4 + column])))
                        }
                    }
                }
                .overlay { Rectangle().stroke(.black, lineWidth: 1) }
            } else {
                Image(systemName: tool.systemImage)
                    .resizable()
                    .aspectRatio(nil, contentMode: .fit)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 1)
            }
        }
        .frame(width: diameter, height: diameter)
        .padding(2)
    }

    static func cursor(tool: MarkupTool, diameter: CGFloat) -> NSCursor? {
        let renderer = ImageRenderer(content: MarkupToolCursor(tool: tool, diameter: diameter))
        renderer.scale = 2
        guard let pixels = renderer.cgImage else { return nil }
        let size = CGSize(
            width: CGFloat(pixels.width) / renderer.scale,
            height: CGFloat(pixels.height) / renderer.scale
        )
        return NSCursor(
            image: NSImage(cgImage: pixels, size: size),
            hotSpot: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }
}
