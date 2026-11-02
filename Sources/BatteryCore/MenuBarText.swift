import Foundation

/// What the menu bar label shows. Raw values are the `menuBarFormat` defaults values.
public enum MenuBarFormat: String, CaseIterable, Sendable {
    case hours, percent, both, watts, none
}

public enum MenuBarText {
    /// The label text for `state`. `.percent` always shows the percent. Without hours
    /// (plugged in, or draw too low to estimate) `.hours` and `.both` show the
    /// hours-format fallback: "—" on battery, otherwise the percent.
    /// `.watts` shows the live draw ("26.6 W", "—" when unknown); `.none` is empty.
    /// `timeStyle` applies to the hours formats.
    public static func text(
        state: PowerState, percent: Int, format: MenuBarFormat,
        timeStyle: MenuBarTimeStyle = .hoursMinutes, watts: Double? = nil
    ) -> String {
        switch format {
        case .none: return ""
        case .percent: return "\(percent)%"
        case .watts: return watts.map { String(format: "%.1f W", $0) } ?? "—"
        case .hours, .both: break
        }
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
        let hoursText = timeStyle == .clock ? DurationText.clock(hours) : DurationText.short(hours)
        return format == .both ? "\(hoursText) · \(percent)%" : hoursText
    }
}
