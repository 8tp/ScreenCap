import Cocoa

class ColorPickerTool {
    private var overlayWindow: NSWindow?
    var completion: ((NSColor) -> Void)?

    func show(completion: @escaping (NSColor) -> Void) {
        self.completion = completion

        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let view = ColorPickerView(frame: screen.frame) { [weak self] color in
            self?.overlayWindow?.orderOut(nil)
            self?.overlayWindow = nil
            completion(color)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        self.overlayWindow = window
        NSCursor.crosshair.push()
    }
}

class ColorPickerView: NSView {
    private let completion: (NSColor) -> Void
    private var currentColor: NSColor = .clear
    private var currentHex: String = ""

    init(frame: NSRect, completion: @escaping (NSColor) -> Void) {
        self.completion = completion
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            NSCursor.pop()
            window?.orderOut(nil)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateColorAtMouse()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.pop()
        updateColorAtMouse()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentHex, forType: .string)

        Toast.show(message: "Copied \(currentHex)")
        completion(currentColor)
    }

    private func updateColorAtMouse() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return }

        let cgPoint = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)

        guard let image = CGWindowListCreateImage(
            CGRect(x: cgPoint.x - 1, y: cgPoint.y - 1, width: 1, height: 1),
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else { return }

        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data),
              CFDataGetLength(data) >= 4 else { return }

        let r = ptr[0]
        let g = ptr[1]
        let b = ptr[2]

        currentColor = NSColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
        currentHex = String(format: "#%02X%02X%02X", r, g, b)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill()

        let mouseLocation = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)

        // Draw magnifier loupe
        let loupeSize: CGFloat = 120
        let loupeRect = NSRect(
            x: mouseLocation.x + 20,
            y: mouseLocation.y + 20,
            width: loupeSize,
            height: loupeSize
        )

        // Color swatch
        currentColor.setFill()
        let swatchRect = NSRect(x: loupeRect.origin.x, y: loupeRect.origin.y, width: loupeSize, height: 30)
        NSBezierPath(roundedRect: swatchRect, xRadius: 6, yRadius: 6).fill()

        // Labels
        let r = Int(currentColor.redComponent * 255)
        let g = Int(currentColor.greenComponent * 255)
        let b = Int(currentColor.blueComponent * 255)

        let labelText = "\(currentHex)\nRGB: \(r), \(g), \(b)"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .backgroundColor: NSColor.black.withAlphaComponent(0.8)
        ]
        let labelPoint = NSPoint(x: loupeRect.origin.x, y: loupeRect.origin.y + 34)
        (labelText as NSString).draw(at: labelPoint, withAttributes: attrs)
    }
}
