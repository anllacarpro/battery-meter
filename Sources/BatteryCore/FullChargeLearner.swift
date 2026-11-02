import Foundation

public struct FullChargeEstimate: Equatable, Sendable {
    public var hours: Double
    public var isEstimate: Bool

    public init(hours: Double, isEstimate: Bool) {
        self.hours = hours
        self.isEstimate = isEstimate
    }
}

public struct DischargeSession: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var percentDrop: Int
    public var hoursPerFullCharge: Double

    public init(start: Date, end: Date, percentDrop: Int, hoursPerFullCharge: Double) {
        self.start = start
        self.end = end
        self.percentDrop = percentDrop
        self.hoursPerFullCharge = hoursPerFullCharge
    }
}

public enum FullChargeLearner {
    static let maxGap: TimeInterval = 300
    static let minPercentDrop = 10
    static let minDuration: TimeInterval = 20 * 60
    static let maxSessions = 10
    static let decay = 0.7

    /// Kept discharge sessions in chronological order.
    public static func sessions(in history: [BatteryReading]) -> [DischargeSession] {
        let readings = history.sorted { $0.timestamp < $1.timestamp }
        var result: [DischargeSession] = []
        var run: [BatteryReading] = []

        func flush() {
            defer { run.removeAll(keepingCapacity: true) }
            guard let first = run.first, let last = run.last else { return }
            let drop = first.percent - last.percent
            let duration = last.timestamp.timeIntervalSince(first.timestamp)
            guard drop >= minPercentDrop, duration >= minDuration else { return }
            result.append(DischargeSession(
                start: first.timestamp, end: last.timestamp, percentDrop: drop,
                hoursPerFullCharge: (duration / 3600) / (Double(drop) / 100)))
        }

        for reading in readings {
            if reading.externalConnected {
                flush()
            } else {
                if let prev = run.last,
                   reading.timestamp.timeIntervalSince(prev.timestamp) > maxGap {
                    flush()
                }
                run.append(reading)
            }
        }
        flush()
        return result
    }

    /// Learned sessions win; with none, full capacity over `fallbackWatts` (an estimate).
    public static func estimate(
        history: [BatteryReading], current: BatteryReading?, fallbackWatts: Double?
    ) -> FullChargeEstimate? {
        let recent = sessions(in: history).suffix(maxSessions).reversed()  // newest first
        if !recent.isEmpty {
            var weighted = 0.0
            var totalWeight = 0.0
            for (i, session) in recent.enumerated() {
                let w = pow(decay, Double(i))
                weighted += w * session.hoursPerFullCharge
                totalWeight += w
            }
            return FullChargeEstimate(hours: weighted / totalWeight, isEstimate: false)
        }
        guard let current, let fallbackWatts, fallbackWatts > 0, current.fullWattHours > 0 else { return nil }
        return FullChargeEstimate(hours: current.fullWattHours / fallbackWatts, isEstimate: true)
    }
}
