import Foundation

public enum DurationText {
    /// Rounds to the nearest 5 minutes, capped at 99h: "6h 40m", "45m", "0m".
    public static func short(_ seconds: TimeInterval) -> String {
        let capped = min(max(seconds, 0), 99 * 3600)
        let totalMinutes = Int((capped / 300).rounded()) * 5
        let h = totalMinutes / 60, m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Same rounding as `short`, as clock time: "6:30", "0:45".
    public static func clock(_ seconds: TimeInterval) -> String {
        let capped = min(max(seconds, 0), 99 * 3600)
        let totalMinutes = Int((capped / 300).rounded()) * 5
        let m = totalMinutes % 60
        return "\(totalMinutes / 60):\(m < 10 ? "0" : "")\(m)"
    }
}
