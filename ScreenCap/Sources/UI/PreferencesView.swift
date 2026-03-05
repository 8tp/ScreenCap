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
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 450)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenCap Preferences"
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

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("Save Location") {
                HStack {
                    Text(saveLocationPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") { chooseSaveLocation() }
                }
            }

            Section("Image Format") {
                Picker("Default format:", selection: $imageFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpeg")
                    Text("TIFF").tag("tiff")
                }
                if imageFormat == "jpeg" {
                    Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.05) {
                        Text("JPEG Quality: \(Int(jpegQuality * 100))%")
                    }
                }
            }

            Section("After Capture") {
                Toggle("Copy to clipboard", isOn: $copyToClipboard)
                Toggle("Show floating thumbnail", isOn: $showThumbnail)
                Toggle("Play sound", isOn: $playSound)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section("Keyboard Shortcuts") {
                ShortcutRow(label: "Capture Fullscreen", shortcut: "Cmd+Shift+3")
                ShortcutRow(label: "Capture Area", shortcut: "Cmd+Shift+4")
                ShortcutRow(label: "Capture Window", shortcut: "Cmd+Shift+5")
                ShortcutRow(label: "Capture Scrolling", shortcut: "Cmd+Shift+6")
                ShortcutRow(label: "Record Screen", shortcut: "Cmd+Shift+7")
                ShortcutRow(label: "Record Area", shortcut: "Cmd+Shift+8")
                ShortcutRow(label: "OCR Screen Region", shortcut: "Cmd+Shift+9")
                ShortcutRow(label: "Color Picker", shortcut: "Cmd+Shift+0")
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section("Capture") {
                Toggle("Include window shadow in captures", isOn: $includeWindowShadow)
            }
            Section("Thumbnail") {
                Slider(value: $thumbnailDuration, in: 1...10, step: 0.5) {
                    Text("Thumbnail duration: \(String(format: "%.1f", thumbnailDuration))s")
                }
            }
            Section {
                Button("Reset All Settings", role: .destructive) {
                    resetAll()
                }
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
        for key in ["saveLocation", "imageFormat", "jpegQuality", "copyToClipboard", "showThumbnail", "playSound", "includeWindowShadow", "thumbnailDuration"] {
            defaults.removeObject(forKey: key)
        }
    }
}

struct ShortcutRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}
