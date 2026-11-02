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

    private var drawSmoother = EMASmoother(halfLife: 300)
    private var chargeSmoother = EMASmoother(halfLife: 300)
    private var wattsSmoother = EMASmoother(halfLife: 30)
    private var voltsSmoother = EMASmoother(halfLife: 30)
    private var ampsSmoother = EMASmoother(halfLife: 30)
    private var lastExternal: Bool?

    public init() {}

    public mutating func update(with reading: BatteryReading) -> PowerState {
        // Plug/unplug changes the current's meaning; never carry it across.
        if let last = lastExternal, last != reading.externalConnected {
            drawSmoother.reset()
            chargeSmoother.reset()
            wattsSmoother.reset()
            voltsSmoother.reset()
            ampsSmoother.reset()
        }
        lastExternal = reading.externalConnected

        let t = reading.timestamp
        drawSmoother.add(reading.powerWatts, at: t)
        wattsSmoother.add(reading.powerWatts, at: t)
        voltsSmoother.add(Double(reading.voltage) / 1000, at: t)
        ampsSmoother.add(Double(reading.amperage) / 1000, at: t)

        if !reading.externalConnected {
            guard let watts = drawSmoother.value, watts >= Self.minDrawWatts else {
                return .onBattery(timeLeft: nil)
            }
            let seconds = reading.remainingWattHours / watts * 3600
            return .onBattery(timeLeft: min(seconds, Self.maxTimeLeft))
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

    /// Smoothed power magnitude in watts.
    public var liveWatts: Double? { wattsSmoother.value }
    /// Smoothed voltage in volts.
    public var liveVolts: Double? { voltsSmoother.value }
    /// Smoothed current in amps, signed as reported (negative = discharging).
    public var liveAmps: Double? { ampsSmoother.value }
}
