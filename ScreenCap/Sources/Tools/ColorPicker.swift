import Cocoa

class ColorPickerTool {
    private var overlayWindow: NSWindow?
    var completion: ((NSColor) -> Void)?

    func show(completion: @escaping (NSColor) -> Void) {
        self.completion = completion

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }

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
        view.onCancel = { [weak self] in
            self?.overlayWindow?.orderOut(nil)
            self?.overlayWindow = nil
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        self.overlayWindow = window
        NSCursor.crosshair.push()
    }
}

class ColorPickerView: NSView {
    var onCancel: (() -> Void)?
    private let completion: (NSColor) -> Void
    private var currentColor: NSColor = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
    private var currentHex: String = "#000000"
    private var magnifiedImage: CGImage?
    private let magnification: CGFloat = 8
    private let captureRadius: CGFloat = 8
    private var lastUpdateTime: CFTimeInterval = 0

    init(frame: NSRect, completion: @escaping (NSColor) -> Void) {
        self.completion = completion
        super.init(frame: frame)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape — cancel
            NSCursor.pop()
            onCancel?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // Throttle to ~60fps — CGWindowListCreateImage is expensive
        let now = CACurrentMediaTime()
        guard now - lastUpdateTime > 0.016 else {
            needsDisplay = true
            return
        }
        lastUpdateTime = now
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
        guard NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main != nil else { return }

        let cgPoint = CGPoint(x: mouseLocation.x, y: NSScreen.primaryHeight - mouseLocation.y)

        // Capture magnified region
        let captureSize = captureRadius * 2 + 1
        let captureRect = CGRect(
            x: cgPoint.x - captureRadius,
            y: cgPoint.y - captureRadius,
            width: captureSize,
            height: captureSize
        )
        magnifiedImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )

        // Sample center pixel
        guard let image = CGWindowListCreateImage(
            CGRect(x: cgPoint.x, y: cgPoint.y, width: 1, height: 1),
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
        // Nearly transparent overlay (so we can receive events)
        NSColor.black.withAlphaComponent(0.001).setFill()
        dirtyRect.fill()

        let mouseLocation = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)

        // Draw magnifier loupe
        let loupeSize: CGFloat = 140
        let loupeOffset: CGFloat = 24

        // Position loupe to avoid going off-screen
        var loupeX = mouseLocation.x + loupeOffset
        var loupeY = mouseLocation.y + loupeOffset
        if loupeX + loupeSize > bounds.width { loupeX = mouseLocation.x - loupeSize - loupeOffset }
        if loupeY + loupeSize + 60 > bounds.height { loupeY = mouseLocation.y - loupeSize - 60 - loupeOffset }

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let loupeRect = NSRect(x: loupeX, y: loupeY + 56, width: loupeSize, height: loupeSize)

        // Draw loupe background
        context.saveGState()

        // Shadow
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.4).cgColor)

        // Clipping circle for loupe
        let clipPath = NSBezierPath(ovalIn: loupeRect)
        clipPath.addClip()

        // Draw magnified image
        if let magImage = magnifiedImage {
            context.interpolationQuality = .none
            context.draw(magImage, in: loupeRect)
        }

        // Draw crosshair in center
        let centerX = loupeRect.midX
        let centerY = loupeRect.midY
        let crossSize: CGFloat = 6

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: centerX - crossSize, y: centerY))
        context.addLine(to: CGPoint(x: centerX + crossSize, y: centerY))
        context.strokePath()
        context.move(to: CGPoint(x: centerX, y: centerY - crossSize))
        context.addLine(to: CGPoint(x: centerX, y: centerY + crossSize))
        context.strokePath()

        // Draw pixel grid lines
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        let pixelSize = loupeSize / (captureRadius * 2 + 1)
        for i in 0...Int(captureRadius * 2 + 1) {
            let offset = CGFloat(i) * pixelSize
            context.move(to: CGPoint(x: loupeRect.origin.x + offset, y: loupeRect.origin.y))
            context.addLine(to: CGPoint(x: loupeRect.origin.x + offset, y: loupeRect.maxY))
            context.strokePath()
            context.move(to: CGPoint(x: loupeRect.origin.x, y: loupeRect.origin.y + offset))
            context.addLine(to: CGPoint(x: loupeRect.maxX, y: loupeRect.origin.y + offset))
            context.strokePath()
        }

        context.restoreGState()

        // Draw loupe border
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(ovalIn: loupeRect.insetBy(dx: 1, dy: 1))
        borderPath.lineWidth = 3
        borderPath.stroke()

        // Info panel below loupe
        let panelRect = NSRect(x: loupeX, y: loupeY, width: loupeSize, height: 52)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: panelRect, xRadius: 8, yRadius: 8).fill()

        // Color swatch
        let swatchRect = NSRect(x: panelRect.origin.x + 8, y: panelRect.origin.y + 8, width: 36, height: 36)
        currentColor.setFill()
        NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).fill()
        NSColor.white.withAlphaComponent(0.3).setStroke()
        NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).stroke()

        // Hex and RGB labels
        let hexAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
        ]
        (currentHex as NSString).draw(at: NSPoint(x: panelRect.origin.x + 50, y: panelRect.origin.y + 26), withAttributes: hexAttrs)

        let safeColor = currentColor.usingColorSpace(.sRGB) ?? currentColor
        let r = Int(safeColor.redComponent * 255)
        let g = Int(safeColor.greenComponent * 255)
        let b = Int(safeColor.blueComponent * 255)
        let rgbText = "RGB: \(r), \(g), \(b)"
        let rgbAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
        ]
        (rgbText as NSString).draw(at: NSPoint(x: panelRect.origin.x + 50, y: panelRect.origin.y + 10), withAttributes: rgbAttrs)
    }
}
