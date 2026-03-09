import Cocoa

enum AnnotationToolType: String, CaseIterable {
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case line = "Line"
    case text = "Text"
    case freehand = "Freehand"
    case highlight = "Highlight"
    case blur = "Blur"
    case numberedStep = "Step"
    case crop = "Crop"

    var iconName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .freehand: return "pencil.tip"
        case .highlight: return "highlighter"
        case .blur: return "eye.slash"
        case .numberedStep: return "1.circle"
        case .crop: return "crop"
        }
    }
}

class Annotation {
    let id = UUID()
    var toolType: AnnotationToolType
    var color: NSColor
    var lineWidth: CGFloat
    var points: [NSPoint] = []
    var rect: NSRect = .zero
    var text: String = ""
    var fontSize: CGFloat = 16
    var stepNumber: Int = 1
    var isFilled: Bool = false
    var isSelected: Bool = false

    // Blur cache — avoids recomputing CIFilter pipeline every frame
    var cachedBlurImage: CGImage?
    var cachedBlurRect: NSRect = .zero

    init(toolType: AnnotationToolType, color: NSColor = .systemRed, lineWidth: CGFloat = 3) {
        self.toolType = toolType
        self.color = color
        self.lineWidth = lineWidth
    }

    func draw(in context: CGContext, viewBounds: NSRect) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch toolType {
        case .arrow:
            drawArrow(in: context)
        case .rectangle:
            drawRectangle(in: context)
        case .ellipse:
            drawEllipse(in: context)
        case .line:
            drawLine(in: context)
        case .text:
            drawText()
        case .freehand:
            drawFreehand(in: context)
        case .highlight:
            drawHighlight(in: context)
        case .blur:
            break // blur is handled separately on the image
        case .numberedStep:
            drawNumberedStep(in: context)
        case .crop:
            drawCropOverlay(in: context, viewBounds: viewBounds)
        }

        if isSelected {
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(rect.insetBy(dx: -4, dy: -4))
        }

        context.restoreGState()
    }

    private func drawArrow(in context: CGContext) {
        guard points.count >= 2 else { return }
        let start = points[0]
        let end = points[1]

        // Arrowhead geometry
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = max(12, lineWidth * 4)
        let headAngle: CGFloat = .pi / 6

        let p1 = NSPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = NSPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        // Shaft — end at base of arrowhead to avoid overlap dot
        let basePoint = NSPoint(
            x: (p1.x + p2.x) / 2,
            y: (p1.y + p2.y) / 2
        )
        context.move(to: start)
        context.addLine(to: basePoint)
        context.strokePath()

        // Arrowhead — filled triangle
        context.beginPath()
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    private func drawRectangle(in context: CGContext) {
        if isFilled {
            context.setFillColor(color.withAlphaComponent(0.3).cgColor)
            context.fill(rect)
        }
        context.stroke(rect)
    }

    private func drawEllipse(in context: CGContext) {
        if isFilled {
            context.setFillColor(color.withAlphaComponent(0.3).cgColor)
            context.fillEllipse(in: rect)
        }
        context.strokeEllipse(in: rect)
    }

    private func drawLine(in context: CGContext) {
        guard points.count >= 2 else { return }
        context.move(to: points[0])
        context.addLine(to: points[1])
        context.strokePath()
    }

    private func drawText() {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ]
        (text as NSString).draw(at: rect.origin, withAttributes: attrs)
    }

    private func drawFreehand(in context: CGContext) {
        guard points.count >= 2 else { return }

        if points.count <= 3 {
            context.move(to: points[0])
            for i in 1..<points.count {
                context.addLine(to: points[i])
            }
            context.strokePath()
            return
        }

        // Smooth Catmull-Rom spline for natural pencil feel
        context.move(to: points[0])
        for i in 0..<points.count - 1 {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[min(points.count - 1, i + 1)]
            let p3 = points[min(points.count - 1, i + 2)]

            let cp1 = NSPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = NSPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            context.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        context.strokePath()
    }

    private func drawHighlight(in context: CGContext) {
        context.setFillColor(color.withAlphaComponent(0.3).cgColor)
        context.fill(rect)
    }

    private func drawNumberedStep(in context: CGContext) {
        let size: CGFloat = 28
        let circleRect = NSRect(x: rect.origin.x - size/2, y: rect.origin.y - size/2, width: size, height: size)

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: circleRect)

        let text = "\(stepNumber)"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14, weight: .bold)
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textPoint = NSPoint(
            x: circleRect.midX - textSize.width / 2,
            y: circleRect.midY - textSize.height / 2
        )
        (text as NSString).draw(at: textPoint, withAttributes: attrs)
    }

    private func drawCropOverlay(in context: CGContext, viewBounds: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        // Dim area outside crop region
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)

        // Top
        context.fill(NSRect(x: 0, y: rect.maxY, width: viewBounds.width, height: viewBounds.height - rect.maxY))
        // Bottom
        context.fill(NSRect(x: 0, y: 0, width: viewBounds.width, height: rect.origin.y))
        // Left
        context.fill(NSRect(x: 0, y: rect.origin.y, width: rect.origin.x, height: rect.height))
        // Right
        context.fill(NSRect(x: rect.maxX, y: rect.origin.y, width: viewBounds.width - rect.maxX, height: rect.height))

        context.restoreGState()

        // Draw crop border
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.stroke(rect)

        // Draw thirds grid
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        let thirdW = rect.width / 3
        let thirdH = rect.height / 3
        for i in 1...2 {
            let x = rect.origin.x + thirdW * CGFloat(i)
            context.move(to: CGPoint(x: x, y: rect.origin.y))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.strokePath()

            let y = rect.origin.y + thirdH * CGFloat(i)
            context.move(to: CGPoint(x: rect.origin.x, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.strokePath()
        }

        // Corner handles
        let handleSize: CGFloat = 8
        context.setFillColor(NSColor.white.cgColor)
        for corner in [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ] {
            context.fill(NSRect(x: corner.x - handleSize/2, y: corner.y - handleSize/2, width: handleSize, height: handleSize))
        }
    }

    func hitTest(point: NSPoint) -> Bool {
        switch toolType {
        case .arrow, .line:
            guard points.count >= 2 else { return false }
            return distanceFromPointToLine(point: point, lineStart: points[0], lineEnd: points[1]) < 8
        case .text:
            return rect.insetBy(dx: -4, dy: -4).contains(point)
        case .numberedStep:
            let size: CGFloat = 28
            let circleRect = NSRect(x: rect.origin.x - size/2, y: rect.origin.y - size/2, width: size, height: size)
            return circleRect.contains(point)
        case .freehand:
            for p in points {
                if hypot(p.x - point.x, p.y - point.y) < 8 { return true }
            }
            return false
        default:
            return rect.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private func distanceFromPointToLine(point: NSPoint, lineStart: NSPoint, lineEnd: NSPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(point.x - lineStart.x, point.y - lineStart.y) }

        var t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lenSq
        t = max(0, min(1, t))

        let proj = NSPoint(x: lineStart.x + t * dx, y: lineStart.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y)
    }
}
