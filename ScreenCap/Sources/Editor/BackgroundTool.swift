import Cocoa
import SwiftUI

// MARK: - Background Style Presets

struct BackgroundPreset {
    let name: String
    let colors: [NSColor]  // gradient stops (1 = solid, 2+ = gradient)
    let angle: CGFloat     // gradient angle in degrees

    static let presets: [BackgroundPreset] = [
        BackgroundPreset(name: "Ocean", colors: [
            NSColor(red: 0.07, green: 0.30, blue: 0.85, alpha: 1),
            NSColor(red: 0.04, green: 0.75, blue: 0.86, alpha: 1)
        ], angle: 135),
        BackgroundPreset(name: "Sunset", colors: [
            NSColor(red: 0.98, green: 0.36, blue: 0.35, alpha: 1),
            NSColor(red: 0.98, green: 0.72, blue: 0.33, alpha: 1)
        ], angle: 135),
        BackgroundPreset(name: "Purple Haze", colors: [
            NSColor(red: 0.50, green: 0.20, blue: 0.90, alpha: 1),
            NSColor(red: 0.90, green: 0.30, blue: 0.60, alpha: 1)
        ], angle: 135),
        BackgroundPreset(name: "Forest", colors: [
            NSColor(red: 0.10, green: 0.55, blue: 0.35, alpha: 1),
            NSColor(red: 0.40, green: 0.80, blue: 0.55, alpha: 1)
        ], angle: 135),
        BackgroundPreset(name: "Night", colors: [
            NSColor(red: 0.10, green: 0.10, blue: 0.20, alpha: 1),
            NSColor(red: 0.25, green: 0.20, blue: 0.45, alpha: 1)
        ], angle: 180),
        BackgroundPreset(name: "Rose", colors: [
            NSColor(red: 0.95, green: 0.40, blue: 0.55, alpha: 1),
            NSColor(red: 0.60, green: 0.25, blue: 0.80, alpha: 1)
        ], angle: 135),
        BackgroundPreset(name: "Sky", colors: [
            NSColor(red: 0.40, green: 0.70, blue: 1.0, alpha: 1),
            NSColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 1)
        ], angle: 180),
        BackgroundPreset(name: "Ember", colors: [
            NSColor(red: 0.90, green: 0.15, blue: 0.10, alpha: 1),
            NSColor(red: 0.20, green: 0.05, blue: 0.05, alpha: 1)
        ], angle: 180),
        BackgroundPreset(name: "Slate", colors: [
            NSColor(red: 0.35, green: 0.40, blue: 0.50, alpha: 1),
            NSColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 1)
        ], angle: 180),
        BackgroundPreset(name: "White", colors: [.white], angle: 0),
        BackgroundPreset(name: "Dark", colors: [
            NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        ], angle: 0),
        BackgroundPreset(name: "Transparent", colors: [], angle: 0),
    ]
}

// MARK: - Background Configuration

struct BackgroundConfig {
    var preset: BackgroundPreset = BackgroundPreset.presets[0]
    var padding: CGFloat = 64
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 20
    var shadowOpacity: CGFloat = 0.4
    var aspectRatio: BackgroundAspectRatio = .auto

    enum BackgroundAspectRatio: String, CaseIterable {
        case auto = "Auto"
        case sixteenNine = "16:9"
        case fourThree = "4:3"
        case square = "1:1"
        case twitter = "Twitter"
    }
}

// MARK: - Background Renderer

class BackgroundRenderer {
    static func render(image: NSImage, config: BackgroundConfig) -> NSImage {
        let imgSize = image.size
        let pad = config.padding

        // Calculate output size based on aspect ratio
        var outputSize: NSSize
        switch config.aspectRatio {
        case .auto:
            outputSize = NSSize(width: imgSize.width + pad * 2, height: imgSize.height + pad * 2)
        case .sixteenNine:
            let w = imgSize.width + pad * 2
            let h = w * 9.0 / 16.0
            outputSize = NSSize(width: w, height: max(h, imgSize.height + pad * 2))
        case .fourThree:
            let w = imgSize.width + pad * 2
            let h = w * 3.0 / 4.0
            outputSize = NSSize(width: w, height: max(h, imgSize.height + pad * 2))
        case .square:
            let side = max(imgSize.width, imgSize.height) + pad * 2
            outputSize = NSSize(width: side, height: side)
        case .twitter:
            let w = imgSize.width + pad * 2
            let h = w * 9.0 / 16.0
            outputSize = NSSize(width: w, height: max(h, imgSize.height + pad * 2))
        }

        let result = NSImage(size: outputSize)
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        let fullRect = NSRect(origin: .zero, size: outputSize)

        // Draw background
        if config.preset.colors.isEmpty {
            // Transparent — draw checkerboard pattern
            drawCheckerboard(in: context, rect: fullRect)
        } else if config.preset.colors.count == 1 {
            // Solid color
            context.setFillColor(config.preset.colors[0].cgColor)
            context.fill(fullRect)
        } else {
            // Gradient
            drawGradient(in: context, rect: fullRect, colors: config.preset.colors, angle: config.preset.angle)
        }

        // Center the image
        let imgX = (outputSize.width - imgSize.width) / 2
        let imgY = (outputSize.height - imgSize.height) / 2
        let imgRect = NSRect(x: imgX, y: imgY, width: imgSize.width, height: imgSize.height)

        // Draw shadow
        if config.shadowRadius > 0 && !config.preset.colors.isEmpty {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -4),
                blur: config.shadowRadius,
                color: NSColor.black.withAlphaComponent(config.shadowOpacity).cgColor
            )
            let shadowPath = NSBezierPath(roundedRect: imgRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
            NSColor.black.setFill()
            shadowPath.fill()
            context.restoreGState()
        }

        // Draw image with rounded corners
        context.saveGState()
        let clipPath = NSBezierPath(roundedRect: imgRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
        clipPath.addClip()
        image.draw(in: imgRect)
        context.restoreGState()

        result.unlockFocus()
        return result
    }

    private static func drawGradient(in context: CGContext, rect: NSRect, colors: [NSColor], angle: CGFloat) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        let locations: [CGFloat] = colors.enumerated().map { CGFloat($0.offset) / CGFloat(colors.count - 1) }

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) else { return }

        let radians = angle * .pi / 180
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = max(rect.width, rect.height)

        let start = CGPoint(
            x: center.x - cos(radians) * length / 2,
            y: center.y - sin(radians) * length / 2
        )
        let end = CGPoint(
            x: center.x + cos(radians) * length / 2,
            y: center.y + sin(radians) * length / 2
        )

        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func drawCheckerboard(in context: CGContext, rect: NSRect) {
        let tileSize: CGFloat = 12
        let light = NSColor(white: 0.95, alpha: 1).cgColor
        let dark = NSColor(white: 0.85, alpha: 1).cgColor

        var y: CGFloat = 0
        var row = 0
        while y < rect.height {
            var x: CGFloat = 0
            var col = 0
            while x < rect.width {
                context.setFillColor((row + col) % 2 == 0 ? light : dark)
                context.fill(CGRect(x: x, y: y, width: tileSize, height: tileSize))
                x += tileSize
                col += 1
            }
            y += tileSize
            row += 1
        }
    }
}

// MARK: - Background Panel Window

class BackgroundPanelController {
    private var window: NSWindow?
    var onApply: ((BackgroundConfig) -> Void)?
    private var config = BackgroundConfig()
    private var previewImageView: NSImageView?
    private var sourceImage: NSImage?
    private var presetButtons: [PresetButton] = []

    func show(for image: NSImage) {
        sourceImage = image

        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 580
        let bottomBarHeight: CGFloat = 56

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Background"
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true

        // Root view holds scroll view + pinned bottom bar
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        rootView.wantsLayer = true

        // --- Bottom bar (pinned) ---
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: bottomBarHeight))
        bottomBar.wantsLayer = true
        rootView.addSubview(bottomBar)

        let applyBtn = NSButton(title: "Apply Background", target: self, action: #selector(applyClicked))
        applyBtn.bezelStyle = .rounded
        applyBtn.controlSize = .large
        applyBtn.keyEquivalent = "\r"
        applyBtn.frame = NSRect(x: panelWidth / 2 - 75, y: 12, width: 150, height: 32)
        bottomBar.addSubview(applyBtn)

        // --- Scrollable content ---
        // Build content from top down, then flip y at the end
        let scrollContentWidth = panelWidth
        var y: CGFloat = 0  // we'll calculate total height, then position from top

        // Calculate all positions top-down first
        let previewSize: CGFloat = 160
        let topPadding: CGFloat = 16
        let sectionGap: CGFloat = 16
        let presets = BackgroundPreset.presets
        let gridCols = 4
        let cellSize: CGFloat = 60
        let gridSpacing: CGFloat = 8
        let gridWidth = CGFloat(gridCols) * cellSize + CGFloat(gridCols - 1) * gridSpacing
        let gridX = (scrollContentWidth - gridWidth) / 2
        let rows = (presets.count + gridCols - 1) / gridCols
        let gridHeight = CGFloat(rows) * (cellSize + gridSpacing) - gridSpacing
        let sliderRowHeight: CGFloat = 28
        let bottomPadding: CGFloat = 12

        let totalContentHeight = topPadding + previewSize + sectionGap + 18 + 4 + gridHeight + sectionGap + sliderRowHeight * 3 + bottomPadding

        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: scrollContentWidth, height: totalContentHeight))
        documentView.wantsLayer = true

        // Position everything top-down (y from top of documentView)
        y = totalContentHeight - topPadding

        // Preview
        y -= previewSize
        let previewX = (scrollContentWidth - previewSize) / 2
        let previewView = NSImageView(frame: NSRect(x: previewX, y: y, width: previewSize, height: previewSize))
        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.imageFrameStyle = .none
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 8
        previewView.layer?.masksToBounds = true
        documentView.addSubview(previewView)
        self.previewImageView = previewView
        updatePreview()

        y -= sectionGap

        // Preset grid header
        y -= 18
        let presetsLabel = NSTextField(labelWithString: "Background")
        presetsLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        presetsLabel.textColor = .secondaryLabelColor
        presetsLabel.frame = NSRect(x: 16, y: y, width: 200, height: 16)
        documentView.addSubview(presetsLabel)
        y -= 4

        // Preset grid
        presetButtons = []
        for (i, preset) in presets.enumerated() {
            let col = i % gridCols
            let row = i / gridCols
            let bx = gridX + CGFloat(col) * (cellSize + gridSpacing)
            let by = y - CGFloat(row + 1) * (cellSize + gridSpacing) + gridSpacing

            let button = PresetButton(frame: NSRect(x: bx, y: by, width: cellSize, height: cellSize))
            button.preset = preset
            button.isSelectedPreset = (i == 0)
            button.tag = i
            button.target = self
            button.action = #selector(presetSelected(_:))
            documentView.addSubview(button)
            presetButtons.append(button)
        }

        y -= gridHeight + sectionGap

        // Padding slider
        y -= sliderRowHeight
        addSliderRow(to: documentView, label: "Padding", value: config.padding, min: 0, max: 128,
                     action: #selector(paddingChanged(_:)), valueTag: 100, y: y, width: scrollContentWidth)

        // Corner radius slider
        y -= sliderRowHeight
        addSliderRow(to: documentView, label: "Corners", value: config.cornerRadius, min: 0, max: 32,
                     action: #selector(radiusChanged(_:)), valueTag: 101, y: y, width: scrollContentWidth)

        // Shadow slider
        y -= sliderRowHeight
        addSliderRow(to: documentView, label: "Shadow", value: config.shadowRadius, min: 0, max: 60,
                     action: #selector(shadowChanged(_:)), valueTag: 102, y: y, width: scrollContentWidth)

        // Scroll view
        let scrollViewHeight = panelHeight - bottomBarHeight
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: bottomBarHeight, width: panelWidth, height: scrollViewHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        rootView.addSubview(scrollView)

        // Scroll to top
        documentView.scroll(NSPoint(x: 0, y: totalContentHeight - scrollViewHeight))

        window.contentView = rootView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func addSliderRow(to parent: NSView, label: String, value: CGFloat, min: Double, max: Double,
                              action: Selector, valueTag: Int, y: CGFloat, width: CGFloat) {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .secondaryLabelColor
        lbl.frame = NSRect(x: 16, y: y, width: 60, height: 16)
        parent.addSubview(lbl)

        let slider = NSSlider(value: Double(value), minValue: min, maxValue: max, target: self, action: action)
        slider.frame = NSRect(x: 80, y: y - 2, width: width - 130, height: 20)
        slider.isContinuous = true
        slider.controlSize = .small
        parent.addSubview(slider)

        let valLabel = NSTextField(labelWithString: "\(Int(value))px")
        valLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valLabel.textColor = .secondaryLabelColor
        valLabel.frame = NSRect(x: width - 48, y: y, width: 40, height: 16)
        valLabel.alignment = .right
        valLabel.tag = valueTag
        parent.addSubview(valLabel)
    }

    private func updatePreview() {
        guard let source = sourceImage else { return }
        let rendered = BackgroundRenderer.render(image: source, config: config)
        previewImageView?.image = rendered
    }

    private func updateValueLabel(tag: Int, text: String) {
        guard let rootView = window?.contentView else { return }
        // Value labels are inside the scroll view's document view
        for subview in rootView.subviews {
            if let scrollView = subview as? NSScrollView,
               let docView = scrollView.documentView {
                for child in docView.subviews {
                    if let tf = child as? NSTextField, tf.tag == tag {
                        tf.stringValue = text
                        return
                    }
                }
            }
        }
    }

    @objc private func presetSelected(_ sender: NSButton) {
        let presets = BackgroundPreset.presets
        guard sender.tag < presets.count else { return }
        config.preset = presets[sender.tag]
        for btn in presetButtons {
            btn.isSelectedPreset = (btn.tag == sender.tag)
            btn.needsDisplay = true
        }
        updatePreview()
    }

    @objc private func paddingChanged(_ sender: NSSlider) {
        config.padding = CGFloat(sender.doubleValue)
        updateValueLabel(tag: 100, text: "\(Int(config.padding))px")
        updatePreview()
    }

    @objc private func radiusChanged(_ sender: NSSlider) {
        config.cornerRadius = CGFloat(sender.doubleValue)
        updateValueLabel(tag: 101, text: "\(Int(config.cornerRadius))px")
        updatePreview()
    }

    @objc private func shadowChanged(_ sender: NSSlider) {
        config.shadowRadius = CGFloat(sender.doubleValue)
        updateValueLabel(tag: 102, text: "\(Int(config.shadowRadius))px")
        updatePreview()
    }

    @objc private func applyClicked() {
        onApply?(config)
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - Preset Button (gradient swatch)

class PresetButton: NSButton {
    var preset: BackgroundPreset?
    var isSelectedPreset: Bool = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isBordered = false
        title = ""
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let preset = preset else { return }

        let rect = bounds.insetBy(dx: 1, dy: 1)

        if preset.colors.isEmpty {
            // Checkerboard for transparent
            let tileSize: CGFloat = 6
            let light = NSColor(white: 0.95, alpha: 1).cgColor
            let dark = NSColor(white: 0.82, alpha: 1).cgColor
            var py: CGFloat = rect.minY
            var row = 0
            while py < rect.maxY {
                var px: CGFloat = rect.minX
                var col = 0
                while px < rect.maxX {
                    context.setFillColor((row + col) % 2 == 0 ? light : dark)
                    context.fill(CGRect(x: px, y: py, width: min(tileSize, rect.maxX - px), height: min(tileSize, rect.maxY - py)))
                    px += tileSize
                    col += 1
                }
                py += tileSize
                row += 1
            }
        } else if preset.colors.count == 1 {
            context.setFillColor(preset.colors[0].cgColor)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            path.addClip()
            context.fill(rect)
        } else {
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            path.addClip()

            let cgColors = preset.colors.map { $0.cgColor } as CFArray
            let locations: [CGFloat] = preset.colors.enumerated().map { CGFloat($0.offset) / CGFloat(preset.colors.count - 1) }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations) {
                let radians = preset.angle * .pi / 180
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let length = max(rect.width, rect.height)
                let start = CGPoint(x: center.x - cos(radians) * length / 2, y: center.y - sin(radians) * length / 2)
                let end = CGPoint(x: center.x + cos(radians) * length / 2, y: center.y + sin(radians) * length / 2)
                context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }

        // Draw preset name with adaptive color
        let isLight = preset.name == "White" || preset.name == "Sky" || preset.name == "Transparent"
        let textColor: NSColor = isLight ? .black : .white
        let shadowColor: NSColor = isLight ? NSColor.white.withAlphaComponent(0.8) : NSColor.black.withAlphaComponent(0.8)

        let shadow = NSShadow()
        shadow.shadowColor = shadowColor
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .shadow: shadow,
        ]
        let textSize = (preset.name as NSString).size(withAttributes: attrs)
        let textPoint = NSPoint(x: bounds.midX - textSize.width / 2, y: 4)
        (preset.name as NSString).draw(at: textPoint, withAttributes: attrs)

        // Selection ring
        if isSelectedPreset {
            context.resetClip()
            let ringRect = bounds.insetBy(dx: -1, dy: -1)
            let ringPath = NSBezierPath(roundedRect: ringRect, xRadius: 9, yRadius: 9)
            NSColor.controlAccentColor.setStroke()
            ringPath.lineWidth = 2.5
            ringPath.stroke()
        }
    }
}
