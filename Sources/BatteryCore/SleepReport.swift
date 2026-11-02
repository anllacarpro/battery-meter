import Foundation

public struct SleepPeriod: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var percentLost: Int
    public var darkWakes: Int

    public init(start: Date, end: Date, percentLost: Int, darkWakes: Int) {
        self.start = start
        self.end = end
        self.percentLost = percentLost
        self.darkWakes = darkWakes
    }
}

public struct WakeReasonCount: Equatable, Sendable {
    public var reason: WakeReason
    public var count: Int

    public init(reason: WakeReason, count: Int) {
        self.reason = reason
        self.count = count
    }
}

public struct SleepReport: Equatable, Sendable {
    public var periods: [SleepPeriod]            // newest first
    public var percentPerHour: Double?           // total lost / total hours
    public var wakeReasons: [WakeReasonCount]    // descending by count

    public init(periods: [SleepPeriod], percentPerHour: Double?, wakeReasons: [WakeReasonCount]) {
        self.periods = periods
        self.percentPerHour = percentPerHour
        self.wakeReasons = wakeReasons
    }

    private static let window: TimeInterval = 7 * 86_400
    private static let minimumDuration: TimeInterval = 1_800

    public static func build(events: [PowerEvent], now: Date) -> SleepReport {
        let windowStart = now.addingTimeInterval(-window)
        // Stable sort keeps log order for events with equal timestamps.
        let sorted = events.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)

        var periods: [SleepPeriod] = []
        var open: PowerEvent?        // the sleep that started the current period
        var allOnBattery = true
        var darkWakes = 0

        for e in sorted {
            switch e.kind {
            case .sleep:
                // Sleep -> DarkWake -> Sleep chains are one period: only the first
                // sleep after a wake opens it, and later sleeps just extend it.
                if open == nil {
                    open = e
                    allOnBattery = e.onBattery
                    darkWakes = 0
                } else {
                    allOnBattery = allOnBattery && e.onBattery
                }
            case .darkWake:
                guard open != nil else { continue }
                darkWakes += 1
                allOnBattery = allOnBattery && e.onBattery
            case .wake:
                guard let start = open else { continue }
                open = nil
                allOnBattery = allOnBattery && e.onBattery
                let duration = e.date.timeIntervalSince(start.date)
                if allOnBattery, duration >= minimumDuration, e.date >= windowStart {
                    periods.append(SleepPeriod(start: start.date, end: e.date,
                                               percentLost: max(start.charge - e.charge, 0),
                                               darkWakes: darkWakes))
                }
            }
        }

        let totalHours = periods.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
        let totalLost = periods.reduce(0) { $0 + $1.percentLost }
        let perHour: Double? = totalHours > 0 ? Double(totalLost) / totalHours : nil

        var counts: [WakeReason: Int] = [:]
        for e in sorted where e.kind != .sleep && e.date >= windowStart {
            counts[e.reason ?? .other, default: 0] += 1
        }
        // Ties fall back to the declaration order of WakeReason so the result is deterministic.
        let order = Dictionary(uniqueKeysWithValues: WakeReason.allCases.enumerated().map { ($1, $0) })
        let reasons = counts
            .map { WakeReasonCount(reason: $0.key, count: $0.value) }
            .sorted { ($0.count, order[$1.reason]!) > ($1.count, order[$0.reason]!) }

        return SleepReport(periods: periods.reversed(), percentPerHour: perHour, wakeReasons: reasons)
    }
}
