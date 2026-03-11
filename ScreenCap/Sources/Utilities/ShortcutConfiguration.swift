import Cocoa
import HotKey

enum ShortcutModifierProfile: String, CaseIterable, Identifiable {
    case controlShift
    case commandShift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlShift:
            return "Ctrl+Shift"
        case .commandShift:
            return "Cmd+Shift"
        }
    }

    var summary: String {
        switch self {
        case .controlShift:
            return "Recommended. Avoids duplicate captures from Apple's built-in screenshot shortcuts."
        case .commandShift:
            return "Matches macOS screenshot keys. Disable Apple's screenshot shortcuts first to avoid conflicts."
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .controlShift:
            return [.control, .shift]
        case .commandShift:
            return [.command, .shift]
        }
    }

    var symbolPrefix: String {
        switch self {
        case .controlShift:
            return "⌃⇧"
        case .commandShift:
            return "⌘⇧"
        }
    }

    var textPrefix: String {
        switch self {
        case .controlShift:
            return "Ctrl+Shift+"
        case .commandShift:
            return "Cmd+Shift+"
        }
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case allInOne
    case captureFullscreen
    case captureArea
    case captureWindow
    case captureScrolling
    case recordScreen
    case recordArea
    case ocr
    case colorPicker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allInOne:
            return "All-in-One Toolbar"
        case .captureFullscreen:
            return "Capture Fullscreen"
        case .captureArea:
            return "Capture Area"
        case .captureWindow:
            return "Capture Window"
        case .captureScrolling:
            return "Scrolling Capture"
        case .recordScreen:
            return "Record Screen"
        case .recordArea:
            return "Record Area"
        case .ocr:
            return "OCR Text Recognition"
        case .colorPicker:
            return "Color Picker"
        }
    }

    var icon: String {
        switch self {
        case .allInOne:
            return "square.grid.2x2"
        case .captureFullscreen:
            return "rectangle.dashed"
        case .captureArea:
            return "rectangle.dashed.badge.record"
        case .captureWindow:
            return "macwindow"
        case .captureScrolling:
            return "arrow.up.and.down.text.horizontal"
        case .recordScreen:
            return "record.circle"
        case .recordArea:
            return "rectangle.inset.filled.and.person.filled"
        case .ocr:
            return "text.viewfinder"
        case .colorPicker:
            return "eyedropper"
        }
    }

    var key: Key {
        switch self {
        case .allInOne:
            return .one
        case .captureFullscreen:
            return .three
        case .captureArea:
            return .four
        case .captureWindow:
            return .five
        case .captureScrolling:
            return .six
        case .recordScreen:
            return .seven
        case .recordArea:
            return .eight
        case .ocr:
            return .nine
        case .colorPicker:
            return .zero
        }
    }

    var keyEquivalent: String {
        switch self {
        case .allInOne:
            return "1"
        case .captureFullscreen:
            return "3"
        case .captureArea:
            return "4"
        case .captureWindow:
            return "5"
        case .captureScrolling:
            return "6"
        case .recordScreen:
            return "7"
        case .recordArea:
            return "8"
        case .ocr:
            return "9"
        case .colorPicker:
            return "0"
        }
    }

    static let quickAccess: [ShortcutAction] = [.allInOne]
    static let capture: [ShortcutAction] = [.captureFullscreen, .captureArea, .captureWindow, .captureScrolling]
    static let recording: [ShortcutAction] = [.recordScreen, .recordArea]
    static let tools: [ShortcutAction] = [.ocr, .colorPicker]
}

struct ShortcutDefinition {
    let action: ShortcutAction
    let profile: ShortcutModifierProfile

    var key: Key { action.key }
    var keyEquivalent: String { action.keyEquivalent }
    var modifiers: NSEvent.ModifierFlags { profile.modifiers }
    var symbol: String { "\(profile.symbolPrefix)\(action.keyEquivalent)" }
    var text: String { "\(profile.textPrefix)\(action.keyEquivalent)" }
}

enum ShortcutCatalog {
    static func currentProfile() -> ShortcutModifierProfile {
        Defaults.shared.shortcutProfile
    }

    static func definition(for action: ShortcutAction, profile: ShortcutModifierProfile = ShortcutCatalog.currentProfile()) -> ShortcutDefinition {
        ShortcutDefinition(action: action, profile: profile)
    }

    static func allDefinitions(profile: ShortcutModifierProfile = ShortcutCatalog.currentProfile()) -> [ShortcutDefinition] {
        ShortcutAction.allCases.map { definition(for: $0, profile: profile) }
    }
}

extension Notification.Name {
    static let shortcutConfigurationDidChange = Notification.Name("shortcutConfigurationDidChange")
}

func postShortcutConfigurationDidChange() {
    NotificationCenter.default.post(name: .shortcutConfigurationDidChange, object: nil)
}
