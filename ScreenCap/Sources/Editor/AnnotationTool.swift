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
            break
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

        // Shaft
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 15
        let headAngle: CGFloat = .pi / 6

        let p1 = NSPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = NSPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.setFillColor(color.cgColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
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
        context.move(to: points[0])
        for i in 1..<points.count {
            context.addLine(to: points[i])
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
