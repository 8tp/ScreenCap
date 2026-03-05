import Cocoa
import HotKey
import Carbon

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

    func registerAll() {
        unregisterAll()

        register(key: .three, modifiers: [.command, .shift]) { [weak self] in
            self?.onCaptureFullscreen?()
        }
        register(key: .four, modifiers: [.command, .shift]) { [weak self] in
            self?.onCaptureArea?()
        }
        register(key: .five, modifiers: [.command, .shift]) { [weak self] in
            self?.onCaptureWindow?()
        }
        register(key: .six, modifiers: [.command, .shift]) { [weak self] in
            self?.onCaptureScrolling?()
        }
        register(key: .seven, modifiers: [.command, .shift]) { [weak self] in
            self?.onRecordScreen?()
        }
        register(key: .eight, modifiers: [.command, .shift]) { [weak self] in
            self?.onRecordArea?()
        }
        register(key: .nine, modifiers: [.command, .shift]) { [weak self] in
            self?.onOCR?()
        }
        register(key: .zero, modifiers: [.command, .shift]) { [weak self] in
            self?.onColorPicker?()
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
}
