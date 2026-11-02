import Foundation

/// Time-weighted exponential moving average.
/// `alpha = 1 - 0.5^(dt / halfLife)`. A gap longer than `maxGap` (e.g. sleep/wake)
/// discards history so stale values never leak into new estimates.
public struct EMASmoother: Sendable {
    public static let maxGap: TimeInterval = 300

    private let halfLife: TimeInterval
    private var lastDate: Date?
    public private(set) var value: Double?

    public init(halfLife: TimeInterval) {
        self.halfLife = halfLife
    }

    public mutating func add(_ value: Double, at date: Date) {
        guard let current = self.value, let last = lastDate else {
            self.value = value
            lastDate = date
            return
        }
        let dt = date.timeIntervalSince(last)
        if dt > Self.maxGap {
            self.value = value
        } else if dt > 0 {
            let alpha = 1 - pow(0.5, dt / halfLife)
            self.value = current + alpha * (value - current)
        }
        // dt <= 0 (duplicate/out-of-order timestamp): keep value, still advance clock below.
        lastDate = date
    }

    public mutating func reset() {
        value = nil
        lastDate = nil
    }
}
