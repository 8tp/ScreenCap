import Cocoa
import AVFoundation
import ScreenCaptureKit

class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let lock = NSLock()
    private var _isRecording = false
    private var _isPaused = false

    private var isRecording: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isRecording }
        set { lock.lock(); _isRecording = newValue; lock.unlock() }
    }
    private var isPaused: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isPaused }
        set { lock.lock(); _isPaused = newValue; lock.unlock() }
    }

    // Timestamp remapping state
    private var firstSampleTime: CMTime?
    private var pauseBeginTime: CMTime?
    private var totalPausedCMTime: CMTime = .zero

    private var startTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var pauseStartDate: Date?
    private var recordingURL: URL?
    private var toolbarWindow: NSWindow?
    private var pauseButton: NSButton?
    private var timerLabel: NSTextField?
    private var statusDot: NSView?
    private var statusLabel: NSTextField?
    private var updateTimer: Timer?
    private var borderWindow: NSWindow?
    private var keyMonitor: Any?
    private var gifButton: NSButton?

    private var activeAreaSelector: AreaSelector?

    var onRecordingFinished: ((URL) -> Void)?

    func startFullscreen() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = displayForMouseLocation(content.displays) else { return }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                try await startRecording(filter: filter, display: display)
            } catch {
                NSLog("Recording failed: \(error)")
            }
        }
    }

    func startArea() {
        let selector = AreaSelector { [weak self] result in
            self?.activeAreaSelector = nil
            guard let self = self else { return }
            switch result {
            case .success(let (rect, _)):
                Task {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        guard let display = self.displayForMouseLocation(content.displays) else { return }
                        let filter = SCContentFilter(display: display, excludingWindows: [])
                        try await self.startRecording(filter: filter, display: display, cropRect: rect)
                    } catch {
                        NSLog("Area recording failed: \(error)")
                    }
                }
            case .failure:
                break
            }
        }
        activeAreaSelector = selector
        selector.show()
    }

    private func displayForMouseLocation(_ displays: [SCDisplay]) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        let ph = NSScreen.primaryHeight
        // Convert NS mouse to CG coords for comparison with SCDisplay frames (CG coords)
        let cgMouse = CGPoint(x: mouse.x, y: ph - mouse.y)
        for d in displays {
            let frame = CGRect(x: CGFloat(d.frame.origin.x),
                               y: CGFloat(d.frame.origin.y),
                               width: CGFloat(d.width),
                               height: CGFloat(d.height))
            if frame.contains(cgMouse) { return d }
        }
        return displays.first
    }

    private func startRecording(filter: SCContentFilter, display: SCDisplay, cropRect: CGRect? = nil) async throws {
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true

        if let crop = cropRect {
            // cropRect is in CG global coords; sourceRect needs display-relative coords
            let displayOrigin = CGPoint(x: CGFloat(display.frame.origin.x),
                                        y: CGFloat(display.frame.origin.y))
            let sourceRect = CGRect(
                x: crop.origin.x - displayOrigin.x,
                y: crop.origin.y - displayOrigin.y,
                width: crop.width,
                height: crop.height
            )
            config.sourceRect = sourceRect
            config.width = Int(crop.width) * 2
            config.height = Int(crop.height) * 2
        } else {
            config.width = Int(filter.contentRect.width) * 2
            config.height = Int(filter.contentRect.height) * 2
        }

        // Enable system audio capture
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        let recFormatter = DateFormatter()
        recFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let filename = "Recording \(recFormatter.string(from: Date()))"
        let url = Defaults.shared.saveLocation.appendingPathComponent("\(filename).mp4")
        recordingURL = url

        let writer = try AVAssetWriter(url: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)
        self.videoInput = vInput

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000,
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        writer.add(aInput)
        self.audioInput = aInput

        self.assetWriter = writer

        writer.startWriting()

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        self.stream = stream
        self.isRecording = true
        self.isPaused = false
        self.startTime = Date()
        self.totalPausedDuration = 0
        self.pauseStartDate = nil
        self.firstSampleTime = nil
        self.pauseBeginTime = nil
        self.totalPausedCMTime = .zero

        let areaRect = cropRect
        await MainActor.run {
            showRecordingToolbar()
            if let rect = areaRect {
                showAreaBorder(cgRect: rect)
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        if let pauseStart = pauseStartDate {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }

        Task {
            try? await stream?.stopCapture()
            stream = nil

            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            await assetWriter?.finishWriting()

            await MainActor.run {
                dismissToolbar()
                if let url = recordingURL {
                    Defaults.shared.addRecentCapture(url)
                    onRecordingFinished?(url)
                }
            }
        }
    }

    func togglePause() {
        if isPaused {
            if let pauseStart = pauseStartDate {
                totalPausedDuration += Date().timeIntervalSince(pauseStart)
                pauseStartDate = nil
            }
            isPaused = false
            DispatchQueue.main.async {
                self.pauseButton?.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
                self.pauseButton?.contentTintColor = .white.withAlphaComponent(0.85)
                self.statusLabel?.stringValue = "Recording"
                self.statusDot?.layer?.backgroundColor = NSColor.systemRed.cgColor
                self.resumeDotPulse()
            }
        } else {
            pauseStartDate = Date()
            isPaused = true
            DispatchQueue.main.async {
                self.pauseButton?.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Resume")
                self.pauseButton?.contentTintColor = .systemGreen
                self.statusLabel?.stringValue = "Paused"
                self.statusDot?.layer?.removeAnimation(forKey: "pulse")
                self.statusDot?.layer?.backgroundColor = NSColor.systemYellow.cgColor
                self.statusDot?.layer?.opacity = 1.0
            }
        }
    }

    // MARK: - Recording Toolbar

    private func showRecordingToolbar() {
        let screen = screenForMouseLocation() ?? NSScreen.main
        guard let screen = screen else { return }

        let toolbarWidth: CGFloat = 340
        let toolbarHeight: CGFloat = 64

        let window = NSWindow(
            contentRect: NSRect(
                x: screen.frame.midX - toolbarWidth / 2,
                y: screen.frame.maxY - toolbarHeight - 12,
                width: toolbarWidth,
                height: toolbarHeight
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.sharingType = .none

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: toolbarWidth, height: toolbarHeight)))
        effectView.blendingMode = .behindWindow
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true

        var x: CGFloat = 16

        // Recording status dot
        let dot = NSView(frame: NSRect(x: x, y: 30, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        effectView.addSubview(dot)
        statusDot = dot
        resumeDotPulse()
        x += 16

        // Status label
        let status = NSTextField(labelWithString: "Recording")
        status.textColor = .white.withAlphaComponent(0.6)
        status.font = .systemFont(ofSize: 10, weight: .medium)
        status.frame = NSRect(x: x, y: 38, width: 70, height: 14)
        effectView.addSubview(status)
        statusLabel = status

        // Timer
        let timer = NSTextField(labelWithString: "00:00")
        timer.textColor = .white
        timer.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        timer.frame = NSRect(x: x, y: 18, width: 70, height: 20)
        effectView.addSubview(timer)
        timerLabel = timer
        x += 76

        // Divider
        addDivider(to: effectView, x: x)
        x += 13

        // Pause button + shortcut
        let pauseBtn = makeToolbarButton(
            icon: "pause.fill", tooltip: "Pause Recording",
            action: #selector(pauseClicked), tint: .white.withAlphaComponent(0.85)
        )
        let pauseCol = makeButtonColumn(button: pauseBtn, shortcut: "P", x: x)
        effectView.addSubview(pauseCol)
        pauseButton = pauseBtn
        x += 48

        // Stop button + shortcut
        let stopBtn = makeToolbarButton(
            icon: "stop.fill", tooltip: "Stop Recording",
            action: #selector(stopClicked), tint: .systemRed
        )
        let stopCol = makeButtonColumn(button: stopBtn, shortcut: "S", x: x)
        effectView.addSubview(stopCol)
        x += 48

        // Divider
        addDivider(to: effectView, x: x)
        x += 13

        // GIF toggle + shortcut
        let gifBtn = makeToolbarButton(
            icon: "photo.badge.arrow.down", tooltip: "Toggle GIF export",
            action: #selector(exportGIFClicked), tint: .white.withAlphaComponent(0.5)
        )
        gifButton = gifBtn
        let gifCol = makeButtonColumn(button: gifBtn, shortcut: "G", x: x)
        effectView.addSubview(gifCol)

        window.contentView = effectView

        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 1.0
        }
        toolbarWindow = window

        // Global key monitor for hotkeys
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            let char = event.charactersIgnoringModifiers?.lowercased()
            if char == "p" {
                self.togglePause()
                return nil
            }
            if char == "s" || event.keyCode == 53 { // S or Escape
                self.stopClicked()
                return nil
            }
            if char == "g" {
                self.exportGIFClicked()
                return nil
            }
            return event
        }

        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, self.isRecording, let start = self.startTime else {
                timer.invalidate()
                return
            }
            let totalElapsed = Date().timeIntervalSince(start)
            let currentPauseDuration = self.isPaused ? Date().timeIntervalSince(self.pauseStartDate ?? Date()) : 0
            let activeTime = Int(totalElapsed - self.totalPausedDuration - currentPauseDuration)
            let minutes = max(0, activeTime) / 60
            let seconds = max(0, activeTime) % 60
            DispatchQueue.main.async {
                self.timerLabel?.stringValue = String(format: "%02d:%02d", minutes, seconds)
            }
        }
    }

    private func makeToolbarButton(icon: String, tooltip: String, action: Selector, tint: NSColor) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 4, y: 16, width: 36, height: 36))
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        btn.contentTintColor = tint
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        return btn
    }

    private func makeButtonColumn(button: NSButton, shortcut: String, x: CGFloat) -> NSView {
        let col = NSView(frame: NSRect(x: x, y: 0, width: 44, height: 64))

        button.frame = NSRect(x: 4, y: 18, width: 36, height: 36)
        col.addSubview(button)

        let label = NSTextField(labelWithString: shortcut)
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.3)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 4, width: 44, height: 12)
        col.addSubview(label)

        return col
    }

    private func addDivider(to view: NSView, x: CGFloat) {
        let div = NSView(frame: NSRect(x: x, y: 16, width: 1, height: 32))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        view.addSubview(div)
    }

    private func resumeDotPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        statusDot?.layer?.add(pulse, forKey: "pulse")
    }

    private func dismissToolbar() {
        updateTimer?.invalidate()
        updateTimer = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
        pauseButton = nil
        gifButton = nil
        timerLabel = nil
        statusDot = nil
        statusLabel = nil
    }

    private func showAreaBorder(cgRect: CGRect) {
        // Convert CG rect to NS screen coordinates
        let ph = NSScreen.primaryHeight
        let nsRect = NSRect(
            x: cgRect.origin.x,
            y: ph - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(nsRect) })
                ?? NSScreen.main else { return }

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
        window.sharingType = .none  // Don't appear in the recording

        let localRect = NSRect(
            x: nsRect.origin.x - screen.frame.origin.x,
            y: nsRect.origin.y - screen.frame.origin.y,
            width: nsRect.width,
            height: nsRect.height
        )

        let borderView = RecordingBorderView(frame: screen.frame, recordingRect: localRect)
        window.contentView = borderView
        window.orderFront(nil)
        self.borderWindow = window
    }

    private func screenForMouseLocation() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
    }

    private var shouldExportGIF = false

    @objc private func pauseClicked() { togglePause() }
    @objc private func stopClicked() {
        if shouldExportGIF {
            stopAndExportGIF()
        } else {
            stopRecording()
        }
    }
    @objc private func exportGIFClicked() {
        shouldExportGIF.toggle()
        gifButton?.contentTintColor = shouldExportGIF ? .systemPurple : .white.withAlphaComponent(0.5)
        Toast.show(message: shouldExportGIF ? "Will export as GIF" : "Will save as MP4")
    }

    private func stopAndExportGIF() {
        guard isRecording else { return }
        isRecording = false
        shouldExportGIF = false

        Task {
            try? await stream?.stopCapture()
            stream = nil

            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            await assetWriter?.finishWriting()

            await MainActor.run {
                dismissToolbar()

                guard let url = recordingURL else { return }

                Toast.show(message: "Converting to GIF...")
                let maxW = Defaults.shared.gifMaxWidth
                let fps = Defaults.shared.gifFrameRate
                GIFExporter.exportToGIF(videoURL: url, maxWidth: maxW, fps: fps) { [weak self] result in
                    switch result {
                    case .success(let gifURL):
                        Defaults.shared.addRecentCapture(gifURL)
                        Toast.show(message: "GIF saved: \(gifURL.lastPathComponent)")
                        self?.onRecordingFinished?(gifURL)
                    case .failure:
                        Toast.show(message: "GIF export failed", style: .error)
                        Defaults.shared.addRecentCapture(url)
                        self?.onRecordingFinished?(url)
                    }
                }
            }
        }
    }
}

// MARK: - Recording area border overlay

private class RecordingBorderView: NSView {
    let recordingRect: NSRect

    init(frame: NSRect, recordingRect: NSRect) {
        self.recordingRect = recordingRect
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim area outside recording region
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)

        // Top
        context.fill(NSRect(x: 0, y: recordingRect.maxY, width: bounds.width, height: bounds.height - recordingRect.maxY))
        // Bottom
        context.fill(NSRect(x: 0, y: 0, width: bounds.width, height: recordingRect.origin.y))
        // Left
        context.fill(NSRect(x: 0, y: recordingRect.origin.y, width: recordingRect.origin.x, height: recordingRect.height))
        // Right
        context.fill(NSRect(x: recordingRect.maxX, y: recordingRect.origin.y, width: bounds.width - recordingRect.maxX, height: recordingRect.height))

        context.restoreGState()

        // Red border around recording area
        context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(2)
        context.stroke(recordingRect.insetBy(dx: -1, dy: -1))

        // Corner brackets for visual clarity
        let bracketLen: CGFloat = 16
        let r = recordingRect
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(3)

        // Top-left
        context.move(to: CGPoint(x: r.minX, y: r.maxY - bracketLen))
        context.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        context.addLine(to: CGPoint(x: r.minX + bracketLen, y: r.maxY))
        context.strokePath()

        // Top-right
        context.move(to: CGPoint(x: r.maxX - bracketLen, y: r.maxY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bracketLen))
        context.strokePath()

        // Bottom-left
        context.move(to: CGPoint(x: r.minX, y: r.minY + bracketLen))
        context.addLine(to: CGPoint(x: r.minX, y: r.minY))
        context.addLine(to: CGPoint(x: r.minX + bracketLen, y: r.minY))
        context.strokePath()

        // Bottom-right
        context.move(to: CGPoint(x: r.maxX - bracketLen, y: r.minY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.minY + bracketLen))
        context.strokePath()
    }
}

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstSampleTime == nil {
            firstSampleTime = pts
            assetWriter?.startSession(atSourceTime: .zero)
        }

        if isPaused {
            if pauseBeginTime == nil {
                pauseBeginTime = pts
            }
            return
        }

        if let begin = pauseBeginTime {
            let gap = CMTimeSubtract(pts, begin)
            totalPausedCMTime = CMTimeAdd(totalPausedCMTime, gap)
            pauseBeginTime = nil
        }

        guard let first = firstSampleTime else { return }
        let remapped = CMTimeSubtract(CMTimeSubtract(pts, first), totalPausedCMTime)

        guard remapped.value >= 0 else { return }

        guard CMSampleBufferGetFormatDescription(sampleBuffer) != nil else { return }
        let timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: remapped,
            decodeTimeStamp: .invalid
        )

        switch type {
        case .screen:
            guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }
            if let remappedBuffer = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timingInfo]) {
                videoInput.append(remappedBuffer)
            }
        case .audio:
            guard let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
            if let remappedBuffer = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timingInfo]) {
                audioInput.append(remappedBuffer)
            }
        case .microphone:
            guard let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
            if let remappedBuffer = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timingInfo]) {
                audioInput.append(remappedBuffer)
            }
        @unknown default:
            break
        }
    }
}
