import Foundation

class Defaults {
    static let shared = Defaults()

    private let store = UserDefaults.standard

    var saveLocation: URL {
        get {
            if let path = store.string(forKey: "saveLocation") {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        }
        set { store.set(newValue.path, forKey: "saveLocation") }
    }

    var imageFormat: String {
        get { store.string(forKey: "imageFormat") ?? "png" }
        set { store.set(newValue, forKey: "imageFormat") }
    }

    var jpegQuality: Double {
        get { store.double(forKey: "jpegQuality").nonZeroOr(0.85) }
        set { store.set(newValue, forKey: "jpegQuality") }
    }

    var copyToClipboard: Bool {
        get { store.object(forKey: "copyToClipboard") == nil ? true : store.bool(forKey: "copyToClipboard") }
        set { store.set(newValue, forKey: "copyToClipboard") }
    }

    var showThumbnail: Bool {
        get { store.object(forKey: "showThumbnail") == nil ? true : store.bool(forKey: "showThumbnail") }
        set { store.set(newValue, forKey: "showThumbnail") }
    }

    var playSound: Bool {
        get { store.object(forKey: "playSound") == nil ? true : store.bool(forKey: "playSound") }
        set { store.set(newValue, forKey: "playSound") }
    }

    var includeWindowShadow: Bool {
        get { store.object(forKey: "includeWindowShadow") == nil ? true : store.bool(forKey: "includeWindowShadow") }
        set { store.set(newValue, forKey: "includeWindowShadow") }
    }

    var thumbnailDuration: Double {
        get { store.double(forKey: "thumbnailDuration").nonZeroOr(5.0) }
        set { store.set(newValue, forKey: "thumbnailDuration") }
    }

    // Timed capture delay in seconds (0 = instant)
    var captureDelay: Int {
        get { store.integer(forKey: "captureDelay") }
        set { store.set(newValue, forKey: "captureDelay") }
    }

    // Hide desktop icons before capture
    var hideDesktopIcons: Bool {
        get { store.bool(forKey: "hideDesktopIcons") }
        set { store.set(newValue, forKey: "hideDesktopIcons") }
    }

    // Thumbnail position: "bottomRight" or "bottomLeft"
    var thumbnailPosition: String {
        get { store.string(forKey: "thumbnailPosition") ?? "bottomRight" }
        set { store.set(newValue, forKey: "thumbnailPosition") }
    }

    // Freeze screen during area capture
    var freezeScreen: Bool {
        get { store.object(forKey: "freezeScreen") == nil ? true : store.bool(forKey: "freezeScreen") }
        set { store.set(newValue, forKey: "freezeScreen") }
    }

    // Desktop icons currently hidden by user toggle (not capture-related)
    var desktopIconsHidden: Bool {
        get { store.bool(forKey: "desktopIconsHidden") }
        set { store.set(newValue, forKey: "desktopIconsHidden") }
    }

    // GIF export settings
    var gifMaxWidth: Int {
        get { let v = store.integer(forKey: "gifMaxWidth"); return v > 0 ? v : 640 }
        set { store.set(newValue, forKey: "gifMaxWidth") }
    }

    var gifFrameRate: Int {
        get { let v = store.integer(forKey: "gifFrameRate"); return v > 0 ? v : 15 }
        set { store.set(newValue, forKey: "gifFrameRate") }
    }

    // MARK: - Capture History

    private let maxRecentCaptures = 20

    var recentCaptures: [URL] {
        get {
            guard let paths = store.stringArray(forKey: "recentCaptures") else { return [] }
            return paths.compactMap { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        set {
            let paths = Array(newValue.prefix(maxRecentCaptures)).map { $0.path }
            store.set(paths, forKey: "recentCaptures")
        }
    }

    func addRecentCapture(_ url: URL) {
        var recent = recentCaptures
        recent.removeAll { $0 == url }
        recent.insert(url, at: 0)
        recentCaptures = recent
    }

    func clearRecentCaptures() {
        store.removeObject(forKey: "recentCaptures")
    }
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}
