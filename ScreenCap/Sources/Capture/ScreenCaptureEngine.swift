import Cocoa
import ScreenCaptureKit

class ScreenCaptureEngine {
    private let defaults = Defaults.shared

    func captureFullscreen(completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.main.async {
            guard NSScreen.main != nil else {
                completion(.failure(CaptureError.noDisplay))
                return
            }

            guard let image = CGWindowListCreateImage(
                CGRect.null,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.nominalResolution]
            ) else {
                completion(.failure(CaptureError.captureFailed))
                return
            }

            // Flash effect
            self.flashScreen()

            // Play shutter sound
            if self.defaults.playSound {
                NSSound(named: "Tink")?.play()
            }

            // Save
            do {
                let url = try ImageUtilities.save(image: image)
                // Copy to clipboard
                if self.defaults.copyToClipboard {
                    ImageUtilities.copyToClipboard(image: image)
                }
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func captureArea(completion: @escaping (Result<URL, Error>) -> Void) {
        let selector = AreaSelector { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let rect):
                guard let image = CGWindowListCreateImage(
                    rect,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.nominalResolution]
                ) else {
                    completion(.failure(CaptureError.captureFailed))
                    return
                }

                if self.defaults.playSound {
                    NSSound(named: "Tink")?.play()
                }

                do {
                    let url = try ImageUtilities.save(image: image)
                    if self.defaults.copyToClipboard {
                        ImageUtilities.copyToClipboard(image: image)
                    }
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
        selector.show()
    }

    func captureWindow(completion: @escaping (Result<URL, Error>) -> Void) {
        let selector = WindowSelector { [weak self] result in
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
                    completion(.success(url))
                } catch {
                    completion(.failure(error))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
        selector.show()
    }

    private func flashScreen() {
        guard let screen = NSScreen.main else { return }
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
}
