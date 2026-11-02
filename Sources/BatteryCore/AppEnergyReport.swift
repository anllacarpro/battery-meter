import Foundation

public struct AppShare: Equatable, Sendable {
    public var name: String
    public var share: Double   // 0...1

    public init(name: String, share: Double) {
        self.name = name
        self.share = share
    }
}

public enum AppEnergyReport {
    private static let dayCount = 7
    private static let maxApps = 8

    /// The single definition of the day-key format: Gregorian `yyyy-MM-dd` (en_US_POSIX) in
    /// `timeZone`, regardless of the user's calendar (Buddhist, Japanese...), so keys always
    /// sort lexicographically as dates.
    static func makeDayFormatter(timeZone: TimeZone) -> DateFormatter {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = gregorian
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// The store's day key for `date`: `yyyy-MM-dd` in the calendar's time zone (always
    /// Gregorian). Shared by the report and by whatever records into `AppEnergyStore`.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        makeDayFormatter(timeZone: calendar.timeZone).string(from: date)
    }

    /// The name as shown: drops invisible format and control characters (the U+200E mark
    /// and U+2066–2069 isolates some apps carry in their localized name) and trims
    /// whitespace. Applied before storing and again when reporting, so names stored before
    /// this cleanup merge with their clean form.
    public static func cleanName(_ name: String) -> String {
        let kept = name.unicodeScalars.filter {
            switch $0.properties.generalCategory {
            case .format, .control: false
            default: true
            }
        }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Each app's share of the total energy impact over today and the 6 days before it,
    /// top 8, descending. Ties sort by name for a deterministic result.
    public static func build(days: [String: [String: Double]], now: Date, calendar: Calendar) -> [AppShare] {
        var totals: [String: Double] = [:]
        for offset in 0..<dayCount {
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now),
                  let apps = days[dayKey(for: d, calendar: calendar)] else { continue }
            for (name, value) in apps {
                let clean = cleanName(name)
                if !clean.isEmpty { totals[clean, default: 0] += value }
            }
        }
        totals = totals.filter { $0.value > 0 }
        let grand = totals.values.reduce(0, +)
        guard grand > 0 else { return [] }
        return totals
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(maxApps)
            .map { AppShare(name: $0.key, share: $0.value / grand) }
    }
}
