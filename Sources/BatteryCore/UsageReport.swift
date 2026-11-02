import Foundation

public struct UsagePeriod: Equatable, Sendable {
    public var start: Date                 // local start of the day or week
    public var batteryTime: TimeInterval
    public var percentUsed: Int
    public var averageWatts: Double?       // nil when batteryTime == 0

    public init(start: Date, batteryTime: TimeInterval, percentUsed: Int, averageWatts: Double?) {
        self.start = start
        self.batteryTime = batteryTime
        self.percentUsed = percentUsed
        self.averageWatts = averageWatts
    }
}

public struct UsageReport: Equatable, Sendable {
    public var days: [UsagePeriod]          // exactly 7, oldest first, today last; zero-filled
    public var weeks: [UsagePeriod]         // exactly 4, oldest first, this week last

    public init(days: [UsagePeriod], weeks: [UsagePeriod]) {
        self.days = days
        self.weeks = weeks
    }

    public var hasData: Bool {
        days.contains { $0.batteryTime > 0 } || weeks.contains { $0.batteryTime > 0 }
    }

    /// Longest gap between two readings that still counts as continuous battery time.
    static let maxPairGap: TimeInterval = 300

    private struct Accumulator {
        var time: TimeInterval = 0
        var percent = 0
        var wattSum = 0.0
        var count = 0
    }

    public static func build(history: [BatteryReading], now: Date, calendar: Calendar) -> UsageReport {
        let today = calendar.startOfDay(for: now)
        let dayStarts: [Date] = (-6...0).map { calendar.date(byAdding: .day, value: $0, to: today) ?? today }
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let weekStarts: [Date] = (-3...0).map { calendar.date(byAdding: .weekOfYear, value: $0, to: thisWeek) ?? thisWeek }

        var dayAcc = [Accumulator](repeating: Accumulator(), count: dayStarts.count)
        var weekAcc = [Accumulator](repeating: Accumulator(), count: weekStarts.count)

        let sorted = history.sorted { $0.timestamp < $1.timestamp }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            guard !a.externalConnected, !b.externalConnected else { continue }
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt <= maxPairGap else { continue }
            let drop = max(a.percent - b.percent, 0)
            // Attribution: the period containing a.timestamp.
            if let i = periodIndex(of: a.timestamp, starts: dayStarts, component: .day, calendar: calendar) {
                add(&dayAcc[i], dt, drop, a.powerWatts)
            }
            if let i = periodIndex(of: a.timestamp, starts: weekStarts, component: .weekOfYear, calendar: calendar) {
                add(&weekAcc[i], dt, drop, a.powerWatts)
            }
        }

        func period(_ start: Date, _ acc: Accumulator) -> UsagePeriod {
            UsagePeriod(start: start, batteryTime: acc.time, percentUsed: acc.percent,
                        averageWatts: acc.time > 0 && acc.count > 0 ? acc.wattSum / Double(acc.count) : nil)
        }
        return UsageReport(
            days: zip(dayStarts, dayAcc).map(period),
            weeks: zip(weekStarts, weekAcc).map(period))
    }

    private static func add(_ acc: inout Accumulator, _ dt: TimeInterval, _ drop: Int, _ watts: Double) {
        acc.time += dt
        acc.percent += drop
        acc.wattSum += watts
        acc.count += 1
    }

    private static func periodIndex(of date: Date, starts: [Date], component: Calendar.Component,
                                     calendar: Calendar) -> Int? {
        guard let i = starts.lastIndex(where: { $0 <= date }),
              let end = calendar.date(byAdding: component, value: 1, to: starts[i]), date < end
        else { return nil }
        return i
    }
}
