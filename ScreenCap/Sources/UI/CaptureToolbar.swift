import Cocoa

/// Floating "All-in-One" capture toolbar.
/// Appears centered on screen as a pill-shaped HUD with all capture modes.
class CaptureToolbarController {
    private var overlayWindow: NSWindow?
    private var backdropWindow: NSWindow?
    private var escMonitor: Any?

    var onCaptureFullscreen: (() -> Void)?
    var onCaptureArea: (() -> Void)?
    var onCaptureWindow: (() -> Void)?
    var onCaptureScrolling: (() -> Void)?
    var onRecordScreen: (() -> Void)?
    var onRecordArea: (() -> Void)?
    var onOCR: (() -> Void)?
    var onColorPicker: (() -> Void)?
    var onDismiss: (() -> Void)?

    var isVisible: Bool { overlayWindow != nil }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard !isVisible, let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }

        // Semi-transparent backdrop that dims the screen and catches clicks
        let backdrop = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        backdrop.level = .floating
        backdrop.backgroundColor = NSColor.black.withAlphaComponent(0.15)
        backdrop.isOpaque = false
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = false

        let backdropView = BackdropView()
        backdropView.frame = backdrop.contentView!.bounds
        backdropView.autoresizingMask = [.width, .height]
        backdropView.onClicked = { [weak self] in self?.dismiss() }
        backdropView.onEscape = { [weak self] in self?.dismiss() }
        backdrop.contentView?.addSubview(backdropView)
        backdrop.makeFirstResponder(backdropView)

        backdrop.orderFront(nil)
        self.backdropWindow = backdrop
        NSApp.activate(ignoringOtherApps: true)

        // Main toolbar panel — width computed from content
        let itemWidth: CGFloat = 52
        let itemCount: CGFloat = 8
        let dividerGap: CGFloat = 12 // gap around each divider
        let panelWidth = itemCount * itemWidth + 2 * dividerGap + 40 // 40 = side margins
        let panelHeight: CGFloat = 148

        let panelX = screen.frame.midX - panelWidth / 2
        let panelY = screen.frame.midY - panelHeight / 2 + 60

        let window = NSWindow(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        let toolbarView = CaptureToolbarView(
            frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))
        )
        toolbarView.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        toolbarView.onEscape = { [weak self] in
            self?.dismiss()
        }

        window.contentView = toolbarView

        // Fade in
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(toolbarView)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        self.overlayWindow = window

        // Local event monitor for ESC — borderless windows can't become key
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil // consume the event
            }
            return event
        }
    }

    func dismiss() {
        guard let window = overlayWindow else { return }

        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            backdropWindow?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.overlayWindow?.orderOut(nil)
            self?.overlayWindow = nil
            self?.backdropWindow?.orderOut(nil)
            self?.backdropWindow = nil
        })
    }

    private func handleAction(_ action: CaptureAction) {
        dismiss()

        // Small delay so the overlay fully disappears before capture starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            switch action {
            case .fullscreen: self?.onCaptureFullscreen?()
            case .area: self?.onCaptureArea?()
            case .window: self?.onCaptureWindow?()
            case .scrolling: self?.onCaptureScrolling?()
            case .recordScreen: self?.onRecordScreen?()
            case .recordArea: self?.onRecordArea?()
            case .ocr: self?.onOCR?()
            case .colorPicker: self?.onColorPicker?()
            }
        }
    }
}

// MARK: - Capture Actions

enum CaptureAction {
    case fullscreen, area, window, scrolling
    case recordScreen, recordArea
    case ocr, colorPicker
}

// MARK: - Backdrop (click-to-dismiss, escape-to-dismiss)

private class BackdropView: NSView {
    var onClicked: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
        }
    }
}

// MARK: - Toolbar View

private class CaptureToolbarView: NSView {
    var onAction: ((CaptureAction) -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }
    }

    private var hoverButton: NSView?

    struct ToolbarItem {
        let icon: String
        let label: String
        let shortcut: String
        let action: CaptureAction
    }

    private let captureItems: [ToolbarItem] = [
        ToolbarItem(icon: "rectangle.dashed", label: "Fullscreen", shortcut: "⌘⇧3", action: .fullscreen),
        ToolbarItem(icon: "rectangle.dashed.badge.record", label: "Area", shortcut: "⌘⇧4", action: .area),
        ToolbarItem(icon: "macwindow", label: "Window", shortcut: "⌘⇧5", action: .window),
        ToolbarItem(icon: "arrow.up.and.down.text.horizontal", label: "Scrolling", shortcut: "⌘⇧6", action: .scrolling),
    ]

    private let recordItems: [ToolbarItem] = [
        ToolbarItem(icon: "record.circle", label: "Record", shortcut: "⌘⇧7", action: .recordScreen),
        ToolbarItem(icon: "rectangle.inset.filled.and.person.filled", label: "Record Area", shortcut: "⌘⇧8", action: .recordArea),
    ]

    private let toolItems: [ToolbarItem] = [
        ToolbarItem(icon: "text.viewfinder", label: "OCR", shortcut: "⌘⇧9", action: .ocr),
        ToolbarItem(icon: "eyedropper", label: "Color", shortcut: "⌘⇧0", action: .colorPicker),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupUI() {
        // Vibrancy background with pill shape
        let effectView = NSVisualEffectView(frame: bounds)
        effectView.blendingMode = .behindWindow
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        // Layout constants
        let itemWidth: CGFloat = 52
        let divGap: CGFloat = 6 // space on each side of divider
        let itemCount = captureItems.count + recordItems.count + toolItems.count
        let contentWidth = CGFloat(itemCount) * itemWidth + 2 * (divGap * 2 + 1)
        let startX = (bounds.width - contentWidth) / 2

        // Vertical layout
        let itemBaseY: CGFloat = 24   // bottom of item containers
        let itemHeight: CGFloat = 90  // icon + label + shortcut
        let sectionLabelY = itemBaseY + itemHeight + 4
        let hintY: CGFloat = 6

        var x = startX
        let sections: [([ToolbarItem], String)] = [
            (captureItems, "CAPTURE"),
            (recordItems, "RECORD"),
            (toolItems, "TOOLS"),
        ]

        for (sectionIndex, (items, label)) in sections.enumerated() {
            // Section label above items
            let sectionLabel = makeSectionLabel(label)
            sectionLabel.frame.origin = NSPoint(x: x + 2, y: sectionLabelY)
            addSubview(sectionLabel)

            for item in items {
                let btn = makeItemButton(item: item, at: NSPoint(x: x, y: itemBaseY))
                addSubview(btn)
                x += itemWidth
            }

            // Divider between sections (not after last)
            if sectionIndex < sections.count - 1 {
                x += divGap
                let div = makeDivider(at: NSPoint(x: x, y: itemBaseY + 8), height: 72)
                addSubview(div)
                x += 1 + divGap
            }
        }

        // ESC hint at bottom
        let hint = NSTextField(labelWithString: "ESC to dismiss")
        hint.font = .systemFont(ofSize: 9, weight: .medium)
        hint.textColor = .white.withAlphaComponent(0.25)
        hint.frame = NSRect(x: 0, y: hintY, width: bounds.width, height: 12)
        hint.alignment = .center
        addSubview(hint)
    }

    private func makeItemButton(item: ToolbarItem, at origin: NSPoint) -> NSView {
        let width: CGFloat = 48
        let height: CGFloat = 90

        let container = NSView(frame: NSRect(x: origin.x, y: origin.y, width: width, height: height))

        // Real NSButton for accessibility and keyboard navigation
        let button = CaptureToolbarButton(frame: NSRect(x: 0, y: 24, width: width, height: 48))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .light)
        button.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.label)?.withSymbolConfiguration(iconConfig)
        button.contentTintColor = .white.withAlphaComponent(0.8)
        button.focusRingType = .exterior
        button.toolTip = "\(item.label) (\(item.shortcut))"
        button.setAccessibilityLabel(item.label)
        button.setAccessibilityRole(.button)
        button.captureAction = item.action
        button.onAction = { [weak self] action in
            self?.onAction?(action)
        }
        button.target = button
        button.action = #selector(CaptureToolbarButton.clicked)
        container.addSubview(button)

        // Label
        let label = NSTextField(labelWithString: item.label)
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.7)
        label.alignment = .center
        label.frame = NSRect(x: -4, y: 12, width: width + 8, height: 12)
        container.addSubview(label)

        // Shortcut hint
        let shortcut = NSTextField(labelWithString: item.shortcut)
        shortcut.font = .systemFont(ofSize: 8, weight: .regular)
        shortcut.textColor = .white.withAlphaComponent(0.3)
        shortcut.alignment = .center
        shortcut.frame = NSRect(x: -4, y: 0, width: width + 8, height: 10)
        container.addSubview(shortcut)

        return container
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 8, weight: .bold)
        label.textColor = .white.withAlphaComponent(0.3)
        label.sizeToFit()
        return label
    }

    private func makeDivider(at origin: NSPoint, height: CGFloat) -> NSView {
        let view = NSView(frame: NSRect(x: origin.x, y: origin.y, width: 1, height: height))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        return view
    }
}

// MARK: - Accessible Toolbar Button

private class CaptureToolbarButton: NSButton {
    var captureAction: CaptureAction?
    var onAction: ((CaptureAction) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    @objc func clicked() {
        guard let action = captureAction else { return }
        // Brief highlight
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.layer?.backgroundColor = nil
            self?.onAction?(action)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        contentTintColor = .white
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        contentTintColor = .white.withAlphaComponent(0.8)
    }
}
