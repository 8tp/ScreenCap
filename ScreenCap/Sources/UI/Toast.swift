import Cocoa

enum ToastStyle {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .success: return .systemGreen
        case .error: return .systemRed
        case .info: return .systemBlue
        }
    }
}

enum Toast {
    private static var toastWindow: NSWindow?

    static func show(message: String, style: ToastStyle = .success, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async {
            toastWindow?.orderOut(nil)

            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }

            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
            let textSize = (message as NSString).size(withAttributes: attrs)
            let padding: CGFloat = 32
            let iconSize: CGFloat = 16
            let toastWidth = textSize.width + padding * 2 + iconSize + 8
            let toastHeight: CGFloat = 36

            let x = screen.frame.midX - toastWidth / 2
            let y = screen.visibleFrame.minY + 60

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

            let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: toastWidth, height: toastHeight)))
            view.blendingMode = .behindWindow
            view.material = .hudWindow
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = toastHeight / 2
            view.layer?.masksToBounds = true

            // Icon
            let iconView = NSImageView(frame: NSRect(x: padding - 4, y: (toastHeight - iconSize) / 2, width: iconSize, height: iconSize))
            iconView.image = NSImage(systemSymbolName: style.icon, accessibilityDescription: nil)
            iconView.contentTintColor = style.tintColor
            view.addSubview(iconView)

            let label = NSTextField(labelWithString: message)
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            label.alignment = .natural
            label.frame = NSRect(x: padding + iconSize + 4, y: (toastHeight - textSize.height) / 2, width: textSize.width + 4, height: textSize.height)
            view.addSubview(label)

            window.contentView = view
            window.alphaValue = 0
            window.orderFront(nil)

            // Slide up + fade in
            let startFrame = window.frame
            window.setFrame(startFrame.offsetBy(dx: 0, dy: -10), display: false)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
                window.animator().setFrame(startFrame, display: true)
            }

            toastWindow = window

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().alphaValue = 0
                    window.animator().setFrame(startFrame.offsetBy(dx: 0, dy: -10), display: true)
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
