import Cocoa

class MenuBarController {
    private var statusItem: NSStatusItem!
    private weak var statusButton: NSStatusBarButton?
    private let captureEngine: ScreenCaptureEngine
    private let thumbnailController: FloatingThumbnailController
    private let screenRecorder: ScreenRecorder
    private let ocrTool: OCRTool
    private let colorPicker: ColorPickerTool
    private let scrollCapture: ScrollCapture
    private let preferencesController: PreferencesWindowController
    private var appBeforeMenuInteraction: NSRunningApplication?
    var prepareForCapture: (_ preferredApp: NSRunningApplication?, _ action: @escaping () -> Void) -> Void = { _, action in action() }
    var onShowAllInOne: (() -> Void)?

    init(captureEngine: ScreenCaptureEngine,
         thumbnailController: FloatingThumbnailController,
         screenRecorder: ScreenRecorder,
         ocrTool: OCRTool,
         colorPicker: ColorPickerTool,
         scrollCapture: ScrollCapture,
         preferencesController: PreferencesWindowController) {
        self.captureEngine = captureEngine
        self.thumbnailController = thumbnailController
        self.screenRecorder = screenRecorder
        self.ocrTool = ocrTool
        self.colorPicker = colorPicker
        self.scrollCapture = scrollCapture
        self.preferencesController = preferencesController
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCap")
            button.target = self
            button.action = #selector(toggleStatusMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusButton = button
        }
    }

    func rebuildMenu() {
        // Menu is built on demand when the status item is clicked.
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // All-in-One shortcut at top
        menu.addItem(makeItem("All-in-One", icon: "square.grid.2x2", action: #selector(showAllInOne), shortcutAction: .allInOne))
        menu.addItem(NSMenuItem.separator())

        // Capture section header
        let captureHeader = NSMenuItem(title: "CAPTURE", action: nil, keyEquivalent: "")
        captureHeader.isEnabled = false
        captureHeader.attributedTitle = NSAttributedString(
            string: "CAPTURE",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        menu.addItem(captureHeader)

        menu.addItem(makeItem("Capture Fullscreen", icon: "rectangle.dashed", action: #selector(captureFullscreen), shortcutAction: .captureFullscreen))
        menu.addItem(makeItem("Capture Area", icon: "rectangle.dashed.badge.record", action: #selector(captureArea), shortcutAction: .captureArea))
        menu.addItem(makeItem("Capture Window", icon: "macwindow", action: #selector(captureWindow), shortcutAction: .captureWindow))
        menu.addItem(makeItem("Capture Scrolling", icon: "arrow.up.and.down.text.horizontal", action: #selector(captureScrolling), shortcutAction: .captureScrolling))

        // Timed capture submenu
        let timedItem = NSMenuItem(title: "Timed Capture", action: nil, keyEquivalent: "")
        timedItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let timedMenu = NSMenu(title: "Timed Capture")
        for delay in [3, 5, 10] {
            let delayItem = NSMenuItem(title: "\(delay) Second Delay", action: #selector(timedCaptureSelected(_:)), keyEquivalent: "")
            delayItem.tag = delay
            delayItem.target = self
            timedMenu.addItem(delayItem)
        }
        timedMenu.addItem(NSMenuItem.separator())
        let noDelay = NSMenuItem(title: "No Delay (Instant)", action: #selector(timedCaptureSelected(_:)), keyEquivalent: "")
        noDelay.tag = 0
        noDelay.target = self
        timedMenu.addItem(noDelay)
        let currentDelay = Defaults.shared.captureDelay
        for item in timedMenu.items {
            if item.tag == currentDelay { item.state = .on }
        }
        timedItem.submenu = timedMenu
        menu.addItem(timedItem)

        menu.addItem(NSMenuItem.separator())

        // Record section
        let recordHeader = NSMenuItem(title: "RECORD", action: nil, keyEquivalent: "")
        recordHeader.isEnabled = false
        recordHeader.attributedTitle = NSAttributedString(
            string: "RECORD",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        menu.addItem(recordHeader)

        menu.addItem(makeItem("Record Screen", icon: "record.circle", action: #selector(recordScreen), shortcutAction: .recordScreen))
        menu.addItem(makeItem("Record Area", icon: "rectangle.inset.filled.and.person.filled", action: #selector(recordArea), shortcutAction: .recordArea))

        menu.addItem(NSMenuItem.separator())

        // Tools section
        let toolsHeader = NSMenuItem(title: "TOOLS", action: nil, keyEquivalent: "")
        toolsHeader.isEnabled = false
        toolsHeader.attributedTitle = NSAttributedString(
            string: "TOOLS",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        menu.addItem(toolsHeader)

        menu.addItem(makeItem("OCR Screen Region", icon: "text.viewfinder", action: #selector(ocrRegion), shortcutAction: .ocr))
        menu.addItem(makeItem("Color Picker", icon: "eyedropper", action: #selector(pickColor), shortcutAction: .colorPicker))
        menu.addItem(makeItem("Pin Last Capture", icon: "pin", action: #selector(pinLastCapture)))

        menu.addItem(NSMenuItem.separator())

        // Desktop section
        let desktopHeader = NSMenuItem(title: "DESKTOP", action: nil, keyEquivalent: "")
        desktopHeader.isEnabled = false
        desktopHeader.attributedTitle = NSAttributedString(
            string: "DESKTOP",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        menu.addItem(desktopHeader)

        let desktopIconsHidden = Defaults.shared.desktopIconsHidden
        let toggleIcons = makeItem(
            desktopIconsHidden ? "Show Desktop Icons" : "Hide Desktop Icons",
            icon: desktopIconsHidden ? "eye" : "eye.slash",
            action: #selector(toggleDesktopIcons)
        )
        menu.addItem(toggleIcons)

        menu.addItem(NSMenuItem.separator())

        // Recent Captures
        let recent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        recent.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        recent.submenu = buildRecentCapturesMenu()
        menu.addItem(recent)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeItem("About ScreenCap", icon: "info.circle", action: #selector(showAbout)))
        menu.addItem(makeItem("Preferences...", icon: "gear", action: #selector(openPreferences), key: ",", modifiers: [.command]))

        menu.addItem(NSMenuItem.separator())

        let quit = makeItem("Quit ScreenCap", icon: "power", action: #selector(quitApp), key: "q", modifiers: [.command])
        menu.addItem(quit)

        return menu
    }

    private func makeItem(_ title: String, icon: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [], shortcutAction: ShortcutAction? = nil) -> NSMenuItem {
        let item: NSMenuItem
        if let shortcutAction {
            let shortcut = ShortcutCatalog.definition(for: shortcutAction)
            item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut.keyEquivalent)
            item.keyEquivalentModifierMask = shortcut.modifiers
        } else {
            item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
        }
        item.target = self
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        return item
    }

    private func buildRecentCapturesMenu() -> NSMenu {
        let menu = NSMenu(title: "Recent Captures")
        let captures = Defaults.shared.recentCaptures

        if captures.isEmpty {
            let noRecent = NSMenuItem(title: "No Recent Captures", action: nil, keyEquivalent: "")
            noRecent.isEnabled = false
            menu.addItem(noRecent)
        } else {
            for (i, url) in captures.prefix(10).enumerated() {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentCapture(_:)), keyEquivalent: "")
                item.tag = i
                item.target = self
                item.representedObject = url

                // Icon based on file type
                let ext = url.pathExtension.lowercased()
                if ext == "mp4" || ext == "gif" {
                    item.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
                } else {
                    item.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
                }
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())

            let showInFinder = NSMenuItem(title: "Show in Finder", action: #selector(showRecentInFinder), keyEquivalent: "")
            showInFinder.target = self
            showInFinder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(showInFinder)

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearRecentCaptures), keyEquivalent: "")
            clearItem.target = self
            clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            menu.addItem(clearItem)
        }

        return menu
    }

    // MARK: - Public Triggers (for hotkey manager)

    func triggerCaptureFullscreen() { captureFullscreen() }
    func triggerCaptureArea() { captureArea() }
    func triggerCaptureWindow() { captureWindow() }
    func triggerCaptureScrolling() { captureScrolling() }
    func triggerRecordScreen() { recordScreen() }
    func triggerRecordArea() { recordArea() }
    func triggerOCR() { ocrRegion() }
    func triggerColorPicker() { pickColor() }

    // MARK: - Actions

    @objc private func captureFullscreen() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.runCaptureFullscreen()
        }
    }

    private func runCaptureFullscreen() {
        captureEngine.captureFullscreen { [weak self] result in
            if case .success(let url) = result {
                self?.thumbnailController.show(for: url)
                self?.rebuildMenu()
            }
        }
    }

    @objc private func captureArea() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.runCaptureArea()
        }
    }

    private func runCaptureArea() {
        captureEngine.captureArea { [weak self] result in
            if case .success(let url) = result {
                self?.thumbnailController.show(for: url)
                self?.rebuildMenu()
            }
        }
    }

    @objc private func captureWindow() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.runCaptureWindow()
        }
    }

    private func runCaptureWindow() {
        captureEngine.captureWindow { [weak self] result in
            if case .success(let url) = result {
                self?.thumbnailController.show(for: url)
                self?.rebuildMenu()
            }
        }
    }

    @objc private func captureScrolling() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.runCaptureScrolling()
        }
    }

    private func runCaptureScrolling() {
        scrollCapture.start { [weak self] result in
            if case .success(let url) = result {
                Defaults.shared.addRecentCapture(url)
                self?.thumbnailController.show(for: url)
                self?.rebuildMenu()
            }
        }
    }

    @objc private func recordScreen() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.screenRecorder.startFullscreen()
        }
    }

    @objc private func recordArea() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.screenRecorder.startArea()
        }
    }

    @objc private func ocrRegion() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.runOCRRegion()
        }
    }

    private func runOCRRegion() {
        ocrTool.captureAndRecognize { result in
            switch result {
            case .success(let text):
                Toast.show(message: "Text copied to clipboard (\(text.prefix(30))...)")
            case .failure:
                Toast.show(message: "No text recognized", style: .error)
            }
        }
    }

    @objc private func pickColor() {
        prepareForCapture(appBeforeMenuInteraction) { [weak self] in
            self?.colorPicker.show { _ in
                // Color is already copied to clipboard by ColorPickerTool
            }
        }
    }

    @objc private func toggleStatusMenu(_ sender: Any?) {
        captureMenuContext()
        statusItem.popUpMenu(buildMenu())
    }

    private func captureMenuContext() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        appBeforeMenuInteraction = frontmost
    }

    @objc private func pinLastCapture() {
        if let url = thumbnailController.currentURL {
            thumbnailController.onPin?(url)
        }
    }

    @objc private func timedCaptureSelected(_ sender: NSMenuItem) {
        Defaults.shared.captureDelay = sender.tag
        rebuildMenu()
        if sender.tag > 0 {
            Toast.show(message: "Capture delay set to \(sender.tag)s")
        } else {
            Toast.show(message: "Capture delay disabled")
        }
    }

    @objc private func openRecentCapture(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showRecentInFinder() {
        NSWorkspace.shared.open(Defaults.shared.saveLocation)
    }

    @objc private func clearRecentCaptures() {
        Defaults.shared.clearRecentCaptures()
        rebuildMenu()
    }

    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }

    @objc private func toggleDesktopIcons() {
        let isCurrentlyHidden = Defaults.shared.desktopIconsHidden
        let newState = !isCurrentlyHidden
        Defaults.shared.desktopIconsHidden = newState

        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", newState ? "false" : "true"]
        task.launch()
        task.waitUntilExit()

        let killTask = Process()
        killTask.launchPath = "/usr/bin/killall"
        killTask.arguments = ["Finder"]
        killTask.launch()

        rebuildMenu()
        Toast.show(message: newState ? "Desktop icons hidden" : "Desktop icons restored")
    }

    @objc private func showAllInOne() {
        onShowAllInOne?()
    }

    @objc private func openPreferences() {
        preferencesController.show()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
