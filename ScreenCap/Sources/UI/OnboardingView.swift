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
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = hostingView
        window.center()
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

struct OnboardingView: View {
    let onDismiss: () -> Void

    @State private var screenRecordingGranted = AppPermissions.hasScreenRecordingPermission()
    @State private var accessibilityGranted = AppPermissions.hasAccessibilityPermission()

    var allGranted: Bool {
        screenRecordingGranted && accessibilityGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.primary)
                    .padding(.top, 28)

                Text("Welcome to ScreenCap")
                    .font(.system(size: 24, weight: .bold))

                Text("The free, open-source screenshot tool for macOS.\nGrant permissions below to get started.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.bottom, 28)

            // Permissions
            VStack(spacing: 0) {
                PermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    iconColor: .red,
                    title: "Screen Recording",
                    description: "Required for capturing screenshots and recordings",
                    isGranted: screenRecordingGranted,
                    action: {
                        AppPermissions.requestScreenRecordingPermission()
                        if !AppPermissions.hasScreenRecordingPermission() {
                            AppPermissions.openScreenRecordingSettings()
                        }
                        refreshStatus()
                    }
                )

                Divider().padding(.horizontal, 20)

                PermissionRow(
                    icon: "keyboard",
                    iconColor: .blue,
                    title: "Accessibility",
                    description: "Required for global keyboard shortcuts",
                    isGranted: accessibilityGranted,
                    action: {
                        AppPermissions.requestAccessibilityPermission()
                        refreshStatus()
                    }
                )
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 28)

            Spacer()

            // Shortcut hint
            if allGranted {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                    Text("Press ⌘⇧1 to open the capture toolbar")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 8)
            }

            // Bottom buttons
            HStack(spacing: 16) {
                Button(action: { refreshStatus() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.regular)

                Spacer()

                Button(action: { onDismiss() }) {
                    Text(allGranted ? "Get Started" : "Continue Anyway")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(width: 500, height: 520)
    }

    private func refreshStatus() {
        screenRecordingGranted = AppPermissions.hasScreenRecordingPermission()
        accessibilityGranted = AppPermissions.hasAccessibilityPermission()
    }
}

struct PermissionRow: View {
    let icon: String
    var iconColor: Color = .primary
    let title: String
    let description: String
    let isGranted: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 20))
            } else if let action = action {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
