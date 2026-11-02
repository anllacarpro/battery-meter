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

    /// The store's day key for `date`: local `yyyy-MM-dd` in the calendar's time zone.
    /// Shared by the report and by whatever records into `AppEnergyStore`.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Each app's share of the total energy impact over today and the 6 days before it,
    /// top 8, descending. Ties sort by name for a deterministic result.
    public static func build(days: [String: [String: Double]], now: Date, calendar: Calendar) -> [AppShare] {
        var totals: [String: Double] = [:]
        for offset in 0..<dayCount {
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now),
                  let apps = days[dayKey(for: d, calendar: calendar)] else { continue }
            for (name, value) in apps { totals[name, default: 0] += value }
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
