import Foundation

public struct BatteryReading: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var percent: Int                 // CurrentCapacity, 0–100
    public var remainingCapacity: Int       // mAh
    public var fullChargeCapacity: Int      // mAh
    public var designCapacity: Int          // mAh
    public var cycleCount: Int
    public var designCycleCount: Int?
    public var voltage: Int                 // mV
    public var amperage: Int                // mA, signed; negative = discharging
    public var isCharging: Bool
    public var externalConnected: Bool
    public var fullyCharged: Bool
    public var adapterWatts: Int?
    public var notChargingReason: Int?
    public var osMinutesToEmpty: Int?
    public var osMinutesToFull: Int?
    public var nominalChargeCapacity: Int?  // mAh, macOS Maximum Capacity basis

    public init(
        timestamp: Date, percent: Int, remainingCapacity: Int, fullChargeCapacity: Int,
        designCapacity: Int, cycleCount: Int, designCycleCount: Int? = nil,
        voltage: Int, amperage: Int, isCharging: Bool, externalConnected: Bool,
        fullyCharged: Bool, adapterWatts: Int? = nil, notChargingReason: Int? = nil,
        osMinutesToEmpty: Int? = nil, osMinutesToFull: Int? = nil,
        nominalChargeCapacity: Int? = nil
    ) {
        self.timestamp = timestamp
        self.percent = percent
        self.remainingCapacity = remainingCapacity
        self.fullChargeCapacity = fullChargeCapacity
        self.designCapacity = designCapacity
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.voltage = voltage
        self.amperage = amperage
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.fullyCharged = fullyCharged
        self.adapterWatts = adapterWatts
        self.notChargingReason = notChargingReason
        self.osMinutesToEmpty = osMinutesToEmpty
        self.osMinutesToFull = osMinutesToFull
        self.nominalChargeCapacity = nominalChargeCapacity
    }

    /// nominalChargeCapacity (falling back to fullChargeCapacity) / designCapacity * 100, capped
    /// at 100: a new cell can measure slightly above its design capacity, which isn't
    /// "better than new" (macOS caps it too).
    public var healthPercent: Double {
        guard designCapacity > 0 else { return 0 }
        let basis = (nominalChargeCapacity ?? 0) > 0 ? nominalChargeCapacity! : fullChargeCapacity
        return min(Double(basis) / Double(designCapacity) * 100, 100)
    }

    /// |voltage * amperage| / 1_000_000
    public var powerWatts: Double {
        abs(Double(voltage) * Double(amperage)) / 1_000_000
    }

    public var remainingWattHours: Double {
        Double(remainingCapacity) * Double(voltage) / 1_000_000
    }

    public var fullWattHours: Double {
        Double(fullChargeCapacity) * Double(voltage) / 1_000_000
    }
}
