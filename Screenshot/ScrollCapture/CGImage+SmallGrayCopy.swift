import CoreGraphics

nonisolated extension CGImage {
    /// A gray copy shrunk to `width` × `height` pixels, for comparing frames.
    ///
    /// Turning colour into gray means colour-matching every pixel, which takes tens of
    /// milliseconds for a full Retina frame. Shrinking in the frame's own colour space needs no
    /// matching, so the frame is shrunk first and only the small result is turned gray.
    func smallGrayCopy(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let ownColorSpace = colorSpace?.model == .rgb ? colorSpace : CGColorSpace(name: CGColorSpace.sRGB)
        guard let ownColorSpace,
              let colorContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: ownColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let grayContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        colorContext.interpolationQuality = .medium
        colorContext.draw(self, in: bounds)
        guard let small = colorContext.makeImage() else { return nil }
        grayContext.draw(small, in: bounds)
        return grayContext.makeImage()
    }
}
