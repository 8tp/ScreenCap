import Cocoa
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

class GIFExporter {
    static func exportToGIF(videoURL: URL, maxWidth: Int = 800, fps: Int = 20, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVAsset(url: videoURL)

        Task {
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
                DispatchQueue.main.async { completion(.failure(CaptureError.captureFailed)) }
                return
            }

            let size = try? await track.load(.naturalSize)
            let duration = try? await asset.load(.duration)

            guard let videoSize = size, let videoDuration = duration else {
                DispatchQueue.main.async { completion(.failure(CaptureError.captureFailed)) }
                return
            }

            let scale = min(CGFloat(maxWidth) / videoSize.width, 1.0)
            let outputSize = CGSize(width: round(videoSize.width * scale), height: round(videoSize.height * scale))

            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = outputSize
            generator.appliesPreferredTrackTransform = true
            // Tight timing tolerances for smooth, consistent frame timing
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 600)

            let totalSeconds = CMTimeGetSeconds(videoDuration)
            let frameCount = Int(totalSeconds * Double(fps))
            guard frameCount > 0 else {
                DispatchQueue.main.async { completion(.failure(CaptureError.captureFailed)) }
                return
            }

            let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")

            guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                DispatchQueue.main.async { completion(.failure(CaptureError.captureFailed)) }
                return
            }

            // Global GIF properties
            let gifProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: 0
                ]
            ]
            CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

            let frameDelay = 1.0 / Double(fps)
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay,
                    kCGImagePropertyGIFDelayTime as String: frameDelay,
                ]
            ]

            // Generate all frame times upfront for batch generation
            var times: [NSValue] = []
            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) * frameDelay, preferredTimescale: 600)
                times.append(NSValue(time: time))
            }

            // Extract frames sequentially with exact timing
            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) * frameDelay, preferredTimescale: 600)
                do {
                    let (image, _) = try await generator.image(at: time)
                    CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
                } catch {
                    continue
                }
            }

            if CGImageDestinationFinalize(destination) {
                DispatchQueue.main.async { completion(.success(gifURL)) }
            } else {
                DispatchQueue.main.async { completion(.failure(CaptureError.captureFailed)) }
            }
        }
    }
}
