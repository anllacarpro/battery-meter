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
        [
            BatteryTiles.fullCharge(fullCharge),
            BatteryTiles.health(reading),
            BatteryTiles.cycles(reading),
            BatteryTiles.power(state: state, watts: liveWatts),
        ].compactMap { $0 }
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

    private var caption: String { BatteryFormat.headlineCaption(for: state) }

    private var bigText: String { MenuBarText.text(state: state, percent: reading.percent, format: .hours) }
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
