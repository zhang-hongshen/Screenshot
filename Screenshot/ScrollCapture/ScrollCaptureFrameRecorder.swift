#if DEBUG
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Debug builds only: saves every frame of a scrolling capture as a PNG, so a capture that was
/// stitched wrongly can be replayed frame by frame outside the app.
///
/// The frames go to the app's Caches folder (inside its sandbox container); the folder is printed
/// to the console when a capture starts.
final class ScrollCaptureFrameRecorder {
    private let folder: URL
    private var frameCount = 0

    init?() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let name = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        folder = caches.appending(path: "ScrollCaptureFrames/\(name)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        print("Scrolling capture frames: \(folder.path)")
    }

    func save(_ frame: CGImage) {
        frameCount += 1
        // Numbered here, on the main actor, so the files keep the capture order however the writes finish.
        save(frame, named: String(format: "frame-%04d.png", frameCount))
    }

    /// Saves what Auto made, so it can be looked at outside the app.
    func saveAutomaticResult(_ image: CGImage) {
        save(image, named: "auto-result.png")
    }

    private func save(_ image: CGImage, named name: String) {
        let url = folder.appending(path: name)
        Task { await Self.write(image, to: url) }
    }

    /// Encoding a Retina frame as PNG takes tens of milliseconds, so it runs off the main thread.
    @concurrent
    nonisolated private static func write(_ frame: CGImage, to url: URL) async {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, frame, nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
