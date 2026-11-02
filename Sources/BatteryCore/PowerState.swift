import Foundation

public enum PowerState: Equatable, Sendable {
    case onBattery(timeLeft: TimeInterval?)
    case charging(timeToFull: TimeInterval?)
    case pluggedIn
}

/// Turns raw readings into a steady `PowerState` plus smoothed live-tile values.
public struct PowerEstimator: Sendable {
    private static let minDrawWatts = 0.5
    private static let maxTimeLeft: TimeInterval = 99 * 3600
    /// Below this smoothed charge current the time to full is too uncertain to show.
    private static let minChargeMilliamps = 100.0
    /// From here up the charge current tapers, so the current-based estimate runs short.
    private static let taperPercent = 80

    private var recentSmoother = EMASmoother(halfLife: 1800)
    private var chargeSmoother = EMASmoother(halfLife: 300)
    private var wattsSmoother = EMASmoother(halfLife: 30)
    private var voltsSmoother = EMASmoother(halfLife: 30)
    private var ampsSmoother = EMASmoother(halfLife: 30)
    private var lastExternal: Bool?
    private var lastRemainingWh: Double?
    private var lastTypicalWatts: Double?

    public init() {}

    public mutating func update(with reading: BatteryReading, typicalWatts: Double? = nil) -> PowerState {
        // Plug/unplug changes the current's meaning; never carry it across.
        if let last = lastExternal, last != reading.externalConnected {
            recentSmoother.reset()
            chargeSmoother.reset()
            wattsSmoother.reset()
            voltsSmoother.reset()
            ampsSmoother.reset()
        }
        lastExternal = reading.externalConnected
        lastRemainingWh = reading.remainingWattHours
        lastTypicalWatts = typicalWatts

        let t = reading.timestamp
        recentSmoother.add(reading.powerWatts, at: t)
        wattsSmoother.add(reading.powerWatts, at: t)
        voltsSmoother.add(Double(reading.voltage) / 1000, at: t)
        ampsSmoother.add(Double(reading.amperage) / 1000, at: t)

        if !reading.externalConnected {
            return .onBattery(timeLeft: runtime?.headline)
        }
        if reading.isCharging {
            chargeSmoother.add(Double(max(reading.amperage, 0)), at: t)
            return .charging(timeToFull: timeToFull(reading))
        }
        // A pause in charging (e.g. held at a limit) must not carry its current into the next one.
        chargeSmoother.reset()
        return .pluggedIn
    }

    /// Missing charge over the smoothed charge current. macOS's own estimate swings wildly
    /// while the current ramps up, so it's only consulted near the top, where the current
    /// tapers and the current-based estimate runs short.
    private func timeToFull(_ reading: BatteryReading) -> TimeInterval? {
        guard let mA = chargeSmoother.value, mA >= Self.minChargeMilliamps else { return nil }
        let missing = Double(max(reading.fullChargeCapacity - reading.remainingCapacity, 0))
        var seconds = missing / mA * 3600
        if reading.percent >= Self.taperPercent, let os = reading.osMinutesToFull {
            seconds = max(seconds, TimeInterval(os) * 60)
        }
        return min(seconds, Self.maxTimeLeft)
    }

    /// Time left on battery; nil while on AC or before the first reading.
    public var runtime: RuntimeEstimate? {
        guard lastExternal == false, let wh = lastRemainingWh else { return nil }
        let blended = recentWatts.map { recent in lastTypicalWatts.map { 0.5 * $0 + 0.5 * recent } ?? recent }
        let pace = liveWatts
        let isHighUse = pace.flatMap { p in lastTypicalWatts.map { p >= 10 && p >= 2 * $0 } } ?? false
        return RuntimeEstimate(
            headline: timeLeft(wattHours: wh, watts: blended),
            atPace: timeLeft(wattHours: wh, watts: pace),
            paceWatts: pace, typicalWatts: lastTypicalWatts,
            isEstimate: lastTypicalWatts == nil, isHighUse: isHighUse)
    }

    private func timeLeft(wattHours: Double, watts: Double?) -> TimeInterval? {
        guard let watts, watts >= Self.minDrawWatts else { return nil }
        return min(wattHours / watts * 3600, Self.maxTimeLeft)
    }

    /// 30-minute smoothed power magnitude in watts.
    public var recentWatts: Double? { recentSmoother.value }
    /// Smoothed power magnitude in watts.
    public var liveWatts: Double? { wattsSmoother.value }
    /// Smoothed voltage in volts.
    public var liveVolts: Double? { voltsSmoother.value }
    /// Smoothed current in amps, signed as reported (negative = discharging).
    public var liveAmps: Double? { ampsSmoother.value }
}
