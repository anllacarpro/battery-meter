import SwiftUI
import BatteryCore

struct PopoverView: View {
    let model: BatteryModel

    var body: some View {
        Group {
            if let reading = model.reading, let state = model.state {
                PopoverContent(
                    reading: reading, state: state,
                    liveWatts: model.liveWatts, fullCharge: model.fullCharge)
            } else {
                EmptyStateView()
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

private struct PopoverContent: View {
    let reading: BatteryReading
    let state: PowerState
    let liveWatts: Double?
    let fullCharge: FullChargeEstimate?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(reading: reading, state: state)
            ChargeBar(reading: reading, state: state)
                .padding(.top, 10)
            TileGrid(tiles: tiles)
                .padding(.top, 12)
            Footer()
                .padding(.top, 12)
        }
    }

    private var tiles: [Tile] {
        var result: [Tile] = []
        if let fullCharge {
            result.append(Tile(
                title: "Per full charge",
                value: DurationText.short(fullCharge.hours * 3600),
                caption: fullCharge.isEstimate ? "estimate" : nil))
        }
        result.append(Tile(
            title: "Health",
            value: reading.healthPercent.formatted(.number.precision(.fractionLength(1))) + "%"))
        result.append(Tile(
            title: "Cycles",
            value: reading.designCycleCount.map { "\(reading.cycleCount) of \($0)" }
                ?? "\(reading.cycleCount)"))
        if let liveWatts {
            result.append(Tile(
                title: "Power draw",
                value: liveWatts.formatted(.number.precision(.fractionLength(1))) + " W"))
        }
        return result
    }
}

private struct Header: View {
    let reading: BatteryReading
    let state: PowerState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(bigText)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: bigText)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        switch state {
        case .onBattery: "Left right now"
        case .charging: "Charging"
        case .pluggedIn: "Plugged in"
        }
    }

    private var bigText: String { MenuBarLabel.text(for: reading, state: state) }
}

private struct ChargeBar: View {
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

private struct Tile: Identifiable {
    var title: String
    var value: String
    var caption: String? = nil
    var id: String { title }
}

private struct TileGrid: View {
    let tiles: [Tile]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { tile in
                        StatTile(title: tile.title, value: tile.value, caption: tile.caption)
                    }
                    if row.count == 1 {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private var rows: [[Tile]] {
        stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
    }
}

private struct Footer: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                NSApp.activate()
                openWindow(id: "main")
            } label: {
                HStack {
                    Text("Open history…")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.tint)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }
}
