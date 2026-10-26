import SwiftUI

/// Lets the user drag the screenshots from the preview into place. Edges snap to each other;
/// the collage is the rectangle around all of them, and the space between stays transparent.
struct CollageEditorView: View {
    private let images: [NSImage]
    @State private var arrangement: CollageArrangement
    /// The collage's bounds when a drag began. The canvas keeps fitting these until the drag ends,
    /// so it does not zoom under the pointer while the collage grows.
    @State private var dragViewport: CGRect?
    @State private var dragStartOrigin: CGPoint?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// In points on screen.
    private static let snapDistance: CGFloat = 8

    init(images: [NSImage]) {
        self.images = images
        _arrangement = State(initialValue: CollageArrangement(sizes: images.map(Self.pixelSize)))
    }

    var body: some View {
        let bounds = arrangement.bounds
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let viewport = dragViewport ?? bounds
                let scale = min(
                    proxy.size.width / max(1, viewport.width),
                    proxy.size.height / max(1, viewport.height)
                )
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: bounds.width * scale, height: bounds.height * scale)
                        .offset(x: (bounds.minX - viewport.minX) * scale, y: (bounds.minY - viewport.minY) * scale)

                    ForEach(arrangement.pieces, id: \.imageIndex) { piece in
                        Image(nsImage: images[piece.imageIndex])
                            .resizable()
                            .frame(width: piece.frame.width * scale, height: piece.frame.height * scale)
                            .offset(
                                x: (piece.frame.minX - viewport.minX) * scale,
                                y: (piece.frame.minY - viewport.minY) * scale
                            )
                            .gesture(dragGesture(for: piece, scale: scale))
                    }
                }
                .frame(width: viewport.width * scale, height: viewport.height * scale, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.snappy, value: dragViewport)

            Text("\(Int(bounds.width)) × \(Int(bounds.height)) px")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    arrangement = CollageArrangement(sizes: images.map(Self.pixelSize))
                }
                .help("Put the screenshots side by side again")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Combine", systemImage: "checkmark", action: combine)
                    .buttonStyle(.glassProminent)
                    .help("Combine and open in the editor")
            }
        }
    }

    /// Measured in the window, not on the piece, because the piece moves under the pointer.
    private func dragGesture(for piece: CollageArrangement.Piece, scale: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                if dragStartOrigin == nil {
                    dragStartOrigin = piece.frame.origin
                    dragViewport = arrangement.bounds
                    arrangement.bringToFront(imageIndex: piece.imageIndex)
                }
                guard let start = dragStartOrigin else { return }
                arrangement.move(
                    imageIndex: piece.imageIndex,
                    to: CGPoint(
                        x: (start.x + value.translation.width / scale).rounded(),
                        y: (start.y + value.translation.height / scale).rounded()
                    ),
                    snapDistance: Self.snapDistance / scale
                )
            }
            .onEnded { _ in
                dragStartOrigin = nil
                dragViewport = nil
            }
    }

    private func combine() {
        guard let collage = CollageRenderer.image(of: images, arrangement: arrangement) else { return }
        CaptureResultManager.shared.openCollageInEditor(collage)
        openWindow(id: "markup-editor")
        dismissWindow()
    }

    /// Screenshots keep their pixels in their only representation; `size` is in points.
    private static func pixelSize(of image: NSImage) -> CGSize {
        guard let representation = image.representations.first else { return image.size }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}
