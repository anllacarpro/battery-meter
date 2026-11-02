import Foundation

/// Pure rules for how the menu bar item looks and what VoiceOver reads.
public enum MenuBarAppearance {
    public static func symbolName(percent: Int, state: PowerState) -> String {
        switch state {
        case .charging: return "battery.100percent.bolt"
        case .pluggedIn: return "powerplug"
        case .onBattery:
            switch percent {
            case 88...: return "battery.100percent"
            case 63..<88: return "battery.75percent"
            case 38..<63: return "battery.50percent"
            case 13..<38: return "battery.25percent"
            default: return "battery.0percent"
            }
        }
    }

    /// Low means on battery at 10% or less.
    public static func isLow(percent: Int, state: PowerState) -> Bool {
        if case .onBattery = state { return percent <= 10 }
        return false
    }

    public static func accessibilityLabel(percent: Int, state: PowerState) -> String {
        let base = "Battery \(percent) percent"
        switch state {
        case .onBattery(let timeLeft):
            guard let timeLeft else { return "\(base), on battery" }
            return "\(base), about \(spelledDuration(timeLeft)) left"
        case .charging(let timeToFull):
            guard let timeToFull else { return "\(base), charging" }
            return "\(base), charging, \(spelledDuration(timeToFull)) to full"
        case .pluggedIn:
            return "\(base), plugged in"
        }
    }

    /// Spelled-out duration rounded to 5 minutes and capped at 99 hours:
    /// "1 hour 10 minutes", "2 hours", "30 minutes", "less than 5 minutes".
    static func spelledDuration(_ seconds: TimeInterval) -> String {
        let capped = min(max(seconds, 0), 99 * 3600)
        let totalMinutes = Int((capped / 300).rounded()) * 5
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h == 0 && m == 0 { return "less than 5 minutes" }
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        return parts.joined(separator: " ")
    }
}
