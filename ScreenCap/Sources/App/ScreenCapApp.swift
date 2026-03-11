import Cocoa
import SwiftUI

@main
struct ScreenCapApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var captureEngine: ScreenCaptureEngine!
    private var thumbnailController: FloatingThumbnailController!
    private var editorController: AnnotationEditorController!
    private var hotkeyManager: HotkeyManager!
    private var screenRecorder: ScreenRecorder!
    private var ocrTool: OCRTool!
    private var colorPicker: ColorPickerTool!
    private var preferencesController: PreferencesWindowController!
    private var scrollCapture: ScrollCapture!
    private var onboardingController: OnboardingWindowController!
    private var captureToolbar: CaptureToolbarController!
    private var pinnedWindows: [PinnedImageWindow] = []
    private var shortcutSettingsObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var lastActiveExternalApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureEngine = ScreenCaptureEngine()
        thumbnailController = FloatingThumbnailController()
        editorController = AnnotationEditorController()
        screenRecorder = ScreenRecorder()
        ocrTool = OCRTool()
        colorPicker = ColorPickerTool()
        preferencesController = PreferencesWindowController()
        scrollCapture = ScrollCapture()
        hotkeyManager = HotkeyManager()
        onboardingController = OnboardingWindowController()
        captureToolbar = CaptureToolbarController()

        thumbnailController.onEdit = { [weak self] url in
            self?.editorController.open(imageURL: url)
        }
        thumbnailController.onPin = { [weak self] url in
            self?.pinImage(url: url)
        }

        screenRecorder.onRecordingFinished = { [weak self] url in
            Defaults.shared.addRecentCapture(url)
            self?.thumbnailController.show(for: url)
            self?.menuBarController.rebuildMenu()
        }

        menuBarController = MenuBarController(
            captureEngine: captureEngine,
            thumbnailController: thumbnailController,
            screenRecorder: screenRecorder,
            ocrTool: ocrTool,
            colorPicker: colorPicker,
            scrollCapture: scrollCapture,
            preferencesController: preferencesController
        )
        menuBarController.prepareForCapture = { [weak self] preferredApp, action in
            self?.prepareForCapture(preferredApp: preferredApp, action: action) ?? action()
        }

        setupCaptureToolbar()
        setupHotkeys()
        observeShortcutSettings()
        observeWorkspaceActivation()

        menuBarController.onShowAllInOne = { [weak self] in
            self?.captureToolbar.toggle()
        }

        // Show onboarding on first launch
        onboardingController.showIfNeeded()
    }

    private func setupCaptureToolbar() {
        captureToolbar.onCaptureFullscreen = { [weak self] in
            self?.menuBarController.triggerCaptureFullscreen()
        }
        captureToolbar.onCaptureArea = { [weak self] in
            self?.menuBarController.triggerCaptureArea()
        }
        captureToolbar.onCaptureWindow = { [weak self] in
            self?.menuBarController.triggerCaptureWindow()
        }
        captureToolbar.onCaptureScrolling = { [weak self] in
            self?.menuBarController.triggerCaptureScrolling()
        }
        captureToolbar.onRecordScreen = { [weak self] in
            self?.menuBarController.triggerRecordScreen()
        }
        captureToolbar.onRecordArea = { [weak self] in
            self?.menuBarController.triggerRecordArea()
        }
        captureToolbar.onOCR = { [weak self] in
            self?.menuBarController.triggerOCR()
        }
        captureToolbar.onColorPicker = { [weak self] in
            self?.menuBarController.triggerColorPicker()
        }
    }

    private func setupHotkeys() {
        hotkeyManager.onCaptureFullscreen = { [weak self] in
            self?.menuBarController.triggerCaptureFullscreen()
        }
        hotkeyManager.onCaptureArea = { [weak self] in
            self?.menuBarController.triggerCaptureArea()
        }
        hotkeyManager.onCaptureWindow = { [weak self] in
            self?.menuBarController.triggerCaptureWindow()
        }
        hotkeyManager.onCaptureScrolling = { [weak self] in
            self?.menuBarController.triggerCaptureScrolling()
        }
        hotkeyManager.onOCR = { [weak self] in
            self?.menuBarController.triggerOCR()
        }
        hotkeyManager.onColorPicker = { [weak self] in
            self?.menuBarController.triggerColorPicker()
        }
        hotkeyManager.onRecordScreen = { [weak self] in
            self?.menuBarController.triggerRecordScreen()
        }
        hotkeyManager.onRecordArea = { [weak self] in
            self?.menuBarController.triggerRecordArea()
        }
        hotkeyManager.onAllInOne = { [weak self] in
            self?.captureToolbar.toggle()
        }
        hotkeyManager.registerAll()
    }

    private func observeShortcutSettings() {
        shortcutSettingsObserver = NotificationCenter.default.addObserver(
            forName: .shortcutConfigurationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager.registerAll()
            self?.menuBarController.rebuildMenu()
        }
    }

    private func observeWorkspaceActivation() {
        updateLastActiveExternalApp(NSWorkspace.shared.frontmostApplication)

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateLastActiveExternalApp(app)
        }
    }

    private func updateLastActiveExternalApp(_ app: NSRunningApplication?) {
        guard let app else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastActiveExternalApp = app
    }

    private func prepareForCapture(preferredApp: NSRunningApplication?, action: @escaping () -> Void) {
        let app = preferredApp?.isTerminated == false ? preferredApp : lastActiveExternalApp

        guard let app, !app.isTerminated else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: action)
            return
        }

        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: action)
    }

    private func pinImage(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let pinned = PinnedImageWindow(image: image, imageURL: url)
        pinned.show()
        pinnedWindows.append(pinned)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutSettingsObserver {
            NotificationCenter.default.removeObserver(shortcutSettingsObserver)
        }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
    }
}
