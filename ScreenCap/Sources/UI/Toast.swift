import Cocoa

enum Toast {
    private static var toastWindow: NSWindow?

    static func show(message: String, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async {
            toastWindow?.orderOut(nil)

            guard let screen = NSScreen.main else { return }

            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ]
            let textSize = (message as NSString).size(withAttributes: attrs)
            let padding: CGFloat = 24
            let toastWidth = textSize.width + padding * 2
            let toastHeight: CGFloat = 36

            let x = screen.frame.midX - toastWidth / 2
            let y = screen.frame.minY + 80

            let window = NSWindow(
                contentRect: NSRect(x: x, y: y, width: toastWidth, height: toastHeight),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true

            let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: toastWidth, height: toastHeight)))
            view.wantsLayer = true
            view.layer?.cornerRadius = toastHeight / 2
            view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor

            let label = NSTextField(labelWithString: message)
            label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 0, y: (toastHeight - textSize.height) / 2, width: toastWidth, height: textSize.height)
            view.addSubview(label)

            window.contentView = view
            window.alphaValue = 0
            window.orderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1.0
            }

            toastWindow = window

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    if toastWindow === window {
                        toastWindow = nil
                    }
                })
            }
        }
    }
}
