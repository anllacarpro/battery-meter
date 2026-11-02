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
        return Tile(title: title, value: watts.formatted(.number.precision(.fractionLength(1))) + " W")
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

    /// Caption above the headline figure.
    static func headlineCaption(for state: PowerState) -> String {
        switch state {
        case .onBattery: "Left right now"
        case .charging: "Charging"
        case .pluggedIn: "Plugged in"
        }
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
            .animation(.default, value: fraction)
    }
}
