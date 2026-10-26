import SwiftUI

/// Tints the window under the pointer, following its real shape when its alpha mask is known.
struct WindowHighlightView: View {
    let frame: CGRect
    let screenFrame: CGRect
    let mask: CGImage?

    var body: some View {
        GeometryReader { _ in
            Color.accentColor.opacity(0.5)
            .frame(
                width: overlayFrame.width,
                height: overlayFrame.height
            )
            .mask {
                if let mask {
                    Image(decorative: mask, scale: 1)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                }
            }
            .position(x: overlayFrame.midX, y: overlayFrame.midY)
        }
    }

    private var overlayFrame: CGRect {
        ScreenCoordinates.overlayRect(fromAppKit: frame, on: screenFrame)
    }
}

/// Dims everything outside a selected window while it is being marked up.
struct WindowEditingSelectionView: View {
    let frame: CGRect
    let screenFrame: CGRect
    let mask: CGImage

    var body: some View {
        GeometryReader { _ in
            Color.black.opacity(0.45)
                .mask {
                    ZStack {
                        Rectangle().fill(.white)
                        Image(decorative: mask, scale: 1)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(position)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }

            Image(decorative: mask, scale: 1)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.white.opacity(0.16))
                .frame(width: overlayFrame.width, height: overlayFrame.height)
                .position(position)
        }
        .allowsHitTesting(false)
    }

    private var overlayFrame: CGRect {
        ScreenCoordinates.overlayRect(fromAppKit: frame, on: screenFrame)
    }

    private var position: CGPoint {
        CGPoint(x: overlayFrame.midX, y: overlayFrame.midY)
    }
}
