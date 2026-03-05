import Cocoa

class PinnedImageWindow {
    private var window: NSWindow?
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

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.center()

        let view = PinnedImageView(frame: NSRect(origin: .zero, size: size), image: image, imageURL: imageURL)
        view.onClose = { [weak self] in
            self?.close()
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

class PinnedImageView: NSView {
    var onClose: (() -> Void)?
    private let image: NSImage
    private let imageURL: URL

    init(frame: NSRect, image: NSImage, imageURL: URL) {
        self.image = image
        self.imageURL = imageURL
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
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
