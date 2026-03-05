import SwiftUI
import Cocoa

class OnboardingWindowController {
    private var window: NSWindow?

    func showIfNeeded() {
        let hasShown = UserDefaults.standard.bool(forKey: "hasShownOnboarding")
        guard !hasShown else { return }

        show()
        UserDefaults.standard.set(true, forKey: "hasShownOnboarding")
    }

    func show() {
        let view = OnboardingView {
            self.window?.orderOut(nil)
            self.window = nil
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 320)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ScreenCap"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to ScreenCap!")
                .font(.title)
                .fontWeight(.bold)

            Text("To work properly, we need a few permissions:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "Required for capturing screenshots",
                    isGranted: AppPermissions.hasScreenRecordingPermission()
                )

                PermissionRow(
                    icon: "keyboard",
                    title: "Accessibility",
                    description: "Required for global keyboard shortcuts",
                    isGranted: false
                )

                PermissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "Optional - for recording with audio",
                    isGranted: false
                )
            }
            .padding()

            HStack(spacing: 16) {
                Button("Open System Settings") {
                    AppPermissions.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Skip") {
                    onDismiss()
                }
            }
        }
        .padding(30)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
