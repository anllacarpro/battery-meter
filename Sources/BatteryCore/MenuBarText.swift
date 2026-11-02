import Foundation

/// What the menu bar label shows. Raw values are the `menuBarFormat` defaults values.
public enum MenuBarFormat: String, CaseIterable, Sendable {
    case hours, percent, both
}

public enum MenuBarText {
    /// The label text for `state`. `.percent` always shows the percent. Without hours
    /// (plugged in, or draw too low to estimate) `.hours` and `.both` show the
    /// hours-format fallback: "—" on battery, otherwise the percent.
    public static func text(state: PowerState, percent: Int, format: MenuBarFormat) -> String {
        if format == .percent { return "\(percent)%" }
        let hours: TimeInterval?
        let fallback: String
        switch state {
        case .onBattery(let timeLeft):
            hours = timeLeft
            fallback = "—"
        case .charging(let timeToFull):
            hours = timeToFull
            fallback = "\(percent)%"
        case .pluggedIn:
            hours = nil
            fallback = "\(percent)%"
        }
        guard let hours else { return fallback }
        let hoursText = DurationText.short(hours)
        return format == .both ? "\(hoursText) · \(percent)%" : hoursText
    }
}
