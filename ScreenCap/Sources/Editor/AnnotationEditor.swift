import Cocoa
import SwiftUI

class AnnotationEditorController: NSObject, NSWindowDelegate {
    private var editorWindow: NSWindow?
    private var canvas: AnnotationCanvas?
    private var cropBar: NSView?
    private var backgroundPanel: BackgroundPanelController?
    private var toolbar: EditorToolbar?
    private var currentImageURL: URL?
    private var scrollView: NSScrollView?
    private var clipViewObserver: NSObjectProtocol?
    private var relayoutWorkItem: DispatchWorkItem?

    func windowWillClose(_ notification: Notification) {
        if let obs = clipViewObserver {
            NotificationCenter.default.removeObserver(obs)
            clipViewObserver = nil
        }
        relayoutWorkItem?.cancel()
        relayoutWorkItem = nil
        editorWindow = nil
        canvas = nil
        scrollView = nil
        toolbar = nil
        cropBar = nil
    }

    func open(imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return }

        // Close any existing editor
        if let obs = clipViewObserver {
            NotificationCenter.default.removeObserver(obs)
            clipViewObserver = nil
        }
        editorWindow?.orderOut(nil)

        let imageSize = image.size
        let maxWidth: CGFloat = 1200
        let maxHeight: CGFloat = 800
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1.0)
        let canvasSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let toolbarHeight: CGFloat = 52
        let bottomBarHeight: CGFloat = 44

        // Compute toolbar minimum width to avoid clipping
        let tempToolbar = EditorToolbar(frame: NSRect(x: 0, y: 0, width: 1200, height: toolbarHeight))
        let minToolbarWidth = tempToolbar.minimumWidth
        let windowWidth = max(canvasSize.width + 40, minToolbarWidth)
        let windowHeight = canvasSize.height + toolbarHeight + bottomBarHeight + 20

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: windowWidth, height: windowHeight)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenCap Editor"
        window.subtitle = imageURL.lastPathComponent
        window.center()
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: minToolbarWidth, height: 400)
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Content view
        let contentView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: windowWidth, height: windowHeight)))
        contentView.wantsLayer = true

        // Editor toolbar (top)
        let toolbarView = EditorToolbar(frame: NSRect(x: 0, y: canvasSize.height + bottomBarHeight + 20, width: windowWidth, height: toolbarHeight))
        toolbarView.autoresizingMask = [.width]
        contentView.addSubview(toolbarView)
        self.toolbar = toolbarView

        // Canvas area with scroll/zoom support
        let containerHeight = canvasSize.height + 20
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: bottomBarHeight, width: windowWidth, height: containerHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 5.0
        scrollView.magnification = 1.0
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.12, alpha: 1)
        scrollView.borderType = .noBorder

        let canvasView = AnnotationCanvas(frame: NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
        canvasView.baseImage = image
        canvasView.wantsLayer = true
        canvasView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        canvasView.layer?.cornerRadius = 2
        canvasView.layer?.masksToBounds = true
        canvasView.shadow = NSShadow()
        canvasView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        canvasView.layer?.shadowOffset = CGSize(width: 0, height: -3)
        canvasView.layer?.shadowRadius = 12
        canvasView.layer?.shadowOpacity = 1

        // Center the canvas within the scroll view using a flipped container
        let documentView = CenteredDocumentView(frame: NSRect(x: 0, y: 0, width: max(windowWidth, canvasSize.width), height: max(containerHeight, canvasSize.height)))
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        let canvasX = max(0, (documentView.frame.width - canvasSize.width) / 2)
        let canvasY = max(0, (documentView.frame.height - canvasSize.height) / 2)
        canvasView.frame.origin = NSPoint(x: canvasX, y: canvasY)
        documentView.addSubview(canvasView)

        scrollView.documentView = documentView
        contentView.addSubview(scrollView)
        self.canvas = canvasView
        self.scrollView = scrollView

        // Re-center canvas when the scroll view resizes (window resize, zoom, etc.)
        scrollView.contentView.postsFrameChangedNotifications = true
        clipViewObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            // Debounce relayout to avoid thrashing during live resize
            self?.relayoutWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.relayoutDocumentView() }
            self?.relayoutWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        // Wire toolbar to canvas
        toolbarView.onToolSelected = { [weak canvasView] tool in
            canvasView?.currentTool = tool
        }
        toolbarView.onColorSelected = { [weak canvasView] color in
            canvasView?.currentColor = color
        }
        toolbarView.onLineWidthChanged = { [weak canvasView] width in
            canvasView?.currentLineWidth = width
        }
        toolbarView.onFillToggled = { [weak canvasView] filled in
            canvasView?.currentFilled = filled
        }
        toolbarView.onUndo = { [weak canvasView] in
            canvasView?.performUndo()
        }
        toolbarView.onRedo = { [weak canvasView] in
            canvasView?.performRedo()
        }
        toolbarView.onBackground = { [weak self] in
            self?.showBackgroundPanel()
        }

        // Crop callback
        canvasView.onCropApplied = { [weak self] _ in
            self?.showCropBar()
        }

        // Canvas size changed (after crop undo/redo)
        canvasView.onCanvasSizeChanged = { [weak self] in
            self?.relayoutDocumentView()
        }

        // Bottom bar
        let bottomBar = buildBottomBar(width: windowWidth, height: bottomBarHeight)
        contentView.addSubview(bottomBar)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.editorWindow = window
        self.currentImageURL = imageURL
    }

    private func relayoutDocumentView() {
        guard let scrollView = scrollView,
              let documentView = scrollView.documentView,
              let canvasView = canvas else { return }

        let clipSize = scrollView.contentView.bounds.size
        let canvasSize = canvasView.frame.size

        let docWidth = max(clipSize.width, canvasSize.width)
        let docHeight = max(clipSize.height, canvasSize.height)
        documentView.frame.size = NSSize(width: docWidth, height: docHeight)

        let canvasX = max(0, (docWidth - canvasSize.width) / 2)
        let canvasY = max(0, (docHeight - canvasSize.height) / 2)
        canvasView.frame.origin = NSPoint(x: canvasX, y: canvasY)
    }

    // MARK: - Bottom Bar

    private func buildBottomBar(width: CGFloat, height: CGFloat) -> NSView {
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bar.blendingMode = .withinWindow
        bar.material = .titlebar
        bar.state = .active
        bar.autoresizingMask = [.width]

        let separator = NSView(frame: NSRect(x: 0, y: height - 1, width: width, height: 1))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.autoresizingMask = [.width]
        bar.addSubview(separator)

        var x: CGFloat = 12
        let btnH: CGFloat = 26
        let btnY: CGFloat = (height - btnH) / 2

        // Save actions on the left
        let copyBtn = makeBarButton(title: "Copy", icon: "doc.on.clipboard", action: #selector(copyToClipboard))
        copyBtn.frame = NSRect(x: x, y: btnY, width: 72, height: btnH)
        bar.addSubview(copyBtn)
        x += 78

        let saveBtn = makeBarButton(title: "Save", icon: "square.and.arrow.down", action: #selector(saveImage))
        saveBtn.frame = NSRect(x: x, y: btnY, width: 64, height: btnH)
        bar.addSubview(saveBtn)
        x += 70

        let saveAsBtn = makeBarButton(title: "Save As...", icon: "folder", action: #selector(saveImageAs))
        saveAsBtn.frame = NSRect(x: x, y: btnY, width: 84, height: btnH)
        bar.addSubview(saveAsBtn)
        x += 96

        // Crop bar (hidden initially)
        let cropContainer = NSView(frame: NSRect(x: x, y: 0, width: 200, height: height))
        cropContainer.isHidden = true

        let applyCrop = NSButton(title: "Apply Crop", target: self, action: #selector(applyCrop))
        applyCrop.bezelStyle = .rounded
        applyCrop.contentTintColor = .systemGreen
        applyCrop.controlSize = .small
        applyCrop.frame = NSRect(x: 0, y: btnY, width: 90, height: btnH)
        cropContainer.addSubview(applyCrop)

        let cancelCrop = NSButton(title: "Cancel", target: self, action: #selector(cancelCrop))
        cancelCrop.bezelStyle = .rounded
        cancelCrop.controlSize = .small
        cancelCrop.frame = NSRect(x: 96, y: btnY, width: 65, height: btnH)
        cropContainer.addSubview(cancelCrop)

        bar.addSubview(cropContainer)
        self.cropBar = cropContainer

        // Zoom / info on the right
        let infoLabel = NSTextField(labelWithString: "ScreenCap Editor")
        infoLabel.font = .systemFont(ofSize: 10, weight: .medium)
        infoLabel.textColor = .tertiaryLabelColor
        infoLabel.frame = NSRect(x: width - 120, y: btnY + 4, width: 110, height: 16)
        infoLabel.alignment = .right
        infoLabel.autoresizingMask = [.minXMargin]
        bar.addSubview(infoLabel)

        return bar
    }

    private func makeBarButton(title: String, icon: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        return button
    }

    // MARK: - Crop

    private func showCropBar() { cropBar?.isHidden = false }
    private func hideCropBar() { cropBar?.isHidden = true }

    @objc private func applyCrop() {
        canvas?.applyCrop()
        hideCropBar()
        relayoutDocumentView()
    }

    @objc private func cancelCrop() {
        canvas?.cancelCrop()
        hideCropBar()
    }

    // MARK: - Background

    private func showBackgroundPanel() {
        guard let image = canvas?.renderFinalImage() else { return }
        let panel = BackgroundPanelController()
        panel.onApply = { [weak self] config in
            guard let self = self, let canvas = self.canvas, let currentImage = canvas.renderFinalImage() else { return }
            canvas.pushUndo()
            let result = BackgroundRenderer.render(image: currentImage, config: config)
            canvas.baseImage = result
            canvas.annotations.removeAll()
            canvas.needsDisplay = true
            self.relayoutDocumentView()
        }
        panel.show(for: image)
        backgroundPanel = panel
    }

    // MARK: - Save / Copy

    @objc private func copyToClipboard() {
        guard let image = canvas?.renderFinalImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        Toast.show(message: "Copied to clipboard")
    }

    @objc private func saveImage() {
        guard let image = canvas?.renderFinalImage(),
              let url = currentImageURL else { return }
        saveNSImage(image, to: url)
        Toast.show(message: "Saved")
        editorWindow?.orderOut(nil)
    }

    @objc private func saveImageAs() {
        guard let image = canvas?.renderFinalImage() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = currentImageURL?.lastPathComponent ?? "screenshot.png"

        if panel.runModal() == .OK, let url = panel.url {
            saveNSImage(image, to: url)
            Toast.show(message: "Saved to \(url.lastPathComponent)")
        }
    }

    private func saveNSImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return }

        let ext = url.pathExtension.lowercased()
        let data: Data?
        switch ext {
        case "jpg", "jpeg":
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: Defaults.shared.jpegQuality])
        case "tiff", "tif":
            data = bitmap.representation(using: .tiff, properties: [:])
        default:
            data = bitmap.representation(using: .png, properties: [:])
        }
        try? data?.write(to: url)
    }
}

// MARK: - Editor Toolbar

class EditorToolbar: NSView {
    var onToolSelected: ((AnnotationToolType) -> Void)?
    var onColorSelected: ((NSColor) -> Void)?
    var onLineWidthChanged: ((CGFloat) -> Void)?
    var onFillToggled: ((Bool) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onBackground: (() -> Void)?

    private var selectedTool: AnnotationToolType = .arrow
    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var selectedColorIndex: Int = 0
    private var fillButton: NSButton?

    private let tools: [AnnotationToolType] = [.select, .arrow, .rectangle, .ellipse, .line, .text, .freehand, .highlight, .blur, .numberedStep, .crop]
    private let colorPalette: [(NSColor, String)] = [
        (.systemRed, "Red"), (.systemOrange, "Orange"), (.systemYellow, "Yellow"),
        (.systemGreen, "Green"), (.systemBlue, "Blue"), (.systemPurple, "Purple"),
        (.black, "Black"), (.white, "White")
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// The minimum width this toolbar needs to display all controls without clipping.
    private(set) var minimumWidth: CGFloat = 0

    private func setupViews() {
        // Vibrancy background
        let effectView = NSVisualEffectView(frame: bounds)
        effectView.blendingMode = .withinWindow
        effectView.material = .titlebar
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        // Bottom separator
        let separator = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: 1))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.autoresizingMask = [.width]
        addSubview(separator)

        let btnSize: CGFloat = 26
        let colorSize: CGFloat = 18
        let gap: CGFloat = 8  // gap around dividers
        let y: CGFloat = (bounds.height - btnSize) / 2
        let colorY: CGFloat = (bounds.height - colorSize) / 2
        var x: CGFloat = 8

        // Tool buttons — tightly packed
        for (i, tool) in tools.enumerated() {
            let button = NSButton(frame: NSRect(x: x, y: y, width: btnSize, height: btnSize))
            button.bezelStyle = .accessoryBarAction
            button.image = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.rawValue)
            button.imagePosition = .imageOnly
            button.toolTip = tool.rawValue
            button.tag = i
            button.target = self
            button.action = #selector(toolButtonClicked(_:))
            button.state = (i == 0) ? .on : .off
            if i == 0 { button.contentTintColor = .controlAccentColor }
            addSubview(button)
            toolButtons.append(button)
            x += btnSize
        }

        x += gap
        addDivider(at: x)
        x += 1 + gap

        // Color palette
        for (i, (color, name)) in colorPalette.enumerated() {
            let button = NSButton(frame: NSRect(x: x, y: colorY, width: colorSize, height: colorSize))
            button.wantsLayer = true
            button.isBordered = false
            button.title = ""
            button.layer?.cornerRadius = colorSize / 2
            button.layer?.backgroundColor = color.cgColor
            button.toolTip = name
            button.tag = i
            button.target = self
            button.action = #selector(colorButtonClicked(_:))

            if color == .white || color == .systemYellow {
                button.layer?.borderWidth = 1
                button.layer?.borderColor = NSColor.separatorColor.cgColor
            }
            if i == 0 {
                button.layer?.borderWidth = 2
                button.layer?.borderColor = NSColor.controlAccentColor.cgColor
            }

            addSubview(button)
            colorButtons.append(button)
            x += colorSize + 2
        }

        x += gap
        addDivider(at: x)
        x += 1 + gap

        // Fill toggle
        let fillBtn = NSButton(frame: NSRect(x: x, y: y, width: btnSize, height: btnSize))
        fillBtn.bezelStyle = .accessoryBarAction
        fillBtn.image = NSImage(systemSymbolName: "square.fill", accessibilityDescription: "Fill")
        fillBtn.imagePosition = .imageOnly
        fillBtn.toolTip = "Toggle Fill"
        fillBtn.target = self
        fillBtn.action = #selector(fillToggled(_:))
        fillBtn.state = .off
        addSubview(fillBtn)
        self.fillButton = fillBtn
        x += btnSize + 4

        // Line width slider (compact)
        let sliderCenterY: CGFloat = bounds.height / 2
        let slider = NSSlider(value: 3, minValue: 1, maxValue: 12, target: self, action: #selector(lineWidthChanged(_:)))
        slider.frame = NSRect(x: x, y: sliderCenterY - 10, width: 50, height: 20)
        slider.isContinuous = true
        slider.controlSize = .small
        addSubview(slider)
        x += 54

        x += gap
        addDivider(at: x)
        x += 1 + gap

        // Background button
        let bgButton = NSButton(frame: NSRect(x: x, y: y, width: btnSize, height: btnSize))
        bgButton.bezelStyle = .accessoryBarAction
        bgButton.image = NSImage(systemSymbolName: "photo.artframe", accessibilityDescription: "Background")
        bgButton.imagePosition = .imageOnly
        bgButton.toolTip = "Add Background"
        bgButton.target = self
        bgButton.action = #selector(backgroundClicked)
        addSubview(bgButton)
        x += btnSize

        // Record where left-side content ends (for min width calculation)
        let leftContentEnd = x + 12 // 12px breathing room before undo/redo
        let undoRedoWidth: CGFloat = 62 // two 26px buttons + 10px gap + 8px margin
        minimumWidth = leftContentEnd + undoRedoWidth

        // Undo/Redo pinned to right edge
        let undoButton = NSButton(frame: NSRect(x: bounds.width - 60, y: y, width: btnSize, height: btnSize))
        undoButton.bezelStyle = .accessoryBarAction
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        undoButton.imagePosition = .imageOnly
        undoButton.toolTip = "Undo (⌘Z)"
        undoButton.target = self
        undoButton.action = #selector(undoClicked)
        undoButton.autoresizingMask = [.minXMargin]
        addSubview(undoButton)

        let redoButton = NSButton(frame: NSRect(x: bounds.width - 32, y: y, width: btnSize, height: btnSize))
        redoButton.bezelStyle = .accessoryBarAction
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        redoButton.imagePosition = .imageOnly
        redoButton.toolTip = "Redo (⇧⌘Z)"
        redoButton.target = self
        redoButton.action = #selector(redoClicked)
        redoButton.autoresizingMask = [.minXMargin]
        addSubview(redoButton)
    }

    private func addDivider(at x: CGFloat) {
        let divider = NSView(frame: NSRect(x: x, y: 10, width: 1, height: bounds.height - 20))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(divider)
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        guard sender.tag < tools.count else { return }
        selectedTool = tools[sender.tag]
        onToolSelected?(selectedTool)

        for (i, button) in toolButtons.enumerated() {
            button.state = i == sender.tag ? .on : .off
            button.contentTintColor = i == sender.tag ? .controlAccentColor : nil
        }
    }

    @objc private func colorButtonClicked(_ sender: NSButton) {
        guard sender.tag < colorPalette.count else { return }

        for (i, button) in colorButtons.enumerated() {
            if i == sender.tag {
                button.layer?.borderWidth = 2
                button.layer?.borderColor = NSColor.controlAccentColor.cgColor
            } else {
                let color = colorPalette[i].0
                if color == .white || color == .systemYellow {
                    button.layer?.borderWidth = 1
                    button.layer?.borderColor = NSColor.separatorColor.cgColor
                } else {
                    button.layer?.borderWidth = 0
                }
            }
        }

        selectedColorIndex = sender.tag
        onColorSelected?(colorPalette[sender.tag].0)
    }

    @objc private func fillToggled(_ sender: NSButton) {
        sender.state = sender.state == .on ? .off : .on
        sender.contentTintColor = sender.state == .on ? .controlAccentColor : nil
        onFillToggled?(sender.state == .on)
    }

    @objc private func lineWidthChanged(_ sender: NSSlider) {
        onLineWidthChanged?(CGFloat(sender.doubleValue))
    }

    @objc private func backgroundClicked() { onBackground?() }
    @objc private func undoClicked() { onUndo?() }
    @objc private func redoClicked() { onRedo?() }
}

// MARK: - Centered Document View for NSScrollView

/// A flipped NSView used as the scroll view's document view.
/// Flipped coordinates match the natural top-to-bottom layout model.
class CenteredDocumentView: NSView {
    override var isFlipped: Bool { true }
}
