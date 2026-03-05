import Cocoa
import CoreImage

class AnnotationCanvas: NSView {
    var baseImage: NSImage? {
        didSet { needsDisplay = true }
    }
    var annotations: [Annotation] = []
    var currentTool: AnnotationToolType = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3
    var onAnnotationsChanged: (() -> Void)?

    private var activeAnnotation: Annotation?
    private var dragStart: NSPoint?
    private var selectedAnnotation: Annotation?
    private var stepCounter = 1
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw base image
        if let image = baseImage {
            image.draw(in: bounds)
        }

        // Apply blur annotations to the image layer
        for annotation in annotations where annotation.toolType == .blur {
            drawBlur(annotation: annotation, in: context)
        }

        // Draw all other annotations
        for annotation in annotations where annotation.toolType != .blur {
            annotation.draw(in: context, viewBounds: bounds)
        }

        // Draw active annotation being created
        if let active = activeAnnotation, active.toolType != .blur {
            active.draw(in: context, viewBounds: bounds)
        }
    }

    private func drawBlur(annotation: Annotation, in context: CGContext) {
        guard annotation.rect.width > 0, annotation.rect.height > 0 else { return }
        guard let image = baseImage,
              let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else { return }

        let scaleX = ciImage.extent.width / bounds.width
        let scaleY = ciImage.extent.height / bounds.height
        let ciRect = CGRect(
            x: annotation.rect.origin.x * scaleX,
            y: annotation.rect.origin.y * scaleY,
            width: annotation.rect.width * scaleX,
            height: annotation.rect.height * scaleY
        )

        guard let pixellateFilter = CIFilter(name: "CIPixellate") else { return }
        pixellateFilter.setValue(ciImage, forKey: kCIInputImageKey)
        pixellateFilter.setValue(max(ciRect.width, ciRect.height) / 10, forKey: kCIInputScaleKey)

        guard let outputImage = pixellateFilter.outputImage else { return }
        let croppedBlur = outputImage.cropped(to: ciRect)

        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(croppedBlur, from: ciRect) else { return }

        context.draw(cgImage, in: annotation.rect)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point

        if currentTool == .text {
            handleTextPlacement(at: point)
            return
        }

        if currentTool == .numberedStep {
            pushUndo()
            let annotation = Annotation(toolType: .numberedStep, color: currentColor, lineWidth: currentLineWidth)
            annotation.rect = NSRect(origin: point, size: .zero)
            annotation.stepNumber = stepCounter
            stepCounter += 1
            annotations.append(annotation)
            needsDisplay = true
            onAnnotationsChanged?()
            return
        }

        pushUndo()
        let annotation = Annotation(toolType: currentTool, color: currentColor, lineWidth: currentLineWidth)

        switch currentTool {
        case .arrow, .line:
            annotation.points = [point, point]
        case .freehand:
            annotation.points = [point]
        default:
            annotation.rect = NSRect(origin: point, size: .zero)
        }

        activeAnnotation = annotation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let annotation = activeAnnotation, let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)

        switch annotation.toolType {
        case .arrow, .line:
            if annotation.points.count >= 2 {
                var endPoint = point
                if NSEvent.modifierFlags.contains(.shift) {
                    endPoint = constrainToAngles(from: annotation.points[0], to: point)
                }
                annotation.points[1] = endPoint
            }
        case .freehand:
            annotation.points.append(point)
        default:
            var rect = NSRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            if NSEvent.modifierFlags.contains(.shift) {
                let side = max(rect.width, rect.height)
                rect.size = NSSize(width: side, height: side)
            }
            annotation.rect = rect
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let annotation = activeAnnotation else { return }
        annotations.append(annotation)
        activeAnnotation = nil
        redoStack.removeAll()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Delete
            if let selected = annotations.last(where: { $0.isSelected }) {
                pushUndo()
                annotations.removeAll { $0.id == selected.id }
                needsDisplay = true
                onAnnotationsChanged?()
            }
        }
    }

    // MARK: - Undo/Redo

    func pushUndo() {
        undoStack.append(annotations.map { copyAnnotation($0) })
    }

    func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations.map { copyAnnotation($0) })
        annotations = previous
        needsDisplay = true
        onAnnotationsChanged?()
    }

    func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations.map { copyAnnotation($0) })
        annotations = next
        needsDisplay = true
        onAnnotationsChanged?()
    }

    private func copyAnnotation(_ a: Annotation) -> Annotation {
        let copy = Annotation(toolType: a.toolType, color: a.color, lineWidth: a.lineWidth)
        copy.points = a.points
        copy.rect = a.rect
        copy.text = a.text
        copy.fontSize = a.fontSize
        copy.stepNumber = a.stepNumber
        copy.isFilled = a.isFilled
        return copy
    }

    // MARK: - Text Input

    private func handleTextPlacement(at point: NSPoint) {
        let alert = NSAlert()
        alert.messageText = "Enter Text"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = ""
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let text = textField.stringValue
            guard !text.isEmpty else { return }

            pushUndo()
            let annotation = Annotation(toolType: .text, color: currentColor, lineWidth: currentLineWidth)
            annotation.text = text
            annotation.rect = NSRect(origin: point, size: NSSize(width: 200, height: 30))
            annotations.append(annotation)
            needsDisplay = true
            onAnnotationsChanged?()
        }
    }

    // MARK: - Helpers

    private func constrainToAngles(from start: NSPoint, to end: NSPoint) -> NSPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let distance = hypot(dx, dy)
        let snapped = round(angle / (.pi / 4)) * (.pi / 4)
        return NSPoint(x: start.x + distance * cos(snapped), y: start.y + distance * sin(snapped))
    }

    // MARK: - Export

    func renderFinalImage() -> NSImage? {
        guard let image = baseImage else { return nil }
        let size = image.size

        let finalImage = NSImage(size: size)
        finalImage.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))

        guard let context = NSGraphicsContext.current?.cgContext else {
            finalImage.unlockFocus()
            return nil
        }

        let scaleX = size.width / bounds.width
        let scaleY = size.height / bounds.height
        context.scaleBy(x: scaleX, y: scaleY)

        // Apply blur annotations first
        for annotation in annotations where annotation.toolType == .blur {
            drawBlur(annotation: annotation, in: context)
        }

        // Then draw all other annotations
        for annotation in annotations where annotation.toolType != .blur {
            annotation.draw(in: context, viewBounds: bounds)
        }

        finalImage.unlockFocus()
        return finalImage
    }
}
