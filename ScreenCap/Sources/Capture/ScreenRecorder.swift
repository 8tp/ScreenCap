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
            case .success(let rect):
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

    /// Pick the SCDisplay whose frame contains the current mouse location.
    private func displayForMouseLocation(_ displays: [SCDisplay]) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        for d in displays {
            let frame = CGRect(x: CGFloat(d.frame.origin.x),
                               y: CGFloat(d.frame.origin.y),
                               width: CGFloat(d.width),
                               height: CGFloat(d.height))
            if frame.contains(mouse) { return d }
        }
        return displays.first
    }

    private func startRecording(filter: SCContentFilter, display: SCDisplay, cropRect: CGRect? = nil) async throws {
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width) * 2
        config.height = Int(filter.contentRect.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true

        if let crop = cropRect {
            // cropRect is in CG global coords; sourceRect needs display-relative coords
            let displayOrigin = CGPoint(x: CGFloat(display.frame.origin.x),
                                        y: CGFloat(display.frame.origin.y))
            config.sourceRect = CGRect(
                x: crop.origin.x - displayOrigin.x,
                y: crop.origin.y - displayOrigin.y,
                width: crop.width,
                height: crop.height
            )
            config.width = Int(crop.width) * 2
            config.height = Int(crop.height) * 2
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

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)
        self.videoInput = vInput

        // Audio input
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
        // Don't start session yet — we start it at first sample

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

        await MainActor.run {
            showRecordingToolbar()
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
                toolbarWindow?.orderOut(nil)
                toolbarWindow = nil
                pauseButton = nil
                timerLabel = nil
                if let url = recordingURL {
                    Defaults.shared.addRecentCapture(url)
                    onRecordingFinished?(url)
                }
            }
        }
    }

    func togglePause() {
        if isPaused {
            // Resuming — accumulate paused CMTime
            if let begin = pauseBeginTime {
                // The actual accumulated pause duration will be computed at next sample arrival
                // For now just record that we resumed
                _ = begin // used later in stream output
            }
            if let pauseStart = pauseStartDate {
                totalPausedDuration += Date().timeIntervalSince(pauseStart)
                pauseStartDate = nil
            }
            isPaused = false
            DispatchQueue.main.async {
                self.pauseButton?.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
                self.pauseButton?.contentTintColor = nil
                self.pauseButton?.toolTip = "Pause Recording"
            }
        } else {
            // Pausing — record the CMTime when pause began
            pauseStartDate = Date()
            isPaused = true
            // pauseBeginTime will be set from the next sample buffer timestamp
            // but we approximate with current state
            DispatchQueue.main.async {
                self.pauseButton?.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Resume")
                self.pauseButton?.contentTintColor = .systemGreen
                self.pauseButton?.toolTip = "Resume Recording"
            }
        }
    }

    private func showRecordingToolbar() {
        let screen = screenForMouseLocation() ?? NSScreen.main
        guard let screen = screen else { return }

        let toolbarWidth: CGFloat = 340
        let toolbarHeight: CGFloat = 44

        let window = NSWindow(
            contentRect: NSRect(
                x: screen.frame.midX - toolbarWidth / 2,
                y: screen.frame.maxY - toolbarHeight - 10,
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

        // Vibrancy background
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: toolbarWidth, height: toolbarHeight)))
        effectView.blendingMode = .behindWindow
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = toolbarHeight / 2
        effectView.layer?.masksToBounds = true

        // Recording dot
        let dotView = NSView(frame: NSRect(x: 14, y: 16, width: 12, height: 12))
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 6
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        effectView.addSubview(dotView)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dotView.layer?.add(pulse, forKey: "pulse")

        var x: CGFloat = 34
        let btnH: CGFloat = 28
        let btnY: CGFloat = 8

        let pauseBtn = NSButton(frame: NSRect(x: x, y: btnY, width: 28, height: btnH))
        pauseBtn.bezelStyle = .accessoryBarAction
        pauseBtn.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        pauseBtn.imagePosition = .imageOnly
        pauseBtn.toolTip = "Pause Recording"
        pauseBtn.target = self
        pauseBtn.action = #selector(pauseClicked)
        pauseBtn.isBordered = false
        effectView.addSubview(pauseBtn)
        self.pauseButton = pauseBtn
        x += 32

        let stopButton = NSButton(frame: NSRect(x: x, y: btnY, width: 28, height: btnH))
        stopButton.bezelStyle = .accessoryBarAction
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        stopButton.imagePosition = .imageOnly
        stopButton.contentTintColor = .systemRed
        stopButton.toolTip = "Stop Recording"
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.isBordered = false
        effectView.addSubview(stopButton)
        x += 36

        // Divider
        let div = NSView(frame: NSRect(x: x, y: 12, width: 1, height: 20))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        effectView.addSubview(div)
        x += 9

        let gifButton = NSButton(frame: NSRect(x: x, y: btnY, width: 28, height: btnH))
        gifButton.bezelStyle = .accessoryBarAction
        gifButton.image = NSImage(systemSymbolName: "gift", accessibilityDescription: "GIF")
        gifButton.imagePosition = .imageOnly
        gifButton.contentTintColor = .systemPurple
        gifButton.toolTip = "Export as GIF when done"
        gifButton.target = self
        gifButton.action = #selector(exportGIFClicked)
        gifButton.isBordered = false
        effectView.addSubview(gifButton)
        x += 36

        // Divider
        let div2 = NSView(frame: NSRect(x: x, y: 12, width: 1, height: 20))
        div2.wantsLayer = true
        div2.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        effectView.addSubview(div2)
        x += 9

        // Timer label
        let label = NSTextField(labelWithString: "00:00")
        label.textColor = .white
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.frame = NSRect(x: x, y: 10, width: 56, height: 24)
        effectView.addSubview(label)
        self.timerLabel = label

        window.contentView = effectView
        window.orderFront(nil)
        toolbarWindow = window

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
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
        Toast.show(message: shouldExportGIF ? "Will export as GIF on stop" : "Will save as MP4")
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
                toolbarWindow?.orderOut(nil)
                toolbarWindow = nil

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

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // On first sample, start the writer session
        if firstSampleTime == nil {
            firstSampleTime = pts
            assetWriter?.startSession(atSourceTime: .zero)
        }

        if isPaused {
            // Record when the pause started (in media time)
            if pauseBeginTime == nil {
                pauseBeginTime = pts
            }
            return // drop samples while paused
        }

        // If we just resumed from a pause, accumulate the gap
        if let begin = pauseBeginTime {
            let gap = CMTimeSubtract(pts, begin)
            totalPausedCMTime = CMTimeAdd(totalPausedCMTime, gap)
            pauseBeginTime = nil
        }

        // Remap: output_pts = pts - firstSampleTime - totalPausedCMTime
        guard let first = firstSampleTime else { return }
        let remapped = CMTimeSubtract(CMTimeSubtract(pts, first), totalPausedCMTime)

        guard remapped.value >= 0 else { return }

        // Create a new sample buffer with the remapped timestamp
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
        @unknown default:
            break
        }
    }
}
