import Cocoa
import HotKey

class HotkeyManager {
    private var hotkeys: [HotKey] = []

    var onCaptureFullscreen: (() -> Void)?
    var onCaptureArea: (() -> Void)?
    var onCaptureWindow: (() -> Void)?
    var onCaptureScrolling: (() -> Void)?
    var onRecordScreen: (() -> Void)?
    var onRecordArea: (() -> Void)?
    var onOCR: (() -> Void)?
    var onColorPicker: (() -> Void)?
    var onAllInOne: (() -> Void)?

    func registerAll() {
        unregisterAll()

        for shortcut in ShortcutCatalog.allDefinitions() {
            register(key: shortcut.key, modifiers: shortcut.modifiers) { [weak self] in
                self?.handler(for: shortcut.action)?()
            }
        }
    }

    func unregisterAll() {
        hotkeys.removeAll()
    }

    private func register(key: Key, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        let hotkey = HotKey(key: key, modifiers: modifiers)
        hotkey.keyDownHandler = handler
        hotkeys.append(hotkey)
    }

    private func handler(for action: ShortcutAction) -> (() -> Void)? {
        switch action {
        case .allInOne:
            return onAllInOne
        case .captureFullscreen:
            return onCaptureFullscreen
        case .captureArea:
            return onCaptureArea
        case .captureWindow:
            return onCaptureWindow
        case .captureScrolling:
            return onCaptureScrolling
        case .recordScreen:
            return onRecordScreen
        case .recordArea:
            return onRecordArea
        case .ocr:
            return onOCR
        case .colorPicker:
            return onColorPicker
        }
    }
}
