import AppKit
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status?
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    var canManage: Bool {
        isRunningFromAppBundle
    }

    var statusMessage: String {
        guard #available(macOS 13.0, *) else {
            return "Launch at login requires macOS 13 or newer."
        }

        guard isRunningFromAppBundle else {
            return "Launch at login is available when ScreenCap is running as an app bundle."
        }

        switch status {
        case .enabled:
            return "ScreenCap is set to launch automatically when you log in."
        case .requiresApproval:
            return "macOS needs approval in Login Items before ScreenCap can launch automatically."
        case .notRegistered:
            return "ScreenCap will stay off until you enable it here."
        case .notFound:
            return "macOS could not find the app bundle for launch-at-login registration."
        case nil:
            return "Launch-at-login status is unavailable right now."
        @unknown default:
            return "Launch-at-login status is unavailable right now."
        }
    }

    var showsApprovalButton: Bool {
        status == .requiresApproval
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    init() {
        refresh()
    }

    func refresh() {
        errorMessage = nil

        guard #available(macOS 13.0, *) else {
            status = nil
            return
        }

        guard isRunningFromAppBundle else {
            status = nil
            return
        }

        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            errorMessage = "Launch at login requires macOS 13 or newer."
            return
        }

        guard isRunningFromAppBundle else {
            errorMessage = "Run ScreenCap as an app bundle to enable launch at login."
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = explain(error: error, enabling: enabled)
        }

        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        guard #available(macOS 13.0, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    private func explain(error: Error, enabling: Bool) -> String {
        let nsError = error as NSError

        switch nsError.code {
        case kSMErrorInvalidSignature:
            return "ScreenCap must be code signed as an app bundle before macOS will register it for launch at login."
        case kSMErrorLaunchDeniedByUser:
            return "macOS blocked launch at login. Approve ScreenCap in System Settings > General > Login Items."
        case kSMErrorAlreadyRegistered:
            return "ScreenCap is already registered to launch at login."
        case kSMErrorJobNotFound:
            return enabling
                ? "macOS could not find the launch-at-login service for ScreenCap."
                : "ScreenCap is already removed from launch at login."
        default:
            break
        }

        return nsError.localizedDescription
    }
}
