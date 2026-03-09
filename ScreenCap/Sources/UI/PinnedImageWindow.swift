import Cocoa

class PinnedImageWindow {
    private var window: NSPanel?
    private let image: NSImage
    private let imageURL: URL

    init(image: NSImage, imageURL: URL) {
        self.image = image
        self.imageURL = imageURL
    }

    func show() {
        let maxSize: CGFloat = 400
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        let panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentAspectRatio = size
        panel.center()

        let view = PinnedImageView(frame: NSRect(origin: .zero, size: size), image: image, imageURL: imageURL)
        view.onClose = { [weak self] in
            self?.close()
        }
        panel.contentView = view
        panel.orderFront(nil) // orderFront, not makeKeyAndOrderFront

        self.window = panel
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Panel subclass that never becomes key, so it doesn't steal focus from the user's current app.
private class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class PinnedImageView: NSView {
    var onClose: (() -> Void)?
    private let image: NSImage
    private let imageURL: URL

    init(frame: NSRect, image: NSImage, imageURL: URL) {
        self.image = image
        self.imageURL = imageURL
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw preserving aspect ratio within current bounds
        let imageAspect = image.size.width / image.size.height
        let viewAspect = bounds.width / bounds.height
        var drawRect = bounds
        if imageAspect > viewAspect {
            // Image is wider — fit to width
            let h = bounds.width / imageAspect
            drawRect = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        } else {
            // Image is taller — fit to height
            let w = bounds.height * imageAspect
            drawRect = NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
        }
        image.draw(in: drawRect)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyImage), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(closeWindow), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        menu.addItem(NSMenuItem.separator())

        let opacityMenu = NSMenu(title: "Adjust Opacity")
        for percent in [25, 50, 75, 100] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = self
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Adjust Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @objc private func closeWindow() {
        onClose?()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        window?.alphaValue = CGFloat(sender.tag) / 100.0
    }
}
