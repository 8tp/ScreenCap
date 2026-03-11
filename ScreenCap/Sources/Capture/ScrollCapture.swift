import Cocoa

class ScrollCapture {
    private var frames: [CGImage] = []
    private var captureRect: CGRect = .zero
    private var isCapturing = false
    private var captureTimer: Timer?
    private var activeAreaSelector: AreaSelector?
    private var doneWindow: NSWindow?
    private var borderWindow: NSWindow?
    private var escMonitor: Any?
    var completion: ((Result<URL, Error>) -> Void)?

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion

        let selector = AreaSelector { [weak self] result in
            self?.activeAreaSelector = nil
            switch result {
            case .success(let (rect, _)):
                self?.captureRect = rect
                self?.beginManualCapture()
            case .failure(let error):
                completion(.failure(error))
            }
        }
        activeAreaSelector = selector
        selector.show()
    }

    private func beginManualCapture() {
        frames.removeAll()
        isCapturing = true

        let ph = NSScreen.primaryHeight
        let nsRect = NSRect(
            x: captureRect.origin.x,
            y: ph - captureRect.origin.y - captureRect.height,
            width: captureRect.width,
            height: captureRect.height
        )

        showBorderOverlay(nsRect: nsRect)
        showDoneButton(nsRect: nsRect)

        // Capture first frame after a short delay (let overlays settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureFrame()
        }

        // 2fps — fast enough to catch scroll content, slow enough to have meaningful differences
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
    }

    private func captureFrame() {
        guard isCapturing else { return }

        guard let image = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return }

        // Only keep if content actually changed
        if let lastFrame = frames.last, framesAreIdentical(lastFrame, image) {
            return
        }

        frames.append(image)
    }

    // MARK: - UI

    private func showBorderOverlay(nsRect: NSRect) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(nsRect.origin) })
                ?? NSScreen.main else { return }

        let localRect = NSRect(
            x: nsRect.origin.x - screen.frame.origin.x,
            y: nsRect.origin.y - screen.frame.origin.y,
            width: nsRect.width,
            height: nsRect.height
        )

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.sharingType = .none  // Exclude from CGWindowListCreateImage

        let borderView = ScrollBorderView(frame: screen.frame, highlightRect: localRect)
        window.contentView = borderView
        window.orderFront(nil)

        self.borderWindow = window
    }

    private func showDoneButton(nsRect: NSRect) {
        let buttonWidth: CGFloat = 120
        let buttonHeight: CGFloat = 36
        let padding: CGFloat = 12

        var buttonX = nsRect.midX - buttonWidth / 2
        var buttonY = nsRect.origin.y - buttonHeight - padding

        if buttonY < 40 {
            buttonY = nsRect.maxY + padding
        }

        if let screen = NSScreen.main {
            buttonX = max(screen.frame.origin.x + 10,
                         min(buttonX, screen.frame.maxX - buttonWidth - 10))
        }

        let window = NSWindow(
            contentRect: NSRect(x: buttonX, y: buttonY, width: buttonWidth, height: buttonHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.sharingType = .none  // Exclude from CGWindowListCreateImage

        let contentView = ScrollDoneView(
            frame: NSRect(origin: .zero, size: NSSize(width: buttonWidth, height: buttonHeight))
        )
        contentView.onDone = { [weak self] in
            self?.finishCapture()
        }
        contentView.onCancel = { [weak self] in
            self?.cancelCapture()
        }
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isCapturing == true else { return event }
            if event.keyCode == 53 {
                self?.cancelCapture()
                return nil
            }
            return event
        }

        self.doneWindow = window
    }

    private func cancelCapture() {
        cleanup()
        completion?(.failure(CaptureError.cancelled))
    }

    private func finishCapture() {
        captureFrame()
        cleanup()

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

    private func cleanup() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        doneWindow?.orderOut(nil)
        doneWindow = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }

    // MARK: - Stitching

    private func stitchFrames() -> CGImage? {
        guard let first = frames.first else { return nil }

        let width = first.width
        var totalHeight = first.height
        var overlaps: [Int] = [0]

        for i in 1..<frames.count {
            let overlap = findOverlap(imageA: frames[i - 1], imageB: frames[i])
            let newHeight = frames[i].height - overlap
            if newHeight <= 10 {
                overlaps.append(-1) // skip
                continue
            }
            overlaps.append(overlap)
            totalHeight += newHeight
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var y = totalHeight

        for i in 0..<frames.count {
            guard i < overlaps.count else { break }
            let overlap = overlaps[i]
            guard overlap >= 0 else { continue }

            let image = frames[i]

            if overlap > 0 {
                let drawHeight = image.height - overlap
                guard let cropped = image.cropping(to: CGRect(
                    x: 0, y: overlap,
                    width: image.width, height: drawHeight
                )) else { continue }
                y -= drawHeight
                context.draw(cropped, in: CGRect(x: 0, y: y, width: width, height: drawHeight))
            } else {
                y -= image.height
                context.draw(image, in: CGRect(x: 0, y: y, width: width, height: image.height))
            }
        }

        return context.makeImage()
    }

    /// Find overlap by rendering each row into a compact 16-value spatial signature,
    /// then searching for where imageA's bottom matches imageB's top.
    /// Each signature bucket captures the average of a horizontal slice of the row,
    /// preserving spatial structure (unlike a single average which loses position info).
    private func findOverlap(imageA: CGImage, imageB: CGImage) -> Int {
        guard let dataA = imageA.dataProvider?.data,
              let dataB = imageB.dataProvider?.data,
              let ptrA = CFDataGetBytePtr(dataA),
              let ptrB = CFDataGetBytePtr(dataB) else { return 0 }

        let heightA = imageA.height
        let heightB = imageB.height
        let widthA = imageA.width
        let widthB = imageB.width
        let bytesPerRowA = imageA.bytesPerRow
        let bytesPerRowB = imageB.bytesPerRow
        let bppA = bytesPerRowA / max(widthA, 1)
        let bppB = bytesPerRowB / max(widthB, 1)

        let minOverlap = 4
        let maxOverlap = min(heightA, heightB) - 4
        guard maxOverlap > minOverlap else { return 0 }

        // Number of buckets in each row signature — captures spatial detail
        let buckets = 16
        // Skip outer 5% on each side to avoid scrollbar region
        let marginA = widthA / 20
        let marginB = widthB / 20
        let innerWidthA = widthA - 2 * marginA
        let innerWidthB = widthB - 2 * marginB

        typealias RowSig = [Int] // length = buckets

        func rowSignature(_ ptr: UnsafePointer<UInt8>, row: Int, bytesPerRow: Int,
                          width: Int, margin: Int, innerWidth: Int, bpp: Int) -> RowSig {
            var sig = [Int](repeating: 0, count: buckets)
            let rowOffset = row * bytesPerRow
            for b in 0..<buckets {
                let startCol = margin + b * innerWidth / buckets
                let endCol = margin + (b + 1) * innerWidth / buckets
                var sum = 0
                var count = 0
                // Sample every 4th pixel in this bucket
                var col = startCol
                let step = max((endCol - startCol) / 4, 1)
                while col < endCol {
                    let px = rowOffset + col * bpp
                    sum += Int(ptr[px]) + Int(ptr[px + 1]) + Int(ptr[px + 2])
                    count += 1
                    col += step
                }
                sig[b] = count > 0 ? sum / count : 0
            }
            return sig
        }

        func sigDistance(_ a: RowSig, _ b: RowSig) -> Int {
            var d = 0
            for i in 0..<buckets { d += abs(a[i] - b[i]) }
            return d
        }

        // Build signatures for imageB's top rows (the region we'll search for in A)
        // We use a few "anchor" rows from B and search for them in A's bottom.
        // Anchors from different vertical positions make false matches very unlikely.
        // Use anchors spread across imageB's top half — need to work for both
        // tiny scrolls (high overlap) and large scrolls (low overlap)
        let anchorRowsB = [2, 8, 20, heightB / 4].filter { $0 < heightB }
        guard anchorRowsB.count >= 2 else { return 0 }

        let anchorSigs: [RowSig] = anchorRowsB.map {
            rowSignature(ptrB, row: $0, bytesPerRow: bytesPerRowB,
                        width: widthB, margin: marginB, innerWidth: innerWidthB, bpp: bppB)
        }

        // For each candidate overlap (large to small), check if all anchor rows match
        let sigThreshold = buckets * 12 // total allowed distance across all buckets

        for candidateOverlap in stride(from: maxOverlap, through: minOverlap, by: -1) {
            // Check first anchor only as a quick filter
            let aRow0 = heightA - candidateOverlap + anchorRowsB[0]
            guard aRow0 >= 0, aRow0 < heightA else { continue }

            let sigA0 = rowSignature(ptrA, row: aRow0, bytesPerRow: bytesPerRowA,
                                     width: widthA, margin: marginA, innerWidth: innerWidthA, bpp: bppA)
            guard sigDistance(sigA0, anchorSigs[0]) < sigThreshold else { continue }

            // Quick filter passed — verify all anchors
            var allMatch = true
            for i in 1..<anchorRowsB.count {
                let aRow = heightA - candidateOverlap + anchorRowsB[i]
                guard aRow >= 0, aRow < heightA else { allMatch = false; break }
                let sigA = rowSignature(ptrA, row: aRow, bytesPerRow: bytesPerRowA,
                                        width: widthA, margin: marginA, innerWidth: innerWidthA, bpp: bppA)
                if sigDistance(sigA, anchorSigs[i]) >= sigThreshold {
                    allMatch = false
                    break
                }
            }
            guard allMatch else { continue }

            // Final verification: check 10 more rows spread across the overlap
            var verified = 0
            let checkCount = 10
            for c in 0..<checkCount {
                let bRow = c * min(candidateOverlap, heightB) / checkCount
                let aRow = heightA - candidateOverlap + bRow
                guard aRow >= 0, aRow < heightA, bRow < heightB else { continue }

                let sA = rowSignature(ptrA, row: aRow, bytesPerRow: bytesPerRowA,
                                      width: widthA, margin: marginA, innerWidth: innerWidthA, bpp: bppA)
                let sB = rowSignature(ptrB, row: bRow, bytesPerRow: bytesPerRowB,
                                      width: widthB, margin: marginB, innerWidth: innerWidthB, bpp: bppB)
                if sigDistance(sA, sB) < sigThreshold { verified += 1 }
            }

            // Require 70% of verification rows to match
            if verified >= checkCount * 7 / 10 {
                return candidateOverlap
            }
        }

        return 0
    }

    /// Check if two frames are effectively identical (content hasn't scrolled).
    /// Uses row fingerprints from the middle of the image to avoid
    /// false positives from sticky headers/footers or scrollbars.
    private func framesAreIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        guard let dataA = a.dataProvider?.data, let dataB = b.dataProvider?.data else { return false }
        guard let ptrA = CFDataGetBytePtr(dataA), let ptrB = CFDataGetBytePtr(dataB) else { return false }

        let bytesPerRow = a.bytesPerRow
        let height = a.height

        // Compare rows from the middle 50% of the image
        let startRow = height / 4
        let endRow = height * 3 / 4
        let step = max((endRow - startRow) / 8, 1)

        var row = startRow
        while row < endRow {
            let offset = row * bytesPerRow
            if memcmp(ptrA + offset, ptrB + offset, bytesPerRow) != 0 {
                return false
            }
            row += step
        }

        return true
    }
}

// MARK: - Border overlay

private class ScrollBorderView: NSView {
    let highlightRect: NSRect

    init(frame: NSRect, highlightRect: NSRect) {
        self.highlightRect = highlightRect
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(highlightRect.insetBy(dx: -1, dy: -1))
    }
}

// MARK: - Done button

private class ScrollDoneView: NSView {
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupUI() {
        let bg = NSVisualEffectView(frame: bounds)
        bg.blendingMode = .behindWindow
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = bounds.height / 2
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]
        addSubview(bg)

        let doneBtn = NSButton(frame: NSRect(x: 8, y: 4, width: 64, height: 28))
        doneBtn.bezelStyle = .rounded
        doneBtn.title = "Done"
        doneBtn.font = .systemFont(ofSize: 12, weight: .semibold)
        doneBtn.target = self
        doneBtn.action = #selector(doneClicked)
        doneBtn.keyEquivalent = "\r"
        addSubview(doneBtn)

        let cancelBtn = NSButton(frame: NSRect(x: 72, y: 4, width: 44, height: 28))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.title = "Esc"
        cancelBtn.font = .systemFont(ofSize: 11, weight: .regular)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelClicked)
        addSubview(cancelBtn)
    }

    @objc private func doneClicked() { onDone?() }
    @objc private func cancelClicked() { onCancel?() }
}
