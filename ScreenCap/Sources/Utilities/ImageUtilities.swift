import Cocoa

enum ImageUtilities {
    static func save(image: CGImage) throws -> URL {
        let defaults = Defaults.shared
        let filename = generateFilename()
        let ext = defaults.imageFormat
        let url = defaults.saveLocation.appendingPathComponent("\(filename).\(ext)")

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, imageUTType(for: ext), 1, nil) else {
            throw CaptureError.captureFailed
        }

        var options: [CFString: Any] = [:]
        if ext == "jpeg" || ext == "jpg" {
            options[kCGImageDestinationLossyCompressionQuality] = defaults.jpegQuality
        }

        CGImageDestinationAddImage(dest, image, options as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw CaptureError.captureFailed
        }

        return url
    }

    static func copyToClipboard(image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
    }

    private static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        return "Screenshot \(formatter.string(from: Date()))"
    }

    private static func imageUTType(for ext: String) -> CFString {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "public.jpeg" as CFString
        case "tiff", "tif": return "public.tiff" as CFString
        default: return "public.png" as CFString
        }
    }
}
