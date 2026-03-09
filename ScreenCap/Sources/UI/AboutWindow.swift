import Cocoa

class AboutWindowController {
    static let shared = AboutWindowController()

    func show() {
        let credits = NSMutableAttributedString()

        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        credits.append(NSAttributedString(
            string: "The free, open-source screenshot\nand screen recording app for macOS.\n\n",
            attributes: descAttrs
        ))

        let featureAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let features = [
            "Screenshots & Area Capture",
            "Screen Recording & GIF Export",
            "Annotation Editor",
            "Background Tool",
            "OCR Text Recognition",
            "Color Picker"
        ]
        credits.append(NSAttributedString(
            string: features.joined(separator: " · "),
            attributes: featureAttrs
        ))

        // Use paragraph style to center the text
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ScreenCap",
            .applicationVersion: "1.0",
            .version: "1",
            .credits: credits,
        ])
    }
}
