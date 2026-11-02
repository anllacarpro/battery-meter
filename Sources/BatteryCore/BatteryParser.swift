import Foundation

public enum BatteryParser {
    /// Sentinel the SMC reports when a time estimate is unavailable.
    private static let unknownMinutes = 65535

    /// The timestamp is truncated to whole seconds: the history file stores ISO 8601 dates
    /// without fractions, so a reading in memory and its stored copy compare equal.
    public static func parse(_ raw: [String: Any], at date: Date) -> BatteryReading? {
        guard
            let battery = raw["BatteryData"] as? [String: Any],
            let design = int(battery["DesignCapacity"]), design > 0,
            let full = int(battery["FullChargeCapacity"]),
            let remaining = int(battery["RemainingCapacity"]),
            let percent = int(raw["CurrentCapacity"]),
            let voltage = int(raw["Voltage"]),
            let amperage = int(raw["Amperage"]),
            let cycles = int(raw["CycleCount"]),
            let isCharging = bool(raw["IsCharging"]),
            let external = bool(raw["ExternalConnected"]),
            let fullyCharged = bool(raw["FullyCharged"])
        else { return nil }

        let adapter = raw["AdapterDetails"] as? [String: Any]
        let charger = raw["ChargerData"] as? [String: Any]

        return BatteryReading(
            timestamp: Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)),
            percent: percent,
            remainingCapacity: remaining,
            fullChargeCapacity: full,
            designCapacity: design,
            cycleCount: cycles,
            designCycleCount: int(raw["DesignCycleCount9C"]),
            voltage: voltage,
            amperage: amperage,
            isCharging: isCharging,
            externalConnected: external,
            fullyCharged: fullyCharged,
            adapterWatts: int(adapter?["Watts"]),
            notChargingReason: int(charger?["NotChargingReason"]),
            osMinutesToEmpty: minutes(raw["AvgTimeToEmpty"]),
            osMinutesToFull: minutes(raw["AvgTimeToFull"])
        )
    }

    /// `int64Value` wraps unsigned bit patterns (e.g. 18446744073709551254) to signed (-362).
    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber).map { Int($0.int64Value) }
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private static func minutes(_ value: Any?) -> Int? {
        guard let m = int(value), m != unknownMinutes else { return nil }
        return m
    }
}
