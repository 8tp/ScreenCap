import Cocoa

class ScrollCapture {
    private var frames: [CGImage] = []
    private var captureRect: CGRect = .zero
    private var isCapturing = false
    private let scrollIncrement: CGFloat = 200
    private let maxFrames = 50
    var completion: ((Result<URL, Error>) -> Void)?

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion

        let selector = AreaSelector { [weak self] result in
            switch result {
            case .success(let rect):
                self?.captureRect = rect
                self?.beginScrollCapture()
            case .failure(let error):
                completion(.failure(error))
            }
        }
        selector.show()
    }

    private func beginScrollCapture() {
        frames.removeAll()
        isCapturing = true
        captureNextFrame()
    }

    private func captureNextFrame() {
        guard isCapturing, frames.count < maxFrames else {
            finishCapture()
            return
        }

        guard let image = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else {
            finishCapture()
            return
        }

        // Check if content stopped scrolling (identical to previous frame)
        if let lastFrame = frames.last, framesAreIdentical(lastFrame, image) {
            finishCapture()
            return
        }

        frames.append(image)

        // Send scroll event
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -Int32(scrollIncrement),
            wheel2: 0,
            wheel3: 0
        )
        let midPoint = CGPoint(x: captureRect.midX, y: captureRect.midY)
        scrollEvent?.location = midPoint
        scrollEvent?.post(tap: .cghidEventTap)

        // Wait for scroll to settle, then capture next frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.captureNextFrame()
        }
    }

    private func finishCapture() {
        isCapturing = false

        guard frames.count >= 2 else {
            if let frame = frames.first {
                do {
                    let url = try ImageUtilities.save(image: frame)
                    completion?(.success(url))
                } catch {
                    completion?(.failure(error))
                }
            } else {
                completion?(.failure(CaptureError.captureFailed))
            }
            return
        }

        // Stitch frames
        guard let stitched = stitchFrames() else {
            completion?(.failure(CaptureError.captureFailed))
            return
        }

        do {
            let url = try ImageUtilities.save(image: stitched)
            if Defaults.shared.copyToClipboard {
                ImageUtilities.copyToClipboard(image: stitched)
            }
            completion?(.success(url))
        } catch {
            completion?(.failure(error))
        }
    }

    private func stitchFrames() -> CGImage? {
        guard let first = frames.first else { return nil }

        let width = first.width
        var strips: [(CGImage, Int)] = [] // (image, yOffset after trimming overlap)
        var totalHeight = first.height

        strips.append((first, 0))

        for i in 1..<frames.count {
            let overlap = findOverlap(imageA: frames[i - 1], imageB: frames[i])
            let newHeight = frames[i].height - overlap
            guard newHeight > 0 else { continue }
            strips.append((frames[i], overlap))
            totalHeight += newHeight
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var y = totalHeight
        for (image, overlap) in strips {
            let drawHeight = image.height - overlap
            y -= drawHeight

            if overlap > 0, let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: drawHeight)) {
                context.draw(cropped, in: CGRect(x: 0, y: y, width: width, height: drawHeight))
            } else {
                context.draw(image, in: CGRect(x: 0, y: y, width: width, height: image.height))
            }
        }

        return context.makeImage()
    }

    private func findOverlap(imageA: CGImage, imageB: CGImage) -> Int {
        guard let dataA = imageA.dataProvider?.data,
              let dataB = imageB.dataProvider?.data else { return 0 }

        let ptrA = CFDataGetBytePtr(dataA)
        let ptrB = CFDataGetBytePtr(dataB)
        let bytesPerRowA = imageA.bytesPerRow
        let bytesPerRowB = imageB.bytesPerRow
        let width = min(imageA.width, imageB.width)
        let maxCheck = min(imageA.height, imageB.height) / 2

        for overlap in stride(from: 10, through: maxCheck, by: 2) {
            var match = true
            // Compare bottom `overlap` rows of A with top `overlap` rows of B
            let startRowA = imageA.height - overlap
            for row in 0..<min(overlap, 5) { // Sample 5 rows for speed
                let checkRow = row * overlap / 5
                let offsetA = (startRowA + checkRow) * bytesPerRowA
                let offsetB = checkRow * bytesPerRowB
                for col in stride(from: 0, to: width * 4, by: 16) { // Sample every 4th pixel
                    guard let a = ptrA, let b = ptrB else { match = false; break }
                    let diff = abs(Int(a[offsetA + col]) - Int(b[offsetB + col]))
                    if diff > 10 {
                        match = false
                        break
                    }
                }
                if !match { break }
            }
            if match { return overlap }
        }

        return 0
    }

    private func framesAreIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard let dataA = a.dataProvider?.data, let dataB = b.dataProvider?.data else { return false }
        guard CFDataGetLength(dataA) == CFDataGetLength(dataB) else { return false }

        let ptrA = CFDataGetBytePtr(dataA)
        let ptrB = CFDataGetBytePtr(dataB)
        let length = min(CFDataGetLength(dataA), a.bytesPerRow * 5) // Check first 5 rows

        guard let a = ptrA, let b = ptrB else { return false }
        return memcmp(a, b, length) == 0
    }
}
