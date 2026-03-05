import Cocoa
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

class GIFExporter {
    static func exportToGIF(videoURL: URL, maxWidth: Int = 640, fps: Int = 15, completion: @escaping (Result<URL, Error>) -> Void) {
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
            let outputSize = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = outputSize
            generator.appliesPreferredTrackTransform = true

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

            let gifProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: 0
                ]
            ]
            CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

            let frameDelay = 1.0 / Double(fps)
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: frameDelay
                ]
            ]

            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) / Double(fps), preferredTimescale: 600)
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
