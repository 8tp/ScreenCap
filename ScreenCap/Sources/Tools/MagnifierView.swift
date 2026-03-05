import Cocoa

class MagnifierView: NSView {
    var magnification: CGFloat = 4.0
    var loupeSize: CGFloat = 120

    private var capturedRegion: CGImage?

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = capturedRegion else { return }

        // Draw loupe circle
        let path = NSBezierPath(ovalIn: bounds)
        path.addClip()

        context.interpolationQuality = .none
        context.draw(image, in: bounds)

        // Border
        NSColor.white.setStroke()
        let border = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        border.stroke()

        // Crosshair
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let crosshairPath = NSBezierPath()
        crosshairPath.move(to: NSPoint(x: center.x - 8, y: center.y))
        crosshairPath.line(to: NSPoint(x: center.x + 8, y: center.y))
        crosshairPath.move(to: NSPoint(x: center.x, y: center.y - 8))
        crosshairPath.line(to: NSPoint(x: center.x, y: center.y + 8))
        crosshairPath.lineWidth = 1
        crosshairPath.stroke()
    }

    func update(at screenPoint: CGPoint) {
        let captureSize = loupeSize / magnification
        let captureRect = CGRect(
            x: screenPoint.x - captureSize / 2,
            y: screenPoint.y - captureSize / 2,
            width: captureSize,
            height: captureSize
        )

        capturedRegion = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        )

        needsDisplay = true
    }
}
