import SwiftUI

/// One screenshot in the floating preview, with a close button that appears on hover.
struct CapturePreviewThumbnail: View {
    let image: NSImage
    let open: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)

            if isHovering {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Close")
                .padding(8)
                .transition(.opacity)
            }
        }
        .onHover { isHovering = $0 }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}
