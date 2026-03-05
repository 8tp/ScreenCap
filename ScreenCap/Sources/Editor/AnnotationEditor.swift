import Cocoa
import SwiftUI

class AnnotationEditorController {
    private var editorWindow: NSWindow?
    private var canvas: AnnotationCanvas?

    func open(imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return }

        let imageSize = image.size
        let maxWidth: CGFloat = 1200
        let maxHeight: CGFloat = 800
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1.0)
        let canvasSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let toolbarHeight: CGFloat = 80
        let bottomBarHeight: CGFloat = 44

        let windowSize = NSSize(width: max(canvasSize.width, 600), height: canvasSize.height + toolbarHeight + bottomBarHeight)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenCap Editor - \(imageURL.lastPathComponent)"
        window.center()

        let contentView = NSView(frame: NSRect(origin: .zero, size: windowSize))

        // Toolbar
        let toolbar = EditorToolbar(frame: NSRect(x: 0, y: canvasSize.height + bottomBarHeight, width: windowSize.width, height: toolbarHeight))
        toolbar.autoresizingMask = [.width]
        contentView.addSubview(toolbar)

        // Canvas
        let canvasView = AnnotationCanvas(frame: NSRect(x: 0, y: bottomBarHeight, width: canvasSize.width, height: canvasSize.height))
        canvasView.baseImage = image
        canvasView.autoresizingMask = [.width, .height]
        contentView.addSubview(canvasView)
        self.canvas = canvasView

        toolbar.onToolSelected = { [weak canvasView] tool in
            canvasView?.currentTool = tool
        }
        toolbar.onColorSelected = { [weak canvasView] color in
            canvasView?.currentColor = color
        }
        toolbar.onUndo = { [weak canvasView] in
            canvasView?.performUndo()
        }
        toolbar.onRedo = { [weak canvasView] in
            canvasView?.performRedo()
        }

        // Bottom bar
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: windowSize.width, height: bottomBarHeight))
        bottomBar.autoresizingMask = [.width]

        let copyButton = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyToClipboard))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 10, y: 8, width: 140, height: 28)
        bottomBar.addSubview(copyButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveImage))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 160, y: 8, width: 80, height: 28)
        bottomBar.addSubview(saveButton)

        let saveAsButton = NSButton(title: "Save As...", target: self, action: #selector(saveImageAs))
        saveAsButton.bezelStyle = .rounded
        saveAsButton.frame = NSRect(x: 250, y: 8, width: 80, height: 28)
        bottomBar.addSubview(saveAsButton)

        contentView.addSubview(bottomBar)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.editorWindow = window
        self.currentImageURL = imageURL
    }

    private var currentImageURL: URL?

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
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?

    private var selectedTool: AnnotationToolType = .arrow

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupToolButtons()
        setupColorButtons()
        setupUndoRedo()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupToolButtons() {
        let tools: [AnnotationToolType] = [.arrow, .rectangle, .ellipse, .line, .text, .freehand, .highlight, .blur, .numberedStep, .crop]
        var x: CGFloat = 10

        for tool in tools {
            let button = NSButton(frame: NSRect(x: x, y: 40, width: 32, height: 32))
            button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.rawValue)
            button.toolTip = tool.rawValue
            button.tag = tools.firstIndex(of: tool) ?? 0
            button.target = self
            button.action = #selector(toolButtonClicked(_:))
            addSubview(button)
            x += 36
        }
    }

    private func setupColorButtons() {
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .black]
        var x: CGFloat = 10

        for (i, color) in colors.enumerated() {
            let button = NSButton(frame: NSRect(x: x, y: 6, width: 24, height: 24))
            button.bezelStyle = .circular
            button.wantsLayer = true
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = 12
            button.tag = i
            button.title = ""
            button.target = self
            button.action = #selector(colorButtonClicked(_:))
            addSubview(button)
            x += 28
        }
    }

    private func setupUndoRedo() {
        let undoButton = NSButton(frame: NSRect(x: bounds.width - 80, y: 40, width: 32, height: 32))
        undoButton.bezelStyle = .rounded
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        undoButton.target = self
        undoButton.action = #selector(undoClicked)
        undoButton.autoresizingMask = [.minXMargin]
        addSubview(undoButton)

        let redoButton = NSButton(frame: NSRect(x: bounds.width - 44, y: 40, width: 32, height: 32))
        redoButton.bezelStyle = .rounded
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        redoButton.target = self
        redoButton.action = #selector(redoClicked)
        redoButton.autoresizingMask = [.minXMargin]
        addSubview(redoButton)
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        let tools: [AnnotationToolType] = [.arrow, .rectangle, .ellipse, .line, .text, .freehand, .highlight, .blur, .numberedStep, .crop]
        guard sender.tag < tools.count else { return }
        selectedTool = tools[sender.tag]
        onToolSelected?(selectedTool)
    }

    @objc private func colorButtonClicked(_ sender: NSButton) {
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .black]
        guard sender.tag < colors.count else { return }
        onColorSelected?(colors[sender.tag])
    }

    @objc private func undoClicked() { onUndo?() }
    @objc private func redoClicked() { onRedo?() }
}
