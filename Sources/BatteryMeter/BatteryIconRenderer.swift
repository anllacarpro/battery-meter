import AppKit
import BatteryCore

/// Draws the "battery with percentage inside" menu bar icon in the style of the native
/// battery symbol: a slim translucent outline, a rounded body, a small nub and a soft level
/// fill. A vector drawing handler, so it stays sharp at any scale.
///
/// The numerals are drawn once, in the ink color, over a translucent fill, so they read the
/// same over the filled and the empty part and are never split. While charging, a bolt sits
/// to the left of the battery, outside the body.
enum BatteryIconRenderer {
    private static let height: CGFloat = 12
    private static let bodyWidth: CGFloat = 25
    private static let outlineWidth: CGFloat = 1.1
    private static let outlineAlpha: CGFloat = 0.45
    private static let cornerRadius: CGFloat = 3.5
    private static let nubSize = NSSize(width: 1.6, height: 4.5)
    private static let nubGap: CGFloat = 0.8
    private static let fillInset: CGFloat = 2.0
    private static let templateFillAlpha: CGFloat = 0.28
    private static let coloredFillAlpha: CGFloat = 0.9
    /// Space left of the body and right of the nub so the strokes are not clipped.
    private static let edgeSlack: CGFloat = 0.5
    /// Digits on the bright red and green fills: dark in both appearances for contrast.
    private static let coloredNumeralInk = NSColor(white: 0.05, alpha: 1)
    /// The empty part of a colored icon in a dark appearance: a light plate, so the dark
    /// numerals stay readable over it as well as over the fill.
    private static let darkTrack = NSColor(white: 0.85, alpha: 0.9)
    /// The bolt as unit-square points, origin bottom-left.
    private static let boltPoints: [(CGFloat, CGFloat)] = [
        (0.72, 1), (0, 0.55), (0.44, 0.55), (0.28, 0), (1, 0.65), (0.54, 0.65)]
    private static let fontSize: CGFloat = 9
    private static let boltSize = NSSize(width: 4.5, height: 8)
    private static let boltGap: CGFloat = 1.5

    /// The icon's size when not charging; charging adds `boltSize.width + boltGap`.
    static let size = size(charging: false)

    static func size(charging: Bool) -> NSSize {
        NSSize(width: (charging ? boltSize.width + boltGap : 0) + bodyWidth + nubGap + nubSize.width + edgeSlack,
               height: height)
    }

    /// A template image when `role` is `.none` (it adapts to the menu bar); otherwise a
    /// colored one: red for `.low`, green for `.charging`. A colored image draws its outline
    /// and bolt in `ink`, and its numerals in near-black, which follows the appearance it is drawn in unless given.
    static func image(percent: Int, charging: Bool, role: MenuBarColorRole, ink: NSColor? = nil) -> NSImage {
        let percent = min(max(percent, 0), 100)
        let image = NSImage(size: size(charging: charging), flipped: false) { _ in
            draw(percent: percent, charging: charging, role: role, ink: ink)
            return true
        }
        image.isTemplate = role == .none
        return image
    }

    private static func draw(percent: Int, charging: Bool, role: MenuBarColorRole, ink custom: NSColor?) {
        let template = role == .none
        let ink: NSColor = template ? .black : custom ?? .labelColor
        let tint: NSColor = switch role {
        case .none: .black
        case .low: .systemRed
        case .charging: .systemGreen
        }
        let fillColor = template ? tint.withAlphaComponent(templateFillAlpha) : tint.withAlphaComponent(coloredFillAlpha)

        let bodyX = (charging ? boltSize.width + boltGap : 0) + edgeSlack
        let outer = NSRect(x: bodyX, y: 0, width: bodyWidth, height: height)

        // Level fill (a visible sliver above 0%), under the outline and numerals.
        let inner = outer.insetBy(dx: fillInset, dy: fillInset)
        let radius = cornerRadius - fillInset
        if !template, (ink.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0) > 0.5 {
            darkTrack.setFill()
            NSBezierPath(roundedRect: inner, xRadius: radius, yRadius: radius).fill()
        }
        if percent > 0 {
            let width = max(2, inner.width * CGFloat(percent) / 100)
            fillColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height),
                         xRadius: radius, yRadius: radius).fill()
        }

        // Outline and terminal nub, at the same translucency.
        let edge = ink.withAlphaComponent(outlineAlpha)
        edge.setStroke()
        let outline = NSBezierPath(
            roundedRect: outer.insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2),
            xRadius: cornerRadius - outlineWidth / 2, yRadius: cornerRadius - outlineWidth / 2)
        outline.lineWidth = outlineWidth
        outline.stroke()
        edge.setFill()
        NSBezierPath(roundedRect: NSRect(x: outer.maxX + nubGap, y: (height - nubSize.height) / 2,
                                         width: nubSize.width, height: nubSize.height),
                     xRadius: nubSize.width / 2, yRadius: nubSize.width / 2).fill()

        // Numerals, once, centered in the body.
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let numeralInk = template ? ink : coloredNumeralInk
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numeralInk]
        let text = "\(percent)" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: outer.midX - textSize.width / 2,
                              y: outer.midY - font.capHeight / 2 + font.descender),
                  withAttributes: attributes)

        if charging {
            (template ? NSColor.black : tint).setFill()
            bolt(at: NSPoint(x: 0, y: (height - boltSize.height) / 2), size: boltSize).fill()
        }
    }

    private static func bolt(at origin: NSPoint, size: NSSize) -> NSBezierPath {
        let path = NSBezierPath()
        for (i, p) in boltPoints.enumerated() {
            let point = NSPoint(x: origin.x + p.0 * size.width, y: origin.y + p.1 * size.height)
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }
}
