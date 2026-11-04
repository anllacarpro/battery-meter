#!/usr/bin/env swift
// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (re-run after changing the drawing; commit the .icns)
import AppKit

let canvas: CGFloat = 1024

func draw() {
    let ctx = NSGraphicsContext.current!.cgContext
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: a)
    }
    func gradient(_ stops: [(NSColor, CGFloat)]) -> NSGradient {
        NSGradient(colors: stops.map(\.0), atLocations: stops.map(\.1), colorSpace: .sRGB)!
    }

    // Tile: the standard macOS icon grid (824 pt body inside a 1024 canvas).
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    color(0x0B1F24).setFill()
    tilePath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    tilePath.addClip()
    gradient([(color(0x15383F), 0), (color(0x0A1A1F), 1)]).draw(in: tile, angle: -90)
    // Soft glow behind the battery.
    gradient([(color(0x34D399, 0.28), 0), (color(0x34D399, 0), 1)])
        .draw(fromCenter: NSPoint(x: 512, y: 500), radius: 0, toCenter: NSPoint(x: 512, y: 500), radius: 420, options: [])

    // Battery body.
    let body = NSRect(x: 196, y: 372, width: 600, height: 280)
    let nub = NSRect(x: 796 + 14, y: 462, width: 38, height: 100)
    let outline = NSBezierPath(roundedRect: body, xRadius: 84, yRadius: 84)

    // Nub.
    color(0xFFFFFF, 0.55).setFill()
    NSBezierPath(roundedRect: nub, xRadius: 19, yRadius: 19).fill()

    // Glass body.
    color(0xFFFFFF, 0.07).setFill()
    outline.fill()

    // Level fill: 78%, inset, clipped to the body's inner shape.
    let inset: CGFloat = 26
    let inner = body.insetBy(dx: inset, dy: inset)
    let level = NSRect(x: inner.minX, y: inner.minY, width: inner.width * 0.78, height: inner.height)
    ctx.saveGState()
    NSBezierPath(roundedRect: inner, xRadius: 58, yRadius: 58).addClip()
    gradient([(color(0x6EE7B7), 0), (color(0x10B981), 1)]).draw(in: level, angle: -90)
    // Top sheen.
    gradient([(color(0xFFFFFF, 0.32), 0), (color(0xFFFFFF, 0), 1)])
        .draw(in: NSRect(x: level.minX, y: level.midY, width: level.width, height: level.height / 2), angle: -90)
    ctx.restoreGState()

    // Outline.
    color(0xFFFFFF, 0.6).setStroke()
    outline.lineWidth = 14
    outline.stroke()

    // Gauge ticks under the battery: the "meter".
    for i in 0...10 {
        let major = i % 5 == 0
        let w: CGFloat = major ? 10 : 6
        let h: CGFloat = major ? 46 : 28
        let x = body.minX + 58 + CGFloat(i) * (body.width - 116) / 10
        let lit = Double(i) / 10 <= 0.78
        (lit ? color(0x6EE7B7, 0.95) : color(0xFFFFFF, 0.28)).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: 262, width: w, height: h), xRadius: w / 2, yRadius: w / 2).fill()
    }
    ctx.restoreGState()

    // Rim light.
    ctx.saveGState()
    tilePath.addClip()
    color(0xFFFFFF, 0.14).setStroke()
    tilePath.lineWidth = 4
    tilePath.stroke()
    ctx.restoreGState()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    g.cgContext.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    g.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(pixels: base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(pixels: base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", set.path, "-o", out.path]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
