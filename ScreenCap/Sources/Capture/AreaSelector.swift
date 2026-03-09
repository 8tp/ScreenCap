import Cocoa

class AreaSelector {
    private var overlayWindow: NSWindow?
    private let completion: (Result<CGRect, Error>) -> Void

    init(completion: @escaping (Result<CGRect, Error>) -> Void) {
        self.completion = completion
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            completion(.failure(CaptureError.noDisplay))
            return
        }

        // Optionally freeze the screen by capturing only this display
        var frozenImage: CGImage?
        if Defaults.shared.freezeScreen {
            frozenImage = CGDisplayCreateImage(screen.displayID)
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

        let view = AreaSelectorView(frame: screen.frame, frozenImage: frozenImage) { [weak self] result in
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
    private var mousePosition: NSPoint = .zero
    private let completion: (Result<CGRect, Error>) -> Void
    private var trackingArea: NSTrackingArea?
    private var frozenImage: CGImage?

    // Space-to-reposition state
    private var isRepositioning = false
    private var repositionLastPoint: NSPoint?

    init(frame: NSRect, frozenImage: CGImage? = nil, completion: @escaping (Result<CGRect, Error>) -> Void) {
        self.completion = completion
        self.frozenImage = frozenImage
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
        trackingArea = area
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            NSCursor.pop()
            completion(.failure(CaptureError.cancelled))
        } else if event.keyCode == 49, isDragging { // Space — enter reposition mode
            isRepositioning = true
            repositionLastPoint = currentPoint ?? mousePosition
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { // Space released
            isRepositioning = false
            repositionLastPoint = nil
        }
    }

    // Prevent key repeat beep
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 49 { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        mousePosition = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, var start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        mousePosition = point

        if isRepositioning, let lastPt = repositionLastPoint {
            // Move entire selection by translating both anchor points
            let dx = point.x - lastPt.x
            let dy = point.y - lastPt.y
            start = NSPoint(x: start.x + dx, y: start.y + dy)
            startPoint = start
            if let cp = currentPoint {
                currentPoint = NSPoint(x: cp.x + dx, y: cp.y + dy)
            }
            repositionLastPoint = point
            if let rect = selectionRect {
                selectionRect = rect.offsetBy(dx: dx, dy: dy)
            }
            needsDisplay = true
            return
        }

        currentPoint = point
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
        isRepositioning = false
        repositionLastPoint = nil
        NSCursor.pop()

        guard let rect = selectionRect, rect.width > 1, rect.height > 1 else {
            completion(.failure(CaptureError.cancelled))
            return
        }

        // The overlay window is positioned at screen.frame, so view-local (0,0)
        // maps to NS global (screen.origin.x, screen.origin.y).
        // CG global coords have origin at top-left of the primary display.
        guard let screen = self.window?.screen ?? NSScreen.main else {
            completion(.failure(CaptureError.noDisplay))
            return
        }

        let ph = NSScreen.primaryHeight
        let cgRect = CGRect(
            x: rect.origin.x + screen.frame.origin.x,
            y: ph - (rect.origin.y + screen.frame.origin.y) - rect.height,
            width: rect.width,
            height: rect.height
        )

        completion(.success(cgRect))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw frozen screenshot as background (if freeze screen is enabled)
        if let frozen = frozenImage {
            NSImage(cgImage: frozen, size: bounds.size).draw(in: bounds)
        }

        // Dim overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        // Draw crosshair lines (before selection)
        if selectionRect == nil {
            drawCrosshair(in: context)
            drawLoupe(at: mousePosition, in: context)
            drawCoordinateLabel(at: mousePosition)
            return
        }

        guard let rect = selectionRect else { return }

        // Clear the selection area to reveal the frozen/live content beneath
        context.setBlendMode(.clear)
        context.fill(rect)
        context.setBlendMode(.normal)

        // If we have a frozen image, redraw just the selected area without the dim
        if let frozen = frozenImage {
            context.saveGState()
            let clipPath = NSBezierPath(rect: rect)
            clipPath.addClip()
            NSImage(cgImage: frozen, size: bounds.size).draw(in: bounds)
            context.restoreGState()
        }

        // Draw selection border
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        // Corner handles
        drawCornerHandles(for: rect)

        // Thirds grid
        drawThirdsGrid(in: rect, context: context)

        // Dimension label
        let w = Int(rect.width)
        let h = Int(rect.height)
        let label = "\(w) x \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let labelPadding: CGFloat = 6
        let labelBgRect = NSRect(
            x: rect.midX - (labelSize.width + labelPadding * 2) / 2,
            y: rect.minY - labelSize.height - labelPadding * 2 - 4,
            width: labelSize.width + labelPadding * 2,
            height: labelSize.height + labelPadding
        )

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: labelBgRect, xRadius: 4, yRadius: 4).fill()

        let labelPoint = NSPoint(
            x: labelBgRect.origin.x + labelPadding,
            y: labelBgRect.origin.y + labelPadding / 2
        )
        (label as NSString).draw(at: labelPoint, withAttributes: attrs)
    }

    private func drawCrosshair(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [4, 4])

        context.move(to: CGPoint(x: 0, y: mousePosition.y))
        context.addLine(to: CGPoint(x: bounds.width, y: mousePosition.y))
        context.strokePath()

        context.move(to: CGPoint(x: mousePosition.x, y: 0))
        context.addLine(to: CGPoint(x: mousePosition.x, y: bounds.height))
        context.strokePath()

        context.restoreGState()
    }

    private func drawCoordinateLabel(at point: NSPoint) {
        guard let screen = self.window?.screen ?? NSScreen.main else { return }
        let ph = NSScreen.primaryHeight
        let cgX = Int(point.x + screen.frame.origin.x)
        let cgY = Int(ph - (point.y + screen.frame.origin.y))
        let label = "\(cgX), \(cgY)"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 4
        let bgRect = NSRect(
            x: point.x + 14,
            y: point.y + 14,
            width: labelSize.width + padding * 2,
            height: labelSize.height + padding
        )

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()

        let textPoint = NSPoint(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding / 2)
        (label as NSString).draw(at: textPoint, withAttributes: attrs)
    }

    // MARK: - Loupe

    private func drawLoupe(at viewPoint: NSPoint, in context: CGContext) {
        let loupeSize: CGFloat = 120
        let magnification: CGFloat = 4
        let captureRadius = loupeSize / magnification / 2

        // Convert view point to CG global coordinates for capture
        guard let screen = self.window?.screen ?? NSScreen.main else { return }
        let ph = NSScreen.primaryHeight
        let screenPoint = CGPoint(
            x: viewPoint.x + screen.frame.origin.x,
            y: ph - (viewPoint.y + screen.frame.origin.y)
        )

        let captureRect = CGRect(
            x: screenPoint.x - captureRadius,
            y: screenPoint.y - captureRadius,
            width: captureRadius * 2,
            height: captureRadius * 2
        )

        guard let capturedImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return }

        // Position loupe offset from cursor
        let offset: CGFloat = 24
        var loupeX = viewPoint.x + offset
        var loupeY = viewPoint.y + offset
        if loupeX + loupeSize + 20 > bounds.width { loupeX = viewPoint.x - loupeSize - offset }
        if loupeY + loupeSize + 30 > bounds.height { loupeY = viewPoint.y - loupeSize - offset }

        let loupeRect = NSRect(x: loupeX, y: loupeY, width: loupeSize, height: loupeSize)

        context.saveGState()

        // Shadow
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.5).cgColor)

        // Clip to circle
        let clipPath = CGPath(ellipseIn: loupeRect, transform: nil)
        context.addPath(clipPath)
        context.clip()

        // Draw magnified content (no interpolation for crisp pixels)
        context.interpolationQuality = .none
        context.draw(capturedImage, in: loupeRect)

        // Crosshair at center
        let cx = loupeRect.midX
        let cy = loupeRect.midY
        let crossSize: CGFloat = 6
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: cx - crossSize, y: cy))
        context.addLine(to: CGPoint(x: cx + crossSize, y: cy))
        context.strokePath()
        context.move(to: CGPoint(x: cx, y: cy - crossSize))
        context.addLine(to: CGPoint(x: cx, y: cy + crossSize))
        context.strokePath()

        // Pixel grid
        let pixelSize = loupeSize / (captureRadius * 2)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(0.5)
        for i in 0...Int(captureRadius * 2) {
            let lineOffset = CGFloat(i) * pixelSize
            context.move(to: CGPoint(x: loupeRect.origin.x + lineOffset, y: loupeRect.origin.y))
            context.addLine(to: CGPoint(x: loupeRect.origin.x + lineOffset, y: loupeRect.maxY))
            context.strokePath()
            context.move(to: CGPoint(x: loupeRect.origin.x, y: loupeRect.origin.y + lineOffset))
            context.addLine(to: CGPoint(x: loupeRect.maxX, y: loupeRect.origin.y + lineOffset))
            context.strokePath()
        }

        context.restoreGState()

        // Border ring
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(ovalIn: loupeRect.insetBy(dx: 1, dy: 1))
        borderPath.lineWidth = 2.5
        borderPath.stroke()
    }

    private func drawCornerHandles(for rect: NSRect) {
        let handleSize: CGFloat = 6
        let handles = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ]

        NSColor.white.setFill()
        for point in handles {
            let handleRect = NSRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSBezierPath(roundedRect: handleRect, xRadius: 1, yRadius: 1).fill()
        }
    }

    private func drawThirdsGrid(in rect: NSRect, context: CGContext) {
        guard rect.width > 60, rect.height > 60 else { return }

        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(0.5)

        let thirdW = rect.width / 3
        let thirdH = rect.height / 3

        for i in 1...2 {
            let x = rect.origin.x + thirdW * CGFloat(i)
            context.move(to: CGPoint(x: x, y: rect.origin.y))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.strokePath()

            let y = rect.origin.y + thirdH * CGFloat(i)
            context.move(to: CGPoint(x: rect.origin.x, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.strokePath()
        }

        context.restoreGState()
    }
}
