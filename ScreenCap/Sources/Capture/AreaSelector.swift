import Cocoa

class AreaSelector {
    private var overlayWindow: NSWindow?
    private let completion: (Result<CGRect, Error>) -> Void

    init(completion: @escaping (Result<CGRect, Error>) -> Void) {
        self.completion = completion
    }

    func show() {
        guard let screen = NSScreen.main else {
            completion(.failure(CaptureError.noDisplay))
            return
        }

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

        let view = AreaSelectorView(frame: screen.frame) { [weak self] result in
            self?.overlayWindow?.orderOut(nil)
            self?.overlayWindow = nil
            self?.completion(result)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        self.overlayWindow = window

        NSCursor.crosshair.push()
    }
}

class AreaSelectorView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isDragging = false
    private var selectionRect: NSRect?
    private let completion: (Result<CGRect, Error>) -> Void

    init(frame: NSRect, completion: @escaping (Result<CGRect, Error>) -> Void) {
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
            completion(.failure(CaptureError.cancelled))
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let start = startPoint else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let current = currentPoint else { return }

        var rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Shift constrains to square
        if NSEvent.modifierFlags.contains(.shift) {
            let side = max(rect.width, rect.height)
            rect.size = NSSize(width: side, height: side)
        }

        selectionRect = rect
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        NSCursor.pop()

        guard let rect = selectionRect, rect.width > 1, rect.height > 1 else {
            completion(.failure(CaptureError.cancelled))
            return
        }

        // Convert from view coordinates to screen coordinates
        guard let screen = NSScreen.main else {
            completion(.failure(CaptureError.noDisplay))
            return
        }

        let screenFrame = screen.frame
        // NSView coordinates are flipped relative to CGWindow coordinates
        let cgRect = CGRect(
            x: rect.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        completion(.success(cgRect))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        guard let rect = selectionRect else { return }

        // Clear the selection area (punch a hole through the dimming overlay)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setBlendMode(.clear)
        context.fill(rect)
        context.setBlendMode(.normal)

        // Draw selection border
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        // Draw dimension label
        let w = Int(rect.width)
        let h = Int(rect.height)
        let label = "\(w) x \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let labelPoint = NSPoint(
            x: rect.midX - labelSize.width / 2,
            y: rect.minY - labelSize.height - 6
        )
        (label as NSString).draw(at: labelPoint, withAttributes: attrs)
    }
}
