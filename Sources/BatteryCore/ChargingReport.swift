import Foundation

public struct ChargingReport: Equatable, Sendable {
    public var chargeCount: Int                       // AC runs in the last 28 days
    public var typicalPlugInPercent: Int?             // median
    public var typicalUnplugPercent: Int?             // median
    public var averageDailyTimeAtFull: TimeInterval?  // over the last 7 days; nil if no AC data in them
    public var cyclesPerWeek: Double?                 // nil if the window spans less than 7 days
    public var usualChargerWatts: Int?                // mode of adapterWatts on AC

    public init(chargeCount: Int, typicalPlugInPercent: Int?, typicalUnplugPercent: Int?,
                averageDailyTimeAtFull: TimeInterval?, cyclesPerWeek: Double?, usualChargerWatts: Int?) {
        self.chargeCount = chargeCount
        self.typicalPlugInPercent = typicalPlugInPercent
        self.typicalUnplugPercent = typicalUnplugPercent
        self.averageDailyTimeAtFull = averageDailyTimeAtFull
        self.cyclesPerWeek = cyclesPerWeek
        self.usualChargerWatts = usualChargerWatts
    }

    private static let day: TimeInterval = 86_400

    public static func build(history: [BatteryReading], now: Date) -> ChargingReport {
        // The clock can be set back, so order by timestamp before pairing neighbours.
        let windowStart = now.addingTimeInterval(-28 * day)
        let sorted = history
            .filter { $0.timestamp >= windowStart }
            .sorted { $0.timestamp < $1.timestamp }

        let maxGap = UsageReport.maxPairGap
        func gap(_ a: BatteryReading, _ b: BatteryReading) -> TimeInterval {
            b.timestamp.timeIntervalSince(a.timestamp)
        }

        // AC runs: maximal stretches of AC readings with no gap over maxGap.
        var plugIns: [Int] = []
        var unplugs: [Int] = []
        var runCount = 0
        var i = 0
        while i < sorted.count {
            guard sorted[i].externalConnected else { i += 1; continue }
            var j = i
            while j + 1 < sorted.count, sorted[j + 1].externalConnected,
                  gap(sorted[j], sorted[j + 1]) <= maxGap {
                j += 1
            }
            runCount += 1

            if i > 0, !sorted[i - 1].externalConnected, gap(sorted[i - 1], sorted[i]) <= maxGap {
                plugIns.append(sorted[i - 1].percent)
            } else {
                plugIns.append(sorted[i].percent)
            }
            if j + 1 < sorted.count, !sorted[j + 1].externalConnected, gap(sorted[j], sorted[j + 1]) <= maxGap {
                unplugs.append(sorted[j].percent)
            }
            i = j + 1
        }

        // Time at full over the last 7 days, averaged per day.
        let weekStart = now.addingTimeInterval(-7 * day)
        var fullTime: TimeInterval = 0
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            guard a.timestamp >= weekStart, a.externalConnected, b.externalConnected,
                  a.percent >= 100, b.percent >= 100, gap(a, b) <= maxGap else { continue }
            fullTime += gap(a, b)
        }
        let hasRecentAC = sorted.contains { $0.timestamp >= weekStart && $0.externalConnected }

        // Cycles per week across the window, only once it spans a full week.
        var cycles: Double?
        if let first = sorted.first, let last = sorted.last {
            let spanDays = last.timestamp.timeIntervalSince(first.timestamp) / day
            if spanDays >= 7 {
                cycles = Double(last.cycleCount - first.cycleCount) / (spanDays / 7)
            }
        }

        // Most common adapter wattage; a tie goes to the higher wattage.
        var counts: [Int: Int] = [:]
        for r in sorted where r.externalConnected {
            if let w = r.adapterWatts { counts[w, default: 0] += 1 }
        }
        let charger = counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key

        return ChargingReport(
            chargeCount: runCount,
            typicalPlugInPercent: median(plugIns),
            typicalUnplugPercent: median(unplugs),
            averageDailyTimeAtFull: hasRecentAC ? fullTime / 7 : nil,
            cyclesPerWeek: cycles,
            usualChargerWatts: charger)
    }

    /// Median of the values; for an even count this is the lower middle element,
    /// so the result is always a value that actually occurred.
    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[(values.count - 1) / 2]
    }
}
