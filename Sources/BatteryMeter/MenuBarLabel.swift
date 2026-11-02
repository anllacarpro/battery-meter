import SwiftUI
import BatteryCore

struct MenuBarLabel: View {
    let model: BatteryModel
    // Task 8 adds the other formats; only "hours" exists for now.
    @AppStorage("menuBarFormat") private var menuBarFormat = "hours"

    var body: some View {
        if let reading = model.reading, let state = model.state {
            HStack(spacing: 4) {
                Image(systemName: Self.symbol(for: reading, state: state))
                Text(Self.text(for: reading, state: state))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "battery.0percent")
        }
    }

    static func symbol(for reading: BatteryReading, state: PowerState) -> String {
        switch state {
        case .charging: return "battery.100percent.bolt"
        case .pluggedIn: return "powerplug"
        case .onBattery: return levelSymbol(percent: reading.percent)
        }
    }

    static func levelSymbol(percent: Int) -> String {
        switch percent {
        case 88...: "battery.100percent"
        case 63..<88: "battery.75percent"
        case 38..<63: "battery.50percent"
        case 13..<38: "battery.25percent"
        default: "battery.0percent"
        }
    }

    static func text(for reading: BatteryReading, state: PowerState) -> String {
        switch state {
        case .onBattery(let timeLeft): timeLeft.map(DurationText.short) ?? "—"
        case .charging(let timeToFull): timeToFull.map(DurationText.short) ?? "\(reading.percent)%"
        case .pluggedIn: "\(reading.percent)%"
        }
    }
}
