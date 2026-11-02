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

    private var drawSmoother = EMASmoother(halfLife: 300)
    private var wattsSmoother = EMASmoother(halfLife: 30)
    private var voltsSmoother = EMASmoother(halfLife: 30)
    private var ampsSmoother = EMASmoother(halfLife: 30)
    private var lastExternal: Bool?

    public init() {}

    public mutating func update(with reading: BatteryReading) -> PowerState {
        // Plug/unplug changes the current's meaning; never carry it across.
        if let last = lastExternal, last != reading.externalConnected {
            drawSmoother.reset()
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
            return .charging(timeToFull: reading.osMinutesToFull.map { TimeInterval($0) * 60 })
        }
        return .pluggedIn
    }

    /// Smoothed power magnitude in watts.
    public var liveWatts: Double? { wattsSmoother.value }
    /// Smoothed voltage in volts.
    public var liveVolts: Double? { voltsSmoother.value }
    /// Smoothed current in amps, signed as reported (negative = discharging).
    public var liveAmps: Double? { ampsSmoother.value }
}
