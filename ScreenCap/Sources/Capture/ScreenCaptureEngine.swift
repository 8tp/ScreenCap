import Cocoa
import ScreenCaptureKit

class ScreenCaptureEngine {
    private let defaults = Defaults.shared
    private var activeAreaSelector: AreaSelector?
    private var activeWindowSelector: WindowSelector?

    func captureFullscreen(completion: @escaping (Result<URL, Error>) -> Void) {
        performWithDelay {
            self.hideDesktopIconsIfNeeded()

            DispatchQueue.main.async {
                let mouse = NSEvent.mouseLocation
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
                    self.restoreDesktopIconsIfNeeded()
                    completion(.failure(CaptureError.noDisplay))
                    return
                }

                guard let image = CGDisplayCreateImage(screen.displayID) else {
                    self.restoreDesktopIconsIfNeeded()
                    completion(.failure(CaptureError.captureFailed))
                    return
                }

                self.restoreDesktopIconsIfNeeded()
                self.flashScreen()

                if self.defaults.playSound {
                    NSSound(named: "Tink")?.play()
                }

                do {
                    let url = try ImageUtilities.save(image: image)
                    if self.defaults.copyToClipboard {
                        ImageUtilities.copyToClipboard(image: image)
                    }
                    self.defaults.addRecentCapture(url)
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func captureArea(completion: @escaping (Result<URL, Error>) -> Void) {
        let selector = AreaSelector { [weak self] result in
            self?.activeAreaSelector = nil  // Release after completion
            guard let self = self else { return }
            switch result {
            case .success(let rect):
                self.performWithDelay {
                    self.hideDesktopIconsIfNeeded()

                    guard let image = CGWindowListCreateImage(
                        rect,
                        .optionOnScreenOnly,
                        kCGNullWindowID,
                        [.bestResolution]
                    ) else {
                        self.restoreDesktopIconsIfNeeded()
                        completion(.failure(CaptureError.captureFailed))
                        return
                    }

                    self.restoreDesktopIconsIfNeeded()

                    if self.defaults.playSound {
                        NSSound(named: "Tink")?.play()
                    }

                    do {
                        let url = try ImageUtilities.save(image: image)
                        if self.defaults.copyToClipboard {
                            ImageUtilities.copyToClipboard(image: image)
                        }
                        self.defaults.addRecentCapture(url)
                        completion(.success(url))
                    } catch {
                        completion(.failure(error))
                    }
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
        activeAreaSelector = selector  // Retain until completion fires
        selector.show()
    }

    func captureWindow(completion: @escaping (Result<URL, Error>) -> Void) {
        let selector = WindowSelector { [weak self] result in
            self?.activeWindowSelector = nil  // Release after completion
            guard let self = self else { return }
            switch result {
            case .success(let image):
                self.flashScreen()

                if self.defaults.playSound {
                    NSSound(named: "Tink")?.play()
                }

                do {
                    let url = try ImageUtilities.save(image: image)
                    if self.defaults.copyToClipboard {
                        ImageUtilities.copyToClipboard(image: image)
                    }
                    self.defaults.addRecentCapture(url)
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
        activeWindowSelector = selector  // Retain until completion fires
        selector.show()
    }

    // MARK: - Timed Capture

    private func performWithDelay(_ action: @escaping () -> Void) {
        let delay = defaults.captureDelay
        guard delay > 0 else {
            action()
            return
        }

        showCountdownOverlay(seconds: delay) {
            action()
        }
    }

    private var countdownWindow: NSWindow?

    private func showCountdownOverlay(seconds: Int, completion: @escaping () -> Void) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            completion()
            return
        }

        let overlaySize: CGFloat = 120
        let window = NSWindow(
            contentRect: NSRect(
                x: screen.frame.midX - overlaySize / 2,
                y: screen.frame.midY - overlaySize / 2,
                width: overlaySize,
                height: overlaySize
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: overlaySize, height: overlaySize)))
        view.wantsLayer = true
        view.layer?.cornerRadius = overlaySize / 2
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor

        let label = NSTextField(labelWithString: "\(seconds)")
        label.font = .systemFont(ofSize: 48, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (overlaySize - 60) / 2, width: overlaySize, height: 60)
        view.addSubview(label)

        window.contentView = view
        window.orderFront(nil)
        countdownWindow = window

        var remaining = seconds
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                window.orderOut(nil)
                self?.countdownWindow = nil
                completion()
            } else {
                label.stringValue = "\(remaining)"
            }
        }
    }

    // MARK: - Hide Desktop Icons

    private var desktopIconsWereHidden = false

    private func hideDesktopIconsIfNeeded() {
        guard defaults.hideDesktopIcons else { return }
        desktopIconsWereHidden = true
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"]
        task.launch()
        task.waitUntilExit()
        restartFinder()
        // Give Finder time to hide icons
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func restoreDesktopIconsIfNeeded() {
        guard desktopIconsWereHidden else { return }
        desktopIconsWereHidden = false
        // If user has manually toggled desktop icons off, don't restore them
        guard !Defaults.shared.desktopIconsHidden else { return }
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", "true"]
        task.launch()
        task.waitUntilExit()
        restartFinder()
    }

    private func restartFinder() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Finder"]
        task.launch()
    }

    // MARK: - Flash Effect

    private func flashScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let flashWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        flashWindow.level = .screenSaver
        flashWindow.backgroundColor = .white
        flashWindow.alphaValue = 0.6
        flashWindow.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            flashWindow.animator().alphaValue = 0.0
        }, completionHandler: {
            flashWindow.orderOut(nil)
        })
    }
}

enum CaptureError: LocalizedError {
    case noDisplay
    case captureFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found"
        case .captureFailed: return "Failed to capture screen"
        case .cancelled: return "Capture cancelled"
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    /// Height of the primary display in NS global coordinates.
    /// Used for converting between NS (origin bottom-left) and CG (origin top-left) coordinate systems.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height ?? 0
    }
}
