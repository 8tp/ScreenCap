import Cocoa

class WindowSelector {
    private var overlayWindow: NSWindow?
    private let completion: (Result<CGImage, Error>) -> Void

    init(completion: @escaping (Result<CGImage, Error>) -> Void) {
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
        window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let view = WindowSelectorView(frame: screen.frame) { [weak self] result in
            self?.overlayWindow?.orderOut(nil)
            self?.overlayWindow = nil
            self?.completion(result)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        self.overlayWindow = window
        NSCursor.pointingHand.push()
    }

    static func listOnScreenWindows() -> [[String: Any]] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowList.filter { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return false }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0
            return width > 50 && height > 50
        }
    }
}

class WindowSelectorView: NSView {
    private var highlightedWindowInfo: [String: Any]?
    private var highlightRect: CGRect = .zero
    private let completion: (Result<CGImage, Error>) -> Void
    private var windowInfoList: [[String: Any]] = []

    init(frame: NSRect, completion: @escaping (Result<CGImage, Error>) -> Void) {
        self.completion = completion
        super.init(frame: frame)
        windowInfoList = WindowSelector.listOnScreenWindows()
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

    override func mouseMoved(with event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        // Convert to CG coordinates (flipped Y)
        guard let screen = NSScreen.main else { return }
        let cgMouseY = screen.frame.height - mouseLocation.y

        highlightedWindowInfo = nil
        highlightRect = .zero

        for info in windowInfoList {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let windowRect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            if windowRect.contains(CGPoint(x: mouseLocation.x, y: cgMouseY)) {
                highlightedWindowInfo = info
                // Convert CG rect to NSView coordinates
                highlightRect = CGRect(
                    x: windowRect.origin.x,
                    y: screen.frame.height - windowRect.origin.y - windowRect.height,
                    width: windowRect.width,
                    height: windowRect.height
                )
                break
            }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.pop()

        guard let windowInfo = highlightedWindowInfo,
              let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
            completion(.failure(CaptureError.cancelled))
            return
        }

        let includeShadow = Defaults.shared.includeWindowShadow
        let imageOption: CGWindowImageOption = includeShadow ? [.boundsIgnoreFraming, .shouldBeOpaque] : [.boundsIgnoreFraming, .nominalResolution]

        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, imageOption) else {
            completion(.failure(CaptureError.captureFailed))
            return
        }

        completion(.success(image))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard highlightRect != .zero else { return }

        // Draw highlight border around the hovered window
        NSColor.systemBlue.withAlphaComponent(0.3).setFill()
        let highlightPath = NSBezierPath(roundedRect: highlightRect, xRadius: 4, yRadius: 4)
        highlightPath.fill()

        NSColor.systemBlue.setStroke()
        highlightPath.lineWidth = 3
        highlightPath.stroke()

        // Show window name label
        if let name = highlightedWindowInfo?[kCGWindowOwnerName as String] as? String {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .backgroundColor: NSColor.black.withAlphaComponent(0.75)
            ]
            let labelPoint = NSPoint(x: highlightRect.minX + 6, y: highlightRect.maxY + 4)
            (name as NSString).draw(at: labelPoint, withAttributes: attrs)
        }
    }
}
