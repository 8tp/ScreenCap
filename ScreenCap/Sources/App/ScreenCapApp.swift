import Cocoa
import SwiftUI

@main
struct ScreenCapApp {
    static func main() {
        let app = NSApplication.shared
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
    private var pinnedWindows: [PinnedImageWindow] = []

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

        thumbnailController.onEdit = { [weak self] url in
            self?.editorController.open(imageURL: url)
        }
        thumbnailController.onPin = { [weak self] url in
            self?.pinImage(url: url)
        }

        screenRecorder.onRecordingFinished = { [weak self] url in
            self?.thumbnailController.show(for: url)
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

        setupHotkeys()

        // Show onboarding on first launch
        onboardingController.showIfNeeded()
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
        hotkeyManager.onOCR = { [weak self] in
            self?.menuBarController.triggerOCR()
        }
        hotkeyManager.onColorPicker = { [weak self] in
            self?.menuBarController.triggerColorPicker()
        }
        hotkeyManager.onRecordScreen = { [weak self] in
            self?.menuBarController.triggerRecordScreen()
        }
        hotkeyManager.registerAll()
    }

    private func pinImage(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let pinned = PinnedImageWindow(image: image, imageURL: url)
        pinned.show()
        pinnedWindows.append(pinned)
    }
}
