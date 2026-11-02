import Foundation

/// The Health trend section's sentence. Pure, so every case of the copy can be tested.
public enum HealthTrendCopy {
    /// Apple's service threshold for battery health.
    static let threshold = 80.0

    /// The sentence for `trend`, or `nil` while there isn't enough data for one (the
    /// section shows its empty state instead).
    public static func sentence(for trend: HealthTrend, calendar: Calendar,
                                locale: Locale = .current) -> String? {
        switch trend {
        case .notEnoughData:
            return nil
        case .steady(let current):
            return "Health is steady at \(percent(current, locale: locale))."
        case .declining(let current, let loss, let reaches80):
            // One decimal; a real but tiny slope would otherwise read "Losing 0.0%".
            let rate = loss < 0.05 ? "under 0.1%" : percent(loss, locale: locale)
            let projection: String
            if current <= threshold {
                // The core gives no date here: the threshold is already behind us.
                projection = "Below 80%, Apple's service threshold."
            } else if let reaches80 {
                let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                    .month(.wide).year()
                projection = "Reaches 80% around \(reaches80.formatted(style))."
            } else {
                projection = "Won't reach 80% in the next 10 years."
            }
            return "Losing \(rate) a month. \(projection)"
        }
    }

    private static func percent(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%"
    }
}
