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
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}
