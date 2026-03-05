import Cocoa
import AVFoundation
import ScreenCaptureKit

class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
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
    private var startTime: Date?
    private var recordingURL: URL?
    private var toolbarWindow: NSWindow?

    var onRecordingFinished: ((URL) -> Void)?

    func startFullscreen() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                try await startRecording(filter: filter)
            } catch {
                NSLog("Recording failed: \(error)")
            }
        }
    }

    func startArea() {
        let selector = AreaSelector { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let rect):
                Task {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        guard let display = content.displays.first else { return }
                        let filter = SCContentFilter(display: display, excludingWindows: [])
                        try await self.startRecording(filter: filter, cropRect: rect)
                    } catch {
                        NSLog("Area recording failed: \(error)")
                    }
                }
            case .failure:
                break
            }
        }
        selector.show()
    }

    private func startRecording(filter: SCContentFilter, cropRect: CGRect? = nil) async throws {
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width) * 2
        config.height = Int(filter.contentRect.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true

        if let crop = cropRect {
            config.sourceRect = crop
            config.width = Int(crop.width) * 2
            config.height = Int(crop.height) * 2
        }

        let filename = "Recording \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "."))"
        let url = Defaults.shared.saveLocation.appendingPathComponent("\(filename).mp4")
        recordingURL = url

        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        self.assetWriter = writer
        self.videoInput = input

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        self.stream = stream
        self.isRecording = true
        self.startTime = Date()

        await MainActor.run {
            showRecordingToolbar()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        Task {
            try? await stream?.stopCapture()
            stream = nil

            videoInput?.markAsFinished()
            await assetWriter?.finishWriting()

            await MainActor.run {
                toolbarWindow?.orderOut(nil)
                toolbarWindow = nil
                if let url = recordingURL {
                    onRecordingFinished?(url)
                }
            }
        }
    }

    func togglePause() {
        isPaused.toggle()
    }

    private func showRecordingToolbar() {
        guard let screen = NSScreen.main else { return }

        let toolbarWidth: CGFloat = 280
        let toolbarHeight: CGFloat = 40

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

        let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: toolbarWidth, height: toolbarHeight)))
        view.wantsLayer = true
        view.layer?.cornerRadius = toolbarHeight / 2
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor

        let pauseButton = NSButton(title: "Pause", target: self, action: #selector(pauseClicked))
        pauseButton.bezelStyle = .inline
        pauseButton.frame = NSRect(x: 12, y: 6, width: 60, height: 28)
        view.addSubview(pauseButton)

        let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopClicked))
        stopButton.bezelStyle = .inline
        stopButton.contentTintColor = .systemRed
        stopButton.frame = NSRect(x: 80, y: 6, width: 50, height: 28)
        view.addSubview(stopButton)

        let timerLabel = NSTextField(labelWithString: "00:00")
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timerLabel.frame = NSRect(x: 140, y: 8, width: 80, height: 24)
        view.addSubview(timerLabel)

        window.contentView = view
        window.orderFront(nil)
        toolbarWindow = window

        // Update timer
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak timerLabel] timer in
            guard let self = self, self.isRecording, let start = self.startTime else {
                timer.invalidate()
                return
            }
            let elapsed = Int(Date().timeIntervalSince(start))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            timerLabel?.stringValue = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    @objc private func pauseClicked() { togglePause() }
    @objc private func stopClicked() { stopRecording() }
}

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, isRecording, !isPaused else { return }
        guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(sampleBuffer)
    }
}
