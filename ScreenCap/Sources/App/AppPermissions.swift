import Cocoa
import ScreenCaptureKit

enum AppPermissions {

    // MARK: - Screen Recording

    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the native macOS "allow screen recording" dialog
    static func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Accessibility

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the native macOS "allow accessibility" dialog with prompt
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - System Settings

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
