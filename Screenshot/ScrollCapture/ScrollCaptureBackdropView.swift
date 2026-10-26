import SwiftUI

/// Dims the screen around a scrolling capture while leaving the captured area and the buttons clear.
struct ScrollCaptureBackdropView: View {
    let captureFrame: CGRect
    let captureMask: CGImage?
    let controlFrame: CGRect
    let screenFrame: CGRect

    var body: some View {
        GeometryReader { proxy in
            Color.black.opacity(0.45)
                .mask {
                    ZStack {
                        Rectangle().fill(.white)
                        captureCutout
                            .blendMode(.destinationOut)
                        if !captureFrame.intersects(controlFrame) {
                            Capsule()
                                .frame(width: controlFrame.width, height: controlFrame.height)
                                .position(
                                    x: overlayControlFrame.midX,
                                    y: overlayControlFrame.midY
                                )
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }

            captureOutline
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var captureCutout: some View {
        if let captureMask {
            Image(decorative: captureMask, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: captureFrame.width, height: captureFrame.height)
                .position(x: overlayCaptureFrame.midX, y: overlayCaptureFrame.midY)
        } else {
            Rectangle()
                .frame(width: captureFrame.width, height: captureFrame.height)
                .position(x: overlayCaptureFrame.midX, y: overlayCaptureFrame.midY)
        }
    }

    @ViewBuilder
    private var captureOutline: some View {
        if let captureMask {
            Image(decorative: captureMask, scale: 1)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.white.opacity(0.18))
                .frame(width: captureFrame.width, height: captureFrame.height)
                .position(x: overlayCaptureFrame.midX, y: overlayCaptureFrame.midY)
        } else {
            Rectangle()
                .stroke(.white, lineWidth: 2)
                .frame(width: captureFrame.width, height: captureFrame.height)
                .position(x: overlayCaptureFrame.midX, y: overlayCaptureFrame.midY)
        }
    }

    private var overlayCaptureFrame: CGRect {
        ScreenCoordinates.overlayRect(fromAppKit: captureFrame, on: screenFrame)
    }

    private var overlayControlFrame: CGRect {
        ScreenCoordinates.overlayRect(fromAppKit: controlFrame, on: screenFrame)
    }
}
