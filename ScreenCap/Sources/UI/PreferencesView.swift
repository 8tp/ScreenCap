import SwiftUI
import Cocoa

class PreferencesWindowController {
    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let prefsView = PreferencesView()
        let hostingView = NSHostingView(rootView: prefsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenCap Preferences"
        window.toolbarStyle = .preference
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

struct PreferencesView: View {
    @AppStorage("saveLocation") private var saveLocationPath: String = NSHomeDirectory() + "/Desktop"
    @AppStorage("imageFormat") private var imageFormat: String = "png"
    @AppStorage("jpegQuality") private var jpegQuality: Double = 0.85
    @AppStorage("copyToClipboard") private var copyToClipboard: Bool = true
    @AppStorage("showThumbnail") private var showThumbnail: Bool = true
    @AppStorage("playSound") private var playSound: Bool = true
    @AppStorage("includeWindowShadow") private var includeWindowShadow: Bool = true
    @AppStorage("thumbnailDuration") private var thumbnailDuration: Double = 5.0
    @AppStorage("captureDelay") private var captureDelay: Int = 0
    @AppStorage("hideDesktopIcons") private var hideDesktopIcons: Bool = false
    @AppStorage("thumbnailPosition") private var thumbnailPosition: String = "bottomRight"
    @AppStorage("freezeScreen") private var freezeScreen: Bool = true
    @AppStorage("gifMaxWidth") private var gifMaxWidth: Int = 640
    @AppStorage("gifFrameRate") private var gifFrameRate: Int = 15

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            captureTab
                .tabItem { Label("Capture", systemImage: "camera") }
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 420)
    }

    private var generalTab: some View {
        Form {
            Section {
                HStack {
                    Label {
                        Text(saveLocationPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose...") { chooseSaveLocation() }
                }
            } header: {
                Text("Save Location")
            }

            Section {
                Picker("Default format:", selection: $imageFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpeg")
                    Text("TIFF").tag("tiff")
                }
                .pickerStyle(.segmented)

                if imageFormat == "jpeg" {
                    HStack {
                        Text("Quality")
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(jpegQuality * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Image Format")
            }

            Section {
                Toggle("Copy to clipboard automatically", isOn: $copyToClipboard)
                Toggle("Show floating thumbnail preview", isOn: $showThumbnail)
                Toggle("Play capture sound", isOn: $playSound)

                if showThumbnail {
                    Picker("Thumbnail position:", selection: $thumbnailPosition) {
                        Text("Bottom Right").tag("bottomRight")
                        Text("Bottom Left").tag("bottomLeft")
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("After Capture")
            }
        }
        .formStyle(.grouped)
    }

    private var captureTab: some View {
        Form {
            Section {
                Picker("Delay before capture:", selection: $captureDelay) {
                    Text("No delay").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
                Text("A countdown overlay will appear before the screenshot is taken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Timed Capture")
            }

            Section {
                Toggle("Hide desktop icons before capture", isOn: $hideDesktopIcons)
                Text("Temporarily hides Finder desktop icons for a clean capture, then restores them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Desktop")
            }

            Section {
                Toggle("Include window shadow in window captures", isOn: $includeWindowShadow)
            } header: {
                Text("Window Capture")
            }

            Section {
                Toggle("Freeze screen during area selection", isOn: $freezeScreen)
                Text("Captures and overlays the current screen content so nothing changes while you select an area.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Area Capture")
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section {
                ShortcutRow(icon: "square.grid.2x2", label: "All-in-One Toolbar", shortcut: "Cmd+Shift+1")
            } header: {
                Text("Quick Access")
            }

            Section {
                ShortcutRow(icon: "rectangle.dashed", label: "Capture Fullscreen", shortcut: "Cmd+Shift+3")
                ShortcutRow(icon: "rectangle.dashed.badge.record", label: "Capture Area", shortcut: "Cmd+Shift+4")
                ShortcutRow(icon: "macwindow", label: "Capture Window", shortcut: "Cmd+Shift+5")
                ShortcutRow(icon: "arrow.up.and.down.text.horizontal", label: "Scrolling Capture", shortcut: "Cmd+Shift+6")
            } header: {
                Text("Capture")
            }

            Section {
                ShortcutRow(icon: "record.circle", label: "Record Screen", shortcut: "Cmd+Shift+7")
                ShortcutRow(icon: "rectangle.inset.filled.and.person.filled", label: "Record Area", shortcut: "Cmd+Shift+8")
            } header: {
                Text("Recording")
            }

            Section {
                ShortcutRow(icon: "text.viewfinder", label: "OCR Text Recognition", shortcut: "Cmd+Shift+9")
                ShortcutRow(icon: "eyedropper", label: "Color Picker", shortcut: "Cmd+Shift+0")
            } header: {
                Text("Tools")
            }

            Section {
                Text("Shortcuts are system-wide and not currently customizable. Cmd+Shift is the primary modifier. Ctrl+Shift also works as an alternative if macOS built-in screenshots conflict.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section {
                HStack {
                    Text("Auto-dismiss after")
                    Slider(value: $thumbnailDuration, in: 1...15, step: 0.5)
                    Text("\(String(format: "%.1f", thumbnailDuration))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            } header: {
                Text("Floating Thumbnail")
            }

            Section {
                Picker("Max width:", selection: $gifMaxWidth) {
                    Text("320px").tag(320)
                    Text("480px").tag(480)
                    Text("640px").tag(640)
                    Text("800px").tag(800)
                    Text("1024px").tag(1024)
                }
                Picker("Frame rate:", selection: $gifFrameRate) {
                    Text("10 fps").tag(10)
                    Text("15 fps").tag(15)
                    Text("20 fps").tag(20)
                    Text("25 fps").tag(25)
                }
            } header: {
                Text("GIF Export")
            }

            Section {
                Button(role: .destructive) {
                    resetAll()
                } label: {
                    Label("Reset All Settings to Defaults", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Reset")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            saveLocationPath = url.path
        }
    }

    private func resetAll() {
        let defaults = UserDefaults.standard
        for key in ["saveLocation", "imageFormat", "jpegQuality", "copyToClipboard", "showThumbnail", "playSound", "includeWindowShadow", "thumbnailDuration", "captureDelay", "hideDesktopIcons", "thumbnailPosition", "freezeScreen", "gifMaxWidth", "gifFrameRate", "recentCaptures"] {
            defaults.removeObject(forKey: key)
        }
    }
}

struct ShortcutRow: View {
    var icon: String = ""
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 10) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
