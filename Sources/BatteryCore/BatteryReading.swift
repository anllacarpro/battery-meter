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

    public init(
        timestamp: Date, percent: Int, remainingCapacity: Int, fullChargeCapacity: Int,
        designCapacity: Int, cycleCount: Int, designCycleCount: Int? = nil,
        voltage: Int, amperage: Int, isCharging: Bool, externalConnected: Bool,
        fullyCharged: Bool, adapterWatts: Int? = nil, notChargingReason: Int? = nil,
        osMinutesToEmpty: Int? = nil, osMinutesToFull: Int? = nil
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
    }

    /// fullChargeCapacity / designCapacity * 100
    public var healthPercent: Double {
        designCapacity > 0 ? Double(fullChargeCapacity) / Double(designCapacity) * 100 : 0
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
