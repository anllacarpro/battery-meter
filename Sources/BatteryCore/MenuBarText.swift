import Foundation

/// What the menu bar label shows. Raw values are the `menuBarFormat` defaults values.
public enum MenuBarFormat: String, CaseIterable, Sendable {
    case hours, percent, both
}

public enum MenuBarText {
    /// The label text for `state`. Without hours (plugged in, or draw too low to estimate)
    /// every format shows the hours-format text.
    public static func text(state: PowerState, percent: Int, format: MenuBarFormat) -> String {
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
        switch format {
        case .hours: return hoursText
        case .percent: return "\(percent)%"
        case .both: return "\(hoursText) · \(percent)%"
        }
    }
}
