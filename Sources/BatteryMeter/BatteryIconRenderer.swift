import AppKit
import BatteryCore

/// Draws the "battery with percentage inside" menu bar icon. A vector drawing handler, so
/// it stays sharp at any scale. The numerals and the bolt are knocked out of the level fill
/// and drawn normally over the empty part, so they read over both.
enum BatteryIconRenderer {
    static let size = NSSize(width: 27, height: 12)
    private static let body = NSRect(x: 0.5, y: 0.5, width: 24, height: 11)
    private static let fontSize: CGFloat = 8

    /// A template image when `role` is `.none` (it adapts to the menu bar); otherwise a
    /// colored one: red for `.low`, green for `.charging`. A colored image draws its outline
    /// and numerals in `ink`, which follows the appearance it is drawn in unless given.
    static func image(percent: Int, charging: Bool, role: MenuBarColorRole, ink: NSColor? = nil) -> NSImage {
        let percent = min(max(percent, 0), 100)
        let image = NSImage(size: size, flipped: false) { _ in
            draw(percent: percent, charging: charging, role: role, ink: ink)
            return true
        }
        image.isTemplate = role == .none
        return image
    }

    private static func draw(percent: Int, charging: Bool, role: MenuBarColorRole, ink custom: NSColor?) {
        guard let ctx = NSGraphicsContext.current else { return }
        let template = role == .none
        let ink: NSColor = template ? .black : custom ?? .labelColor
        let fillColor: NSColor = switch role {
        case .none: .black
        case .low: .systemRed
        case .charging: .systemGreen
        }

        // Outline and terminal nub.
        ink.setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1
        outline.stroke()
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: 24.5, y: 4, width: 2, height: 4), xRadius: 1, yRadius: 1).fill()

        // Level fill, with a visible sliver above 0%.
        let inner = body.insetBy(dx: 1.5, dy: 1.5)
        var fillRect = NSRect.zero
        if percent > 0 {
            fillRect = NSRect(x: inner.minX, y: inner.minY,
                              width: max(1.5, inner.width * CGFloat(percent) / 100), height: inner.height)
            fillColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 1.7, yRadius: 1.7).fill()
        }

        // Numerals (and the bolt while charging), centered in the body.
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let text = "\(percent)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let textSize = text.size(withAttributes: attributes)
        let boltSize = NSSize(width: 3.2, height: 6)
        let gap: CGFloat = 0.75
        let contentWidth = textSize.width + (charging ? boltSize.width + gap : 0)
        var x = body.midX - contentWidth / 2
        let midY = body.midY
        let boltOrigin = NSPoint(x: x, y: midY - boltSize.height / 2)
        if charging { x += boltSize.width + gap }
        let textOrigin = NSPoint(x: x, y: midY - font.capHeight / 2 + font.descender)

        let drawOverlay = {
            if charging { bolt(at: boltOrigin, size: boltSize).fill() }
            text.draw(at: textOrigin, withAttributes: attributes)
        }
        // Over the fill: knocked out. Over the rest: drawn in the ink color.
        ctx.saveGraphicsState()
        if percent > 0 {
            NSBezierPath(roundedRect: fillRect, xRadius: 1.7, yRadius: 1.7).addClip()
            ctx.compositingOperation = .destinationOut
            drawOverlay()
        }
        ctx.restoreGraphicsState()
        ctx.saveGraphicsState()
        let outside = NSBezierPath(rect: NSRect(origin: .zero, size: size))
        if percent > 0 { outside.append(NSBezierPath(roundedRect: fillRect, xRadius: 1.7, yRadius: 1.7)) }
        outside.windingRule = .evenOdd
        outside.addClip()
        ink.setFill()
        drawOverlay()
        ctx.restoreGraphicsState()
    }

    private static func bolt(at origin: NSPoint, size: NSSize) -> NSBezierPath {
        let points: [(CGFloat, CGFloat)] = [(0.72, 1), (0, 0.55), (0.44, 0.55), (0.28, 0), (1, 0.65), (0.54, 0.65)]
        let path = NSBezierPath()
        for (i, p) in points.enumerated() {
            let point = NSPoint(x: origin.x + p.0 * size.width, y: origin.y + p.1 * size.height)
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }
}
