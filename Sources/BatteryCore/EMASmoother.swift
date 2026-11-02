import Foundation

/// Time-weighted exponential moving average with a warm-up.
/// The value is the exponentially weighted mean of the samples seen so far: each sample is
/// weighted by the seconds it covers, and older weight decays by `0.5^(dt / halfLife)`.
/// Until the window has filled this is a plain interval-weighted mean, so one early spike
/// cannot keep half its weight for a whole half-life; once filled it equals the classic EMA.
/// A gap longer than `maxGap` (e.g. sleep/wake) discards history so stale values never leak
/// into new estimates. The first sample after a reset or gap counts as 1 second.
public struct EMASmoother: Sendable {
    public static let maxGap: TimeInterval = 300

    private let halfLife: TimeInterval
    private var lastDate: Date?
    private var weightedSum = 0.0
    private var weight = 0.0

    public var value: Double? { weight > 0 ? weightedSum / weight : nil }

    public init(halfLife: TimeInterval) {
        self.halfLife = halfLife
    }

    public mutating func add(_ value: Double, at date: Date) {
        guard let last = lastDate, weight > 0 else {
            seed(value)
            lastDate = date
            return
        }
        let dt = date.timeIntervalSince(last)
        if dt > Self.maxGap {
            seed(value)
        } else if dt > 0 {
            let decay = pow(0.5, dt / halfLife)
            weightedSum = weightedSum * decay + value * dt
            weight = weight * decay + dt
        }
        // dt <= 0 (duplicate/out-of-order timestamp): keep value, still advance clock below.
        lastDate = date
    }

    public mutating func reset() {
        weightedSum = 0
        weight = 0
        lastDate = nil
    }

    private mutating func seed(_ value: Double) {
        weightedSum = value
        weight = 1
    }
}
