import Cocoa
import AVFoundation

class FloatingThumbnailController {
    private var thumbnailWindows: [(window: NSWindow, timer: Timer?, url: URL)] = []
    private(set) var currentURL: URL?
    var onEdit: ((URL) -> Void)?
    var onPin: ((URL) -> Void)?

    private let thumbWidth: CGFloat = 280
    private let thumbHeight: CGFloat = 210
    private let padding: CGFloat = 16
    private let stackSpacing: CGFloat = 8

    func show(for imageURL: URL) {
        guard Defaults.shared.showThumbnail else { return }

        currentURL = imageURL

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }

        // Generate thumbnail: use AVAssetImageGenerator for video files, NSImage for images
        let image: NSImage
        let videoExtensions = ["mp4", "mov", "m4v"]
        if videoExtensions.contains(imageURL.pathExtension.lowercased()) {
            let asset = AVAsset(url: imageURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 560, height: 420)
            if let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } else if let fallback = NSImage(contentsOf: imageURL) {
                image = fallback
            } else {
                return
            }
        } else {
            guard let loadedImage = NSImage(contentsOf: imageURL) else { return }
            image = loadedImage
        }

        let isRight = Defaults.shared.thumbnailPosition == "bottomRight"

        // Calculate stacked Y position
        let baseY = screen.visibleFrame.minY + padding
        let stackIndex = thumbnailWindows.count
        let y = baseY + CGFloat(stackIndex) * (thumbHeight + stackSpacing)

        // Start position (off-screen)
        let finalX: CGFloat
        let startX: CGFloat
        if isRight {
            finalX = screen.visibleFrame.maxX - thumbWidth - padding
            startX = screen.visibleFrame.maxX + 10
        } else {
            finalX = screen.visibleFrame.minX + padding
            startX = screen.visibleFrame.minX - thumbWidth - 10
        }

        let window = NSWindow(
            contentRect: NSRect(x: startX, y: y, width: thumbWidth, height: thumbHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.transient]

        let isRecording = ["mp4", "gif", "mov"].contains(imageURL.pathExtension.lowercased())

        let view = ThumbnailView(
            frame: NSRect(origin: .zero, size: NSSize(width: thumbWidth, height: thumbHeight)),
            image: image,
            imageURL: imageURL,
            isRecording: isRecording,
            isRightAligned: isRight
        )

        view.onEdit = { [weak self, weak window] in
            guard let self = self, let window = window else { return }
            if let idx = self.thumbnailWindows.firstIndex(where: { $0.window === window }) {
                self.removeThumbnail(at: idx)
            }
            self.onEdit?(imageURL)
        }
        view.onPin = { [weak self, weak window] in
            guard let self = self, let window = window else { return }
            if let idx = self.thumbnailWindows.firstIndex(where: { $0.window === window }) {
                self.removeThumbnail(at: idx)
            }
            self.onPin?(imageURL)
        }
        view.onDismiss = { [weak self, weak window] in
            guard let self = self, let window = window else { return }
            if let idx = self.thumbnailWindows.firstIndex(where: { $0.window === window }) {
                self.animateDismiss(at: idx)
            }
        }
        view.onCopy = {
            if let img = NSImage(contentsOf: imageURL) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([img])
                Toast.show(message: "Copied to clipboard")
            }
        }
        view.onSaveAsGIF = {
            Toast.show(message: "Converting to GIF...")
            GIFExporter.exportToGIF(videoURL: imageURL) { result in
                switch result {
                case .success(let gifURL):
                    Defaults.shared.addRecentCapture(gifURL)
                    Toast.show(message: "GIF saved: \(gifURL.lastPathComponent)")
                case .failure:
                    Toast.show(message: "GIF export failed", style: .error)
                }
            }
        }
        view.onHoverChanged = { [weak self, weak window] hovering in
            guard let self = self, let window = window else { return }
            if let idx = self.thumbnailWindows.firstIndex(where: { $0.window === window }) {
                if hovering {
                    self.thumbnailWindows[idx].timer?.invalidate()
                    self.thumbnailWindows[idx].timer = nil
                } else {
                    let timer = Timer.scheduledTimer(withTimeInterval: Defaults.shared.thumbnailDuration, repeats: false) { [weak self, weak window] _ in
                        guard let self = self, let window = window else { return }
                        if let idx = self.thumbnailWindows.firstIndex(where: { $0.window === window }) {
                            self.animateDismiss(at: idx)
                        }
                    }
                    self.thumbnailWindows[idx].timer = timer
                }
            }
        }

        window.contentView = view
        window.orderFront(nil)

        // Auto-dismiss timer
        let timer = Timer.scheduledTimer(withTimeInterval: Defaults.shared.thumbnailDuration, repeats: false) { [weak self, weak window] _ in
            guard let self = self, let window = window else { return }
            if let idx = self.thumbnailWindows.firstIndex(where: { $0.window === window }) {
                self.animateDismiss(at: idx)
            }
        }

        thumbnailWindows.append((window: window, timer: timer, url: imageURL))

        // Slide in animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(
                NSRect(x: finalX, y: y, width: thumbWidth, height: thumbHeight),
                display: true
            )
        }

        // Cap at 5 thumbnails — dismiss oldest
        if thumbnailWindows.count > 5 {
            animateDismiss(at: 0)
        }
    }

    func dismiss() {
        for entry in thumbnailWindows {
            entry.timer?.invalidate()
            entry.window.orderOut(nil)
        }
        thumbnailWindows.removeAll()
    }

    private func removeThumbnail(at index: Int) {
        guard index < thumbnailWindows.count else { return }
        let entry = thumbnailWindows[index]
        entry.timer?.invalidate()
        entry.window.orderOut(nil)
        thumbnailWindows.remove(at: index)
        repositionThumbnails()
    }

    private func animateDismiss(at index: Int) {
        guard index < thumbnailWindows.count else { return }
        let entry = thumbnailWindows[index]
        entry.timer?.invalidate()

        // Use the screen the thumbnail is actually on
        let windowCenter = NSPoint(x: entry.window.frame.midX, y: entry.window.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) }) ?? NSScreen.main else {
            removeThumbnail(at: index)
            return
        }

        let isRight = Defaults.shared.thumbnailPosition == "bottomRight"
        let offScreenX = isRight ? screen.visibleFrame.maxX + 10 : screen.visibleFrame.minX - thumbWidth - 10

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            entry.window.animator().setFrame(
                NSRect(x: offScreenX, y: entry.window.frame.origin.y, width: entry.window.frame.width, height: entry.window.frame.height),
                display: true
            )
            entry.window.animator().alphaValue = 0.5
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            let targetWindow = entry.window
            if let idx = self.thumbnailWindows.firstIndex(where: { $0.window === targetWindow }) {
                self.thumbnailWindows[idx].window.orderOut(nil)
                self.thumbnailWindows.remove(at: idx)
                self.repositionThumbnails()
            }
        })
    }

    private func repositionThumbnails() {
        // Use screen of the first thumbnail, or the mouse's screen
        let refPoint = thumbnailWindows.first.map { NSPoint(x: $0.window.frame.midX, y: $0.window.frame.midY) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(refPoint) }) ?? NSScreen.main else { return }
        let isRight = Defaults.shared.thumbnailPosition == "bottomRight"
        let baseY = screen.visibleFrame.minY + padding
        let finalX = isRight
            ? screen.visibleFrame.maxX - thumbWidth - padding
            : screen.visibleFrame.minX + padding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (i, entry) in thumbnailWindows.enumerated() {
                let y = baseY + CGFloat(i) * (thumbHeight + stackSpacing)
                entry.window.animator().setFrame(
                    NSRect(x: finalX, y: y, width: thumbWidth, height: thumbHeight),
                    display: true
                )
            }
        }

        // Update currentURL to most recent
        currentURL = thumbnailWindows.last?.url
    }
}

// MARK: - Thumbnail View

class ThumbnailView: NSView, NSDraggingSource {
    var onEdit: (() -> Void)?
    var onPin: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSaveAsGIF: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private let imageView: NSImageView
    private let imageURL: URL
    private var dragStartPoint: NSPoint?
    private let isRecording: Bool
    private let isRightAligned: Bool
    private let buttonBar: NSView
    private var isHovering = false

    init(frame: NSRect, image: NSImage, imageURL: URL, isRecording: Bool = false, isRightAligned: Bool = true) {
        self.imageURL = imageURL
        self.isRecording = isRecording
        self.isRightAligned = isRightAligned
        imageView = NSImageView()
        buttonBar = NSView()

        super.init(frame: frame)

        wantsLayer = true

        // Vibrancy background
        let effectView = NSVisualEffectView(frame: bounds)
        effectView.blendingMode = .behindWindow
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        // Image area
        let imageInset: CGFloat = 8
        let barHeight: CGFloat = 44
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.frame = NSRect(
            x: imageInset,
            y: barHeight,
            width: frame.width - imageInset * 2,
            height: frame.height - barHeight - imageInset
        )
        addSubview(imageView)

        // Button bar
        buttonBar.frame = NSRect(x: 0, y: 0, width: frame.width, height: barHeight)
        addSubview(buttonBar)

        setupButtons()
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupButtons() {
        var x: CGFloat = 10
        let btnSize: CGFloat = 28
        let btnY: CGFloat = 8
        let spacing: CGFloat = 4

        if !isRecording {
            x += addIconButton(icon: "pencil", tooltip: "Edit (Annotate)", action: #selector(editClicked), x: x, y: btnY, size: btnSize) + spacing
        }

        x += addIconButton(icon: "doc.on.clipboard", tooltip: "Copy", action: #selector(copyClicked), x: x, y: btnY, size: btnSize) + spacing
        x += addIconButton(icon: "pin", tooltip: "Pin to Desktop", action: #selector(pinClicked), x: x, y: btnY, size: btnSize) + spacing

        if isRecording {
            x += addIconButton(icon: "gift", tooltip: "Save as GIF", action: #selector(gifClicked), x: x, y: btnY, size: btnSize) + spacing
        }

        // Close button on the right
        _ = addIconButton(icon: "xmark", tooltip: "Dismiss", action: #selector(dismissClicked), x: buttonBar.frame.width - btnSize - 10, y: btnY, size: btnSize)

        // Filename label
        let filename = imageURL.deletingPathExtension().lastPathComponent
        let label = NSTextField(labelWithString: filename)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: x + 4, y: btnY + 6, width: buttonBar.frame.width - x - 48, height: 14)
        buttonBar.addSubview(label)
    }

    @discardableResult
    private func addIconButton(icon: String, tooltip: String, action: Selector, x: CGFloat, y: CGFloat, size: CGFloat) -> CGFloat {
        let button = NSButton(frame: NSRect(x: x, y: y, width: size, height: size))
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.isBordered = true
        buttonBar.addSubview(button)
        return size
    }

    private func setupTrackingArea() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChanged?(false)
    }

    // MARK: - Click and Drag

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let distance = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)

        guard distance > 5 else { return }

        let draggingItem = NSDraggingItem(pasteboardWriter: imageURL as NSURL)
        draggingItem.setDraggingFrame(imageView.frame, contents: imageView.image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        dragStartPoint = nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let endPoint = convert(event.locationInWindow, from: nil)
        let distance = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        dragStartPoint = nil

        // Single click on the image area opens the editor (or the file for recordings)
        if distance <= 5 {
            let clickPoint = endPoint
            // Only trigger if click was on the image area (above the button bar)
            if clickPoint.y > 44 {
                if isRecording {
                    NSWorkspace.shared.open(imageURL)
                } else {
                    onEdit?()
                }
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    @objc private func editClicked() { onEdit?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func pinClicked() { onPin?() }
    @objc private func gifClicked() { onSaveAsGIF?() }
    @objc private func dismissClicked() { onDismiss?() }
}
