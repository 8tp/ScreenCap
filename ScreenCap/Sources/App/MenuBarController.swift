import Cocoa

class MenuBarController {
    private var statusItem: NSStatusItem!
    private let captureEngine: ScreenCaptureEngine
    private let thumbnailController: FloatingThumbnailController
    private let screenRecorder: ScreenRecorder
    private let ocrTool: OCRTool
    private let colorPicker: ColorPickerTool
    private let scrollCapture: ScrollCapture
    private let preferencesController: PreferencesWindowController

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
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let fullscreen = NSMenuItem(title: "Capture Fullscreen", action: #selector(captureFullscreen), keyEquivalent: "")
        fullscreen.keyEquivalentModifierMask = [.command, .shift]
        fullscreen.keyEquivalent = "3"
        fullscreen.target = self
        menu.addItem(fullscreen)

        let area = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "")
        area.keyEquivalentModifierMask = [.command, .shift]
        area.keyEquivalent = "4"
        area.target = self
        menu.addItem(area)

        let window = NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: "")
        window.keyEquivalentModifierMask = [.command, .shift]
        window.keyEquivalent = "5"
        window.target = self
        menu.addItem(window)

        let scrolling = NSMenuItem(title: "Capture Scrolling", action: #selector(captureScrolling), keyEquivalent: "")
        scrolling.keyEquivalentModifierMask = [.command, .shift]
        scrolling.keyEquivalent = "6"
        scrolling.target = self
        menu.addItem(scrolling)

        menu.addItem(NSMenuItem.separator())

        let recordScreenItem = NSMenuItem(title: "Record Screen", action: #selector(recordScreen), keyEquivalent: "")
        recordScreenItem.keyEquivalentModifierMask = [.command, .shift]
        recordScreenItem.keyEquivalent = "7"
        recordScreenItem.target = self
        menu.addItem(recordScreenItem)

        let recordAreaItem = NSMenuItem(title: "Record Area", action: #selector(recordArea), keyEquivalent: "")
        recordAreaItem.keyEquivalentModifierMask = [.command, .shift]
        recordAreaItem.keyEquivalent = "8"
        recordAreaItem.target = self
        menu.addItem(recordAreaItem)

        menu.addItem(NSMenuItem.separator())

        let ocr = NSMenuItem(title: "OCR Screen Region", action: #selector(ocrRegion), keyEquivalent: "")
        ocr.keyEquivalentModifierMask = [.command, .shift]
        ocr.keyEquivalent = "9"
        ocr.target = self
        menu.addItem(ocr)

        let colorPickerItem = NSMenuItem(title: "Color Picker", action: #selector(pickColor), keyEquivalent: "")
        colorPickerItem.keyEquivalentModifierMask = [.command, .shift]
        colorPickerItem.keyEquivalent = "0"
        colorPickerItem.target = self
        menu.addItem(colorPickerItem)

        menu.addItem(NSMenuItem.separator())

        let pin = NSMenuItem(title: "Pin Last Capture", action: #selector(pinLastCapture), keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)

        let recent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        recent.submenu = NSMenu(title: "Recent Captures")
        let noRecent = NSMenuItem(title: "No Recent Captures", action: nil, keyEquivalent: "")
        noRecent.isEnabled = false
        recent.submenu?.addItem(noRecent)
        menu.addItem(recent)

        menu.addItem(NSMenuItem.separator())

        let prefs = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = [.command]
        prefs.target = self
        menu.addItem(prefs)

        let quit = NSMenuItem(title: "Quit ScreenCap", action: #selector(quitApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Public Triggers (for hotkey manager)

    func triggerCaptureFullscreen() { captureFullscreen() }
    func triggerCaptureArea() { captureArea() }
    func triggerCaptureWindow() { captureWindow() }
    func triggerOCR() { ocrRegion() }
    func triggerColorPicker() { pickColor() }
    func triggerRecordScreen() { recordScreen() }

    // MARK: - Actions

    @objc private func captureFullscreen() {
        captureEngine.captureFullscreen { [weak self] result in
            if case .success(let url) = result {
                self?.thumbnailController.show(for: url)
            }
        }
    }

    @objc private func captureArea() {
        captureEngine.captureArea { [weak self] result in
            if case .success(let url) = result {
                self?.thumbnailController.show(for: url)
            }
        }
    }

    @objc private func captureWindow() {
        captureEngine.captureWindow { [weak self] result in
            if case .success(let url) = result {
                self?.thumbnailController.show(for: url)
            }
        }
    }

    @objc private func captureScrolling() {
        scrollCapture.start { [weak self] result in
            if case .success(let url) = result {
                self?.thumbnailController.show(for: url)
            }
        }
    }

    @objc private func recordScreen() {
        screenRecorder.startFullscreen()
    }

    @objc private func recordArea() {
        screenRecorder.startArea()
    }

    @objc private func ocrRegion() {
        ocrTool.captureAndRecognize { result in
            switch result {
            case .success(let text):
                Toast.show(message: "Text copied to clipboard (\(text.prefix(30))...)")
            case .failure:
                Toast.show(message: "No text recognized")
            }
        }
    }

    @objc private func pickColor() {
        colorPicker.show { color in
            // Color is already copied to clipboard by ColorPickerTool
        }
    }

    @objc private func pinLastCapture() {
        if let url = thumbnailController.currentURL {
            thumbnailController.onPin?(url)
        }
    }

    @objc private func openPreferences() {
        preferencesController.show()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
