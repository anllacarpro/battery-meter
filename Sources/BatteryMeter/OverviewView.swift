import SwiftUI
import BatteryCore

struct OverviewView: View {
    let model: BatteryModel

    var body: some View {
        if let reading = model.reading, let state = model.state {
            ScrollView {
                OverviewContent(
                    reading: reading, state: state, fullCharge: model.fullCharge,
                    liveWatts: model.liveWatts, liveVolts: model.liveVolts, liveAmps: model.liveAmps)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
            }
        } else {
            EmptyStateView()
                .frame(maxHeight: .infinity)
        }
    }
}

private struct OverviewContent: View {
    let reading: BatteryReading
    let state: PowerState
    let fullCharge: FullChargeEstimate?
    let liveWatts: Double?
    let liveVolts: Double?
    let liveAmps: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Overview")
            HStack(alignment: .top, spacing: 48) {
                BigFigure(
                    caption: BatteryFormat.headlineCaption(for: state),
                    value: MenuBarText.text(state: state, percent: reading.percent, format: .hours))
                if let fullCharge {
                    BigFigure(
                        caption: "Per full charge",
                        value: DurationText.short(fullCharge.hours * 3600),
                        note: fullCharge.isEstimate ? "estimate" : nil)
                }
            }
            .padding(.top, 16)
            ChargeBar(reading: reading, state: state)
                .padding(.top, 14)
            TileSection(title: "Battery", tiles: [
                BatteryTiles.health(reading),
                BatteryTiles.cycles(reading),
            ])
            .padding(.top, 24)
            let live = [
                BatteryTiles.power(state: state, watts: liveWatts),
                BatteryTiles.voltage(liveVolts),
                BatteryTiles.amperage(liveAmps),
            ].compactMap { $0 }
            if !live.isEmpty {
                TileSection(title: "Right now", tiles: live)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BigFigure: View {
    let caption: String
    let value: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.default, value: value)
                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TileSection: View {
    let title: String
    let tiles: [Tile]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(tiles) { tile in
                    StatTile(title: tile.title, value: tile.value, caption: tile.caption)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
