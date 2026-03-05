import Cocoa
import Vision

class OCRTool {
    func captureAndRecognize(completion: @escaping (Result<String, Error>) -> Void) {
        let selector = AreaSelector { result in
            switch result {
            case .success(let rect):
                guard let image = CGWindowListCreateImage(
                    rect,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.nominalResolution]
                ) else {
                    completion(.failure(CaptureError.captureFailed))
                    return
                }
                self.recognizeText(in: image, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
        selector.show()
    }

    private func recognizeText(in image: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let text = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""

            DispatchQueue.main.async {
                if text.isEmpty {
                    completion(.failure(CaptureError.captureFailed))
                } else {
                    // Copy to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    completion(.success(text))
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
