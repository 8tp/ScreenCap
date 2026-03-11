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
    var currentFilled: Bool = false
    var onAnnotationsChanged: (() -> Void)?
    var onCropApplied: ((NSRect) -> Void)?
    var onCanvasSizeChanged: (() -> Void)?

    private struct UndoState {
        let image: NSImage?
        let annotations: [Annotation]
        let canvasSize: NSSize
    }

    private static let sharedCIContext = CIContext()

    private var activeAnnotation: Annotation?
    private var dragStart: NSPoint?
    private var stepCounter = 1
    private var undoStack: [UndoState] = []
    private var redoStack: [UndoState] = []
    private var cropAnnotation: Annotation?
    private var activeTextField: NSTextField?

    // Selection/move state
    private var movingAnnotation: Annotation?
    private var moveOffset: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let image = baseImage {
            image.draw(in: bounds)
        }

        // Draw blur annotations
        for annotation in annotations where annotation.toolType == .blur {
            drawBlur(annotation: annotation, in: context)
        }

        // Live blur preview while dragging
        if let active = activeAnnotation, active.toolType == .blur {
            drawBlur(annotation: active, in: context)
        }

        // Draw all other annotations (except crop and blur)
        for annotation in annotations where annotation.toolType != .blur && annotation.toolType != .crop {
            annotation.draw(in: context, viewBounds: bounds)
        }

        // Draw active annotation being created (except blur which is drawn above, and crop)
        if let active = activeAnnotation, active.toolType != .blur, active.toolType != .crop {
            active.draw(in: context, viewBounds: bounds)
        }

        // Draw crop overlay last
        if let crop = cropAnnotation {
            crop.draw(in: context, viewBounds: bounds)
        } else if let active = activeAnnotation, active.toolType == .crop {
            active.draw(in: context, viewBounds: bounds)
        }
    }

    private func drawBlur(annotation: Annotation, in context: CGContext) {
        guard annotation.rect.width > 0, annotation.rect.height > 0 else { return }

        if let cached = annotation.cachedBlurImage, annotation.cachedBlurRect == annotation.rect {
            context.draw(cached, in: annotation.rect)
            return
        }

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

        guard let cgImage = Self.sharedCIContext.createCGImage(croppedBlur, from: ciRect) else { return }

        annotation.cachedBlurImage = cgImage
        annotation.cachedBlurRect = annotation.rect

        context.draw(cgImage, in: annotation.rect)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        commitActiveTextField()
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        dragStart = point

        // Select tool: click to select, then drag to move
        if currentTool == .select {
            handleSelectMouseDown(point: point)
            return
        }

        // For non-select tools, deselect all on click
        for a in annotations { a.isSelected = false }
        needsDisplay = true

        if currentTool == .text {
            handleInlineText(at: point)
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

        if currentTool == .crop {
            cropAnnotation = nil
            let annotation = Annotation(toolType: .crop, color: .white, lineWidth: 1)
            annotation.rect = NSRect(origin: point, size: .zero)
            activeAnnotation = annotation
            needsDisplay = true
            return
        }

        pushUndo()
        let annotation = Annotation(toolType: currentTool, color: currentColor, lineWidth: currentLineWidth)
        annotation.isFilled = currentFilled

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
        let point = convert(event.locationInWindow, from: nil)

        // Handle move drag for select tool
        if currentTool == .select, let moving = movingAnnotation {
            let dx = point.x - moveOffset.x
            let dy = point.y - moveOffset.y
            moveOffset = point
            moveAnnotation(moving, dx: dx, dy: dy)
            needsDisplay = true
            return
        }

        guard let annotation = activeAnnotation, let start = dragStart else { return }

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
        case .blur:
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
            // Clear blur cache so it re-renders during drag
            annotation.cachedBlurImage = nil
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
        // Finish move
        if currentTool == .select, movingAnnotation != nil {
            movingAnnotation = nil
            onAnnotationsChanged?()
            return
        }

        guard let annotation = activeAnnotation else { return }

        if annotation.toolType == .crop {
            if annotation.rect.width > 5, annotation.rect.height > 5 {
                cropAnnotation = annotation
                activeAnnotation = nil
                needsDisplay = true
                onCropApplied?(annotation.rect)
            } else {
                activeAnnotation = nil
                needsDisplay = true
            }
            return
        }

        annotations.append(annotation)
        activeAnnotation = nil
        redoStack.removeAll()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    // MARK: - Select & Move

    private func handleSelectMouseDown(point: NSPoint) {
        // Check for hit on existing annotation (reverse order = topmost first)
        var hitAnnotation: Annotation?
        for annotation in annotations.reversed() {
            if annotation.hitTest(point: point) {
                hitAnnotation = annotation
                break
            }
        }

        if let hit = hitAnnotation {
            // Select it
            for a in annotations { a.isSelected = false }
            hit.isSelected = true

            // Start move
            pushUndo()
            movingAnnotation = hit
            moveOffset = point
        } else {
            // Deselect all
            for a in annotations { a.isSelected = false }
            movingAnnotation = nil
        }

        needsDisplay = true
    }

    private func moveAnnotation(_ annotation: Annotation, dx: CGFloat, dy: CGFloat) {
        switch annotation.toolType {
        case .arrow, .line, .freehand:
            for i in 0..<annotation.points.count {
                annotation.points[i].x += dx
                annotation.points[i].y += dy
            }
        default:
            annotation.rect.origin.x += dx
            annotation.rect.origin.y += dy
        }
        // Clear blur cache if moving a blur annotation
        if annotation.toolType == .blur {
            annotation.cachedBlurImage = nil
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            if event.charactersIgnoringModifiers == "z" {
                if flags.contains(.shift) {
                    performRedo()
                } else {
                    performUndo()
                }
                return
            }
            if event.charactersIgnoringModifiers == "c" {
                copyToClipboard()
                return
            }
        }

        if event.keyCode == 53 { // Escape
            if cropAnnotation != nil {
                cropAnnotation = nil
                needsDisplay = true
                return
            }
            for a in annotations { a.isSelected = false }
            needsDisplay = true
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Delete
            if let selected = annotations.last(where: { $0.isSelected }) {
                pushUndo()
                annotations.removeAll { $0.id == selected.id }
                needsDisplay = true
                onAnnotationsChanged?()
            }
        }
    }

    private func copyToClipboard() {
        guard let image = renderFinalImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        Toast.show(message: "Copied to clipboard")
    }

    // MARK: - Inline Text

    private func handleInlineText(at point: NSPoint) {
        pushUndo()

        let textField = NSTextField(frame: NSRect(x: point.x, y: point.y - 10, width: 200, height: 24))
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = .systemFont(ofSize: 16, weight: .medium)
        textField.textColor = currentColor
        textField.focusRingType = .none
        textField.placeholderString = "Type here..."
        textField.target = self
        textField.action = #selector(textFieldCommitted(_:))
        textField.delegate = self

        addSubview(textField)
        window?.makeFirstResponder(textField)
        activeTextField = textField
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitActiveTextField()
    }

    private func commitActiveTextField() {
        guard let tf = activeTextField else { return }
        let text = tf.stringValue
        let origin = tf.frame.origin

        tf.removeFromSuperview()
        activeTextField = nil

        guard !text.isEmpty else { return }

        let annotation = Annotation(toolType: .text, color: currentColor, lineWidth: currentLineWidth)
        annotation.text = text
        annotation.fontSize = 16
        let textSize = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium)])
        annotation.rect = NSRect(origin: NSPoint(x: origin.x, y: origin.y + 10), size: textSize)
        annotations.append(annotation)
        redoStack.removeAll()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    // MARK: - Crop

    func applyCrop() {
        guard let crop = cropAnnotation, let image = baseImage else { return }

        let scaleX = image.size.width / bounds.width
        let scaleY = image.size.height / bounds.height

        let cropRect = NSRect(
            x: crop.rect.origin.x * scaleX,
            y: crop.rect.origin.y * scaleY,
            width: crop.rect.width * scaleX,
            height: crop.rect.height * scaleY
        )

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else { return }

        let flippedRect = CGRect(
            x: cropRect.origin.x,
            y: image.size.height - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )

        guard let croppedCG = cgImage.cropping(to: flippedRect) else { return }

        let croppedImage = NSImage(cgImage: croppedCG, size: NSSize(width: croppedCG.width, height: croppedCG.height))

        // Save undo state BEFORE changing anything (includes current canvas size)
        pushUndo()
        annotations.removeAll()
        cropAnnotation = nil
        baseImage = croppedImage

        let maxWidth: CGFloat = 1200
        let maxHeight: CGFloat = 800
        let scale = min(maxWidth / croppedImage.size.width, maxHeight / croppedImage.size.height, 1.0)
        let newSize = NSSize(width: croppedImage.size.width * scale, height: croppedImage.size.height * scale)
        frame = NSRect(origin: frame.origin, size: newSize)

        needsDisplay = true
        onAnnotationsChanged?()
        onCanvasSizeChanged?()
    }

    func cancelCrop() {
        cropAnnotation = nil
        needsDisplay = true
    }

    var hasPendingCrop: Bool { cropAnnotation != nil }

    // MARK: - Undo/Redo

    func pushUndo() {
        undoStack.append(UndoState(image: baseImage, annotations: annotations.map { copyAnnotation($0) }, canvasSize: frame.size))
        redoStack.removeAll()
    }

    func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(UndoState(image: baseImage, annotations: annotations.map { copyAnnotation($0) }, canvasSize: frame.size))
        baseImage = previous.image
        annotations = previous.annotations
        cropAnnotation = nil

        // Restore canvas size (critical for undoing crop)
        if previous.canvasSize != frame.size {
            frame = NSRect(origin: frame.origin, size: previous.canvasSize)
            onCanvasSizeChanged?()
        }

        needsDisplay = true
        onAnnotationsChanged?()
    }

    func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(UndoState(image: baseImage, annotations: annotations.map { copyAnnotation($0) }, canvasSize: frame.size))
        baseImage = next.image
        annotations = next.annotations
        cropAnnotation = nil

        if next.canvasSize != frame.size {
            frame = NSRect(origin: frame.origin, size: next.canvasSize)
            onCanvasSizeChanged?()
        }

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
        copy.cachedBlurImage = a.cachedBlurImage
        copy.cachedBlurRect = a.cachedBlurRect
        return copy
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

        for annotation in annotations where annotation.toolType == .blur {
            drawBlur(annotation: annotation, in: context)
        }

        for annotation in annotations where annotation.toolType != .blur && annotation.toolType != .crop {
            annotation.draw(in: context, viewBounds: bounds)
        }

        finalImage.unlockFocus()
        return finalImage
    }
}

// MARK: - NSTextFieldDelegate

extension AnnotationCanvas: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveTextField()
    }
}
