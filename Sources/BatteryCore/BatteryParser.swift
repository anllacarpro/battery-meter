import Foundation

public enum BatteryParser {
    /// Sentinel the SMC reports when a time estimate is unavailable.
    private static let unknownMinutes = 65535

    public static func parse(_ raw: [String: Any], at date: Date) -> BatteryReading? {
        guard
            let battery = raw["BatteryData"] as? [String: Any],
            let design = int(battery["DesignCapacity"]), design > 0,
            let full = int(battery["FullChargeCapacity"]),
            let remaining = int(battery["RemainingCapacity"]),
            let percent = int(raw["CurrentCapacity"]),
            let voltage = int(raw["Voltage"]),
            let amperage = int(raw["Amperage"])
        else { return nil }

        let adapter = raw["AdapterDetails"] as? [String: Any]
        let charger = raw["ChargerData"] as? [String: Any]

        return BatteryReading(
            timestamp: date,
            percent: percent,
            remainingCapacity: remaining,
            fullChargeCapacity: full,
            designCapacity: design,
            cycleCount: int(raw["CycleCount"]) ?? 0,
            designCycleCount: int(raw["DesignCycleCount9C"]),
            voltage: voltage,
            amperage: amperage,
            isCharging: bool(raw["IsCharging"]),
            externalConnected: bool(raw["ExternalConnected"]),
            fullyCharged: bool(raw["FullyCharged"]),
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

    private static func bool(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private static func minutes(_ value: Any?) -> Int? {
        guard let m = int(value), m != unknownMinutes else { return nil }
        return m
    }
}
