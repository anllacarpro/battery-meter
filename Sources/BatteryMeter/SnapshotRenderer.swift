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

    static func run(model: BatteryModel, reports: ReportsModel, sampler: EnergySampler, to dir: URL) async {
        await model.loadHistory(pruning: false)
        model.refresh(record: false)
        // Synthetic history lives only in this in-memory model; its store points at
        // /dev/null and is never loaded from or written to.
        let sample = BatteryModel(store: HistoryStore(fileURL: URL(fileURLWithPath: "/dev/null")))
        sample.history = SampleHistory.readings()

        // The real report: built from the loaded history, the read-only `pmset -g log` and a
        // load of the app-energy file (none of which writes). Awaited here so the capture
        // doesn't race the background build; the panes' own refresh is then throttled.
        reports.refresh(force: true)
        for _ in 0..<150 where reports.report == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // The synthetic report is injected, never built: its collectors are inert and
        // `showSnapshot` keeps `refresh()` from running them.
        let sampleReports = ReportsModel(
            battery: sample, energyStore: AppEnergyStore(fileURL: URL(fileURLWithPath: "/dev/null")),
            logSource: PowerLogSource())
        sampleReports.showSnapshot(SampleReport.make(history: sample.history))
        // Review-only: the same sample with an unreadable sleep log.
        let noLogReports = ReportsModel(
            battery: sample, energyStore: AppEnergyStore(fileURL: URL(fileURLWithPath: "/dev/null")),
            logSource: PowerLogSource())
        noLogReports.showSnapshot(SampleReport.make(history: sample.history, sleepLog: false))

        // In-memory battery states with the runtime fields set directly, so these renders
        // never depend on the real typical-draw compute (which races in snapshot mode).
        let highUse = SampleBattery.highUse()
        let estimate = SampleBattery.estimate()
        let charging = SampleBattery.charging()
        let highUseSampler = EnergySampler(
            battery: highUse, store: AppEnergyStore(fileURL: URL(fileURLWithPath: "/dev/null")))
        highUseSampler.showSnapshot(topApps: ["iPhone Mirroring", "rapportd"], date: .now)
        let idleSampler = EnergySampler(
            battery: estimate, store: AppEnergyStore(fileURL: URL(fileURLWithPath: "/dev/null")))

        // Reads the login-item status only; never registers or sets didOfferLaunchAtLogin.
        let settings = SettingsState()
        let settingsWithNote = SettingsState()
        settingsWithNote.showSampleError("The operation couldn't be completed. Operation not permitted")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            for (name, source, energy) in [
                ("popover", model, sampler),
                ("popover-high-use", highUse, highUseSampler),
                ("popover-estimate", estimate, idleSampler),
                ("popover-charging", charging, idleSampler),
            ] {
                write(PopoverView(model: source, sampler: energy, actions: .inert), scheme: scheme,
                      to: dir.appending(path: "\(name)-\(suffix).png"))
            }
            // Review-only: hosted in a window, so AppKit-backed controls (the footer's
            // accessory-bar buttons) draw as they do live.
            await writeWindow(PopoverView(model: highUse, sampler: highUseSampler, actions: .inert),
                              width: 300, height: 380, scheme: scheme,
                              to: dir.appending(path: "popover-high-use-hosted-\(suffix).png"))
            write(MenuBarIconSheet(), scheme: scheme, to: dir.appending(path: "menubar-icons-\(suffix).png"))
            write(NativeIconSheet(), scheme: scheme, to: dir.appending(path: "menubar-icons-native-\(suffix).png"))
            write(EmptyStateView().padding(16).frame(width: 300), scheme: scheme,
                  to: dir.appending(path: "empty-\(suffix).png"))
            for (name, item, source, report, state, height) in [
                ("overview", SidebarItem.overview, model, reports, settings, 520.0),
                ("overview-high-use", .overview, highUse, sampleReports, settings, 620),
                ("overview-estimate", .overview, estimate, sampleReports, settings, 620),
                ("overview-charging", .overview, charging, sampleReports, settings, 620),
                ("reports", .reports, model, reports, settings, 520),
                ("reports-sample", .reports, sample, sampleReports, settings, 520),
                // Review-only: the whole pane, to check every section.
                ("reports-tall", .reports, model, reports, settings, 1700),
                ("reports-sample-tall", .reports, sample, sampleReports, settings, 2000),
                ("reports-sample-nolog-tall", .reports, sample, noLogReports, settings, 2000),
                ("overview-sample", .overview, model, sampleReports, settings, 620),
                ("overview-sample-nolog", .overview, model, noLogReports, settings, 620),
                ("history", .history, model, reports, settings, 520),
                ("health", .health, model, reports, settings, 520),
                ("history-sample", .history, sample, reports, settings, 520),
                ("settings", .settings, model, reports, settings, 520),
                ("settings-menubar", .settings, model, reports, settings, 640),
                ("settings-note", .settings, model, reports, settingsWithNote, 520),
            ] {
                await writeWindow(
                    MainSplitView(model: source, reports: report, hover: ChartHover(), settings: state,
                                  selection: .constant(item)),
                    height: height, scheme: scheme, to: dir.appending(path: "window-\(name)-\(suffix).png"))
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
    private static func writeWindow(
        _ view: some View, width: CGFloat = 760, height: CGFloat, scheme: ColorScheme, to url: URL
    ) async {
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
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

/// Review-only: the percentage-inside icon at each level, template and colored, charging
/// or not. Large (4x) to check the numerals, then at real size on a menu-bar-like strip.
private struct MenuBarIconSheet: View {
    private static let levels = [100, 85, 50, 20, 8, 5]
    private static let rows: [(String, Bool, MenuBarColorRole)] = [
        ("Template", false, .none), ("Red", false, .low),
        ("Template, charging", true, .none), ("Green, charging", true, .charging),
    ]

    @Environment(\.colorScheme) private var scheme
    private var ink: NSColor { scheme == .dark ? .white : .black }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.0).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        ForEach(Self.levels, id: \.self) { level in
                            Image(nsImage: BatteryIconRenderer.image(percent: level, charging: row.1, role: row.2, ink: ink))
                                .resizable()
                                .frame(width: BatteryIconRenderer.size(charging: row.1).width * 4,
                                       height: BatteryIconRenderer.size.height * 4)
                        }
                    }
                }
            }
            Text("Real size").font(.caption).foregroundStyle(.secondary)
            ForEach(Self.rows, id: \.0) { row in
                HStack(spacing: 10) {
                    ForEach(Self.levels, id: \.self) { level in
                        Image(nsImage: BatteryIconRenderer.image(percent: level, charging: row.1, role: row.2, ink: ink))
                    }
                }
            }
            Text("Preview strips").font(.caption).foregroundStyle(.secondary)
            HStack {
                MenuBarPreview(style: .standard, source: PreviewSource(percent: 75, state: .onBattery(timeLeft: 19_800), watts: 12.4))
                MenuBarPreview(
                    style: MenuBarStyle(icon: .percentInside, format: .hours, colors: .lowOnly, lowThreshold: 10, timeStyle: .clock),
                    source: PreviewSource(percent: 75, state: .onBattery(timeLeft: 19_800), watts: 12.4))
                MenuBarPreview(
                    style: MenuBarStyle(icon: .percentInside, format: .watts, colors: .lowAndCharging, lowThreshold: 10, timeStyle: .clock),
                    source: PreviewSource(percent: 60, state: .charging(timeToFull: 1800), watts: 38.4))
            }
        }
        .padding(16)
    }
}

/// Review-only: the native battery symbol above the custom icon at the same height, at 4x
/// and at real size, in each variant.
private struct NativeIconSheet: View {
    private static let levels: [(percent: Int, symbol: String)] = [
        (100, "battery.100percent"), (85, "battery.75percent"), (50, "battery.50percent"),
        (20, "battery.25percent"), (8, "battery.0percent"), (5, "battery.0percent"),
    ]
    private static let rows: [(String, Bool, MenuBarColorRole)] = [
        ("Template", false, .none), ("Red", false, .low),
        ("Template, charging", true, .none), ("Green, charging", true, .charging),
    ]

    @Environment(\.colorScheme) private var scheme
    private var ink: NSColor { scheme == .dark ? .white : .black }

    private func native(_ symbol: String, charging: Bool, role: MenuBarColorRole) -> NSImage {
        let name = charging ? symbol + ".bolt" : symbol
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// A bitmap of `image` drawn at `scale` times its size and 2x again in pixels, so the 4x
    /// views are sharp rather than an upscaled 1x raster. Keeps the template flag.
    private func sharp(_ image: NSImage, scale: CGFloat) -> NSImage {
        guard scale > 1 else { return image }
        let pixels = 2 * scale
        let width = Int((image.size.width * pixels).rounded()), height = Int((image.size.height * pixels).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: NSSize(width: image.size.width * scale, height: image.size.height * scale))
        result.addRepresentation(rep)
        result.isTemplate = image.isTemplate
        return result
    }

    private func column(_ level: (percent: Int, symbol: String), _ row: (String, Bool, MenuBarColorRole),
                        scale: CGFloat) -> some View {
        let mine = sharp(BatteryIconRenderer.image(percent: level.percent, charging: row.1, role: row.2, ink: ink), scale: scale)
        let theirs = sharp(native(level.symbol, charging: row.1, role: row.2), scale: scale)
        let box = NSSize(width: BatteryIconRenderer.size(charging: row.1).width * scale,
                         height: BatteryIconRenderer.size.height * scale)
        return VStack(alignment: .leading, spacing: scale > 1 ? 6 : 3) {
            Image(nsImage: theirs).resizable().scaledToFit()
                .frame(width: theirs.size.width, height: theirs.size.height)
                .foregroundStyle(row.2.color ?? .primary)
                .frame(width: box.width, height: box.height, alignment: .leading)
            Image(nsImage: mine).resizable()
                .frame(width: mine.size.width, height: mine.size.height)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Native above, custom below, 4x").font(.caption).foregroundStyle(.secondary)
            ForEach(Self.rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.0).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        ForEach(Self.levels, id: \.percent) { column($0, row, scale: 4) }
                    }
                }
            }
            Text("Real size, native above, custom below").font(.caption).foregroundStyle(.secondary)
            ForEach(Self.rows, id: \.0) { row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Self.levels, id: \.percent) { column($0, row, scale: 1) }
                }
            }
        }
        .padding(16)
    }
}

private extension PopoverActions {
    /// Snapshots never click.
    static var inert: PopoverActions { PopoverActions(openWindow: {}, openReports: {}, openSettings: {}, quit: {}) }
}

/// Battery states for the headline renders. Each model's store points at /dev/null and
/// it is never started, so it reads nothing and writes nothing.
@MainActor
private enum SampleBattery {
    private static let hour: TimeInterval = 3600

    /// 75%, 26.6 W against a typical 6.7 W: the high-use case.
    static func highUse() -> BatteryModel {
        let model = make(percent: 75, amperage: -2217, external: false, charging: false)
        model.state = .onBattery(timeLeft: 5.5 * hour)
        model.runtime = RuntimeEstimate(
            headline: 5.5 * hour, atPace: 1.5 * hour, paceWatts: 26.6,
            typicalWatts: 6.7, isEstimate: false, isHighUse: true)
        model.typicalWatts = 6.7
        model.liveWatts = 26.6
        model.liveVolts = 12.0
        model.liveAmps = -2.22
        model.fullCharge = FullChargeEstimate(hours: 8.5, isEstimate: false)
        return model
    }

    /// No typical draw yet: the headline is a first guess and "Per full charge" is hidden.
    static func estimate() -> BatteryModel {
        let model = make(percent: 75, amperage: -767, external: false, charging: false)
        model.state = .onBattery(timeLeft: 4.75 * hour)
        model.runtime = RuntimeEstimate(
            headline: 4.75 * hour, atPace: 4.25 * hour, paceWatts: 9.2,
            typicalWatts: nil, isEstimate: true, isHighUse: false)
        model.liveWatts = 9.2
        model.liveVolts = 12.0
        model.liveAmps = -0.77
        return model
    }

    static func charging() -> BatteryModel {
        let model = make(percent: 80, amperage: 3200, external: true, charging: true)
        model.state = .charging(timeToFull: 70 * 60)
        model.liveWatts = 38.4
        model.liveVolts = 12.0
        model.liveAmps = 3.2
        model.fullCharge = FullChargeEstimate(hours: 8.5, isEstimate: false)
        return model
    }

    /// Health 98.6% of a 4629 mAh design, 8 of 1000 cycles, 12 V.
    private static func make(percent: Int, amperage: Int, external: Bool, charging: Bool) -> BatteryModel {
        let model = BatteryModel(
            store: HistoryStore(fileURL: URL(fileURLWithPath: "/dev/null")),
            energyStore: AppEnergyStore(fileURL: URL(fileURLWithPath: "/dev/null")))
        let full = Int((4629 * 0.986).rounded())
        model.reading = BatteryReading(
            timestamp: .now, percent: percent, remainingCapacity: full * percent / 100,
            fullChargeCapacity: full, designCapacity: 4629, cycleCount: 8, designCycleCount: 1000,
            voltage: 12_000, amperage: amperage, isCharging: charging,
            externalConnected: external, fullyCharged: false)
        return model
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

/// A rich in-memory report: a week of usage, 12 sessions, charging stats, a few sleep
/// periods and 8 apps. The health trend is built from the sample history so the sentence
/// matches the chart drawn from that same history.
private enum SampleReport {
    static func make(history: [BatteryReading], sleepLog: Bool = true) -> BatteryReport {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let hour: TimeInterval = 3600

        let dayHours = [3.2, 5.1, 0, 4.4, 6.3, 2.4, 1.6]
        let days = dayHours.enumerated().map { i, h in
            UsagePeriod(start: cal.date(byAdding: .day, value: i - 6, to: today)!,
                        batteryTime: h * hour, percentUsed: Int(h * 9.5),
                        averageWatts: h > 0 ? 6.2 + Double(i % 3) * 0.7 : nil)
        }
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)!.start
        let weekHours = [18.5, 22.0, 15.75, 9.5]
        let weeks = weekHours.enumerated().map { i, h in
            UsagePeriod(start: cal.date(byAdding: .weekOfYear, value: i - 3, to: thisWeek)!,
                        batteryTime: h * hour, percentUsed: Int(h * 9.1), averageWatts: 6.4 + Double(i) * 0.3)
        }

        let sessions = (0..<12).map { i in
            let start = today.addingTimeInterval(-Double(i) * 1.6 * 86_400 + (9 + Double(i % 4) * 2.5) * hour)
            let drop = [42, 28, 61, 17, 35, 54, 22, 47, 31, 66, 19, 38][i]
            let perFull = 10.6 + [0.4, -0.3, 0.2, -0.6, 0.5, -0.1, 0.3, -0.4, 0.1, -0.2, 0.6, -0.5][i]
            return DischargeSession(start: start, end: start.addingTimeInterval(perFull * Double(drop) / 100 * hour),
                                    percentDrop: drop, hoursPerFullCharge: perFull)
        }

        let charging = ChargingReport(
            chargeCount: 11, typicalPlugInPercent: 34, typicalUnplugPercent: 96,
            averageDailyTimeAtFull: 2.6 * hour, timeAtFullDays: 7, cyclesPerWeek: 2.8, usualChargerWatts: 70)

        let periods = [(1, 23.2, 8.1, 3, 2), (2, 22.5, 7.4, 2, 1), (3, 13.0, 2.2, 1, 0),
                       (4, 23.8, 9.0, 4, 3), (5, 0.4, 7.9, 3, 1)].map { d, from, length, lost, dark in
            let start = cal.date(byAdding: .day, value: -d, to: today)!.addingTimeInterval(from * hour)
            return SleepPeriod(start: start, end: start.addingTimeInterval(length * hour),
                               percentLost: lost, darkWakes: dark)
        }
        let sleep = SleepReport(
            periods: periods, percentPerHour: 13.0 / 34.6,
            wakeReasons: [WakeReasonCount(reason: .lid, count: 9), WakeReasonCount(reason: .userInput, count: 4),
                          WakeReasonCount(reason: .network, count: 3), WakeReasonCount(reason: .scheduled, count: 2),
                          WakeReasonCount(reason: .powerButton, count: 1)])

        let apps = [("Safari", 0.31), ("Xcode Previews Helper with a long name", 0.18), ("WhatsApp", 0.14),
                    ("Mail", 0.11), ("Music", 0.09), ("Finder", 0.07), ("Messages", 0.06), ("Terminal", 0.004)]
            .map { AppShare(name: $0.0, share: $0.1) }

        let points = DailyHealth.points(in: history)
        return BatteryReport(
            generated: now, usage: UsageReport(days: days, weeks: weeks), sessions: sessions,
            charging: charging, health: HealthTrend.build(points: points), healthPoints: points,
            sleep: sleepLog ? sleep : nil, apps: apps)
    }
}
#endif
