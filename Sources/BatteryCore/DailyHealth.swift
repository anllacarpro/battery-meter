import Foundation

public struct HealthPoint: Identifiable, Equatable, Sendable {
    public let day: Date
    public let percent: Double
    public var id: Date { day }

    public init(day: Date, percent: Double) {
        self.day = day
        self.percent = percent
    }
}

public enum DailyHealth {
    /// Daily mean of `healthPercent`. Buckets by local day with one UTC offset, which
    /// avoids a Calendar call per reading (history holds ~260k of them). Once any reading
    /// carries a nominal capacity, readings without one are skipped: their health comes from
    /// full charge capacity, which runs lower and would make the trend jump upward.
    public static func points(in history: [BatteryReading]) -> [HealthPoint] {
        let offset = TimeInterval(TimeZone.current.secondsFromGMT())
        let hasNominal = history.contains { ($0.nominalChargeCapacity ?? 0) > 0 }
        var sums: [Int: (total: Double, count: Int)] = [:]
        for reading in history where reading.designCapacity > 0 {
            if hasNominal, (reading.nominalChargeCapacity ?? 0) <= 0 { continue }
            let day = Int(((reading.timestamp.timeIntervalSince1970 + offset) / 86_400).rounded(.down))
            sums[day, default: (0, 0)].total += reading.healthPercent
            sums[day, default: (0, 0)].count += 1
        }
        return sums.keys.sorted().map { day in
            let s = sums[day]!
            // Plot at local noon so the point sits in the middle of its day.
            let noon = Date(timeIntervalSince1970: TimeInterval(day) * 86_400 - offset + 43_200)
            return HealthPoint(day: noon, percent: s.total / Double(s.count))
        }
    }
}
