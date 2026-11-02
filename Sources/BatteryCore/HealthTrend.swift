import Foundation

public enum HealthTrend: Equatable, Sendable {
    case notEnoughData(daysCollected: Int)
    case steady(currentPercent: Double)
    case declining(currentPercent: Double, lossPerMonth: Double, reaches80: Date?)  // nil if > 10 years out

    private static let day: TimeInterval = 86_400
    private static let minPoints = 14
    private static let minSpanDays = 14.0
    /// Percent per day; a slope shallower than this reads as noise, not wear.
    private static let steadySlope = -0.001
    private static let maxProjectionDays = 3_650.0

    public static func build(points: [HealthPoint]) -> HealthTrend {
        let sorted = points.sorted { $0.day < $1.day }
        guard sorted.count >= minPoints, let first = sorted.first, let last = sorted.last,
              last.day.timeIntervalSince(first.day) / day >= minSpanDays else {
            return .notEnoughData(daysCollected: points.count)
        }

        // Least squares of percent against days since the first point.
        let xs = sorted.map { $0.day.timeIntervalSince(first.day) / day }
        let ys = sorted.map(\.percent)
        let n = Double(sorted.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        let current = meanY + slope * ((xs.last ?? 0) - meanX)

        guard slope < steadySlope else { return .steady(currentPercent: current) }

        var reaches80: Date?
        if current > 80 {
            let daysOut = (current - 80) / -slope
            if daysOut <= maxProjectionDays {
                reaches80 = last.day.addingTimeInterval(daysOut * day)
            }
        }
        return .declining(currentPercent: current, lossPerMonth: -slope * 30, reaches80: reaches80)
    }
}
