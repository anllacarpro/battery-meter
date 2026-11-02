import SwiftUI
import BatteryCore

/// One stat tile's content, shared by the popover and the window's Overview.
struct Tile: Identifiable {
    var title: String
    var value: String
    var caption: String? = nil
    var id: String { title }
}

/// Tile builders shared by every surface. A builder returns nil when the hardware
/// doesn't provide the value, so the tile is hidden rather than showing "0".
enum BatteryTiles {
    static func fullCharge(_ estimate: FullChargeEstimate?) -> Tile? {
        estimate.map {
            Tile(title: "Per full charge", value: DurationText.short($0.hours * 3600),
                 caption: $0.isEstimate ? "estimate" : nil)
        }
    }

    static func health(_ reading: BatteryReading) -> Tile {
        Tile(title: "Health", value: BatteryFormat.percent(reading.healthPercent))
    }

    static func cycles(_ reading: BatteryReading) -> Tile {
        Tile(title: "Cycles", value: BatteryFormat.cycles(reading))
    }

    /// Battery draw while on battery, charge rate while charging; hidden when the
    /// adapter powers the Mac and the battery is idle.
    static func power(state: PowerState, watts: Double?) -> Tile? {
        guard let watts else { return nil }
        let title: String
        switch state {
        case .onBattery: title = "Power draw"
        case .charging: title = "Charging at"
        case .pluggedIn: return nil
        }
        return Tile(title: title, value: BatteryFormat.watts(watts))
    }

    static func voltage(_ volts: Double?) -> Tile? {
        volts.map { Tile(title: "Voltage", value: $0.formatted(.number.precision(.fractionLength(2))) + " V") }
    }

    static func amperage(_ amps: Double?) -> Tile? {
        amps.map { Tile(title: "Amperage", value: BatteryFormat.signed($0, digits: 2) + " A") }
    }
}

enum BatteryFormat {
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    static func cycles(_ reading: BatteryReading) -> String {
        reading.designCycleCount.map { "\(reading.cycleCount) of \($0.formatted())" }
            ?? reading.cycleCount.formatted()
    }

    /// Uses a true minus sign so negative values line up with positive ones.
    static func signed(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
            .replacingOccurrences(of: "-", with: "\u{2212}")
    }

    static func watts(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " W"
    }

    /// Caption above the headline figure.
    static func headlineCaption(for state: PowerState) -> String {
        switch state {
        case .onBattery(let timeLeft): timeLeft == nil ? "Estimating…" : "Estimated left"
        case .charging: "Charging"
        case .pluggedIn: "Plugged in"
        }
    }
}

/// The headline block shared by the popover and the Overview: caption, big figure,
/// charge bar and, on battery, the at-this-pace row and the high-use line. Charging and
/// plugged in show only the caption, figure and bar.
struct RuntimeHeadline: View {
    let reading: BatteryReading
    let state: PowerState
    let runtime: RuntimeEstimate?
    /// Fresh top apps; the high-use line shows only when non-empty and `isHighUse`.
    var highUseApps: [String] = []

    var body: some View {
        let figure = MenuBarText.text(state: state, percent: reading.percent, format: .hours)
        VStack(alignment: .leading, spacing: 0) {
            HeadlineFigure(
                caption: BatteryFormat.headlineCaption(for: state),
                value: figure,
                isEstimate: timeLeft != nil && runtime?.isEstimate == true)
            ChargeBar(reading: reading, state: state)
                .padding(.top, 8)
            if isOnBattery, let runtime, let atPace = runtime.atPace, let watts = runtime.paceWatts {
                // The duration is dropped when it would only repeat the headline.
                let duration = DurationText.short(atPace)
                PaceRow(duration: timeLeft != nil && duration == figure ? nil : duration, watts: watts)
                    .padding(.top, 12)
                if runtime.isHighUse, !highUseApps.isEmpty {
                    HighUseLine(apps: highUseApps)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var isOnBattery: Bool {
        if case .onBattery = state { true } else { false }
    }

    /// The headline's time left on battery; nil off battery or while estimating.
    private var timeLeft: TimeInterval? {
        if case .onBattery(let timeLeft) = state { timeLeft } else { nil }
    }
}

private struct HeadlineFigure: View {
    let caption: String
    let value: String
    let isEstimate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if isEstimate {
                    EstimateTag()
                }
            }
            // Fixed, so the tag appearing or going never shifts the figure below.
            .frame(height: 16)
            Text(value)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .modifier(ReduceMotionAnimation(value: value))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A quiet capsule saying the figure is a first guess.
private struct EstimateTag: View {
    var body: some View {
        Text("estimate")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
    }
}

private struct PaceRow: View {
    let duration: String?
    let watts: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("At this pace")
            Spacer(minLength: 8)
            Text(duration.map { "\($0) · \(BatteryFormat.watts(watts))" } ?? BatteryFormat.watts(watts))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct HighUseLine: View {
    let apps: [String]

    var body: some View {
        let names = apps.joined(separator: ", ")
        Label {
            Text("High use: \(names)")
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: "bolt.fill")
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .help("High use: \(names)")
    }
}

struct TileGrid: View {
    let tiles: [Tile]
    var columns = 2
    var fill = AnyShapeStyle(.regularMaterial)

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { tile in
                        StatTile(title: tile.title, value: tile.value, caption: tile.caption, fill: fill)
                    }
                    ForEach(row.count..<columns, id: \.self) { _ in
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private var rows: [[Tile]] {
        stride(from: 0, to: tiles.count, by: columns).map {
            Array(tiles[$0..<min($0 + columns, tiles.count)])
        }
    }
}

struct ChargeBar: View {
    let reading: BatteryReading
    let state: PowerState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(min(max(reading.percent, 0), 100)), total: 100)
                .progressViewStyle(CapsuleProgressStyle())
                .tint(reading.percent <= 20 ? .yellow : .green)
            Text("\(reading.percent)% · \(source)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var source: String {
        switch state {
        case .onBattery: "on battery"
        case .charging: "charging"
        case .pluggedIn: "plugged in"
        }
    }
}

private struct CapsuleProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(.capsule)
            .frame(height: 8)
            .modifier(ReduceMotionAnimation(value: fraction))
    }
}

/// `.default` animation for `value`, or none with Reduce Motion on.
private struct ReduceMotionAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .default, value: value)
    }
}
