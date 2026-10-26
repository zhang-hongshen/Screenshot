import SwiftUI

/// Live preview beside a scrolling capture: the picture so far, following and outlining the part
/// that is on screen now, with a hint when the user scrolls faster than frames can be joined.
struct ScrollCaptureThumbnailView: View {
    let state: ScrollCaptureControlState

    var body: some View {
        GeometryReader { proxy in
            if let image = state.previewImage {
                preview(of: image, in: proxy.size)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay(alignment: .bottom) {
            if state.isScrollingTooFast {
                Label("Scroll back a little, then slower", systemImage: "tortoise.fill")
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange, in: .rect(cornerRadius: 10))
                    .padding(10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live scrolling capture preview")
    }

    /// Shows the picture at the panel's width and moves it so the visible part stays in the middle.
    private func preview(of image: NSImage, in size: CGSize) -> some View {
        let scale = size.width / max(1, image.size.width)
        let displayHeight = image.size.height * scale
        let visibleRect = state.previewVisibleRect.map { rect in
            CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        }
        let centeredOffset = (visibleRect?.midY ?? displayHeight) - size.height / 2
        let offset = max(0, min(centeredOffset, displayHeight - size.height))

        return ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: displayHeight)

            if let visibleRect {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.tint, lineWidth: 2)
                    .frame(width: visibleRect.width, height: visibleRect.height)
                    .offset(x: visibleRect.minX, y: visibleRect.minY)
            }
        }
        .offset(y: -offset)
        .animation(.smooth(duration: 0.2), value: offset)
        .frame(width: size.width, height: size.height, alignment: displayHeight < size.height ? .center : .top)
        .clipShape(.rect(cornerRadius: 8))
    }
}
