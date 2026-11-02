import SwiftUI
import BatteryCore

/// What the popover's buttons do; the status item controller supplies them.
struct PopoverActions {
    var openWindow: () -> Void
    var openReports: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}

struct PopoverView: View {
    let model: BatteryModel
    /// Not read yet; the top apps section (Task 5) uses it.
    let sampler: EnergySampler
    let actions: PopoverActions

    var body: some View {
        Group {
            if let reading = model.reading, let state = model.state {
                PopoverContent(
                    reading: reading, state: state,
                    liveWatts: model.liveWatts, fullCharge: model.fullCharge, actions: actions)
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
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(reading: reading, state: state)
            ChargeBar(reading: reading, state: state)
                .padding(.top, 10)
            TileGrid(tiles: tiles)
                .padding(.top, 12)
            Footer(actions: actions)
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
    let actions: PopoverActions
    /// Shared with MainWindow, so writing it here picks the pane the window opens on.
    @AppStorage("sidebarSelection") private var selection: SidebarItem = .overview

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                selection = .history
                actions.openWindow()
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

            Button {
                actions.quit()
            } label: {
                HStack {
                    Text("Quit Battery Meter")
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .padding(.top, 8)
        }
    }
}
