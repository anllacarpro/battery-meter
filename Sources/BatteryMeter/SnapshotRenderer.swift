#if DEBUG
import SwiftUI
import BatteryCore

/// Debug-only: `--render-snapshots <dir>` writes popover, empty-state and window PNGs in
/// light and dark, then exits. It reads the history file but never prunes or appends.
@MainActor
enum SnapshotRenderer {
    static var requestedDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(model: BatteryModel, to dir: URL) async {
        await model.loadHistory(pruning: false)
        model.refresh(record: false)
        // Synthetic history lives only in this in-memory model; its store points at
        // /dev/null and is never loaded from or written to.
        let sample = BatteryModel(store: HistoryStore(fileURL: URL(fileURLWithPath: "/dev/null")))
        sample.history = SampleHistory.readings()

        // Reads the login-item status only; never registers or sets didOfferLaunchAtLogin.
        let settings = SettingsState()
        let settingsWithNote = SettingsState()
        settingsWithNote.showSampleError("The operation couldn't be completed. Operation not permitted")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            write(PopoverView(model: model), scheme: scheme, to: dir.appending(path: "popover-\(suffix).png"))
            write(EmptyStateView().padding(16).frame(width: 300), scheme: scheme,
                  to: dir.appending(path: "empty-\(suffix).png"))
            for (name, item, source, state) in [
                ("overview", SidebarItem.overview, model, settings),
                ("history", .history, model, settings),
                ("health", .health, model, settings),
                ("history-sample", .history, sample, settings),
                ("settings", .settings, model, settings),
                ("settings-note", .settings, model, settingsWithNote),
            ] {
                await writeWindow(
                    MainSplitView(model: source, hover: ChartHover(), settings: state,
                                  selection: .constant(item)),
                    scheme: scheme, to: dir.appending(path: "window-\(name)-\(suffix).png"))
            }
        }
        exit(0)
    }

    private static func write(_ view: some View, scheme: ColorScheme, to url: URL) {
        // Stand-in for the menu bar window's own material background.
        let background = scheme == .light ? Color(white: 0.96) : Color(white: 0.17)
        let renderer = ImageRenderer(content: view
            .background(background)
            .environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// ImageRenderer can't draw AppKit-backed views (List, Form), so the window is hosted
    /// in a transparent NSWindow and captured with `cacheDisplay`.
    private static func writeWindow(_ view: some View, scheme: ColorScheme, to url: URL) async {
        let frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.frame = frame
        let window = NSWindow(
            contentRect: frame, styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = hosting
        // On screen but invisible: table-backed views only draw in an ordered-in window.
        window.alphaValue = 0
        window.ignoresMouseEvents = true  // the pointer must not drive chart hover
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Let SwiftUI and the split view settle before capturing.
        try? await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()

        guard let appearance = window.appearance,
              let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            // The window, not the hosting view, paints the background.
            NSColor.windowBackgroundColor.setFill()
            hosting.bounds.fill()
            draw(hosting, in: hosting)
            drawSidebar(of: hosting, scheme: scheme)
            NSGraphicsContext.restoreGraphicsState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Caches `view` on its own and draws it at its place in `root`, into the current context.
    private static func draw(_ view: NSView, in root: NSView) {
        guard let viewRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: viewRep)
        viewRep.draw(in: rect(of: view, in: root), from: .zero, operation: .sourceOver,
                     fraction: 1, respectFlipped: true, hints: nil)
    }

    /// `view`'s frame in `root`, in the bottom-left-origin space of a bitmap context.
    private static func rect(of view: NSView, in root: NSView) -> NSRect {
        var r = view.convert(view.bounds, to: root)
        if root.isFlipped { r.origin.y = root.bounds.height - r.maxY }
        return r
    }

    /// The sidebar sits in an NSGlassEffectView, which only the window server composites,
    /// so `cacheDisplay` leaves it blank. Draw a flat stand-in for the glass, a stand-in
    /// selection pill, then each row's content (in place, rows render with vibrancy, which
    /// also needs the glass).
    private static func drawSidebar(of root: NSView, scheme: ColorScheme) {
        guard let glass = firstSubview(NSGlassEffectView.self, in: root),
              let content = glass.contentView else { return }
        NSColor(white: scheme == .light ? 0.93 : 0.16, alpha: 1).setFill()
        rect(of: glass, in: root).fill()
        for row in allSubviews(NSTableRowView.self, in: content) {
            if row.isSelected {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: rect(of: row, in: root).insetBy(dx: 10, dy: 0),
                             xRadius: 8, yRadius: 8).fill()
            }
            for cell in row.subviews where !(cell is NSVisualEffectView) {
                draw(cell, in: root)
            }
        }
    }

    private static func allSubviews<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        view.subviews.flatMap { sub in (sub as? T).map { [$0] } ?? allSubviews(type, in: sub) }
    }

    private static func firstSubview<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        for sub in view.subviews {
            if let match = sub as? T ?? firstSubview(type, in: sub) { return match }
        }
        return nil
    }
}

/// About 90 days of synthetic readings: one plugged-in reading a day with health easing
/// from 100% to 98.5%, plus 8 discharge sessions whose hours per full charge slowly decline.
private enum SampleHistory {
    static func readings() -> [BatteryReading] {
        let design = 4629
        let days = 90
        let today = Calendar.current.startOfDay(for: .now)
        let jitter = [0.4, -0.3, 0.2, -0.5, 0.35, -0.1, 0.25, -0.2]
        var result: [BatteryReading] = []

        func reading(_ t: Date, percent: Int, health: Double, external: Bool) -> BatteryReading {
            BatteryReading(
                timestamp: t, percent: percent,
                remainingCapacity: Int(Double(design) * health / 100 * Double(percent) / 100),
                fullChargeCapacity: Int((Double(design) * health / 100).rounded()),
                designCapacity: design, cycleCount: 8, designCycleCount: 1000,
                voltage: 12_000, amperage: external ? 0 : -400,
                isCharging: false, externalConnected: external, fullyCharged: external)
        }

        for d in 0..<days {
            let dayStart = Calendar.current.date(byAdding: .day, value: d - days + 1, to: today)!
            let progress = Double(d) / Double(days - 1)
            let health = min(100, 100 - 1.5 * progress + 0.08 * sin(Double(d) * 1.7))
            result.append(reading(dayStart.addingTimeInterval(12 * 3600), percent: 100, health: health, external: true))

            // Sessions every ~11 days starting at 14:00, each using 60% of the battery.
            if d % 11 == 5 {
                let index = d / 11
                let hoursPerFull = 11.4 - 1.0 * progress + jitter[index % jitter.count]
                let duration = hoursPerFull * 0.6 * 3600
                let start = dayStart.addingTimeInterval(14 * 3600)
                var t: TimeInterval = 0
                while t <= duration {
                    let percent = 95 - Int((t / duration * 60).rounded())
                    result.append(reading(start.addingTimeInterval(t), percent: percent, health: health, external: false))
                    t += 60
                }
                result.append(reading(start.addingTimeInterval(duration + 60), percent: 35, health: health, external: true))
            }
        }
        return result
    }
}
#endif
