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
    let sampler: EnergySampler
    let actions: PopoverActions

    var body: some View {
        Group {
            if let reading = model.reading, let state = model.state {
                PopoverContent(
                    reading: reading, state: state, runtime: model.runtime,
                    // Read only when high use is flagged, so a new sample alone doesn't redraw.
                    highUseApps: model.runtime?.isHighUse == true ? sampler.freshTopApps(now: .now) : [],
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
    let runtime: RuntimeEstimate?
    let highUseApps: [String]
    let liveWatts: Double?
    let fullCharge: FullChargeEstimate?
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuntimeHeadline(reading: reading, state: state, runtime: runtime, highUseApps: highUseApps)
            TileGrid(tiles: tiles)
                .padding(.top, 16)
            Footer(actions: actions)
                .padding(.top, 16)
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

/// Window, Reports and Settings on the left, Quit on the right. Each button only calls
/// its action; which pane the window opens on is the controller's business.
private struct Footer: View {
    let actions: PopoverActions

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                FooterButton(title: "Open window", symbol: "macwindow", shortcut: "o", action: actions.openWindow)
                FooterButton(title: "Reports", symbol: "chart.bar.doc.horizontal", shortcut: nil, action: actions.openReports)
                FooterButton(title: "Settings", symbol: "gearshape", shortcut: ",", action: actions.openSettings)
                Spacer()
                FooterButton(title: "Quit Battery Meter", symbol: "power", shortcut: "q", action: actions.quit)
            }
        }
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let shortcut: KeyEquivalent?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .imageScale(.large)
        }
        // Borderless at rest, with the system's rounded highlight on hover and press.
        .buttonStyle(.accessoryBar)
        .help(helpText)
        .keyboardShortcut(shortcut.map { KeyboardShortcut($0) })
    }

    /// The tooltip names the shortcut, as a menu item would.
    private var helpText: String {
        guard let shortcut else { return title }
        return "\(title) (⌘\(String(shortcut.character).uppercased()))"
    }
}
