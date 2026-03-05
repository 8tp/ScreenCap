import Cocoa

class FloatingThumbnailController {
    private var thumbnailWindow: NSWindow?
    private var dismissTimer: Timer?
    private(set) var currentURL: URL?
    var onEdit: ((URL) -> Void)?
    var onPin: ((URL) -> Void)?

    func show(for imageURL: URL) {
        guard Defaults.shared.showThumbnail else { return }

        dismiss()
        currentURL = imageURL

        guard let screen = NSScreen.main else { return }
        guard let image = NSImage(contentsOf: imageURL) else { return }

        let thumbWidth: CGFloat = 200
        let thumbHeight: CGFloat = 140
        let padding: CGFloat = 16

        let windowRect = NSRect(
            x: screen.visibleFrame.maxX - thumbWidth - padding,
            y: screen.visibleFrame.minY + padding,
            width: thumbWidth,
            height: thumbHeight
        )

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        let view = ThumbnailView(frame: NSRect(origin: .zero, size: windowRect.size), image: image, imageURL: imageURL)
        view.onEdit = { [weak self] in
            guard let self = self, let url = self.currentURL else { return }
            self.dismiss()
            self.onEdit?(url)
        }
        view.onPin = { [weak self] in
            guard let self = self, let url = self.currentURL else { return }
            self.dismiss()
            self.onPin?(url)
        }
        view.onDismiss = { [weak self] in
            self?.dismiss()
        }

        window.contentView = view
        window.orderFront(nil)
        thumbnailWindow = window

        dismissTimer = Timer.scheduledTimer(withTimeInterval: Defaults.shared.thumbnailDuration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        thumbnailWindow?.orderOut(nil)
        thumbnailWindow = nil
    }
}

class ThumbnailView: NSView, NSDraggingSource {
    var onEdit: (() -> Void)?
    var onPin: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let imageView: NSImageView
    private let editButton: NSButton
    private let pinButton: NSButton
    private let closeButton: NSButton
    private let imageURL: URL
    private var dragStartPoint: NSPoint?

    init(frame: NSRect, image: NSImage, imageURL: URL) {
        self.imageURL = imageURL
        imageView = NSImageView()
        editButton = NSButton(title: "Edit", target: nil, action: nil)
        pinButton = NSButton(title: "Pin", target: nil, action: nil)
        closeButton = NSButton(title: "X", target: nil, action: nil)

        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(x: 4, y: 30, width: frame.width - 8, height: frame.height - 34)
        addSubview(imageView)

        editButton.bezelStyle = .inline
        editButton.frame = NSRect(x: 8, y: 4, width: 50, height: 22)
        editButton.target = self
        editButton.action = #selector(editClicked)
        addSubview(editButton)

        pinButton.bezelStyle = .inline
        pinButton.frame = NSRect(x: 64, y: 4, width: 40, height: 22)
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        addSubview(pinButton)

        closeButton.bezelStyle = .inline
        closeButton.frame = NSRect(x: frame.width - 30, y: 4, width: 24, height: 22)
        closeButton.target = self
        closeButton.action = #selector(dismissClicked)
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Drag and Drop

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

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    @objc private func editClicked() { onEdit?() }
    @objc private func pinClicked() { onPin?() }
    @objc private func dismissClicked() { onDismiss?() }
}
